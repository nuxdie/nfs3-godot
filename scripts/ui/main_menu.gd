extends Control
## Front end: pick mode, track, car and race options, then start.

const ACCENT := Color(1.0, 0.72, 0.1)

var _mode: OptionButton
var _track: OptionButton
var _car: OptionButton
var _laps: SpinBox
var _opp: SpinBox
var _traffic: CheckBox
var _kmh: CheckBox
var _quality: OptionButton
var _status: Label
var _preview: SubViewport
var _preview_pivot: Node3D
var _preview_car: Node3D


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var split := HBoxContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 30)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 40)
	add_child(margin)
	margin.add_child(split)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(460, 0)
	col.add_theme_constant_override("separation", 14)
	split.add_child(col)

	var title := Label.new()
	title.text = "NFS3 REVIVAL"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", ACCENT)
	col.add_child(title)
	var sub := Label.new()
	sub.text = "A Hot Pursuit-style racer for Godot"
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	col.add_child(sub)
	col.add_child(HSeparator.new())

	_mode = _option(col, "Mode")
	for m in Game.MODE_NAMES:
		_mode.add_item(m)
	_mode.selected = Game.mode
	_track = _option(col, "Track")
	_car = _option(col, "Car")
	_car.item_selected.connect(func(_i): _update_preview())
	_laps = _spin(col, "Laps", 1, 8, Game.laps)
	_opp = _spin(col, "Opponents", 0, 7, Game.opponents)
	_quality = _option(col, "Graphics")
	for q in Game.QUALITY_NAMES:
		_quality.add_item(q)
	_quality.selected = Game.quality
	_traffic = CheckBox.new()
	_traffic.text = "Traffic"
	_traffic.button_pressed = Game.traffic
	col.add_child(_traffic)
	_kmh = CheckBox.new()
	_kmh.text = "Show speed in km/h"
	_kmh.button_pressed = Game.units_kmh
	col.add_child(_kmh)

	var start := Button.new()
	start.text = "RACE"
	start.custom_minimum_size = Vector2(0, 56)
	start.add_theme_font_size_override("font_size", 28)
	start.pressed.connect(_start)
	col.add_child(start)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func(): get_tree().quit())
	col.add_child(quit)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_status.add_theme_font_size_override("font_size", 13)
	col.add_child(_status)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(svc)
	_preview = SubViewport.new()
	_preview.own_world_3d = true
	_preview.transparent_bg = true
	svc.add_child(_preview)
	_build_preview_world()
	var help := Label.new()
	help.text = "Arrows/WASD drive · Space handbrake · C camera · B look back · R reset · M mirror · Esc pause"
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(help)

	_fill_lists()
	start.grab_focus()


func _option(parent: Control, label: String) -> OptionButton:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(120, 0)
	row.add_child(l)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.fit_to_longest_item = false
	row.add_child(ob)
	parent.add_child(row)
	return ob


func _spin(parent: Control, label: String, lo: int, hi: int, v: int) -> SpinBox:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(120, 0)
	row.add_child(l)
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.value = v
	row.add_child(sb)
	parent.add_child(row)
	return sb


func _fill_lists() -> void:
	_track.clear()
	for i in Game.tracks.size():
		_track.add_item(Game.track_name(Game.tracks[i]))
		if Game.tracks[i] == Game.track_id:
			_track.selected = i
	_car.clear()
	for c in Game.cars:
		_car.add_item(c.name)
	_car.selected = Game.car_index
	if Game.has_game_data():
		_status.text = "NFS3 data: %s\n%d tracks, %d cars, %d police, %d traffic models." % [
			Game.data_root, Game.tracks.size() - 1, Game.cars.size(), Game.cop_cars.size(), Game.traffic_cars.size()]
	else:
		_status.text = "No NFS3 data found - using the procedural circuit and stand-in cars.\nPoint the NFS3_DATA environment variable at a folder containing gamedata/ (see README)."
	_update_preview()


func _build_preview_world() -> void:
	var w := Node3D.new()
	_preview.add_child(w)
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.position = Vector3(0, 1.6, 6.2)
	cam.rotation_degrees = Vector3(-10, 0, 0)
	cam.fov = 45
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	w.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	w.add_child(env)
	var floor_mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 3.6
	disc.bottom_radius = 3.6
	disc.height = 0.05
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.15, 0.15, 0.18)
	disc.material = fm
	floor_mi.mesh = disc
	floor_mi.position.y = -0.62
	w.add_child(floor_mi)
	_preview_pivot = Node3D.new()
	w.add_child(_preview_pivot)


func _update_preview() -> void:
	if _preview_car:
		_preview_car.queue_free()
		_preview_car = null
	if _car.selected < 0:
		return
	var c: Dictionary = Game.cars[_car.selected]
	var data: Object = Game.load_car(c.path, _car.selected)
	var root := Node3D.new()
	var mat: Material = null
	if data.texture:
		var sm := ShaderMaterial.new()
		sm.shader = preload("res://shaders/car.gdshader")
		sm.set_shader_parameter("albedo_tex", data.texture)
		if data.colours.size() > 0:
			sm.set_shader_parameter("paint", data.colours[0])
		mat = sm
	for p in data.body_parts + data.wheels:
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
		mi.position = p.center
		if mat:
			mi.material_override = mat
		root.add_child(mi)
	_preview_pivot.add_child(root)
	_preview_car = root


func _process(dt: float) -> void:
	if _preview_pivot:
		_preview_pivot.rotate_y(dt * 0.5)


func _start() -> void:
	Game.mode = _mode.selected
	Game.track_id = Game.tracks[_track.selected]
	Game.car_index = _car.selected
	Game.laps = int(_laps.value)
	Game.opponents = int(_opp.value)
	Game.traffic = _traffic.button_pressed
	Game.units_kmh = _kmh.button_pressed
	Game.quality = _quality.selected as Game.Quality
	Game.save_settings()
	get_tree().change_scene_to_file("res://scenes/race.tscn")
