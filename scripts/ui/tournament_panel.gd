class_name TournamentPanel
extends Control
## High Stakes' tournaments (HsCareer), a screen of the front end: the tournaments down the
## left (won, locked, one-make), the chosen one's circuits on the right with how they're run
## (laps, rivals, entry fee, first prize, your best result), and the focused circuit's races
## as postcards. Choosing a circuit goes on to the car; winning every circuit of a
## tournament opens the next ones.

signal chosen(tournament: Dictionary, circuit: int)
signal focus_changed
signal back

const LIST_W := 330.0
const T_ROW := 42.0
const C_ROW := 56.0
const KINDS := ["CIRCUIT", "KNOCKOUT", "CAR RACE"]

## (track id, night) -> Texture2D or null, for the races' pictures.
var postcard: Callable

var _tours: Array = []
var _ti := 0                  # tournament
var _ci := 0                  # circuit within it
var _hover_t := -1
var _hover_c := -1
var _message := ""
var _message_t := 0.0


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP


func open() -> void:
	var career := Game.career_data()
	var first := _tours.is_empty()
	_tours = career.tournaments if career else []
	_message = ""
	visible = true
	queue_redraw()
	if not first:
		focus_changed.emit()
		return
	# The first time, start on the first open circuit not yet won.
	_ti = 0
	_ci = 0
	var found := false
	for i in _tours.size():
		if not Game.tournament_open(_tours[i]):
			continue
		for k in _tours[i].circuits.size():
			if int(Game.career_won.get(_tours[i].circuits[k], 99)) != 1 and not found:
				_ti = i
				_ci = k
				found = true
	visible = true
	queue_redraw()
	focus_changed.emit()


func close() -> void:
	visible = false


func tournament() -> Dictionary:
	return _tours[_ti] if _ti < _tours.size() else {}


func circuit() -> Dictionary:
	var t := tournament()
	if t.is_empty() or _ci >= t.circuits.size():
		return {}
	return Game.career_data().circuits.get(t.circuits[_ci], {})


## The first track of the focused circuit, for the backdrop.
func focus_track() -> String:
	var c := circuit()
	return HsCareer.track_id(c.races[0].track) if not c.is_empty() and not c.races.is_empty() else ""


## Why the focused circuit can't be entered ("" if it can), the car aside.
func blocked() -> String:
	var t := tournament()
	var c := circuit()
	if c.is_empty():
		return "Nothing to enter"
	if not Game.tournament_open(t):
		return "Locked"
	if Game.career_money < c.fee:
		return "Entry fee $%s: not enough money" % money(c.fee)
	for r: Dictionary in c.races:
		if HsCareer.track_id(r.track) == "":
			return "A track of this circuit isn't installed"
	return ""


func choose() -> void:
	var why := blocked()
	if why != "":
		_say(why)
		return
	chosen.emit(tournament(), circuit().id)


func _say(text: String) -> void:
	_message = text
	_message_t = 3.0
	queue_redraw()


func _move(dir: int) -> void:
	var n: int = tournament().get("circuits", []).size()
	var k := _ci + dir
	if k < 0 and _ti > 0:
		_ti -= 1
		_ci = _tours[_ti].circuits.size() - 1
	elif k >= n and _ti < _tours.size() - 1:
		_ti += 1
		_ci = 0
	else:
		_ci = clampi(k, 0, n - 1)
	_message = ""
	queue_redraw()
	focus_changed.emit()


func _move_tournament(dir: int) -> void:
	var i := clampi(_ti + dir, 0, _tours.size() - 1)
	if i == _ti:
		return
	_ti = i
	_ci = 0
	_message = ""
	queue_redraw()
	focus_changed.emit()


# ------------------------------------------------------------------ layout

func _t_rect(i: int) -> Rect2:
	return Rect2(0, 8 + i * T_ROW, LIST_W, T_ROW - 4)


func _right_x() -> float:
	return LIST_W + 36.0


func _c_rect(k: int) -> Rect2:
	var x := _right_x()
	return Rect2(x, 104 + k * C_ROW, size.x - x, C_ROW - 4)


# ------------------------------------------------------------------ input

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var ht := -1
		var hc := -1
		for i in _tours.size():
			if _t_rect(i).has_point(e.position):
				ht = i
		for k in tournament().get("circuits", []).size():
			if _c_rect(k).has_point(e.position):
				hc = k
		if ht != _hover_t or hc != _hover_c:
			_hover_t = ht
			_hover_c = hc
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if ht >= 0 or hc >= 0 else Control.CURSOR_ARROW
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				if _hover_t >= 0:
					_move_tournament(_hover_t - _ti)
				elif _hover_c >= 0:
					if _hover_c == _ci:
						choose()
					else:
						_move(_hover_c - _ci)
			MOUSE_BUTTON_RIGHT:
				back.emit()
			MOUSE_BUTTON_WHEEL_UP:
				_move(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_move(1)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and (_hover_t >= 0 or _hover_c >= 0):
		_hover_t = -1
		_hover_c = -1
		queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var key := e as InputEventKey
	if e.is_action_pressed("ui_down", true):
		_move(1)
	elif e.is_action_pressed("ui_up", true):
		_move(-1)
	elif e.is_action_pressed("ui_left", true) or (key and key.pressed and key.physical_keycode == KEY_PAGEUP):
		_move_tournament(-1)
	elif e.is_action_pressed("ui_right", true) or (key and key.pressed and key.physical_keycode == KEY_PAGEDOWN):
		_move_tournament(1)
	elif (key and key.pressed and not key.echo and not key.alt_pressed and key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]) \
			or (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_A):
		choose()
	elif e.is_action_pressed("ui_cancel"):
		back.emit()
	else:
		return
	get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	if _message_t > 0.0:
		_message_t -= dt
		if _message_t <= 0.0:
			_message = ""
			queue_redraw()


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var cf := UiKit.font("cond", 2)
	var df := UiKit.font("display")
	# The tournaments.
	draw_rect(Rect2(-12, 0, LIST_W + 24, size.y), Color(0.04, 0.045, 0.06, 0.9))
	draw_rect(Rect2(-12, 0, LIST_W + 24, 3), UiKit.ACCENT)
	if _tours.is_empty():
		draw_string(UiKit.font("body"), Vector2(_right_x(), 40), "The tournaments come with a High Stakes install (see README).",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.INK_DIM)
		return
	for i in _tours.size():
		var t: Dictionary = _tours[i]
		var r := _t_rect(i)
		var open := Game.tournament_open(t)
		var now := i == _ti
		if now:
			UiKit.draw_slant(self, r, Color(1, 1, 1, 0.1), 0.1)
			UiKit.draw_slant(self, Rect2(r.position, Vector2(4, r.size.y)), UiKit.ACCENT, 0.1)
		elif i == _hover_t:
			UiKit.draw_slant(self, r, Color(1, 1, 1, 0.05), 0.1)
		var won := _won(t)
		var col := UiKit.INK if now else (Color(UiKit.INK, 0.85) if open else UiKit.INK_FAINT)
		if not open:
			_lock(Vector2(r.position.x + 22, r.get_center().y), UiKit.INK_FAINT)
		elif won == t.circuits.size():
			_tick(Vector2(r.position.x + 22, r.get_center().y), UiKit.ACCENT)
		draw_string(df, Vector2(r.position.x + 40, r.get_center().y + 7), t.name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
			r.size.x - 120, 20, col)
		var note := "%d / %d" % [won, t.circuits.size()] if open else ""
		draw_string(cf, Vector2(r.position.x, r.get_center().y + 5), note, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 14, 13,
			UiKit.ACCENT if now else UiKit.INK_DIM)
	# The chosen tournament.
	var t := tournament()
	var x := _right_x()
	var w := size.x - x
	var open := Game.tournament_open(t)
	draw_string(cf, Vector2(x, 20), "MONEY", HORIZONTAL_ALIGNMENT_RIGHT, w - 120, 13, UiKit.INK_DIM)
	draw_string(UiKit.font("display", 0, true), Vector2(x, 24), "$" + money(Game.career_money), HORIZONTAL_ALIGNMENT_RIGHT, w,
		26, UiKit.ACCENT)
	draw_string(df, Vector2(x, 44), t.name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w - 260, 38, UiKit.INK)
	var sub := PackedStringArray()
	sub.append("%d CIRCUIT%s" % [t.circuits.size(), "" if t.circuits.size() == 1 else "S"])
	if not open:
		var by := _opened_by(t)
		sub.append("LOCKED: WIN EVERY CIRCUIT OF %s TO OPEN IT" % by.to_upper() if by != "" else "LOCKED")
	else:
		sub.append("%d WON" % _won(t))
	if not t.unlocks.is_empty():
		var names := PackedStringArray()
		for u in t.unlocks:
			for o in _tours:
				if o.id == u:
					names.append(o.name)
		sub.append("OPENS " + " & ".join(names).to_upper())
	draw_string(cf, Vector2(x, 72), "   ·   ".join(sub), HORIZONTAL_ALIGNMENT_LEFT, w, 13,
		UiKit.INK_DIM if open else UiKit.COP_RED.lerp(UiKit.INK, 0.3))
	# Its circuits.
	var cols := [0.0, 0.42, 0.58, 0.72, 0.86]
	var heads := ["", "LAPS · RIVALS", "ENTRY", "FIRST PRIZE", "BEST"]
	for k in heads.size():
		draw_string(UiKit.font("cond", 3), Vector2(x + 16 + (w - 16) * cols[k], 98), heads[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			UiKit.INK_FAINT)
	var circuits: Dictionary = Game.career_data().circuits
	for k in t.circuits.size():
		var c: Dictionary = circuits.get(t.circuits[k], {})
		if c.is_empty():
			continue
		var r := _c_rect(k)
		var now: bool = k == _ci
		UiKit.draw_slant(self, r, Color(1, 1, 1, 0.1 if now else (0.06 if k == _hover_c else 0.035)), 0.08)
		if now:
			UiKit.draw_slant(self, Rect2(r.position, Vector2(4, r.size.y)), UiKit.ACCENT, 0.08)
		var col := (UiKit.INK if now else Color(UiKit.INK, 0.8)) if open else UiKit.INK_FAINT
		var cx := r.position.x + 16
		var cw := r.size.x - 16
		var only := Game.career_data().restriction_text(c).to_upper()
		draw_string(df, Vector2(cx, r.position.y + 25), "%d  %s%s" % [k + 1, KINDS[clampi(c.type, 0, 2)], "  ·  " + only if only != "" else ""], HORIZONTAL_ALIGNMENT_LEFT,
			cw * cols[1] - 10, 20, UiKit.ACCENT if now and open else col)
		draw_string(cf, Vector2(cx, r.position.y + 44), _races_text(c), HORIZONTAL_ALIGNMENT_LEFT, cw * cols[1] - 10, 12,
			UiKit.INK_DIM if open else UiKit.INK_FAINT)
		var fee := "$" + money(c.fee) if c.fee > 0.0 else "FREE"
		var prize := "$" + money(c.prizes[0]) if c.type != HsCareer.TYPE_CAR_RACE and not c.prizes.is_empty() \
			else (Game.serial_name(c.award).to_upper() if c.award >= 0 and Game.serial_name(c.award) != "" else "THE CAR")
		var best := _result(c.id)
		var cells := ["%d · %d" % [c.laps, c.opponents], fee, prize, best if best != "" else "—"]
		for j in cells.size():
			var won := j == 3 and best == "WON"
			draw_string(UiKit.font("display", 0, true), Vector2(cx + cw * cols[j + 1], r.position.y + 33), cells[j],
				HORIZONTAL_ALIGNMENT_LEFT, cw * 0.14, 20,
				UiKit.ACCENT if won else (UiKit.COP_RED if j == 1 and now and Game.career_money < c.fee else col))
	# The focused circuit's races, as postcards.
	var c := circuit()
	if c.is_empty():
		return
	var y := _c_rect(t.circuits.size()).position.y + 18
	draw_string(UiKit.font("cond", 3), Vector2(x, y), "RACES", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.ACCENT)
	draw_line(Vector2(x + 64, y - 5), Vector2(size.x, y - 5), UiKit.INK_FAINT, 1.0)
	y += 14
	var n: int = c.races.size()
	var gap := 12.0
	var tw := minf(200.0, (w - gap * (n - 1)) / maxf(n, 1))
	var th := tw * 9.0 / 16.0
	if y + th + 40 > size.y:
		th = maxf(size.y - y - 40, 30.0)
		tw = minf(tw, th * 16.0 / 9.0)
	for i in n:
		var race: Dictionary = c.races[i]
		var id := HsCareer.track_id(race.track)
		var img := Rect2(x + i * (tw + gap), y, tw, th)
		var tex: Texture2D = postcard.call(id, race.night) if postcard.is_valid() and id != "" else null
		if tex:
			draw_texture_rect(tex, img, false, Color(1, 1, 1) if open else Color(0.5, 0.5, 0.5))
		else:
			draw_rect(img, Color(0.08, 0.09, 0.11))
		draw_rect(img, Color(1, 1, 1, 0.15), false, 1.0)
		UiKit.draw_slant(self, Rect2(img.position + Vector2(6, 6), Vector2(22, 20)), UiKit.ACCENT, 0.15)
		draw_string(df, img.position + Vector2(6, 22), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 22, 16, UiKit.BG)
		var name := Game.track_name(id).to_upper() if id != "" else "NOT INSTALLED"
		draw_string(df, Vector2(img.position.x, img.end.y + 20), name, HORIZONTAL_ALIGNMENT_LEFT, tw, 17, UiKit.INK)
		draw_string(cf, Vector2(img.position.x, img.end.y + 36), _tags(race), HORIZONTAL_ALIGNMENT_LEFT, tw, 11, UiKit.INK_DIM)
	if _message != "":
		draw_string(UiKit.font("cond", 2), Vector2(x, size.y - 6), _message.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w, 15, UiKit.COP_RED)


func _won(t: Dictionary) -> int:
	var won := 0
	for cid in t.circuits:
		won += int(int(Game.career_won.get(cid, 99)) == 1)
	return won


## The tournament whose winning opens `t`.
func _opened_by(t: Dictionary) -> String:
	for o in _tours:
		if t.id in o.unlocks:
			return o.name
	return ""


func _lock(c: Vector2, col: Color) -> void:
	draw_rect(Rect2(c + Vector2(-6, -2), Vector2(12, 9)), col)
	draw_arc(c + Vector2(0, -3), 4.0, PI, TAU, 10, col, 2.0, true)


func _tick(c: Vector2, col: Color) -> void:
	draw_polyline(PackedVector2Array([c + Vector2(-6, 0), c + Vector2(-2, 4), c + Vector2(6, -5)]), col, 2.5, true)


static func _tags(r: Dictionary) -> String:
	var tags := PackedStringArray()
	for k in ["reverse", "mirror", "night", "weather"]:
		if r[k]:
			tags.append({"reverse": "reversed", "mirror": "mirrored", "night": "night", "weather": "wet"}[k])
	return " · ".join(tags).to_upper() if not tags.is_empty() else "FORWARD · DAY"


## "Celtic Ruins · Dolphin Cove · Kindiak Park" for the circuit's races.
static func _races_text(c: Dictionary) -> String:
	var out := PackedStringArray()
	for r: Dictionary in c.races:
		var id := HsCareer.track_id(r.track)
		out.append(Game.track_name(id) if id != "" else "?")
	return " · ".join(out).to_upper()


static func _result(cid: int) -> String:
	var p := int(Game.career_won.get(cid, 0))
	return "" if p == 0 else ("WON" if p == 1 else Hud.ordinal(p).to_upper())


static func money(v: float) -> String:
	var s := str(int(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out
