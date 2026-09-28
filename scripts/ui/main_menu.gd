extends Control
## Front end: a showroom with the selected car on a turntable, the race setup down
## the left, the track map top right and the start button bottom right. Everything
## is driven by up/down + left/right (keys or pad) and also works with the mouse.

const MODE_NOTES := [
	"Race up to seven rivals over a set number of laps.",
	"One rival, and every cop in the county after you both.",
	"Just you and the clock. No rivals, no traffic.",
	"No laps, no rivals. Cruise the track with traffic and patrols.",
]
const CONTROLS := [
	[["↑↓", "W", "S"], "Throttle · brake"], [["←→", "A", "D"], "Steer"], [["SPACE"], "Handbrake"],
	[["C"], "Change camera"], [["B"], "Look back"], [["R"], "Reset car"], [["H"], "Horn"],
	[["L", "K"], "Lights · high beam"], [["M"], "Mirror"], [["ESC"], "Pause"],
]
const M := 48.0               # screen margin
const PODIUM_TOP := -0.595
const CAM_DIST := 14.0
const CAM_Y := 2.6

enum Row { MODE, TRACK, CAR, LAPS, OPPONENTS, TRAFFIC, TIME }

var _rows: Array[SelectorRow] = []
var _settings_rows: Array[SelectorRow] = []
var _focus := 0
var _settings_focus := 0
var _opp_value := 3           # remembered across modes that cap or hide it

var _left: Control
var _overlay: Control
var _track_map: TrackMap
var _stats: CarStats
var _start_btn: Control
var _settings: Control
var _settings_panel: Control
var _status: Label
var _fade: ColorRect
var _photo_back: TextureRect
var _photo_front: TextureRect
var _chips: Array[Control] = []

var _preview: SubViewport
var _cam: Camera3D
var _mover: Node3D            # slides a new car in along the camera's x
var _pivot: Node3D            # turntable
var _floor: MeshInstance3D
var _preview_car: Node3D
var _spin_vel := 0.5          # turntable speed, rad/s; a flick sets it, then it eases back
var _dragging := false
var _last_drag_ms := 0
var _car_slide := 0.0

var _photos := {}             # track id -> Texture2D (or null)
var _outlines := {}           # track id -> PackedVector3Array
var _time := 0.0
var _start_hot := 0.0         # start-button hover/flash
var _quit_armed_until := 0
var _starting := false


func _ready() -> void:
	theme = UiKit.theme()
	_build_backdrop()
	_build_showroom()
	_build_overlay()
	_build_rows()
	_build_start()
	_build_chips()
	_build_settings()
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	resized.connect(_layout)
	_layout()
	_on_track_changed(false)
	_on_car_changed(0)
	_on_mode_changed()
	_set_focus(0)
	_intro()


# ------------------------------------------------------------------ building

func _build_backdrop() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	for i in 2:
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.modulate.a = 0.0
		add_child(tr)
		if i == 0:
			_photo_back = tr
		else:
			_photo_front = tr
	var shade := Control.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.draw.connect(_draw_shade.bind(shade))
	add_child(shade)


func _build_showroom() -> void:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_default_cursor_shape = Control.CURSOR_DRAG
	svc.gui_input.connect(_on_preview_input)
	add_child(svc)
	_preview = SubViewport.new()
	_preview.own_world_3d = true
	_preview.transparent_bg = true
	_preview.msaa_3d = Viewport.MSAA_4X if Game.quality == Game.Quality.HIGH else Viewport.MSAA_2X \
		if Game.quality == Game.Quality.MEDIUM else Viewport.MSAA_DISABLED
	svc.add_child(_preview)

	var w := Node3D.new()
	_preview.add_child(w)
	_cam = Camera3D.new()
	_cam.fov = 30
	_cam.position = Vector3(0, CAM_Y, CAM_DIST)
	_cam.rotation_degrees = Vector3(-9.5, 0, 0)
	w.add_child(_cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 30, 0)
	key.light_energy = 1.15
	key.light_color = Color(1.0, 0.97, 0.92)
	w.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 160, 0)
	rim.light_energy = 0.9
	rim.light_color = Color(0.7, 0.8, 1.0)
	w.add_child(rim)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	# A studio-softbox sky that only shows up in reflections: the backdrop stays transparent.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.9, 0.9, 0.95)
	sky_mat.sky_horizon_color = Color(0.35, 0.36, 0.4)
	sky_mat.ground_horizon_color = Color(0.12, 0.12, 0.14)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.03)
	sky_mat.sun_angle_max = 0.0
	env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.58)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)

	_floor = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(11, 11)
	var fm := ShaderMaterial.new()
	fm.shader = _floor_shader()
	fm.set_shader_parameter("accent", UiKit.ACCENT)
	plane.material = fm
	_floor.mesh = plane
	_floor.position.y = PODIUM_TOP
	w.add_child(_floor)
	_mover = Node3D.new()
	w.add_child(_mover)
	_pivot = Node3D.new()
	_mover.add_child(_pivot)


static func _floor_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 accent : source_color;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	float r = length(lp.xz);
	float a = atan(lp.z, lp.x);
	float disc = (1.0 - smoothstep(1.0, 4.2, r)) * 0.8;
	float ring = exp(-abs(r - 2.95) * 60.0) * 0.8;
	float halo = exp(-abs(r - 2.95) * 9.0) * 0.1;
	float ticks = step(0.8, fract(a * 72.0 / 6.2831853)) * step(3.05, r) * step(r, 3.13) * 0.22;
	float lines = exp(-abs(fract(r * 1.25) - 0.5) * 90.0) * 0.04 * step(r, 2.8);
	vec3 base = vec3(0.025, 0.027, 0.034) + vec3(lines);
	ALBEDO = mix(mix(base, accent.rgb, clamp(ring + halo, 0.0, 1.0)), vec3(0.9), ticks * 2.0);
	ALPHA = clamp(max(disc, ring + halo + ticks), 0.0, 1.0);
}
"""
	return s


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_track_map = TrackMap.new()
	_track_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_track_map)
	_stats = CarStats.new()
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_stats)


func _build_rows() -> void:
	_left = Control.new()
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_left)
	var track_names := PackedStringArray()
	var track_i := 0
	for i in Game.tracks.size():
		track_names.append(Game.track_name(Game.tracks[i]))
		if Game.tracks[i] == Game.track_id:
			track_i = i
	var car_names := PackedStringArray()
	for c in Game.cars:
		car_names.append(c.name)
	var laps := PackedStringArray()
	for n in range(1, 9):
		laps.append("%d lap%s" % [n, "" if n == 1 else "s"])
	_opp_value = Game.opponents
	var defs := [
		["Mode", PackedStringArray(Game.MODE_NAMES), Game.mode],
		["Track", track_names, track_i],
		["Car", car_names, Game.car_index],
		["Laps", laps, Game.laps - 1],
		["Opponents", PackedStringArray(), 0],
		["Traffic", PackedStringArray(["Off", "On"]), int(Game.traffic)],
		["Time of day", PackedStringArray(["Day", "Night"]), int(Game.night)],
	]
	for i in defs.size():
		var r := SelectorRow.new(defs[i][0], defs[i][1])
		r.index = defs[i][2]
		r.hovered.connect(func(): if not _settings.visible and not _rows[i].disabled: _set_focus(i))
		r.changed.connect(_on_row_changed.bind(i))
		_left.add_child(r)
		_rows.append(r)
	_rows[Row.LAPS].wrap = false
	_rows[Row.OPPONENTS].wrap = false


func _build_start() -> void:
	_start_btn = Control.new()
	_start_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_start_btn.draw.connect(_draw_start)
	_start_btn.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_start())
	_start_btn.mouse_entered.connect(func(): _start_btn.set_meta("hover", true))
	_start_btn.mouse_exited.connect(func(): _start_btn.set_meta("hover", false))
	add_child(_start_btn)


func _build_chips() -> void:
	for def in [["TAB", "SETTINGS", _toggle_settings], ["ESC", "QUIT", _request_quit]]:
		var c := Control.new()
		c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		c.set_meta("key", def[0])
		c.set_meta("text", def[1])
		c.draw.connect(_draw_chip.bind(c))
		var cb: Callable = def[2]
		c.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				cb.call())
		c.mouse_entered.connect(func(): c.set_meta("hover", true); c.queue_redraw())
		c.mouse_exited.connect(func(): c.set_meta("hover", false); c.queue_redraw())
		add_child(c)
		_chips.append(c)


func _build_settings() -> void:
	_settings = Control.new()
	_settings.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings.visible = false
	_settings.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings.draw.connect(func(): _settings.draw_rect(Rect2(Vector2.ZERO, _settings.size), Color(0.01, 0.012, 0.02, 0.8)))
	_settings.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and not _settings_panel.get_rect().has_point(e.position):
			_toggle_settings())
	add_child(_settings)
	_settings_panel = Control.new()
	_settings_panel.draw.connect(_draw_settings_panel)
	_settings.add_child(_settings_panel)
	var defs := [
		["Graphics", PackedStringArray(Game.QUALITY_NAMES), Game.quality],
		["Speed units", PackedStringArray(["km/h", "mph"]), 0 if Game.units_kmh else 1],
	]
	for i in defs.size():
		var r := SelectorRow.new(defs[i][0], defs[i][1])
		r.index = defs[i][2]
		r.hovered.connect(func(): _set_settings_focus(i))
		r.changed.connect(func(_v): _apply_settings())
		_settings_panel.add_child(r)
		_settings_rows.append(r)
	_settings_rows[0].wrap = false
	_status = UiKit.label("", "body", 14, UiKit.INK_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settings_panel.add_child(_status)
	if Game.has_game_data():
		_status.text = "%s\n%d tracks · %d cars · %d police · %d traffic models" % [
			Game.data_root, Game.tracks.size() - 1, Game.cars.size(), Game.cop_cars.size(), Game.traffic_cars.size()]
	else:
		_status.text = "No NFS3 data found, so you get the procedural circuit and stand-in cars. Point the NFS3_DATA environment variable at a folder containing gamedata/ (see README)."


func _layout() -> void:
	var W := size.x
	var H := size.y
	for tr in [_photo_back, _photo_front]:
		tr.size = size * 1.08
		tr.position = -size * 0.04
	_left.position = Vector2(M - 22, 112)
	_left.size = Vector2(minf(440.0, W * 0.4), SelectorRow.H * _rows.size())
	for i in _rows.size():
		_rows[i].position = Vector2(0, i * SelectorRow.H)
		_rows[i].size = Vector2(_left.size.x, SelectorRow.H)
	_track_map.size = Vector2(150, 104)
	_track_map.position = Vector2(W - M - _track_map.size.x + 8, 112)
	_stats.size = Vector2(minf(460.0, W * 0.38), 62)
	_stats.position = Vector2(W - M - _stats.size.x, H - 190)
	_start_btn.size = Vector2(330, 60)
	_start_btn.position = Vector2(W - M - _start_btn.size.x + 6, H - 40 - _start_btn.size.y)
	var x := W - M
	for i in range(_chips.size() - 1, -1, -1):
		var c := _chips[i]
		var cw := UiKit.text_width("cond", c.get_meta("key"), 13, 1) + 12 + 8 \
			+ UiKit.text_width("cond", "PRESS ESC AGAIN TO QUIT" if i == 1 and _quit_armed() else c.get_meta("text"), 14, 2) + 16
		c.size = Vector2(cw, 32)
		x -= cw
		c.position = Vector2(x, 44 - 16)
		x -= 10
	_settings_panel.size = Vector2(minf(640.0, W - 2 * M), minf(560.0, H - 80))
	_settings_panel.position = (size - _settings_panel.size) * 0.5
	for i in _settings_rows.size():
		_settings_rows[i].position = Vector2(20, 92 + i * SelectorRow.H)
		_settings_rows[i].size = Vector2(_settings_panel.size.x - 40, SelectorRow.H)
	_status.position = Vector2(42, 92 + _settings_rows.size() * SelectorRow.H + 44)
	_status.size = Vector2(_settings_panel.size.x - 84, 60)
	# Put the car in the space right of the setup column, a little above centre.
	if _cam:
		var aspect := W / maxf(H, 1.0)
		var half_w := CAM_DIST * tan(deg_to_rad(_cam.fov * 0.5)) * aspect
		var target_x := (_left.position.x + _left.size.x + W - M) * 0.5 / W
		_cam.h_offset = -(target_x - 0.5) * 2.0 * half_w
		# ...and lift it clear of the car caption at the bottom right.
		_cam.v_offset = -CAM_DIST * tan(deg_to_rad(_cam.fov * 0.5)) * 0.2
	_overlay.queue_redraw()


# ------------------------------------------------------------------ drawing

func _draw_shade(c: Control) -> void:
	var W := c.size.x
	var H := c.size.y
	var clear := Color(UiKit.BG, 0.0)
	var dark := Color(UiKit.BG, 0.92)
	# Left column scrim, top and bottom bands, so text reads over any photo.
	_grad_rect(c, Rect2(0, 0, 620, H), dark, clear, true)
	_grad_rect(c, Rect2(0, 0, W, 150), Color(UiKit.BG, 0.75), clear, false)
	_grad_rect(c, Rect2(0, H - 300, W, 300), clear, Color(UiKit.BG, 0.95), false)


static func _grad_rect(ci: CanvasItem, r: Rect2, from: Color, to: Color, horizontal: bool) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var cols := PackedColorArray([from, to, to, from]) if horizontal else PackedColorArray([from, from, to, to])
	ci.draw_polygon(pts, cols)


func _draw_overlay() -> void:
	var o := _overlay
	var W := o.size.x
	var H := o.size.y
	# Logo.
	var lf := UiKit.font("display")
	o.draw_string(lf, Vector2(M, 58), "NFS3", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, UiKit.ACCENT)
	var lw := lf.get_string_size("NFS3", HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	o.draw_string(UiKit.font("cond_med", 6), Vector2(M + lw + 10, 57), "REVIVAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UiKit.INK)
	UiKit.draw_slant(o, Rect2(M, 68, 132, 3), UiKit.ACCENT, 0.9)
	# Hot Pursuit: light bar sweeping across the top edge.
	if _rows[Row.MODE].index == Game.Mode.HOT_PURSUIT:
		var phase := fmod(_time * 2.2, 2.0)
		var col := UiKit.COP_RED if phase < 1.0 else UiKit.COP_BLUE
		var a := 0.6 * absf(sin(_time * 14.0))
		_grad_rect(o, Rect2(0, 0, W * 0.5, 4), Color(col, a if phase < 1.0 else 0.0), Color(col, 0.0), true)
		_grad_rect(o, Rect2(W * 0.5, 0, W * 0.5, 4), Color(col, 0.0), Color(col, a if phase >= 1.0 else 0.0), true)
	# Mode blurb under the setup list.
	var ny := _left.position.y + _left.size.y + 26
	o.draw_string(UiKit.font("body"), Vector2(M, ny), MODE_NOTES[_rows[Row.MODE].index], HORIZONTAL_ALIGNMENT_LEFT,
		_left.size.x - 20, 15, UiKit.INK_DIM)
	# Track card: header rule, then the map at the right with name and distances beside it.
	var card_w := 400.0
	var cx := W - M - card_w
	var cy := _track_map.position.y - 24
	var tid := Game.tracks[_rows[Row.TRACK].index]
	var hf0 := UiKit.font("cond", 3)
	var head := "TRACK %02d / %02d" % [_rows[Row.TRACK].index + 1, Game.tracks.size()]
	o.draw_string(hf0, Vector2(cx, cy), head, HORIZONTAL_ALIGNMENT_RIGHT, card_w, 13, UiKit.ACCENT)
	var head_w := hf0.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	o.draw_line(Vector2(cx + 60, cy - 5), Vector2(W - M - head_w - 14, cy - 5), UiKit.INK_FAINT, 1.0)
	var text_w := _track_map.position.x - 18 - cx
	var ty := _track_map.position.y + 38
	o.draw_string(UiKit.font("display"), Vector2(cx, ty), Game.track_name(tid).to_upper(), HORIZONTAL_ALIGNMENT_RIGHT,
		text_w, 30, UiKit.INK)
	var km := _track_map.length_m / 1000.0
	var laps := _rows[Row.LAPS].index + 1
	var bf := UiKit.font("cond", 2)
	if _track_map.length_m > 0:
		o.draw_string(bf, Vector2(cx, ty + 24), "%s  PER LAP" % _dist(km), HORIZONTAL_ALIGNMENT_RIGHT, text_w, 13, UiKit.INK_DIM)
		if not _rows[Row.LAPS].disabled:
			o.draw_string(bf, Vector2(cx, ty + 44), "%s  RACE" % _dist(km * laps), HORIZONTAL_ALIGNMENT_RIGHT, text_w, 13, UiKit.INK_DIM)
	# Car caption, right-aligned above the stats.
	var ci := _rows[Row.CAR].index
	var car_name: String = Game.cars[ci].name.to_upper()
	var df := UiKit.font("display")
	var fs := 58
	var max_w := W * 0.5
	while fs > 30 and df.get_string_size(car_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		fs -= 2
	var sx := _stats.position.x
	var sw := _stats.size.x
	var hf := UiKit.font("cond", 3)
	var car_no := "CAR %02d / %02d" % [ci + 1, Game.cars.size()]
	var spec_w := hf.get_string_size(_stats.spec, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	o.draw_string(hf, Vector2(sx, H - 268), _stats.spec, HORIZONTAL_ALIGNMENT_RIGHT, sw, 13, UiKit.INK_DIM)
	o.draw_string(hf, Vector2(sx, H - 268), car_no, HORIZONTAL_ALIGNMENT_RIGHT, sw - spec_w - 24, 13, UiKit.ACCENT)
	o.draw_string(df, Vector2(W - M - max_w, H - 214), car_name, HORIZONTAL_ALIGNMENT_RIGHT, max_w, fs, UiKit.INK)
	# Key hints.
	var hints := [["↑↓", "SELECT"], ["←→", "CHANGE"], ["ENTER", "RACE"], ["DRAG", "ROTATE CAR"]]
	UiKit.draw_hints(o, Vector2(M, H - 40 - 30), hints)


func _draw_start() -> void:
	var b := _start_btn
	var r := Rect2(Vector2.ZERO, b.size)
	var t := _start_hot
	# Drop "shadow" slab, then the face; hovering pushes the face out a touch.
	UiKit.draw_slant(b, Rect2(r.position + Vector2(6, 6), r.size), Color(UiKit.ACCENT_HOT, 0.35 + 0.3 * t))
	var face := Rect2(r.position - Vector2(3, 3) * t, r.size)
	UiKit.draw_slant(b, face, UiKit.ACCENT.lerp(Color(1, 0.85, 0.4), t * 0.6))
	# Sheen sweeping across every few seconds.
	var sweep := fmod(_time * 0.45, 1.6) - 0.3
	if sweep > -0.2 and sweep < 1.2:
		var sxp := face.position.x + face.size.x * sweep
		var sp := PackedVector2Array([Vector2(sxp, face.position.y), Vector2(sxp + 40, face.position.y),
			Vector2(sxp + 40 - face.size.y * 0.5, face.end.y), Vector2(sxp - face.size.y * 0.5, face.end.y)])
		var clipped := Geometry2D.intersect_polygons(sp, UiKit.slant_points(face))
		for poly in clipped:
			b.draw_colored_polygon(poly, Color(1, 1, 1, 0.25))
	var f := UiKit.font("display")
	var txt := "START RACE"
	var fs := 30
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var kx := face.position.x + (face.size.x - tw - 70) * 0.5
	b.draw_string(f, Vector2(kx, face.position.y + face.size.y * 0.5 + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.BG)
	UiKit.draw_key(b, Vector2(kx + tw + 14, face.position.y + face.size.y * 0.5), "ENTER", 12, UiKit.BG)


func _draw_chip(c: Control) -> void:
	var hover: bool = c.get_meta("hover", false)
	var armed := c == _chips[1] and _quit_armed()
	var col := UiKit.COP_RED if armed else (UiKit.ACCENT if hover else UiKit.INK)
	if hover or armed:
		UiKit.draw_slant(c, Rect2(Vector2.ZERO, c.size), Color(col, 0.12), 0.15)
	var kw := UiKit.draw_key(c, Vector2(8, c.size.y * 0.5), c.get_meta("key"), 13, col)
	var txt: String = "PRESS ESC AGAIN TO QUIT" if armed else c.get_meta("text")
	c.draw_string(UiKit.font("cond", 2), Vector2(8 + kw + 8, c.size.y * 0.5 + 5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		col if hover or armed else UiKit.INK_DIM)


func _draw_settings_panel() -> void:
	var p := _settings_panel
	var r := Rect2(Vector2.ZERO, p.size)
	p.draw_rect(r, Color(0.06, 0.065, 0.085, 0.97))
	p.draw_rect(Rect2(0, 0, r.size.x, 3), UiKit.ACCENT)
	p.draw_string(UiKit.font("display"), Vector2(42, 62), "SETTINGS", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, UiKit.INK)
	UiKit.draw_key(p, Vector2(r.size.x - 110, 44), "ESC", 13)
	p.draw_string(UiKit.font("cond", 2), Vector2(r.size.x - 72, 49), "BACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiKit.INK_DIM)
	var y := 92 + _settings_rows.size() * SelectorRow.H + 28
	_section(p, "GAME DATA", Vector2(42, y), r.size.x - 84)
	y += 110
	_section(p, "CONTROLS", Vector2(42, y), r.size.x - 84)
	y += 30
	var colw := (r.size.x - 84) * 0.5
	for i in CONTROLS.size():
		var pos := Vector2(42 + (i % 2) * colw, y + (i / 2) * 30)
		var kw := 0.0
		for k in CONTROLS[i][0]:
			kw += UiKit.draw_key(p, pos + Vector2(kw, 0), k, 12) + 4.0
		p.draw_string(UiKit.font("body"), pos + Vector2(kw + 6, 5), CONTROLS[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiKit.INK_DIM)


func _dist(km: float) -> String:
	return "%.1f KM" % km if Game.units_kmh else "%.1f MI" % (km / 1.609)


static func _section(ci: CanvasItem, title: String, pos: Vector2, w: float) -> void:
	var f := UiKit.font("cond", 3)
	ci.draw_string(f, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.ACCENT)
	var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	ci.draw_line(pos + Vector2(tw + 12, -5), pos + Vector2(w, -5), UiKit.INK_FAINT, 1.0)


# ------------------------------------------------------------------ behaviour

func _intro() -> void:
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_fade, "color:a", 0.0, 0.5).from(1.0)
	for i in _rows.size():
		var r := _rows[i]
		r.modulate.a = 0.0
		tw.tween_property(r, "modulate:a", 1.0, 0.35).set_delay(0.12 + i * 0.04)
	for c in [_overlay, _start_btn] + _chips:
		c.modulate.a = 0.0
		tw.tween_property(c, "modulate:a", 1.0, 0.45).set_delay(0.2)
	_car_slide = 3.0


func _set_focus(i: int) -> void:
	_focus = i
	for k in _rows.size():
		_rows[k].focused = k == i


func _set_settings_focus(i: int) -> void:
	_settings_focus = i
	for k in _settings_rows.size():
		_settings_rows[k].focused = k == i


func _move_focus(dir: int) -> void:
	var i := _focus
	for n in _rows.size():
		i = posmod(i + dir, _rows.size())
		if not _rows[i].disabled:
			break
	_set_focus(i)


func _on_row_changed(_v: int, row: int) -> void:
	match row:
		Row.MODE:
			_on_mode_changed()
		Row.TRACK:
			_on_track_changed(true)
		Row.CAR:
			_on_car_changed(_rows[Row.CAR].last_dir)
		Row.OPPONENTS:
			_opp_value = _rows[Row.OPPONENTS].index
		Row.TIME:
			_tint_backdrop()
	_overlay.queue_redraw()


func _on_mode_changed() -> void:
	var m := _rows[Row.MODE].index
	var opp := _rows[Row.OPPONENTS]
	var items := PackedStringArray()
	var cap := 7 if m == Game.Mode.SINGLE_RACE else 1
	for n in cap + 1:
		items.append("Solo" if n == 0 else "%d rival%s" % [n, "" if n == 1 else "s"])
	opp.set_items(items, mini(_opp_value, cap))
	opp.disabled = m == Game.Mode.TIME_TRIAL or m == Game.Mode.FREE_ROAM
	opp.disabled_text = "None"
	_rows[Row.LAPS].disabled = m == Game.Mode.FREE_ROAM
	_rows[Row.LAPS].disabled_text = "Endless"
	_rows[Row.TRAFFIC].disabled = m == Game.Mode.TIME_TRIAL
	_rows[Row.TRAFFIC].disabled_text = "Off"
	for r in _rows:
		r.queue_redraw()
	_overlay.queue_redraw()


func _on_track_changed(animate: bool) -> void:
	var id := Game.tracks[_rows[Row.TRACK].index]
	if not _outlines.has(id):
		_outlines[id] = ProceduralTrack.outline() if id == Game.PROCEDURAL_TRACK \
			else Nfs3Track.peek_outline(Game.track_dir(id))
	_track_map.set_outline(_outlines[id])
	var tex := _track_photo(id)
	# Cross-fade: the old photo becomes the back layer, the new one fades in over it.
	_photo_back.texture = _photo_front.texture
	_photo_back.modulate.a = _photo_front.modulate.a
	_photo_front.texture = tex
	_photo_front.modulate.a = 0.0
	if tex:
		create_tween().tween_property(_photo_front, "modulate:a", 1.0, 0.5 if animate else 0.9)
	create_tween().tween_property(_photo_back, "modulate:a", 0.0, 0.6)
	_tint_backdrop()


func _tint_backdrop() -> void:
	var night := _rows[Row.TIME].index == 1
	var tint := Color(0.22, 0.27, 0.45) if night else Color(0.42, 0.42, 0.45)
	for tr in [_photo_back, _photo_front]:
		create_tween().tween_property(tr, "self_modulate", tint, 0.4)


## The track's front-end slide, cropped to the photo, heavily blurred and used as mood
## lighting behind the showroom (the baked-in map and logo blur away).
func _track_photo(id: String) -> Texture2D:
	if _photos.has(id):
		return _photos[id]
	var tex: Texture2D = null
	if id != Game.PROCEDURAL_TRACK and Game.has_game_data():
		var n := id.trim_prefix("trk").to_int()
		var fsh := Fsh.load_file(Game.find_ci(Game.data_root, "fedata/art/slides/t%d_00.qfs" % n))
		if fsh and fsh.images.size() > 0 and fsh.images[0].get_width() >= 640:
			var img: Image = fsh.images[0].get_region(Rect2i(0, 60, 640, 322))
			img.convert(Image.FORMAT_RGBA8)
			img.resize(48, 24, Image.INTERPOLATE_BILINEAR)
			img.resize(96, 48, Image.INTERPOLATE_BILINEAR)
			img.resize(384, 192, Image.INTERPOLATE_CUBIC)
			tex = ImageTexture.create_from_image(img)
	_photos[id] = tex
	return tex


func _on_car_changed(dir: int) -> void:
	var ci := _rows[Row.CAR].index
	var data: Object = Game.load_car(Game.cars[ci].path, ci)
	_stats.set_car(data, _settings_rows[1].index == 0)
	_show_car(data)
	_car_slide = 2.2 * signf(dir) if dir != 0 else 0.0


func _show_car(data: Object) -> void:
	if _preview_car:
		_preview_car.queue_free()
		_preview_car = null
	var root := Node3D.new()
	var mat: Material = null
	if data.texture:
		var sm := ShaderMaterial.new()
		sm.shader = preload("res://shaders/car.gdshader")
		sm.set_shader_parameter("albedo_tex", data.texture)
		if data.colours.size() > 0:
			sm.set_shader_parameter("paint", data.colours[0])
		mat = sm
	# Model origins sit at different heights per car, so rest the lowest point (the tyres,
	# or the body if the wheels are baked into it) on the podium top.
	var low := INF
	for p in data.body_parts + data.wheels:
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
		mi.position = p.center
		if mat:
			mi.material_override = mat
		root.add_child(mi)
		var is_wheel: bool = p in data.wheels
		if p.mesh and (data.wheels.is_empty() or is_wheel):
			low = minf(low, p.center.y + p.mesh.get_aabb().position.y)
		# Settle on the springs like the race car at rest: the body sinks by the static
		# sag while the tyres stay on the ground, so they ride up into the arches.
		if is_wheel:
			mi.position.y += Car.STATIC_SAG
	if low != INF:
		root.position.y = PODIUM_TOP - low
		if not data.wheels.is_empty():
			root.position.y -= Car.STATIC_SAG
	# Soft contact shadow under the body.
	var shadow := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(data.half_size.x * 2.6, data.half_size.z * 2.3)
	var sm2 := ShaderMaterial.new()
	sm2.shader = _shadow_shader()
	q.material = sm2
	shadow.mesh = q
	root.add_child(shadow)
	shadow.position.y = PODIUM_TOP + 0.01 - root.position.y
	_pivot.add_child(root)
	_preview_car = root


static var _shadow_sh: Shader

static func _shadow_shader() -> Shader:
	if _shadow_sh == null:
		_shadow_sh = Shader.new()
		_shadow_sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled;
void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	ALBEDO = vec3(0.0);
	ALPHA = pow(1.0 - smoothstep(0.2, 1.0, r), 1.6) * 0.85;
}
"""
	return _shadow_sh


func _apply_settings() -> void:
	Game.quality = _settings_rows[0].index as Game.Quality
	Game.units_kmh = _settings_rows[1].index == 0
	var ci := _rows[Row.CAR].index
	_stats.set_car(Game.load_car(Game.cars[ci].path, ci), Game.units_kmh)
	_overlay.queue_redraw()


func _toggle_settings() -> void:
	if _starting:
		return
	_settings.visible = not _settings.visible
	if _settings.visible:
		_set_settings_focus(0)
		_settings.modulate.a = 0.0
		_settings_panel.position.y = (size.y - _settings_panel.size.y) * 0.5 + 24
		var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_settings, "modulate:a", 1.0, 0.2)
		tw.tween_property(_settings_panel, "position:y", (size.y - _settings_panel.size.y) * 0.5, 0.3)
	else:
		Game.save_settings()


func open_settings() -> void:
	if not _settings.visible:
		_toggle_settings()


func _quit_armed() -> bool:
	return Time.get_ticks_msec() < _quit_armed_until


func _request_quit() -> void:
	if _quit_armed():
		get_tree().quit()
		return
	_quit_armed_until = Time.get_ticks_msec() + 2500
	_layout()
	for c in _chips:
		c.queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	if _starting:
		return
	var rows := _settings_rows if _settings.visible else _rows
	var focus := _settings_focus if _settings.visible else _focus
	if e.is_action_pressed("ui_down", true):
		if _settings.visible:
			_set_settings_focus(posmod(focus + 1, rows.size()))
		else:
			_move_focus(1)
	elif e.is_action_pressed("ui_up", true):
		if _settings.visible:
			_set_settings_focus(posmod(focus - 1, rows.size()))
		else:
			_move_focus(-1)
	elif e.is_action_pressed("ui_left", true):
		rows[focus].step(-1)
	elif e.is_action_pressed("ui_right", true):
		rows[focus].step(1)
	elif e.is_action_pressed("ui_cancel"):
		if _settings.visible:
			_toggle_settings()
		else:
			_request_quit()
	elif (e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_TAB) \
			or (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_Y):
		_toggle_settings()
	elif e.is_action_pressed("ui_accept") and not _settings.visible:
		_start()
	else:
		return
	get_viewport().set_input_as_handled()


## Drag the car around with the mouse; letting go mid-drag flings it.
func _on_preview_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_dragging = e.pressed
		# Holding still before letting go shouldn't fling it with a stale speed.
		if not e.pressed and Time.get_ticks_msec() - _last_drag_ms > 80:
			_spin_vel = 0.0
	elif e is InputEventMouseMotion and _dragging and _pivot:
		_pivot.rotate_y(e.relative.x * 0.01)
		_spin_vel = clampf(e.velocity.x * 0.01, -12.0, 12.0)
		_last_drag_ms = Time.get_ticks_msec()


func _process(dt: float) -> void:
	_time += dt
	if not _dragging:
		_pivot.rotate_y(dt * _spin_vel)
		_spin_vel = UiKit.damp(_spin_vel, 0.5, 1.5, dt)
	_floor.rotation.y = _pivot.rotation.y
	if not _starting:
		_car_slide = UiKit.damp(_car_slide, 0.0, 9.0, dt)
	_mover.position.x = _car_slide
	# Slow drift on the backdrop and a breath of camera motion keep the scene alive.
	var drift := Vector2(sin(_time * 0.07), cos(_time * 0.05)) * size * 0.02
	for tr in [_photo_back, _photo_front]:
		tr.position = -size * 0.04 + drift
	_cam.position.y = CAM_Y + sin(_time * 0.3) * 0.06
	var hover: bool = _start_btn.get_meta("hover", false)
	_start_hot = UiKit.damp(_start_hot, 1.0 if hover else 0.0, 12.0, dt)
	_start_btn.queue_redraw()
	if _rows[Row.MODE].index == Game.Mode.HOT_PURSUIT:
		_overlay.queue_redraw()
	if _quit_armed_until > 0 and not _quit_armed():
		_quit_armed_until = 0
		_layout()
		for c in _chips:
			c.queue_redraw()


func _start() -> void:
	if _starting:
		return
	_starting = true
	Game.mode = _rows[Row.MODE].index as Game.Mode
	Game.track_id = Game.tracks[_rows[Row.TRACK].index]
	Game.car_index = _rows[Row.CAR].index
	Game.laps = _rows[Row.LAPS].index + 1
	Game.opponents = _opp_value
	Game.traffic = _rows[Row.TRAFFIC].index == 1
	Game.night = _rows[Row.TIME].index == 1
	Game.quality = _settings_rows[0].index as Game.Quality
	Game.units_kmh = _settings_rows[1].index == 0
	Game.save_settings()
	_start_hot = 1.0
	var loading := UiKit.label("LOADING  " + Game.track_name(Game.track_id).to_upper(), "display", 34, UiKit.INK)
	loading.modulate.a = 0.0
	_fade.add_child(loading)
	loading.position = Vector2(M, size.y - 40 - 46)
	var tw := create_tween().set_parallel()
	tw.tween_property(_fade, "color:a", 1.0, 0.35)
	tw.tween_property(loading, "modulate:a", 1.0, 0.25).set_delay(0.15)
	tw.tween_property(self, "_car_slide", -6.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	# Let the loading caption reach the screen before the (blocking) track load.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/race.tscn")
