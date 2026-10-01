class_name MapBrowser
extends BrowserBase
## A picker that's one world map with its items pinned where they belong. The map glides to
## frame the region of the item in focus (the chips pick a region, Tab steps them); a search
## frames what matches. A place with several items has one pin and a chip for each. Labels go
## beside their pins where they overlap nothing, further out on a leader where it's crowded.
## Subclasses give the places and say where each item is (the hooks below).

const NAME_SIZE := 17
const CHIP_SIZE := 13
const CHIP_H := 21.0
const SIDE_GAP := 28.0

## The regions the chips frame: [name, [south, west, north, east] in degrees]; the first is
## the whole world (a click there flies to an item's region, a second picks it).
var regions: Array = []
## Where the map starts down this control (the header's above it: labels keep out).
var map_top := 132.0
## Width kept clear at the right (a card there), the gap before it included.
var side_w := 0.0
## The region chips' row.
var chips_y := 100.0

var _map: WorldMap
## key -> {name, where, pos (map units), region, entries (indices into `entries`), multi,
## off (the label's top-left from the pin, px), size, shown (the label found room)}
var _places := {}
var _place_order: Array[String] = []


func _init() -> void:
	super()
	grid = true
	_map = WorldMap.new()
	_map.show_behind_parent = true
	_map.moved.connect(_on_map_moved)
	add_child(_map)
	move_child(_map, 0)
	# The chips pick a region (not a filter): the map flies there and the focus with it.
	for c in filters.changed.get_connections():
		filters.changed.disconnect(c.callable)
	filters.changed.connect(_on_region)
	move_child(filters, -1)


func set_regions(r: Array) -> void:
	regions = r
	filters.set_items(PackedStringArray(r.map(func(x: Array) -> String: return x[0])), mini(1, r.size() - 1))


# ------------------------------------------------------------------ for subclasses

## The places: key -> [name, where, latitude, longitude, region].
func _place_table() -> Dictionary:
	return {}


## Every item there is (searched or not).
func _item_ids() -> Array:
	return []


## An item's place key and its chip there ("" where the place has only it).
func _item_place(_item: int) -> Array:
	return ["", ""]


func _item_text(_item: int) -> String:
	return ""


## The small tag after a lone item's name ("HS", "6 CARS").
func _item_tag(_item: int) -> String:
	return ""


## What a search looks through (lower case).
func _item_hay(_item: int) -> String:
	return ""


## Ringed on the map: the item in use.
func _item_marked(item: int) -> bool:
	return item == picked


## A pin drawn faint: somewhere that isn't a real place.
func _place_faint(_key: String) -> bool:
	return false


# ------------------------------------------------------------------ open / layout

func _region_of_item(item: int) -> int:
	return _place_table()[_item_place(item)[0]][4] if item >= 0 else 0


func open(item: int) -> void:
	filters.set_items(filters.items, _region_of_item(item))
	# Fly in from the whole world.
	_layout()
	_map.fit(_box(regions[0][1]), true, Vector2(40, 20))
	super(item)


func _layout() -> void:
	super()
	filters.position = Vector2(-8, chips_y)
	_list.position = Vector2.ZERO
	_list.size = size
	# The map runs out past the frame's edges and fades there; pins are fitted into the part
	# left of the side, under the header.
	_map.position = Vector2(-40, -24)
	_map.size = size + Vector2(80, 48)
	_map.frame = Rect2(Vector2(40, 24 + map_top), Vector2(size.x - side_w, size.y - map_top))
	(_map.material as ShaderMaterial).set_shader_parameter("top_fade", 60.0)
	_map._push()
	if visible:
		_reframe(true)


func _build_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var table := _place_table()
	# Grouped by place, places in the table's order, so chips come in theirs.
	var by_place := {}
	var count := {}   # items at each place in all (not just matching): a place of several shows chips
	for i in _item_ids():
		var pl := _item_place(i)
		count[pl[0]] = count.get(pl[0], 0) + 1
		var p: Array = table[pl[0]]
		if query != "" and not _matches(("%s %s %s" % [_item_hay(i), p[0], p[1]]).to_lower()):
			continue
		if not by_place.has(pl[0]):
			by_place[pl[0]] = []
		by_place[pl[0]].append({"item": i, "text": _item_text(i), "place": pl[0], "chip": pl[1], "rect": Rect2()})
	_places.clear()
	_place_order.clear()
	for key in table:
		if not by_place.has(key):
			continue
		var p: Array = table[key]
		var idx: Array[int] = []
		for e in by_place[key]:
			idx.append(out.size())
			out.append(e)
		_places[key] = {"name": p[0], "where": p[1], "pos": WorldMap.project(p[2], p[3]), "region": p[4],
			"entries": idx, "multi": count[key] > 1, "off": Vector2(12, -10), "size": Vector2.ZERO, "shown": false}
		_place_order.append(key)
	return out


func _layout_entries(_w: float) -> float:
	return _list.size.y


func _rebuild(keep := -2) -> void:
	super(keep)
	_reframe()


## Fits the map to the region (or to what the search found) and lays the labels out for it.
func _reframe(instant := false) -> void:
	if not visible:
		return
	# The chip follows the item in focus (but stays on the world while that's the view).
	if focused_item() >= 0 and (filters.index != 0 or query != "") and _region_of_item(focused_item()) != filters.index:
		filters.set_items(filters.items, _region_of_item(focused_item()))
	if query != "" and not entries.is_empty():
		var r := Rect2(_places[_place_order[0]].pos, Vector2.ZERO)
		for key in _place_order:
			r = r.expand(_places[key].pos)
		# Room round a lone match: about a country's worth.
		r = r.grow(0.05)
		_map.fit(r, instant, Vector2(110, 60), 1600.0)
	else:
		_map.fit(_box(regions[filters.index][1]), instant, Vector2(40, 16))
	_layout_labels()
	_update_rects()
	_list.queue_redraw()


static func _box(b: Array) -> Rect2:
	var a := WorldMap.project(b[2], b[1])
	return Rect2(a, Vector2.ZERO).expand(WorldMap.project(b[0], b[3]))


## Where a place's pin is in the list's pixels, for the camera now (or where it's heading).
func _pin(key: String, target := false) -> Vector2:
	return _map.to_px(_places[key].pos, target) + _map.position


func _label_size(key: String) -> Vector2:
	var pl: Dictionary = _places[key]
	var nf := UiKit.font("display")
	if not pl.multi:
		var e: Dictionary = entries[pl.entries[0]]
		var tag := _item_tag(e.item)
		return Vector2(nf.get_string_size(e.text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x + 8
			+ UiKit.text_width("cond", tag, 11, 1) + 10, 24)
	var w := nf.get_string_size(pl.name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x + 10
	var cw := 0.0
	for k in pl.entries:
		cw += _chip_w(entries[k].chip) + 4
	return Vector2(maxf(w, cw), 24 + CHIP_H + 2)


func _chip_w(text: String) -> float:
	return UiKit.text_width("cond", text, CHIP_SIZE, 1) + 14


## The part of this control the labels may use.
func _label_area() -> Rect2:
	return Rect2(4, 4, size.x - side_w + 12.0 if side_w > 0.0 else size.x - 8.0, size.y - 8)


## Puts each place's label beside its pin where it overlaps nothing (no other label, pin,
## the header or the side), trying close round it first and then further out on a leader.
## Laid out for where the camera is heading, so they don't shuffle while it moves.
func _layout_labels() -> void:
	var area := _label_area()
	var blocked: Array[Rect2] = [Rect2(0, 0, (head_w if head_w > 0.0 else size.x) + 20, map_top),
		Rect2(area.end.x, 0, size.x, size.y)]
	# Over the whole world only labels that fit close by: a long leader there loses its pin.
	var radii: Array = [10.0, 26.0] if filters.index == 0 and query == "" else [10.0, 26.0, 46.0, 72.0, 104.0, 140.0]
	var pins := {}
	for key in _place_order:
		pins[key] = _pin(key, true)
	for key in _place_order:
		blocked.append(Rect2(pins[key] - Vector2(6, 6), Vector2(12, 12)))
	# Places of several first (bigger labels), then west to east.
	var order := _place_order.duplicate()
	order.sort_custom(func(a: String, b: String) -> bool:
		if _places[a].multi != _places[b].multi:
			return _places[a].multi
		return pins[a].x < pins[b].x)
	for key in order:
		var pl: Dictionary = _places[key]
		var sz := _label_size(key)
		pl.size = sz
		pl.shown = false
		var p: Vector2 = pins[key]
		pl.off = Vector2(12, -12)
		if not area.has_point(p):
			continue
		# The first spot that's clear; failing that, the one overlapping least, kept for when
		# it's in focus (it's drawn over the rest then).
		var least := INF
		for c in _candidates(sz, radii):
			var r := Rect2(p + c, sz)
			if not area.encloses(r):
				continue
			var over := 0.0
			for b in blocked:
				if b.intersects(r.grow(2)) and not b.has_point(p):
					over += b.intersection(r.grow(2)).get_area() + 1.0
			if over == 0.0:
				pl.off = c
				pl.shown = true
				blocked.append(r)
				break
			if over < least:
				least = over
				pl.off = c


## Label offsets from a pin to try, nearest first: right, left, above, below and the corners.
static func _candidates(sz: Vector2, radii: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for d: float in radii:
		var dd: float = d * 0.75
		out.append_array([Vector2(d, -12), Vector2(-d - sz.x, -12), Vector2(dd, -dd - sz.y), Vector2(dd, dd),
			Vector2(-dd - sz.x, -dd - sz.y), Vector2(-dd - sz.x, dd), Vector2(-sz.x * 0.5, -d - sz.y), Vector2(-sz.x * 0.5, d)])
	return out


## Each entry's rect in the list (for the pointer, and for moving with the keys): its chip, or
## its label and pin; just the pin while its label is hidden.
func _update_rects(target := false) -> void:
	for key in _place_order:
		var pl: Dictionary = _places[key]
		var p := _pin(key, target)
		var pin := Rect2(p - Vector2(9, 9), Vector2(18, 18))
		for j in pl.entries.size():
			var e: Dictionary = entries[pl.entries[j]]
			if not pl.shown:
				# Chips at one pin: a hair apart, in order, so ←→ steps through them.
				e.rect = Rect2(pin.position + Vector2(j * 0.5, 0), pin.size)
			elif pl.multi:
				e.rect = _chip_rect(pl, p + pl.off, j)
			else:
				e.rect = Rect2(p + pl.off, pl.size).merge(pin)


## Chip `j` of a place whose label's top-left is at `at`.
func _chip_rect(pl: Dictionary, at: Vector2, j: int) -> Rect2:
	var x := at.x
	for k in j:
		x += _chip_w(entries[pl.entries[k]].chip) + 4
	return Rect2(x, at.y + 24, _chip_w(entries[pl.entries[j]].chip), CHIP_H)


func _on_map_moved() -> void:
	_update_rects()
	_list.queue_redraw()


# ------------------------------------------------------------------ moving

func _on_region(i: int) -> void:
	if query == "" and i != 0 and _region_of_item(focused_item()) != i:
		# Into the region: the item in use if it's there, else the one nearest its middle.
		var c: Vector2 = _box(regions[i][1]).get_center()
		var best := -1
		for k in entries.size():
			if _places[entries[k].place].region != i:
				continue
			if entries[k].item == picked:
				best = k
				break
			if best < 0 or _places[entries[k].place].pos.distance_to(c) < _places[entries[best].place].pos.distance_to(c):
				best = k
		if best >= 0:
			focus = best
			current = focused_item()
			focus_changed.emit(current)
	_reframe()


func _set_focus(k: int) -> void:
	if k < 0 or k == focus:
		return
	super(k)
	if _region_of_item(focused_item()) != filters.index:
		filters.set_items(filters.items, _region_of_item(focused_item()))
		if query == "":
			_reframe()


func _move_vertical(dir: int) -> void:
	_move(Vector2(0, dir))


func _move_horizontal(dir: int) -> void:
	_move(Vector2(dir, 0))


## To the nearest entry that way, as the map will stand: straight on counts for more than
## off to the side. Chips of one place step along their row first.
func _move(v: Vector2) -> void:
	if focus < 0:
		_set_focus(_next_item(-1, 1))
		return
	_update_rects(true)
	var from: Vector2 = entries[focus].rect.get_center()
	var best := -1
	var best_s := INF
	for k in entries.size():
		if k == focus:
			continue
		var d: Vector2 = entries[k].rect.get_center() - from
		var along := d.dot(v)
		if along < 0.25:
			continue
		var side := absf(d.cross(v))
		# Within one place's row of chips, the next chip wins.
		if entries[k].place == entries[focus].place and side < 4.0:
			along *= 0.01
		var s := along + side * 2.5
		if s < best_s:
			best_s = s
			best = k
	_update_rects()
	_set_focus(best)


func _on_list_input(e: InputEvent) -> void:
	# Over the whole world, a click flies to the region (a second one picks).
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and filters.index == 0 and query == "":
		var k := _entry_at(e.position)
		if k >= 0 and _places[entries[k].place].region != 0:
			focus = -1
			_set_focus(k)
			_list.accept_event()
			return
	super(e)


func _process(dt: float) -> void:
	super(dt)
	if visible:
		_list.queue_redraw()   # the pulse round the focused pin


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	# Darken the map under the title and search, so they read over it.
	var w := head_w + 120
	var a := Color(0.035, 0.038, 0.05, 0.85)
	var b := Color(a, 0.0)
	draw_polygon(PackedVector2Array([Vector2(-40, -24), Vector2(w, -24), Vector2(w, map_top), Vector2(-40, map_top)]),
		PackedColorArray([a, b, b, a]))
	super()


func _draw_list() -> void:
	var l := _list
	if entries.is_empty():
		var f := UiKit.font("display")
		var msg := "NO %s MATCH \"%s\"" % [noun.to_upper(), query.to_upper()] if query != "" else "NOTHING HERE"
		l.draw_string(f, Vector2(0, map_top + 60), msg, HORIZONTAL_ALIGNMENT_LEFT, size.x - side_w, 24, UiKit.INK_DIM)
		l.draw_string(UiKit.font("body"), Vector2(0, map_top + 88), "Backspace to edit, Esc to clear.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiKit.INK_DIM)
		return
	var fk: String = entries[focus].place if focus >= 0 and focus < entries.size() else ""
	var hk: String = entries[_hover].place if _hover >= 0 and _hover < entries.size() else ""
	# Leaders, then pins, then labels; the focused place's last, over the rest.
	for key in _place_order:
		var pl: Dictionary = _places[key]
		if pl.shown and key != fk:
			_draw_leader(l, _pin(key), Rect2(_pin(key) + pl.off, pl.size), Color(1, 1, 1, 0.22))
	for key in _place_order:
		_draw_pin(l, key, key == fk)
	for key in _place_order:
		if key != fk and (_places[key].shown or key == hk):
			_draw_label(l, key, false)
	if fk != "":
		var pl: Dictionary = _places[fk]
		_draw_leader(l, _pin(fk), Rect2(_pin(fk) + pl.off, pl.size), Color(UiKit.ACCENT, 0.7))
		_draw_label(l, fk, true)


func _draw_leader(ci: CanvasItem, p: Vector2, r: Rect2, col: Color) -> void:
	if r.grow(4).has_point(p):
		return
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y + 4, r.end.y - 4))
	if (q - p).length() > 9.0:
		ci.draw_line(p + (q - p).normalized() * 6.0, q, col, 1.0, true)


func _draw_pin(ci: CanvasItem, key: String, focused: bool) -> void:
	var p := _pin(key)
	var pl: Dictionary = _places[key]
	var marked := false
	for k in pl.entries:
		marked = marked or _item_marked(entries[k].item)
	if focused:
		var t := fmod(_time * 0.9, 1.0)
		ci.draw_arc(p, 6.0 + t * 16.0, 0, TAU, 32, Color(UiKit.ACCENT, 0.7 * (1.0 - t)), 1.5, true)
		ci.draw_circle(p, 7.0, Color(0, 0, 0, 0.6))
		ci.draw_circle(p, 5.0, UiKit.ACCENT)
	else:
		ci.draw_circle(p, 5.0, Color(0, 0, 0, 0.55))
		ci.draw_circle(p, 3.2, UiKit.INK_DIM if _place_faint(key) else Color(1, 1, 1, 0.9))
	if marked:
		ci.draw_arc(p, 9.5, 0, TAU, 32, UiKit.ACCENT, 1.5, true)


func _draw_label(ci: CanvasItem, key: String, focused: bool) -> void:
	var pl: Dictionary = _places[key]
	var p := _pin(key)
	var r := Rect2(p + pl.off, pl.size)
	var nf := UiKit.font("display")
	if not pl.multi:
		var k: int = pl.entries[0]
		var e: Dictionary = entries[k]
		var name: String = e.text.to_upper()
		var nw := nf.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x
		var hot := k == _hover
		if focused or not pl.shown:
			UiKit.draw_slant(ci, Rect2(r.position - Vector2(2, 0), Vector2(r.size.x + 4, 22)),
				UiKit.ACCENT if focused else Color(0.05, 0.055, 0.07, 0.92), 0.18)
		var ink := UiKit.BG if focused else (UiKit.INK if hot or not pl.shown else Color(0.92, 0.93, 0.96, 0.85))
		ci.draw_string(nf, r.position + Vector2(4, 17), name, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, ink)
		ci.draw_string(UiKit.font("cond", 1), r.position + Vector2(nw + 11, 16), _item_tag(e.item), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(UiKit.BG, 0.7) if focused else UiKit.INK_FAINT)
		return
	# A place of several: its name, and a chip for each of its items.
	if not pl.shown or focused:
		UiKit.box(ci, r.grow(4), Color(0.05, 0.055, 0.07, 0.88), 4)
	ci.draw_string(nf, r.position + Vector2(2, 17), pl.name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE,
		UiKit.INK if focused else Color(0.92, 0.93, 0.96, 0.85))
	var cf := UiKit.font("cond", 1)
	for j in pl.entries.size():
		var k: int = pl.entries[j]
		var e: Dictionary = entries[k]
		var cr := _chip_rect(pl, r.position, j)
		var on := k == focus
		var fill := UiKit.ACCENT if on else (Color(1, 1, 1, 0.16) if k == _hover else Color(0.05, 0.055, 0.07, 0.75))
		var border := UiKit.ACCENT if _item_marked(e.item) else Color(1, 1, 1, 0.28)
		UiKit.box(ci, cr, fill, 3, border, 1)
		ci.draw_string(cf, Vector2(cr.position.x, cr.position.y + 15), e.chip, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, CHIP_SIZE,
			UiKit.BG if on else UiKit.INK)
