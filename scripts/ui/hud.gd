class_name Hud
extends CanvasLayer
## Race HUD in the front end's style (see UiKit): segmented tach with speed and
## gear, position/lap/time blocks, minimap, framed rear-view mirror, banner
## messages and countdown, plus the pause and results screens.

const RED := UiKit.COP_RED
const GO := Color(0.35, 1.0, 0.5)
const M := 36.0

var race: Node
var player: Car
var pursuit := false

var _root: Control
var _draw: Control
var _mirror: TextureRect
var _mirror_vp: SubViewport
var _mirror_cam: Camera3D
var _loading: Control
var _loading_text := ""
var _pause: Control
var _pause_list: ActionList
var _results: Control
var _results_list: ActionList
var _results_data := {}
var _results_t := 0.0

var _msg := ""
var _msg_kind := ""
var _msg_t := 0.0
var _msg_len := 1.0
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.theme()
	add_child(_root)
	_setup_mirror()
	_draw = Control.new()
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_on_draw)
	_root.add_child(_draw)
	_build_pause()
	_loading = Control.new()
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.visible = false
	_loading.draw.connect(func():
		_loading.draw_rect(Rect2(Vector2.ZERO, _loading.size), Color.BLACK)
		_loading.draw_string(UiKit.font("display"), Vector2(48, _loading.size.y - 40 - 12), _loading_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 34, UiKit.INK))
	_root.add_child(_loading)


func _setup_mirror() -> void:
	_mirror_vp = SubViewport.new()
	_mirror_vp.size = Vector2i(400, 100)
	_mirror_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_mirror_vp)
	_mirror_cam = Camera3D.new()
	_mirror_cam.fov = 40
	_mirror_cam.far = 500
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
	_pause_list = ActionList.new(PackedStringArray(["Resume", "Restart", "Quit to menu"]))
	_pause_list.set_item_size(Vector2(330, 54))
	_pause_list.position = Vector2(48, 250)
	_pause_list.activated.connect(func(i: int): [_resume, _restart, _quit][i].call())
	_pause.add_child(_pause_list)


# ------------------------------------------------------------------ API

func show_loading(text: String) -> void:
	_loading_text = text.trim_suffix("...").to_upper()
	_loading.visible = true
	_loading.queue_redraw()


func hide_loading() -> void:
	_loading.visible = false
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


## Swaps in fresh rows (cars finishing behind the results screen) without replaying the intro.
func update_results(rows: Array) -> void:
	if _results:
		_results_data.rows = rows


## `rows`: [{name, time, best, you?, t?}] in finishing order.
func show_results(title: String, rows: Array, extra: String) -> void:
	_results_data = {"title": title, "rows": rows, "extra": extra}
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
	_results_list = ActionList.new(PackedStringArray(["Race again", "Main menu"]), true)
	_results_list.set_item_size(Vector2(240, 54))
	_results_list.activated.connect(func(i: int): [_restart, _quit][i].call())
	_results.add_child(_results_list)
	_results_list.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_results_list.position = Vector2(48, _root.size.y - 40 - 54 - 36)
	_results_list.modulate.a = 0.0
	create_tween().tween_property(_results_list, "modulate:a", 1.0, 0.3).set_delay(0.6)
	_set_mouse_look(false)
	_mirror.visible = false
	# The results title says it all; don't let a lingering banner overlap it.
	_msg_t = 0.0


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
			_pause_list.focus = 0
			_pause.modulate.a = 0.0
			create_tween().tween_property(_pause, "modulate:a", 1.0, 0.15)
			_set_mouse_look(false)
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("mirror") and _results == null and not get_tree().paused:
		_mirror.visible = not _mirror.visible


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


func _quit() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ------------------------------------------------------------------ per frame

func _process(dt: float) -> void:
	_time += dt
	_msg_t = maxf(_msg_t - dt, 0.0)
	if not get_tree().paused:
		_hint_t = maxf(_hint_t - dt, 0.0)
		_cam_toast_t = maxf(_cam_toast_t - dt, 0.0)
	if _results:
		_results_t += dt
		_results.get_child(1).queue_redraw()
	if _pause.visible:
		_pause.get_child(1).queue_redraw()
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
	_draw.queue_redraw()


func _on_draw() -> void:
	if player == null or not is_instance_valid(player) or race == null or race.path == null:
		return
	if _pause.visible or _results:
		return
	var size := _draw.size
	# Soft scrims behind the corner readouts so they hold up against a bright sky.
	_scrim(Vector2.ZERO, Vector2(420, 230))
	_scrim(Vector2(size.x, 0), Vector2(-360, 200))
	_scrim(Vector2(size.x, size.y), Vector2(-380, -300))
	if _mirror.visible:
		var mr := _mirror.get_rect()
		_draw.draw_rect(mr.grow(1), Color(1, 1, 1, 0.35), false, 1.0)
		UiKit.draw_slant(_draw, Rect2(mr.position.x + mr.size.x * 0.5 - 30, mr.end.y + 3, 60, 3), UiKit.ACCENT, 1.0)
	_draw_tach(Vector2(size.x - M - 118, size.y - M - 104))
	_draw_info(size)
	_draw_map(Rect2(M, size.y - M - 190, 190, 190))
	if pursuit:
		_draw_pursuit(size)
	_draw_banner(size)
	_draw_countdown(size)
	_draw_hints(size)


# ------------------------------------------------------------------ drawing

## A dark wash fading out from a screen corner; `ext` points into the screen.
func _scrim(corner: Vector2, ext: Vector2) -> void:
	var n := 20
	var pts := PackedVector2Array([corner])
	var cols := PackedColorArray([Color(0, 0, 0, 0.38)])
	for i in n + 1:
		var a := PI * 0.5 * i / n
		pts.append(corner + Vector2(cos(a) * ext.x, sin(a) * ext.y))
		cols.append(Color(0, 0, 0, 0.0))
	_draw.draw_polygon(pts, cols)


func _str(s: String, pos: Vector2, kind: String, fsize: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT,
		width := -1.0, tracking := 0, tabular := false) -> void:
	# A soft dark outline keeps text legible over bright sky without looking 1998.
	var f := UiKit.font(kind, tracking, tabular)
	_draw.draw_string_outline(f, pos, s, align, width, fsize, maxi(fsize / 7, 3), Color(0, 0, 0, 0.35 * color.a))
	_draw.draw_string(f, pos, s, align, width, fsize, color)


func _draw_tach(c: Vector2) -> void:
	var r := 104.0
	for k in 3:
		_draw.draw_circle(c, r + 26 - k * 10, Color(0, 0, 0, 0.14))
	# One scale for every car, so a lazy V12's redline sits well short of a racer's.
	var max_rpm := maxf(10000.0, ceilf(player.redline / 1000.0 + 1.0) * 1000.0)
	var a0 := deg_to_rad(140)
	var a1 := deg_to_rad(400)
	var segs := 40
	var frac := clampf(player.rpm / max_rpm, 0.0, 1.0)
	var red_frac := player.redline / max_rpm
	var shift := player.rpm > player.redline * 0.96 and fmod(_time * 12.0, 2.0) < 1.0
	var span := (a1 - a0) / segs
	for i in segs:
		var s0 := a0 + i * span + span * 0.12
		var s1 := s0 + span * 0.76
		var mid := (i + 0.5) / segs
		var in_red := mid >= red_frac
		var col := Color(1, 1, 1, 0.13) if not in_red else Color(RED, 0.3)
		if mid <= frac:
			col = RED if in_red or shift else (UiKit.ACCENT if mid > red_frac * 0.72 else UiKit.INK)
		# Segments thicken towards the top of the range, like a modern digital cluster.
		var w := lerpf(9.0, 15.0, mid)
		_draw.draw_arc(c, r - w * 0.5, s0, s1, 4, col, w, true)
	var kf := UiKit.font("cond", 0, true)
	for k in int(max_rpm / 1000.0) + 1:
		var a := lerpf(a0, a1, k * 1000.0 / max_rpm)
		var p := c + Vector2(cos(a), sin(a)) * (r - 30)
		_draw.draw_string(kf, p + Vector2(-8, 5), str(k), HORIZONTAL_ALIGNMENT_CENTER, 16, 13,
			Color(RED, 0.9) if k * 1000.0 >= player.redline else UiKit.INK_DIM)
	var spd := player.kmh() if Game.units_kmh else player.kmh() / 1.609
	_str("%d" % roundi(spd), c + Vector2(-80, 22), "display", 62, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER, 160, 0, true)
	_str("KM/H" if Game.units_kmh else "MPH", c + Vector2(-80, 44), "cond", 13, UiKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER, 160, 3)
	# Gear in a slanted chip in the gap at the bottom of the arc.
	var g := "R" if player.gear < 0 else ("N" if player.gear == 0 else str(player.gear))
	var gr := Rect2(c + Vector2(-22, r - 26), Vector2(44, 36))
	UiKit.draw_slant(_draw, gr, RED if player.gear < 0 else UiKit.ACCENT)
	_draw.draw_string(UiKit.font("display"), gr.position + Vector2(0, 29), g, HORIZONTAL_ALIGNMENT_CENTER, gr.size.x, 32, UiKit.BG)


func _draw_info(size: Vector2) -> void:
	var r: Dictionary = race.player_racer()
	if r.is_empty():
		return
	var x := M
	var y := M + 12
	var free_roam: bool = Game.mode == Game.Mode.FREE_ROAM
	if not free_roam:
		if Game.mode != Game.Mode.TIME_TRIAL:
			var pos: int = race.position_of(player)
			_str("POSITION", Vector2(x, y), "cond", 12, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
			_str(str(pos), Vector2(x - 2, y + 58), "display", 66, UiKit.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, 0, true)
			var pw := UiKit.text_width("display", str(pos), 66)
			_str("/%d" % race.racers.size(), Vector2(x + pw + 2, y + 58), "display", 26, UiKit.INK_DIM)
			x += 130
		var lap := clampi(r.lap + 1, 1, Game.laps)
		_str("LAP", Vector2(x, y), "cond", 12, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
		_str(str(lap), Vector2(x - 2, y + 58), "display", 66, UiKit.INK, HORIZONTAL_ALIGNMENT_LEFT, -1, 0, true)
		var lw := UiKit.text_width("display", str(lap), 66)
		_str("/%d" % Game.laps, Vector2(x + lw + 2, y + 58), "display", 26, UiKit.INK_DIM)
		# Lap progress under the whole block.
		var pr := Rect2(M, y + 72, x + 90 - M, 4)
		var frac := clampf(float(r.node) / maxf(race.path.size(), 1.0), 0.0, 1.0) if r.lap >= 0 else 0.0
		_draw.draw_rect(pr, Color(1, 1, 1, 0.15))
		_draw.draw_rect(Rect2(pr.position, Vector2(pr.size.x * frac, pr.size.y)), UiKit.ACCENT)
	if Game.mode == Game.Mode.HOT_PURSUIT:
		var ty := y + 104
		_str("TICKETS", Vector2(M, ty), "cond", 12, RED, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
		for k in race.MAX_TICKETS:
			var pr := Rect2(M + 72 + k * 26, ty - 11, 22, 12)
			UiKit.draw_slant(_draw, pr, RED if k < race.tickets else Color(1, 1, 1, 0.18), 0.5)
	# Timers, right-aligned. Nothing to time in free roam.
	if free_roam:
		return
	var rx := size.x - M
	var tw := 220.0
	_str("TIME", Vector2(rx - tw, y), "cond", 12, UiKit.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT, tw, 3)
	_str(fmt_time(race.race_time), Vector2(rx - tw, y + 44), "display", 44, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT, tw, 0, true)
	var lap_t: float = race.race_time - r.lap_start if r.lap >= 0 else 0.0
	_str("LAP  " + fmt_time(lap_t), Vector2(rx - tw, y + 68), "cond", 17, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT, tw, 1, true)
	_str("BEST  " + fmt_time(r.best), Vector2(rx - tw, y + 90), "cond", 17, UiKit.INK_DIM, HORIZONTAL_ALIGNMENT_RIGHT, tw, 1, true)


func _draw_pursuit(size: Vector2) -> void:
	var on := fmod(_time * 4.0, 2.0) < 1.0
	var col := RED if on else UiKit.COP_BLUE
	# Light bar washing in from both top corners.
	var a := 0.55
	var w := size.x * 0.35
	_draw.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(0, 90)]),
		PackedColorArray([Color(RED, a if on else 0.0), Color(RED, 0), Color(RED, 0)]))
	_draw.draw_polygon(PackedVector2Array([Vector2(size.x, 0), Vector2(size.x - w, 0), Vector2(size.x, 90)]),
		PackedColorArray([Color(UiKit.COP_BLUE, 0.0 if on else a), Color(UiKit.COP_BLUE, 0), Color(UiKit.COP_BLUE, 0)]))
	var br := Rect2(size.x * 0.5 - 80, 132, 160, 30)
	UiKit.draw_slant(_draw, br, col)
	_draw.draw_string(UiKit.font("display", 3), br.position + Vector2(0, 24), "PURSUIT", HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 24, UiKit.INK)
	# Heat level: one bar per level, like the ticket row.
	for k in 3:
		var hr := Rect2(size.x * 0.5 - 40 + k * 28, br.end.y + 8, 24, 8)
		UiKit.draw_slant(_draw, hr, RED if k < race.heat else Color(1, 1, 1, 0.18), 0.5)
	if player and player.tyres_flat():
		_str("FLAT TYRES", Vector2(size.x * 0.5 - 80, br.end.y + 36), "cond", 14, RED, HORIZONTAL_ALIGNMENT_CENTER, 160, 3)


func _draw_banner(size: Vector2) -> void:
	if _msg_t <= 0.0 or _msg == "":
		return
	var age := _msg_len - _msg_t
	var grow := clampf(age / 0.18, 0.0, 1.0)
	grow = 1.0 - pow(1.0 - grow, 3.0)
	var fade := clampf(_msg_t / 0.3, 0.0, 1.0)
	var fs := 40
	var f := UiKit.font("display", 1)
	var tw := f.get_string_size(_msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w := (tw + 80) * grow
	var r := Rect2(size.x * 0.5 - w * 0.5, 190, w, 58)
	var col := UiKit.ACCENT
	var ink := UiKit.BG
	match _msg_kind:
		"alert":
			col = RED
			ink = UiKit.INK
		"go":
			col = GO
	UiKit.draw_slant(_draw, Rect2(r.position + Vector2(6, 6), r.size), Color(0, 0, 0, 0.3 * fade))
	UiKit.draw_slant(_draw, r, Color(col, fade))
	if grow > 0.6:
		_draw.draw_string(f, Vector2(size.x * 0.5 - tw * 0.5, r.position.y + 44), _msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(ink, fade * (grow - 0.6) / 0.4))


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
	_draw.draw_string_outline(f, c + Vector2(-tw * 0.5, fs * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 14, Color(0, 0, 0, 0.3 * a))
	_draw.draw_string(f, c + Vector2(-tw * 0.5, fs * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiKit.INK, a))


func _draw_hints(size: Vector2) -> void:
	if _cam_toast_t > 0.0:
		var a := clampf(_cam_toast_t / 0.3, 0.0, 1.0)
		var txt := "CAMERA  ·  " + _cam_name.to_upper()
		_str(txt, Vector2(0, size.y - M - 4), "cond", 16, Color(UiKit.INK, a), HORIZONTAL_ALIGNMENT_CENTER, size.x, 3)
		return
	if _hint_t <= 0.0:
		return
	var hints := [["C", "CAMERA"], ["R", "RESET"], ["M", "MIRROR"], ["L", "LIGHTS"], ["ESC", "PAUSE"]]
	var w := 0.0
	for h in hints:
		w += UiKit.text_width("cond", h[0], 13, 1) + 12 + 7 + UiKit.text_width("cond", h[1], 13, 2) + 22
	var a := clampf(_hint_t / 0.6, 0.0, 1.0)
	_draw.draw_rect(Rect2(size.x * 0.5 - w * 0.5 - 12, size.y - M - 20, w + 12, 30), Color(0, 0, 0, 0.35 * a))
	UiKit.draw_hints(_draw, Vector2(size.x * 0.5 - w * 0.5, size.y - M - 5), hints, 13, a)


## Top-down view with +Z up the screen; +X (the driver's left when heading +Z) is then screen-left.
func _to_map(p: Vector3) -> Vector2:
	return _map_origin + Vector2(_map_max.x - p.x, _map_max.y - p.z) * _map_scale


func _draw_map(rect: Rect2) -> void:
	var path: TrackPath = race.path
	_draw.draw_rect(rect, Color(0.03, 0.035, 0.05, 0.45))
	_draw.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3)), UiKit.ACCENT)
	# The outline only depends on the track and the map rect; build it once, not every frame.
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
		_map_pts.append(_map_pts[0])
	_draw.draw_polyline(_map_pts, Color(0, 0, 0, 0.45), 7, true)
	_draw.draw_polyline(_map_pts, Color(1, 1, 1, 0.8), 3, true)
	# Start/finish: a short bar across the track, perpendicular to its direction at node 0.
	var s0 := _to_map(path.points[0])
	var across := (_to_map(path.points[1]) - s0).normalized().orthogonal() * 7.0
	_draw.draw_line(s0 - across, s0 + across, UiKit.ACCENT, 3)
	var blink := fmod(_time * 4.0, 2.0) < 1.0
	for c in race.cops:
		if is_instance_valid(c):
			var cc := RED if pursuit and blink else UiKit.COP_BLUE
			_draw.draw_circle(_to_map(c.global_position), 5, Color(0, 0, 0, 0.5))
			_draw.draw_circle(_to_map(c.global_position), 3.5, cc)
	for rr in race.racers:
		if rr.car == player:
			continue
		_draw.draw_circle(_to_map(rr.car.global_position), 5.5, Color(0, 0, 0, 0.5))
		_draw.draw_circle(_to_map(rr.car.global_position), 4, UiKit.INK)
	# The player as an arrow pointing along the car's heading.
	var p := _to_map(player.global_position)
	var fwd3 := player.global_transform.basis.z
	var d := Vector2(-fwd3.x, -fwd3.z).normalized()
	var n := d.orthogonal()
	var tri := PackedVector2Array([p + d * 9, p - d * 6 + n * 6, p - d * 3, p - d * 6 - n * 6])
	_draw.draw_colored_polygon(PackedVector2Array([p + d * 11, p - d * 8 + n * 8, p - d * 4, p - d * 8 - n * 8]), Color(0, 0, 0, 0.5))
	_draw.draw_colored_polygon(tri, UiKit.ACCENT)


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
			stats.append(["LAP", "%d / %d" % [clampi(r.lap + 1, 1, Game.laps), Game.laps]])
			stats.append(["TIME", fmt_time(race.race_time)])
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
	var arrested := title == "ARRESTED"
	var ease := func(x: float) -> float: return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)
	# Headline: "FINISHED 2nd" becomes a giant "2ND" with a small caption.
	var big := title
	var caption: String = Game.track_name(Game.track_id).to_upper() + "  ·  " + Game.MODE_NAMES[Game.mode].to_upper()
	if title.begins_with("FINISHED "):
		big = title.trim_prefix("FINISHED ").to_upper()
		caption = "FINISHED  ·  " + caption
	var k: float = ease.call(t / 0.4)
	var col := RED if arrested else UiKit.ACCENT
	c.draw_string(UiKit.font("cond", 3), Vector2(48, 110), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(col, k))
	c.draw_string(UiKit.font("display"), Vector2(46 - 30 * (1.0 - k), 200), big, HORIZONTAL_ALIGNMENT_LEFT, -1,
		96 if big.length() <= 4 else 72, Color(UiKit.INK, k))
	# Leaderboard.
	var x0 := 48.0
	var tw := minf(W - 96, 820.0)
	var cols := [[0.0, "POS"], [70.0, "DRIVER"], [tw - 330, "TIME"], [tw - 210, "BEST LAP"], [tw - 90, "GAP"]]
	var y := 250.0
	for cdef in cols:
		c.draw_string(UiKit.font("cond", 3), Vector2(x0 + cdef[0] + 16, y), cdef[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.INK_DIM)
	y += 12
	var lead_t := INF
	if rows.size() > 0 and rows[0].get("t", INF) is float:
		lead_t = rows[0].get("t", INF)
	# Rows shrink to fit between the header and the buttons (a full grid of 8 is tall).
	var extra: String = _results_data.extra
	var bottom := H - 40 - 54 - 36 - 28 - (34.0 if extra != "" else 0.0)
	var rh := clampf((bottom - y) / maxf(rows.size(), 1.0) - 4.0, 26.0, 40.0)
	var k2 := rh / 40.0
	for i in rows.size():
		var row: Dictionary = rows[i]
		var a: float = ease.call((t - 0.25 - i * 0.07) / 0.3)
		if a <= 0.0:
			continue
		var you: bool = row.get("you", false) or str(row.name).ends_with("(you)")
		var rr := Rect2(x0 - 24 * (1.0 - a), y + i * (rh + 4), tw, rh)
		UiKit.draw_slant(c, rr, Color(UiKit.ACCENT, 0.9 * a) if you else Color(1, 1, 1, 0.07 * a), 0.12)
		var ink := Color(UiKit.BG if you else UiKit.INK, a)
		var dim := Color(UiKit.BG if you else UiKit.INK_DIM, a * (0.8 if you else 1.0))
		var by := rr.position.y + rh * 0.5 + 8.0 * k2
		var tf := UiKit.font("cond", 1, true)
		c.draw_string(UiKit.font("display", 0, true), Vector2(rr.position.x + cols[0][0] + 16, by + 2), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, int(28 * k2), ink)
		var nm := str(row.name).trim_suffix("  (you)").to_upper()
		c.draw_string(UiKit.font("display"), Vector2(rr.position.x + cols[1][0] + 16, by), nm, HORIZONTAL_ALIGNMENT_LEFT, cols[2][0] - cols[1][0] - 20, int(22 * k2), ink)
		if you:
			var nw := minf(UiKit.text_width("display", nm, int(22 * k2)), cols[2][0] - cols[1][0] - 70)
			UiKit.draw_key(c, Vector2(rr.position.x + cols[1][0] + 16 + nw + 10, by - 7 * k2), "YOU", 11, UiKit.BG)
		c.draw_string(tf, Vector2(rr.position.x + cols[2][0] + 16, by - 1), str(row.time), HORIZONTAL_ALIGNMENT_LEFT, -1, int(19 * k2), ink)
		c.draw_string(tf, Vector2(rr.position.x + cols[3][0] + 16, by - 1), str(row.best), HORIZONTAL_ALIGNMENT_LEFT, -1, int(19 * k2), dim)
		var gap := ""
		var rt: Variant = row.get("t", INF)
		if i > 0 and rt is float and rt < INF and lead_t < INF:
			gap = "+%.2f" % (rt - lead_t)
		c.draw_string(tf, Vector2(rr.position.x + cols[4][0] + 16, by - 1), gap, HORIZONTAL_ALIGNMENT_LEFT, -1, int(19 * k2), dim)
	if extra != "":
		var ey := y + rows.size() * (rh + 4) + 26
		c.draw_string(UiKit.font("cond", 2), Vector2(x0 + 16, ey), extra.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			Color(RED, ease.call((t - 0.5) / 0.3)))
	_results_list.position = Vector2(48, H - 40 - 54 - 36)
	UiKit.draw_hints(c, Vector2(48, H - 40 - 8), [["←→", "SELECT"], ["ENTER", "CONFIRM"]])
