extends Node3D

## M2：闭环打通。
## 种 → 等 10 分钟 → 收 → 卖 45 → 买种子 20，离线按时间戳结算，封顶 8 小时。
## 调试包里有「立刻成熟 / 回拨 2 小时」两个按钮，用来在不等 10 分钟的前提下验收。

const PLOT_SIZE := 1.7
const PLOT_HEIGHT := 0.28
const SPACING_X := 2.0
const SPACING_Z := 2.1
const GROUND_SIZE := Vector3(9.4, 0.2, 6.6)

const COLOR_EMPTY := Color(0.45, 0.31, 0.21)
const COLOR_GROWING := Color(0.64, 0.47, 0.20)
const COLOR_MATURE := Color(0.30, 0.62, 0.25)
const COLOR_GROUND := Color(0.36, 0.55, 0.28)

const STATE_EMPTY := "empty"
const STATE_GROWING := "growing"
const STATE_MATURE := "mature"

const PLOT_SCENE := preload("res://assets/models/plot_block.glb")
const CROP_SEED := preload("res://assets/models/crop_seed.glb")
const CROP_SPROUT := preload("res://assets/models/crop_sprout.glb")
const CROP_MATURE := preload("res://assets/models/crop_mature.glb")
const COIN_SCENE := preload("res://assets/models/coin.glb")
const GROUND_SCENE := preload("res://assets/models/ground.glb")
const FENCE_SCENE := preload("res://assets/models/fence.glb")
const WINDMILL_SCENE := preload("res://assets/models/windmill.glb")

var _camera: Camera3D
var _hud: Label
var _debug_panel: VBoxContainer
var _plots: Array[Dictionary] = []      # {node, mat, center}
var _data: Dictionary = {}
var _message := ""
var _tick_accum := 0.0

# 调试参数：--tap=x,y 模拟点击；--shot=path 截图；--fastforward=秒 把 last_seen_at 往前拨
var _shot_path := ""
var _tap_pos := Vector2(-1, -1)
var _force_mature := false
var _frames := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--tap="):
			var parts := arg.trim_prefix("--tap=").split(",")
			if parts.size() == 2:
				_tap_pos = Vector2(float(parts[0]), float(parts[1]))
		elif arg == "--mature":
			_force_mature = true

	_data = SaveManager.load_data()
	if _force_mature:
		for plot in _data.get("plots", []):
			if String(plot.get("state", STATE_EMPTY)) == STATE_GROWING:
				plot["planted_at"] = _now() - Balance.MATURE_SECONDS
	_apply_offline()
	_build_environment()
	_build_ground()
	_build_plots()
	_build_decor()
	_build_hud()
	_refresh_plots()
	_update_hud()

	var autosave := Timer.new()
	autosave.wait_time = 10.0
	autosave.autostart = true
	autosave.timeout.connect(func() -> void: SaveManager.save_data(_data))
	add_child(autosave)

	SaveManager.save_data(_data)


func _process(delta: float) -> void:
	_tick_accum += delta
	if _tick_accum >= 1.0:
		_tick_accum = 0.0
		_tick_growth()
	for entry in _plots:
		var coin := entry["coin"] as Node3D
		if coin.visible:
			coin.rotation.y += delta * 2.5
			coin.position.y = PLOT_HEIGHT + 1.15 + sin(Time.get_ticks_msec() / 400.0) * 0.08
	_frames += 1
	if _frames == 2 and _tap_pos.x >= 0.0:
		_try_select(_tap_pos)
	if _shot_path != "" and _frames == 5:
		_capture_and_quit()


func _capture_and_quit() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shot_path)
	print("SHOT_SAVED ", _shot_path)
	get_tree().quit()


# ---------- 存档与时间 ----------

func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _apply_offline() -> void:
	## 用 last_seen_at 结算离线期间的生长；离线时长按 OFFLINE_CAP_HOURS 封顶。
	var now := _now()
	var last := int(_data.get("last_seen_at", now))
	var elapsed := clampi(now - last, 0, Balance.OFFLINE_CAP_HOURS * 3600)
	if elapsed > 60:
		_message = "离线 %d 分钟" % int(elapsed / 60.0)
	for plot in _data.get("plots", []):
		if String(plot.get("state", STATE_EMPTY)) != STATE_GROWING:
			continue
		var planted := int(plot.get("planted_at", now))
		if now - planted >= Balance.MATURE_SECONDS:
			plot["state"] = STATE_MATURE


func _tick_growth() -> void:
	var now := _now()
	var changed := false
	for plot in _data.get("plots", []):
		if String(plot.get("state", STATE_EMPTY)) != STATE_GROWING:
			continue
		if now - int(plot.get("planted_at", now)) >= Balance.MATURE_SECONDS:
			plot["state"] = STATE_MATURE
			changed = true
	if changed:
		_refresh_plots()
		SaveManager.save_data(_data)
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
	_camera.position = Vector3(0.0, 8.6, 6.2)
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
			coin.position = Vector3(x, PLOT_HEIGHT + 1.15, z)
			coin.visible = false
			add_child(coin)

			_plots.append({
				"center": Vector3(x, PLOT_HEIGHT, z),
				"seed": seed_node,
				"sprout": sprout_node,
				"mature": mature_node,
				"coin": coin,
			})


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(24, 20)
	layer.add_child(panel)

	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 24)
	panel.add_child(_hud)

	if not OS.is_debug_build():
		return

	_debug_panel = VBoxContainer.new()
	_debug_panel.position = Vector2(24, 80)
	layer.add_child(_debug_panel)

	var skip := Button.new()
	skip.text = "DEBUG: 立刻成熟"
	skip.pressed.connect(_debug_mature_all)
	_debug_panel.add_child(skip)

	var rewind := Button.new()
	rewind.text = "DEBUG: 回拨 2 小时"
	rewind.pressed.connect(_debug_rewind)
	_debug_panel.add_child(rewind)


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
	var plots: Array = _data["plots"]
	var plot: Dictionary = plots[index]
	var state := String(plot.get("state", STATE_EMPTY))
	var now := _now()

	match state:
		STATE_EMPTY:
			if int(_data["coins"]) < Balance.SEED_PRICE:
				_message = "金币不够买种子"
				_update_hud()
				return
			_data["coins"] = int(_data["coins"]) - Balance.SEED_PRICE
			plot["state"] = STATE_GROWING
			plot["planted_at"] = now
			_message = "种下 #%d（-%d）" % [index, Balance.SEED_PRICE]
		STATE_GROWING:
			var left := Balance.MATURE_SECONDS - (now - int(plot.get("planted_at", now)))
			_message = "还要 %d 秒" % maxi(left, 0)
		STATE_MATURE:
			_data["coins"] = int(_data["coins"]) + Balance.SELL_PRICE
			plot["state"] = STATE_EMPTY
			plot["planted_at"] = 0
			_message = "收获 #%d（+%d）" % [index, Balance.SELL_PRICE]

	_refresh_plots()
	SaveManager.save_data(_data)
	_update_hud()


# ---------- 调试 ----------

func _debug_mature_all() -> void:
	for plot in _data.get("plots", []):
		if String(plot.get("state", STATE_EMPTY)) == STATE_GROWING:
			plot["planted_at"] = _now() - Balance.MATURE_SECONDS
	_refresh_plots()
	SaveManager.save_data(_data)
	_message = "DEBUG：全部成熟"
	_update_hud()


func _debug_rewind() -> void:
	## 模拟「关掉 2 小时再打开」：last_seen_at 和生长中的 planted_at 一起往回拨，
	## 这样 apply_offline() 走的完全是真实离线结算的代码路径。
	var shift := 7200
	_data["last_seen_at"] = _now() - shift
	for plot in _data.get("plots", []):
		if String(plot.get("state", STATE_EMPTY)) == STATE_GROWING:
			plot["planted_at"] = int(plot.get("planted_at", _now())) - shift
	_apply_offline()
	_refresh_plots()
	SaveManager.save_data(_data)
	_message = "DEBUG：回拨 2 小时（模拟离线）"
	_update_hud()


# ---------- 视图 ----------

func _refresh_plots() -> void:
	var plots: Array = _data.get("plots", [])
	var now := _now()
	for i in _plots.size():
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

		(_plots[i]["seed"] as Node3D).visible = show_seed
		(_plots[i]["sprout"] as Node3D).visible = show_sprout
		(_plots[i]["mature"] as Node3D).visible = show_mature
		var coin := _plots[i]["coin"] as Node3D
		coin.visible = state == STATE_MATURE


func _update_hud() -> void:
	var coins := int(_data.get("coins", Balance.START_COINS))
	var empty := 0
	var growing := 0
	var mature := 0
	for plot in _data.get("plots", []):
		match String(plot.get("state", STATE_EMPTY)):
			STATE_GROWING:
				growing += 1
			STATE_MATURE:
				mature += 1
			_:
				empty += 1
	var line := "Farm 111   Coins: %d   空地 %d / 生长 %d / 成熟 %d" % [coins, empty, growing, mature]
	if _message != "":
		line += "   |   " + _message
	_hud.text = line
