class_name TournamentPanel
extends Control
## The tournaments (HsCareer), a screen of the front end, laid out as the three questions a
## career asks in turn:
##   WHERE AM I    down the left, the game's tournaments as a ladder (Tab switches between
##                 High Stakes', NFS3's and Porsche Unleashed's, each a career of its own):
##                 a pip per circuit won, the trophy once all are, the lock and what opens it;
##   WHAT'S NEXT   in the middle, the chosen tournament's circuits ("events"), each with its
##                 state (won / your best / open / locked), what it pays and what it costs;
##   SHOULD I GO   on the right, the focused event's brief: how it's run, its races as
##                 postcards, the purse place by place, and what entering takes: the fee
##                 against your money, and whether a car of yours is allowed in (else the
##                 cheapest the dealer has that is).
## Choosing an event goes on to the garage to pick (or buy) the car; winning every event of a
## tournament wins its trophy and opens the next ones.

signal chosen(tournament: Dictionary, circuit: int)
signal focus_changed
signal garage
signal back
signal changed                # the money or the cars changed (a new career)

const LIST_W := 290.0
const SERIES_H := 46.0
const GUTTER := 36.0
const E_TOP := 128.0          # the events' first row, under the tournament's heading
const E_ROW := 52.0
const KINDS := ["Circuit", "Knockout", "Car race"]
const SERIES_LABELS := {"nfs3": "NFS III", "hs": "HIGH STAKES", "pu": "PORSCHE"}

## (track id, night) -> Texture2D or null, for the races' pictures.
var postcard: Callable

var _tours: Array = []
var _ti := 0                  # tournament
var _ci := 0                  # circuit within it
var _hover_t := -1
var _hover_c := -1
var _hover_s := -1            # a game's tab
var _c_first := 0             # the first event's row shown
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
	if first:
		_pick_start()
	queue_redraw()
	focus_changed.emit()


## Starts on the first open circuit not yet won.
func _pick_start() -> void:
	_ti = 0
	_ci = 0
	_c_first = 0
	var circuits: Dictionary = Game.career_data().circuits if Game.career_data() else {}
	for i in _tours.size():
		if not Game.tournament_open(_tours[i]):
			continue
		for k in _tours[i].circuits.size():
			if int(Game.career_won.get(_tours[i].circuits[k], 99)) != 1 \
					and Game.circuit_open(circuits.get(_tours[i].circuits[k], {})):
				_ti = i
				_ci = k
				return


## Over to the next (`dir` 1) or the previous game's tournaments.
func next_series(dir := 1) -> void:
	var list := Game.career_series_list()
	if list.size() < 2:
		return
	var i := list.find(Game.career_series)
	_switch_series(list[posmod(i + dir, list.size())])


func _switch_series(s: String) -> void:
	if s == Game.career_series:
		return
	Game.set_career_series(s)
	_tours = Game.career_data().tournaments
	_message = ""
	_pick_start()
	queue_redraw()
	focus_changed.emit()
	changed.emit()


## The games to choose between (more than one installed).
func _series_shown() -> bool:
	return Game.career_series_list().size() > 1


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
	return HsCareer.race_track(c.races[0]) if not c.is_empty() and not c.races.is_empty() else ""


## Why the focused circuit can't be entered ("" if it can), the car aside.
func blocked() -> String:
	var t := tournament()
	var c := circuit()
	if c.is_empty():
		return "Nothing to enter"
	if not Game.tournament_open(t):
		var by := _opened_by(t)
		return "Locked: win %s first" % by if by != "" else "Locked"
	if not Game.circuit_open(c):
		return "Win the rest of the %s first" % t.name
	if Game.career_broke():
		return "No car, and not enough money for one: N starts a new career"
	if Game.career_money < c.fee:
		return "Entry fee %s: not enough money" % UiKit.money(c.fee)
	for r: Dictionary in c.races:
		if HsCareer.race_track(r) == "":
			return "A track of this event isn't installed"
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
	_c_first = 0
	# On the first event still to win, if there is one.
	var t := tournament()
	for k in t.circuits.size():
		if int(Game.career_won.get(t.circuits[k], 99)) != 1:
			_ci = k
			break
	_message = ""
	queue_redraw()
	focus_changed.emit()


# ------------------------------------------------------------------ layout

func _s_rect(k: int) -> Rect2:
	var n := Game.career_series_list().size()
	var w := (LIST_W - (n - 1) * 6) / maxf(n, 1)
	return Rect2(k * (w + 6), 2, w, SERIES_H - 12)


func _t_top() -> float:
	return 4.0 + (SERIES_H if _series_shown() else 0.0)


## The ladder's rows share the height left over the trophy tally, up to 58 px each.
func _t_row_h() -> float:
	return clampf((size.y - _t_top() - 70.0) / maxf(_tours.size(), 1), 34.0, 58.0)


func _t_rect(i: int) -> Rect2:
	var h := _t_row_h()
	return Rect2(0, _t_top() + i * h, LIST_W, h - 4)


## The events' column and the brief's.
func _mid() -> Rect2:
	var x := LIST_W + GUTTER
	var w := clampf((size.x - x) * 0.46, 420.0, 680.0)
	return Rect2(x, 0, w, size.y)


func _brief() -> Rect2:
	var m := _mid()
	var x := m.end.x + GUTTER
	return Rect2(x, 0, size.x - x, size.y)


func _c_rect(k: int) -> Rect2:
	var m := _mid()
	return Rect2(m.position.x, E_TOP + (k - _c_first) * E_ROW, m.size.x, E_ROW - 6)


## How many events' rows fit (Porsche Unleashed's eras have up to 13).
func _c_rows() -> int:
	return maxi(int((size.y - E_TOP - 24.0) / E_ROW), 3)


## Scrolls the events' rows so the focused one shows.
func _scroll_to_focus() -> void:
	var n: int = tournament().get("circuits", []).size()
	var rows := _c_rows()
	_c_first = clampi(_c_first, _ci - rows + 1, _ci)
	_c_first = clampi(_c_first, 0, maxi(n - rows, 0))


func _c_visible(k: int) -> bool:
	return k >= _c_first and k < _c_first + _c_rows()


# ------------------------------------------------------------------ input

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var hs := -1
		if _series_shown():
			for k in Game.career_series_list().size():
				if _s_rect(k).has_point(e.position):
					hs = k
		var ht := -1
		var hc := -1
		for i in _tours.size():
			if _t_rect(i).has_point(e.position):
				ht = i
		for k in tournament().get("circuits", []).size():
			if _c_visible(k) and _c_rect(k).has_point(e.position):
				hc = k
		if ht != _hover_t or hc != _hover_c or hs != _hover_s:
			_hover_s = hs
			_hover_t = ht
			_hover_c = hc
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if ht >= 0 or hc >= 0 or hs >= 0 else Control.CURSOR_ARROW
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				if _hover_s >= 0:
					_switch_series(Game.career_series_list()[_hover_s])
				elif _hover_t >= 0:
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
	if what == NOTIFICATION_MOUSE_EXIT and (_hover_t >= 0 or _hover_c >= 0 or _hover_s >= 0):
		_hover_t = -1
		_hover_c = -1
		_hover_s = -1
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
	elif (key and key.pressed and not key.echo and key.physical_keycode == KEY_TAB) \
			or (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_Y):
		next_series(-1 if key and key.shift_pressed else 1)
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
		("Every trophy you've won in %s's tournaments is lost." % Game.CAREER_SERIES_NAMES.get(Game.career_series, "")
			if Game.career_series == "nfs3" else
			"Your %s money, cars and every trophy you've won are lost." % Game.CAREER_SERIES_NAMES.get(Game.career_series, "")),
		"Start over", "Keep playing", _new_career)


func _new_career() -> void:
	Game.new_career()
	_pick_start()
	_say("New career: %s to buy a car with in the garage" % UiKit.money(Game.career_money) if Game.career_series != "nfs3"
		else "New career: every trophy to win again")
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
	_scroll_to_focus()
	if _series_shown():
		_draw_series()
	if _tours.is_empty():
		draw_string(UiKit.font("body"), Vector2(_mid().position.x, 40),
			"The tournaments come with a High Stakes install (see README).", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.INK_DIM)
		return
	_draw_ladder()
	_draw_events()
	_draw_brief(_brief())


func _draw_series() -> void:
	var list := Game.career_series_list()
	for k in list.size():
		var sr := _s_rect(k)
		var on: bool = list[k] == Game.career_series
		if on:
			UiKit.box(self, sr, UiKit.ACCENT, 4)
		elif k == _hover_s:
			UiKit.glow(self, sr, 0.4, UiKit.INK, false)
		else:
			UiKit.box(self, sr, Color(0, 0, 0, 0), 4, UiKit.LINE)
		var label: String = SERIES_LABELS.get(list[k], list[k])
		draw_string(UiKit.font("cond", 1, true), Vector2(sr.position.x, sr.get_center().y + 5), label,
			HORIZONTAL_ALIGNMENT_CENTER, sr.size.x, UiKit.fit("cond", label, sr.size.x - 8, 14, 10, 1),
			UiKit.BG if on else UiKit.INK_DIM)


## WHERE AM I: the tournaments, one above the next, and the trophies won under them.
func _draw_ladder() -> void:
	var df := UiKit.font("display")
	var small := _t_row_h() < 46.0
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
		var n: int = t.circuits.size()
		var cy := r.get_center().y
		var icon := Vector2(r.position.x + 20, cy)
		if not open:
			UiKit.lock(self, icon, UiKit.INK_FAINT)
		elif Game.tournament_won(t):
			UiKit.draw_trophy(self, icon + Vector2(0, 13), 28, 1, 1.0, Game.trophy_design(t.id))
		else:
			_ring(icon, 9.0, float(won) / maxf(n, 1), UiKit.ACCENT if now else UiKit.INK_DIM)
		var name: String = t.name.to_upper()
		var nx := r.position.x + 40
		var nw := r.size.x - 52
		var ny := cy + 7 if small else cy + 1
		draw_string(df, Vector2(nx, ny), name, HORIZONTAL_ALIGNMENT_LEFT, nw, UiKit.fit("display", name, nw, 19, 13),
			UiKit.INK if now else (Color(UiKit.INK, 0.85) if open else UiKit.INK_FAINT))
		if small:
			continue
		# Under the name: a pip per circuit, gold when won; or, locked, what opens it.
		var sub_y := cy + 18
		if open:
			var px := nx + 3
			for k in n:
				var p := Game.circuit_trophy(int(t.circuits[k]))
				var c := UiKit.trophy_colour(p) if int(Game.career_won.get(t.circuits[k], 99)) == 1 else \
					(Color(UiKit.trophy_colour(p), 0.6) if p > 0 else Color(1, 1, 1, 0.18))
				draw_circle(Vector2(px, sub_y - 4), 3.2, c)
				px += 10
			draw_string(UiKit.font("cond", 1, true), Vector2(px + 4, sub_y), "%d/%d" % [won, n], HORIZONTAL_ALIGNMENT_LEFT, -1,
				12, UiKit.ACCENT if won == n else UiKit.INK_FAINT)
		else:
			var by := _opened_by(t)
			draw_string(UiKit.font("body"), Vector2(nx, sub_y), "Win %s to open" % by if by != "" else "Locked",
				HORIZONTAL_ALIGNMENT_LEFT, nw, 12, UiKit.INK_FAINT)
	_draw_cabinet(Vector2(0, size.y - 12))


## The trophies won so far, gold, silver and bronze (each shown as the first tournament's it
## was won in), at the foot of the ladder.
func _draw_cabinet(at: Vector2) -> void:
	var n := [0, 0, 0]
	var design := [1, 1, 1]
	var tours := 0
	for t in _tours:
		tours += int(Game.tournament_won(t))
		for cid in t.circuits:
			var p := Game.circuit_trophy(int(cid))
			if p > 0 and Game.career_data().circuits.get(int(cid), {}).get("type", 0) != HsCareer.TYPE_CAR_RACE:
				if n[p - 1] == 0:
					design[p - 1] = Game.trophy_design(t.id)
				n[p - 1] += 1
	draw_line(Vector2(at.x, at.y - 44), Vector2(at.x + LIST_W, at.y - 44), UiKit.LINE, 1.0)
	UiKit.kicker(self, Vector2(at.x, at.y - 24), "Trophy cabinet", LIST_W, UiKit.INK_DIM)
	var x := at.x
	for k in 3:
		UiKit.draw_trophy(self, Vector2(x + 9, at.y + 2), 22, k + 1, 1.0 if n[k] > 0 else 0.3, design[k])
		x += 22
		draw_string(UiKit.font("display", 0, true), Vector2(x, at.y - 1), str(n[k]), HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
			UiKit.INK if n[k] > 0 else UiKit.INK_FAINT)
		x += 34
	draw_string(UiKit.font("body"), Vector2(at.x, at.y - 2), "%d of %d tournaments" % [tours, _tours.size()],
		HORIZONTAL_ALIGNMENT_RIGHT, LIST_W, 13, UiKit.INK_DIM)


## A progress ring: a faint circle, its `t` share drawn over clockwise from the top.
func _ring(c: Vector2, r: float, t: float, col: Color) -> void:
	draw_arc(c, r, 0, TAU, 32, Color(1, 1, 1, 0.16), 2.5, true)
	if t > 0.0:
		draw_arc(c, r, -PI / 2, -PI / 2 + TAU * t, 32, col, 2.5, true)


## WHAT'S NEXT: the chosen tournament's heading and its events.
func _draw_events() -> void:
	var m := _mid()
	var t := tournament()
	var x := m.position.x
	var w := m.size.x
	var open := Game.tournament_open(t)
	var df := UiKit.font("display")
	var bf := UiKit.font("body")
	UiKit.kicker(self, Vector2(x, 14), "%s %d of %d" % [_tour_word(), _ti + 1, _tours.size()], w)
	var name: String = t.name.to_upper()
	draw_string(df, Vector2(x - 2, 54), name, HORIZONTAL_ALIGNMENT_LEFT, w, UiKit.fit("display", name, w, 40, 22), UiKit.INK)
	var line1: String = t.get("about", "")
	var line2 := ""
	if not open:
		var by := _opened_by(t)
		line2 = "Locked: win every event of %s to open it" % by if by != "" else "Locked"
	elif Game.tournament_won(t):
		line2 = "Trophy won"
	else:
		line2 = "Win all %d %s for the trophy" % [t.circuits.size(), _event_word(t.circuits.size())]
	var names := PackedStringArray()
	for u in t.unlocks:
		for o in _tours:
			if o.id == u:
				names.append(o.name)
	if not names.is_empty():
		line2 += "  ·  opens " + " & ".join(names)
	if line1 != "":
		draw_string(bf, Vector2(x, 80), line1, HORIZONTAL_ALIGNMENT_LEFT, w, 14, UiKit.INK_DIM)
	draw_string(UiKit.font("body_bold"), Vector2(x, 80 if line1 == "" else 100), line2, HORIZONTAL_ALIGNMENT_LEFT, w, 14,
		UiKit.ACCENT if Game.tournament_won(t) else (UiKit.INK_DIM if open else UiKit.COP_RED.lerp(UiKit.INK, 0.35)))
	var circuits: Dictionary = Game.career_data().circuits
	for k in t.circuits.size():
		var c: Dictionary = circuits.get(t.circuits[k], {})
		if c.is_empty() or not _c_visible(k):
			continue
		_draw_event(c, k, _c_rect(k), open)
	# More rows than fit: where we are in them.
	var shown := mini(t.circuits.size(), _c_first + _c_rows())
	if _c_first > 0 or shown < t.circuits.size():
		var y := _c_rect(shown).position.y + 6
		draw_string(UiKit.font("cond", 1), Vector2(x, y), "%d-%d OF %d  ·  ↑↓ FOR MORE" % [_c_first + 1, shown, t.circuits.size()],
			HORIZONTAL_ALIGNMENT_RIGHT, w, 11, UiKit.INK_DIM)


## One event's row: its state at the left (number, lock, trophy), its name and what it
## takes, and at the right what winning it pays over what it costs to enter.
func _draw_event(c: Dictionary, k: int, r: Rect2, tour_open: bool) -> void:
	var now: bool = k == _ci
	if now:
		UiKit.glow(self, r, 1.0)
	elif k == _hover_c:
		UiKit.glow(self, r, 0.4, UiKit.INK, false)
	draw_line(Vector2(r.position.x, r.end.y + 3), Vector2(r.end.x, r.end.y + 3), UiKit.LINE, 1.0)
	var reachable := tour_open and Game.circuit_open(c)
	var won := int(Game.career_won.get(c.id, 99)) == 1
	var cy := r.get_center().y
	# State.
	var badge := Vector2(r.position.x + 26, cy)
	var cup := Game.circuit_trophy(c.id) if c.type != HsCareer.TYPE_CAR_RACE else 0
	if not reachable:
		UiKit.lock(self, badge, UiKit.INK_FAINT)
	elif cup > 0:
		UiKit.draw_trophy(self, badge + Vector2(0, 15), 32, cup, 1.0, Game.trophy_design(tournament().id))
	elif won:
		_tick(badge, UiKit.ACCENT)
	else:
		draw_arc(badge, 13, 0, TAU, 32, UiKit.ACCENT if now else Color(1, 1, 1, 0.3), 1.5, true)
		draw_string(UiKit.font("display", 0, true), badge + Vector2(-13, 6), str(k + 1), HORIZONTAL_ALIGNMENT_CENTER, 26, 16,
			UiKit.ACCENT if now else UiKit.INK_DIM)
	# Name, and under it the format and what car it takes.
	var col := (UiKit.INK if now else Color(UiKit.INK, 0.88)) if reachable else UiKit.INK_FAINT
	var x := r.position.x + 54
	var right_w := 132.0
	var nw := r.end.x - x - right_w - 12
	var title := _title(c, k).to_upper()
	draw_string(UiKit.font("display"), Vector2(x, cy + 1), title, HORIZONTAL_ALIGNMENT_LEFT, nw,
		UiKit.fit("display", title, nw, 20, 14), UiKit.ACCENT if now and reachable else col)
	var sub := PackedStringArray([_format_short(c)])
	var only := Game.career_data().restriction_text(c)
	if only != "":
		sub.append(only)
	var best := _result(c.id)
	if best != "" and not won:
		sub.append("best " + best.to_lower())
	draw_string(UiKit.font("body"), Vector2(x, cy + 19), " · ".join(sub), HORIZONTAL_ALIGNMENT_LEFT, nw, 13,
		UiKit.INK_DIM if reachable else UiKit.INK_FAINT)
	# What it pays, what it costs.
	var rx := r.end.x - 12 - right_w
	var pay := _prize_text(c)
	var mf := UiKit.font("display", 0, true)
	draw_string(mf, Vector2(rx, cy + 1), pay.to_upper(), HORIZONTAL_ALIGNMENT_RIGHT, right_w,
		UiKit.fit("display", pay.to_upper(), right_w, 19, 12), (UiKit.ACCENT if not won else UiKit.INK_DIM) if reachable else UiKit.INK_FAINT)
	if Game.career_series != "nfs3":
		var poor: bool = c.fee > Game.career_money
		draw_string(UiKit.font("cond", 1), Vector2(rx, cy + 19), ("ENTRY " + UiKit.money(c.fee)) if c.fee > 0.0 else "FREE ENTRY",
			HORIZONTAL_ALIGNMENT_RIGHT, right_w, 12, UiKit.COP_RED if poor and reachable else UiKit.INK_FAINT)


func _tick(c: Vector2, col: Color) -> void:
	draw_circle(c, 13, Color(col, 0.18))
	draw_polyline(PackedVector2Array([c + Vector2(-6, 0), c + Vector2(-1.5, 5), c + Vector2(7, -5)]), col, 2.5, true)


## SHOULD I GO: the focused event in full.
func _draw_brief(b: Rect2) -> void:
	var c := circuit()
	if c.is_empty():
		return
	var t := tournament()
	var reachable := Game.tournament_open(t) and Game.circuit_open(c)
	var x := b.position.x
	var w := b.size.x
	var df := UiKit.font("display")
	var bf := UiKit.font("body")
	var kind: String = "Rally" if c.get("rally", false) else KINDS[clampi(c.type, 0, 2)]
	var kick := "%s %d of %d" % [_event_word(1), _ci + 1, t.circuits.size()]
	if kind != "Circuit":
		kick += "  ·  " + kind
	UiKit.kicker(self, Vector2(x, 14), kick, w)
	var title := _title(c, _ci).to_upper()
	draw_string(df, Vector2(x - 2, 54), title, HORIZONTAL_ALIGNMENT_LEFT, w, UiKit.fit("display", title, w, 40, 22), UiKit.INK)
	var y := 80.0
	var about := _about(c)
	if about != "":
		var lines := mini(roundi(bf.get_multiline_string_size(about, HORIZONTAL_ALIGNMENT_LEFT, w, 14).y / bf.get_height(14)), 3)
		draw_multiline_string(bf, Vector2(x, y), about, HORIZONTAL_ALIGNMENT_LEFT, w, 14, 3, UiKit.INK_DIM)
		y += maxi(lines, 1) * bf.get_height(14) + 6
	y += 8
	# The deal: what it takes (car, fee) and what it gives (the purse).
	var deal_h := 96.0
	_draw_requirements(c, Rect2(x, y, w * 0.5 - 12, deal_h), reachable)
	_draw_purse(c, Rect2(x + w * 0.5 + 12, y, w * 0.5 - 12, deal_h))
	y += deal_h + 16
	# The races.
	UiKit.heading(self, Vector2(x, y + 10), "%d race%s" % [c.races.size(), "" if c.races.size() == 1 else "s"], w)
	y += 24
	_draw_races(c, Rect2(x, y, w, size.y - y - 30), reachable)
	if _message != "":
		draw_string(UiKit.font("body_bold"), Vector2(x, size.y - 6), _message, HORIZONTAL_ALIGNMENT_LEFT, w, 15, UiKit.COP_RED)


## What entering takes: a car it allows (yours, or the cheapest the dealer has), the fee.
func _draw_requirements(c: Dictionary, r: Rect2, reachable: bool) -> void:
	UiKit.heading(self, r.position + Vector2(0, 10), "To enter", r.size.x)
	var y := r.position.y + 36
	var only := Game.career_data().restriction_text(c)
	var lines := []   # [label, value, colour]
	lines.append(["Car", only if only != "" else "Any car", UiKit.INK])
	var mine := Game.garage_cars().filter(func(i: int) -> bool: return Game.circuit_allows(c, i))
	if not mine.is_empty():
		lines.append(["", "You have %d that %s" % [mine.size(), "fits" if mine.size() == 1 else "fit"], UiKit.GOOD])
	elif c.restriction == HsCareer.LOANER:
		lines.append(["", "A car is lent to you", UiKit.GOOD])
	else:
		var sale := Game.dealer_cars().filter(func(i: int) -> bool: return Game.circuit_allows(c, i) and not Game.owns(i))
		if sale.is_empty():
			lines.append(["", "None of yours, none for sale", UiKit.COP_RED])
		else:
			var price := Game.career_price(sale[0])
			lines.append(["", "None of yours: from %s at the dealer" % UiKit.money(price),
				UiKit.ACCENT if price + c.fee <= Game.career_money else UiKit.COP_RED])
	if Game.career_series != "nfs3":
		var poor: bool = c.fee > Game.career_money
		lines.append(["Fee", (UiKit.money(c.fee) if c.fee > 0.0 else "Free") + ("  ·  you have %s" % UiKit.money(Game.career_money)
			if c.fee > 0.0 else ""), UiKit.COP_RED if poor else UiKit.INK])
	for l in lines:
		if l[0] != "":
			draw_string(UiKit.font("body"), Vector2(r.position.x, y), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.INK_DIM)
		draw_string(UiKit.font("body_bold" if l[0] == "" else "body"), Vector2(r.position.x + 40, y), l[1],
			HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 40, 14, l[2] if reachable else UiKit.INK_FAINT)
		y += 21


## What it gives: the prize place by place (or the car), and what you've won of it.
func _draw_purse(c: Dictionary, r: Rect2) -> void:
	UiKit.heading(self, r.position + Vector2(0, 10), "To win", r.size.x)
	var y := r.position.y + 36
	var vf := UiKit.font("display", 0, true)
	var car := _award_name(c)
	if car != "":
		draw_string(UiKit.font("body"), Vector2(r.position.x, y), "Winner", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.INK_DIM)
		draw_string(vf, Vector2(r.position.x + 56, y + 1), car.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 56,
			UiKit.fit("display", car.to_upper(), r.size.x - 56, 18, 12), UiKit.ACCENT)
		y += 24
	var paid: Array = c.prizes.filter(func(p) -> bool: return float(p) > 0.0)
	if not paid.is_empty():
		var x := r.position.x
		for k in mini(c.prizes.size(), 3):
			if float(c.prizes[k]) <= 0.0:
				continue
			UiKit.draw_trophy(self, Vector2(x + 8, y + 4), 20, k + 1, 1.0 if c.type != HsCareer.TYPE_CAR_RACE else 0.4)
			var s := UiKit.money(c.prizes[k])
			draw_string(vf, Vector2(x + 20, y + 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiKit.INK if k == 0 else UiKit.INK_DIM)
			x += 30 + UiKit.text_width("display", s, 17, 0, true)
		y += 24
	var per_race: Array = c.races.filter(func(rr: Dictionary) -> bool:
		return not rr.get("prizes", []).is_empty() and float(rr.prizes[0]) > 0.0)
	if not per_race.is_empty():
		draw_string(UiKit.font("body"), Vector2(r.position.x, y), "and %s to each race's winner" % UiKit.money(per_race[0].prizes[0]),
			HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 13, UiKit.INK_DIM)
		y += 20
	if car == "" and paid.is_empty() and per_race.is_empty():
		draw_string(UiKit.font("body"), Vector2(r.position.x, y), "The trophy", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiKit.INK)
		y += 20
	var best := _result(c.id)
	if best != "":
		draw_string(UiKit.font("body_bold"), Vector2(r.position.x, y), "Your best: " + best.to_lower(), HORIZONTAL_ALIGNMENT_LEFT,
			r.size.x, 13, UiKit.ACCENT if best == "WON" else UiKit.INK)


## The races as postcards, in as many columns as keep them a good size.
func _draw_races(c: Dictionary, area: Rect2, reachable: bool) -> void:
	var n: int = c.races.size()
	if n == 0:
		return
	var gap := 14.0
	var cap := 40.0
	var cols := 1
	var tw := 0.0
	var th := 0.0
	# The fewest columns that fit them all in height, as wide as allowed.
	for k in range(1, n + 1):
		cols = k
		tw = minf((area.size.x - gap * (cols - 1)) / cols, 300.0)
		th = tw * 9.0 / 16.0
		var rows := ceili(float(n) / cols)
		if rows * (th + cap + gap) - gap <= area.size.y:
			break
	var rows_n := ceili(float(n) / cols)
	if rows_n * (th + cap + gap) - gap > area.size.y:
		th = maxf((area.size.y + gap) / rows_n - cap - gap, 24.0)
		tw = minf(tw, th * 16.0 / 9.0)
	var df := UiKit.font("display")
	for i in n:
		var race: Dictionary = c.races[i]
		var id := HsCareer.race_track(race)
		var img := Rect2(area.position.x + (i % cols) * (tw + gap), area.position.y + (i / cols) * (th + cap + gap), tw, th)
		var tex: Texture2D = postcard.call(id, race.night) if postcard.is_valid() and id != "" else null
		if tex:
			draw_texture_rect(tex, img, false, Color(1, 1, 1) if reachable else Color(0.5, 0.5, 0.5))
		else:
			UiKit.box(self, img, Color(0.08, 0.09, 0.11), 4)
		UiKit.box(self, img, Color(0, 0, 0, 0), 4, Color(1, 1, 1, 0.15))
		UiKit.box(self, Rect2(img.position + Vector2(6, 6), Vector2(22, 20)), UiKit.ACCENT, 3)
		draw_string(df, img.position + Vector2(6, 22), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 22, 16, UiKit.BG)
		var name := Game.track_name(id).to_upper() if id != "" else "NOT INSTALLED"
		draw_string(df, Vector2(img.position.x, img.end.y + 19), name, HORIZONTAL_ALIGNMENT_LEFT, tw,
			UiKit.fit("display", name, tw, 17, 12), UiKit.INK)
		draw_string(UiKit.font("body"), Vector2(img.position.x, img.end.y + 35), _tags(race), HORIZONTAL_ALIGNMENT_LEFT, tw, 12,
			UiKit.INK_DIM)


# ------------------------------------------------------------------ words

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


func _tour_word() -> String:
	return "Era" if Game.career_series == "pu" else "Tournament"


func _event_word(n: int) -> String:
	var w := "circuit" if Game.career_series == "hs" else "event" if Game.career_series == "pu" else "level"
	return (w + ("" if n == 1 else "s")) if n != 1 else w.capitalize()


static func _title(c: Dictionary, k: int) -> String:
	return c.get("name", "%s %d" % [KINDS[clampi(c.type, 0, 2)], k + 1])


## "3 races · 5 rivals" (or "2 laps · 5 rivals" for High Stakes' lap counts).
static func _format_short(c: Dictionary) -> String:
	var n: int = c.races.size()
	var bits := PackedStringArray(["%d race%s" % [n, "" if n == 1 else "s"]])
	if Game.career_series == "hs" and int(c.laps) > 1:
		bits.append("%d laps" % c.laps)
	bits.append("%d rival%s" % [c.opponents, "" if c.opponents == 1 else "s"])
	return " · ".join(bits)


## What winning event `c` pays, in a word: the car, the first prize, or the trophy.
static func _prize_text(c: Dictionary) -> String:
	var car := _award_name(c)
	if car != "":
		return car
	if not c.prizes.is_empty() and float(c.prizes[0]) > 0.0:
		return UiKit.money(c.prizes[0])
	return "Trophy"


static func _award_name(c: Dictionary) -> String:
	if c.get("award_id", "") != "" and Game.car_name_by_id(c.award_id) != "":
		return Game.car_name_by_id(c.award_id)
	if c.award >= 0:
		return Game.serial_name(c.award)
	return ""


## The focused event's lines under its name: what the game says of it, and how it's run.
static func _about(c: Dictionary) -> String:
	var bits := PackedStringArray()
	if c.get("about", "") != "":
		bits.append(c.about)
	if c.get("rally", false):
		bits.append("Rally: the lowest total time wins, the prize paid at the end.")
	elif c.type == HsCareer.TYPE_KNOCKOUT and not str(c.get("about", "")).contains("out"):
		bits.append("Knockout: the last car of each race is out.")
	if c.get("traffic", false):
		bits.append("On the open road, in traffic.")
	if Game.career_series == "hs":
		bits.append("%d laps a race, %d rivals." % [c.laps, c.opponents])
	if c.get("opens", "") != "":
		bits.append(str(c.opens) + ".")
	return " ".join(bits)


static func _tags(r: Dictionary) -> String:
	var tags := PackedStringArray()
	if int(r.get("laps", 1)) > 1 and not Game.is_sprint(HsCareer.race_track(r)):
		tags.append("%d laps" % r.laps)
	for k in ["reverse", "mirror", "night", "weather"]:
		if r[k]:
			tags.append({"reverse": "reversed", "mirror": "mirrored", "night": "night", "weather": "wet"}[k])
	return (" · ".join(tags) if not tags.is_empty() else "forward · day").capitalize()


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
