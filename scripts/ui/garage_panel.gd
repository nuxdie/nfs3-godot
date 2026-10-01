class_name GaragePanel
extends Control
## The tournaments' garage, a screen of the front end, in one of two roles:
##   your stable   (visiting, from its tab) the cars you own, each with its upgrade level and
##                 damage, then the dealer's at their prices. What decides a buy is where a
##                 car gets you, so each says how many events still to win it can enter, and
##                 the dealer's flag those none of yours can. The focused car's state sits at
##                 the foot with each action beside what it changes: upgrade by the level,
##                 repair by the damage, respray by the paint, sell by the value. A dealer's car
##                 is painted as you choose it before buying; yours keeps that paint, and the
##                 paint row beside then only tries colours on until one is paid for.
##   the entry     (choosing a car for an event) the event at the top, the cars it takes, yours
##                 first; Enter races one of yours there, or buys the dealer's.
## The menu's showroom and car sheet beside it show the car in focus.

signal focus_changed(car: int)
signal changed                    # money or the cars changed, or the focus moved
signal chosen(car: int)           # entering a circuit: race it with this car
signal transacted                 # bought, sold, upgraded or repaired (MenuSounds)
signal back

const ROW_H := 50.0
const HEAD_H := 30.0
const LIST_TOP := 84.0
const DETAIL_H := 176.0
const CLASS_NAMES := ["AAA", "AA", "A", "B"]

## The circuit being entered ({} just visiting): only the cars it takes are listed.
var circuit := {}

var _entries: Array[Dictionary] = []   # {car, owned} or {head: String}; rect set by _layout_rows()
var _focus := -1                       # index into _entries (a car)
var _hover := -1
var _scroll := 0.0
var _buttons: Array = []               # [Rect2, action] of the detail's buttons, as last drawn
var _hover_btn := -1
var _message := ""
var _message_t := 0.0
var _message_col := UiKit.COP_RED
## Car index -> its paints' names (the menu's), for the respray line.
var paint_names: Callable
var _paint_try := -1                   # a paint of yours being tried on (-1 none)
var _events := {}                      # car -> [events still to win it can enter, of those none of yours can]


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


## Shows the garage, on `car` if it's listed (else the first of yours, else the cheapest
## car for sale).
func open(car: int) -> void:
	_message = ""
	visible = true
	_rebuild(car)


func close() -> void:
	visible = false


## The car in focus (-1 none).
func car() -> int:
	return _entries[_focus].car if _focus >= 0 and _focus < _entries.size() else -1


func owned() -> bool:
	return _focus >= 0 and _entries[_focus].get("owned", false)


## What Enter does, for the main button ("" nothing).
func primary_text() -> String:
	var i := car()
	if i < 0:
		return ""
	if not owned():
		return "BUY  ·  " + UiKit.money(Game.career_price(i))
	if circuit.is_empty():
		return ""
	return "ENTER  ·  " + UiKit.money(circuit.fee) if circuit.fee > 0.0 else "ENTER CIRCUIT"


## Whether the main action can be done (else its button is shown disabled).
func primary_ok() -> bool:
	var i := car()
	if i < 0:
		return false
	if not owned():
		return Game.career_price(i) <= Game.career_money
	return circuit.is_empty() or Game.career_money >= circuit.fee


func primary() -> void:
	var i := car()
	if i < 0:
		return
	if not owned():
		_do(Game.buy_car(i), "%s bought" % Game.cars[i].name, i)
	elif not circuit.is_empty():
		if Game.career_money < circuit.fee:
			_say("Entry fee %s: not enough money" % UiKit.money(circuit.fee))
		else:
			chosen.emit(i)
	else:
		_say("Race it in a circuit: choose one in the tournaments", UiKit.INK_DIM)


## The menu's paint row moved on one of your cars: paint `p` tried on (its own: none).
func try_paint(p: int) -> void:
	_paint_try = p if owned() and p != Game.garage_paint(car()) else -1
	queue_redraw()
	changed.emit()


## The paint being tried on car `i` (-1 none).
func paint_tried(i: int) -> int:
	return _paint_try if i == car() and _paint_try >= 0 else -1


func respray() -> void:
	var i := car()
	if i >= 0 and owned() and _paint_try >= 0:
		var name := _paint_name(i, _paint_try)
		_do(Game.respray_car(i, _paint_try), "%s resprayed %s" % [Game.cars[i].name, name.to_lower()], i)


func _paint_name(i: int, p: int) -> String:
	var names: PackedStringArray = paint_names.call(i) if paint_names.is_valid() else PackedStringArray()
	return names[p] if p >= 0 and p < names.size() else "Colour %d" % (p + 1)


func upgrade() -> void:
	var i := car()
	if i >= 0 and owned():
		_do(Game.upgrade_car(i), "%s upgraded to %s" % [Game.cars[i].name, Car.UPGRADE_NAMES[Game.garage_upgrade(i) + 1].to_lower()], i)


func repair() -> void:
	var i := car()
	if i >= 0 and owned():
		_do(Game.repair_car(i), "%s repaired" % Game.cars[i].name, i)


## Sells the car in focus, once asked.
func sell() -> void:
	var i := car()
	if i < 0 or not owned():
		return
	ConfirmDialog.ask(get_parent() as Control, "Garage", "Sell the %s?" % Game.cars[i].name,
		"You get %s for it, with its upgrades. It's gone from your garage." % UiKit.money(Game.resale_value(i)),
		"Sell it", "Keep it", func(): _do(Game.sell_car(i), "%s sold" % Game.cars[i].name, i))


## After a buy, upgrade, repair or sale: the message, the list again (the car keeps focus).
func _do(err: String, done: String, i: int) -> void:
	if err != "":
		_say(err)
		return
	transacted.emit()
	_say(done, UiKit.ACCENT)
	_rebuild(i)


func _say(text: String, col := UiKit.COP_RED) -> void:
	_message = text
	_message_col = col
	_message_t = 3.5
	queue_redraw()


# ------------------------------------------------------------------ the list

func _rebuild(keep: int) -> void:
	_entries.clear()
	_paint_try = -1
	_count_events()
	var mine := Game.garage_cars().filter(_listed)
	var sale := Game.dealer_cars().filter(func(i: int) -> bool: return not Game.owns(i) and _listed(i))
	if not mine.is_empty():
		_entries.append({"head": "Your cars" if circuit.is_empty() else "Your cars it takes"})
		for i in mine:
			_entries.append({"car": i, "owned": true})
	if not sale.is_empty():
		_entries.append({"head": "Dealer" if circuit.is_empty() or not mine.is_empty() else "None of yours fits: the dealer's"})
		for i in sale:
			_entries.append({"car": i, "owned": false})
	_focus = -1
	for k in _entries.size():
		if _entries[k].get("car", -2) == keep:
			_focus = k
	if _focus < 0:
		_focus = _next_car(-1, 1)
	_layout_rows()
	_ensure_visible()
	queue_redraw()
	focus_changed.emit(car())
	changed.emit()


## For every car listed: the open events not yet won that it may enter, and how many of those
## none of your cars may.
func _count_events() -> void:
	_events.clear()
	var career := Game.career_data()
	if career == null:
		return
	var todo := []
	for t in career.tournaments:
		if not Game.tournament_open(t):
			continue
		for cid in t.circuits:
			var c: Dictionary = career.circuits.get(cid, {})
			if not c.is_empty() and Game.circuit_open(c) and int(Game.career_won.get(cid, 99)) != 1 \
					and c.restriction != HsCareer.LOANER:
				todo.append(c)
	var mine := Game.garage_cars()
	var uncovered := todo.filter(func(c: Dictionary) -> bool: return not mine.any(func(i: int) -> bool: return Game.circuit_allows(c, i)))
	for i in mine + Game.dealer_cars():
		_events[i] = [todo.filter(func(c: Dictionary) -> bool: return Game.circuit_allows(c, i)).size(),
			uncovered.filter(func(c: Dictionary) -> bool: return Game.circuit_allows(c, i)).size()]


func _listed(i: int) -> bool:
	return circuit.is_empty() or Game.circuit_allows(circuit, i)


func _layout_rows() -> void:
	var y := 0.0
	for e in _entries:
		var h := HEAD_H if e.has("head") else ROW_H
		e.rect = Rect2(0, y, size.x, h)
		y += h


func _list_rect() -> Rect2:
	return Rect2(0, LIST_TOP, size.x, size.y - LIST_TOP - DETAIL_H - 12)


func _content_h() -> float:
	return _entries[-1].rect.end.y if not _entries.is_empty() else 0.0


func _next_car(from: int, dir: int) -> int:
	var k := from + dir
	while k >= 0 and k < _entries.size():
		if _entries[k].has("car"):
			return k
		k += dir
	return from if from >= 0 and from < _entries.size() else -1


func _ensure_visible() -> void:
	if _focus < 0:
		return
	var r: Rect2 = _entries[_focus].rect
	var h := _list_rect().size.y
	# Keep the section's heading in view with its first car.
	var top := r.position.y - (HEAD_H if _focus > 0 and _entries[_focus - 1].has("head") else 0.0)
	_scroll = clampf(_scroll, r.end.y - h, top)
	_scroll = clampf(_scroll, 0.0, maxf(_content_h() - h, 0.0))


func _move(dir: int) -> void:
	_set_focus(_next_car(_focus, dir))


func _set_focus(k: int) -> void:
	if k == _focus or k < 0:
		return
	_focus = k
	_paint_try = -1
	_ensure_visible()
	queue_redraw()
	focus_changed.emit(car())
	changed.emit()


# ------------------------------------------------------------------ input

func _entry_at(p: Vector2) -> int:
	var lr := _list_rect()
	if not lr.has_point(p):
		return -1
	var q := p - lr.position + Vector2(0, _scroll)
	for k in _entries.size():
		if _entries[k].has("car") and _entries[k].rect.has_point(q):
			return k
	return -1


func _button_at(p: Vector2) -> int:
	for k in _buttons.size():
		if (_buttons[k][0] as Rect2).has_point(p):
			return k
	return -1


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := _entry_at(e.position)
		var b := _button_at(e.position)
		if h != _hover or b != _hover_btn:
			_hover = h
			_hover_btn = b
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 or b >= 0 else Control.CURSOR_ARROW
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				var b := _button_at(e.position)
				if b >= 0:
					(_buttons[b][1] as Callable).call()
				elif _hover >= 0:
					if _hover == _focus:
						primary()
					else:
						_set_focus(_hover)
			MOUSE_BUTTON_RIGHT:
				back.emit()
			MOUSE_BUTTON_WHEEL_UP:
				_scroll = clampf(_scroll - ROW_H, 0.0, maxf(_content_h() - _list_rect().size.y, 0.0))
				queue_redraw()
			MOUSE_BUTTON_WHEEL_DOWN:
				_scroll = clampf(_scroll + ROW_H, 0.0, maxf(_content_h() - _list_rect().size.y, 0.0))
				queue_redraw()
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and (_hover >= 0 or _hover_btn >= 0):
		_hover = -1
		_hover_btn = -1
		queue_redraw()
	elif what == NOTIFICATION_RESIZED:
		_layout_rows()
		_ensure_visible()


func _unhandled_input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var key := e as InputEventKey
	var pressed := key != null and key.pressed and not key.echo and not key.alt_pressed
	if e.is_action_pressed("ui_down", true):
		_move(1)
	elif e.is_action_pressed("ui_up", true):
		_move(-1)
	elif pressed and key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER] \
			or (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_A):
		primary()
	elif (pressed and key.physical_keycode == KEY_U) or (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_X):
		upgrade()
	elif (pressed and key.physical_keycode == KEY_R) or (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_LEFT_SHOULDER):
		repair()
	elif pressed and key.physical_keycode == KEY_P:
		respray()
	elif (pressed and key.physical_keycode == KEY_S) or (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_RIGHT_SHOULDER):
		sell()
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

func _moneyed() -> bool:
	# (NFS3's tournaments have no money: its cars are all yours, the bonus ones once won.)
	return Game.career_series != "nfs3"


func _draw() -> void:
	var w := size.x
	var bf := UiKit.font("body")
	if circuit.is_empty():
		_draw_stable_head(w)
	else:
		_draw_entry_head(w)
	draw_line(Vector2(0, LIST_TOP - 1), Vector2(w, LIST_TOP - 1), UiKit.LINE, 1.0)
	# The list.
	var lr := _list_rect()
	if _entries.is_empty():
		draw_string(bf, lr.position + Vector2(0, 30), "No car can enter this event." if not circuit.is_empty() else "No cars.",
			HORIZONTAL_ALIGNMENT_LEFT, w, 16, UiKit.INK_DIM)
	for k in _entries.size():
		var e: Dictionary = _entries[k]
		var r: Rect2 = e.rect
		r.position += lr.position - Vector2(0, _scroll)
		if r.end.y < lr.position.y or r.position.y > lr.end.y:
			continue
		if e.has("head"):
			if r.position.y >= lr.position.y - 4:
				UiKit.kicker(self, Vector2(0, r.position.y + 21), e.head, w)
			continue
		if r.position.y < lr.position.y - 2 or r.end.y > lr.end.y + 2:
			continue
		_draw_row(e, r.grow_individual(0, 0, -10, 0), k == _focus, k == _hover)
	# Scroll hint.
	var max_s := _content_h() - lr.size.y
	if max_s > 1.0:
		var bh := lr.size.y * lr.size.y / _content_h()
		UiKit.box(self, Rect2(w - 7, lr.position.y + (lr.size.y - bh) * _scroll / max_s, 3, bh), Color(1, 1, 1, 0.25), 2)
	_draw_detail(Rect2(0, size.y - DETAIL_H, w, DETAIL_H))


## Visiting: the money to spend (the tab above already says where you are) and the stable.
func _draw_stable_head(w: float) -> void:
	var n := Game.career_garage.size()
	if _moneyed():
		UiKit.kicker(self, Vector2(0, 14), "To spend", w, UiKit.INK_DIM)
		draw_string(UiKit.font("display", 0, true), Vector2(-1, 50), UiKit.money(Game.career_money), HORIZONTAL_ALIGNMENT_LEFT,
			w, 34, UiKit.ACCENT)
	else:
		draw_string(UiKit.font("display"), Vector2(-2, 50), "YOUR CARS", HORIZONTAL_ALIGNMENT_LEFT, w, 32, UiKit.INK)
	draw_string(UiKit.font("display", 0, true), Vector2(0, 50), str(n), HORIZONTAL_ALIGNMENT_RIGHT, w, 34, UiKit.INK)
	draw_string(UiKit.font("cond", 1), Vector2(0, 66), "CAR OWNED" if n == 1 else "CARS OWNED", HORIZONTAL_ALIGNMENT_RIGHT, w, 11,
		UiKit.INK_DIM)


## Entering an event: the event, what it takes and what it costs, over the cars it takes.
func _draw_entry_head(w: float) -> void:
	UiKit.kicker(self, Vector2(0, 14), "Entering", w)
	var name := str(circuit.get("name", "Circuit")).to_upper()
	draw_string(UiKit.font("display"), Vector2(-2, 48), name, HORIZONTAL_ALIGNMENT_LEFT, w - 150,
		UiKit.fit("display", name, w - 150, 32, 18), UiKit.INK)
	var only := Game.career_data().restriction_text(circuit)
	var bits := PackedStringArray([only if only != "" else "Any car"])
	if _moneyed():
		bits.append("entry " + UiKit.money(circuit.fee) if circuit.fee > 0.0 else "free entry")
	bits.append("%d races" % circuit.races.size())
	draw_string(UiKit.font("body"), Vector2(0, 70), "  ·  ".join(bits), HORIZONTAL_ALIGNMENT_LEFT, w, 14, UiKit.INK_DIM)
	if _moneyed():
		draw_string(UiKit.font("display", 0, true), Vector2(0, 46), UiKit.money(Game.career_money), HORIZONTAL_ALIGNMENT_RIGHT,
			w, 24, UiKit.ACCENT)
		draw_string(UiKit.font("cond", 1), Vector2(0, 60), "TO SPEND", HORIZONTAL_ALIGNMENT_RIGHT, w, 11, UiKit.INK_DIM)


func _draw_row(e: Dictionary, r: Rect2, focused: bool, hovered: bool) -> void:
	var i: int = e.car
	if focused:
		UiKit.glow(self, r, 1.0)
	elif hovered:
		UiKit.glow(self, r, 0.4, UiKit.INK, false)
	draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), Color(1, 1, 1, 0.05))
	var cy := r.get_center().y
	var cls := Game.hs_class(i)
	var badge := Rect2(r.position.x + 14, cy - 12, 40, 24)
	UiKit.box(self, badge, Color(UiKit.ACCENT, 0.95 if focused else 0.6), 3)
	draw_string(UiKit.font("display"), Vector2(badge.position.x, cy + 7), CLASS_NAMES[cls] if cls >= 0 else "—",
		HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, 16, UiKit.BG)
	var right := r.end.x - 12
	var x := badge.end.x + 14
	var name_w := right - x - 120
	var name := str(Game.cars[i].name).to_upper()
	draw_string(UiKit.font("display"), Vector2(x, cy + 1), name, HORIZONTAL_ALIGNMENT_LEFT, name_w,
		UiKit.fit("display", name, name_w, 20, 13), UiKit.INK if focused or hovered else Color(UiKit.INK, 0.85))
	# Under the name: where it gets you.
	var ev: Array = _events.get(i, [0, 0])
	var sub := ""
	var sub_col := UiKit.INK_DIM
	if not e.owned and ev[1] > 0:
		sub = "Gets you into %d new event%s" % [ev[1], "" if ev[1] == 1 else "s"]
		sub_col = UiKit.GOOD
	else:
		sub = "Fits %d event%s still to win" % [ev[0], "" if ev[0] == 1 else "s"] if ev[0] > 0 else "Fits no event still to win"
		sub_col = UiKit.INK_DIM if ev[0] > 0 else UiKit.INK_FAINT
	if sub != "":
		draw_string(UiKit.font("body"), Vector2(x, cy + 18), sub, HORIZONTAL_ALIGNMENT_LEFT, name_w, 12, sub_col)
	# At the right: yours, its upgrade level and damage; the dealer's, its price.
	if e.owned:
		if Game.upgrade_cost(i, 1) > 0:
			_pips(Vector2(right - 46, cy - 5), Game.garage_upgrade(i), focused)
		var dmg := Game.garage_damage(i)
		if dmg > 0.005:
			draw_string(UiKit.font("cond", 1), Vector2(right - 110, cy + 17), "%d%% DAMAGE" % roundi(dmg * 100.0),
				HORIZONTAL_ALIGNMENT_RIGHT, 110, 12, UiKit.COP_RED)
		else:
			var lvl := Game.garage_upgrade(i)
			draw_string(UiKit.font("cond", 1), Vector2(right - 110, cy + 17), "LEVEL %d" % lvl if lvl > 0 else "STOCK",
				HORIZONTAL_ALIGNMENT_RIGHT, 110, 12, UiKit.INK_DIM)
	elif _moneyed():
		var price := Game.career_price(i)
		var ok := price <= Game.career_money
		draw_string(UiKit.font("display", 0, true), Vector2(right - 120, cy + 1), UiKit.money(price),
			HORIZONTAL_ALIGNMENT_RIGHT, 120, 19, UiKit.INK if ok else UiKit.COP_RED)
		if not ok:
			draw_string(UiKit.font("cond", 1), Vector2(right - 120, cy + 17), "%s SHORT" % UiKit.money(price - Game.career_money),
				HORIZONTAL_ALIGNMENT_RIGHT, 120, 12, Color(UiKit.COP_RED, 0.8))


## The upgrade levels as three pips from `at` (top left), the fitted ones lit.
func _pips(at: Vector2, level: int, bright: bool) -> void:
	for k in Car.UPGRADES.size():
		var r := Rect2(at + Vector2(k * 16, 0), Vector2(12, 6))
		UiKit.box(self, r, UiKit.ACCENT if k < level else Color(1, 1, 1, 0.16 if bright else 0.1), 2)


## The focused car's state, a line per thing about it with the action that changes it.
func _draw_detail(r: Rect2) -> void:
	_buttons.clear()
	draw_line(Vector2(0, r.position.y), Vector2(r.end.x, r.position.y), UiKit.LINE, 1.0)
	var i := car()
	if i < 0:
		return
	var lines := []   # [label, value, colour, extra (Callable: draws after the label) or null, button or []]
	if owned():
		var lvl := Game.garage_upgrade(i)
		var next := Game.upgrade_cost(i, lvl + 1)
		var up_val: String = Car.UPGRADE_NAMES[lvl] + ("" if next > 0 else (" · all fitted" if lvl > 0 else ", takes none"))
		lines.append(["Upgrades", up_val, UiKit.INK, lvl if Game.upgrade_cost(i, 1) > 0 else null, ["U", "UPGRADE " + UiKit.money(next), upgrade, next <= Game.career_money]
			if next > 0 and _moneyed() else []])
		var dmg := Game.garage_damage(i)
		var fix := Game.repair_cost(i)
		lines.append(["Damage", "%d%%" % roundi(dmg * 100.0) if dmg > 0.005 else "None", UiKit.COP_RED if dmg > 0.005 else UiKit.INK,
			null, ["R", "REPAIR " + UiKit.money(fix), repair, fix <= Game.career_money] if fix > 0 else []])
		var paint := _paint_name(i, Game.garage_paint(i))
		if _paint_try >= 0:
			var cost := Game.respray_cost(i)
			lines.append(["Paint", "%s → %s" % [paint, _paint_name(i, _paint_try)], UiKit.ACCENT, null,
				["P", "RESPRAY " + (UiKit.money(cost) if cost > 0 else ""), respray, cost <= Game.career_money]])
		else:
			lines.append(["Paint", paint, UiKit.INK, null, []])
		if _moneyed():
			lines.append(["Worth", UiKit.money(Game.resale_value(i)), UiKit.INK, null, ["S", "SELL", sell, true]])
	else:
		var price := Game.career_price(i)
		var short := price - Game.career_money
		lines.append(["Price", UiKit.money(price), UiKit.INK, null, []])
		lines.append(["After", ("%s left" % UiKit.money(-short)) if short <= 0 else ("%s more needed" % UiKit.money(short)),
			UiKit.INK_DIM if short <= 0 else UiKit.COP_RED, null, []])
		var ups := PackedStringArray()
		for level in range(1, Car.UPGRADES.size() + 1):
			var c := Game.upgrade_cost(i, level)
			if c > 0:
				ups.append(UiKit.money(c))
		lines.append(["Upgrades", " / ".join(ups) if not ups.is_empty() else "None to fit", UiKit.INK, null, []])
	var y := r.position.y + 30
	var vx := 96.0
	for l in lines:
		draw_string(UiKit.font("body"), Vector2(0, y), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.INK_DIM)
		var vx2 := vx
		if l[3] is int:
			_pips(Vector2(vx, y - 9), l[3], true)
			vx2 += 56
		draw_string(UiKit.font("display", 0, true), Vector2(vx2, y + 1), l[1].to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
			r.size.x * 0.58 - vx2, UiKit.fit("display", l[1].to_upper(), r.size.x * 0.58 - vx2, 18, 12), l[2])
		if not l[4].is_empty():
			_draw_button(l[4], r.end.x, y)
		y += 31
	if _message != "":
		draw_string(UiKit.font("body_bold"), Vector2(0, r.end.y - 6), _message, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 14,
			Color(_message_col, clampf(_message_t * 2.0, 0.0, 1.0)))


## A text button, right-aligned to `right` on baseline `y`: its key and its action, lit and
## underlined under the pointer, faint when it can't be done.
func _draw_button(b: Array, right: float, y: float) -> void:
	var label: String = b[1]
	var kw0 := UiKit.key_width(b[0], 12)
	var bw := kw0 + UiKit.text_width("cond", label, 14, 1) + 28
	var br := Rect2(right - bw, y - 22, bw, 32)
	var hot: bool = _buttons.size() == _hover_btn and b[3]
	var ink := UiKit.ACCENT if hot else (UiKit.INK if b[3] else UiKit.INK_FAINT)
	var kx := br.position.x + 8
	var kw := UiKit.draw_key(self, Vector2(kx, br.get_center().y), b[0], 12, ink)
	draw_string(UiKit.font("cond", 1), Vector2(kx + kw + 8, br.get_center().y + 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
	if hot:
		draw_rect(Rect2(kx + kw + 8, br.end.y - 5, br.end.x - kx - kw - 8, 2), UiKit.ACCENT)
	_buttons.append([br, b[2]])
