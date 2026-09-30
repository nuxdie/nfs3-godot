class_name GaragePanel
extends Control
## The tournaments' garage, a screen of the front end: the cars you own, then the dealer's,
## at High Stakes' prices (Game.career_price). Yours can be upgraded (a level at a time),
## repaired and sold; the dealer's bought. Entering a circuit it lists only the cars the
## circuit takes, and Enter on one of yours races it there. The menu's showroom beside it
## shows the car in focus.

signal focus_changed(car: int)
signal changed                    # money or the cars changed, or the focus moved
signal chosen(car: int)           # entering a circuit: race it with this car
signal transacted                 # bought, sold, upgraded or repaired (MenuSounds)
signal back

const ROW_H := 42.0
const HEAD_H := 30.0
const LIST_TOP := 72.0
const DETAIL_H := 132.0
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
	var mine := Game.garage_cars().filter(_listed)
	var sale := Game.dealer_cars().filter(func(i: int) -> bool: return not Game.owns(i) and _listed(i))
	if not mine.is_empty():
		_entries.append({"head": "Your cars" if circuit.is_empty() else "Your cars it takes"})
		for i in mine:
			_entries.append({"car": i, "owned": true})
	if not sale.is_empty():
		_entries.append({"head": "Dealer"})
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

func _draw() -> void:
	var w := size.x
	var bf := UiKit.font("body")
	# Heading: what it's for, and the money.
	var title := "GARAGE" if circuit.is_empty() else "YOUR CAR FOR IT"
	draw_string(UiKit.font("display"), Vector2(-2, 34), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, UiKit.INK)
	draw_string(UiKit.font("display", 0, true), Vector2(0, 34), UiKit.money(Game.career_money), HORIZONTAL_ALIGNMENT_RIGHT,
		w, 28, UiKit.ACCENT)
	draw_string(UiKit.font("cond", 1), Vector2(0, 50), "TO SPEND", HORIZONTAL_ALIGNMENT_RIGHT, w, 11, UiKit.INK_DIM)
	var sub := "%d owned  ·  buy, upgrade, repair or sell" % Game.career_garage.size()
	if not circuit.is_empty():
		var only := Game.career_data().restriction_text(circuit)
		sub = "%s  ·  entry %s" % [only if only != "" else "Any car", UiKit.money(circuit.fee) if circuit.fee > 0.0 else "free"]
	draw_string(bf, Vector2(0, 58), sub, HORIZONTAL_ALIGNMENT_LEFT, w - 90, 15, UiKit.INK_DIM)
	draw_line(Vector2(0, LIST_TOP - 1), Vector2(w, LIST_TOP - 1), UiKit.LINE, 1.0)
	# The list.
	var lr := _list_rect()
	if _entries.is_empty():
		draw_string(bf, lr.position + Vector2(24, 30), "No car can enter this circuit.", HORIZONTAL_ALIGNMENT_LEFT,
			w - 48, 16, UiKit.INK_DIM)
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
	# At the right: yours, its upgrade level and damage; the dealer's, its price.
	var right := r.end.x - 12
	var tf := UiKit.font("cond", 1, true)
	var name_end := right - 150
	if e.owned:
		var dmg := Game.garage_damage(i)
		if dmg > 0.005:
			var bw := 46.0
			UiKit.box(self, Rect2(right - bw, cy - 2.5, bw, 5), Color(1, 1, 1, 0.1), 2)
			UiKit.box(self, Rect2(right - bw, cy - 2.5, bw * dmg, 5), UiKit.COP_RED, 2)
			draw_string(UiKit.font("cond", 1), Vector2(right - bw - 80, cy + 5), "%d%% damage" % roundi(dmg * 100.0),
				HORIZONTAL_ALIGNMENT_RIGHT, 72, 13, UiKit.COP_RED)
			right -= bw + 90
		var lvl := Game.garage_upgrade(i)
		draw_string(tf, Vector2(right - 90, cy + 5), "LEVEL %d" % lvl if lvl > 0 else "STOCK", HORIZONTAL_ALIGNMENT_RIGHT, 90, 14,
			UiKit.INK if focused else UiKit.INK_DIM)
		name_end = right - 100
	else:
		var price := Game.career_price(i)
		var ok := price <= Game.career_money
		draw_string(UiKit.font("display", 0, true), Vector2(right - 130, cy + 7), UiKit.money(price),
			HORIZONTAL_ALIGNMENT_RIGHT, 130, 19, UiKit.INK if ok else UiKit.COP_RED)
	var name := str(Game.cars[i].name).to_upper()
	var x := badge.end.x + 14
	draw_string(UiKit.font("display"), Vector2(x, cy + 7), name, HORIZONTAL_ALIGNMENT_LEFT, name_end - x,
		UiKit.fit("display", name, name_end - x, 20, 14), UiKit.INK if focused or hovered else Color(UiKit.INK, 0.85))


## The focused car's figures, and buttons for what can be done with it.
func _draw_detail(r: Rect2) -> void:
	_buttons.clear()
	draw_line(Vector2(0, r.position.y), Vector2(r.end.x, r.position.y), UiKit.LINE, 1.0)
	var i := car()
	if i < 0:
		return
	var bf := UiKit.font("body")
	var vf := UiKit.font("display", 0, true)
	var x := 0.0
	var y := r.position.y + 26
	var facts := []
	if owned():
		var lvl := Game.garage_upgrade(i)
		var next := Game.upgrade_cost(i, lvl + 1)
		facts.append(["Upgrades", Car.UPGRADE_NAMES[lvl] + ("" if next > 0 else (" · all fitted" if lvl > 0 else " · none to fit"))])
		var dmg := Game.garage_damage(i)
		facts.append(["Damage", "%d%%" % roundi(dmg * 100.0) if dmg > 0.005 else "None"])
		facts.append(["Resale", UiKit.money(Game.resale_value(i))])
	else:
		facts.append(["Price", UiKit.money(Game.career_price(i))])
		var ups := PackedStringArray()
		for level in range(1, Car.UPGRADES.size() + 1):
			var c := Game.upgrade_cost(i, level)
			if c > 0:
				ups.append(UiKit.money(c))
		facts.append(["Upgrades, level by level", " / ".join(ups) if not ups.is_empty() else "None"])
		var short := Game.career_price(i) - Game.career_money
		if short > 0:
			facts.append(["You need", "%s more" % UiKit.money(short)])
	# The middle column is the widest: the upgrades' prices go there.
	var widths := [0.26, 0.44, 0.30]
	for k in facts.size():
		var cw: float = r.size.x * widths[k]
		draw_string(bf, Vector2(x, y), facts[k][0], HORIZONTAL_ALIGNMENT_LEFT, cw - 10, 13, UiKit.INK_DIM)
		var v: String = facts[k][1].to_upper()
		draw_string(vf, Vector2(x, y + 24), v, HORIZONTAL_ALIGNMENT_LEFT, cw - 10,
			UiKit.fit("display", v, cw - 10, 19, 12), UiKit.COP_RED if facts[k][0] == "You need" else UiKit.INK)
		x += cw
	# Buttons, for yours (the dealer's are bought with the main button).
	var btns := []
	if owned():
		var next := Game.upgrade_cost(i, Game.garage_upgrade(i) + 1)
		if next > 0:
			btns.append(["U", "UPGRADE  " + UiKit.money(next), upgrade, next <= Game.career_money])
		var fix := Game.repair_cost(i)
		if fix > 0:
			btns.append(["R", "REPAIR  " + UiKit.money(fix), repair, fix <= Game.career_money])
		btns.append(["S", "SELL  " + UiKit.money(Game.resale_value(i)), sell, true])
	var bx := -12.0
	var by := r.position.y + 58
	for b in btns:
		var label: String = b[1]
		var bw := UiKit.key_width(b[0], 12) + UiKit.text_width("cond", label, 14, 1) + 34
		var br := Rect2(bx, by, bw, 34)
		var hot: bool = _buttons.size() == _hover_btn and b[3]
		# Text buttons: the key and the action, lit and underlined under the pointer.
		var ink := UiKit.ACCENT if hot else (UiKit.INK if b[3] else UiKit.INK_FAINT)
		if hot:
			draw_rect(Rect2(bx + 20 + UiKit.key_width(b[0], 12), br.end.y - 6, br.size.x - 34 - UiKit.key_width(b[0], 12), 2), UiKit.ACCENT)
		var kw := UiKit.draw_key(self, Vector2(bx + 12, br.get_center().y), b[0], 12, ink)
		draw_string(UiKit.font("cond", 1), Vector2(bx + 20 + kw, br.get_center().y + 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
		_buttons.append([br, b[2]])
		bx += bw + 8
	if _message != "":
		draw_string(UiKit.font("body_bold"), Vector2(0, r.end.y - 14), _message, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 48, 14,
			Color(_message_col, clampf(_message_t * 2.0, 0.0, 1.0)))
