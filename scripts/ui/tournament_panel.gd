class_name TournamentPanel
extends Control
## High Stakes' tournaments (HsCareer), a screen of the front end: the tournaments down the
## left (won, locked, one-make), the chosen one's circuits on the right with how they're run
## (laps, rivals, entry fee, first prize, your best result and its trophy), and the focused
## circuit's races as postcards. Choosing a circuit goes on to the garage to pick (or buy)
## the car; winning every circuit of a tournament wins its trophy and opens the next ones.

signal chosen(tournament: Dictionary, circuit: int)
signal focus_changed
signal garage
signal back
signal changed                # the money or the cars changed (a new career)

const LIST_W := 300.0
const T_ROW := 42.0
const C_ROW := 58.0
const C_TOP := 118.0
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
	if Game.career_broke():
		return "No car, and not enough money for one: N starts a new career"
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
	return Rect2(0, 4 + i * T_ROW, LIST_W - 8, T_ROW - 4)


func _right_x() -> float:
	return LIST_W + 16.0 + 32.0


## The right edge of the tournament's details.
func _right_end() -> float:
	return size.x


func _c_rect(k: int) -> Rect2:
	var x := _right_x()
	return Rect2(x, C_TOP + k * C_ROW, _right_end() - x, C_ROW - 6)


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
	elif key and key.pressed and not key.echo and key.physical_keycode == KEY_G:
		garage.emit()
	elif key and key.pressed and not key.echo and key.physical_keycode == KEY_N:
		new_career()
	elif e.is_action_pressed("ui_cancel"):
		back.emit()
	else:
		return
	get_viewport().set_input_as_handled()


## Once asked: everything won, the cars and the money go.
func new_career() -> void:
	ConfirmDialog.ask(get_parent() as Control, "Career", "Start a new career?",
		"Your money, your cars and every trophy you've won are lost.", "Start over", "Keep playing", _new_career)


func _new_career() -> void:
	Game.new_career()
	_say("New career: %s to buy a car with in the garage" % UiKit.money(Game.career_money))
	_message_t = 5.0
	focus_changed.emit()
	changed.emit()


func _process(dt: float) -> void:
	if _message_t > 0.0:
		_message_t -= dt
		if _message_t <= 0.0:
			_message = ""
			queue_redraw()


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var cf := UiKit.font("cond", 1)
	var df := UiKit.font("display")
	var bf := UiKit.font("body")
	# The tournaments.
	draw_line(Vector2(LIST_W + 16, 8), Vector2(LIST_W + 16, size.y - 8), UiKit.LINE, 1.0)
	if _tours.is_empty():
		draw_string(bf, Vector2(_right_x(), 40), "The tournaments come with a High Stakes install (see README).",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.INK_DIM)
		return
	for i in _tours.size():
		var t: Dictionary = _tours[i]
		var r := _t_rect(i)
		var open := Game.tournament_open(t)
		var now := i == _ti
		if now:
			UiKit.glow(self, r, 1.0)
		elif i == _hover_t:
			UiKit.glow(self, r, 0.4, UiKit.INK, false)
		var won := _won(t)
		var col := UiKit.INK if now else (Color(UiKit.INK, 0.85) if open else UiKit.INK_FAINT)
		if not open:
			UiKit.lock(self, Vector2(r.position.x + 18, r.get_center().y), UiKit.INK_FAINT)
		elif Game.tournament_won(t):
			UiKit.draw_trophy(self, Vector2(r.position.x + 18, r.get_center().y + 13), 26, 1, 1.0, t.id)
		var name: String = t.name.to_upper()
		draw_string(df, Vector2(r.position.x + 34, r.get_center().y + 7), name, HORIZONTAL_ALIGNMENT_LEFT,
			r.size.x - 96, UiKit.fit("display", name, r.size.x - 96, 19, 14), col)
		if open:
			draw_string(UiKit.font("cond", 1, true), Vector2(r.position.x, r.get_center().y + 5), "%d/%d" % [won, t.circuits.size()],
				HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 12, 14, UiKit.ACCENT if won == t.circuits.size() else UiKit.INK_DIM)
	# The chosen tournament, on a surface of its own.
	var t := tournament()
	var x := _right_x()
	var w := _right_end() - x
	var open := Game.tournament_open(t)
	_draw_purse(Vector2(_right_end(), 38))
	UiKit.kicker(self, Vector2(x, 14), "Tournament %d of %d" % [_ti + 1, _tours.size()], w - 330)
	draw_string(df, Vector2(x - 2, 52), t.name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w - 330,
		UiKit.fit("display", t.name.to_upper(), w - 330, 42, 22), UiKit.INK)
	var sub := PackedStringArray()
	sub.append("%d circuit%s" % [t.circuits.size(), "" if t.circuits.size() == 1 else "s"])
	if not open:
		var by := _opened_by(t)
		sub.append("Locked: win every circuit of %s to open it" % by if by != "" else "Locked")
	elif Game.tournament_won(t):
		sub.append("Trophy won")
	else:
		sub.append("%d won" % _won(t))
	if not t.unlocks.is_empty():
		var names := PackedStringArray()
		for u in t.unlocks:
			for o in _tours:
				if o.id == u:
					names.append(o.name)
		sub.append("Winning it opens " + " & ".join(names))
	draw_string(bf, Vector2(x, 78), "  ·  ".join(sub), HORIZONTAL_ALIGNMENT_LEFT, w, 15,
		UiKit.INK_DIM if open else UiKit.COP_RED.lerp(UiKit.INK, 0.35))
	# Its circuits.
	var cols := [0.0, 0.5, 0.63, 0.76, 0.89]
	var heads := ["CIRCUIT", "LAPS · RIVALS", "ENTRY", "FIRST PRIZE", "BEST"]
	for k in heads.size():
		draw_string(cf, Vector2(x + 16 + (w - 16) * cols[k], C_TOP - 8), heads[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			UiKit.INK_DIM)
	var circuits: Dictionary = Game.career_data().circuits
	for k in t.circuits.size():
		var c: Dictionary = circuits.get(t.circuits[k], {})
		if c.is_empty():
			continue
		var r := _c_rect(k)
		var now: bool = k == _ci
		if now:
			UiKit.glow(self, r, 1.0)
		elif k == _hover_c:
			UiKit.glow(self, r, 0.4, UiKit.INK, false)
		draw_line(Vector2(r.position.x, r.end.y + 3), Vector2(r.end.x, r.end.y + 3), UiKit.LINE, 1.0)
		var col := (UiKit.INK if now else Color(UiKit.INK, 0.85)) if open else UiKit.INK_FAINT
		var cx := r.position.x + 16
		var cw := r.size.x - 16
		var kind: String = KINDS[clampi(c.type, 0, 2)].capitalize()
		var only := Game.career_data().restriction_text(c)
		var title := "%s %d" % [kind, k + 1]
		draw_string(df, Vector2(cx, r.position.y + 23), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, cw * cols[1] - 12, 19,
			UiKit.ACCENT if now and open else col)
		if only != "":
			var tw := df.get_string_size(title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
			draw_string(bf, Vector2(cx + tw + 10, r.position.y + 22), only, HORIZONTAL_ALIGNMENT_LEFT, cw * cols[1] - tw - 22, 13,
				UiKit.INK_DIM)
		draw_string(bf, Vector2(cx, r.position.y + 42), _races_text(c), HORIZONTAL_ALIGNMENT_LEFT, cw * cols[1] - 12, 13,
			UiKit.INK_DIM if open else UiKit.INK_FAINT)
		var fee := UiKit.money(c.fee) if c.fee > 0.0 else "Free"
		var prize := UiKit.money(c.prizes[0]) if c.award < 0 and not c.prizes.is_empty() and c.prizes[0] > 0.0 \
			else (Game.serial_name(c.award) if c.award >= 0 and Game.serial_name(c.award) != "" else "The win")
		var best := _result(c.id)
		var cup := Game.circuit_trophy(c.id) if c.type != HsCareer.TYPE_CAR_RACE else 0
		var cells := ["%d · %d" % [c.laps, c.opponents], fee, prize, best if best != "" else "—"]
		for j2 in cells.size():
			var won := j2 == 3 and best == "WON"
			var cell_x: float = cx + cw * cols[j2 + 1]
			var cell_w: float = cw * ((cols[j2 + 2] if j2 + 2 < cols.size() else 1.0) - cols[j2 + 1]) - 8
			if j2 == 3 and cup > 0:
				UiKit.draw_trophy(self, Vector2(cell_x + 12, r.position.y + 44), 34, cup, 1.0, t.id)
				cell_x += 30
				cell_w -= 30
			var poor: bool = j2 == 1 and now and Game.career_money < c.fee
			draw_string(UiKit.font("display", 0, true), Vector2(cell_x, r.position.y + 33), cells[j2].to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, cell_w, UiKit.fit("display", cells[j2].to_upper(), cell_w, 19, 13),
				UiKit.ACCENT if won else (UiKit.COP_RED if poor else col))
	# The focused circuit's races, as postcards.
	var c := circuit()
	if c.is_empty():
		return
	var y := _c_rect(t.circuits.size()).position.y + 22
	UiKit.kicker(self, Vector2(x, y), "The races of circuit %d" % (_ci + 1), w)
	y += 14
	var n: int = c.races.size()
	var gap := 14.0
	var tw := minf(220.0, (w - gap * (n - 1)) / maxf(n, 1))
	var th := tw * 9.0 / 16.0
	if y + th + 56 > size.y:
		th = maxf(size.y - y - 56, 30.0)
		tw = minf(tw, th * 16.0 / 9.0)
	for i in n:
		var race: Dictionary = c.races[i]
		var id := HsCareer.track_id(race.track)
		var img := Rect2(x + i * (tw + gap), y, tw, th)
		var tex: Texture2D = postcard.call(id, race.night) if postcard.is_valid() and id != "" else null
		if tex:
			draw_texture_rect(tex, img, false, Color(1, 1, 1) if open else Color(0.5, 0.5, 0.5))
		else:
			UiKit.box(self, img, Color(0.08, 0.09, 0.11), 4)
		UiKit.box(self, img, Color(0, 0, 0, 0), 4, Color(1, 1, 1, 0.15))
		UiKit.box(self, Rect2(img.position + Vector2(6, 6), Vector2(22, 20)), UiKit.ACCENT, 3)
		draw_string(df, img.position + Vector2(6, 22), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 22, 16, UiKit.BG)
		var name := Game.track_name(id).to_upper() if id != "" else "NOT INSTALLED"
		draw_string(df, Vector2(img.position.x, img.end.y + 20), name, HORIZONTAL_ALIGNMENT_LEFT, tw, 17, UiKit.INK)
		draw_string(bf, Vector2(img.position.x, img.end.y + 37), _tags(race), HORIZONTAL_ALIGNMENT_LEFT, tw, 13, UiKit.INK_DIM)
	if _message != "":
		draw_string(UiKit.font("body_bold"), Vector2(x, size.y - 14), _message, HORIZONTAL_ALIGNMENT_LEFT, w, 15, UiKit.COP_RED)


## Top right: the money, and under it the circuit trophies won, gold, silver and bronze (each
## shown as the first tournament's it was won in).
func _draw_purse(right: Vector2) -> void:
	var n := [0, 0, 0]
	var design := [1, 1, 1]
	for t in _tours:
		for cid in t.circuits:
			var p := Game.circuit_trophy(int(cid))
			if p > 0 and Game.career_data().circuits.get(int(cid), {}).get("type", 0) != HsCareer.TYPE_CAR_RACE:
				if n[p - 1] == 0:
					design[p - 1] = t.id
				n[p - 1] += 1
	var mf := UiKit.font("display", 0, true)
	var m := UiKit.money(Game.career_money)
	draw_string(mf, Vector2(right.x - 400, right.y + 8), m, HORIZONTAL_ALIGNMENT_RIGHT, 400, 30, UiKit.ACCENT)
	var mw := mf.get_string_size(m, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	draw_string(UiKit.font("body"), Vector2(right.x - mw - 130, right.y + 5), "Money", HORIZONTAL_ALIGNMENT_RIGHT, 120, 14,
		UiKit.INK_DIM)
	var x := right.x
	var y := right.y + 34
	for k in [2, 1, 0]:
		var num := str(n[k])
		x -= UiKit.text_width("display", num, 16, 0)
		draw_string(UiKit.font("display", 0, true), Vector2(x, y + 1), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			UiKit.INK if n[k] > 0 else UiKit.INK_FAINT)
		x -= 18
		UiKit.draw_trophy(self, Vector2(x + 7, y + 5), 22, k + 1, 1.0 if n[k] > 0 else 0.3, design[k])
		x -= 16


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


static func _tags(r: Dictionary) -> String:
	var tags := PackedStringArray()
	for k in ["reverse", "mirror", "night", "weather"]:
		if r[k]:
			tags.append({"reverse": "reversed", "mirror": "mirrored", "night": "night", "weather": "wet"}[k])
	return (" · ".join(tags) if not tags.is_empty() else "forward · day").capitalize()


## "Celtic Ruins · Dolphin Cove · Kindiak Park" for the circuit's races.
static func _races_text(c: Dictionary) -> String:
	var out := PackedStringArray()
	for r: Dictionary in c.races:
		var id := HsCareer.track_id(r.track)
		out.append(Game.track_name(id) if id != "" else "?")
	return " · ".join(out)


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
