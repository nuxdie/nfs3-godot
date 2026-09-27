class_name Hud
extends CanvasLayer
## Race HUD, drawn with plain Control drawing: tachometer and speed, gear,
## lap/position/time, a track map, rear-view mirror, messages, pause menu and
## the results screen.

const ACCENT := Color(1.0, 0.72, 0.1)
const RED := Color(1.0, 0.22, 0.15)
const PANEL := Color(0, 0, 0, 0.45)

var race: Node
var player: Car
var pursuit := false

var _root: Control
var _draw: Control
var _msg: Label
var _msg_t := 0.0
var _count: Label
var _loading: Label
var _pause: Control
var _results: Control
var _mirror: TextureRect
var _mirror_vp: SubViewport
var _mirror_cam: Camera3D
var _font: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_draw = Control.new()
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_on_draw)
	_root.add_child(_draw)

	# Labels span the screen and centre their text, so they stay centred at any size.
	_msg = _big_label(42)
	_msg.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_msg.offset_top = 165
	_msg.offset_bottom = 235
	_count = _big_label(110)
	_count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading = _big_label(34)
	_loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_setup_mirror()
	_build_pause()


func _big_label(size: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ACCENT)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(l)
	return l


func _setup_mirror() -> void:
	_mirror_vp = SubViewport.new()
	_mirror_vp.size = Vector2i(420, 110)
	_mirror_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_mirror_vp)
	_mirror_cam = Camera3D.new()
	_mirror_cam.fov = 40
	_mirror_cam.far = 500
	_mirror_vp.add_child(_mirror_cam)
	_mirror = TextureRect.new()
	_mirror.texture = _mirror_vp.get_texture()
	_mirror.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_mirror.size = Vector2(420, 110)
	_mirror.position = Vector2(-210, 12)
	_mirror.flip_h = true
	_mirror.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_mirror)


func _build_pause() -> void:
	_pause = _panel("PAUSED")
	var box: VBoxContainer = _pause.get_meta("box")
	for item in [["Resume", _resume], ["Restart", _restart], ["Quit to Menu", _quit]]:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(260, 44)
		b.pressed.connect(item[1])
		box.add_child(b)
	_pause.visible = false


func _panel(title: String) -> Control:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 48)
	t.add_theme_color_override("font_color", ACCENT)
	box.add_child(t)
	bg.set_meta("box", box)
	bg.set_meta("title", t)
	return bg


# ------------------------------------------------------------------ API

func show_loading(text: String) -> void:
	_loading.text = text
	_loading.visible = true


func hide_loading() -> void:
	_loading.visible = false


func set_countdown(t: float) -> void:
	_count.visible = t > 0.0 and t <= 3.0
	_count.text = str(ceili(t))


func flash(text: String, secs: float) -> void:
	_msg.text = text
	_msg_t = secs
	_msg.visible = true
	_count.visible = false


func show_results(title: String, rows: Array, extra: String) -> void:
	_results = _panel(title)
	var box: VBoxContainer = _results.get_meta("box")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 28)
	box.add_child(grid)
	for h in ["Pos", "Driver / Car", "Time", "Best Lap"]:
		grid.add_child(_cell(h, ACCENT))
	for i in rows.size():
		grid.add_child(_cell(str(i + 1)))
		grid.add_child(_cell(rows[i].name))
		grid.add_child(_cell(rows[i].time))
		grid.add_child(_cell(rows[i].best))
	if extra != "":
		box.add_child(_cell(extra, RED))
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(hb)
	for item in [["Race Again", _restart], ["Main Menu", _quit]]:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(200, 44)
		b.pressed.connect(item[1])
		hb.add_child(b)
	hb.get_child(0).grab_focus()
	_mirror.visible = false
	# The results title says it all; don't let a lingering flash message overlap it.
	_msg_t = 0.0
	_msg.visible = false


func _cell(text: String, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", color)
	return l


static func fmt_time(t: float) -> String:
	if t == INF or t < 0.0:
		return "--:--.--"
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]


static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, suffix]


# ------------------------------------------------------------------ input

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause") and _results == null:
		if get_tree().paused:
			_resume()
		else:
			get_tree().paused = true
			_pause.visible = true
			(_pause.get_meta("box") as VBoxContainer).get_child(1).grab_focus()
	elif e.is_action_pressed("mirror"):
		_mirror.visible = not _mirror.visible


func _resume() -> void:
	get_tree().paused = false
	_pause.visible = false


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _quit() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ------------------------------------------------------------------ drawing

func _process(dt: float) -> void:
	if _msg_t > 0.0:
		_msg_t -= dt
		_msg.modulate.a = clampf(_msg_t * 2.0, 0.0, 1.0)
		if _msg_t <= 0.0:
			_msg.visible = false
	if player and is_instance_valid(player) and _mirror.visible:
		var xf := player.global_transform
		_mirror_cam.global_transform = Transform3D(xf.basis, xf * Vector3(0, 1.25, 0.2))
		# Camera looks down -Z; the car faces +Z, so this already looks backwards.
	_draw.queue_redraw()


func _on_draw() -> void:
	if player == null or not is_instance_valid(player) or race == null or race.path == null:
		return
	var size := _draw.size
	_draw_gauges(Vector2(size.x - 170, size.y - 150))
	_draw_info(size)
	_draw_map(Rect2(20, size.y - 240, 220, 220))
	if pursuit:
		var on := fmod(Time.get_ticks_msec() / 250.0, 2.0) < 1.0
		var c := RED if on else Color(0.2, 0.4, 1)
		_text("PURSUIT", Vector2(size.x * 0.5, 155), 30, c, true)


func _text(s: String, pos: Vector2, fsize: int, color := Color.WHITE, centered := false) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var p := pos - Vector2(w * 0.5 if centered else 0.0, 0)
	_draw.draw_string_outline(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 6, Color(0, 0, 0, 0.8))
	_draw.draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)


func _draw_gauges(c: Vector2) -> void:
	var r := 120.0
	_draw.draw_circle(c, r + 8, PANEL)
	var max_rpm := ceilf(player.redline / 1000.0 + 1.0) * 1000.0
	var a0 := deg_to_rad(135)
	var a1 := deg_to_rad(405)
	# Redline band.
	var red_from := lerpf(a0, a1, player.redline / max_rpm)
	_draw.draw_arc(c, r - 6, red_from, a1, 24, RED, 8)
	for k in int(max_rpm / 1000.0) + 1:
		var a := lerpf(a0, a1, k * 1000.0 / max_rpm)
		var dir := Vector2(cos(a), sin(a))
		_draw.draw_line(c + dir * (r - 16), c + dir * (r - 2), Color.WHITE, 3)
		_text(str(k), c + dir * (r - 32) + Vector2(-5, 7), 16)
	var na := lerpf(a0, a1, clampf(player.rpm / max_rpm, 0.0, 1.05))
	_draw.draw_line(c, c + Vector2(cos(na), sin(na)) * (r - 10), RED, 4)
	_draw.draw_circle(c, 8, RED)
	var spd := player.kmh() if Game.units_kmh else player.kmh() / 1.609
	_text("%d" % roundi(spd), c + Vector2(0, 58), 40, Color.WHITE, true)
	_text("KM/H" if Game.units_kmh else "MPH", c + Vector2(0, 80), 14, ACCENT, true)
	var g := "R" if player.gear < 0 else str(player.gear)
	_text(g, c + Vector2(0, -32), 34, ACCENT, true)


func _draw_info(size: Vector2) -> void:
	var r: Dictionary = race.player_racer()
	if r.is_empty():
		return
	var x := 24.0
	var y := 44.0
	var free_roam: bool = Game.mode == Game.Mode.FREE_ROAM
	if not free_roam:
		_text("LAP", Vector2(x, y), 16, ACCENT)
		_text("%d/%d" % [clampi(r.lap + 1, 1, Game.laps), Game.laps], Vector2(x, y + 34), 34)
		if Game.mode != Game.Mode.TIME_TRIAL:
			_text("POS", Vector2(x + 120, y), 16, ACCENT)
			_text("%d/%d" % [race.position_of(player), race.racers.size()], Vector2(x + 120, y + 34), 34)
	var tx := size.x - 250
	_text("TIME", Vector2(tx, y), 16, ACCENT)
	_text(fmt_time(race.race_time), Vector2(tx, y + 30), 28)
	_text("LAP " + fmt_time(race.race_time - r.lap_start if r.lap >= 0 else 0.0), Vector2(tx, y + 58), 18)
	_text("BEST " + fmt_time(r.best), Vector2(tx, y + 80), 18)
	if Game.mode == Game.Mode.HOT_PURSUIT:
		_text("TICKETS %d/%d" % [race.tickets, race.MAX_TICKETS], Vector2(x, y + 70), 18, RED)
	var cam: ChaseCamera = race.cam
	_text("[C] " + cam.mode_name() + "   [R] reset   [M] mirror   [Esc] pause", Vector2(size.x * 0.5, size.y - 14), 13, Color(1, 1, 1, 0.6), true)


func _draw_map(rect: Rect2) -> void:
	var path: TrackPath = race.path
	_draw.draw_rect(rect, PANEL)
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in path.points:
		mn = mn.min(Vector2(p.x, p.z))
		mx = mx.max(Vector2(p.x, p.z))
	var span := maxf(mx.x - mn.x, mx.y - mn.y)
	var scale := (rect.size.x - 20) / maxf(span, 1.0)
	var off := rect.position + Vector2(10, 10) + (Vector2(span, span) - (mx - mn)) * 0.5 * scale
	var to_map := func(p: Vector3) -> Vector2:
		# Top-down view with +Z up the screen; +X (the driver's left when heading +Z) is then screen-left.
		return off + Vector2(mx.x - p.x, mx.y - p.z) * scale
	var pts := PackedVector2Array()
	for i in range(0, path.size(), 2):
		pts.append(to_map.call(path.points[i]))
	pts.append(pts[0])
	_draw.draw_polyline(pts, Color(1, 1, 1, 0.7), 3)
	_draw.draw_circle(to_map.call(path.points[0]), 4, Color.WHITE)
	for c in race.cops:
		if is_instance_valid(c):
			_draw.draw_circle(to_map.call(c.global_position), 4, Color(0.3, 0.5, 1))
	for rr in race.racers:
		var col := ACCENT if rr.car == player else RED
		_draw.draw_circle(to_map.call(rr.car.global_position), 6 if rr.car == player else 4, col)
