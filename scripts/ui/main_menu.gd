extends Control
## The front end. The home screen lists what there is to do: race again with the last setup,
## one of the modes, High Stakes' tournaments, the settings. Picking a mode walks through
## three steps, each with the screen to itself: the track, the car, then the race options.
## The step bar across the top shows what has been picked and goes back to any step; Esc
## goes back one, Enter goes on. The chosen car stands on a turntable over the track's
## postcard. Mouse, keyboard and pad work throughout.

enum Screen { HOME, TRACK, CAR, OPTIONS, TOURNAMENTS }

const MODE_NOTES := [
	"Up to seven rivals over one to eight laps.",
	"One rival, and every cop in the county after you both.",
	"Just you and the clock. No rivals, no traffic.",
	"No laps, no rivals. Cruise with the traffic and the patrols.",
	"Sit back and watch the AI race your car and its rivals.",
]
const START_TEXT := ["START RACE", "START PURSUIT", "START TRIAL", "START DRIVING", "WATCH RACE"]
## What the focused race option does, under the options.
const HELP := {
	"Paint": "The colours this car came in.",
	"Upgrades": "High Stakes' tuning, each level on top of the last: suspension, then aero, then engine. How the rivals are tuned is in Settings.",
	"Layout": "Reverse runs the lap the other way round. Mirror flips the whole track, left for right.",
	"Time": "Race by day, or at night by headlights.",
	"Weather": "The track's own weather: rain on most, snow on some.",
	"Laps": "How many laps the race runs.",
	"Rivals": "AI cars on the grid with you.",
	"Traffic": "Everyday cars in their lanes, both ways. They pull over for sirens.",
}
const M := 48.0               # screen margin
const TOP := 96.0             # below the top bar
const FOOT := 70.0            # the footer: hints and the main button
const SETUP_ROW_H := 40.0
const SECTION_H := 28.0
const PODIUM_TOP := -0.595
const CAM_DIST := 14.0
const CAM_Y := 2.6
const DROP_HEIGHT := 0.6      # tyres this far above the podium when a car is dropped in
const CAR_PREVIEW_DELAY := 0.14   # s a browsed car must keep focus before its model loads

var _screen := Screen.HOME
var _mode := 0                   # the mode being set up
var _quick_mode := 0             # the one raced last, for the home screen's quick start
var _tour := {}                  # a tournament's circuit being entered: {t, cid}; {} in a race setup

var _home: MenuList
var _home_items: Array[Dictionary] = []
var _steps: StepBar
var _hints: HintBar
var _chip: HintBar               # settings, top right
var _next_btn: BigButton
var _tournaments: TournamentPanel

var _opts: Control               # the race options, in sections
var _sections: Array = []        # [title, [OptionRow]]
var _upgrade_row: OptionRow      # High Stakes' upgrades for the chosen car, remembered per car
var _paint_row: OptionRow        # its paint, by the names its fedata gives them, remembered per car
var _layout_row: OptionRow       # which way round the track: forward, reverse, mirrored (Game.LAYOUTS)
var _laps: OptionRow
var _opp: OptionRow
var _traffic: OptionRow
var _time_row: OptionRow
var _weather: OptionRow
var _opt_focus: OptionRow
var _help_y := 0.0
var _opp_value := 3              # remembered across modes that hide it

var _track_i := 0                # picked
var _car_i := 0
var _track_shown := 0            # shown: the picked one, or the one pointed at in a browser
var _car_shown := 0

var _overlay: Control
var _track_map: TrackMap
var _stats: CarStats
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
var _quit_armed_until := 0
var _starting := false
var _toast := ""
var _toast_t := 0.0
var _toast_col := UiKit.ACCENT


func _ready() -> void:
	theme = UiKit.theme()
	_track_i = maxi(Game.tracks.find(Game.track_id), 0)
	_car_i = Game.car_index
	_track_shown = _track_i
	_car_shown = _car_i
	_mode = Game.mode
	_quick_mode = Game.mode
	_postcards = TrackPostcards.new()
	add_child(_postcards)
	_build_backdrop()
	_build_showroom()
	_build_overlay()
	_build_home()
	_build_options()
	_build_browsers()
	_build_chrome()
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
	_set_track(_track_i)
	_show_car_now(_car_i)
	_go(Screen.HOME, false)
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
	# High and soft: a low one lights the grey wheel-arch liners and inner panels up blue.
	rim.rotation_degrees = Vector3(-50, 160, 0)
	rim.light_energy = 0.45
	rim.light_color = Color(0.7, 0.8, 1.0)
	_rig.add_child(rim)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	# A dark studio with softboxes, that only shows up in reflections and the fill light (the
	# backdrop stays transparent): lit panels mirror crisp highlight shapes and the sides fall
	# into shade, where an even grey dome and fill light made the paint look like porcelain.
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = _studio_shader()
	env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
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

static func _studio_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type sky;
// Soft-edged panel: 1 inside |p| < half, fading out over `soft`.
float panel(vec2 p, vec2 half, float soft) {
	vec2 q = smoothstep(half + soft, half - soft, abs(p));
	return q.x * q.y;
}
void sky() {
	vec3 d = EYEDIR;
	// Walls: near black, a touch lighter toward the ceiling; the floor darker still.
	vec3 c = mix(vec3(0.012), vec3(0.04, 0.042, 0.05), smoothstep(-0.1, 0.8, d.y));
	// A big softbox overhead, a little in front of the car.
	if (d.y > 0.2) {
		vec2 top = d.xz / d.y;
		c += vec3(2.2, 2.15, 2.05) * panel(top - vec2(0.0, 0.2), vec2(0.55, 0.3), 0.08);
	}
	// Tall strip lights either side, and a warmer low one ahead, for crisp lines down the flanks.
	float az = atan(d.x, -d.z);
	float el = d.y;
	c += vec3(1.5, 1.55, 1.7) * panel(vec2(abs(az) - 1.3, el - 0.2), vec2(0.05, 0.25), 0.03);
	c += vec3(1.1, 1.0, 0.9) * panel(vec2(az - 2.9, el - 0.12), vec2(0.35, 0.05), 0.03);
	COLOR = c;
}
"""
	return s


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


func _build_home() -> void:
	_home = MenuList.new()
	_home.activated.connect(_on_home_activated)
	_home.focus_changed.connect(func(_i): _overlay.queue_redraw())
	add_child(_home)


## The home screen's entries, with what they'd start as it stands now.
func _refresh_home() -> void:
	var key := func(it: Dictionary) -> String: return "%s%s" % [it.id, it.get("mode", "")]
	var keep: String = key.call(_home_items[_home.focus]) if not _home_items.is_empty() else "quick"
	_home_items.clear()
	var m := _quick_mode
	var rules := PackedStringArray([Game.cars[_car_i].name])
	if m != Game.Mode.FREE_ROAM:
		rules.append("%d lap%s" % [_laps.index + 1, "" if _laps.index == 0 else "s"])
	if m == Game.Mode.SINGLE_RACE or m == Game.Mode.SPECTATE or m == Game.Mode.HOT_PURSUIT:
		rules.append("%d rival%s" % [_opp_value, "" if _opp_value == 1 else "s"])
	_home_items.append({"id": "quick", "kind": "hero", "over": "Quick start  ·  " + Game.MODE_NAMES[m],
		"title": Game.track_name(Game.tracks[_track_i]), "note": "  ·  ".join(rules)})
	for i in Game.MODE_NAMES.size():
		_home_items.append({"id": "mode", "mode": i, "title": Game.MODE_NAMES[i], "note": MODE_NOTES[i],
			"gap": 10.0 if i == 0 else 0.0, "color": UiKit.COP_RED if i == Game.Mode.HOT_PURSUIT else UiKit.ACCENT})
		# The tournaments after the single race and the pursuit.
		if i == Game.Mode.HOT_PURSUIT and Game.career_data():
			var won := Game.career_won.values().filter(func(p) -> bool: return int(p) == 1).size()
			_home_items.append({"id": "tournaments", "title": "Tournaments",
				"note": "High Stakes' cups for prize money: %d of %d circuits won." % [won, Game.career_data().circuits.size()],
				"value": "$" + TournamentPanel.money(Game.career_money)})
	_home_items.append({"id": "settings", "kind": "small", "title": "Settings", "gap": 10.0, "value": "TAB"})
	_home_items.append({"id": "quit", "kind": "small", "title": "Press again to quit" if _quit_armed() else "Quit",
		"color": UiKit.COP_RED if _quit_armed() else UiKit.ACCENT})
	var focus := 0
	for k in _home_items.size():
		if key.call(_home_items[k]) == keep:
			focus = k
	_home.set_items(_home_items, focus)


func _build_options() -> void:
	_opts = Control.new()
	_opts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_opts.draw.connect(_draw_options)
	add_child(_opts)
	var nums := func(from: int, to: int) -> PackedStringArray:
		var out := PackedStringArray()
		for n in range(from, to + 1):
			out.append(str(n))
		return out
	_upgrade_row = OptionRow.new("Upgrades", PackedStringArray(Car.UPGRADE_NAMES))
	_upgrade_row.index = Game.upgrade_of(_car_i)
	_upgrade_row.changed.connect(func(i: int):
		Game.set_upgrade(_car_i, i)
		_stats.set_car(Game.car_spec(_car_shown), Game.units_kmh, Game.upgrade_of(_car_shown)))
	_layout_row = OptionRow.new("Layout", PackedStringArray(Game.LAYOUTS))
	_layout_row.index = Game.layout
	_paint_row = OptionRow.new("Paint", PackedStringArray(["Factory"]))
	_paint_row.changed.connect(func(i: int):
		Game.paints[Game.cars[_car_i].id] = i
		_show_car_now(_car_i))
	_opp_value = Game.opponents
	_laps = OptionRow.new("Laps", nums.call(1, 8))
	_laps.index = Game.laps - 1
	_opp = OptionRow.new("Rivals", nums.call(0, 7))
	_opp.index = Game.opponents
	_opp.changed.connect(func(i: int): _opp_value = i)
	_traffic = OptionRow.new("Traffic", PackedStringArray(["Off", "On"]))
	_traffic.index = int(Game.traffic)
	_time_row = OptionRow.new("Time", PackedStringArray(["Day", "Night"]))
	_time_row.index = int(Game.night)
	_time_row.changed.connect(func(_i): _show_backdrop(true); _tracks.night = _time_row.index == 1)
	_weather = OptionRow.new("Weather", PackedStringArray(["Clear", "Rain"]))
	_weather.index = int(Game.weather)
	_weather.changed.connect(func(_i): _tint_backdrop())
	_sections = [["YOUR CAR", [_paint_row, _upgrade_row]], ["TRACK", [_layout_row, _time_row, _weather]],
		["RACE", [_laps, _opp, _traffic]]]
	for s in _sections:
		for r: OptionRow in s[1]:
			r.custom_minimum_size.y = SETUP_ROW_H
			r.hovered.connect(func(): _set_opt_focus(r))
			r.changed.connect(func(_v): _update_steps(); _overlay.queue_redraw())
			_opts.add_child(r)
	_opt_focus = _paint_row


func _build_browsers() -> void:
	var postcard := func(id: String, night: bool) -> Texture2D:
		var tex := _postcards.get_postcard(id, night)
		return tex if tex else _track_photo(id)
	_tracks = TrackBrowser.new()
	_tracks.postcard = postcard
	_tracks.outline = _outline
	_tracks.focus_changed.connect(_set_track)
	_tracks.previewed.connect(func(i: int): _track_shown = i; _show_track(true))
	_tracks.confirmed.connect(func(i: int): _set_track(i); _next())
	_tracks.cancelled.connect(_back)
	add_child(_tracks)
	_cars = CarBrowser.new()
	_cars.focus_changed.connect(_set_car)
	_cars.previewed.connect(_preview_car_later)
	_cars.confirmed.connect(func(i: int): _set_car(i); _next())
	_cars.cancelled.connect(_back)
	add_child(_cars)
	_tournaments = TournamentPanel.new()
	_tournaments.postcard = postcard
	_tournaments.focus_changed.connect(_on_circuit_focus)
	_tournaments.chosen.connect(func(t: Dictionary, cid: int): _tour = {"t": t, "cid": cid}; _go(Screen.CAR))
	_tournaments.back.connect(_back)
	add_child(_tournaments)


func _build_chrome() -> void:
	_steps = StepBar.new()
	_steps.chosen.connect(_on_step_chosen)
	add_child(_steps)
	_hints = HintBar.new()
	add_child(_hints)
	_chip = HintBar.new()
	add_child(_chip)
	_next_btn = BigButton.new()
	_next_btn.pressed.connect(_next)
	add_child(_next_btn)


func _layout() -> void:
	var W := size.x
	var H := size.y
	for tr in [_photo_back, _photo_front]:
		tr.size = size * 1.08
		tr.position = -size * 0.04
	_chip.position = Vector2(W - M - _chip.size.x + 8, 32)
	_steps.position = Vector2(M + 222, 22)
	_steps.size = Vector2(_chip.position.x - 20 - _steps.position.x, 52)
	_hints.position = Vector2(M - 8, H - 30 - _hints.size.y * 0.5)
	_next_btn.size = Vector2(330, 60)
	_next_btn.position = Vector2(W - M - _next_btn.size.x + 6, H - 34 - _next_btn.size.y)
	var body_h := H - TOP - FOOT
	_home.position = Vector2(M - 22, TOP + 16)
	_home.size = Vector2(minf(450.0, W * 0.38), _home.content_height())
	_opts.position = Vector2(M - 22, TOP + 14)
	_opts.size = Vector2(minf(470.0, W * 0.38), body_h - 14)
	_layout_options()
	_cars.position = Vector2(M - 22, TOP)
	_cars.size = Vector2(minf(580.0, W * 0.46), body_h)
	_tracks.position = Vector2(M - 22, TOP)
	_tracks.size = Vector2(minf(W * 0.62, 1100.0), body_h)
	_tournaments.position = Vector2(M - 10, TOP + 8)
	_tournaments.size = Vector2(W - M * 2 + 10, H - TOP - 8 - 118)
	if _screen == Screen.TRACK:
		# The map large, beside the grid.
		var x0 := _tracks.position.x + _tracks.size.x + 40
		var mw := W - M - x0
		_track_map.size = Vector2(mw, minf(mw * 0.72, H * 0.34))
		_track_map.position = Vector2(x0, TOP + 110)
	else:
		_track_map.size = Vector2(150, 104)
		_track_map.position = Vector2(W - M - _track_map.size.x + 8, TOP + 24)
	_stats.size = Vector2(minf(460.0, W * 0.38), 62)
	_stats.position = Vector2(W - M - _stats.size.x, H - 190)
	_place_car()
	_overlay.queue_redraw()


## Put the car in the space right of whatever is down the left, a little above centre.
func _place_car() -> void:
	if not _cam:
		return
	var W := size.x
	var aspect := W / maxf(size.y, 1.0)
	var half_w := CAM_DIST * tan(deg_to_rad(_cam.fov * 0.5)) * aspect
	var left := _home.position.x + _home.size.x
	match _screen:
		Screen.CAR: left = _cars.position.x + _cars.size.x
		Screen.OPTIONS: left = _opts.position.x + _opts.size.x
	var target_x := (left + W - M) * 0.5 / W
	_cam.h_offset = -(target_x - 0.5) * 2.0 * half_w
	# ...and lift it clear of the car caption at the bottom right.
	_cam.v_offset = -CAM_DIST * tan(deg_to_rad(_cam.fov * 0.5)) * (0.2 if _screen != Screen.HOME else 0.12)


# ------------------------------------------------------------------ screens

## Show screen `s`: its panel, the step bar and hints for it, and the main button.
func _go(s: Screen, animate := true) -> void:
	if s != Screen.CAR:
		_tour = {}
	var was := _screen
	_screen = s
	_home.visible = s == Screen.HOME
	_opts.visible = s == Screen.OPTIONS
	_stats.visible = s == Screen.CAR or s == Screen.OPTIONS
	_track_map.visible = s == Screen.HOME or s == Screen.TRACK or s == Screen.OPTIONS
	_steps.visible = s != Screen.HOME
	_next_btn.visible = s != Screen.HOME
	if s == Screen.TRACK and not _tracks.visible:
		_tracks.night = _time_row.index == 1
		_tracks.open(_track_i)
	elif s != Screen.TRACK:
		_tracks.close()
	if s == Screen.CAR and not _cars.visible:
		var c: Dictionary = Game.career_data().circuits.get(_tour.cid, {}) if not _tour.is_empty() else {}
		_cars.allow = (func(i: int) -> bool: return Game.circuit_allows(c, i)) if not c.is_empty() else Callable()
		_cars.open(_car_i)
	elif s != Screen.CAR:
		_cars.close()
	if s == Screen.TOURNAMENTS and not _tournaments.visible:
		_tournaments.open()
	elif s != Screen.TOURNAMENTS:
		_tournaments.close()
	if s == Screen.OPTIONS:
		_configure_options()
	if s == Screen.HOME:
		_refresh_home()
	if not _in_tour():
		_track_shown = _track_i
		_show_track(animate)
	if s != Screen.CAR:
		_preview_car_later(_car_i)
	# The car stands in the showroom on the screens that are about it.
	var show_car := s == Screen.HOME or s == Screen.CAR or s == Screen.OPTIONS
	create_tween().tween_property(_showroom, "modulate:a", 1.0 if show_car else 0.0, 0.25 if animate else 0.0)
	_update_steps()
	_update_hints()
	_next_btn.set_text(_next_text())
	_layout()
	_show_backdrop(animate)
	_tint_backdrop()
	# (The browsers slide themselves in.)
	if animate and was != s and s != Screen.TRACK and s != Screen.CAR:
		var panel: Control = {Screen.HOME: _home, Screen.OPTIONS: _opts, Screen.TOURNAMENTS: _tournaments}[s]
		var x := panel.position.x
		panel.position.x = x - 24
		panel.modulate.a = 0.0
		var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "modulate:a", 1.0, 0.18)
		tw.tween_property(panel, "position:x", x, 0.25)


func _in_tour() -> bool:
	return _screen == Screen.TOURNAMENTS or not _tour.is_empty()


## On: the next step, or off to the race.
func _next() -> void:
	if _starting:
		return
	_next_btn.flash()
	match _screen:
		Screen.TRACK: _go(Screen.CAR)
		Screen.CAR:
			if _tour.is_empty():
				_go(Screen.OPTIONS)
			else:
				_enter_circuit()
		Screen.OPTIONS: _start()
		Screen.TOURNAMENTS: _tournaments.choose()


## Back a step (from the home screen: quit, asked twice).
func _back() -> void:
	if _starting:
		return
	match _screen:
		Screen.HOME: _request_quit()
		Screen.TRACK, Screen.TOURNAMENTS: _go(Screen.HOME)
		Screen.CAR: _go(Screen.TOURNAMENTS if not _tour.is_empty() else Screen.TRACK)
		Screen.OPTIONS: _go(Screen.CAR)


func _on_step_chosen(i: int) -> void:
	if _starting:
		return
	if i < 0:
		_go(Screen.HOME)
	elif not _tour.is_empty() or _screen == Screen.TOURNAMENTS:
		if i == 0:
			_go(Screen.TOURNAMENTS)
		elif _screen == Screen.TOURNAMENTS:
			_tournaments.choose()
	else:
		_go([Screen.TRACK, Screen.CAR, Screen.OPTIONS][i])


func _on_home_activated(i: int) -> void:
	var it: Dictionary = _home_items[i]
	match it.id:
		"quick":
			_start(true)
		"mode":
			_mode = it.mode
			_go(Screen.TRACK)
		"tournaments":
			_go(Screen.TOURNAMENTS)
		"settings":
			_open_settings()
		"quit":
			_request_quit()


func _next_text() -> String:
	match _screen:
		Screen.TRACK: return "NEXT: CAR"
		Screen.CAR:
			if not _tour.is_empty():
				var c: Dictionary = Game.career_data().circuits.get(_tour.cid, {})
				return "ENTER  ·  $" + TournamentPanel.money(c.fee) if c.get("fee", 0.0) > 0.0 else "ENTER CIRCUIT"
			return "NEXT: OPTIONS"
		Screen.OPTIONS: return START_TEXT[_mode]
		Screen.TOURNAMENTS: return "NEXT: CAR"
	return ""


func _update_steps() -> void:
	if _screen == Screen.HOME:
		return
	if _in_tour():
		var t: Dictionary = _tour.get("t", _tournaments.tournament())
		var cid: int = _tour.get("cid", _tournaments.circuit().get("id", -1))
		var label := "%s  %d" % [t.get("name", ""), t.get("circuits", []).find(cid) + 1] if not t.is_empty() else ""
		_steps.crumb_color = UiKit.ACCENT
		_steps.set_steps("TOURNAMENTS", PackedStringArray(["CIRCUIT", "CAR"]), PackedStringArray([label, Game.cars[_car_i].name]),
			0 if _screen == Screen.TOURNAMENTS else 1)
		return
	var track := Game.track_name(Game.tracks[_track_i])
	if _layout_row.index > 0:
		track += "  ·  " + Game.LAYOUTS[_layout_row.index]
	var rules := PackedStringArray()
	if _laps.visible:
		rules.append("%d LAP%s" % [_laps.index + 1, "" if _laps.index == 0 else "S"])
	if _opp.visible:
		rules.append("%d RIVAL%s" % [_opp.index, "" if _opp.index == 1 else "S"])
	rules.append(_time_row.value_text())
	if _weather.index == 1:
		rules.append(_weather.value_text())
	_steps.crumb_color = UiKit.COP_RED if _mode == Game.Mode.HOT_PURSUIT else UiKit.ACCENT
	_steps.set_steps(Game.MODE_NAMES[_mode].to_upper(), PackedStringArray(["TRACK", "CAR", "OPTIONS"]),
		PackedStringArray([track, Game.cars[_car_i].name, " · ".join(rules)]),
		{Screen.TRACK: 0, Screen.CAR: 1, Screen.OPTIONS: 2}.get(_screen, 0))


func _update_hints() -> void:
	var back := ["ESC", "BACK", _back]
	var h: Array = []
	match _screen:
		Screen.HOME:
			h = [["↑↓", "CHOOSE"], ["ENTER", "GO"], ["DRAG", "ROTATE CAR"], ["ESC", "QUIT", _request_quit]]
		Screen.TRACK:
			h = [back] + _tracks.hints() + [["", "TYPE TO SEARCH"]]
		Screen.CAR:
			h = [back] + _cars.hints() + [["DRAG", "ROTATE CAR"]]
		Screen.OPTIONS:
			h = [back, ["↑↓", "SELECT"], ["←→", "CHANGE"], ["DRAG", "ROTATE CAR"]]
		Screen.TOURNAMENTS:
			h = [back, ["↑↓", "CIRCUIT"], ["←→", "TOURNAMENT"]]
	_hints.set_hints(h)
	# Tab steps the browsers' filters, so there Settings is a click only.
	var browsing := _screen == Screen.TRACK or _screen == Screen.CAR
	_chip.set_hints([["" if browsing else "TAB", "SETTINGS", _open_settings]])
	_layout()


# ------------------------------------------------------------------ race options

## The rows that apply to the mode: hidden, not greyed out, where they don't.
func _configure_options() -> void:
	var m := _mode
	_opp.visible = m != Game.Mode.TIME_TRIAL and m != Game.Mode.FREE_ROAM
	_laps.visible = m != Game.Mode.FREE_ROAM
	_traffic.visible = m != Game.Mode.TIME_TRIAL
	_sections[2][0] = "TRAFFIC" if m == Game.Mode.FREE_ROAM else "RACE"
	# The car's paints and upgrades, which only load with the car.
	_upgrade_row.set_items(_upgrade_row.items, Game.upgrade_of(_car_i))
	var names := _paint_names(_car_i)
	_paint_row.swatches = _paint_swatches(_car_i)
	_paint_row.set_items(names, mini(Game.paint_of(_car_i), names.size() - 1))
	if not _opt_focus.visible:
		_opt_focus = _opt_nav()[0]
	_set_opt_focus(_opt_focus)
	_layout_options()


func _opt_nav() -> Array[OptionRow]:
	var out: Array[OptionRow] = []
	for s in _sections:
		for r: OptionRow in s[1]:
			if r.visible:
				out.append(r)
	return out


func _set_opt_focus(r: OptionRow) -> void:
	_opt_focus = r
	for s in _sections:
		for o: OptionRow in s[1]:
			o.focused = o == r
	_opts.queue_redraw()


func _move_opt_focus(dir: int) -> void:
	var nav := _opt_nav()
	_set_opt_focus(nav[posmod(nav.find(_opt_focus) + dir, nav.size())])


func _layout_options() -> void:
	var y := 0.0
	for s in _sections:
		var rows: Array = s[1].filter(func(r: OptionRow) -> bool: return r.visible)
		s.resize(2)
		if rows.is_empty():
			continue
		s.append(y)
		y += SECTION_H
		for r: OptionRow in rows:
			r.position = Vector2(0, y)
			r.size = Vector2(_opts.size.x, SETUP_ROW_H)
			y += SETUP_ROW_H
		y += 12
	_help_y = y + 4
	_opts.queue_redraw()


func _draw_options() -> void:
	var o := _opts
	var f := UiKit.font("cond", 3)
	for s in _sections:
		if s.size() < 3:
			continue
		var y: float = s[2] + 18
		o.draw_string(f, Vector2(22, y), s[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.ACCENT)
		var tw := f.get_string_size(s[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		o.draw_line(Vector2(34 + tw, y - 5), Vector2(o.size.x - 12, y - 5), UiKit.INK_FAINT, 1.0)
	var help: String = HELP.get(_opt_focus.caption, "")
	o.draw_rect(Rect2(22, _help_y, 3, 40), UiKit.ACCENT)
	o.draw_multiline_string(UiKit.font("body"), Vector2(36, _help_y + 15), help, HORIZONTAL_ALIGNMENT_LEFT, o.size.x - 60, 14, 3,
		UiKit.INK_DIM)


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


func _draw_overlay() -> void:
	var o := _overlay
	var W := o.size.x
	var H := o.size.y
	# Logo.
	var lf := UiKit.font("display")
	o.draw_string(lf, Vector2(M, 58), "NFS", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, UiKit.ACCENT)
	var lw := lf.get_string_size("NFS", HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	o.draw_string(UiKit.font("cond_med", 6), Vector2(M + lw + 10, 57), "REVIVAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UiKit.INK)
	UiKit.draw_slant(o, Rect2(M, 68, 132, 3), UiKit.ACCENT, 0.9)
	o.draw_string(UiKit.font("cond", 3), Vector2(M, 88), "HOT PURSUIT  ·  HIGH STAKES", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		UiKit.INK_DIM)
	# Hot Pursuit: light bar sweeping across the top edge.
	if _pursuit_lights():
		var phase := fmod(_time * 2.2, 2.0)
		var col := UiKit.COP_RED if phase < 1.0 else UiKit.COP_BLUE
		var a := 0.6 * absf(sin(_time * 14.0))
		_grad_rect(o, Rect2(0, 0, W * 0.5, 4), Color(col, a if phase < 1.0 else 0.0), Color(col, 0.0), true)
		_grad_rect(o, Rect2(W * 0.5, 0, W * 0.5, 4), Color(col, 0.0), Color(col, a if phase >= 1.0 else 0.0), true)
	match _screen:
		Screen.HOME:
			_draw_track_card(o)
			_draw_car_caption(o, H - 40)
			if not Game.has_game_data():
				o.draw_multiline_string(UiKit.font("body"), Vector2(W * 0.5, TOP + 190), "No NFS3 data found: you get the generated "
					+ "circuit and stand-in cars. Settings → Game data says where it looks.", HORIZONTAL_ALIGNMENT_LEFT, W * 0.5 - M, 14,
					3, UiKit.ACCENT)
		Screen.TRACK:
			_draw_track_detail(o)
		Screen.CAR:
			_draw_car_caption(o, _stats.position.y)
		Screen.OPTIONS:
			_draw_track_card(o)
			_draw_car_caption(o, _stats.position.y)
	if _toast_t > 0.0:
		var a := clampf(_toast_t * 3.0, 0.0, 1.0)
		var f := UiKit.font("cond", 2)
		var y := _next_btn.position.y - 18 if _next_btn.visible else H - 30
		o.draw_string(f, Vector2(W * 0.5, y + 5), _toast.to_upper(), HORIZONTAL_ALIGNMENT_RIGHT, W * 0.5 - M, 16, Color(_toast_col, a))


func _pursuit_lights() -> bool:
	if _screen == Screen.HOME:
		var it: Dictionary = _home_items[_home.focus] if _home.focus < _home_items.size() else {}
		return it.get("mode", -1) == Game.Mode.HOT_PURSUIT or (it.get("id") == "quick" and _quick_mode == Game.Mode.HOT_PURSUIT)
	return _mode == Game.Mode.HOT_PURSUIT and not _in_tour()


## Top right: track name, lengths and the map.
func _draw_track_card(o: Control) -> void:
	var W := o.size.x
	var card_w := 400.0
	var cx := W - M - card_w
	var cy := _track_map.position.y - 24
	var tid := Game.tracks[_track_shown]
	var hf0 := UiKit.font("cond", 3)
	var head := "TRACK"
	if _layout_row.index > 0:
		head += "  ·  " + Game.LAYOUTS[_layout_row.index].to_upper()
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
		if _laps.visible and _screen == Screen.OPTIONS:
			o.draw_string(bf, Vector2(cx, ty + 44), "%s  RACE" % _dist(km * (_laps.index + 1)), HORIZONTAL_ALIGNMENT_RIGHT,
				text_w, 13, UiKit.INK_DIM)


## Beside the track browser: the track in focus large, with its map.
func _draw_track_detail(o: Control) -> void:
	var x0 := _track_map.position.x
	var w := _track_map.size.x
	var id := Game.tracks[_track_shown]
	var hf := UiKit.font("cond", 3)
	o.draw_string(hf, Vector2(x0, TOP + 22), _tracks.section(id), HORIZONTAL_ALIGNMENT_LEFT, w, 13, UiKit.ACCENT)
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
	var bf := UiKit.font("cond", 2)
	for f in facts:
		o.draw_string(bf, Vector2(x0, y), f[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.INK_DIM)
		o.draw_string(UiKit.font("display"), Vector2(x0, y + 26), f[1], HORIZONTAL_ALIGNMENT_LEFT, w, 22, UiKit.INK)
		y += 52


## Bottom right: the car's showroom facts, spec line and name, standing on `y0` (the top of
## the rating bars where they're shown).
func _draw_car_caption(o: Control, y0: float) -> void:
	var W := o.size.x
	var ci := _car_shown
	var car_name: String = Game.cars[ci].name.to_upper()
	var df := UiKit.font("display")
	var fs := 58 if _screen != Screen.HOME else 48
	var left := _cars.position.x + _cars.size.x + 40 if _screen == Screen.CAR else W * 0.5
	var max_w := W - M - left
	while fs > 30 and df.get_string_size(car_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		fs -= 2
	var hf := UiKit.font("cond", 3)
	var line := _stats.spec
	var line_y := y0 - 24 - fs * 0.93
	if _screen == Screen.HOME:
		var lw := hf.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		o.draw_string(hf, Vector2(W - M - max_w, line_y), "YOUR CAR", HORIZONTAL_ALIGNMENT_RIGHT, max_w - lw - 24, 13, UiKit.ACCENT)
	o.draw_string(hf, Vector2(W - M - max_w, line_y), line, HORIZONTAL_ALIGNMENT_RIGHT, max_w, 13, UiKit.INK_DIM)
	o.draw_string(df, Vector2(W - M - max_w, y0 - 24), car_name, HORIZONTAL_ALIGNMENT_RIGHT, max_w, fs, UiKit.INK)
	if _screen == Screen.HOME:
		return
	# The car file's own showroom facts, as the original listed them.
	var spec := Game.car_spec(ci)
	var info: Dictionary = spec.info if "info" in spec else {}
	var facts := PackedStringArray()
	for k in ["engine", "power", "zero_60", "price"]:
		var v: String = info.get(k, "")
		# Asides such as "(7.3 auto)" left out.
		if v.find("(") > 0:
			v = v.left(v.find("(")).strip_edges()
		if v != "" and v.to_lower() != "n/a":
			facts.append(("0-60  " + v) if k == "zero_60" else v)
	if not facts.is_empty():
		o.draw_string(hf, Vector2(W - M - max_w, line_y - 26), "   ·   ".join(facts).to_upper(),
			HORIZONTAL_ALIGNMENT_RIGHT, max_w, 12, UiKit.INK_DIM)


func _dist(km: float) -> String:
	return "%.1f KM" % km if Game.units_kmh else "%.1f MI" % (km / 1.609)


# ------------------------------------------------------------------ setup

func _intro() -> void:
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_fade, "color:a", 0.0, 0.5).from(1.0)
	for c in [_overlay, _home, _chip, _hints]:
		c.modulate.a = 0.0
		tw.tween_property(c, "modulate:a", 1.0, 0.45).set_delay(0.15)


func _outline(id: String) -> PackedVector3Array:
	if not _outlines.has(id):
		_outlines[id] = ProceduralTrack.outline() if id == Game.PROCEDURAL_TRACK \
			else Nfs3Track.peek_outline(Game.track_dir(id))
	return _outlines[id]


func _set_track(i: int) -> void:
	_track_i = i
	_track_shown = i
	# The generated circuit can be driven either way but has no mirror image.
	_layout_row.max_index = 1 if Game.tracks[i] == Game.PROCEDURAL_TRACK else -1
	_layout_row.set_items(_layout_row.items, mini(_layout_row.index, 1) if _layout_row.max_index == 1 else _layout_row.index)
	# The weather is the track's own: rain on most, snow on some.
	var snow := _tracks.precip(Game.tracks[i]) == Nfs3Horizon.Precip.SNOW
	_weather.set_items(PackedStringArray(["Clear", "Snow" if snow else "Rain"]), _weather.index)
	_show_track(true)
	_update_steps()


## Map and backdrop for the shown track.
func _show_track(animate: bool) -> void:
	_track_map.set_outline(_outline(Game.tracks[_track_shown]))
	_show_backdrop(animate)
	_overlay.queue_redraw()


func _on_circuit_focus() -> void:
	var id := _tournaments.focus_track()
	var i := Game.tracks.find(id)
	if i >= 0:
		_track_shown = i
		_show_backdrop(true)
	_update_steps()


func _set_car(i: int) -> void:
	_car_i = i
	_preview_car_later(i)
	_update_steps()


## Car `i`'s paints by name ("Torch Red"...), as many as its model has colours.
func _paint_names(i: int) -> PackedStringArray:
	var spec := Game.car_spec(i)
	var names: Array = spec.info.get("colours", []) if "info" in spec else []
	var out := PackedStringArray()
	for n: String in names:
		out.append(n if n != "" else "Colour %d" % (out.size() + 1))
	if out.is_empty():
		out.append("Factory")
	return out


## ...and their colours (the paint areas are mid-grey, so the car files' colours are held
## at double strength: halved here to show as they come out on the car).
func _paint_swatches(i: int) -> Array[Color]:
	var out: Array[Color] = []
	var data: Object = Game.load_car(Game.cars[i].path, i)
	for c: Color in data.colours:
		out.append(Color(minf(c.r * 0.5, 1.0), minf(c.g * 0.5, 1.0), minf(c.b * 0.5, 1.0)))
	return out if out.size() == _paint_names(i).size() else []


## A browsed car: its caption and ratings at once, the model once focus rests on it.
func _preview_car_later(i: int) -> void:
	_car_shown = i
	_show_backdrop(true)
	_stats.set_car(Game.car_spec(i), Game.units_kmh, Game.upgrade_of(i))
	_car_pending = i if _preview_car == null or i != _preview_car.get_meta("car", -1) else -1
	_car_pending_t = CAR_PREVIEW_DELAY
	_overlay.queue_redraw()


func _show_car_now(i: int) -> void:
	_car_shown = i
	_car_pending = -1
	var data: Object = Game.load_car(Game.cars[i].path, i)
	_stats.set_car(data, Game.units_kmh, Game.upgrade_of(i))
	_show_car(data)
	_preview_car.set_meta("car", i)
	_overlay.queue_redraw()


func _show_car(data: Object) -> void:
	if _preview_car:
		_preview_car.queue_free()
		_preview_car = null
	# The race car itself, parked (handbrake on, no brake lights) and dropped from a little
	# height: it lands on its springs, bounces and settles at its real static sag.
	var car := Car.new()
	car.setup(data, Game.paint_tint(_car_shown, data))
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
	# Choosing a car: a High Stakes car's own showroom photo behind it.
	if _screen == Screen.CAR and _showcase_photo(_car_shown):
		tex = _showcase_photo(_car_shown)
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
	_tracks.refresh()
	_tournaments.queue_redraw()


func _tint_backdrop() -> void:
	var night := _time_row.index == 1
	var tint := Color(0.22, 0.27, 0.45) if night else Color(0.42, 0.42, 0.45)
	if _photo_front.texture and not _photos.values().has(_photo_front.texture):
		# A render already has the time of day in it: just dim it behind the showroom.
		tint = Color(0.72, 0.72, 0.75)
	if _screen == Screen.TRACK:
		tint = Color(0.9, 0.9, 0.92)
	elif _screen == Screen.TOURNAMENTS:
		tint = Color(0.45, 0.45, 0.48)
	if _weather.index == 1 and not _in_tour():
		tint = tint.darkened(0.25).lerp(Color(0.3, 0.33, 0.36), 0.3)
	for tr in [_photo_back, _photo_front]:
		create_tween().tween_property(tr, "self_modulate", tint, 0.4)


## High Stakes' showroom photos of the cars, by car id.
var _showcase := {}


## High Stakes' showroom photo of car `i` (Showcase/art/sl<car>01.qfs), or null.
func _showcase_photo(i: int) -> Texture2D:
	if not Game.is_hs_car(i) or Game.hs_root == "":
		return null
	var id: String = Game.cars[i].id.trim_prefix(Game.HS_PREFIX)
	if not _showcase.has(id):
		var fsh := Fsh.load_file(Game.find_ci(Game.find_ci(Game.hs_root, "showcase/art"), "sl%s01.qfs" % id))
		_showcase[id] = ImageTexture.create_from_image(fsh.images[0]) if fsh and not fsh.images.is_empty() else null
	return _showcase[id]


## The track's front-end slide, cropped to the photo, heavily blurred and used as mood
## lighting behind the showroom (the baked-in map and logo blur away).
func _track_photo(id: String) -> Texture2D:
	if _photos.has(id):
		return _photos[id]
	var tex: Texture2D = null
	var fsh: Fsh = null
	var top := 60
	if Game.is_hs_track(id):
		# High Stakes' own slides (FeArt/slides/tN_00.qfs), numbered in its track order.
		var n: int = Game.HS_SLIDES.get(id.trim_prefix(Game.HS_PREFIX), -1)
		if n >= 0:
			fsh = Fsh.load_file(Game.find_ci(Game.find_ci(Game.hs_root, "feart"), "slides/t%d_00.qfs" % n))
			top = 40
	elif id != Game.PROCEDURAL_TRACK and Game.has_game_data():
		var n := id.trim_prefix("trk").to_int()
		fsh = Fsh.load_file(Game.find_ci(Game.data_root, "fedata/art/slides/t%d_00.qfs" % n))
	if fsh and fsh.images.size() > 0 and fsh.images[0].get_width() >= 640:
		var img: Image = fsh.images[0].get_region(Rect2i(0, top, 640, 322))
		img.convert(Image.FORMAT_RGBA8)
		img.resize(48, 24, Image.INTERPOLATE_BILINEAR)
		img.resize(96, 48, Image.INTERPOLATE_BILINEAR)
		img.resize(384, 192, Image.INTERPOLATE_CUBIC)
		tex = ImageTexture.create_from_image(img)
	_photos[id] = tex
	return tex


func _on_settings_changed() -> void:
	_stats.set_car(Game.car_spec(_car_shown), Game.units_kmh, Game.upgrade_of(_car_shown))
	_overlay.queue_redraw()


# ------------------------------------------------------------------ overlays

func _open_settings(page := 0) -> void:
	if _starting or _settings.visible:
		return
	_settings.open(page)


## `page`: 0 general, 1 the race HUD (tools/autotest.gd).
func open_settings(page := 0) -> void:
	_open_settings(page)


## For tools/autotest.gd: "home", "track", "car", "options", "tournaments" or "circuit"
## (the car for the first tournament circuit open).
func show_screen(name: String) -> void:
	match name:
		"track": _go(Screen.TRACK, false)
		"car": _go(Screen.CAR, false)
		"options": _go(Screen.OPTIONS, false)
		"tournaments": _go(Screen.TOURNAMENTS, false)
		"circuit":
			_go(Screen.TOURNAMENTS, false)
			_tournaments.choose()
		_: _go(Screen.HOME, false)


func _open_tournaments() -> void:
	if Game.career_data():
		show_screen("tournaments")


func _open_cars() -> void:
	show_screen("car")


func _say(text: String, col := UiKit.ACCENT) -> void:
	_toast = text
	_toast_col = col
	_toast_t = 3.0
	_overlay.queue_redraw()


func _quit_armed() -> bool:
	return Time.get_ticks_msec() < _quit_armed_until


func _request_quit() -> void:
	if _quit_armed():
		get_tree().quit()
		return
	_quit_armed_until = Time.get_ticks_msec() + 2500
	_say("Press Esc again to quit", UiKit.COP_RED)
	if _screen == Screen.HOME:
		_refresh_home()


func _unhandled_input(e: InputEvent) -> void:
	if _starting or _settings.visible:
		return
	if e is InputEventKey:
		if not e.pressed:
			return
		if e.physical_keycode == KEY_TAB and not e.echo:
			_open_settings()
		elif e.physical_keycode == KEY_ESCAPE:
			if not e.echo:
				_back()
		elif _screen == Screen.OPTIONS:
			match e.physical_keycode:
				KEY_UP, KEY_W: _move_opt_focus(-1)
				KEY_DOWN, KEY_S: _move_opt_focus(1)
				KEY_LEFT, KEY_A: _opt_focus.step(-1)
				KEY_RIGHT, KEY_D: _opt_focus.step(1)
				KEY_ENTER, KEY_KP_ENTER:
					if e.alt_pressed or e.echo:
						return
					_next()
				_: return
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_Y:
		_open_settings()
	elif e.is_action_pressed("ui_cancel"):
		_back()
	elif _screen != Screen.OPTIONS:
		return
	elif e.is_action_pressed("ui_down", true):
		_move_opt_focus(1)
	elif e.is_action_pressed("ui_up", true):
		_move_opt_focus(-1)
	elif e.is_action_pressed("ui_left", true):
		_opt_focus.step(-1)
	elif e.is_action_pressed("ui_right", true):
		_opt_focus.step(1)
	elif e.is_action_pressed("ui_accept"):
		_next()
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
	if _pursuit_lights():
		_overlay.queue_redraw()
	if _toast_t > 0.0:
		_toast_t -= dt
		_overlay.queue_redraw()
	if _quit_armed_until > 0 and not _quit_armed():
		_quit_armed_until = 0
		if _screen == Screen.HOME:
			_refresh_home()


func _start(quick := false) -> void:
	if _starting:
		return
	_starting = true
	var m := _quick_mode if quick else _mode
	Game.mode = m as Game.Mode
	Game.track_id = Game.tracks[_track_i]
	Game.car_index = _car_i
	Game.laps = _laps.index + 1
	Game.opponents = _opp_value
	Game.traffic = _traffic.index == 1
	Game.night = _time_row.index == 1
	Game.weather = _weather.index == 1
	Game.layout = _layout_row.index
	Game.save_settings()
	Game.circuit_run = {}
	_launch()


## Into the chosen tournament circuit (Game.start_circuit sets its first race up) with the
## car chosen here; the rest is the circuit's.
func _enter_circuit() -> void:
	Game.car_index = _car_i
	var err := Game.start_circuit(_tour.t, _tour.cid)
	if err != "":
		_say(err, UiKit.COP_RED)
		return
	_starting = true
	_launch()


## The race scene, after the car rolls off and the loading caption fades in.
func _launch() -> void:
	_next_btn.flash()
	if _preview_car:
		_preview_car.freeze = true
		_slide_from = _preview_car.global_position
	# The race's loading screen fades in over the menu; the race scene opens on the same one.
	var loading := LoadingScreen.new()
	loading.stage("Getting ready", 0.0, 0.03)
	loading.modulate.a = 0.0
	add_child(loading)
	var tw := create_tween().set_parallel()
	tw.tween_property(loading, "modulate:a", 1.0, 0.35).set_delay(0.1)
	tw.tween_property(self, "_car_slide", -6.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	loading.hand_over()
	# Let it reach the screen before the scene change (which blocks while it loads).
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/race.tscn")
