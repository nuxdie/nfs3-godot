class_name Dealership
extends BrowserBase
## Every car, the way Gran Turismo 2 sells them: by maker, not by game. One screen for both
## the race's car and the career's garage.
##   the makers    on the world map, each where it builds its cars (MakerMap, as the tracks'
##                 map). Pointing at a maker shows its car you last looked at (or the one in
##                 use). In the career "My garage" sits in the head (G).
##   a maker       under its badge (NFS3's own wordmark where it has one) its models from
##                 every game, each tagged with the game; a maker with many
##                 (Porsche Unleashed's) split by model line. Tab / Shift+Tab (or the pad's
##                 shoulders) step to the next maker, Esc or Backspace back to the makers.
## Typing searches every car at once, by name, maker, country, class, game or drive.
## In a race (`career` false) every car is free: the figures in columns (a click on a heading
## sorts by it), ←→ paint and Shift+←→ trim (the menu does those), Enter uses it. In the
## career only the cars you own and the dealer's are here (only those an event takes while
## `circuit` is set): each says what it costs or how it's kept and how many events it gets
## you into; Enter buys one, or races yours in the event; the foot has the car's upgrades,
## damage, paint and worth beside the keys that change them (U, R, P, S).

signal paint_step(dir: int)
signal trim_step(dir: int)
signal changed                    # what the main button says may have changed
signal chosen(car: int)           # entering a circuit: race it with this car
signal transacted                 # bought, sold, upgraded, resprayed or repaired

const GARAGE := "\u0001garage"     # the career's own cars, as a maker of their own
## Countries with their makers (by the name shown): Tab's order through the makers.
const COUNTRIES := [
	["Germany", ["Audi", "BMW", "Mercedes", "Opel", "Porsche", "RUF", "Volkswagen"]],
	["Italy", ["Alfa Romeo", "Ferrari", "Fiat", "Italdesign", "Lamborghini", "Lancia"]],
	["France", ["Citroen", "Peugeot", "Renault", "Venturi"]],
	["Great Britain", ["Aston Martin", "Jaguar", "Lister", "Lotus", "McLaren", "Rover", "Spectre", "TVR", "Vauxhall"]],
	["United States", ["Chevrolet", "Dodge", "Ford", "Plymouth", "Pontiac", "Shelby", "Vector"]],
	["Australia", ["HSV"]],
	["Japan", ["Acura", "Daihatsu", "Honda", "Isuzu", "Mazda", "Mitsubishi", "Nissan", "Subaru", "Suzuki", "Tommykaira", "Toyota"]],
]
const SPECIALS := "Specials"      # EA's own and the police's, after the countries
## The car files' makes, as their makers are shown here.
const ALIASES := {"98 indy": "Chevrolet", "mhrt": "HSV", "holden": "HSV", "": "EA", "mercedes-benz": "Mercedes"}
## NFS3's badges (fedata/art/logos.qfs), top to bottom on its two sheets.
const LOGO_SHEETS := [["Aston Martin", "Lamborghini", "Chevrolet", "Mercedes", "Jaguar", "Italdesign"],
	["Ford", "HSV", "Ferrari", "Lister", "Spectre"]]
const LINE_SPLIT := 12            # a maker with more models than this is split by model line

const ROW_H := 40.0               # a race's row
const CAREER_ROW_H := 50.0        # a career's: with where it gets you under the name
const DETAIL_H := 140.0
const CLASS_LETTERS := "ABCX"
const HS_CLASSES := ["AAA", "AA", "A", "B"]
const SORT_MODEL := 0             # by model line (the maker's own order)
## The figures' columns: [heading, width]. Sorts 1.. are these.
const COLS := [["POWER", 52.0], ["TOP", 58.0], ["0-100", 50.0], ["WEIGHT", 62.0]]
const GAME_TAGS := ["NFS III", "HS", "PU", "HP2", "GEN", "GT2"]

static var _logos := {}           # maker -> Texture2D (silvered)
static var _logos_read := false

## The career's dealership (prices, your cars) rather than the race's free pick.
var career := false
## The circuit being entered ({} just visiting): only the cars it takes are listed.
var circuit := {}
## Car index -> its paints' names (the menu's), for the respray line.
var paint_names: Callable
var sort := SORT_MODEL
var desc := false

var _brand := ""                  # the maker open ("" the map of them)
var _maker_map: MakerMap
var _makers: Array = []           # the map's items: [{brand, cars, in_use, tag}]
var _lead := {}                   # maker -> the car of it last looked at
var _meta := {}                   # car index -> what's listed and drawn of it (_read_car)
var _col_x: Array[float] = []     # the figures' right edges, list space
var _head_hover := -3             # -5 my garage, -4 the way back, -2 the model heading, 0.. a figure
var _events := {}                 # car -> [events still to win it may enter, of those none of yours may]
var _paint_try := -1              # a paint of yours being tried on (-1 none)
var _buttons: Array = []          # [Rect2, Callable, ok] of the foot's buttons, as last drawn
var _hover_btn := -1
var _message := ""
var _message_t := 0.0
var _message_col := UiKit.COP_RED


func _init() -> void:
	super()
	title = "DEALERS"
	noun = "cars"
	filters.visible = false
	hover_previews = false
	_maker_map = MakerMap.new()
	_maker_map.focus_changed.connect(_on_map_focus)
	_maker_map.previewed.connect(func(k: int): previewed.emit(_maker_lead(k)))
	_maker_map.confirmed.connect(func(k: int): _open_brand(_makers[k].brand))
	_maker_map.cancelled.connect(_cancel)
	add_child(_maker_map)
	move_child(_maker_map, 0)


func open(item: int) -> void:
	_message = ""
	_paint_try = -1
	if _meta.is_empty():
		for i in Game.cars.size():
			_meta[i] = _read_car(i)
	_count_events()
	# A race's on the map (on the maker of the car in use); the career's on your cars (those
	# that fit) if any.
	var listed := _listed_cars()
	_brand = ""
	sort = SORT_MODEL
	desc = false
	_maker_map.close()
	if career and listed.any(func(i: int) -> bool: return Game.owns(i)):
		_brand = GARAGE
	total = listed.size()
	super(item if item in listed else (listed[0] if not listed.is_empty() else -1))
	# Not the car on show (one this event doesn't take): this one is.
	if focused_item() >= 0 and focused_item() != item:
		focus_changed.emit(focused_item())
	changed.emit()


## The car in focus (-1 none); on the map, the one the maker in focus shows.
func car() -> int:
	if at_makers():
		return _maker_lead(_maker_map.focused_item())
	return focused_item()


func owned() -> bool:
	return career and Game.owns(car())


func at_makers() -> bool:
	return _brand == "" and query == ""


## The maker open ("" none), as its name.
func brand_name(b := _brand) -> String:
	return "My garage" if b == GARAGE else b


func _maker_lead(k: int) -> int:
	return _lead_of(_makers[k].brand, _makers[k].cars) if k >= 0 and k < _makers.size() else -1


# ------------------------------------------------------------------ the cars

## What's shown and searched of car `i`: its maker and country, the model without the
## maker's name, the year it's from, its model line, its class and its figures.
func _read_car(i: int) -> Dictionary:
	var spec := Game.car_spec(i)
	var info: Dictionary = spec.info if "info" in spec else {}
	var name := str(Game.cars[i].name)
	var make := str(info.get("make", "")).strip_edges()
	var police := Game.is_pursuit_car(i)
	var brand: String = "Police" if police else ALIASES.get(make.to_lower(), make)
	var model := name.trim_prefix("Pursuit ") if police else name
	var year := 0
	var m := RegEx.create_from_string("^((?:19|20)\\d\\d) (.+)$").search(model)
	if m:
		year = m.get_string(1).to_int()
		model = m.get_string(2)
	for p in [make, brand]:
		if p != "" and model.to_lower().begins_with(p.to_lower() + " "):
			model = model.substr(p.length() + 1)
	if model.ends_with(" HS") and Game.is_hs_car(i):
		model = model.left(-3)
	var country := SPECIALS
	for c in COUNTRIES:
		if brand in c[1]:
			country = c[0]
	# The model line a maker with many is split by: "911 · 993", "356"; another game's
	# own cars of that maker go together, after them.
	var line: String = Game.GAME_NAMES[Game.car_game(i)]
	if year > 0:
		line = model.split(" ")[0]
		var gen := RegEx.create_from_string("\\((\\d{3})\\)").search(model)
		if gen:
			line += " · " + gen.get_string(1)
	var out := {"brand": brand, "country": country, "model": model, "year": year, "line": line, "make": make,
		"group": 4 if police else Game.car_class(i)}
	# The figures (the race's columns).
	out.top = spec.carp_value(15, 70.0) * 3.6
	out.kg = spec.carp_value(2, 1400.0)
	var t := CarStats.zero_to_100(spec)
	out.t100_claimed = t <= 0.0
	if t <= 0.0:
		var z := str(info.get("zero_60", "")).to_lower().replace("sec", "").replace("s", "").strip_edges()
		t = z.to_float() if z.is_valid_float() else -1.0
	out.t100 = t
	var power := str(info.get("power", "")).to_lower()
	var bhp := power.split("bhp")[0].strip_edges() if power.contains("bhp") else ""
	out.power = bhp.to_int() if bhp.is_valid_int() else -1
	out.drive = ""
	if "carp" in spec and spec.carp.has(16):
		var fd: float = spec.carp_value(16)
		out.drive = "FWD" if fd >= 1.0 else ("AWD" if fd > 0.0 else "RWD")
	return out


## The cars there are here: every car in a race; in the career yours and the dealer's
## (those the event takes, while entering one).
func _listed_cars() -> Array:
	if not career:
		return range(Game.cars.size())
	var out := Game.garage_cars().filter(_fits)
	for i in Game.dealer_cars():
		if not Game.owns(i) and _fits(i):
			out.append(i)
	return out


func _fits(i: int) -> bool:
	return circuit.is_empty() or Game.circuit_allows(circuit, i)


func _cars_of(b: String, listed: Array) -> Array:
	if b == GARAGE:
		return listed.filter(func(i: int) -> bool: return Game.owns(i))
	return listed.filter(func(i: int) -> bool: return _meta[i].brand == b)


## The makers with cars here, your garage first, then by country (Tab's order).
func _brands(listed: Array) -> Array:
	var have := {}
	for i in listed:
		have[_meta[i].brand] = true
	var out := []
	if career and listed.any(func(i: int) -> bool: return Game.owns(i)):
		out.append(GARAGE)
	for c in COUNTRIES:
		for b in c[1]:
			if have.has(b):
				out.append(b)
	var rest := have.keys().filter(func(b: String) -> bool: return not out.has(b) and b != "Police")
	rest.sort()
	if have.has("Police"):
		rest.append("Police")
	return out + rest


## The car a maker's badge shows: the one last looked at, the one in use, else its first.
func _lead_of(b: String, cars: Array) -> int:
	if _lead.has(b) and _lead[b] in cars:
		return _lead[b]
	if picked in cars:
		return picked
	return _ordered(b, cars)[0]


## A maker's cars in its own order: by model line (the oldest first), year, then name.
func _ordered(b: String, cars: Array) -> Array:
	var first := {}   # line -> its first year (other games' after)
	for i in cars:
		var mt: Dictionary = _meta[i]
		var y: int = mt.year if mt.year > 0 else 9000 + Game.car_game(i)
		first[mt.line] = mini(first.get(mt.line, 99999), y)
	var out := cars.duplicate()
	if b == GARAGE:
		return out    # (cheapest first, as the garage keeps them)
	out.sort_custom(func(x: int, y: int) -> bool:
		var a: Dictionary = _meta[x]
		var c: Dictionary = _meta[y]
		if a.line != c.line:
			return first[a.line] < first[c.line] if first[a.line] != first[c.line] else a.line < c.line
		if a.year != c.year:
			return a.year < c.year
		if a.model.to_lower() != c.model.to_lower():
			return a.model.to_lower() < c.model.to_lower()
		return Game.car_game(x) < Game.car_game(y))
	return out


# ------------------------------------------------------------------ entries

func _build_entries() -> Array[Dictionary]:
	var listed := _listed_cars()
	total = listed.size()
	var out: Array[Dictionary] = []
	if query != "":
		# Every car that matches, under its maker.
		var hits := listed.filter(func(i: int) -> bool: return _matches(_haystack(i)))
		for b in _brands(hits):
			if b == GARAGE:
				continue
			out.append({"item": -1, "text": b})
			for i in _sorted(b, _cars_of(b, hits)):
				out.append({"item": i, "text": Game.cars[i].name})
		return out
	if _brand == "":
		return out   # (the map has them)
	var cars := _cars_of(_brand, listed)
	if cars.is_empty():
		return out
	var split := sort == SORT_MODEL and _brand != GARAGE and cars.size() > LINE_SPLIT
	var last := ""
	for i in _sorted(_brand, cars):
		if split and _meta[i].line != last:
			last = _meta[i].line
			out.append({"item": -1, "text": last})
		out.append({"item": i, "text": Game.cars[i].name})
	return out


func _haystack(i: int) -> String:
	var mt: Dictionary = _meta[i]
	var g: int = mt.group
	return ("%s %s %s %s %s %s %s %d" % [Game.cars[i].name, mt.brand, mt.make, mt.country,
		"police pursuit" if g == 4 else "class " + "abcx"[g], ["nfs3 hot pursuit", "high stakes hs nfs4",
		"porsche unleashed pu nfs5", "hot pursuit 2 hp2 nfs6", "generated procedural", "gran turismo 2 gt2"][Game.car_game(i)], mt.drive, mt.year]).to_lower()


## A maker's cars in the order chosen: its own, or by a figure.
func _sorted(b: String, cars: Array) -> Array:
	var ids := _ordered(b, cars)
	if sort > SORT_MODEL and not career:
		var k := sort - 1
		# Less is better for the 0-100 and the weight; unknown figures always last.
		var up := k >= 2
		ids.sort_custom(func(x: int, y: int) -> bool:
			var fa := _figure(x, k)
			var fb := _figure(y, k)
			if (fa < 0.0) != (fb < 0.0):
				return fb < 0.0
			if is_equal_approx(fa, fb):
				return x < y
			return (fa < fb) == up)
	if desc:
		ids.reverse()
	return ids


func _figure(i: int, k: int) -> float:
	var mt: Dictionary = _meta[i]
	return [mt.power, mt.top, mt.t100, mt.kg][k]


func _layout_entries(w: float) -> float:
	_col_x.clear()
	var x := w - 16
	for k in range(COLS.size() - 1, -1, -1):
		_col_x.push_front(x)
		x -= COLS[k][1]
	var y := 4.0
	var rh := CAREER_ROW_H if career else ROW_H
	for e in entries:
		var h := 32.0 if e.item < 0 else rh
		e.rect = Rect2(0, y, w - 14, h)
		y += h
	return y + 8.0


# ------------------------------------------------------------------ moving about

func _open_brand(b: String) -> void:
	_brand = b
	sort = SORT_MODEL
	desc = false
	_scroll_to = 0.0
	_scroll = 0.0
	_layout()
	var listed := _listed_cars()
	var was := current
	_rebuild(_lead_of(b, _cars_of(b, listed)) if b != "" else -2)
	# (What it opens on is shown: the menu only hears of a move.)
	if focused_item() >= 0 and focused_item() != was:
		current = focused_item()
		focus_changed.emit(current)
	_scroll = _scroll_to
	queue_redraw()
	changed.emit()


## Back to the map, on the maker just left (from your garage, the car's maker).
func _up() -> void:
	var was := focused_item()
	if was >= 0:
		_lead[_brand] = was
		_lead[_meta[was].brand] = was
	_brand = ""
	_layout()
	_rebuild(-1)
	if car() >= 0 and car() != was:
		current = car()
		focus_changed.emit(current)
	queue_redraw()
	changed.emit()


## Shows the map while it's the makers (not a maker, not a search), on the maker of the car
## last in focus.
func _sync_map() -> void:
	var on := at_makers() and visible
	_list.visible = not on
	if on and not _maker_map.visible:
		var listed := _listed_cars()
		_makers = []
		var brand: String = _meta[current].brand if current >= 0 and _meta.has(current) else ""
		var at := 0
		for b in _brands(listed):
			if b == GARAGE:
				continue
			var cars := _cars_of(b, listed)
			if b == brand:
				at = _makers.size()
			_makers.append({"brand": b, "cars": cars, "in_use": not career and picked in cars, "tag": _maker_tag(cars)})
		_maker_map.set_makers(_makers)
		_maker_map.open(at)
	elif not on and _maker_map.visible:
		_maker_map.close()


## After a maker's name on the map: how many cars; in the career how many are yours.
func _maker_tag(cars: Array) -> String:
	var n := cars.size()
	var yours := cars.filter(func(i: int) -> bool: return Game.owns(i)).size() if career else 0
	return "%d YOURS" % yours if yours > 0 else "%d CAR%s" % [n, "" if n == 1 else "S"]


## The map's focus moved: its maker's car is the one on show.
func _on_map_focus(_k: int) -> void:
	var i := car()
	if i >= 0:
		current = i
		focus_changed.emit(i)
	queue_redraw()
	changed.emit()


## The next maker (or the one before) while one is open.
func _step_brand(dir: int) -> void:
	var brands := _brands(_listed_cars())
	if brands.size() < 2:
		return
	if focused_item() >= 0:
		_lead[_brand] = focused_item()
	_open_brand(brands[posmod(brands.find(_brand) + dir, brands.size())])


func _set_focus(k: int) -> void:
	super(k)
	_paint_try = -1
	if focused_item() >= 0 and query == "":
		_lead[_brand] = focused_item()
	queue_redraw()
	changed.emit()


func _rebuild(keep := -2) -> void:
	super(keep)
	_sync_map()
	queue_redraw()
	changed.emit()


func _confirm() -> void:
	var k := focus
	if k < 0 or k >= entries.size() or entries[k].item < 0:
		return
	if query != "":
		# A car found: its maker is where it's chosen from.
		_brand = _meta[entries[k].item].brand
		_lead[_brand] = entries[k].item
	if career:
		current = entries[k].item
		primary()
		return
	super()


func _cancel() -> void:
	if _brand != "":
		_up()
	else:
		cancelled.emit()


func _side_step(dir: int, shift := false, ctrl := false) -> void:
	if ctrl and not career:
		sort = posmod(sort + dir, 1 + COLS.size())
		desc = false
		_rebuild()
	elif shift and not career:
		trim_step.emit(dir)
	elif not shift and not ctrl:
		paint_step.emit(dir)


func hints() -> Array:
	if at_makers():
		return _maker_map.hints() + ([["G", "MY GARAGE"]] if _has_garage() else [["", "TYPE TO SEARCH"]] if not career else [])
	var h := [["↑↓", "BROWSE"], ["TAB", "NEXT MAKER"], ["ESC", "MAKERS"], ["←→", "PAINT"]]
	if not career:
		h.append(["SHIFT ←→", "TRIM"])
	return h


# ------------------------------------------------------------------ input

func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	var key := e as InputEventKey
	if key and key.pressed and not key.echo and not key.alt_pressed and not key.ctrl_pressed:
		var done := true
		match key.physical_keycode:
			KEY_TAB:
				if _brand != "" and query == "":
					_step_brand(-1 if key.shift_pressed else 1)
			KEY_BACKSPACE:
				done = query == "" and _brand != ""
				if done:
					_up()
			KEY_G when _has_garage() and at_makers():
				_open_brand(GARAGE)
			KEY_U when career and not at_makers():
				upgrade()
			KEY_R when career and not at_makers():
				repair()
			KEY_P when career and not at_makers():
				respray()
			KEY_S when career and not at_makers():
				sell()
			_:
				done = false
				# No typing to search in the career: its letters are its actions, and Q / E
				# the menu's tabs.
				if career and key.unicode >= 32:
					return
		if done:
			get_viewport().set_input_as_handled()
			return
	var pad := e as InputEventJoypadButton
	if pad and pad.pressed:
		if pad.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
			# (The career's tabs have the shoulders, while they're showing.)
			if career and circuit.is_empty():
				return
			if _brand != "":
				_step_brand(-1 if pad.button_index == JOY_BUTTON_LEFT_SHOULDER else 1)
			get_viewport().set_input_as_handled()
			return
		if career and pad.button_index == JOY_BUTTON_X and not at_makers():
			upgrade()
			get_viewport().set_input_as_handled()
			return
		if career and pad.button_index == JOY_BUTTON_Y:
			if at_makers():
				if _has_garage():
					_open_brand(GARAGE)
			else:
				repair()
			get_viewport().set_input_as_handled()
			return
	super(e)


## A click picks a car out (puts it on show) and a second on it does what Enter does (races
## it, buys it, say): browsing never takes a car by itself.
func _on_list_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not grid:
		var k := _entry_at(e.position)
		if k >= 0 and entries[k].item != current:
			focus = -1
			_set_focus(k)
			_list.accept_event()
			return
	super(e)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := _head_at(e.position)
		var b := _button_at(e.position)
		if h != _head_hover or b != _hover_btn:
			_head_hover = h
			_hover_btn = b
			queue_redraw()
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h > -3 or b >= 0 else Control.CURSOR_ARROW
		return
	if not (e is InputEventMouseButton and e.pressed):
		return
	if e.button_index == MOUSE_BUTTON_RIGHT:
		_cancel()
		accept_event()
		return
	if e.button_index != MOUSE_BUTTON_LEFT:
		return
	var b := _button_at(e.position)
	if b >= 0:
		if _buttons[b][2]:
			(_buttons[b][1] as Callable).call()
		accept_event()
		return
	var h := _head_at(e.position)
	if h == -5:
		_open_brand(GARAGE)
	elif h == -4:
		_up()
	elif h == -2:
		sort = SORT_MODEL
		desc = false
		_rebuild()
	elif h >= 0:
		if sort == h + 1:
			desc = not desc
		else:
			sort = h + 1
			desc = false
		_rebuild()
	else:
		return
	accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and (_head_hover > -3 or _hover_btn >= 0):
		_head_hover = -3
		_hover_btn = -1
		queue_redraw()


func _process(dt: float) -> void:
	super(dt)
	if _message_t > 0.0:
		_message_t -= dt
		if _message_t <= 0.0:
			_message = ""
			queue_redraw()


# ------------------------------------------------------------------ the career's actions

## What Enter does, for the main button ("" nothing).
func primary_text() -> String:
	if at_makers():
		var k := _maker_map.focused_item()
		return "VISIT " + str(_makers[k].brand).to_upper() if k >= 0 and k < _makers.size() else ""
	var i := car()
	if i < 0:
		return ""
	if not career:
		return "USE THIS CAR"
	if not owned():
		return "BUY  ·  " + UiKit.money(Game.career_price(i)) if _moneyed() else ""
	if circuit.is_empty():
		return ""
	return "ENTER  ·  " + UiKit.money(circuit.fee) if circuit.fee > 0.0 else "ENTER CIRCUIT"


## Whether the main action can be done (else its button is shown disabled).
func primary_ok() -> bool:
	var i := car()
	if i < 0 or at_makers() or not career:
		return i >= 0
	if not owned():
		return Game.career_price(i) <= Game.career_money
	return circuit.is_empty() or Game.career_money >= circuit.fee


func primary() -> void:
	if at_makers():
		var k := _maker_map.focused_item()
		if k >= 0 and k < _makers.size():
			_open_brand(_makers[k].brand)
		return
	var i := car()
	if i < 0:
		return
	if not career:
		current = i
		confirmed.emit(i)
	elif not owned():
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
		_do(Game.upgrade_car(i), "%s upgraded to %s" % [Game.cars[i].name,
			Car.UPGRADE_NAMES[mini(Game.garage_upgrade(i) + 1, Car.UPGRADE_NAMES.size() - 1)].to_lower()], i)


func repair() -> void:
	var i := car()
	if i >= 0 and owned():
		_do(Game.repair_car(i), "%s repaired" % Game.cars[i].name, i)


## Sells the car in focus, once asked.
func sell() -> void:
	var i := car()
	if i < 0 or not owned() or not _moneyed():
		return
	ConfirmDialog.ask(get_parent() as Control, "Garage", "Sell the %s?" % Game.cars[i].name,
		"You get %s for it, with its upgrades. It's gone from your garage." % UiKit.money(Game.resale_value(i)),
		"Sell it", "Keep it", func(): _do(Game.sell_car(i), "%s sold" % Game.cars[i].name, i))


## After a buy, upgrade, repair or sale: the message, the cars again (the car keeps focus
## where it's still listed: a car sold stays at its maker's).
func _do(err: String, done: String, i: int) -> void:
	if err != "":
		_say(err)
		return
	transacted.emit()
	_say(done, UiKit.ACCENT)
	_count_events()
	var listed := _listed_cars()
	if _brand == GARAGE and not i in _cars_of(GARAGE, listed):
		_brand = _meta[i].brand if i in listed else ""
	_paint_try = -1
	_layout()
	_rebuild(i)


func _say(text: String, col := UiKit.COP_RED) -> void:
	_message = text
	_message_col = col
	_message_t = 3.5
	queue_redraw()


func _moneyed() -> bool:
	# (NFS3's tournaments have no money: its cars are all yours, the bonus ones once won.)
	return Game.career_series != "nfs3"


## For every car listed: the open events not yet won that it may enter, and how many of those
## none of your cars may.
func _count_events() -> void:
	_events.clear()
	var data: HsCareer = Game.career_data() if career else null
	if data == null:
		return
	var todo := []
	for t in data.tournaments:
		if not Game.tournament_open(t):
			continue
		for cid in t.circuits:
			var c: Dictionary = data.circuits.get(cid, {})
			if not c.is_empty() and Game.circuit_open(c) and int(Game.career_won.get(cid, 99)) != 1 \
					and c.restriction != HsCareer.LOANER:
				todo.append(c)
	var mine := Game.garage_cars()
	var uncovered := todo.filter(func(c: Dictionary) -> bool: return not mine.any(func(i: int) -> bool: return Game.circuit_allows(c, i)))
	for i in mine + Game.dealer_cars():
		_events[i] = [todo.filter(func(c: Dictionary) -> bool: return Game.circuit_allows(c, i)).size(),
			uncovered.filter(func(c: Dictionary) -> bool: return Game.circuit_allows(c, i)).size()]


# ------------------------------------------------------------------ layout

func _layout() -> void:
	head_h = _head_height()
	_list.position = Vector2(0, head_h)
	_list.size = Vector2(size.x, maxf(size.y - head_h - (DETAIL_H if career else 0.0), 40))
	_layout_list()
	_maker_map.position = Vector2(0, head_h + 6)
	_maker_map.size = _list.size - Vector2(0, 6)
	_sync_map()
	queue_redraw()


## Whether "My garage" is there to open (the career's, with a car of yours that fits).
func _has_garage() -> bool:
	return career and _listed_cars().any(func(i: int) -> bool: return Game.owns(i))


func _garage_rect() -> Rect2:
	var label := "MY GARAGE  ·  %d" % _cars_of(GARAGE, _listed_cars()).size()
	var bw := UiKit.key_width("G", 12) + UiKit.text_width("cond", label, 14, 1) + 28
	return Rect2(size.x - bw, 26, bw, 30)


## The head: the way back and the title; the search (a race's); the columns' headings (a
## race's maker or search).
func _head_height() -> float:
	var h := 64.0
	if career and not circuit.is_empty():
		h += 18.0
	if not career:
		h += 44.0
		if not at_makers():
			h += 30.0
	return h


func _search_rect() -> Rect2:
	return Rect2(0, 62, size.x, 36)


## The headings' rects (panel space): -4 the way back to the makers, -2 the model heading,
## 0.. the figures.
func _head_rects() -> Dictionary:
	var out := {}
	if _brand != "" and query == "":
		out[-4] = Rect2(-4, 0, 200, 52)
	if at_makers() and _has_garage():
		out[-5] = _garage_rect()
	if not career and not at_makers():
		var y := head_h - 26
		out[-2] = Rect2(0, y, 160, 24)
		for k in COLS.size():
			if k < _col_x.size():
				out[k] = Rect2(_col_x[k] - COLS[k][1], y, COLS[k][1], 24)
	return out


func _head_at(p: Vector2) -> int:
	var rects := _head_rects()
	for k in rects:
		if (rects[k] as Rect2).has_point(p):
			return k
	return -3


func _button_at(p: Vector2) -> int:
	for k in _buttons.size():
		if (_buttons[k][0] as Rect2).has_point(p):
			return k
	return -1


func _head_hot() -> bool:
	return _head_hover > -3


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var w := size.x
	var listed_n := entries.filter(func(en: Dictionary) -> bool: return en.item >= 0).size()
	var in_maker := _brand != "" and query == ""
	# The way back, then where you are (where the maker builds its cars).
	var crumb := "‹  Dealers" if in_maker else "Dealers"
	if in_maker and _brand != GARAGE:
		crumb += "  ·  " + MakerMap.where(_brand)
	UiKit.kicker(self, Vector2(0, 14), crumb, w * 0.8, UiKit.INK if _head_hover == -4 else UiKit.ACCENT)
	var big := "SEARCH" if query != "" else ("ALL MAKERS" if _brand == "" else brand_name().to_upper())
	var right_w := _garage_rect().size.x + 16 if at_makers() and _has_garage() else 0.0
	var max_w := w - right_w - 90
	var tw := 0.0
	var logo := _logo(_brand) if in_maker else null
	if logo:
		# The maker's own badge for its name.
		var s := minf(34.0 / logo.get_height(), max_w / logo.get_width())
		draw_texture_rect(logo, Rect2(0, 20, logo.get_width() * s, logo.get_height() * s), false, UiKit.INK)
		tw = logo.get_width() * s
	else:
		var tf := UiKit.font("display")
		var fs := UiKit.fit("display", big, max_w, 32, 20)
		draw_string(tf, Vector2(-2, 50), big, HORIZONTAL_ALIGNMENT_LEFT, max_w, fs, UiKit.INK)
		tw = minf(tf.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, max_w)
	if right_w > 0.0:
		_draw_garage_button(_garage_rect())
	var n := _makers.size() if at_makers() else listed_n
	var count := "%d %s" % [n, ("maker" if n == 1 else "makers") if at_makers() else ("car" if n == 1 else "cars")]
	draw_string(UiKit.font("cond", 1, true), Vector2(tw + 10, 49), count, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiKit.ACCENT)
	if career and not circuit.is_empty():
		var only := Game.career_data().restriction_text(circuit)
		var bits := PackedStringArray([only if only != "" else "Any car"])
		if _moneyed():
			bits.append("entry " + UiKit.money(circuit.fee) if circuit.fee > 0.0 else "free entry")
		bits.append("%d races" % circuit.races.size())
		# (The money's in the bar while visiting; here the bar is the way back.)
		# (What it is the bar above says.)
		var x := 0.0
		if _moneyed():
			var ms := UiKit.money(Game.career_money) + " to spend"
			draw_string(UiKit.font("body_bold"), Vector2(0, 72), ms, HORIZONTAL_ALIGNMENT_LEFT, w, 14, UiKit.ACCENT)
			x = UiKit.text_width("body_bold", ms, 14) + 6
		draw_string(UiKit.font("body"), Vector2(x, 72), "·  " + "  ·  ".join(bits) if x > 0.0 else "  ·  ".join(bits),
			HORIZONTAL_ALIGNMENT_LEFT, w - x, 14, UiKit.INK_DIM)
	if not career:
		_draw_search(_search_rect())
		if not at_makers():
			_draw_columns()
	draw_line(Vector2(0, head_h - 1), Vector2(w, head_h - 1), UiKit.LINE, 1.0)
	if career:
		_draw_detail(Rect2(0, size.y - DETAIL_H, w, DETAIL_H))


## "My garage" on the map's head: its key, its name and how many cars, lit under the pointer.
func _draw_garage_button(r: Rect2) -> void:
	var hot := _head_hover == -5
	var ink := UiKit.ACCENT if hot else UiKit.INK
	UiKit.box(self, r, Color(1, 1, 1, 0.08 if hot else 0.04), 4, Color(UiKit.ACCENT, 0.7 if hot else 0.35), 1)
	var kw := UiKit.draw_key(self, Vector2(r.position.x + 8, r.get_center().y), "G", 12, ink)
	draw_string(UiKit.font("cond", 1), Vector2(r.position.x + 16 + kw, r.get_center().y + 5),
		"MY GARAGE  ·  %d" % _cars_of(GARAGE, _listed_cars()).size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)


func _draw_search(sr: Rect2) -> void:
	draw_rect(Rect2(sr.position.x, sr.end.y - 1, sr.size.x, 1), UiKit.ACCENT if query != "" else Color(1, 1, 1, 0.25))
	var gc := sr.position + Vector2(8, 16)
	draw_arc(gc, 6.0, 0, TAU, 20, UiKit.INK_DIM, 2.0, true)
	draw_line(gc + Vector2(4.5, 4.5), gc + Vector2(9, 9), UiKit.INK_DIM, 2.0, true)
	var bf := UiKit.font("body")
	var tx := sr.position.x + 28
	if query == "":
		draw_string(bf, Vector2(tx, sr.position.y + 23), "Type to search every car", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.INK_FAINT)
	else:
		draw_string(bf, Vector2(tx, sr.position.y + 23), query, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.INK)
		tx += bf.get_string_size(query, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 2
		UiKit.draw_key(self, Vector2(sr.end.x - 96, sr.get_center().y), "ESC", 11, UiKit.INK_DIM)
		draw_string(UiKit.font("cond", 1), Vector2(sr.end.x - 56, sr.get_center().y + 5), "CLEAR", HORIZONTAL_ALIGNMENT_LEFT,
			-1, 13, UiKit.INK_DIM)
	if fmod(_time, 1.0) < 0.5:
		draw_rect(Rect2(tx, sr.position.y + 8, 2, 19), UiKit.ACCENT)


func _draw_columns() -> void:
	var rects := _head_rects()
	var f := UiKit.font("cond", 1)
	var units := ["BHP", "KM/H" if Game.units_kmh else "MPH", "S", "KG" if Game.units_kmh else "LB"]
	for k in rects:
		if k == -4:
			continue
		var r: Rect2 = rects[k]
		var lit: bool = (k == -2 and sort == SORT_MODEL) or sort == k + 1
		var hot: bool = k == _head_hover
		var col := UiKit.ACCENT if lit else (UiKit.INK if hot else UiKit.INK_DIM)
		var label: String = "BY MODEL" if k == -2 else COLS[k][0]
		var align := HORIZONTAL_ALIGNMENT_LEFT if k == -2 else HORIZONTAL_ALIGNMENT_RIGHT
		var x := r.position.x + (12.0 if k == -2 else 0.0)
		var w := r.size.x - (12.0 if k == -2 else 6.0)
		draw_string(f, Vector2(x, r.position.y + 11), label, align, w, 12, col)
		if k >= 0:
			draw_string(f, Vector2(x, r.position.y + 23), units[k], align, w, 10, Color(col, col.a * 0.7))
		if lit and k >= 0:
			var ax: float = r.end.x - 6 - UiKit.text_width("cond", label, 12, 1) - 9
			UiKit.chevron(self, Vector2(ax, r.position.y + 7), 2 if not desc else -2, UiKit.ACCENT, 3.0, 1.5)


func _draw_entry(ci: CanvasItem, e: Dictionary, r: Rect2, focused: bool, hovered: bool) -> void:
	if career:
		_draw_career_row(ci, e.item, r, focused, hovered)
	else:
		_draw_race_row(ci, e.item, r, focused, hovered)


## The class badge and the name with its year and tags, shared by both kinds of row; returns
## where the name ends.
func _draw_name(ci: CanvasItem, i: int, r: Rect2, focused: bool, hovered: bool, badge: String, badge_col: Color,
		cy: float, max_x: float) -> float:
	var bw := 22.0 if badge.length() <= 1 else 38.0
	var br := Rect2(r.position.x + 12, cy - 10, bw, 20)
	UiKit.box(ci, br, Color(badge_col, 0.95 if focused else 0.6), 3)
	ci.draw_string(UiKit.font("display"), Vector2(br.position.x, cy + 7), badge, HORIZONTAL_ALIGNMENT_CENTER, br.size.x,
		16 if badge.length() <= 2 else 14, UiKit.BG)
	var mt: Dictionary = _meta[i]
	var x := br.end.x + 12
	var tf := UiKit.font("cond", 1, true)
	if mt.year > 0:
		ci.draw_string(tf, Vector2(x, cy + 6), str(mt.year), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiKit.INK_DIM)
		x += 40
	# On search, or in your garage, the maker's name goes with the model.
	var name: String = mt.model
	if query != "" or _brand == GARAGE:
		name = (mt.brand + " " + name) if mt.brand != "EA" and mt.brand != "Police" else str(Game.cars[i].name)
	name = name.to_upper()
	var nf := UiKit.font("display")
	var fs := UiKit.fit("display", name, max_x - x, 19, 13)
	ci.draw_string(nf, Vector2(x, cy + 7), name, HORIZONTAL_ALIGNMENT_LEFT, max_x - x, fs,
		UiKit.INK if focused or hovered else Color(UiKit.INK, 0.85))
	x += minf(nf.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, max_x - x) + 8
	var tags := [[GAME_TAGS[Game.car_game(i)], UiKit.INK_DIM]]
	if not career and i == picked:
		tags.append(["IN USE", UiKit.ACCENT])
	elif career and Game.owns(i) and _brand != GARAGE:
		tags.append(["YOURS", UiKit.ACCENT])
	var gf := UiKit.font("cond", 1)
	for tag in tags:
		var tw := gf.get_string_size(tag[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12
		if x + tw > max_x:
			break
		UiKit.box(ci, Rect2(x, cy - 9, tw, 18), Color(0, 0, 0, 0), 9, Color(tag[1], 0.6))
		ci.draw_string(gf, Vector2(x + 6, cy + 4), tag[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tag[1])
		x += tw + 6
	return x


func _row_back(ci: CanvasItem, r: Rect2, focused: bool, hovered: bool) -> void:
	if focused:
		UiKit.glow(ci, r, 1.0)
	elif hovered:
		UiKit.glow(ci, r, 0.4, UiKit.INK, false)
	ci.draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), Color(1, 1, 1, 0.05))


## A race's row: class, year and model, the figures in columns (the one sorted by lit).
func _draw_race_row(ci: CanvasItem, i: int, r: Rect2, focused: bool, hovered: bool) -> void:
	_row_back(ci, r, focused, hovered)
	var g: int = _meta[i].group
	var cy := r.get_center().y
	_draw_name(ci, i, r, focused, hovered, "P" if g == 4 else CLASS_LETTERS[g], UiKit.COP_BLUE if g == 4 else UiKit.ACCENT,
		cy, _col_x[0] - COLS[0][1] - 6)
	var ff := UiKit.font("cond", 1, true)
	for k in COLS.size():
		var lit := sort == k + 1
		var col := UiKit.INK if lit or focused else UiKit.INK_DIM
		if k == 2 and _meta[i].t100_claimed:
			col = Color(col, col.a * 0.6)
		ci.draw_string(ff, Vector2(_col_x[k] - COLS[k][1], cy + 5), _col_text(i, k), HORIZONTAL_ALIGNMENT_RIGHT,
			COLS[k][1] - 6, 15 if lit else 14, col)


func _col_text(i: int, k: int) -> String:
	var v := _figure(i, k)
	if v < 0.0:
		return "—"
	match k:
		0: return "%d" % roundi(v)
		1: return "%d" % roundi(v if Game.units_kmh else v / 1.609)
		2: return "%.1f" % v
	return "%d" % roundi(v if Game.units_kmh else v * 2.2046)


## A career's row: class, model, where it gets you under it; at the right yours' upgrades
## and damage, the dealer's price.
func _draw_career_row(ci: CanvasItem, i: int, r: Rect2, focused: bool, hovered: bool) -> void:
	_row_back(ci, r, focused, hovered)
	var cls := Game.hs_class(i)
	var right := r.end.x - 12
	var cy := r.get_center().y
	var mine := Game.owns(i)
	_draw_name(ci, i, r, focused, hovered, HS_CLASSES[cls] if cls >= 0 else "—", UiKit.ACCENT, cy - 7, right - 120)
	var ev: Array = _events.get(i, [0, 0])
	var sub := ""
	var sub_col := UiKit.INK_DIM
	if not mine and ev[1] > 0:
		sub = "Gets you into %d new event%s" % [ev[1], "" if ev[1] == 1 else "s"]
		sub_col = UiKit.GOOD
	else:
		sub = "Fits %d event%s still to win" % [ev[0], "" if ev[0] == 1 else "s"] if ev[0] > 0 else "Fits no event still to win"
		sub_col = UiKit.INK_DIM if ev[0] > 0 else UiKit.INK_FAINT
	ci.draw_string(UiKit.font("body"), Vector2(r.position.x + 62, cy + 17), sub, HORIZONTAL_ALIGNMENT_LEFT, right - 120 - 62, 12, sub_col)
	if mine:
		if Game.upgrade_cost(i, 1) > 0:
			_pips(ci, Vector2(right - 46, cy - 9), Game.garage_upgrade(i), focused)
		var dmg := Game.garage_damage(i)
		var lvl := Game.garage_upgrade(i)
		var txt := "%d%% DAMAGE" % roundi(dmg * 100.0) if dmg > 0.005 else ("LEVEL %d" % lvl if lvl > 0 else "STOCK")
		ci.draw_string(UiKit.font("cond", 1), Vector2(right - 110, cy + 14), txt, HORIZONTAL_ALIGNMENT_RIGHT, 110, 12,
			UiKit.COP_RED if dmg > 0.005 else UiKit.INK_DIM)
	elif _moneyed():
		var price := Game.career_price(i)
		var ok := price <= Game.career_money
		ci.draw_string(UiKit.font("display", 0, true), Vector2(right - 120, cy - 1), UiKit.money(price),
			HORIZONTAL_ALIGNMENT_RIGHT, 120, 19, UiKit.INK if ok else UiKit.COP_RED)
		if not ok:
			ci.draw_string(UiKit.font("cond", 1), Vector2(right - 120, cy + 15), "%s SHORT" % UiKit.money(price - Game.career_money),
				HORIZONTAL_ALIGNMENT_RIGHT, 120, 12, Color(UiKit.COP_RED, 0.8))


## The upgrade levels as three pips from `at` (top left), the fitted ones lit.
func _pips(ci: CanvasItem, at: Vector2, level: int, bright: bool) -> void:
	for k in Car.UPGRADES.size():
		UiKit.box(ci, Rect2(at + Vector2(k * 16, 0), Vector2(12, 6)), UiKit.ACCENT if k < level else Color(1, 1, 1, 0.16 if bright else 0.1), 2)


## The career's foot: the focused car's state, a line per thing about it with the action
## that changes it.
func _draw_detail(r: Rect2) -> void:
	_buttons.clear()
	draw_line(Vector2(0, r.position.y), Vector2(r.end.x, r.position.y), UiKit.LINE, 1.0)
	var i := car()
	if i < 0:
		return
	var lines := []   # [label, value, colour, pips (int) or null, button or []]
	if at_makers():
		var k := _maker_map.focused_item()
		if k < 0 or k >= _makers.size():
			return
		var cars: Array = _makers[k].cars
		var sale := cars.filter(func(c: int) -> bool: return not Game.owns(c))
		var yours := cars.size() - sale.size()
		lines.append(["Yours", "%d car%s" % [yours, "" if yours == 1 else "s"] if yours > 0 else "None yet", UiKit.INK, null, []])
		if not sale.is_empty() and _moneyed():
			var prices := sale.map(func(c: int) -> int: return Game.career_price(c))
			var span := UiKit.money(prices.min()) + ("" if prices.min() == prices.max() else " to " + UiKit.money(prices.max()))
			lines.append(["For sale", "%d · %s" % [sale.size(), span], UiKit.INK, null, []])
		var fits := cars.filter(func(c: int) -> bool: return _events.get(c, [0, 0])[1] > 0).size()
		if fits > 0:
			lines.append(["New events", "%d of its cars open one" % fits, UiKit.GOOD, null, []])
	elif owned():
		var lvl := Game.garage_upgrade(i)
		var next := Game.upgrade_cost(i, lvl + 1)
		var up_val: String = Car.UPGRADE_NAMES[lvl] + ("" if next > 0 else (" · all fitted" if lvl > 0 else ", takes none"))
		lines.append(["Upgrades", up_val, UiKit.INK, lvl if Game.upgrade_cost(i, 1) > 0 else null,
			["U", "UPGRADE " + UiKit.money(next), upgrade, next <= Game.career_money] if next > 0 and _moneyed() else []])
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
		if _moneyed():
			lines.append(["After", ("%s left" % UiKit.money(-short)) if short <= 0 else ("%s more needed" % UiKit.money(short)),
				UiKit.INK_DIM if short <= 0 else UiKit.COP_RED, null, []])
		var ups := PackedStringArray()
		for level in range(1, Car.UPGRADES.size() + 1):
			var c := Game.upgrade_cost(i, level)
			if c > 0:
				ups.append(UiKit.money(c))
		lines.append(["Upgrades", " / ".join(ups) if not ups.is_empty() else "None to fit", UiKit.INK, null, []])
	var y := r.position.y + 28
	var vx := 96.0
	for l in lines:
		draw_string(UiKit.font("body"), Vector2(0, y), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.INK_DIM)
		var vx2 := vx
		if l[3] is int:
			_pips(self, Vector2(vx, y - 9), l[3], true)
			vx2 += 56
		var val: String = l[1].to_upper()
		draw_string(UiKit.font("display", 0, true), Vector2(vx2, y + 1), val, HORIZONTAL_ALIGNMENT_LEFT,
			r.size.x * 0.58 - vx2, UiKit.fit("display", val, r.size.x * 0.58 - vx2, 17, 12), l[2])
		if not l[4].is_empty():
			_draw_button(l[4], r.end.x, y)
		y += 27
	if _message != "":
		draw_string(UiKit.font("body_bold"), Vector2(0, r.end.y - 4), _message, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 14,
			Color(_message_col, clampf(_message_t * 2.0, 0.0, 1.0)))


## A text button, right-aligned to `right` on baseline `y`: its key and its action, lit and
## underlined under the pointer, faint when it can't be done.
func _draw_button(b: Array, right: float, y: float) -> void:
	var label: String = b[1]
	var bw := UiKit.key_width(b[0], 12) + UiKit.text_width("cond", label, 14, 1) + 28
	var br := Rect2(right - bw, y - 20, bw, 28)
	var hot: bool = _buttons.size() == _hover_btn and b[3]
	var ink := UiKit.ACCENT if hot else (UiKit.INK if b[3] else UiKit.INK_FAINT)
	var kx := br.position.x + 8
	var kw := UiKit.draw_key(self, Vector2(kx, br.get_center().y), b[0], 12, ink)
	draw_string(UiKit.font("cond", 1), Vector2(kx + kw + 8, br.get_center().y + 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
	if hot:
		draw_rect(Rect2(kx + kw + 8, br.end.y - 4, br.end.x - kx - kw - 8, 2), UiKit.ACCENT)
	_buttons.append([br, b[2], b[3]])


# ------------------------------------------------------------------ the makers' badges

## NFS3's wordmark for maker `b` (fedata/art/logos.qfs: two sheets of them, one under
## another), silvered; null where it has none.
func _logo(b: String) -> Texture2D:
	if not _logos_read:
		_logos_read = true
		_read_logos()
	return _logos.get(b)


func _read_logos() -> void:
	if Game.data_root == "":
		return
	var fsh := Fsh.load_file(Game.find_ci(Game.data_root, "fedata/art/logos.qfs"))
	if fsh == null:
		return
	for s in mini(fsh.images.size(), LOGO_SHEETS.size()):
		var img: Image = fsh.images[s].duplicate()
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		# The badges are the bands of rows with anything in them.
		var bands := []
		var start := -1
		for y in img.get_height() + 1:
			var any := false
			if y < img.get_height():
				for x in range(0, w, 2):
					if img.get_pixel(x, y).a > 0.06:
						any = true
						break
			if any and start < 0:
				start = y
			elif not any and start >= 0:
				bands.append(Vector2i(start, y))
				start = -1
		if bands.size() != LOGO_SHEETS[s].size():
			continue
		for k in bands.size():
			var band: Vector2i = bands[k]
			var x0 := w
			var x1 := 0
			for y in range(band.x, band.y):
				for x in w:
					if img.get_pixel(x, y).a > 0.06:
						x0 = mini(x0, x)
						x1 = maxi(x1, x)
			var part := img.get_region(Rect2i(x0, band.x, x1 - x0 + 1, band.y - band.x))
			# Chrome-blue to silver: the brightest channel as the grey.
			for y in part.get_height():
				for x in part.get_width():
					var c := part.get_pixel(x, y)
					var v := clampf(maxf(c.r, maxf(c.g, c.b)) * 1.15, 0.0, 1.0)
					part.set_pixel(x, y, Color(v, v, v, c.a))
			_logos[LOGO_SHEETS[s][k]] = ImageTexture.create_from_image(part)
