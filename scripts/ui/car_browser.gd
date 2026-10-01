class_name CarBrowser
extends BrowserBase
## Every car as a table to compare them by: its class, name and game, then its power, top
## speed, 0-100 and weight in columns. A click on a column's heading sorts by it (again: the
## other way); by class the table is grouped by class, by name by make. Filtered by class,
## game and drive, searched by typing (name, make, class, game, drive). The showroom beside it
## shows the car in focus; ←→ change its paint and Shift+←→ its trim (the menu does those),
## Ctrl+←→ steps the sort.

signal paint_step(dir: int)
signal trim_step(dir: int)

const ROW_H := 40.0
const CLASS_NAMES := ["CLASS A", "CLASS B", "CLASS C", "BONUS"]
const SORT_CLASS := 0
const SORT_NAME := 1
## The figures' columns: [heading, width]. Sorts 2.. are these.
const COLS := [["POWER", 52.0], ["TOP", 58.0], ["0-100", 50.0], ["WEIGHT", 62.0]]

var sort := SORT_CLASS
var desc := false             # the sort the other way round
## (car index) -> bool: only the cars it passes are listed (a one-make cup's). Unset: all.
var allow: Callable
var games: TabStrip           # only with more than one game's cars present
var drives: TabStrip
var _games: Array[int] = []   # the games whose cars there are (Game.car_game), in the chips' order

var _groups := {}             # car index -> 0..3 class, 4 police
var _power := {}              # car index -> bhp (-1 unknown)
var _top := {}                # -> km/h
var _t100 := {}               # -> s, the game's own (or the maker's 0-60 where it has none; -1 neither)
var _t100_claimed := {}       # -> true where that's the maker's
var _kg := {}
var _drive := {}              # -> "RWD", "FWD", "AWD" or ""
var _make := {}
var _col_x: Array[float] = [] # the columns' right edges, list space
var _head_hover := -1         # the heading under the pointer: -2 name, 0.. a figure


func _init() -> void:
	super()
	title = "CARS"
	noun = "cars"
	head_h = 200.0
	for i in Game.cars.size():
		var spec := Game.car_spec(i)
		var info: Dictionary = spec.info if "info" in spec else {}
		_groups[i] = 4 if Game.is_pursuit_car(i) else Game.car_class(i)
		_top[i] = spec.carp_value(15, 70.0) * 3.6
		_kg[i] = spec.carp_value(2, 1400.0)
		var t := CarStats.zero_to_100(spec)
		_t100_claimed[i] = t <= 0.0
		if t <= 0.0:
			var z := str(info.get("zero_60", "")).to_lower().replace("sec", "").replace("s", "").strip_edges()
			t = z.to_float() if z.is_valid_float() else -1.0
		_t100[i] = t
		var power := str(info.get("power", "")).to_lower()
		var bhp := power.split("bhp")[0].strip_edges() if power.contains("bhp") else ""
		_power[i] = bhp.to_int() if bhp.is_valid_int() else -1
		_drive[i] = ""
		if "carp" in spec and spec.carp.has(16):
			var fd: float = spec.carp_value(16)
			_drive[i] = "FWD" if fd >= 1.0 else ("AWD" if fd > 0.0 else "RWD")
		var make := str(info.get("make", "")).strip_edges()
		var name := str(Game.cars[i].name)
		_make[i] = make if make != "" and name.to_lower().begins_with(make.to_lower()) else name.split(" ")[0]
	total = Game.cars.size()
	var chips := PackedStringArray(["ALL", "CLASS A", "CLASS B", "CLASS C"])
	if _groups.values().has(4):
		chips.append("POLICE")
	if _groups.values().has(3):
		chips.append("BONUS")
	filters.set_items(chips, 0)
	for i in Game.cars.size():
		if Game.car_game(i) not in _games:
			_games.append(Game.car_game(i))
	_games.sort()
	if _games.size() > 1:
		var game_chips := PackedStringArray(["ALL"])
		for g in _games:
			game_chips.append(Game.GAME_NAMES[g])
		games = TabStrip.new(game_chips, TabStrip.Style.CHIPS)
		games.changed.connect(func(_i): _rebuild())
		add_child(games)
	drives = TabStrip.new(PackedStringArray(["ANY", "RWD", "FWD", "AWD"]), TabStrip.Style.CHIPS)
	drives.changed.connect(func(_i): _rebuild())
	add_child(drives)


func _layout_head() -> void:
	if games:
		games.position = Vector2(-8, 134)
	drives.position = Vector2(size.x - drives.custom_minimum_size.x + 8, 134)


func hints() -> Array:
	return [["↑↓", "BROWSE"], ["←→", "PAINT"], ["SHIFT ←→", "TRIM"], ["TAB", "CLASS"]]


func _side_step(dir: int, shift := false, ctrl := false) -> void:
	if ctrl:
		sort = posmod(sort + dir, 2 + COLS.size())
		desc = false
		_rebuild()
	elif shift:
		trim_step.emit(dir)
	else:
		paint_step.emit(dir)


func _filter_group() -> int:
	match filters.items[filters.index]:
		"CLASS A": return 0
		"CLASS B": return 1
		"CLASS C": return 2
		"BONUS": return 3
		"POLICE": return 4
	return -1


## The figure a car sorts by in column `k` (bigger first, but for 0-100 and weight).
func _figure(i: int, k: int) -> float:
	match k:
		0: return _power[i]
		1: return _top[i]
		2: return _t100[i]
	return _kg[i]


func _build_entries() -> Array[Dictionary]:
	var group := _filter_group()
	var game := games.index if games else 0
	var drive: String = drives.items[drives.index] if drives.index > 0 else ""
	var ids: Array[int] = []
	for i in Game.cars.size():
		if group >= 0 and _groups[i] != group:
			continue
		if game > 0 and Game.car_game(i) != _games[game - 1]:
			continue
		if drive != "" and _drive[i] != drive:
			continue
		if allow.is_valid() and not allow.call(i):
			continue
		var g: int = _groups[i]
		var hay := "%s %s %s %s %s" % [Game.cars[i].name, _make[i], "police pursuit" if g == 4 else CLASS_NAMES[g],
			["nfs3 hot pursuit", "high stakes hs nfs4", "porsche unleashed pu nfs5", "hot pursuit 2 hp2 nfs6"][Game.car_game(i)], _drive[i]]
		if query != "" and not _matches(hay.to_lower()):
			continue
		ids.append(i)
	var name_of := func(i: int) -> String: return str(Game.cars[i].name).to_lower()
	match sort:
		SORT_CLASS:
			ids.sort_custom(func(a: int, b: int) -> bool:
				return _groups[a] < _groups[b] if _groups[a] != _groups[b] else name_of.call(a) < name_of.call(b))
		SORT_NAME:
			ids.sort_custom(func(a: int, b: int) -> bool: return name_of.call(a) < name_of.call(b))
		_:
			var k := sort - 2
			# Less is better for the 0-100 and the weight; unknown figures always last.
			var up := k >= 2
			ids.sort_custom(func(a: int, b: int) -> bool:
				var fa := _figure(a, k)
				var fb := _figure(b, k)
				if (fa < 0.0) != (fb < 0.0):
					return fb < 0.0
				if is_equal_approx(fa, fb):
					return name_of.call(a) < name_of.call(b)
				return (fa < fb) == up)
	if desc:
		ids.reverse()
	var out: Array[Dictionary] = []
	var last := ""
	for i in ids:
		var head := ""
		if sort == SORT_CLASS:
			head = "POLICE" if _groups[i] == 4 else CLASS_NAMES[_groups[i]]
		elif sort == SORT_NAME:
			head = str(_make[i]).to_upper()
		if head != "" and head != last:
			last = head
			out.append({"item": -1, "text": head})
		out.append({"item": i, "text": Game.cars[i].name})
	return out


func _layout_entries(w: float) -> float:
	_col_x.clear()
	var x := w - 16
	for k in range(COLS.size() - 1, -1, -1):
		_col_x.push_front(x)
		x -= COLS[k][1]
	var y := 4.0
	for e in entries:
		var h := 32.0 if e.item < 0 else ROW_H
		e.rect = Rect2(0, y, w - 14, h)
		y += h
	return y + 8.0


func _col_text(i: int, k: int) -> String:
	var v := _figure(i, k)
	if v < 0.0:
		return "—"
	match k:
		0: return "%d" % roundi(v)
		1: return "%d" % roundi(v if Game.units_kmh else v / 1.609)
		2: return "%.1f" % v
	return "%d" % roundi(v if Game.units_kmh else v * 2.2046)


func _draw_entry(ci: CanvasItem, e: Dictionary, r: Rect2, focused: bool, hovered: bool) -> void:
	var i: int = e.item
	if focused:
		UiKit.glow(ci, r, 1.0)
	elif hovered:
		UiKit.glow(ci, r, 0.4, UiKit.INK, false)
	ci.draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), Color(1, 1, 1, 0.05))
	var g: int = _groups[i]
	var cy := r.get_center().y
	var br := Rect2(r.position.x + 12, cy - 10, 22, 20)
	UiKit.box(ci, br, Color(UiKit.COP_BLUE if g == 4 else UiKit.ACCENT, 0.95 if focused else 0.6), 3)
	ci.draw_string(UiKit.font("display"), Vector2(br.position.x, cy + 7), "P" if g == 4 else "ABCX"[g],
		HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 16, UiKit.BG)
	# The figures, the one sorted by lit.
	var ff := UiKit.font("cond", 1, true)
	for k in COLS.size():
		var lit := sort == k + 2
		var col := UiKit.INK if lit or focused else UiKit.INK_DIM
		if k == 2 and _t100_claimed[i]:
			col = Color(col, col.a * 0.6)
		ci.draw_string(ff, Vector2(_col_x[k] - COLS[k][1], cy + 5), _col_text(i, k), HORIZONTAL_ALIGNMENT_RIGHT,
			COLS[k][1] - 6, 15 if lit else 14, col)
	# The name, then small tags.
	var x := br.end.x + 12
	var max_w := _col_x[0] - COLS[0][1] - 12 - x
	var nf := UiKit.font("display")
	var name := str(Game.cars[i].name).to_upper()
	var fs := UiKit.fit("display", name, max_w, 19, 14)
	ci.draw_string(nf, Vector2(x, cy + 7), name, HORIZONTAL_ALIGNMENT_LEFT, max_w, fs,
		UiKit.INK if focused or hovered else Color(UiKit.INK, 0.85))
	x += minf(nf.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, max_w) + 8
	var tf := UiKit.font("cond", 1)
	var game_tag: Array = [[], [["HS", UiKit.INK_DIM]], [["PU", UiKit.INK_DIM]]][Game.car_game(i)]
	for tag in game_tag + ([["IN USE", UiKit.ACCENT]] if i == picked else []):
		var tw := tf.get_string_size(tag[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12
		if x + tw > _col_x[0] - COLS[0][1] - 6:
			break
		UiKit.box(ci, Rect2(x, cy - 9, tw, 18), Color(0, 0, 0, 0), 9, Color(tag[1], 0.6))
		ci.draw_string(tf, Vector2(x + 6, cy + 4), tag[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tag[1])
		x += tw + 6


# ------------------------------------------------------------------ the headings

## The headings' rects (panel space): [-2 name, 0.. figures].
func _head_rects() -> Dictionary:
	var out := {}
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


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := _head_at(e.position)
		if h != _head_hover:
			_head_hover = h
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _head_at(e.position) > -3:
		var h := _head_at(e.position)
		# The name's heading goes class, name; a figure's sorts by it; again: the other way.
		var s := (SORT_NAME if sort == SORT_CLASS else SORT_CLASS) if h == -2 else h + 2
		if h != -2 and s == sort:
			desc = not desc
		else:
			sort = s
			desc = false
		_rebuild()
		accept_event()
		return
	super(e)


func _head_hot() -> bool:
	return _head_hover > -3


func _draw() -> void:
	super()
	var rects := _head_rects()
	var f := UiKit.font("cond", 1)
	var units := ["BHP", "KM/H" if Game.units_kmh else "MPH", "S", "KG" if Game.units_kmh else "LB"]
	for k in rects:
		var r: Rect2 = rects[k]
		var lit: bool = (k == -2 and sort <= SORT_NAME) or sort == k + 2
		var hot: bool = k == _head_hover
		var col := UiKit.ACCENT if lit else (UiKit.INK if hot else UiKit.INK_DIM)
		var label: String = ("BY CLASS" if sort == SORT_CLASS else "BY NAME") if k == -2 else COLS[k][0]
		var align := HORIZONTAL_ALIGNMENT_LEFT if k == -2 else HORIZONTAL_ALIGNMENT_RIGHT
		var x := r.position.x + (12.0 if k == -2 else 0.0)
		var w := r.size.x - (12.0 if k == -2 else 6.0)
		draw_string(f, Vector2(x, r.position.y + 11), label, align, w, 12, col)
		if k >= 0:
			draw_string(f, Vector2(x, r.position.y + 23), units[k], align, w, 10, Color(col, col.a * 0.7))
		if lit and k >= 0:
			var ax: float = r.end.x - 6 - UiKit.text_width("cond", label, 12, 1) - 9
			UiKit.chevron(self, Vector2(ax, r.position.y + 7), 2 if not desc else -2, UiKit.ACCENT, 3.0, 1.5)
	draw_line(Vector2(0, head_h - 1), Vector2(size.x, head_h - 1), UiKit.LINE, 1.0)
