class_name Hud
extends CanvasLayer
## Race HUD in the front end's style (see UiKit): segmented tach with speed and
## gear, timing tower, lap counter, minimap, framed rear-view mirror, banner
## messages and countdown, plus the pause and results screens. Each part can be hidden
## (Game.hud_shows, Settings -> HUD, also from the pause menu); F1 hides the lot.

const RED := UiKit.COP_RED
const GO := Color(0.35, 1.0, 0.5)
const M := 36.0
# An unlit ticket / heat pip: dark, so it reads over sky and road alike.

var race: Node
var player: Car:
	set(v):
		player = v
		if _classic:
			_classic.car = v
## High Stakes' own dials in place of the tach (Settings -> HUD), or null.
var _classic: ClassicGauges
var pursuit := false

var _root: Control
var _draw: Control
# The moving parts are drawn in as few batches as possible (a weak GPU and CPU pay per draw
# call, and every shape or change of font size is one): all the shapes in one triangle array
# on _draw, then all the text's outlines and then its fills on two layers over it, grouped by
# font and size.
var _text_ol: Control
var _text_fg: Control
var _texts := {}         # font and size -> [[pos, text, align, width, colour, outline size, outline colour]]
var _tri_pts := PackedVector2Array()
var _tri_cols := PackedColorArray()
var _tri_idx := PackedInt32Array()
var _static: Control
var _static_key := []          # what the static layer was drawn for; redrawn when it changes
var _tach_segs: Array[PackedVector2Array] = []   # the tach's segments as polygons, at _tach_c
var _tach_c := Vector2.INF
var _mirror: TextureRect
var _mirror_on := true   # the rear-view mirror is wanted (M): this one, or in the in-car view the car's own
var _mirror_vp: SubViewport
var _mirror_cam: Camera3D
var _loading: LoadingScreen
var _pause: Control
var _pause_list: ActionList
var _settings: SettingsPanel
var _results: Control
var _results_list: ActionList
var _results_data := {}
var _results_t := 0.0

var _msg := ""
var _msg_kind := ""
var _msg_t := 0.0
var _msg_len := 1.0
var _chat := {}               # a rival's word: {name, color, text}
var _chat_t := 0.0
const CHAT_TIME := 3.2
var _count := 0.0
var _hint_t := 0.0            # seconds left to show the key hints
var _cam_name := ""
var _cam_toast_t := 0.0
var _time := 0.0

var _map_path: TrackPath
var _map_rect := Rect2()
var _map_pts := PackedVector2Array()
var _map_origin := Vector2.ZERO
var _map_max := Vector2.ZERO
var _map_scale := 1.0

## When the leader passed each SPLIT metres of race distance, for the tower's time gaps.
const SPLIT := 10.0
var _splits := PackedFloat64Array()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.theme()
	add_child(_root)
	_setup_mirror()
	# What doesn't change from frame to frame (the map's outline, the tach's dial) is drawn
	# once on a layer of its own; _draw redraws only the moving parts over it every frame.
	_static = Control.new()
	_static.set_anchors_preset(Control.PRESET_FULL_RECT)
	_static.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_static.draw.connect(_on_draw_static)
	_root.add_child(_static)
	_draw = Control.new()
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_on_draw)
	_root.add_child(_draw)
	_text_ol = Control.new()
	_text_ol.set_anchors_preset(Control.PRESET_FULL_RECT)
	_text_ol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_ol.draw.connect(_on_draw_text.bind(true))
	_root.add_child(_text_ol)
	_text_fg = Control.new()
	_text_fg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_text_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_fg.draw.connect(_on_draw_text.bind(false))
	_root.add_child(_text_fg)
	_build_pause()
	_settings = SettingsPanel.new()
	_settings.in_race = true
	_settings.changed.connect(_apply_hud)
	_settings.closed.connect(func(): _pause.visible = true; _pause_list.focus = 2)
	_root.add_child(_settings)
	_apply_hud()
	# It's a second view of the whole scene: on Low it starts off (M turns it on).
	_mirror_on = Game.hud_shows("mirror") and Game.quality != Game.Quality.LOW
	_mirror.visible = _mirror_on


## The HUD's parts as the settings have them now.
func _apply_hud() -> void:
	var classic := Game.hud_style > 0 and ClassicGauges.available()
	if classic and _classic == null:
		_classic = ClassicGauges.new()
		_classic.car = player
		_root.add_child(_classic)
		_root.move_child(_classic, _pause.get_index())
	elif not classic and _classic:
		_classic.queue_free()
		_classic = null
	if _classic:
		_classic.visible = Game.hud_shows("speed")
		_classic.placement = Game.hud_style - 1
	# Now playing sits top right, under High Stakes' dials when they're up there.
	if Game.music:
		var np := Game.music.now_playing
		np.reset_place()
		if _classic and _classic.visible and _classic.placement == ClassicGauges.Placement.TOP:
			np.top = ClassicGauges.dial_height(_root.size.y if _root.size.y > 0 else 720.0) + 30.0
	_mirror_on = Game.hud_shows("mirror")
	_mirror.visible = _mirror_on


func mirror_viewport() -> SubViewport:
	return _mirror_vp


func _setup_mirror() -> void:
	_mirror_vp = SubViewport.new()
	_mirror_vp.size = Vector2i(400, 100)
	_mirror_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_mirror_vp)
	_mirror_cam = Camera3D.new()
	_mirror_cam.fov = 40
	_mirror_cam.cull_mask &= ~Car.OWN_VIEW_LAYER
	_mirror_cam.far = 250 if Game.quality == Game.Quality.LOW else 500
	_mirror_vp.add_child(_mirror_cam)
	_mirror = TextureRect.new()
	_mirror.texture = _mirror_vp.get_texture()
	_mirror.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_mirror.size = Vector2(400, 100)
	_mirror.position = Vector2(-200, 16)
	_mirror.flip_h = true
	_mirror.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_mirror)


## Blurred, darkened copy of the race behind a full-screen menu.
static func _backdrop(parent: Control) -> ColorRect:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float lod = 3.0;
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, lod).rgb;
	float side = smoothstep(0.75, 0.0, SCREEN_UV.x);
	COLOR = vec4(c * mix(0.42, 0.18, side), 1.0);
}
"""
	# Low quality skips the blur: mip chains of a full-screen copy aren't free on an iGPU.
	sm.set_shader_parameter("lod", 0.0 if Game.quality == Game.Quality.LOW else 3.0)
	bg.material = sm
	parent.add_child(bg)
	return bg


func _build_pause() -> void:
	_pause = Control.new()
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	_root.add_child(_pause)
	_backdrop(_pause)
	var deco := Control.new()
	deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.draw.connect(_draw_pause.bind(deco))
	_pause.add_child(deco)
	_pause_list = ActionList.new(PackedStringArray(["Resume", "Restart", "Settings", "Quit to menu"]))
	_pause_list.set_item_size(Vector2(330, 54))
	_pause_list.position = Vector2(48, 250)
	_pause_list.activated.connect(func(i: int): [_resume, _restart, _open_settings, _quit][i].call())
	_pause.add_child(_pause_list)


# ------------------------------------------------------------------ API

## The loading screen (the one the menu faded to), over everything until hide_loading().
func show_loading() -> void:
	if _loading == null:
		_loading = LoadingScreen.new()
		_root.add_child(_loading)


## A stage of the loading has begun: `label` says what; the bar runs from `from` toward `to`.
func loading_stage(label: String, from: float, to: float) -> void:
	if _loading:
		_loading.stage(label, from, to)


func hide_loading() -> void:
	if _loading:
		_loading.finish()
		_loading = null
	_hint_t = 12.0


func set_countdown(t: float) -> void:
	_count = t


## `kind` picks the banner colour: "" (accent), "alert" (red) or "go" (green).
func flash(text: String, secs: float, kind := "") -> void:
	_msg = text.to_upper()
	_msg_kind = kind
	_msg_t = secs
	_msg_len = secs
	_count = 0.0


## A rival's word as it passes you, under the middle of the screen: its colour, its name, the line.
func chatter(who: String, color: Color, text: String) -> void:
	_chat = {"name": who.to_upper(), "color": color, "text": "\u201c%s\u201d" % text}
	_chat_t = CHAT_TIME


## Swaps in fresh rows (cars finishing behind the results screen) without replaying the intro.
func update_results(rows: Array) -> void:
	if _results:
		_results_data.rows = rows


## `rows`: [{name, time, best, you?, t?}] in finishing order.
## `actions`: [[label, Callable]] in place of "Race again" and "Main menu" (a tournament's
## next race).
## A tournament's race also has `circuit`: {caption, standings: [{name, you, race (place, 0
## not in it), gained, points, out}], and at the end of the circuit tour (the tournament's
## id, for its trophy's design), trophy (1..3, 0 none), lines (what it won, in order)}.
func show_results(title: String, rows: Array, extra: String, actions: Array = [], circuit := {}) -> void:
	_results_data = {"title": title, "rows": rows, "extra": extra, "circuit": circuit}
	_results_t = 0.0
	_results = Control.new()
	_results.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_results)
	_backdrop(_results)
	var deco := Control.new()
	deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.draw.connect(_draw_results.bind(deco))
	_results.add_child(deco)
	if actions.is_empty():
		actions = [["Race again", _restart], ["Main menu", _quit]]
	set_result_actions(actions)
	_results_list.modulate.a = 0.0
	create_tween().tween_property(_results_list, "modulate:a", 1.0, 0.3).set_delay(0.6)
	_set_mouse_look(false)
	_mirror_on = false
	_mirror.visible = false
	# The results title says it all; don't let a lingering banner overlap it.
	_msg_t = 0.0


## Puts `actions` ([[label, Callable]]) under the results in place of those there, the
## focus kept where it was (paying for a repair takes its button away).
func set_result_actions(actions: Array, focus := 0) -> void:
	var a := 1.0
	if _results_list:
		a = _results_list.modulate.a
		_results_list.queue_free()
	_results_list = ActionList.new(PackedStringArray(actions.map(func(x: Array) -> String: return x[0])), true)
	_results_list.set_item_size(Vector2(240, 54))
	_results_list.activated.connect(func(i: int): (actions[i][1] as Callable).call())
	_results_list.focus = clampi(focus, 0, actions.size() - 1)
	_results_list.modulate.a = a
	_results.add_child(_results_list)
	_results_list.position = Vector2(48, _root.size.y - 40 - 54 - 36)


## Changes the results' line under the table.
func set_result_extra(extra: String) -> void:
	_results_data.extra = extra


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
	if _settings.visible or _loading:
		return
	if e.is_action_pressed("toggle_hud") and _results == null:
		Game.hud_on = not Game.hud_on
		Game.save_settings()
		_apply_hud()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("pause") and _results == null:
		if get_tree().paused:
			_resume()
		else:
			get_tree().paused = true
			_pause.visible = true
			_pause_list.focus = 0
			_pause.modulate.a = 0.0
			create_tween().tween_property(_pause, "modulate:a", 1.0, 0.15)
			_set_mouse_look(false)
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("mirror") and _results == null and not get_tree().paused and Game.hud_on:
		_mirror_on = not _mirror_on


## The settings over the paused race (the pause menu out of the way, so the HUD's changes show).
func _open_settings() -> void:
	_pause.visible = false
	_settings.open(SettingsPanel.PAGE_HUD)


func _resume() -> void:
	get_tree().paused = false
	_pause.visible = false
	_set_mouse_look(true)


func _set_mouse_look(on: bool) -> void:
	if race and race.get("cam"):
		race.cam.mouse_look = on


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func quit() -> void:
	_quit()


func _quit() -> void:
	# Leaving mid-circuit forfeits it.
	Game.circuit_run = {}
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ------------------------------------------------------------------ per frame

func _process(dt: float) -> void:
	_time += dt
	_msg_t = maxf(_msg_t - dt, 0.0)
	_chat_t = maxf(_chat_t - dt, 0.0)
	if not get_tree().paused:
		_hint_t = maxf(_hint_t - dt, 0.0)
		_cam_toast_t = maxf(_cam_toast_t - dt, 0.0)
	if _results:
		_results_t += dt
		_results.get_child(1).queue_redraw()
	if _pause.visible:
		_pause.get_child(1).queue_redraw()
	# In the in-car view the car's own rear-view mirror, where it sits, stands in for this one.
	Car.rear_mirror_wanted = _mirror_on
	_mirror.visible = _mirror_on and not is_instance_valid(Car.in_car_view)
	# A hidden mirror must stop rendering too: it's a whole second view of the scene.
	_mirror_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _mirror.visible else SubViewport.UPDATE_DISABLED
	if player and is_instance_valid(player) and _mirror.visible:
		var xf := player.global_transform
		_mirror_cam.global_transform = Transform3D(xf.basis, xf * Vector3(0, 1.25, 0.2))
		# Camera looks down -Z; the car faces +Z, so this already looks backwards.
	if race and race.get("cam"):
		var n: String = race.cam.mode_name()
		if _cam_name != "" and n != _cam_name:
			_cam_toast_t = 1.6
		_cam_name = n
	_record_splits()
	_draw.queue_redraw()
	var key := [player, _draw.size, _mirror.visible, _pause.visible or _results != null, race.path if race else null,
		Game.units_kmh, Game.hud_on, Game.hud_hidden.duplicate(), _classic]
	if key != _static_key:
		_static_key = key
		_static.queue_redraw()


func _record_splits() -> void:
	if race == null or race.path == null or race.racers.is_empty():
		return
	if race.race_time <= 0.0:
		_splits.clear()
		return
	var lead: float = race.racers[0].total
	for rr in race.racers:
		lead = maxf(lead, rr.total)
	var i := int((lead + race.path.length) / SPLIT)
	while _splits.size() <= i:
		_splits.append(race.race_time)


func _on_draw() -> void:
	_texts.clear()
	_tri_pts.clear()
	_tri_cols.clear()
	_tri_idx.clear()
	# (Drawn after this, from what it records; queued now so an early return clears them too.)
	_text_ol.queue_redraw()
	_text_fg.queue_redraw()
	if player == null or not is_instance_valid(player) or race == null or race.path == null:
		return
	if _pause.visible or _results:
		return
	var size := _draw.size
	if _classic == null and Game.hud_shows("speed"):
		_draw_tach(Vector2(size.x - M - 118, size.y - M - 104))
	_draw_info(size)
	if Game.hud_shows("map"):
		_draw_map(Rect2(M, size.y - M - 190, 190, 190))
	if pursuit and Game.hud_shows("lights"):
		_draw_pursuit(size)
	if Game.hud_shows("messages"):
		_draw_banner(size)
		_draw_chatter(size)
	if not _tri_idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(_draw.get_canvas_item(), _tri_idx, _tri_pts, _tri_cols)
	if Game.hud_shows("countdown"):
		_draw_countdown(size)
	if Game.hud_shows("hints"):
		_draw_hints(size)


## The text recorded by _on_draw: its outlines, or the text itself over them.
func _on_draw_text(outlines: bool) -> void:
	var ci := _text_ol if outlines else _text_fg
	for key: Array in _texts:
		var f: Font = key[0]
		var fsize: int = key[1]
		for t: Array in _texts[key]:
			if not outlines:
				ci.draw_string(f, t[0], t[1], t[2], t[3], fsize, t[4])
			elif t[5] > 0:
				ci.draw_string_outline(f, t[0], t[1], t[2], t[3], fsize, t[5], t[6])


## Text for the text layers, optionally outlined.
func _text(f: Font, pos: Vector2, s: String, align: HorizontalAlignment, width: float, fsize: int, color: Color,
		outline := 0, outline_color := Color(0, 0, 0, 0)) -> void:
	# Grouped by font and size, each of which has a texture of its own: one batch per group.
	var key := [f, fsize]
	if not _texts.has(key):
		_texts[key] = []
	_texts[key].append([pos, s, align, width, color, outline, outline_color])


## A convex (or star-shaped about its first point) polygon into this frame's batch of shapes.
func _poly(pts: PackedVector2Array, color: Color) -> void:
	var base := _tri_pts.size()
	_tri_pts.append_array(pts)
	for k in pts.size():
		_tri_cols.append(color)
	for k in range(1, pts.size() - 1):
		_tri_idx.append_array([base, base + k, base + k + 1])


func _rect(r: Rect2, color: Color) -> void:
	_poly(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), color)


func _slant(r: Rect2, color: Color, slant := UiKit.SLANT) -> void:
	_poly(UiKit.slant_points(r, slant), color)


func _circle(c: Vector2, radius: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for k in 12:
		pts.append(c + Vector2.from_angle(k * TAU / 12.0) * radius)
	_poly(pts, color)


# ------------------------------------------------------------------ drawing

func _str(s: String, pos: Vector2, kind: String, fsize: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT,
		width := -1.0, tracking := 0, tabular := false) -> void:
	# A soft dark outline keeps text legible over bright sky without looking 1998.
	_text(UiKit.font(kind, tracking, tabular), pos, s, align, width, fsize, color, maxi(fsize / 7, 3),
		Color(0, 0, 0, 0.35 * color.a))


## The static layer: the mirror's frame, the tach's dial and the map's outline.
func _on_draw_static() -> void:
	if player == null or not is_instance_valid(player) or race == null or race.path == null:
		return
	if _pause.visible or _results:
		return
	var size := _static.size
	if _mirror.visible:
		var mr := _mirror.get_rect()
		_static.draw_rect(mr.grow(1), Color(1, 1, 1, 0.35), false, 1.0)
	if _classic == null and Game.hud_shows("speed"):
		_draw_tach_dial(Vector2(size.x - M - 118, size.y - M - 104))
	if Game.hud_shows("map"):
		_draw_map_outline(Rect2(M, size.y - M - 190, 190, 190))


## Unlit segments, the thousands and the units under the speed.
func _draw_tach_dial(c: Vector2) -> void:
	var r := TACH_R
	var max_rpm := _tach_max_rpm()
	var red_frac := player.redline / max_rpm
	# The unlit segments, all in one batch of triangles.
	_tach_polys(c)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var tris := PackedInt32Array()
	for i in TACH_SEGS:
		var col := Color(1, 1, 1, 0.13) if (i + 0.5) / TACH_SEGS < red_frac else Color(RED, 0.3)
		var base := pts.size()
		pts.append_array(_tach_segs[i])
		for k in _tach_segs[i].size():
			cols.append(col)
		for k in range(1, _tach_segs[i].size() - 1):
			tris.append_array([base, base + k, base + k + 1])
	RenderingServer.canvas_item_add_triangle_array(_static.get_canvas_item(), tris, pts, cols)
	var kf := UiKit.font("cond", 0, true)
	for k in int(max_rpm / 1000.0) + 1:
		var a := lerpf(TACH_A0, TACH_A1, k * 1000.0 / max_rpm)
		var p := c + Vector2(cos(a), sin(a)) * (r - 30)
		_static.draw_string(kf, p + Vector2(-8, 5), str(k), HORIZONTAL_ALIGNMENT_CENTER, 16, 13,
			Color(RED, 0.9) if k * 1000.0 >= player.redline else UiKit.INK_DIM)
	var f := UiKit.font("cond", 3)
	var pos := c + Vector2(-80, 44)
	var units := "KM/H" if Game.units_kmh else "MPH"
	_static.draw_string_outline(f, pos, units, HORIZONTAL_ALIGNMENT_CENTER, 160, 13, 3, Color(0, 0, 0, 0.35 * UiKit.INK_DIM.a))
	_static.draw_string(f, pos, units, HORIZONTAL_ALIGNMENT_CENTER, 160, 13, UiKit.INK_DIM)


const TACH_R := 104.0
const TACH_SEGS := 40
const TACH_A0 := deg_to_rad(140)
const TACH_A1 := deg_to_rad(400)


## The tach's scale: one for every car, so a lazy V12's redline sits well short of a racer's.
func _tach_max_rpm() -> float:
	return maxf(10000.0, ceilf(player.redline / 1000.0 + 1.0) * 1000.0)


## Segment i of the tach: an arc from s0 to s1, thickening towards the top of the range like a
## modern digital cluster.
func _tach_seg(i: int) -> Array:
	var span := (TACH_A1 - TACH_A0) / TACH_SEGS
	var s0 := TACH_A0 + i * span + span * 0.12
	var mid := (i + 0.5) / TACH_SEGS
	return [s0, s0 + span * 0.76, lerpf(9.0, 15.0, mid), mid]


## Each of the tach's segments as a polygon round the dial centred on `c`, built once.
func _tach_polys(c: Vector2) -> void:
	if c == _tach_c:
		return
	_tach_c = c
	_tach_segs.clear()
	for i in TACH_SEGS:
		var sg := _tach_seg(i)
		var pts := PackedVector2Array()
		for k in 5:
			var a: float = lerpf(sg[0], sg[1], k / 4.0)
			pts.append(c + Vector2(cos(a), sin(a)) * TACH_R)
		for k in 5:
			var a: float = lerpf(sg[1], sg[0], k / 4.0)
			pts.append(c + Vector2(cos(a), sin(a)) * (TACH_R - sg[2]))
		_tach_segs.append(pts)


## The tach's lit segments over the dial (_draw_tach_dial, on the static layer), speed and gear.
func _draw_tach(c: Vector2) -> void:
	var r := TACH_R
	var max_rpm := _tach_max_rpm()
	var frac := clampf(player.rpm / max_rpm, 0.0, 1.0)
	var red_frac := player.redline / max_rpm
	var shift := player.rpm > player.redline * 0.96 and fmod(_time * 12.0, 2.0) < 1.0
	_tach_polys(c)
	for i in TACH_SEGS:
		var mid := (i + 0.5) / TACH_SEGS
		if mid > frac:
			break
		var in_red := mid >= red_frac
		_poly(_tach_segs[i], RED if in_red or shift else (UiKit.ACCENT if mid > red_frac * 0.72 else UiKit.INK))
	var spd := player.kmh() if Game.units_kmh else player.kmh() / 1.609
	_str("%d" % roundi(spd), c + Vector2(-80, 22), "display", 62, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER, 160, 0, true)
	# Gear in a slanted chip in the gap at the bottom of the arc.
	var g := "R" if player.gear < 0 else ("N" if player.gear == 0 else str(player.gear))
	var gr := Rect2(c + Vector2(-22, r - 26), Vector2(44, 36))
	_slant(gr, RED if player.gear < 0 else UiKit.ACCENT)
	_text(UiKit.font("display"), gr.position + Vector2(0, 29), g, HORIZONTAL_ALIGNMENT_CENTER, gr.size.x, 32, UiKit.BG)


func _draw_info(size: Vector2) -> void:
	var r: Dictionary = race.player_racer()
	if r.is_empty() or Game.mode == Game.Mode.FREE_ROAM:
		return
	# High Stakes' dials at the top: the field lists under the speedometer.
	var top := M
	if _classic and _classic.visible and _classic.placement == ClassicGauges.Placement.TOP:
		top += ClassicGauges.dial_height(size.y) - 8.0
	var y := _draw_tower(Vector2(M, top)) if Game.hud_shows("standings") else top - 10.0
	if Game.mode == Game.Mode.HOT_PURSUIT and Game.hud_shows("police"):
		_draw_cop_block(y + 26)
	if not Game.hud_shows("lap"):
		return
	# Lap counter and progress, over the minimap (or where it would be).
	var map_y := size.y - M - 190
	if not race.path.closed:
		_draw_sprint_progress(r, map_y)
		return
	var lap := clampi(r.lap + 1, 1, Game.race_laps())
	_kicker("LAP", Vector2(M, map_y - 54))
	_str(str(lap), Vector2(M - 2, map_y - 12), "display", 42, UiKit.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, 0, true)
	var lw := UiKit.text_width("display", str(lap), 42, 0, true)
	_str("/ %d" % Game.race_laps(), Vector2(M + lw + 6, map_y - 12), "display", 22, UiKit.INK_DIM)
	if r.best < INF:
		_str("BEST", Vector2(M, map_y - 32), "cond", 12, UiKit.INK_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 190 - 74, 2)
		_str(fmt_time(r.best), Vector2(M, map_y - 12), "cond", 18, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT, 190, 1, true)
	var pr := Rect2(M, map_y - 2, 190, 3)
	var frac := clampf(float(r.node) / maxf(race.path.size(), 1.0), 0.0, 1.0) if r.lap >= 0 else 0.0
	_rect(pr, Color(1, 1, 1, 0.18))
	_rect(Rect2(pr.position, Vector2(pr.size.x * frac, pr.size.y)), UiKit.ACCENT)


## A kicker: the small amber caps over a figure, as the menus have them.
func _kicker(t: String, pos: Vector2, col := UiKit.ACCENT) -> void:
	_str(t, pos, "cond", 13, col, HORIZONTAL_ALIGNMENT_LEFT, -1, 2)


## A point-to-point run's in place of the lap counter: how far is left to the finish, and a
## bar from the start line to it.
func _draw_sprint_progress(r: Dictionary, map_y: float) -> void:
	var path: TrackPath = race.path
	var total := path.cumulative[path.finish_node] - path.cumulative[path.start_node]
	var done := clampf(path.cumulative[r.node] - path.cumulative[path.start_node], 0.0, total) if r.lap >= 0 else 0.0
	var left := (total - done) / 1000.0
	_kicker("TO THE FINISH", Vector2(M, map_y - 54))
	var v := "%.1f" % (left if Game.units_kmh else left / 1.609)
	_str(v, Vector2(M - 2, map_y - 12), "display", 42, UiKit.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, 0, true)
	var lw := UiKit.text_width("display", v, 42, 0, true)
	_str("KM" if Game.units_kmh else "MI", Vector2(M + lw + 6, map_y - 12), "display", 22, UiKit.INK_DIM)
	var pr := Rect2(M, map_y - 2, 190, 3)
	_rect(pr, Color(1, 1, 1, 0.18))
	_rect(Rect2(pr.position, Vector2(pr.size.x * done / maxf(total, 1.0), pr.size.y)), UiKit.ACCENT)


## Timing tower: every racer in order, the leader with the race clock, the rest with their
## gap to the leader. Returns the y below it.
func _draw_tower(at: Vector2) -> float:
	var w := 300.0
	var h := 27.0
	var L: float = race.path.length
	var lead: Dictionary = race.racers[0]
	var y := at.y
	for i in race.racers.size():
		var rr: Dictionary = race.racers[i]
		var you: bool = rr.car == player
		var base := y + h - 8
		if you:
			# As a menu's focus: a wash of the accent fading out, a bar down its edge.
			var r := Rect2(at.x - 12, y, w + 24, h - 1)
			var a := Color(UiKit.ACCENT, 0.42)
			var b := Color(UiKit.ACCENT, 0.0)
			_tri_quad(r, a, b)
			_rect(Rect2(r.position.x, r.position.y, 3, r.size.y), UiKit.ACCENT)
		_str(str(i + 1), Vector2(at.x, base), "display", 21, UiKit.ACCENT if you else UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT, 22,
			0, true)
		var gap := _gap(rr, lead, L)
		if rr.finished:
			# The race runs on past the winner until you're home: show each finisher's time and flag them.
			gap = fmt_time(rr.time)
		var gw := UiKit.text_width("cond", gap, 16, 0, true)
		var fin_w := 34.0 if rr.finished else 0.0
		var nw := w - 41 - gw - fin_w - 12
		var nm: String = str(rr.get("short", rr.name)).to_upper()
		if not you:
			_chip(Rect2(at.x + 28, y + 7, 7, h - 13), rr.get("color", UiKit.INK))
		_str(nm, Vector2(at.x + 41, base), "cond", UiKit.fit("cond", nm, nw, 16, 12, 1), UiKit.INK if i == 0 or you else \
			Color(UiKit.INK, 0.86), HORIZONTAL_ALIGNMENT_LEFT, nw, 1)
		if rr.finished:
			_str("FIN", Vector2(at.x, base), "cond", 12, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT, w - gw - 8, 2)
		_str(gap, Vector2(at.x, base), "cond", 16, UiKit.INK if i == 0 or you else UiKit.INK_DIM,
			HORIZONTAL_ALIGNMENT_RIGHT, w, 0, true)
		y += h
	return y


## A rectangle shaded from `a` at its left to `b` at its right, into this frame's batch.
func _tri_quad(r: Rect2, a: Color, b: Color) -> void:
	var base := _tri_pts.size()
	_tri_pts.append_array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	_tri_cols.append_array([a, b, b, a])
	_tri_idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


func _gap(rr: Dictionary, lead: Dictionary, L: float) -> String:
	if is_same(rr, lead):
		return fmt_time(rr.time if rr.finished else race.race_time)
	if race.race_time <= 0.0:
		return ""
	if rr.finished:
		return "+%.1f" % (rr.time - lead.time)
	if not lead.finished:
		var laps := int((lead.total - rr.total) / L)
		if laps >= 1:
			return "+%d LAP%s" % [laps, "" if laps == 1 else "S"]
	var i := int((rr.total + L) / SPLIT)
	if i < 0 or i >= _splits.size():
		return ""
	var g: float = race.race_time - _splits[i]
	return "+%.1f" % g if g < 60.0 else "+" + fmt_time(g)


## Everything about the police in one block under the tower: chase status and heat while
## they're after you, tickets always, flat tyres once spiked.
func _draw_cop_block(y: float) -> void:
	if pursuit:
		var on := fmod(_time * 4.0, 2.0) < 1.0
		_circle(Vector2(M + 4, y - 5), 4, RED if on else UiKit.COP_BLUE)
		_kicker("IN PURSUIT", Vector2(M + 14, y), UiKit.INK)
		y += 22
		_pips("HEAT", y, 3, race.heat)
		y += 22
	_pips("TICKETS", y, race.MAX_TICKETS, race.tickets)
	if player and player.tyres_flat():
		_kicker("FLAT TYRES", Vector2(M, y + 22), RED)


## A label and a row of `n` slanted pips, the first `lit` of them red.
func _pips(label: String, y: float, n: int, lit: int) -> void:
	_kicker(label, Vector2(M, y), UiKit.INK_DIM)
	for k in n:
		_rect(Rect2(M + 84 + k * 24, y - 9, 18, 6), RED if k < lit else Color(1, 1, 1, 0.22))


## While chased: a thin light bar along the top edge, red and blue halves taking turns.
func _draw_pursuit(size: Vector2) -> void:
	var on := fmod(_time * 4.0, 2.0) < 1.0
	var h := size.x * 0.5
	_rect(Rect2(0, 0, h, 3), Color(RED, 0.85 if on else 0.15))
	_rect(Rect2(h, 0, h, 3), Color(UiKit.COP_BLUE, 0.15 if on else 0.85))


## A message across the middle as a broadcast graphic: a dark band fading out at its ends, a
## line of the kind's colour above and below it drawing out from the centre, the words over it.
func _draw_banner(size: Vector2) -> void:
	if _msg_t <= 0.0 or _msg == "":
		return
	var age := _msg_len - _msg_t
	var grow := clampf(age / 0.22, 0.0, 1.0)
	grow = 1.0 - pow(1.0 - grow, 3.0)
	var fade := clampf(_msg_t / 0.3, 0.0, 1.0)
	var fs := 42
	var f := UiKit.font("display", 1)
	var tw := f.get_string_size(_msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var col := UiKit.ACCENT
	match _msg_kind:
		"alert": col = RED
		"go": col = GO
	var cx := size.x * 0.5
	var half := (tw * 0.5 + 160.0) * grow
	var band := Rect2(cx - half, 188, half * 2.0, 62)
	var dark := Color(0, 0, 0, 0.55 * fade)
	var clear := Color(0, 0, 0, 0.0)
	_tri_quad(Rect2(band.position, Vector2(half, band.size.y)), clear, dark)
	_tri_quad(Rect2(cx, band.position.y, half, band.size.y), dark, clear)
	var lw := (tw * 0.5 + 40.0) * grow
	_rect(Rect2(cx - lw, band.position.y, lw * 2.0, 2), Color(col, fade))
	_rect(Rect2(cx - lw, band.end.y - 2, lw * 2.0, 2), Color(col, fade))
	if grow > 0.5:
		_text(f, Vector2(cx - tw * 0.5, band.position.y + 46), _msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(UiKit.INK if _msg_kind == "" else col.lerp(UiKit.INK, 0.35), fade * (grow - 0.5) / 0.5), 5, Color(0, 0, 0, 0.3 * fade))


func _draw_chatter(size: Vector2) -> void:
	if _chat_t <= 0.0 or _chat.is_empty():
		return
	var a := clampf(_chat_t / 0.4, 0.0, 1.0) * clampf((CHAT_TIME - _chat_t) / 0.15, 0.0, 1.0)
	var y := size.y - M - 96
	if _classic and _classic.visible and _classic.placement == ClassicGauges.Placement.BOTTOM:
		y -= ClassicGauges.dial_height(size.y) + 14.0
	var nw := UiKit.text_width("cond", _chat.name, 14, 2)
	var tw := UiKit.text_width("display", _chat.text, 24)
	var w := maxf(nw + 22, tw)
	var x := size.x * 0.5 - w * 0.5
	var dark := Color(0, 0, 0, 0.5 * a)
	_tri_quad(Rect2(x - 60, y - 22, w * 0.5 + 60, 58), Color(0, 0, 0, 0), dark)
	_tri_quad(Rect2(x + w * 0.5, y - 22, w * 0.5 + 60, 58), dark, Color(0, 0, 0, 0))
	_chip(Rect2(x, y - 12, 14, 12), Color(_chat.color, a))
	_str(_chat.name, Vector2(x + 22, y - 1), "cond", 14, Color(_chat.color.lerp(UiKit.INK, 0.45), a), HORIZONTAL_ALIGNMENT_LEFT, -1, 2)
	_str(_chat.text, Vector2(x, y + 27), "display", 24, Color(UiKit.INK, a))


## A driver's colour as a small slanted swatch, rimmed so the dark ones show on the dark HUD.
func _chip(r: Rect2, color: Color) -> void:
	_slant(r.grow(1.0), Color(1, 1, 1, 0.4 * color.a))
	_slant(r, color)


func _draw_countdown(size: Vector2) -> void:
	if _count <= 0.0 or _count > 3.0:
		return
	var n := ceili(_count)
	var sub := _count - (n - 1)          # 1 -> 0 over each second
	var pop := 1.0 + pow(sub, 6.0) * 0.5
	var c := size * Vector2(0.5, 0.4)
	_draw.draw_arc(c, 92, -PI * 0.5, -PI * 0.5 + TAU * sub, 64, Color(UiKit.ACCENT, 0.9), 6, true)
	_draw.draw_arc(c, 92, 0, TAU, 64, Color(1, 1, 1, 0.12), 6, true)
	var fs := int(130 * pop)
	var f := UiKit.font("display")
	var s := str(n)
	var tw := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var a := clampf(sub * 3.0, 0.0, 1.0)
	_text(f, c + Vector2(-tw * 0.5, fs * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiKit.INK, a), 14, Color(0, 0, 0, 0.3 * a))


func _draw_hints(size: Vector2) -> void:
	# Over High Stakes' dials when they're at the bottom.
	if _classic and _classic.visible and _classic.placement == ClassicGauges.Placement.BOTTOM:
		size.y -= ClassicGauges.dial_height(size.y) + 14.0
	if _cam_toast_t > 0.0:
		var a := clampf(_cam_toast_t / 0.3, 0.0, 1.0)
		_str("CAMERA", Vector2(0, size.y - M - 26), "cond", 12, Color(UiKit.ACCENT, a), HORIZONTAL_ALIGNMENT_CENTER, size.x, 2)
		_str(_cam_name.to_upper(), Vector2(0, size.y - M - 4), "cond", 18, Color(UiKit.INK, a), HORIZONTAL_ALIGNMENT_CENTER, size.x, 1)
		return
	if _hint_t <= 0.0:
		return
	var hints := [["C", "CAMERA"], ["R", "RESET"], ["M", "MIRROR"], ["L", "LIGHTS"], ["F1", "HUD"], ["ESC", "PAUSE"]]
	if Game.mode == Game.Mode.SPECTATE:
		hints = [["←→", "SWITCH CAR"], ["C", "CAMERA"], ["M", "MIRROR"], ["F1", "HUD"], ["ESC", "PAUSE"]]
	var w := 0.0
	for h in hints:
		w += UiKit.text_width("cond", h[0], 13, 1) + 12 + 7 + UiKit.text_width("cond", h[1], 13, 2) + 22
	var a := clampf(_hint_t / 0.6, 0.0, 1.0)
	UiKit.draw_hints(_draw, Vector2(size.x * 0.5 - w * 0.5, size.y - M - 5), hints, 13, a)


## Top-down view with +Z up the screen; +X (the driver's left when heading +Z) is then screen-left.
func _to_map(p: Vector3) -> Vector2:
	return _map_origin + Vector2(_map_max.x - p.x, _map_max.y - p.z) * _map_scale


## The track's outline and the start line (on the static layer).
func _draw_map_outline(rect: Rect2) -> void:
	_map_layout(rect)
	var path: TrackPath = race.path
	_static.draw_polyline(_map_pts, Color(0, 0, 0, 0.45), 7, true)
	_static.draw_polyline(_map_pts, Color(1, 1, 1, 0.8), 3, true)
	# Start/finish: a short bar across the track, perpendicular to its direction at the start
	# (node 0 of a lap). A point-to-point run's finish is a chequered flag at its far end.
	var a := path.start_node if not path.closed else 0
	var s0 := _to_map(path.points[a])
	var dir := _to_map(path.points[path.idx(a + 1)]) - s0
	if dir.length() < 0.01:
		dir = s0 - _to_map(path.points[path.idx(a - 1)])
	var across := dir.normalized().orthogonal() * 7.0
	_static.draw_line(s0 - across, s0 + across, UiKit.ACCENT, 3)
	if not path.closed:
		UiKit.route_ends(_static, s0, dir, _to_map(path.points[path.finish_node]), 1.1, UiKit.ACCENT)


## The cars on the map, over its outline.
func _draw_map(rect: Rect2) -> void:
	_map_layout(rect)
	var blink := fmod(_time * 4.0, 2.0) < 1.0
	for c in race.cops:
		if is_instance_valid(c):
			var cc := RED if pursuit and blink else UiKit.COP_BLUE
			_circle(_to_map(c.global_position), 5, Color(0, 0, 0, 0.5))
			_circle(_to_map(c.global_position), 3.5, cc)
	for rr in race.racers:
		if rr.car == player:
			continue
		_circle(_to_map(rr.car.global_position), 5.5, Color(1, 1, 1, 0.55))
		_circle(_to_map(rr.car.global_position), 4, rr.get("color", UiKit.INK))
	# The player as an arrow pointing along the car's heading.
	var p := _to_map(player.global_position)
	var fwd3 := player.global_transform.basis.z
	var d := Vector2(-fwd3.x, -fwd3.z).normalized()
	var n := d.orthogonal()
	var tri := PackedVector2Array([p + d * 9, p - d * 6 + n * 6, p - d * 3, p - d * 6 - n * 6])
	_poly(PackedVector2Array([p + d * 11, p - d * 8 + n * 8, p - d * 4, p - d * 8 - n * 8]), Color(0, 0, 0, 0.5))
	_poly(tri, UiKit.ACCENT)


## Fits the track into the map's rect; the outline only depends on the track and the rect,
## so it's built once, not every frame.
func _map_layout(rect: Rect2) -> void:
	var path: TrackPath = race.path
	if _map_path != path or _map_rect != rect:
		_map_path = path
		_map_rect = rect
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p in path.points:
			mn = mn.min(Vector2(p.x, p.z))
			mx = mx.max(Vector2(p.x, p.z))
		var span := maxf(mx.x - mn.x, mx.y - mn.y)
		_map_scale = (rect.size.x - 28) / maxf(span, 1.0)
		_map_origin = rect.position + Vector2(14, 14) + (Vector2(span, span) - (mx - mn)) * 0.5 * _map_scale
		_map_max = mx
		_map_pts = PackedVector2Array()
		for i in range(0, path.size(), 2):
			_map_pts.append(_to_map(path.points[i]))
		# A lap closes on itself; an open road runs from end to end.
		if path.closed:
			_map_pts.append(_map_pts[0])
		elif (path.size() - 1) % 2 != 0:
			_map_pts.append(_to_map(path.points[path.size() - 1]))


# ------------------------------------------------------------------ pause / results

func _draw_pause(c: Control) -> void:
	var W := c.size.x
	var H := c.size.y
	c.draw_string(UiKit.font("cond", 3), Vector2(48, 160), "%s  ·  %s" % [Game.track_name(Game.track_id).to_upper(),
		Game.MODE_NAMES[Game.mode].to_upper()], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiKit.ACCENT)
	c.draw_string(UiKit.font("display"), Vector2(46, 222), "PAUSED", HORIZONTAL_ALIGNMENT_LEFT, -1, 72, UiKit.INK)
	# Where you stand, bottom right.
	if race and player and is_instance_valid(player):
		var r: Dictionary = race.player_racer()
		var stats := []
		if Game.mode != Game.Mode.FREE_ROAM and not r.is_empty():
			if Game.mode != Game.Mode.TIME_TRIAL:
				stats.append(["POSITION", "%d / %d" % [race.position_of(player), race.racers.size()]])
			if race.path.closed:
				stats.append(["LAP", "%d / %d" % [clampi(r.lap + 1, 1, Game.race_laps()), Game.race_laps()]])
			stats.append(["TIME", fmt_time(race.race_time)])
			if race.path.closed:
				stats.append(["BEST LAP", fmt_time(r.best)])
		var x := W - 48.0
		for i in range(stats.size() - 1, -1, -1):
			var vw := maxf(UiKit.text_width("display", stats[i][1], 36, 0, true) + 4.0, 90.0)
			c.draw_string(UiKit.font("cond", 3), Vector2(x - vw, H - 128), stats[i][0], HORIZONTAL_ALIGNMENT_RIGHT, vw, 12, UiKit.INK_DIM)
			c.draw_string(UiKit.font("display", 0, true), Vector2(x - vw, H - 90), stats[i][1], HORIZONTAL_ALIGNMENT_RIGHT, vw, 36, UiKit.INK)
			x -= vw + 40
	UiKit.draw_hints(c, Vector2(48, H - 40 - 14), [["↑↓", "SELECT"], ["ENTER", "CONFIRM"], ["ESC", "RESUME"]])


func _draw_results(c: Control) -> void:
	var W := c.size.x
	var H := c.size.y
	var t := _results_t
	var title: String = _results_data.title
	var rows: Array = _results_data.rows
	var circuit: Dictionary = _results_data.get("circuit", {})
	var standings: Array = circuit.get("standings", [])
	var arrested := title == "ARRESTED"
	var ease := func(x: float) -> float: return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)
	# Headline: "FINISHED 2nd" becomes a giant "2ND" with a small caption.
	var big := title
	var caption: String = Game.track_name(Game.track_id).to_upper() + "  ·  " + Game.MODE_NAMES[Game.mode].to_upper()
	if circuit.has("caption"):
		caption = circuit.caption
	if title.begins_with("FINISHED "):
		big = title.trim_prefix("FINISHED ").to_upper()
		caption = "FINISHED  ·  " + caption
	var k: float = ease.call(t / 0.4)
	var col := RED if arrested else UiKit.ACCENT
	c.draw_string(UiKit.font("cond", 3), Vector2(48, 110), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(col, k))
	c.draw_string(UiKit.font("display"), Vector2(46 - 30 * (1.0 - k), 200), big, HORIZONTAL_ALIGNMENT_LEFT, -1,
		96 if big.length() <= 4 else 72, Color(UiKit.INK, k))
	# A circuit's end: its trophy, and what it won beside it.
	var trophy: int = circuit.get("trophy", 0)
	var lines: Array = circuit.get("lines", [])
	if trophy > 0 or not lines.is_empty():
		var a: float = ease.call((t - 0.5) / 0.5)
		var cup_h := 170.0
		var cx := W - 48.0 - cup_h * 0.5
		if trophy > 0:
			# Rises into place, with a glow behind.
			var rise := 30.0 * (1.0 - a)
			for r in 4:
				c.draw_circle(Vector2(cx, 150 + rise), 70.0 + r * 16.0, Color(UiKit.trophy_colour(trophy), 0.05 * a))
			# High Stakes' own, turning (its 16 frames at 10 a second).
			UiKit.draw_trophy(c, Vector2(cx, 235 + rise), cup_h, trophy, a, circuit.get("tour", 0), t * 10.0)
		var tx := cx - (cup_h * 0.5 + 16.0 if trophy > 0 else -60.0)
		var ly := 96.0
		if trophy > 0:
			c.draw_string(UiKit.font("cond", 3), Vector2(0, ly), UiKit.TROPHY_NAMES[trophy - 1] + " TROPHY", HORIZONTAL_ALIGNMENT_RIGHT,
				tx, 14, Color(UiKit.trophy_colour(trophy), a))
			ly += 34
		for i in lines.size():
			var la: float = ease.call((t - 0.7 - i * 0.15) / 0.3)
			c.draw_string(UiKit.font("display"), Vector2(0, ly), str(lines[i]).to_upper(), HORIZONTAL_ALIGNMENT_RIGHT, tx,
				26 if i == 0 else 20, Color(UiKit.INK if i == 0 else UiKit.INK_DIM, la))
			ly += 30 if i == 0 else 26
	# Leaderboard (a tournament's beside its standings).
	var x0 := 48.0
	var tw := minf(W - 96, 820.0)
	if not standings.is_empty():
		tw = minf((W - 96) * 0.56, 820.0)
	var cols := [[0.0, "POS"], [70.0, "DRIVER"], [tw - 330, "TIME"], [tw - 210, "BEST LAP"], [tw - 90, "GAP"]]
	var y := 250.0
	if not standings.is_empty():
		c.draw_string(UiKit.font("cond", 3), Vector2(x0 + 16, y - 26), "THIS RACE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(UiKit.ACCENT, k))
	for cdef in cols:
		c.draw_string(UiKit.font("cond", 3), Vector2(x0 + cdef[0] + 16, y), cdef[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.INK_DIM)
	y += 12
	var lead_t := INF
	if rows.size() > 0 and rows[0].get("t", INF) is float:
		lead_t = rows[0].get("t", INF)
	# Rows shrink to fit between the header and the buttons (a full grid of 8 is tall).
	var extra: String = _results_data.extra
	var bottom := H - 40 - 54 - 36 - 28 - (34.0 if extra != "" else 0.0)
	var n_rows := maxf(rows.size(), standings.size())
	var rh := clampf((bottom - y) / maxf(n_rows, 1.0) - 4.0, 26.0, 40.0)
	var k2 := rh / 40.0
	for i in rows.size():
		var row: Dictionary = rows[i]
		var a: float = ease.call((t - 0.25 - i * 0.07) / 0.3)
		if a <= 0.0:
			continue
		var you: bool = row.get("you", false) or str(row.name).ends_with("(you)")
		var rr := Rect2(x0 - 24 * (1.0 - a), y + i * (rh + 4), tw, rh)
		# Your row as a menu's focus: the accent's wash and a bar; the rest on hairlines.
		if you:
			UiKit.glow(c, rr, a * 1.6)
		c.draw_rect(Rect2(rr.position.x, rr.end.y + 1, rr.size.x, 1), Color(1, 1, 1, 0.08 * a))
		var ink := Color(UiKit.INK, a)
		var dim := Color(UiKit.INK if you else UiKit.INK_DIM, a)
		var by := rr.position.y + rh * 0.5 + 8.0 * k2
		var tf := UiKit.font("cond", 1, true)
		c.draw_string(UiKit.font("display", 0, true), Vector2(rr.position.x + cols[0][0] + 16, by + 2), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, int(28 * k2),
			Color(UiKit.ACCENT, a) if you else ink)
		var nm := str(row.name).trim_suffix("  (you)").to_upper()
		if not you and row.has("color"):
			_draw_chip(c, Rect2(rr.position.x + cols[1][0] + 2, by - 16 * k2, 6, 16 * k2), Color(row.color, a))
		c.draw_string(UiKit.font("display"), Vector2(rr.position.x + cols[1][0] + 16, by), nm, HORIZONTAL_ALIGNMENT_LEFT, cols[2][0] - cols[1][0] - 20, int(22 * k2), ink)
		if you:
			var nw := minf(UiKit.text_width("display", nm, int(22 * k2)), cols[2][0] - cols[1][0] - 70)
			UiKit.kicker(c, Vector2(rr.position.x + cols[1][0] + 16 + nw + 12, by - 1), "YOU", -1, Color(UiKit.ACCENT, a))
		c.draw_string(tf, Vector2(rr.position.x + cols[2][0] + 16, by - 1), str(row.time), HORIZONTAL_ALIGNMENT_LEFT, -1, int(19 * k2), ink)
		c.draw_string(tf, Vector2(rr.position.x + cols[3][0] + 16, by - 1), str(row.best), HORIZONTAL_ALIGNMENT_LEFT, -1, int(19 * k2), dim)
		var gap := ""
		var rt: Variant = row.get("t", INF)
		if i > 0 and rt is float and rt < INF and lead_t < INF:
			gap = "+%.2f" % (rt - lead_t)
		c.draw_string(tf, Vector2(rr.position.x + cols[4][0] + 16, by - 1), gap, HORIZONTAL_ALIGNMENT_LEFT, -1, int(19 * k2), dim)
	if not standings.is_empty():
		_draw_standings(c, Vector2(x0 + tw + 40, y - 12), W - 48 - (x0 + tw + 40), standings, rh, k2, t, ease)
	if extra != "":
		var ey := y + n_rows * (rh + 4) + 26
		c.draw_string(UiKit.font("body"), Vector2(x0 + 16, ey), extra, HORIZONTAL_ALIGNMENT_LEFT, W - 96 - 16, 17,
			Color(RED if arrested else UiKit.INK_DIM, ease.call((t - 0.5) / 0.3)))
	_results_list.position = Vector2(48, H - 40 - 54 - 36)
	UiKit.draw_hints(c, Vector2(48, H - 40 - 8), [["←→", "SELECT"], ["ENTER", "CONFIRM"]])


## _chip's swatch drawn straight onto `c` (the results screen isn't batched).
func _draw_chip(c: CanvasItem, r: Rect2, color: Color) -> void:
	UiKit.draw_slant(c, r.grow(1.0), Color(1, 1, 1, 0.4 * color.a))
	UiKit.draw_slant(c, r, color)


## A tournament's standings after the race, at `at` (the column heads' baseline), `w` wide:
## place, driver, where each finished this race and the points it took, the total. Those
## knocked out are listed last, struck out. A rally's (standings with a `total`) show the
## total time instead of the points.
func _draw_standings(c: Control, at: Vector2, w: float, standings: Array, rh: float, k2: float, t: float, ease: Callable) -> void:
	var timed := not standings.is_empty() and str(standings[0].get("total", "")) != ""
	var cols := [[0.0, "POS"], [54.0, "STANDINGS"], [w - 196, "RACE"], [w - 128, "+PTS"], [w - 60, "PTS"]]
	if timed:
		cols = [[0.0, "POS"], [54.0, "STANDINGS"], [w - 236, "STAGE"], [w - 128, ""], [w - 128, "TOTAL"]]
	var k: float = ease.call((t - 0.3) / 0.4)
	c.draw_string(UiKit.font("cond", 3), Vector2(at.x + 16, at.y - 26), _results_data.circuit.get("standings_caption", "STANDINGS"),
		HORIZONTAL_ALIGNMENT_LEFT, w - 16, 13, Color(UiKit.ACCENT, k))
	for cdef in cols:
		c.draw_string(UiKit.font("cond", 3), Vector2(at.x + cdef[0] + 16, at.y), "" if cdef[1] == "STANDINGS" else cdef[1],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.INK_DIM)
	var y := at.y + 12
	var tf := UiKit.font("cond", 1, true)
	for i in standings.size():
		var s: Dictionary = standings[i]
		var a: float = ease.call((t - 0.6 - i * 0.07) / 0.3)
		if a <= 0.0:
			continue
		var you: bool = s.get("you", false)
		var out: bool = s.get("out", false)
		var rr := Rect2(at.x + 24 * (1.0 - a), y + i * (rh + 4), w, rh)
		if you:
			UiKit.glow(c, rr, a * 1.6)
		c.draw_rect(Rect2(rr.position.x, rr.end.y + 1, rr.size.x, 1), Color(1, 1, 1, 0.08 * a))
		var ink := Color(UiKit.INK_FAINT if out else UiKit.INK, a)
		var dim := Color(UiKit.INK if you else UiKit.INK_DIM, a * (0.5 if out else 1.0))
		var by := rr.position.y + rh * 0.5 + 8.0 * k2
		c.draw_string(UiKit.font("display", 0, true), Vector2(rr.position.x + cols[0][0] + 16, by + 2), str(i + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(28 * k2), ink)
		var nm := str(s.name).to_upper()
		var nw: float = cols[2][0] - cols[1][0] - 20
		if not you and s.has("color"):
			_draw_chip(c, Rect2(rr.position.x + cols[1][0] + 2, by - 16 * k2, 6, 16 * k2), Color(s.color, a))
		c.draw_string(UiKit.font("display"), Vector2(rr.position.x + cols[1][0] + 16, by), nm, HORIZONTAL_ALIGNMENT_LEFT, nw,
			int(22 * k2), ink)
		if out:
			var sw := minf(UiKit.text_width("display", nm, int(22 * k2)), nw)
			c.draw_line(Vector2(rr.position.x + cols[1][0] + 14, by - 7 * k2), Vector2(rr.position.x + cols[1][0] + 18 + sw, by - 7 * k2),
				ink, 2.0)
		var race: int = s.get("race", 0)
		var race_txt := ordinal(race).to_upper() if race > 0 else "—"
		if out and race == 0:
			race_txt = "OUT"
		c.draw_string(tf, Vector2(rr.position.x + cols[2][0] + 16, by - 1), race_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(19 * k2),
			Color(RED, a) if out and not you else dim)
		if timed:
			c.draw_string(tf, Vector2(rr.position.x + cols[4][0] + 16, by - 1), str(s.get("total", "")), HORIZONTAL_ALIGNMENT_LEFT,
				-1, int(19 * k2), ink)
			continue
		var gained: int = s.get("gained", 0)
		c.draw_string(tf, Vector2(rr.position.x + cols[3][0] + 16, by - 1), "+%d" % gained if gained > 0 else "", HORIZONTAL_ALIGNMENT_LEFT,
			-1, int(19 * k2), Color(UiKit.BG, a) if you else Color(GO, a * 0.9))
		c.draw_string(UiKit.font("display", 0, true), Vector2(rr.position.x + cols[4][0] + 16, by + 1), str(s.get("points", 0)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * k2), ink)
