class_name LoadingScreen
extends Control
## The picture between the menu and the race, for the race Game is set up for: the track's
## postcard slowly closing in, your car on it (in 3D, with its driver, a Showroom going round
## it slowly) with its name large and its figures, the track's map with what's being raced
## (the mode, or the tournament and which race of its circuit), the track's name and the
## race's facts, a tip, and a bar with what's being done. The menu fades it in over itself and the race scene
## opens on the same picture, so the two join up; the race moves the bar through its stages
## (the track loads on a worker thread, so all this keeps moving) and fades it out at the end.

signal finished

const M := 40.0
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
	["tournament", "After the first race the grid lines up by the standings: lead them and start on pole."],
	["tournament", "Damage stays with the car until it's repaired: between races, or in the garage."],
	["tournament", "Upgrades are bought in the garage, a level at a time. Selling a car gets back part of what it cost."],
	["tournament", "Finish a circuit in the top three for a trophy. Win a Pro Cup and its bonus car is yours."],
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
var _car_kick := ""             # "Your car · Porsche · class B"
var _car_line := ""             # its figures: "160 bhp · 227 km/h · 1,030 kg"
var _tip := ""
var _map: TrackMap
var _back: Control              # the picture, under the car
var _view: Showroom             # your car
var _time := 0.0
var _progress := 0.0            # shown
var _target := 0.0
var _cap := 0.0                 # the current stage creeps toward this while it runs
var _stage := "Getting ready"
var _done := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Drawn before this one's own drawing (the words go over the car): the picture, then the car.
	_back = Control.new()
	_back.show_behind_parent = true
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_back.draw.connect(_draw_back)
	add_child(_back)
	_view = Showroom.new()
	_view.loading = true
	_view.show_behind_parent = true
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_view)
	_map = TrackMap.new()
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map)
	resized.connect(_layout)
	_read_game()


## What's about to be raced, from Game.
func _read_game() -> void:
	var id := Game.track_id
	_tex = TrackPostcards.cached(id, Game.night)
	_view.set_backdrop(_tex)
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
				var which: String = c.name.to_upper() if c.has("name") else "CIRCUIT %d" % (t.circuits.find(run.circuit) + 1)
				_over = "%s  ·  %s  ·  RACE %d OF %d" % [t.name.to_upper(), which, run.race + 1, c.races.size()]
		tips.append("tournament")
	var facts := PackedStringArray()
	if Game.is_hp2_track(id):
		_over += "  ·  HOT PURSUIT 2"
	elif Game.is_pu_track(id):
		_over += "  ·  PORSCHE UNLEASHED"
	elif Game.is_hs_track(id):
		_over += "  ·  HIGH STAKES"
	elif id != Game.PROCEDURAL_TRACK:
		_over += "  ·  NEED FOR SPEED III"
	if Game.layout > 0:
		facts.append(Game.LAYOUTS[Game.layout])
	if m != Game.Mode.FREE_ROAM:
		if Game.is_sprint(id):
			facts.append("Point to point")
		else:
			facts.append("%d lap%s" % [Game.laps, "" if Game.laps == 1 else "s"])
	if m == Game.Mode.SINGLE_RACE or m == Game.Mode.SPECTATE or m == Game.Mode.HOT_PURSUIT:
		var n := Game.opponents
		facts.append("%d rival%s" % [n, "" if n == 1 else "s"])
	facts.append("Night" if Game.night else "Day")
	if Game.weather:
		var dir := Game.track_dir(id)
		var snow := dir != "" and Nfs3Horizon.peek_precip(dir) == Nfs3Horizon.Precip.SNOW
		facts.append("Snow" if snow else "Rain")
	if m != Game.Mode.TIME_TRIAL and Game.traffic:
		facts.append("Traffic")
	_facts = "  ·  ".join(facts)
	if Game.car_index < Game.cars.size():
		_read_car(Game.car_index)
	var pts := ProceduralTrack.outline() if id == Game.PROCEDURAL_TRACK else Nfs3Track.peek_outline(Game.track_dir(id))
	if Game.layout_mirrored():
		for i in pts.size():
			pts[i].x = -pts[i].x
	_map.set_outline(pts, _handoff.is_empty(), Game.is_sprint(id))
	var pool := TIPS.filter(func(t: Array) -> bool: return t[0] in tips)
	_tip = pool[randi() % pool.size()][1]
	if not _handoff.is_empty():
		_tip = _handoff.tip
		_time = _handoff.time
		_handoff = {}
	_view.set_clock(_time)


## Your car on the stage (once it's in the tree: the car finds its place on it).
func _ready() -> void:
	if Game.car_index < Game.cars.size():
		var i := Game.car_index
		var data: Object = Game.own_car(i)
		var up := Game.upgrade_of(i) if Game.circuit_run.is_empty() else Game.garage_upgrade(i)
		_view.show_car(data, Game.paint_tint(i, data), up, i, 0.0)


## The menu's, as it hands over to the race scene: the next one carries on from this one.
func hand_over() -> void:
	_handoff = {"tip": _tip, "time": _time}


## A stage of the loading has begun: `label` says what, the bar goes to `from` and creeps
## toward `to` until the next stage.
func stage(label: String, from: float, to: float) -> void:
	_stage = label
	_target = maxf(_target, from)
	_cap = to
	queue_redraw()


## Loaded: the bar fills, then the picture fades away (and frees itself).
func finish() -> void:
	if _done:
		return
	_done = true
	_stage = "Ready"
	_target = 1.0
	var tw := create_tween()
	tw.tween_interval(0.2)
	tw.tween_property(self, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): finished.emit(); queue_free())


## Your car's lockup: its name, what it is, and its figures as the game has them.
func _read_car(i: int) -> void:
	var spec := Game.car_spec(i)
	var info: Dictionary = spec.info if "info" in spec else {}
	_car = str(Game.cars[i].name).to_upper()
	var kick := PackedStringArray(["Your car"])
	var cls := int(spec.carp_value(1, -1.0)) if "carp" in spec and spec.carp.has(1) else -1
	if cls >= 0 and cls <= 2:
		kick.append("class " + "ABC"[cls])
	var up := Game.upgrade_of(i) if Game.circuit_run.is_empty() else Game.garage_upgrade(i)
	if up > 0:
		kick.append(Car.UPGRADE_NAMES[up].to_lower() + " upgrades")
	_car_kick = "  ·  ".join(kick)
	var fig := PackedStringArray()
	var power := str(info.get("power", "")).to_lower()
	if power.contains("bhp"):
		fig.append(power.split("bhp")[0].strip_edges() + " bhp")
	var kmh: float = spec.carp_value(15, 70.0) * 3.6 * Car.upgrade_mults(up).w
	fig.append(("%d km/h" % roundi(kmh)) if Game.units_kmh else ("%d mph" % roundi(kmh / 1.609)))
	var t := CarStats.zero_to_100(spec, up)
	if t > 0.0:
		fig.append(("0-100 %.1f s" if Game.units_kmh else "0-62 %.1f s") % t)
	var kg: float = spec.carp_value(2, 1400.0)
	fig.append(UiKit.money(roundi(kg if Game.units_kmh else kg * 2.2046)).trim_prefix("$") + (" kg" if Game.units_kmh else " lb"))
	_car_line = " · ".join(fig)


func _layout() -> void:
	var w := minf(340.0, size.x * 0.26)
	_map.size = Vector2(w, w * 0.8)
	_map.position = Vector2(size.x - M - w, 110.0)
	# The car between the words down the left and the map, above the track's name.
	var x0 := size.x * 0.3
	_view.set_region(Rect2(x0, 90.0, _map.position.x - 30.0 - x0, size.y * 0.62 - 90.0))


func _process(dt: float) -> void:
	_time += dt
	if not _done and _target < _cap:
		# Ease toward the stage's end without ever reaching it: how long a stage takes isn't known.
		_target += (_cap - _target) * (1.0 - exp(-dt * 0.9))
	_progress = UiKit.damp(_progress, _target, 10.0, dt)
	queue_redraw()
	_back.queue_redraw()


## The track's picture, darkened where the words go, under the car.
func _draw_back() -> void:
	var W := size.x
	var H := size.y
	var b := _back
	b.draw_rect(Rect2(Vector2.ZERO, size), UiKit.BG)
	if _tex:
		# Covering the screen, closing in slowly.
		var ts := _tex.get_size()
		var s := maxf(W / ts.x, H / ts.y) * (1.04 + 0.05 * (1.0 - exp(-_time * 0.12)))
		var d := ts * s
		b.draw_texture_rect(_tex, Rect2((size - d) * Vector2(0.5, 0.45), d), false, Color(0.62, 0.62, 0.66))
	_grad(b, Rect2(0, 0, W * 0.7, H), Color(UiKit.BG, 0.85), Color(UiKit.BG, 0.0), true)
	_grad(b, Rect2(0, H * 0.45, W, H * 0.55), Color(UiKit.BG, 0.0), Color(UiKit.BG, 0.95), false)
	_grad(b, Rect2(0, 0, W, 140), Color(UiKit.BG, 0.8), Color(UiKit.BG, 0.0), false)


func _draw() -> void:
	var W := size.x
	var H := size.y
	# Over the car: the foot of the screen darkened again for the words.
	_grad(self, Rect2(0, H * 0.7, W, H * 0.3), Color(UiKit.BG, 0.0), Color(UiKit.BG, 0.8), false)
	# The logo, as the menu's bar has it.
	var lf := UiKit.font("display")
	draw_string(lf, Vector2(M, 44), "NFS", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UiKit.ACCENT)
	var lw := lf.get_string_size("NFS", HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	draw_string(UiKit.font("cond_med", 5), Vector2(M + lw + 8, 43), "REVIVAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, UiKit.INK)
	# The map (open start to flag on a point-to-point run) and what's being raced under it:
	# the mode (or tournament), the track's name, the race's facts.
	var mx := _map.position.x
	var mw := _map.size.x
	var bf := UiKit.font("body")
	if _map.length_m > 0.0:
		var km := _map.length_m / 1000.0
		UiKit.kicker(self, Vector2(mx, _map.position.y - 12), "Route" if _map.open else "The lap", mw)
		draw_string(bf, Vector2(mx, _map.position.y - 12), UiKit.dist(km), HORIZONTAL_ALIGNMENT_RIGHT, mw, 15, UiKit.INK_DIM)
	var ty := _map.position.y + _map.size.y + 34
	UiKit.kicker(self, Vector2(mx, ty + 13), _over, mw, _over_col)
	var tfs := UiKit.fit("display", _title, mw, 30, 18)
	draw_string(lf, Vector2(mx - 2, ty + 18 + tfs * 0.92), _title, HORIZONTAL_ALIGNMENT_LEFT, mw, tfs, UiKit.INK)
	draw_string(bf, Vector2(mx, ty + 18 + tfs * 0.92 + 24), _facts, HORIZONTAL_ALIGNMENT_LEFT, mw,
		UiKit.fit("body", _facts, mw, 15, 11), UiKit.INK_DIM)
	# Your car, bottom left, under it on the stage: what it is, its name large, its figures.
	var bar_y := H - 40.0
	var tip_y := bar_y - 46.0
	var line_y := tip_y - 40.0
	var name_y := line_y - 30.0
	var max_w := W - M * 3 - mw
	if _car != "":
		var fs := UiKit.fit("display", _car, max_w, 96, 40)
		UiKit.kicker(self, Vector2(M, name_y - fs * 0.86 - 16), _car_kick, max_w)
		draw_string(lf, Vector2(M - 3, name_y), _car, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.INK)
		draw_string(bf, Vector2(M, line_y), _car_line, HORIZONTAL_ALIGNMENT_LEFT, max_w, 18, Color(UiKit.INK, 0.85))
	# A tip.
	UiKit.kicker(self, Vector2(M, tip_y), "Tip", 40)
	draw_string(bf, Vector2(M + 40, tip_y), _tip, HORIZONTAL_ALIGNMENT_LEFT, W - M * 2 - 40, 15, UiKit.INK_DIM)
	# The progress: what's being done and how far, over a thin line with a sheen.
	var br := Rect2(M, bar_y, W - M * 2, 3)
	draw_rect(br, Color(1, 1, 1, 0.14))
	var fw := br.size.x * clampf(_progress, 0.0, 1.0)
	draw_rect(Rect2(br.position, Vector2(fw, br.size.y)), UiKit.ACCENT)
	var sx := br.position.x + fmod(_time * 260.0, maxf(fw + 120.0, 1.0)) - 60.0
	if fw > 8.0:
		var a := clampf(sx - br.position.x, 0.0, fw)
		var b := clampf(sx + 60.0 - br.position.x, 0.0, fw)
		if b > a:
			draw_rect(Rect2(br.position.x + a, br.position.y, b - a, br.size.y), Color(1, 0.95, 0.75, 0.8))
	var dots := "…" if not _done else ""
	draw_string(bf, Vector2(M, bar_y - 12), _stage + dots, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiKit.INK_DIM)
	draw_string(UiKit.font("cond", 1, true), Vector2(M, bar_y - 12), "%d%%" % roundi(_progress * 100.0),
		HORIZONTAL_ALIGNMENT_RIGHT, br.size.x, 14, UiKit.INK)


static func _grad(ci: CanvasItem, r: Rect2, from: Color, to: Color, horizontal: bool) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	ci.draw_polygon(pts, PackedColorArray([from, to, to, from]) if horizontal else PackedColorArray([from, from, to, to]))
