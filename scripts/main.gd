extends Node3D

## M1：端上跑通。
## 运行时用代码搭场景（相机 / 光 / 地面 / 6 块地 / HUD），避免手写 .tscn 出错。
## 交互：单指点地块 → 变色 + 写存档；重启后颜色还在（验证存档链路）。

const PLOT_SIZE := 1.7
const PLOT_HEIGHT := 0.28
const SPACING_X := 2.0
const SPACING_Z := 2.1
const GROUND_SIZE := Vector3(9.4, 0.2, 6.6)

const COLOR_EMPTY := Color(0.45, 0.31, 0.21)
const COLOR_SELECTED := Color(0.40, 0.72, 0.32)
const COLOR_GROUND := Color(0.36, 0.55, 0.28)

var _camera: Camera3D
var _hud: Label
var _plots: Array[Dictionary] = []      # {node: MeshInstance3D, mat: StandardMaterial3D, center: Vector3}
var _data: Dictionary = {}
var _selected: int = -1

# 调试用：-- --shot=res://build/shot.png 时截一张图然后退出（M3 做截图验收会复用）。
# 调试用：-- --tap=640,470 在启动时模拟一次点击，用来在无人值守下验证点选与存档链路。
var _shot_path := ""
var _tap_pos := Vector2(-1, -1)
var _frames := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--tap="):
			var parts := arg.trim_prefix("--tap=").split(",")
			if parts.size() == 2:
				_tap_pos = Vector2(float(parts[0]), float(parts[1]))

	_data = SaveManager.load_data()
	_build_environment()
	_build_ground()
	_build_plots()
	_build_hud()
	_apply_saved_state()
	_update_hud()

	var autosave := Timer.new()
	autosave.wait_time = 10.0
	autosave.autostart = true
	autosave.timeout.connect(func() -> void: SaveManager.save_data(_data))
	add_child(autosave)

	# 首次运行时立刻落一份档，确认写入链路是通的。
	SaveManager.save_data(_data)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 2 and _tap_pos.x >= 0.0:
		_try_select(_tap_pos)
	if _shot_path != "" and _frames == 5:
		_capture_and_quit()


func _capture_and_quit() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_path)
	print("SHOT_SAVED ", _shot_path)
	get_tree().quit()


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

	# 固定俯视相机：不跟随、不旋转、不缩放。
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.position = Vector3(0.0, 7.6, 5.4)
	_camera.rotation_degrees = Vector3(-54.0, 0.0, 0.0)
	_camera.fov = 42.0
	_camera.current = true
	add_child(_camera)


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var mesh := BoxMesh.new()
	mesh.size = GROUND_SIZE
	ground.mesh = mesh
	ground.position = Vector3(0.0, -GROUND_SIZE.y * 0.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR_GROUND
	mat.roughness = 1.0
	ground.material_override = mat
	add_child(ground)


func _build_plots() -> void:
	for row in Balance.PLOT_ROWS:
		for col in Balance.PLOT_COLS:
			var index := row * Balance.PLOT_COLS + col
			var x := (col - (Balance.PLOT_COLS - 1) * 0.5) * SPACING_X
			var z := (row - (Balance.PLOT_ROWS - 1) * 0.5) * SPACING_Z

			var plot := MeshInstance3D.new()
			plot.name = "Plot%d" % index
			var mesh := BoxMesh.new()
			mesh.size = Vector3(PLOT_SIZE, PLOT_HEIGHT, PLOT_SIZE)
			plot.mesh = mesh
			plot.position = Vector3(x, PLOT_HEIGHT * 0.5, z)

			var mat := StandardMaterial3D.new()
			mat.albedo_color = COLOR_EMPTY
			mat.roughness = 0.9
			plot.material_override = mat
			add_child(plot)

			_plots.append({
				"node": plot,
				"mat": mat,
				"center": Vector3(x, PLOT_HEIGHT, z),
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


func _apply_saved_state() -> void:
	var saved: Array = _data.get("plots", [])
	for i in _plots.size():
		var state := "empty"
		if i < saved.size() and saved[i] is Dictionary:
			state = String(saved[i].get("state", "empty"))
		_set_plot_visual(i, state)


func _set_plot_visual(index: int, state: String) -> void:
	var mat: StandardMaterial3D = _plots[index]["mat"]
	mat.albedo_color = COLOR_SELECTED if state == "selected" else COLOR_EMPTY


func _update_hud() -> void:
	var coins := int(_data.get("coins", Balance.START_COINS))
	var hint := "Tap a plot"
	if _selected >= 0:
		hint = "Selected: plot %d" % _selected
	elif _selected == -2:
		hint = "Missed (tap a brown plot)"
	_hud.text = "Farm 111   Coins: %d   %s" % [coins, hint]


func _unhandled_input(event: InputEvent) -> void:
	# 项目设置里开了 emulate_touch_from_mouse，所以桌面上的鼠标点击也会变成触摸事件。
	if event is InputEventScreenTouch and event.pressed:
		_try_select(event.position)


func _try_select(screen_pos: Vector2) -> void:
	var from := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	# 地块顶面：y = PLOT_HEIGHT
	var hit: Variant = Plane(Vector3.UP, PLOT_HEIGHT).intersects_ray(from, dir)
	if hit == null:
		_selected = -2
		_update_hud()
		return

	var point: Vector3 = hit
	var half := PLOT_SIZE * 0.5
	for i in _plots.size():
		var center: Vector3 = _plots[i]["center"]
		if absf(point.x - center.x) <= half and absf(point.z - center.z) <= half:
			_toggle_plot(i)
			return

	_selected = -2
	_update_hud()


func _toggle_plot(index: int) -> void:
	_selected = index
	var plots: Array = _data["plots"]
	if index >= plots.size():
		return
	var current := String(plots[index].get("state", "empty"))
	var next := "empty" if current == "selected" else "selected"
	plots[index]["state"] = next
	_set_plot_visual(index, next)
	SaveManager.save_data(_data)
	_update_hud()
