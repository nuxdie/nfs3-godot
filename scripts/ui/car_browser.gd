class_name CarBrowser
extends BrowserBase
## Every car in one list: filtered by class and game, searched by typing, sorted by class,
## name or any of the four ratings. The showroom beside it shows whichever car has focus.

const SORTS := ["CLASS", "NAME", "TOP SPEED", "ACCELERATION", "HANDLING", "BRAKING"]
const ROW_H := 44.0
const CLASS_NAMES := ["CLASS A", "CLASS B", "CLASS C", "BONUS"]

var sort := 0
## (car index) -> bool: only the cars it passes are listed (a one-make cup's). Unset: all.
var allow: Callable
var games: TabStrip           # only with both games' cars present

var _ratings := {}            # car index -> [speed, accel, handling, braking] 0..1
var _top := {}                # car index -> km/h
var _t100 := {}               # car index -> s (or -1)
var _groups := {}             # car index -> 0..3 class, 4 police
var _sort_rect := Rect2()
var _sort_hover := 0          # -1 left half, 1 right half


func _init() -> void:
	super()
	title = "CARS"
	noun = "cars"
	head_h = 194.0
	for i in Game.cars.size():
		var spec := Game.car_spec(i)
		_ratings[i] = CarStats.ratings(spec)
		_top[i] = spec.carp_value(15, 70.0) * 3.6
		_t100[i] = CarStats.zero_to_100(spec)
		_groups[i] = 4 if Game.is_pursuit_car(i) else Game.car_class(i)
	total = Game.cars.size()
	var chips := PackedStringArray(["ALL", "CLASS A", "CLASS B", "CLASS C"])
	if _groups.values().has(4):
		chips.append("POLICE")
	if _groups.values().has(3):
		chips.append("BONUS")
	filters.set_items(chips, 0)
	var has_hs := false
	var has_nfs3 := false
	for i in Game.cars.size():
		has_hs = has_hs or Game.is_hs_car(i)
		has_nfs3 = has_nfs3 or not Game.is_hs_car(i)
	if has_hs and has_nfs3:
		games = TabStrip.new(PackedStringArray(["BOTH GAMES", "NFS III", "HIGH STAKES"]), TabStrip.Style.CHIPS)
		games.changed.connect(func(_i): _rebuild())
		add_child(games)


func _layout_head() -> void:
	if games:
		games.position = Vector2(PAD, 152)
	_sort_rect = Rect2(size.x - PAD - 200, 152, 200, 28)


func hints() -> Array:
	return [["↑↓", "BROWSE"], ["←→", "SORT"], ["TAB", "CLASS"]]


func _side_step(dir: int) -> void:
	sort = posmod(sort + dir, SORTS.size())
	_rebuild()


func _filter_group() -> int:
	var name := filters.items[filters.index]
	match name:
		"CLASS A": return 0
		"CLASS B": return 1
		"CLASS C": return 2
		"BONUS": return 3
		"POLICE": return 4
	return -1


func _build_entries() -> Array[Dictionary]:
	var group := _filter_group()
	var game := games.index if games else 0
	var ids: Array[int] = []
	for i in Game.cars.size():
		if group >= 0 and _groups[i] != group:
			continue
		if (game == 1 and Game.is_hs_car(i)) or (game == 2 and not Game.is_hs_car(i)):
			continue
		if allow.is_valid() and not allow.call(i):
			continue
		var g: int = _groups[i]
		var hay := "%s %s %s" % [Game.cars[i].name, "police pursuit" if g == 4 else CLASS_NAMES[g],
			"high stakes hs nfs4" if Game.is_hs_car(i) else "nfs3 hot pursuit"]
		if query != "" and not _matches(hay.to_lower()):
			continue
		ids.append(i)
	var name_of := func(i: int) -> String: return str(Game.cars[i].name).to_lower()
	match sort:
		0:
			ids.sort_custom(func(a: int, b: int) -> bool:
				return _groups[a] < _groups[b] if _groups[a] != _groups[b] else name_of.call(a) < name_of.call(b))
		1:
			ids.sort_custom(func(a: int, b: int) -> bool: return name_of.call(a) < name_of.call(b))
		_:
			var s := sort - 2
			ids.sort_custom(func(a: int, b: int) -> bool:
				return _ratings[a][s] > _ratings[b][s] if not is_equal_approx(_ratings[a][s], _ratings[b][s]) \
					else name_of.call(a) < name_of.call(b))
	var out: Array[Dictionary] = []
	var last_group := -1
	for i in ids:
		if sort == 0 and _groups[i] != last_group:
			last_group = _groups[i]
			out.append({"item": -1, "text": "POLICE" if last_group == 4 else CLASS_NAMES[last_group]})
		out.append({"item": i, "text": Game.cars[i].name})
	return out


func _layout_entries(w: float) -> float:
	var y := 4.0
	for e in entries:
		var h := 34.0 if e.item < 0 else ROW_H
		e.rect = Rect2(8, y, w - 22, h)
		y += h
	return y + 8.0


## The number shown against each car: the sorted-by rating, or top speed.
func _readout(i: int) -> String:
	var s := maxi(sort - 2, 0)
	match s:
		1:
			var t: float = _t100[i]
			return ("%.1f S" % t) if t > 0.0 else "—"
		2, 3:
			return "%d" % roundi(_ratings[i][s] * 100.0)
	var top: float = _top[i]
	return "%d KM/H" % roundi(top) if Game.units_kmh else "%d MPH" % roundi(top / 1.609)


func _draw_entry(ci: CanvasItem, e: Dictionary, r: Rect2, focused: bool, hovered: bool) -> void:
	var i: int = e.item
	if focused:
		UiKit.draw_slant(ci, r.grow_individual(0, -2, 0, -2), Color(1, 1, 1, 0.1), 0.1)
		UiKit.draw_slant(ci, Rect2(r.position.x, r.position.y + 2, 4, r.size.y - 4), UiKit.ACCENT, 0.1)
	elif hovered:
		UiKit.draw_slant(ci, r.grow_individual(0, -2, 0, -2), Color(1, 1, 1, 0.05), 0.1)
	var g: int = _groups[i]
	var br := Rect2(r.position.x + 16, r.position.y + 9, 26, 26)
	var bc := UiKit.COP_BLUE if g == 4 else UiKit.ACCENT
	UiKit.draw_slant(ci, br, Color(bc, 0.9 if focused else 0.55), 0.15)
	var letter := "P" if g == 4 else ("ABCX"[g])
	ci.draw_string(UiKit.font("display"), Vector2(br.position.x, br.position.y + 20), letter, HORIZONTAL_ALIGNMENT_CENTER,
		br.size.x, 19, UiKit.BG)
	# Rating bar and its readout at the right.
	var bar_w := 64.0
	var bx := r.end.x - bar_w - 10
	var cy := r.get_center().y
	var s := maxi(sort - 2, 0)
	var v: float = clampf(_ratings[i][s], 0.04, 1.0)
	UiKit.draw_slant(ci, Rect2(bx, cy - 3, bar_w, 6), Color(1, 1, 1, 0.1), 0.5)
	UiKit.draw_slant(ci, Rect2(bx, cy - 3, bar_w * v, 6), UiKit.ACCENT.lerp(UiKit.ACCENT_HOT, v) if focused
		else Color(UiKit.ACCENT, 0.6), 0.5)
	var rf := UiKit.font("cond", 1, true)
	var rtxt := _readout(i)
	ci.draw_string(rf, Vector2(bx - 90, cy + 5), rtxt, HORIZONTAL_ALIGNMENT_RIGHT, 80, 14,
		UiKit.INK if focused else UiKit.INK_DIM)
	# Name, then small tags.
	var x := br.end.x + 14
	var nf := UiKit.font("display")
	var max_w := bx - 100 - x
	var name := str(Game.cars[i].name).to_upper()
	var fs := 21
	while fs > 15 and nf.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		fs -= 1
	ci.draw_string(nf, Vector2(x, cy + 7), name, HORIZONTAL_ALIGNMENT_LEFT, max_w, fs,
		UiKit.INK if focused or hovered else Color(UiKit.INK, 0.8))
	x += minf(nf.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, max_w) + 10
	var tf := UiKit.font("cond", 2)
	for tag in ([["HS", UiKit.INK_DIM]] if Game.is_hs_car(i) else []) + ([["SELECTED", UiKit.ACCENT]] if i == current else []):
		var tw := tf.get_string_size(tag[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 10
		if x + tw > bx - 100:
			break
		var tr := Rect2(x, cy - 8, tw, 17)
		ci.draw_rect(tr, Color(tag[1], 0.5), false, 1.0)
		ci.draw_string(tf, Vector2(x + 5, cy + 4), tag[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tag[1])
		x += tw + 6


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := 0
		if _sort_rect.has_point(e.position):
			h = -1 if e.position.x < _sort_rect.get_center().x - 20 else 1
		if h != _sort_hover:
			_sort_hover = h
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed and _sort_rect.has_point(e.position):
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				_side_step(-1 if e.position.x < _sort_rect.get_center().x - 20 else 1)
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_UP:
				_side_step(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_side_step(1)
		accept_event()
		return
	super(e)


func _head_hot() -> bool:
	return _sort_hover != 0


func _draw() -> void:
	super()
	# Sort: "SORT  ‹ TOP SPEED ›", stepped by clicking either half or ←→.
	var r := _sort_rect
	var f := UiKit.font("cond", 2)
	UiKit.draw_slant(self, r, Color(1, 1, 1, 0.1 if _sort_hover != 0 else 0.06), 0.3)
	draw_string(f, Vector2(r.position.x + 12, r.get_center().y + 5), "SORT", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.INK_DIM)
	var vx := r.position.x + 66
	var vw := r.end.x - 26 - vx
	draw_string(f, Vector2(vx, r.get_center().y + 5), SORTS[sort], HORIZONTAL_ALIGNMENT_CENTER, vw, 13, UiKit.INK)
	for side in [-1, 1]:
		var c := Vector2(vx - 8 if side < 0 else vx + vw + 8, r.get_center().y)
		var col := UiKit.ACCENT if _sort_hover == side else UiKit.INK_DIM
		draw_polyline(PackedVector2Array([c + Vector2(-3 * side, -5), c + Vector2(3 * side, 0), c + Vector2(-3 * side, 5)]),
			col, 2.0, true)
