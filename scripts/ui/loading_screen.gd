class_name LoadingScreen
extends Control
## The picture between the menu and the race, for the race Game is set up for: the track's
## postcard slowly closing in, what's being raced (the mode, or the tournament and which
## race of its circuit), the track's name and the race's facts, its map, your car, a tip,
## and a bar with what's being done. The menu fades it in over itself and the race scene
## opens on the same picture, so the two join up; the race moves the bar through its stages
## (the track loads on a worker thread, so all this keeps moving) and fades it out at the end.

signal finished

const M := 48.0
const TIPS := [
	["", "F1 hides the HUD. Settings → HUD picks which parts of it show."],
	["", "C cycles the cameras, the trackside TV cameras among them."],
	["", "R puts your car back on the road."],
	["", "B looks back; M shows or hides the rear-view mirror."],
	["", "L switches the headlights on, K the high beams."],
	["", "Space is the handbrake: a tug of it swings the tail round a hairpin."],
	["", "Reverse and Mirror (the race options) make three more tracks of every one."],
	["", "Upgrades (the race options) sharpen acceleration, braking, handling and top speed."],
	["", "Settings → Rival cars decides whether the AI's cars are upgraded like yours."],
	["pursuit", "Stop with a cop on you and you're ticketed. The third ticket is an arrest."],
	["pursuit", "Get more than 380 m clear of the police and they give up the chase."],
	["pursuit", "The longer a chase, the higher the heat: roadblocks, then spike strips."],
	["pursuit", "Speed past a parked cruiser and it comes after you, lights and siren."],
	["tournament", "Win every circuit of a tournament to open the next ones."],
	["tournament", "A knockout drops the last car home after every race."],
]

## What the menu's loading screen left for the race scene's to pick up, so the two join up
## without the tip changing or the picture jumping: {tip, time}.
static var _handoff := {}

var _tex: Texture2D
var _title := ""
var _over := ""                 # the mode, or the tournament and race
var _over_col := UiKit.ACCENT
var _facts := ""
var _car := ""
var _tip := ""
var _map: TrackMap
var _time := 0.0
var _progress := 0.0            # shown
var _target := 0.0
var _cap := 0.0                 # the current stage creeps toward this while it runs
var _stage := ""
var _done := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_map = TrackMap.new()
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map)
	resized.connect(_layout)
	_read_game()


## What's about to be raced, from Game.
func _read_game() -> void:
	var id := Game.track_id
	_tex = TrackPostcards.cached(id, Game.night)
	_title = Game.track_name(id).to_upper()
	var m := Game.mode
	_over = Game.MODE_NAMES[m].to_upper()
	_over_col = UiKit.COP_RED if m == Game.Mode.HOT_PURSUIT else UiKit.ACCENT
	var tips := ["", "pursuit" if m == Game.Mode.HOT_PURSUIT else ""]
	if not Game.circuit_run.is_empty() and Game.career_data():
		var run := Game.circuit_run
		var c: Dictionary = Game.career_data().circuits.get(run.circuit, {})
		for t in Game.career_data().tournaments:
			if t.id == run.tournament and not c.is_empty():
				_over = "%s  ·  CIRCUIT %d  ·  RACE %d OF %d" % [t.name.to_upper(), t.circuits.find(run.circuit) + 1,
					run.race + 1, c.races.size()]
		tips.append("tournament")
	var facts := PackedStringArray()
	if Game.is_hs_track(id):
		facts.append("HIGH STAKES")
	elif id != Game.PROCEDURAL_TRACK:
		facts.append("NEED FOR SPEED III")
	if Game.layout > 0:
		facts.append(Game.LAYOUTS[Game.layout].to_upper())
	if m != Game.Mode.FREE_ROAM:
		facts.append("%d LAP%s" % [Game.laps, "" if Game.laps == 1 else "S"])
	if m == Game.Mode.SINGLE_RACE or m == Game.Mode.SPECTATE or m == Game.Mode.HOT_PURSUIT:
		var n := Game.opponents
		facts.append("%d RIVAL%s" % [n, "" if n == 1 else "S"])
	facts.append("NIGHT" if Game.night else "DAY")
	if Game.weather:
		var dir := Game.track_dir(id)
		var snow := dir != "" and Nfs3Horizon.peek_precip(dir) == Nfs3Horizon.Precip.SNOW
		facts.append("SNOW" if snow else "RAIN")
	if m != Game.Mode.TIME_TRIAL and Game.traffic:
		facts.append("TRAFFIC")
	_facts = "   ·   ".join(facts)
	if Game.car_index < Game.cars.size():
		_car = str(Game.cars[Game.car_index].name).to_upper()
	var pts := ProceduralTrack.outline() if id == Game.PROCEDURAL_TRACK else Nfs3Track.peek_outline(Game.track_dir(id))
	if Game.layout_mirrored():
		for i in pts.size():
			pts[i].x = -pts[i].x
	_map.set_outline(pts, _handoff.is_empty())
	var pool := TIPS.filter(func(t: Array) -> bool: return t[0] in tips)
	_tip = pool[randi() % pool.size()][1]
	if not _handoff.is_empty():
		_tip = _handoff.tip
		_time = _handoff.time
		_handoff = {}


## The menu's, as it hands over to the race scene: the next one carries on from this one.
func hand_over() -> void:
	_handoff = {"tip": _tip, "time": _time}


## A stage of the loading has begun: `label` says what, the bar goes to `from` and creeps
## toward `to` until the next stage.
func stage(label: String, from: float, to: float) -> void:
	_stage = label.to_upper()
	_target = maxf(_target, from)
	_cap = to
	queue_redraw()


## Loaded: the bar fills, then the picture fades away (and frees itself).
func finish() -> void:
	if _done:
		return
	_done = true
	_stage = "READY"
	_target = 1.0
	var tw := create_tween()
	tw.tween_interval(0.2)
	tw.tween_property(self, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): finished.emit(); queue_free())


func _layout() -> void:
	var w := minf(300.0, size.x * 0.24)
	_map.size = Vector2(w, w * 0.72)
	_map.position = Vector2(size.x - M - w, maxf(size.y * 0.5 - _map.size.y - 20.0, 110.0))


func _process(dt: float) -> void:
	_time += dt
	if not _done and _target < _cap:
		# Ease toward the stage's end without ever reaching it: how long a stage takes isn't known.
		_target += (_cap - _target) * (1.0 - exp(-dt * 0.9))
	_progress = UiKit.damp(_progress, _target, 10.0, dt)
	queue_redraw()


func _draw() -> void:
	var W := size.x
	var H := size.y
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.BG)
	if _tex:
		# Covering the screen, closing in slowly.
		var ts := _tex.get_size()
		var s := maxf(W / ts.x, H / ts.y) * (1.04 + 0.05 * (1.0 - exp(-_time * 0.12)))
		var d := ts * s
		draw_texture_rect(_tex, Rect2((size - d) * Vector2(0.5, 0.45), d), false, Color(0.62, 0.62, 0.66))
	_grad(Rect2(0, 0, W * 0.7, H), Color(UiKit.BG, 0.85), Color(UiKit.BG, 0.0), true)
	_grad(Rect2(0, H * 0.45, W, H * 0.55), Color(UiKit.BG, 0.0), Color(UiKit.BG, 0.95), false)
	_grad(Rect2(0, 0, W, 130), Color(UiKit.BG, 0.6), Color(UiKit.BG, 0.0), false)
	# Logo.
	var lf := UiKit.font("display")
	draw_string(lf, Vector2(M, 58), "NFS", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, UiKit.ACCENT)
	var lw := lf.get_string_size("NFS", HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	draw_string(UiKit.font("cond_med", 6), Vector2(M + lw + 10, 57), "REVIVAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UiKit.INK)
	UiKit.draw_slant(self, Rect2(M, 68, 132, 3), UiKit.ACCENT, 0.9)
	# The map and your car, right.
	var mx := _map.position.x
	var mw := _map.size.x
	var cf := UiKit.font("cond", 3)
	draw_string(cf, Vector2(mx, _map.position.y - 10), "TRACK", HORIZONTAL_ALIGNMENT_LEFT, mw, 12, UiKit.ACCENT)
	if _map.length_m > 0.0:
		var km := _map.length_m / 1000.0
		var len := "%.1f KM LAP" % km if Game.units_kmh else "%.1f MI LAP" % (km / 1.609)
		draw_string(cf, Vector2(mx, _map.position.y - 10), len, HORIZONTAL_ALIGNMENT_RIGHT, mw, 12, UiKit.INK_DIM)
	var cy := _map.position.y + _map.size.y + 40
	if _car != "":
		draw_string(cf, Vector2(mx, cy), "YOUR CAR", HORIZONTAL_ALIGNMENT_RIGHT, mw, 12, UiKit.ACCENT)
		var fs := 30
		while fs > 16 and lf.get_string_size(_car, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > mw + 60:
			fs -= 2
		draw_string(lf, Vector2(W - M - 400, cy + 34), _car, HORIZONTAL_ALIGNMENT_RIGHT, 400, fs, UiKit.INK)
	# What's being raced, bottom left.
	var bar_y := H - 44.0
	var tip_y := bar_y - 44.0
	var facts_y := tip_y - 44.0
	var name_y := facts_y - 30.0
	var fs := 84
	var max_w := W * 0.62
	while fs > 40 and lf.get_string_size(_title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		fs -= 4
	draw_string(cf, Vector2(M, name_y - fs * 0.86 - 14), _over, HORIZONTAL_ALIGNMENT_LEFT, max_w, 15, _over_col)
	draw_string(lf, Vector2(M - 3, name_y), _title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.INK)
	draw_string(UiKit.font("cond", 2), Vector2(M, facts_y), _facts, HORIZONTAL_ALIGNMENT_LEFT, W - M * 2, 15, UiKit.INK_DIM)
	# A tip.
	var kw := UiKit.draw_key(self, Vector2(M, tip_y - 5), "TIP", 12, UiKit.ACCENT)
	draw_string(UiKit.font("body"), Vector2(M + kw + 12, tip_y), _tip, HORIZONTAL_ALIGNMENT_LEFT, W - M * 2 - kw - 12, 15,
		Color(UiKit.INK, 0.8))
	# The bar, with the stage over it and a sheen running along what's done.
	var br := Rect2(M, bar_y, W - M * 2, 4)
	draw_rect(br, Color(1, 1, 1, 0.12))
	var fw := br.size.x * clampf(_progress, 0.0, 1.0)
	draw_rect(Rect2(br.position, Vector2(fw, br.size.y)), UiKit.ACCENT)
	var sx := br.position.x + fmod(_time * 260.0, maxf(fw + 120.0, 1.0)) - 60.0
	if fw > 8.0:
		var a := clampf(sx - br.position.x, 0.0, fw)
		var b := clampf(sx + 60.0 - br.position.x, 0.0, fw)
		if b > a:
			draw_rect(Rect2(br.position.x + a, br.position.y, b - a, br.size.y), Color(1, 0.95, 0.75, 0.8))
	var dots := ".".repeat(int(_time * 3.0) % 4) if not _done else ""
	draw_string(cf, Vector2(M, bar_y - 12), _stage + dots, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.INK_DIM)
	draw_string(UiKit.font("cond", 2, true), Vector2(M, bar_y - 12), "%d%%" % roundi(_progress * 100.0),
		HORIZONTAL_ALIGNMENT_RIGHT, br.size.x, 13, UiKit.INK)


func _grad(r: Rect2, from: Color, to: Color, horizontal: bool) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	draw_polygon(pts, PackedColorArray([from, to, to, from]) if horizontal else PackedColorArray([from, from, to, to]))
