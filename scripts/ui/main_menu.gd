extends Control
## Front end, built for a mouse and keyboard first (a pad works too). Mode tabs across the
## top; down the left the race setup: the track and car, each a click (or T / C) away from
## a browser of all of them, then one-click options. The selected car sits on a turntable
## over the track's postcard, with the track map top right and the start button bottom right.

const MODE_NOTES := [
	"Race up to seven rivals over a set number of laps.",
	"One rival, and every cop in the county after you both.",
	"Just you and the clock. No rivals, no traffic.",
	"No laps, no rivals. Cruise the track with traffic and patrols.",
	"Sit back and watch the AI race your car and its rivals.",
]
const M := 48.0               # screen margin
const TOP := 88.0             # below the top bar
const PODIUM_TOP := -0.595
const CAM_DIST := 14.0
const CAM_Y := 2.6
const DROP_HEIGHT := 0.6      # tyres this far above the podium when a car is dropped in
const CAR_PREVIEW_DELAY := 0.14   # s a browsed car must keep focus before its model loads

var _tabs: TabStrip
var _left: Control
var _track_row: PickerRow
var _car_row: PickerRow
var _laps: OptionRow
var _opp: OptionRow
var _traffic: OptionRow
var _time_row: OptionRow
var _weather: OptionRow
var _nav: Array = []             # the setup rows in focus order (PickerRows, then OptionRows)
var _focus := 0
var _opp_value := 3              # remembered across modes that cap or hide it

var _track_i := 0                # picked
var _car_i := 0
var _track_shown := 0            # shown: the picked one, or the one in focus in a browser
var _car_shown := 0

var _overlay: Control
var _track_map: TrackMap
var _stats: CarStats
var _start_btn: Control
var _chips: Array[Control] = []
var _settings: SettingsPanel
var _tracks: TrackBrowser
var _cars: CarBrowser
var _fade: ColorRect
var _photo_back: TextureRect
var _photo_front: TextureRect
var _photo_drift: Node2D         # carries the photos' drift: a Control's position snaps to whole pixels

var _showroom: SubViewportContainer
var _preview: SubViewport
var _cam: Camera3D
var _rig: Node3D                 # camera and lights orbiting the car (a physics body can't ride a turntable)
var _floor: MeshInstance3D
var _preview_car: Car            # a real, simulated car dropped onto the podium, so it lands and sags
var _shadow: MeshInstance3D
var _spin_vel := 0.5             # orbit speed, rad/s; a flick sets it, then it eases back
var _dragging := false
var _last_drag_ms := 0
var _car_slide := 0.0            # start: how far the car has slid out
var _slide_from := Vector3.ZERO
var _car_pending := -1           # car to load into the showroom once browsing settles on it
var _car_pending_t := 0.0

var _photos := {}                # track id -> Texture2D (or null)
var _postcards: TrackPostcards   # rendered stills of the tracks, filled in in the background
var _outlines := {}              # track id -> PackedVector3Array
var _time := 0.0
var _start_hot := 0.0            # start-button hover/flash
var _quit_armed_until := 0
var _starting := false


func _ready() -> void:
	theme = UiKit.theme()
	_track_i = maxi(Game.tracks.find(Game.track_id), 0)
	_car_i = Game.car_index
	_track_shown = _track_i
	_car_shown = _car_i
	_postcards = TrackPostcards.new()
	add_child(_postcards)
	_build_backdrop()
	_build_showroom()
	_build_overlay()
	_build_tabs()
	_build_setup()
	_build_start()
	_build_chips()
	_build_browsers()
	_settings = SettingsPanel.new()
	_settings.closed.connect(func(): _layout())
	_settings.changed.connect(_on_settings_changed)
	add_child(_settings)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	resized.connect(_layout)
	_postcards.rendered.connect(_on_postcard_rendered)
	for id in Game.tracks:
		_postcards.request(id)
	_on_mode_changed()
	_show_track(false)
	_update_track_row(0)
	_show_car_now(_car_i)
	_update_car_row(0)
	_layout()
	_set_focus(0)
	_intro()


# ------------------------------------------------------------------ building

func _build_backdrop() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_photo_drift = Node2D.new()
	add_child(_photo_drift)
	for i in 2:
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.modulate.a = 0.0
		_photo_drift.add_child(tr)
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
	_showroom = SubViewportContainer.new()
	_showroom.stretch = true
	_showroom.set_anchors_preset(Control.PRESET_FULL_RECT)
	_showroom.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_showroom.gui_input.connect(_on_preview_input)
	add_child(_showroom)
	_preview = SubViewport.new()
	_preview.own_world_3d = true
	_preview.transparent_bg = true
	_preview.msaa_3d = Viewport.MSAA_4X if Game.quality == Game.Quality.HIGH else Viewport.MSAA_2X \
		if Game.quality == Game.Quality.MEDIUM else Viewport.MSAA_DISABLED
	_showroom.add_child(_preview)

	var w := Node3D.new()
	_preview.add_child(w)
	_rig = Node3D.new()
	w.add_child(_rig)
	_cam = Camera3D.new()
	_cam.fov = 30
	_cam.position = Vector3(0, CAM_Y, CAM_DIST)
	_cam.rotation_degrees = Vector3(-9.5, 0, 0)
	_rig.add_child(_cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 30, 0)
	key.light_energy = 1.15
	key.light_color = Color(1.0, 0.97, 0.92)
	_rig.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 160, 0)
	rim.light_energy = 0.9
	rim.light_color = Color(0.7, 0.8, 1.0)
	_rig.add_child(rim)
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
	# The podium top is solid ground (layer 1, what the wheel rays hit).
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(11, 1, 11)
	gs.shape = gb
	gs.position.y = PODIUM_TOP - 0.5
	ground.add_child(gs)
	w.add_child(ground)
	_shadow = MeshInstance3D.new()
	var q := PlaneMesh.new()
	var sm := ShaderMaterial.new()
	sm.shader = _shadow_shader()
	# Both it and the floor are transparent and coplanar: depth sorting by AABB centre flips
	# as the camera orbits and the floor would paint over it. Always draw it after the floor.
	sm.render_priority = 1
	q.material = sm
	_shadow.mesh = q
	_shadow.visible = false
	w.add_child(_shadow)


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


func _build_tabs() -> void:
	_tabs = TabStrip.new(PackedStringArray(Game.MODE_NAMES), TabStrip.Style.TABS)
	_tabs.keys = PackedStringArray(["Q", "E"])
	_tabs.set_items(_tabs.items, Game.mode)
	_tabs.changed.connect(func(_i): _on_mode_changed())
	add_child(_tabs)


func _build_setup() -> void:
	_left = Control.new()
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_left)
	_track_row = PickerRow.new("Track", "T")
	_track_row.browse_text = "ALL %d" % Game.tracks.size()
	_track_row.browse.connect(_open_tracks)
	_track_row.stepped.connect(func(d: int): _set_track(posmod(_track_i + d, Game.tracks.size()), d))
	_car_row = PickerRow.new("Car", "C")
	_car_row.browse_text = "ALL %d" % Game.cars.size()
	_car_row.browse.connect(_open_cars)
	_car_row.stepped.connect(func(d: int): _set_car(posmod(_car_i + d, Game.cars.size()), d))
	var nums := func(from: int, to: int) -> PackedStringArray:
		var out := PackedStringArray()
		for n in range(from, to + 1):
			out.append(str(n))
		return out
	_opp_value = Game.opponents
	_laps = OptionRow.new("Laps", nums.call(1, 8))
	_laps.index = Game.laps - 1
	_laps.disabled_text = "Endless"
	_opp = OptionRow.new("Rivals", nums.call(0, 7))
	_opp.index = Game.opponents
	_opp.disabled_text = "None"
	_opp.changed.connect(func(i: int): _opp_value = i)
	_traffic = OptionRow.new("Traffic", PackedStringArray(["Off", "On"]))
	_traffic.index = int(Game.traffic)
	_traffic.disabled_text = "Off"
	_time_row = OptionRow.new("Time", PackedStringArray(["Day", "Night"]))
	_time_row.index = int(Game.night)
	_time_row.changed.connect(func(_i): _show_backdrop(true); _update_track_row(0))
	_weather = OptionRow.new("Weather", PackedStringArray(["Clear", "Rain"]))
	_weather.index = int(Game.weather)
	_weather.changed.connect(func(_i): _tint_backdrop())
	_nav = [_track_row, _car_row, _laps, _opp, _traffic, _time_row, _weather]
	for i in _nav.size():
		var c: Control = _nav[i]
		c.hovered.connect(func(): if not c.get("disabled"): _set_focus(i))
		if c is OptionRow:
			c.changed.connect(func(_v): _overlay.queue_redraw())
		_left.add_child(c)


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
	for def in [["TAB", "SETTINGS", _open_settings], ["ESC", "QUIT", _request_quit]]:
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


func _build_browsers() -> void:
	_tracks = TrackBrowser.new()
	_tracks.postcard = func(id: String, night: bool) -> Texture2D:
		var tex := _postcards.get_postcard(id, night)
		return tex if tex else _track_photo(id)
	_tracks.outline = _outline
	_tracks.focus_changed.connect(func(i: int): _track_shown = i; _show_track(true))
	_tracks.confirmed.connect(func(i: int): _close_browser(); _set_track(i, 0))
	_tracks.cancelled.connect(func(): _close_browser(); _track_shown = _track_i; _show_track(true))
	add_child(_tracks)
	_cars = CarBrowser.new()
	_cars.focus_changed.connect(_preview_car_later)
	_cars.confirmed.connect(func(i: int): _close_browser(); _set_car(i, 0))
	_cars.cancelled.connect(func(): _close_browser(); _preview_car_later(_car_i))
	add_child(_cars)


func _layout() -> void:
	var W := size.x
	var H := size.y
	for tr in [_photo_back, _photo_front]:
		tr.size = size * 1.08
		tr.position = -size * 0.04
	_tabs.position = Vector2(M + 228, 22)
	_tabs.size = Vector2(_tabs.custom_minimum_size.x, 44)
	_left.position = Vector2(M - 22, TOP + 30)
	_left.size = Vector2(minf(470.0, W * 0.38), H - TOP - 30 - 90)
	var y := 0.0
	for c: Control in _nav:
		if c == _laps:
			y += 10
		c.position = Vector2(0, y)
		c.size = Vector2(_left.size.x, c.custom_minimum_size.y)
		y += c.custom_minimum_size.y
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
	_cars.position = Vector2(M - 22, TOP)
	_cars.size = Vector2(minf(580.0, W * 0.46), H - TOP - 24)
	_tracks.position = Vector2(M - 22, TOP)
	_tracks.size = Vector2(minf(W * 0.64, 1100.0), H - TOP - 24)
	if _tracks.visible:
		# The map large, beside the grid.
		var x0 := _tracks.position.x + _tracks.size.x + 40
		var mw := W - M - x0
		_track_map.size = Vector2(mw, minf(mw * 0.72, H * 0.36))
		_track_map.position = Vector2(x0, TOP + 118)
	else:
		_track_map.size = Vector2(150, 104)
		_track_map.position = Vector2(W - M - _track_map.size.x + 8, TOP + 24)
	_place_car()
	_overlay.queue_redraw()


## Put the car in the space right of whatever is down the left, a little above centre.
func _place_car() -> void:
	if not _cam:
		return
	var W := size.x
	var aspect := W / maxf(size.y, 1.0)
	var half_w := CAM_DIST * tan(deg_to_rad(_cam.fov * 0.5)) * aspect
	var left := _cars.position.x + _cars.size.x if _cars.visible else _left.position.x + _left.size.x
	var target_x := (left + W - M) * 0.5 / W
	_cam.h_offset = -(target_x - 0.5) * 2.0 * half_w
	# ...and lift it clear of the car caption at the bottom right.
	_cam.v_offset = -CAM_DIST * tan(deg_to_rad(_cam.fov * 0.5)) * 0.2


# ------------------------------------------------------------------ drawing

func _draw_shade(c: Control) -> void:
	var W := c.size.x
	var H := c.size.y
	var clear := Color(UiKit.BG, 0.0)
	var dark := Color(UiKit.BG, 0.92)
	# Left column scrim, top and bottom bands, so text reads over any photo.
	_grad_rect(c, Rect2(0, 0, 640, H), dark, clear, true)
	_grad_rect(c, Rect2(0, 0, W, 150), Color(UiKit.BG, 0.75), clear, false)
	_grad_rect(c, Rect2(0, H - 300, W, 300), clear, Color(UiKit.BG, 0.95), false)


static func _grad_rect(ci: CanvasItem, r: Rect2, from: Color, to: Color, horizontal: bool) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var cols := PackedColorArray([from, to, to, from]) if horizontal else PackedColorArray([from, from, to, to])
	ci.draw_polygon(pts, cols)


func _browsing() -> bool:
	return _tracks.visible or _cars.visible


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
	if _tabs.index == Game.Mode.HOT_PURSUIT:
		var phase := fmod(_time * 2.2, 2.0)
		var col := UiKit.COP_RED if phase < 1.0 else UiKit.COP_BLUE
		var a := 0.6 * absf(sin(_time * 14.0))
		_grad_rect(o, Rect2(0, 0, W * 0.5, 4), Color(col, a if phase < 1.0 else 0.0), Color(col, 0.0), true)
		_grad_rect(o, Rect2(W * 0.5, 0, W * 0.5, 4), Color(col, 0.0), Color(col, a if phase >= 1.0 else 0.0), true)
	if _tracks.visible:
		_draw_track_detail(o)
		return
	if not _cars.visible:
		# What the mode is, over the setup.
		o.draw_string(UiKit.font("body"), Vector2(M, TOP + 16), MODE_NOTES[_tabs.index], HORIZONTAL_ALIGNMENT_LEFT,
			_left.size.x - 20, 15, UiKit.INK_DIM)
		var hints := [["↑↓", "SELECT"], ["←→", "CHANGE"], ["T", "TRACKS"], ["C", "CARS"], ["DRAG", "ROTATE CAR"]]
		UiKit.draw_hints(o, Vector2(M, H - 40 - 30), hints)
	_draw_track_card(o)
	_draw_car_caption(o)


## Top right: track name, lengths and the map.
func _draw_track_card(o: Control) -> void:
	var W := o.size.x
	var card_w := 400.0
	var cx := W - M - card_w
	var cy := _track_map.position.y - 24
	var tid := Game.tracks[_track_shown]
	var hf0 := UiKit.font("cond", 3)
	var head := "TRACK %02d / %02d" % [_track_shown + 1, Game.tracks.size()]
	o.draw_string(hf0, Vector2(cx, cy), head, HORIZONTAL_ALIGNMENT_RIGHT, card_w, 13, UiKit.ACCENT)
	var head_w := hf0.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	o.draw_line(Vector2(cx + 60, cy - 5), Vector2(W - M - head_w - 14, cy - 5), UiKit.INK_FAINT, 1.0)
	var text_w := _track_map.position.x - 18 - cx
	var ty := _track_map.position.y + 38
	var df := UiKit.font("display")
	var name := Game.track_name(tid).to_upper()
	var fs := 30
	while fs > 18 and df.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > text_w:
		fs -= 2
	o.draw_string(df, Vector2(cx, ty), name, HORIZONTAL_ALIGNMENT_RIGHT, text_w, fs, UiKit.INK)
	var km := _track_map.length_m / 1000.0
	var bf := UiKit.font("cond", 2)
	if _track_map.length_m > 0:
		o.draw_string(bf, Vector2(cx, ty + 24), "%s  PER LAP" % _dist(km), HORIZONTAL_ALIGNMENT_RIGHT, text_w, 13, UiKit.INK_DIM)
		if not _laps.disabled:
			o.draw_string(bf, Vector2(cx, ty + 44), "%s  RACE" % _dist(km * (_laps.index + 1)), HORIZONTAL_ALIGNMENT_RIGHT,
				text_w, 13, UiKit.INK_DIM)


## Beside the track browser: the focused track large, with its map.
func _draw_track_detail(o: Control) -> void:
	var x0 := _track_map.position.x
	var w := _track_map.size.x
	var id := Game.tracks[_track_shown]
	var hf := UiKit.font("cond", 3)
	o.draw_string(hf, Vector2(x0, TOP + 22), "TRACK %02d / %02d  ·  %s" % [_track_shown + 1, Game.tracks.size(),
		_tracks.section(id)], HORIZONTAL_ALIGNMENT_LEFT, w, 13, UiKit.ACCENT)
	var df := UiKit.font("display")
	var name := Game.track_name(id).to_upper()
	var fs := 48
	while fs > 24 and df.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
		fs -= 2
	o.draw_string(df, Vector2(x0, TOP + 68), name, HORIZONTAL_ALIGNMENT_LEFT, w, fs, UiKit.INK)
	var y := _track_map.position.y + _track_map.size.y + 34
	var km := _track_map.length_m / 1000.0
	var snow := _tracks.precip(id) == Nfs3Horizon.Precip.SNOW
	var facts := [["LAP", _dist(km) if km > 0 else "—"], ["WEATHER", "CLEAR OR SNOW" if snow else "CLEAR OR RAIN"]]
	if not _laps.disabled and km > 0:
		var n := _laps.index + 1
		facts.insert(1, ["RACE · %d LAP%s" % [n, "" if n == 1 else "S"], _dist(km * n)])
	var bf := UiKit.font("cond", 2)
	for f in facts:
		o.draw_string(bf, Vector2(x0, y), f[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.INK_DIM)
		o.draw_string(UiKit.font("display"), Vector2(x0, y + 26), f[1], HORIZONTAL_ALIGNMENT_LEFT, w, 22, UiKit.INK)
		y += 52


## Bottom right: the car's number, spec line and name over its rating bars.
func _draw_car_caption(o: Control) -> void:
	var W := o.size.x
	var H := o.size.y
	var ci := _car_shown
	var car_name: String = Game.cars[ci].name.to_upper()
	var df := UiKit.font("display")
	var fs := 58
	var max_w := W - M - (_cars.position.x + _cars.size.x + 40) if _cars.visible else W * 0.5
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
	var txt := "START RACE" if _tabs.index != Game.Mode.SPECTATE else "WATCH RACE"
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


func _dist(km: float) -> String:
	return "%.1f KM" % km if Game.units_kmh else "%.1f MI" % (km / 1.609)


# ------------------------------------------------------------------ setup

func _intro() -> void:
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_fade, "color:a", 0.0, 0.5).from(1.0)
	for i in _nav.size():
		var r: Control = _nav[i]
		r.modulate.a = 0.0
		tw.tween_property(r, "modulate:a", 1.0, 0.35).set_delay(0.12 + i * 0.04)
	for c in [_overlay, _start_btn, _tabs] + _chips:
		c.modulate.a = 0.0
		tw.tween_property(c, "modulate:a", 1.0, 0.45).set_delay(0.2)


func _set_focus(i: int) -> void:
	_focus = i
	for k in _nav.size():
		_nav[k].focused = k == i


func _move_focus(dir: int) -> void:
	var i := _focus
	for n in _nav.size():
		i = posmod(i + dir, _nav.size())
		if not _nav[i].get("disabled"):
			break
	_set_focus(i)


func _on_mode_changed() -> void:
	var m := _tabs.index
	var cap := 7 if m == Game.Mode.SINGLE_RACE or m == Game.Mode.SPECTATE else 1
	_opp.max_index = cap
	_opp.set_items(_opp.items, mini(_opp_value, cap))
	_opp.disabled = m == Game.Mode.TIME_TRIAL or m == Game.Mode.FREE_ROAM
	_laps.disabled = m == Game.Mode.FREE_ROAM
	_traffic.disabled = m == Game.Mode.TIME_TRIAL
	for r in _nav:
		r.queue_redraw()
	if _nav[_focus].get("disabled"):
		_move_focus(1)
	_start_btn.queue_redraw()
	_overlay.queue_redraw()


func _outline(id: String) -> PackedVector3Array:
	if not _outlines.has(id):
		_outlines[id] = ProceduralTrack.outline() if id == Game.PROCEDURAL_TRACK \
			else Nfs3Track.peek_outline(Game.track_dir(id))
	return _outlines[id]


func _set_track(i: int, dir: int) -> void:
	_track_i = i
	_track_shown = i
	_show_track(true)
	_update_track_row(dir)


## Map and backdrop for the shown track.
func _show_track(animate: bool) -> void:
	_track_map.set_outline(_outline(Game.tracks[_track_shown]))
	_show_backdrop(animate)
	_overlay.queue_redraw()


func _update_track_row(dir: int) -> void:
	var id := Game.tracks[_track_i]
	var km := 0.0
	var pts := _outline(id)
	for k in pts.size():
		km += pts[k].distance_to(pts[(k + 1) % pts.size()]) / 1000.0
	var sub := _tracks.section(id)
	if km > 0:
		sub += "  ·  " + _dist(km)
	_track_row.set_value(Game.track_name(id), sub, dir)
	var tex := _postcards.get_postcard(id, _time_row.index == 1)
	_track_row.thumb = tex if tex else _track_photo(id)
	# The weather is the track's own: rain on most, snow on some.
	var snow := _tracks.precip(id) == Nfs3Horizon.Precip.SNOW
	_weather.set_items(PackedStringArray(["Clear", "Snow" if snow else "Rain"]), _weather.index)


func _set_car(i: int, dir: int) -> void:
	_car_i = i
	_update_car_row(dir)
	_show_car_now(i)


func _update_car_row(dir: int) -> void:
	var g := Game.car_class(_car_i)
	var police := Game.is_pursuit_car(_car_i)
	var sub: String = "POLICE" if police else ["CLASS A", "CLASS B", "CLASS C", "BONUS"][g]
	sub += "  ·  " + ("HIGH STAKES" if Game.is_hs_car(_car_i) else "NFS III")
	_car_row.set_value(Game.cars[_car_i].name, sub, dir)
	_car_row.badge = "P" if police else "ABCX"[g]
	_car_row.badge_color = UiKit.COP_BLUE if police else UiKit.ACCENT


## A browsed car: its caption and ratings at once, the model once focus rests on it.
func _preview_car_later(i: int) -> void:
	_car_shown = i
	_stats.set_car(Game.car_spec(i), Game.units_kmh)
	_car_pending = i
	_car_pending_t = CAR_PREVIEW_DELAY
	_overlay.queue_redraw()


func _show_car_now(i: int) -> void:
	_car_shown = i
	_car_pending = -1
	var data: Object = Game.load_car(Game.cars[i].path, i)
	_stats.set_car(data, Game.units_kmh)
	_show_car(data)
	_overlay.queue_redraw()


func _show_car(data: Object) -> void:
	if _preview_car:
		_preview_car.queue_free()
		_preview_car = null
	# The race car itself, parked (handbrake on, no brake lights) and dropped from a little
	# height: it lands on its springs, bounces and settles at its real static sag.
	var car := Car.new()
	car.setup(data)
	car.handbrake = true
	car.set_headlights(false)
	_floor.get_parent().add_child(car)
	car.reset_to(Transform3D(Basis(), Vector3(0, PODIUM_TOP, 0)), DROP_HEIGHT)
	_preview_car = car
	(_shadow.mesh as PlaneMesh).size = Vector2(data.half_size.x * 2.6, data.half_size.z * 2.3)
	_shadow.visible = true


## The shown track's rendered postcard for the time of day; the blurred front-end slide
## until that has been rendered.
func _show_backdrop(animate: bool) -> void:
	var id := Game.tracks[_track_shown]
	var tex := _postcards.get_postcard(id, _time_row.index == 1)
	if tex == null:
		tex = _track_photo(id)
	if tex == _photo_front.texture:
		return
	# Cross-fade: the old photo becomes the back layer, the new one fades in over it.
	_photo_back.texture = _photo_front.texture
	_photo_back.modulate.a = _photo_front.modulate.a
	_photo_front.texture = tex
	_photo_front.modulate.a = 0.0
	if tex:
		create_tween().tween_property(_photo_front, "modulate:a", 1.0, 0.35 if animate else 0.9)
	create_tween().tween_property(_photo_back, "modulate:a", 0.0, 0.45)
	_tint_backdrop()


func _on_postcard_rendered(id: String) -> void:
	if id == Game.tracks[_track_shown]:
		_show_backdrop(true)
	if id == Game.tracks[_track_i]:
		_update_track_row(0)
	_tracks.refresh()


func _tint_backdrop() -> void:
	var night := _time_row.index == 1
	var tint := Color(0.22, 0.27, 0.45) if night else Color(0.42, 0.42, 0.45)
	if _photo_front.texture and not _photos.values().has(_photo_front.texture):
		# A render already has the time of day in it: just dim it behind the showroom.
		tint = Color(0.72, 0.72, 0.75)
	if _tracks.visible:
		tint = Color(0.9, 0.9, 0.92)
	if _weather.index == 1:
		tint = tint.darkened(0.25).lerp(Color(0.3, 0.33, 0.36), 0.3)
	for tr in [_photo_back, _photo_front]:
		create_tween().tween_property(tr, "self_modulate", tint, 0.4)


## The track's front-end slide, cropped to the photo, heavily blurred and used as mood
## lighting behind the showroom (the baked-in map and logo blur away).
func _track_photo(id: String) -> Texture2D:
	if _photos.has(id):
		return _photos[id]
	var tex: Texture2D = null
	if id != Game.PROCEDURAL_TRACK and not Game.is_hs_track(id) and Game.has_game_data():
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


func _on_settings_changed() -> void:
	_stats.set_car(Game.car_spec(_car_shown), Game.units_kmh)
	_update_track_row(0)
	_overlay.queue_redraw()


# ------------------------------------------------------------------ overlays

func _open_tracks() -> void:
	if _starting or _browsing():
		return
	_tracks.current = _track_i
	_tracks.night = _time_row.index == 1
	_open_browser(_tracks, _track_i)
	# The backdrop is the preview here: let it through, and put the car away.
	create_tween().tween_property(_showroom, "modulate:a", 0.0, 0.2)
	_tint_backdrop()


func _open_cars() -> void:
	if _starting or _browsing():
		return
	_cars.current = _car_i
	_open_browser(_cars, _car_i)


func _open_browser(b: BrowserBase, item: int) -> void:
	_left.visible = false
	_start_btn.visible = false
	_stats.visible = b == _cars
	b.open(item)
	_layout()


func _close_browser() -> void:
	_tracks.close()
	_cars.close()
	_left.visible = true
	_start_btn.visible = true
	_stats.visible = true
	if _showroom.modulate.a < 1.0:
		create_tween().tween_property(_showroom, "modulate:a", 1.0, 0.25)
	_layout()
	_tint_backdrop()


func _open_settings() -> void:
	if _starting or _browsing():
		return
	_settings.open()


## For tools/autotest.gd ("--autotest menu --settings").
func open_settings() -> void:
	if not _settings.visible:
		_open_settings()


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


func _step_focused(dir: int) -> void:
	var c = _nav[_focus]
	if c is PickerRow:
		c.stepped.emit(dir)
	else:
		c.step(dir)


func _browse_focused() -> bool:
	if _nav[_focus] == _track_row:
		_open_tracks()
	elif _nav[_focus] == _car_row:
		_open_cars()
	else:
		return false
	return true


func _unhandled_input(e: InputEvent) -> void:
	if _starting or _browsing() or _settings.visible:
		return
	if e is InputEventKey:
		if not e.pressed:
			return
		match e.physical_keycode:
			KEY_UP, KEY_W:
				_move_focus(-1)
			KEY_DOWN, KEY_S:
				_move_focus(1)
			KEY_LEFT, KEY_A:
				_step_focused(-1)
			KEY_RIGHT, KEY_D:
				_step_focused(1)
			KEY_Q:
				if not e.echo: _tabs.step(-1)
			KEY_E:
				if not e.echo: _tabs.step(1)
			KEY_T:
				_open_tracks()
			KEY_C:
				_open_cars()
			KEY_SPACE:
				if not _browse_focused():
					return
			KEY_ENTER, KEY_KP_ENTER:
				if e.alt_pressed or e.echo:
					return
				_start()
			KEY_TAB:
				if not e.echo: _open_settings()
			KEY_ESCAPE:
				if not e.echo: _request_quit()
			_:
				return
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("ui_down", true):
		_move_focus(1)
	elif e.is_action_pressed("ui_up", true):
		_move_focus(-1)
	elif e.is_action_pressed("ui_left", true):
		_step_focused(-1)
	elif e.is_action_pressed("ui_right", true):
		_step_focused(1)
	elif e is InputEventJoypadButton and e.pressed:
		match e.button_index:
			JOY_BUTTON_A: _start()
			JOY_BUTTON_B: _request_quit()
			JOY_BUTTON_X: _browse_focused()
			JOY_BUTTON_Y: _open_settings()
			JOY_BUTTON_LEFT_SHOULDER: _tabs.step(-1)
			JOY_BUTTON_RIGHT_SHOULDER: _tabs.step(1)
			_: return
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
	elif e is InputEventMouseMotion and _dragging and _rig:
		_rig.rotate_y(-e.relative.x * 0.01)
		_spin_vel = clampf(e.velocity.x * 0.01, -12.0, 12.0)
		_last_drag_ms = Time.get_ticks_msec()


func _process(dt: float) -> void:
	_time += dt
	if not _dragging:
		_rig.rotate_y(-dt * _spin_vel)
		_spin_vel = UiKit.damp(_spin_vel, 0.5, 1.5, dt)
	if _car_pending >= 0:
		_car_pending_t -= dt
		if _car_pending_t <= 0.0:
			_show_car_now(_car_pending)
	if _preview_car:
		if _starting:
			# Drive off screen: slide the (frozen) car out along the camera's x.
			_preview_car.global_position = _slide_from + _rig.basis.x * _car_slide
		var xf := _preview_car.get_global_transform_interpolated()
		_shadow.position = Vector3(xf.origin.x, PODIUM_TOP + 0.01, xf.origin.z)
		_shadow.rotation.y = xf.basis.get_euler().y
	# Slow drift on the backdrop and a breath of camera motion keep the scene alive.
	_photo_drift.position = Vector2(sin(_time * 0.07), cos(_time * 0.05)) * size * 0.02
	_cam.position.y = CAM_Y + sin(_time * 0.3) * 0.06
	var hover: bool = _start_btn.get_meta("hover", false)
	_start_hot = UiKit.damp(_start_hot, 1.0 if hover else 0.0, 12.0, dt)
	_start_btn.queue_redraw()
	if _tabs.index == Game.Mode.HOT_PURSUIT:
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
	Game.mode = _tabs.index as Game.Mode
	Game.track_id = Game.tracks[_track_i]
	Game.car_index = _car_i
	Game.laps = _laps.index + 1
	Game.opponents = _opp_value
	Game.traffic = _traffic.index == 1
	Game.night = _time_row.index == 1
	Game.weather = _weather.index == 1
	Game.save_settings()
	_start_hot = 1.0
	if _preview_car:
		_preview_car.freeze = true
		_slide_from = _preview_car.global_position
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
