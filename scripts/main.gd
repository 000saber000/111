extends Node3D

## M3：打磨与验收。
## 种 → 等 10 分钟 → 收 → 卖 45 → 买种子 20；离线按时间戳结算，封顶 8 小时。
##
## M3 加的东西：
## - 收获反馈：作物弹一下再缩没、金币小圆点飞向 HUD、+45 跳字、金币数弹一下、轻微镜头震动
## - 音效：种植 / 收获 / 金币（assets/audio/*.wav，tools/audio/generate_sfx.py 生成）
## - 横屏 HUD：金币数醒目、地块状态、情境提示条，每块生长中的地有一条进度条
## - 回到游戏时告诉玩家「离线多久、几块熟了」
## 规则判定全部走 FarmLogic（纯函数，可无头测试）。

const STATE_EMPTY := FarmLogic.STATE_EMPTY
const STATE_GROWING := FarmLogic.STATE_GROWING
const STATE_MATURE := FarmLogic.STATE_MATURE

const PLOT_SIZE := 1.7
const PLOT_HEIGHT := 0.28
const SPACING_X := 2.0
const SPACING_Z := 2.1

const CAMERA_POS := Vector3(0.0, 8.6, 6.2)

const COIN_GOLD := Color(1.0, 0.78, 0.25)
const TEXT_LIGHT := Color(0.94, 0.96, 0.92)
const TEXT_MUTED := Color(0.78, 0.84, 0.78)

const BAR_WIDTH := 1.25
const BAR_HEIGHT := 0.16
const BAR_Y := 1.15
const BAR_GROW := Color(0.55, 0.90, 0.40)

const SFX_VOL_PLANT := -4.0
const SFX_VOL_HARVEST := -2.0
const SFX_VOL_COIN := -3.0
const SFX_VOL_MATURE := -12.0
const SFX_VOL_GREET := -8.0
const SFX_VOL_TICK := -18.0

const PLOT_SCENE := preload("res://assets/models/plot_block.glb")
const CROP_SEED := preload("res://assets/models/crop_seed.glb")
const CROP_SPROUT := preload("res://assets/models/crop_sprout.glb")
const CROP_MATURE := preload("res://assets/models/crop_mature.glb")
const COIN_SCENE := preload("res://assets/models/coin.glb")
const GROUND_SCENE := preload("res://assets/models/ground.glb")
const FENCE_SCENE := preload("res://assets/models/fence.glb")
const WINDMILL_SCENE := preload("res://assets/models/windmill.glb")

const SFX_NAMES := ["plant", "harvest", "coin"]
const SFX_VOICES := 2

var _camera: Camera3D
var _hud: CanvasLayer
var _coin_value: Label
var _status: Label
var _hint: Label
var _fx_layer: Control
var _plots: Array[Dictionary] = []      # 每块地的节点与基准变换
var _data: Dictionary = {}
var _tick_accum := 0.0
var _ui_accum := 0.0
var _message := ""
var _message_until := 0
var _anim_plots := {}                  # 下标 -> true，动效期间别让 _refresh_plots 抢画面
var _offline_elapsed := 0
var _offline_matured := 0
var _white_tex: ImageTexture
var _sfx := {}                         # 名字 -> Array[AudioStreamPlayer]
var _sfx_cursor := {}

# 无人值守验收参数（桌面截图用；不影响正常玩）
var _shot_path := ""
var _shot_frame := 5
var _tap_pos := Vector2(-1, -1)
var _force_mature := false
var _demo := ""
var _fresh := false
var _mute := false
var _persist := true
var _frames := 0


func _ready() -> void:
	_parse_cmdline()
	if _mute:
		AudioServer.set_bus_mute(0, true)

	_white_tex = _make_white_texture()
	_data = SaveManager.default_data() if _fresh else SaveManager.load_data()
	if _force_mature:
		for plot in _data.get("plots", []):
			if FarmLogic.state_of(plot) == STATE_GROWING:
				plot["planted_at"] = _now() - Balance.MATURE_SECONDS
	_apply_offline()

	_build_environment()
	_build_ground()
	_build_plots()
	_build_decor()
	_build_audio()
	_build_hud()
	_refresh_plots()
	_update_hud()
	_update_progress_bars()

	var autosave := Timer.new()
	autosave.wait_time = 10.0
	autosave.autostart = true
	autosave.timeout.connect(_save)
	add_child(autosave)

	_greet_after_offline()
	_save()

	if _demo != "":
		_run_demo()


func _parse_cmdline() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--shot-frame="):
			_shot_frame = int(arg.trim_prefix("--shot-frame="))
		elif arg.begins_with("--tap="):
			var parts := arg.trim_prefix("--tap=").split(",")
			if parts.size() == 2:
				_tap_pos = Vector2(float(parts[0]), float(parts[1]))
		elif arg == "--mature":
			_force_mature = true
		elif arg.begins_with("--demo="):
			_demo = arg.trim_prefix("--demo=")
		elif arg == "--fresh":
			_fresh = true
		elif arg == "--mute":
			_mute = true
	if _shot_path != "" or _fresh:
		# 截图/演示不该改玩家存档。
		_persist = false


func _process(delta: float) -> void:
	_tick_accum += delta
	if _tick_accum >= 1.0:
		_tick_accum = 0.0
		_tick_growth()

	_ui_accum += delta
	if _ui_accum >= 0.2:
		_ui_accum = 0.0
		_update_progress_bars()

	_animate_plots(delta)

	_frames_tick()


func _frames_tick() -> void:
	_frames += 1
	if _frames == 2 and _tap_pos.x >= 0.0:
		_try_select(_tap_pos)
	if _shot_path != "" and _frames == _shot_frame:
		_capture_and_quit()


func _capture_and_quit() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shot_path)
	print("SHOT_SAVED ", _shot_path)
	get_tree().quit()


func _notification(what: int) -> void:
	## 切后台/被杀之前存一次，离线结算才准。
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()


func _exit_tree() -> void:
	_save()


func _save() -> void:
	if not _persist or _data.is_empty():
		return
	SaveManager.save_data(_data)


# ---------- 存档与时间 ----------

func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _apply_offline() -> void:
	var now := _now()
	var last := int(_data.get("last_seen_at", now))
	var result := FarmLogic.apply_offline(_data.get("plots", []), now, last)
	_offline_elapsed = int(result["elapsed_seconds"])
	_offline_matured = (result["matured"] as Array).size()


func _greet_after_offline() -> void:
	if _offline_elapsed < 60:
		return
	var minutes := _offline_elapsed / 60
	if _offline_matured > 0:
		_flash("离线 %d 分钟 · 回来啦，%d 块熟了" % [minutes, _offline_matured], 4.5)
		_play_delayed("coin", 0.35, SFX_VOL_GREET)
	else:
		_flash("离线 %d 分钟" % minutes, 3.0)


func _tick_growth() -> void:
	var matured := FarmLogic.tick_growth(_data.get("plots", []), _now())
	if not matured.is_empty():
		_refresh_plots()
		_save()
		_flash("有 %d 块作物熟了！" % matured.size(), 3.0)
		_play("coin", SFX_VOL_MATURE, 1.18)
	_update_hud()


# ---------- 场景 ----------

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.80, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.55
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.position = CAMERA_POS
	_camera.rotation_degrees = Vector3(-54.0, 0.0, 0.0)
	_camera.fov = 44.0
	_camera.current = true
	add_child(_camera)


func _build_ground() -> void:
	var ground := GROUND_SCENE.instantiate()
	ground.name = "Ground"
	add_child(ground)


func _build_decor() -> void:
	var fence := FENCE_SCENE.instantiate()
	fence.name = "Fence"
	add_child(fence)

	var windmill := WINDMILL_SCENE.instantiate()
	windmill.name = "Windmill"
	windmill.position = Vector3(3.85, 0.0, -2.55)
	windmill.scale = Vector3(0.42, 0.42, 0.42)
	windmill.rotation_degrees = Vector3(0, 180, 0)
	add_child(windmill)


func _build_plots() -> void:
	for row in Balance.PLOT_ROWS:
		for col in Balance.PLOT_COLS:
			var index := row * Balance.PLOT_COLS + col
			var x := (col - (Balance.PLOT_COLS - 1) * 0.5) * SPACING_X
			var z := (row - (Balance.PLOT_ROWS - 1) * 0.5) * SPACING_Z

			var plot := PLOT_SCENE.instantiate()
			plot.name = "Plot%d" % index
			plot.position = Vector3(x, 0.0, z)
			add_child(plot)

			var crops := Node3D.new()
			crops.name = "Crops%d" % index
			crops.position = Vector3(x, PLOT_HEIGHT, z)
			add_child(crops)

			var seed_node := CROP_SEED.instantiate()
			var sprout_node := CROP_SPROUT.instantiate()
			var mature_node := CROP_MATURE.instantiate()
			crops.add_child(seed_node)
			crops.add_child(sprout_node)
			crops.add_child(mature_node)

			var coin := COIN_SCENE.instantiate()
			coin.name = "Coin%d" % index
			coin.position = Vector3(x, PLOT_HEIGHT + BAR_Y, z)
			coin.visible = false
			add_child(coin)

			# 空地提示：一个若隐若现的「+」，比只靠底部提示更容易看出哪块是空的。
			var marker := Label3D.new()
			marker.name = "EmptyMark%d" % index
			marker.text = "+"
			marker.font_size = 128
			marker.pixel_size = 0.0045
			marker.modulate = Color(1.0, 1.0, 1.0, 0.55)
			marker.outline_size = 18
			marker.outline_modulate = Color(0.12, 0.16, 0.10, 0.55)
			marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			marker.position = Vector3(x, PLOT_HEIGHT + 0.55, z)
			add_child(marker)

			var entry := {
				"center": Vector3(x, PLOT_HEIGHT, z),
				"seed": seed_node,
				"sprout": sprout_node,
				"mature": mature_node,
				"coin": coin,
				"marker": marker,
				"seed_scale": seed_node.scale,
				"sprout_scale": sprout_node.scale,
				"mature_scale": mature_node.scale,
				"mature_pos": mature_node.position,
				"coin_scale": coin.scale,
				"coin_pos": coin.position,
			}
			entry.merge(_build_plot_bar(plot))
			_plots.append(entry)


## 生长进度条：两个 billboard 面片（底槽 + 填充），只在生长中显示。
func _build_plot_bar(plot: Node3D) -> Dictionary:
	var bar := Node3D.new()
	bar.name = "Bar"
	bar.position = Vector3(0.0, PLOT_HEIGHT + BAR_Y, 0.0)
	plot.add_child(bar)

	var bg := Sprite3D.new()
	bg.texture = _white_tex
	bg.pixel_size = 1.0
	bg.centered = true
	bg.modulate = Color(0.06, 0.09, 0.06, 0.45)
	bg.scale = Vector3(BAR_WIDTH + 0.1, BAR_HEIGHT + 0.07, 1.0)
	bg.render_priority = 1
	bar.add_child(bg)

	var fill := Sprite3D.new()
	fill.texture = _white_tex
	fill.pixel_size = 1.0
	fill.centered = true
	fill.modulate = BAR_GROW
	fill.scale = Vector3(BAR_WIDTH, BAR_HEIGHT, 1.0)
	fill.render_priority = 2
	bar.add_child(fill)

	bar.visible = false
	return {"bar": bar, "bar_fill": fill}


func _build_audio() -> void:
	for sfx_name in SFX_NAMES:
		var path := "res://assets/audio/%s.wav" % sfx_name
		if not ResourceLoader.exists(path):
			push_warning("缺少音效：%s（跑 tools/audio/generate_sfx.py）" % path)
			continue
		var stream: AudioStream = load(path)
		var voices: Array[AudioStreamPlayer] = []
		for i in SFX_VOICES:
			var player := AudioStreamPlayer.new()
			player.name = "Sfx_%s_%d" % [sfx_name, i]
			player.stream = stream
			add_child(player)
			voices.append(player)
		_sfx[sfx_name] = voices
		_sfx_cursor[sfx_name] = 0


func _play(sfx_name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _sfx.has(sfx_name):
		return
	var voices: Array = _sfx[sfx_name]
	var index: int = _sfx_cursor[sfx_name]
	_sfx_cursor[sfx_name] = (index + 1) % voices.size()
	var player: AudioStreamPlayer = voices[index]
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func _play_delayed(sfx_name: String, delay: float, volume_db := 0.0, pitch := 1.0) -> void:
	get_tree().create_timer(delay).timeout.connect(func() -> void: _play(sfx_name, volume_db, pitch))


# ---------- HUD ----------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	add_child(_hud)

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)

	# 左上：金币（数字是主角），下面一行常驻「种子 -20 · 收 +45」提示，等于买种子入口的价格牌
	var coin_panel := _make_panel(root, 20, 10)
	coin_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	coin_panel.position = Vector2(24, 18)
	var coin_column := VBoxContainer.new()
	coin_column.add_theme_constant_override("separation", 0)
	coin_panel.add_child(coin_column)
	var coin_box := HBoxContainer.new()
	coin_box.add_theme_constant_override("separation", 12)
	coin_column.add_child(coin_box)
	var coin_caption := Label.new()
	coin_caption.text = "金币"
	coin_caption.add_theme_font_size_override("font_size", 20)
	coin_caption.add_theme_color_override("font_color", TEXT_MUTED)
	coin_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coin_box.add_child(coin_caption)
	_coin_value = Label.new()
	_coin_value.text = str(Balance.START_COINS)
	_coin_value.add_theme_font_size_override("font_size", 46)
	_coin_value.add_theme_color_override("font_color", COIN_GOLD)
	coin_box.add_child(_coin_value)
	var price_hint := Label.new()
	price_hint.text = "种子 -%d · 收 +%d" % [Balance.SEED_PRICE, Balance.SELL_PRICE]
	price_hint.add_theme_font_size_override("font_size", 15)
	price_hint.add_theme_color_override("font_color", TEXT_MUTED)
	coin_column.add_child(price_hint)

	# 右上：地块状态
	var status_panel := _make_panel(root, 16, 8)
	status_panel.anchor_left = 1.0
	status_panel.anchor_right = 1.0
	status_panel.offset_left = -24.0 - 330.0
	status_panel.offset_right = -24.0
	status_panel.offset_top = 18.0
	status_panel.offset_bottom = 70.0
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 19)
	_status.add_theme_color_override("font_color", TEXT_LIGHT)
	status_panel.add_child(_status)

	# 底部中间：情境提示
	var hint_panel := _make_panel(root, 22, 10)
	hint_panel.anchor_left = 0.5
	hint_panel.anchor_right = 0.5
	hint_panel.anchor_top = 1.0
	hint_panel.anchor_bottom = 1.0
	hint_panel.offset_left = -360.0
	hint_panel.offset_right = 360.0
	hint_panel.offset_top = -76.0
	hint_panel.offset_bottom = -22.0
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_color", TEXT_LIGHT)
	hint_panel.add_child(_hint)

	# 动效层：飞向 HUD 的金币小圆点画在这里，盖在其他 HUD 元素上面。
	_fx_layer = Control.new()
	_fx_layer.name = "Fx"
	_fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fx_layer)

	if not OS.is_debug_build():
		return
	_build_debug_panel(root)


func _make_panel(parent: Control, corner: int, margin: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(corner, margin))
	parent.add_child(panel)
	return panel


func _panel_style(corner: int, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.10, 0.08, 0.62)
	style.corner_radius_top_left = corner
	style.corner_radius_top_right = corner
	style.corner_radius_bottom_left = corner
	style.corner_radius_bottom_right = corner
	style.content_margin_left = margin + 8
	style.content_margin_right = margin + 8
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style


func _build_debug_panel(root: Control) -> void:
	var debug_panel := VBoxContainer.new()
	debug_panel.name = "Debug"
	debug_panel.anchor_top = 1.0
	debug_panel.anchor_bottom = 1.0
	debug_panel.offset_left = 24.0
	debug_panel.offset_right = 280.0
	debug_panel.offset_top = -204.0
	debug_panel.offset_bottom = -24.0
	debug_panel.add_theme_constant_override("separation", 8)
	root.add_child(debug_panel)

	_add_debug_button(debug_panel, "DEBUG: 立刻成熟", _debug_mature_all)
	_add_debug_button(debug_panel, "DEBUG: 回拨 2 小时", _debug_rewind)
	_add_debug_button(debug_panel, "DEBUG: +100 金币", _debug_give_coins)


func _add_debug_button(parent: Control, text: String, handler: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 44)
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(handler)
	parent.add_child(button)


func _update_hud() -> void:
	var coins := int(_data.get("coins", Balance.START_COINS))
	_coin_value.text = str(coins)

	var counts := FarmLogic.counts(_data.get("plots", []))
	_status.text = "空地 %d · 生长 %d · 成熟 %d" % [
		counts.get(STATE_EMPTY, 0), counts.get(STATE_GROWING, 0), counts.get(STATE_MATURE, 0),
	]

	var show_message := _message != "" and Time.get_ticks_msec() < _message_until
	if show_message:
		_hint.text = _message
		_hint.add_theme_color_override("font_color", Color(1.0, 0.91, 0.55))
		return
	_hint.text = _context_hint(counts, coins)
	if int(counts.get(STATE_MATURE, 0)) > 0:
		_hint.add_theme_color_override("font_color", COIN_GOLD)
	else:
		_hint.add_theme_color_override("font_color", TEXT_LIGHT)


func _context_hint(counts: Dictionary, coins: int) -> String:
	var mature := int(counts.get(STATE_MATURE, 0))
	var growing := int(counts.get(STATE_GROWING, 0))
	var empty := int(counts.get(STATE_EMPTY, 0))
	if mature > 0:
		return "有 %d 块可以收了 · 点地块收获 +%d" % [mature, Balance.SELL_PRICE]
	if growing > 0:
		if empty > 0 and coins >= Balance.SEED_PRICE:
			return "作物在长 · 还能再种 %d 块（每块 -%d）" % [empty, Balance.SEED_PRICE]
		return "作物在长，长好了会冒金币"
	if coins < Balance.SEED_PRICE:
		return "金币不够买种子了（要 %d）" % Balance.SEED_PRICE
	return "点空地种下 · 每颗种子 -%d" % Balance.SEED_PRICE


func _flash(text: String, seconds := 2.4) -> void:
	_message = text
	_message_until = Time.get_ticks_msec() + int(seconds * 1000.0)
	_update_hud()


func _punch(node: Control, amount := 1.22) -> void:
	node.pivot_offset = node.size * 0.5
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector2(amount, amount), 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector2.ONE, 0.16)


# ---------- 交互 ----------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_try_select(event.position)


func _try_select(screen_pos: Vector2) -> void:
	var from := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var hit: Variant = Plane(Vector3.UP, PLOT_HEIGHT).intersects_ray(from, dir)
	if hit == null:
		return

	var point: Vector3 = hit
	var half := PLOT_SIZE * 0.5
	for i in _plots.size():
		var center: Vector3 = _plots[i]["center"]
		if absf(point.x - center.x) <= half and absf(point.z - center.z) <= half:
			_interact(i)
			return


func _interact(index: int) -> void:
	if _anim_plots.has(index):
		return
	var plots: Array = _data["plots"]
	var plot: Dictionary = plots[index]
	var center: Vector3 = _plots[index]["center"]
	var state := FarmLogic.state_of(plot)
	var coins := int(_data["coins"])

	match state:
		STATE_EMPTY:
			var result := FarmLogic.plant(plot, coins, _now())
			if not result["ok"]:
				_flash("金币不够买种子（要 %d）" % Balance.SEED_PRICE)
				_float_text(center + Vector3(0, 1.1, 0), "金币不够", Color(1.0, 0.45, 0.4), 0.7, 0.8, 0.62)
				return
			_data["coins"] = result["coins"]
			_play("plant", SFX_VOL_PLANT, randf_range(0.95, 1.08))
			_play_plant_juice(index)
			_flash("种下 #%d（-%d）" % [index + 1, Balance.SEED_PRICE])
		STATE_GROWING:
			var left: int = Balance.MATURE_SECONDS - (_now() - int(plot.get("planted_at", _now())))
			var label := _format_left(left)
			_flash("还要 %s" % label)
			_float_text(center + Vector3(0, 1.4, 0), label, TEXT_LIGHT, 0.7, 0.7, 0.6)
			_play("plant", SFX_VOL_TICK, 1.35)
		STATE_MATURE:
			var result := FarmLogic.harvest(plot, coins)
			_data["coins"] = result["coins"]
			# 先更新金币数再飞金币：小圆的落点按新数字的宽度算，才不会偏一格数字。
			_update_hud()
			_play("harvest", SFX_VOL_HARVEST)
			_play_delayed("coin", 0.09, SFX_VOL_COIN)
			_play_harvest_juice(index)
			_shake()
			_flash("收获 #%d（+%d）" % [index + 1, Balance.SELL_PRICE], 2.0)
			_float_text(center + Vector3(0, 1.6, 0), "+%d" % Balance.SELL_PRICE, COIN_GOLD, 0.9, 0.95, 0.8)

	_refresh_plots()
	_save()
	_update_hud()


func _format_left(seconds: int) -> String:
	var left := maxi(seconds, 0)
	if left < 60:
		return "%d 秒" % left
	return "%d:%02d" % [left / 60, left % 60]


# ---------- 动效 ----------

func _play_plant_juice(index: int) -> void:
	var entry: Dictionary = _plots[index]
	var seed_node := entry["seed"] as Node3D
	var base: Vector3 = entry["seed_scale"]
	seed_node.scale = base * 0.25
	var tw := create_tween()
	tw.tween_property(seed_node, "scale", base, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _play_harvest_juice(index: int) -> void:
	var entry: Dictionary = _plots[index]
	_anim_plots[index] = true

	var mature_node := entry["mature"] as Node3D
	var mature_base: Vector3 = entry["mature_scale"]
	var mature_pos: Vector3 = mature_node.position

	var pop := create_tween()
	pop.tween_property(mature_node, "scale", mature_base * 1.35, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(mature_node, "scale", Vector3.ZERO, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	var rise := create_tween()
	rise.tween_property(mature_node, "position:y", mature_pos.y + 0.55, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var coin := entry["coin"] as Node3D
	var coin_base: Vector3 = entry["coin_scale"]
	var coin_pos: Vector3 = entry["coin_pos"]
	var coin_pop := create_tween()
	coin_pop.set_parallel(true)
	coin_pop.tween_property(coin, "position:y", coin_pos.y + 0.55, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	coin_pop.tween_property(coin, "scale", coin_base * 0.45, 0.24)
	_fly_coin_to_hud(entry["center"] as Vector3)

	var done := create_tween()
	done.tween_interval(0.42)
	done.tween_callback(func() -> void:
		mature_node.visible = false
		mature_node.scale = mature_base
		mature_node.position = mature_pos
		coin.visible = false
		coin.position = coin_pos
		coin.scale = coin_base
		_anim_plots.erase(index)
		_refresh_plots()
	)


## 2D 金币飞向 HUD 金币数：3D 金币贴脸放大会糊屏，用 2D 小圆点从地块位置飞到 HUD 更干净。
func _fly_coin_to_hud(world_pos: Vector3) -> void:
	var from := _camera.unproject_position(world_pos + Vector3(0, 0.8, 0))
	var to := _coin_value.get_global_rect().get_center()
	var dot := Panel.new()
	dot.size = Vector2(42, 42)
	dot.position = from - dot.size * 0.5
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = COIN_GOLD
	style.border_color = Color(0.95, 0.62, 0.10)
	style.set_border_width_all(4)
	style.set_corner_radius_all(21)
	dot.add_theme_stylebox_override("panel", style)
	_fx_layer.add_child(dot)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(dot, "position", to - dot.size * 0.5, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(dot, "scale", Vector2(0.55, 0.55), 0.34)
	tw.chain().tween_callback(func() -> void:
		dot.queue_free()
		_punch(_coin_value)
	)


func _float_text(world_pos: Vector3, text: String, color: Color, rise := 1.0,
		duration := 0.9, font_scale := 1.0) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.0055 * font_scale
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 20
	label.outline_modulate = Color(0.08, 0.07, 0.04, 0.85)
	label.position = world_pos
	add_child(label)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", world_pos.y + rise, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "scale", Vector3.ONE * 1.2, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, duration * 0.55).set_delay(duration * 0.45)
	tw.chain().tween_callback(label.queue_free)


func _shake() -> void:
	var tw := create_tween()
	tw.tween_property(_camera, "position", CAMERA_POS + Vector3(0.07, 0.05, 0.0), 0.05)
	tw.tween_property(_camera, "position", CAMERA_POS + Vector3(-0.05, -0.03, 0.0), 0.06)
	tw.tween_property(_camera, "position", CAMERA_POS, 0.07)


func _animate_plots(delta: float) -> void:
	var pulse := 1.0 + sin(Time.get_ticks_msec() / 220.0) * 0.045
	var plots: Array = _data.get("plots", [])
	for i in _plots.size():
		if _anim_plots.has(i):
			continue
		var entry: Dictionary = _plots[i]
		var state := STATE_EMPTY
		if i < plots.size():
			state = String(plots[i].get("state", STATE_EMPTY))
		if state == STATE_MATURE:
			var mature_node := entry["mature"] as Node3D
			mature_node.scale = (entry["mature_scale"] as Vector3) * pulse
			var coin := entry["coin"] as Node3D
			coin.rotation.y += delta * 2.5
			var coin_pos: Vector3 = entry["coin_pos"]
			coin.position.y = coin_pos.y + sin(Time.get_ticks_msec() / 400.0) * 0.08


func _update_progress_bars() -> void:
	var now := _now()
	var plots: Array = _data.get("plots", [])
	for i in _plots.size():
		var fill := _plots[i]["bar_fill"] as Sprite3D
		if i >= plots.size():
			continue
		var plot: Dictionary = plots[i]
		if FarmLogic.state_of(plot) != STATE_GROWING:
			continue
		var planted := int(plot.get("planted_at", now))
		var progress := clampf(float(now - planted) / float(Balance.MATURE_SECONDS), 0.0, 1.0)
		var width := BAR_WIDTH * maxf(progress, 0.02)
		fill.scale = Vector3(width, BAR_HEIGHT, 1.0)
		fill.position.x = -(BAR_WIDTH - width) * 0.5
		fill.modulate = BAR_GROW.lerp(COIN_GOLD, progress)


# ---------- 调试 ----------

func _debug_mature_all() -> void:
	for plot in _data.get("plots", []):
		if FarmLogic.state_of(plot) == STATE_GROWING:
			plot["planted_at"] = _now() - Balance.MATURE_SECONDS
	# 调试按钮按下就立刻变熟，不等下一次 1 秒 tick。
	FarmLogic.tick_growth(_data.get("plots", []), _now())
	_flash("DEBUG：全部成熟")
	_refresh_plots()
	_save()
	_update_hud()


func _debug_rewind() -> void:
	## 模拟「关掉 2 小时再打开」：last_seen_at 和生长中的 planted_at 一起往回拨，
	## 这样 apply_offline() 走的完全是真实离线结算的代码路径。
	var shift := 7200
	_data["last_seen_at"] = _now() - shift
	for plot in _data.get("plots", []):
		if FarmLogic.state_of(plot) == STATE_GROWING:
			plot["planted_at"] = int(plot.get("planted_at", _now())) - shift
	_apply_offline()
	_flash("DEBUG：回拨 2 小时（模拟离线）")
	_refresh_plots()
	_save()
	_update_hud()


func _debug_give_coins() -> void:
	_data["coins"] = int(_data["coins"]) + 100
	_flash("DEBUG：+100 金币")
	_save()
	_update_hud()


func _run_demo() -> void:
	match _demo:
		"plant":
			_interact(4)
		"growing":
			_interact(4)
			_data["plots"][4]["planted_at"] = _now() - Balance.MATURE_SECONDS / 2
			_refresh_plots()
			_update_progress_bars()
			_update_hud()
		"mature":
			_interact(0)
			_interact(4)
			_interact(5)
			_debug_mature_all()
		"harvest":
			_interact(4)
			_debug_mature_all()
			_interact(4)


# ---------- 视图 ----------

func _refresh_plots() -> void:
	var plots: Array = _data.get("plots", [])
	var now := _now()
	for i in _plots.size():
		if _anim_plots.has(i):
			continue
		var entry: Dictionary = _plots[i]
		var state := STATE_EMPTY
		var planted := now
		if i < plots.size():
			state = String(plots[i].get("state", STATE_EMPTY))
			planted = int(plots[i].get("planted_at", now))

		var show_seed := false
		var show_sprout := false
		var show_mature := false
		if state == STATE_GROWING:
			if now - planted < Balance.MATURE_SECONDS / 3:
				show_seed = true
			else:
				show_sprout = true
		elif state == STATE_MATURE:
			show_mature = true

		_show_crop(entry["seed"] as Node3D, entry["seed_scale"], show_seed)
		_show_crop(entry["sprout"] as Node3D, entry["sprout_scale"], show_sprout)

		var mature_node := entry["mature"] as Node3D
		_show_crop(mature_node, entry["mature_scale"], show_mature)
		mature_node.position = entry["mature_pos"]

		var coin := entry["coin"] as Node3D
		coin.visible = state == STATE_MATURE
		coin.scale = entry["coin_scale"]
		coin.position = entry["coin_pos"]

		var bar := entry["bar"] as Node3D
		bar.visible = state == STATE_GROWING

		var marker := entry["marker"] as Label3D
		marker.visible = state == STATE_EMPTY


func _show_crop(node: Node3D, base_scale: Vector3, visible_now: bool) -> void:
	node.visible = visible_now
	node.scale = base_scale


func _make_white_texture() -> ImageTexture:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)
