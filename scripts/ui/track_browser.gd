class_name TrackBrowser
extends BrowserBase
## Every track pinned on one world map, where it's set (the real place, or where the game's
## made-up one would be), whichever game it's from. The map glides to frame the region of the
## track in focus; a search frames what matches. A place with several tracks (Monte Carlo's
## five, a High Stakes remake beside its NFS III original) has one pin and a chip for each.
## The card on the right shows the track in focus: its picture, outline and facts.

const REGIONS := ["WORLD", "NORTH AMERICA", "EUROPE"]
## What each region frames: [south, west, north, east] in degrees.
const REGION_BOX := [[14.0, -127.0, 60.0, 26.0], [17.0, -125.0, 52.5, -65.0], [35.5, -6.5, 58.0, 16.5]]

## Places: [name, where (for the card), latitude, longitude, region].
const PLACES := {
	# NFS III's towns and roads, and High Stakes' takes on them.
	"hometown": ["Hometown", "Pennsylvania, USA", 40.8, -77.8, 1],
	"redrock": ["Redrock Ridge", "Sedona, Arizona, USA", 34.87, -111.76, 1],
	"atlantica": ["Atlantica", "Atlantic coast, Georgia, USA", 31.6, -81.2, 1],
	"rockypass": ["Rocky Pass", "Rocky Mountains, Alberta, Canada", 51.2, -115.6, 1],
	"countrywoods": ["Country Woods", "Wisconsin, USA", 44.5, -89.6, 1],
	"lostcanyons": ["Lost Canyons", "Canyon country, Utah, USA", 37.6, -112.4, 1],
	"aquatica": ["Aquatica", "The Bahamas", 25.05, -77.35, 1],
	"summit": ["The Summit", "Colorado Rockies, USA", 39.6, -106.1, 1],
	"empire": ["Empire City", "New York, USA", 40.75, -73.99, 1],
	# High Stakes' own.
	"celtic": ["Celtic Ruins", "Scottish Highlands", 57.1, -4.7, 2],
	"landstrasse": ["Landstrasse", "Bavaria, Germany", 47.6, 10.7, 2],
	"dolphincove": ["Dolphin Cove", "Big Sur, California, USA", 36.3, -121.9, 1],
	"kindiak": ["Kindiak Park", "Wyoming, USA", 44.6, -110.5, 1],
	"adonf": ["Route Adonf", "Loire Valley, France", 47.3, 0.7, 2],
	"durham": ["Durham Road", "County Durham, England", 54.7, -1.8, 2],
	"snowy": ["Snowy Ridge", "Laurentians, Québec, Canada", 46.9, -71.2, 1],
	"raceway": ["Raceway", "Indiana, USA", 39.8, -86.2, 1],
	# Porsche Unleashed's France and Germany.
	"normandie": ["Normandie", "Normandy, France", 49.2, -0.4, 2],
	"schwarzwald": ["Schwarzwald", "Black Forest, Germany", 48.0, 8.1, 2],
	"corsica": ["Corsica", "Corsica, France", 42.15, 9.1, 2],
	"cotedazur": ["Côte d'Azur", "French Riviera", 43.27, 6.64, 2],
	"pyrenees": ["Pyrénées", "Pyrenees, France", 42.8, 0.3, 2],
	"alps": ["Alps", "French Alps", 45.9, 6.9, 2],
	"auvergne": ["Auvergne", "Massif Central, France", 45.4, 2.8, 2],
	"autobahn": ["Autobahn", "Franconia, Germany", 49.6, 10.4, 2],
	"industrielle": ["Zone Industrielle", "Outside Paris, France", 48.95, 2.35, 2],
	"monaco": ["Monte Carlo", "Monaco", 43.74, 7.42, 2],
	"skidpad": ["Skid Pad", "Weissach, Germany", 48.85, 8.92, 2],
	# Hot Pursuit 2's four areas, a course in each corner of them (keyed by the track ids).
	"hp2_parkland0": ["Coastal Parklands", "Oregon coast, USA", 44.6, -124.05, 1],
	"hp2_parkland1": ["National Forest", "Cascades, Oregon, USA", 44.0, -122.0, 1],
	"hp2_parkland2": ["Scenic Drive", "Columbia Gorge, USA", 45.65, -121.6, 1],
	"hp2_tropics0": ["Island Outskirts", "Puerto Rico", 18.3, -66.1, 1],
	"hp2_tropics1": ["Palm City Island", "Miami, Florida, USA", 25.8, -80.2, 1],
	"hp2_tropics2": ["Tropical Sunset", "Florida Keys, USA", 24.6, -81.6, 1],
	"hp2_alpine0": ["Fall Winds", "Green Mountains, Vermont, USA", 44.2, -72.85, 1],
	"hp2_alpine1": ["Alpine Trail", "White Mountains, New Hampshire, USA", 44.25, -71.2, 1],
	"hp2_alpine2": ["Autumn Crossing", "Maine, USA", 45.2, -69.4, 1],
	"hp2_medit0": ["Wine Country", "Tuscany, Italy", 43.4, 11.2, 2],
	"hp2_medit1": ["Calypso Coast", "Gozo, Malta", 36.05, 14.25, 2],
	"hp2_medit2": ["Mediterranean Paradise", "Amalfi Coast, Italy", 40.63, 14.6, 2],
	# Off the map: made up each time, and add-on tracks we can't place.
	"generated": ["Generated", "Out in the Atlantic: a new road from a seed", 36.0, -38.0, 0],
	"elsewhere": ["Elsewhere", "Add-on tracks", 30.0, -48.0, 0],
}
## Each track's place, and its chip there when the place has several ("" otherwise).
const TRACK_PLACES := {
	"trk000": ["hometown", "NFS III"], "hs_hometown": ["hometown", "HIGH STAKES"],
	"trk001": ["redrock", "NFS III"], "hs_redrock": ["redrock", "HIGH STAKES"],
	"trk002": ["atlantica", "NFS III"], "hs_atlantic": ["atlantica", "HIGH STAKES"],
	"trk003": ["rockypass", "NFS III"], "hs_rockypas": ["rockypass", "HIGH STAKES"],
	"trk004": ["countrywoods", "NFS III"], "hs_country": ["countrywoods", "HIGH STAKES"],
	"trk005": ["lostcanyons", "NFS III"], "hs_lostcany": ["lostcanyons", "HIGH STAKES"],
	"trk006": ["aquatica", "NFS III"], "hs_aquatica": ["aquatica", "HIGH STAKES"],
	"trk007": ["summit", "NFS III"], "hs_summit": ["summit", "HIGH STAKES"],
	"trk008": ["empire", "NFS III"], "hs_empire": ["empire", "HIGH STAKES"],
	"hs_uk": ["celtic", ""], "hs_germany": ["landstrasse", ""], "hs_coastal": ["dolphincove", ""],
	"hs_park": ["kindiak", ""], "hs_france": ["adonf", ""], "hs_hills": ["durham", ""],
	"hs_snowy": ["snowy", ""], "hs_gt1": ["raceway", "1"], "hs_gt2": ["raceway", "2"], "hs_gt3": ["raceway", "3"],
	"pu_farmland": ["normandie", ""], "pu_forest": ["schwarzwald", ""], "pu_foothills": ["corsica", ""],
	"pu_coastal": ["cotedazur", ""], "pu_canyon": ["pyrenees", ""], "pu_alps": ["alps", ""],
	"pu_castle": ["auvergne", ""], "pu_autobahn": ["autobahn", ""], "pu_industrial": ["industrielle", ""],
	"pu_monaco1": ["monaco", "1"], "pu_monaco2": ["monaco", "2"], "pu_monaco3": ["monaco", "3"],
	"pu_monaco4": ["monaco", "4"], "pu_monaco5": ["monaco", "5"], "pu_skidpad": ["skidpad", ""],
	"procedural": ["generated", ""],
}
const GAME_TAGS := ["NFS III", "HS", "PU", "HP2"]
const GAME_TITLES := ["NEED FOR SPEED III", "HIGH STAKES", "PORSCHE UNLEASHED", "HOT PURSUIT 2"]
const CARD_GAP := 28.0
const HEAD_BOTTOM := 132.0
const NAME_SIZE := 17
const CHIP_SIZE := 13
const CHIP_H := 21.0

var night := false
## (id: String, night: bool) -> Texture2D or null, and (id) -> PackedVector3Array.
var postcard: Callable
var outline: Callable

var _maps := {}               # id -> {pts: PackedVector2Array in 0..1, km: float}
var _precip := {}             # id -> Nfs3Horizon.Precip
var _map: WorldMap
var _card: Control
var _card_outline: TrackMap
var _card_item := -1
## key -> {name, where, pos (map units), region, entries (indices into `entries`), multi,
## off (the label's top-left from the pin, px), size, shown (the label found room)}
var _places := {}
var _place_order: Array[String] = []


func _init() -> void:
	super()
	title = "TRACKS"
	noun = "tracks"
	grid = true
	head_h = HEAD_BOTTOM
	total = Game.tracks.size()
	_map = WorldMap.new()
	_map.show_behind_parent = true
	_map.moved.connect(_on_map_moved)
	add_child(_map)
	move_child(_map, 0)
	_card = Control.new()
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.draw.connect(_draw_card)
	add_child(_card)
	_card_outline = TrackMap.new()
	_card_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_card_outline)
	# The chips pick a region (not a filter): the map flies there and the focus with it.
	for c in filters.changed.get_connections():
		filters.changed.disconnect(c.callable)
	filters.changed.connect(_on_region)
	filters.set_items(PackedStringArray(REGIONS), 1)
	move_child(filters, -1)


func hints() -> Array:
	return [["←→↑↓", "BROWSE"], ["TAB", "REGION"]]


## The game a track is from, in full ("PORSCHE UNLEASHED").
func section(id: String) -> String:
	return "GENERATED" if id == Game.PROCEDURAL_TRACK else GAME_TITLES[Game.track_game(id)]


func precip(id: String) -> int:
	if not _precip.has(id):
		var dir := Game.track_dir(id)
		_precip[id] = Nfs3Horizon.peek_precip(dir) if dir != "" else Nfs3Horizon.Precip.RAIN
	return _precip[id]


## The outline scaled into 0..1 (aspect kept) and the lap length.
func map_of(id: String) -> Dictionary:
	if not _maps.has(id):
		var pts: PackedVector3Array = outline.call(id)
		var out := PackedVector2Array()
		var len_m := 0.0
		if pts.size() > 2:
			var lo := Vector2(INF, INF)
			var hi := -lo
			for i in pts.size():
				var p := Vector2(pts[i].x, pts[i].z)
				lo = lo.min(p)
				hi = hi.max(p)
				if i + 1 < pts.size() or not Game.is_sprint(id):
					len_m += pts[i].distance_to(pts[(i + 1) % pts.size()])
			var s := maxf(hi.x - lo.x, hi.y - lo.y)
			for p3 in pts:
				out.append((Vector2(p3.x, p3.z) - lo) / s)
		_maps[id] = {"pts": out, "km": len_m / 1000.0}
	return _maps[id]


## The track's place key and its chip there.
static func place_of(id: String) -> Array:
	if PLACES.has(id):
		return [id, ""]   # Hot Pursuit 2's courses: a place each
	return TRACK_PLACES.get(id, ["elsewhere", Game.track_name(id)])


## "Monte Carlo, Monaco": where the track is set.
func where(id: String) -> String:
	return PLACES[place_of(id)[0]][1]


func _region_of_item(item: int) -> int:
	return PLACES[place_of(Game.tracks[item])[0]][4] if item >= 0 else 0


# ------------------------------------------------------------------ open / layout

func open(item: int) -> void:
	filters.set_items(filters.items, _region_of_item(item))
	_card_item = -1
	# Fly in from the whole world.
	_layout()
	_map.fit(_box(REGION_BOX[0]), true, Vector2(40, 20))
	super(item)


func refresh() -> void:
	super()
	_card.queue_redraw()


func _layout() -> void:
	var cw := _card_w()
	head_w = minf(size.x - cw - CARD_GAP, 520.0)
	super()
	filters.position = Vector2(-8, 100)
	_list.position = Vector2.ZERO
	_list.size = size
	_card.position = Vector2(size.x - cw, 0)
	_card.size = Vector2(cw, size.y)
	# The map runs out past the frame's edges and fades there; pins are fitted into the part
	# left of the card, under the header.
	_map.position = Vector2(-40, -24)
	_map.size = size + Vector2(80, 48)
	_map.frame = Rect2(Vector2(40, 24 + HEAD_BOTTOM), Vector2(size.x - cw - CARD_GAP, size.y - HEAD_BOTTOM))
	(_map.material as ShaderMaterial).set_shader_parameter("top_fade", 60.0)
	_map._push()
	_layout_card()
	if visible:
		_reframe(true)


func _card_w() -> float:
	return clampf(size.x * 0.3, 320.0, 440.0)


func _build_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# Grouped by place, places in the table's order, so chips come in theirs.
	var by_place := {}
	for i in Game.tracks.size():
		var id := Game.tracks[i]
		var pl := place_of(id)
		var p: Array = PLACES[pl[0]]
		var hay := "%s %s %s %s %s" % [Game.track_name(id), p[0], p[1], section(id),
			"snow" if precip(id) == Nfs3Horizon.Precip.SNOW else ""]
		if query != "" and not _matches(hay.to_lower()):
			continue
		if not by_place.has(pl[0]):
			by_place[pl[0]] = []
		by_place[pl[0]].append({"item": i, "text": Game.track_name(id), "place": pl[0], "chip": pl[1], "rect": Rect2()})
	_places.clear()
	_place_order.clear()
	# How many tracks each place has in all (not just matching): a place of several shows chips.
	var count := {}
	for id in Game.tracks:
		var key: String = place_of(id)[0]
		count[key] = count.get(key, 0) + 1
	for key in PLACES:
		if not by_place.has(key):
			continue
		var p: Array = PLACES[key]
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
	# The chip follows the track in focus (but stays on the world while that's the view).
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
		_map.fit(_box(REGION_BOX[filters.index]), instant, Vector2(40, 16))
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
		var tag := _tag(e.item)
		return Vector2(nf.get_string_size(e.text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x + 8
			+ UiKit.text_width("cond", tag, 11, 1) + 10, 24)
	var w := nf.get_string_size(pl.name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x + 10
	var cw := 0.0
	for k in pl.entries:
		cw += _chip_w(entries[k].chip) + 4
	return Vector2(maxf(w, cw), 24 + CHIP_H + 2)


func _chip_w(text: String) -> float:
	return UiKit.text_width("cond", text, CHIP_SIZE, 1) + 14


func _tag(item: int) -> String:
	var id := Game.tracks[item]
	return "" if id == Game.PROCEDURAL_TRACK else GAME_TAGS[Game.track_game(id)]


## Puts each place's label beside its pin where it overlaps nothing (no other label, pin,
## the header or the card), trying close round it first and then further out on a leader.
## Laid out for where the camera is heading, so they don't shuffle while it moves.
func _layout_labels() -> void:
	var blocked: Array[Rect2] = [Rect2(0, 0, head_w + 20, HEAD_BOTTOM), Rect2(_card.position - Vector2(12, 0), _card.size + Vector2(12, 0))]
	var area := Rect2(4, 4, _card.position.x - 16, size.y - 8)
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
		# Into the region: the track in use if it's there, else the one nearest its middle.
		var c: Vector2 = _box(REGION_BOX[i]).get_center()
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
	if not visible:
		return
	if focused_item() != _card_item:
		_card_item = focused_item()
		_show_card()
	_list.queue_redraw()   # the pulse round the focused pin


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	# Darken the map under the title and search, so they read over it.
	var w := head_w + 120
	var a := Color(0.035, 0.038, 0.05, 0.85)
	var b := Color(a, 0.0)
	draw_polygon(PackedVector2Array([Vector2(-40, -24), Vector2(w, -24), Vector2(w, HEAD_BOTTOM), Vector2(-40, HEAD_BOTTOM)]),
		PackedColorArray([a, b, b, a]))
	super()


func _draw_list() -> void:
	var l := _list
	if entries.is_empty():
		var f := UiKit.font("display")
		var msg := "NO %s MATCH \"%s\"" % [noun.to_upper(), query.to_upper()] if query != "" else "NOTHING HERE"
		l.draw_string(f, Vector2(0, HEAD_BOTTOM + 60), msg, HORIZONTAL_ALIGNMENT_LEFT, _card.position.x - 20, 24, UiKit.INK_DIM)
		l.draw_string(UiKit.font("body"), Vector2(0, HEAD_BOTTOM + 88), "Backspace to edit, Esc to clear.",
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
	var in_use := false
	for k in pl.entries:
		in_use = in_use or entries[k].item == picked
	if focused:
		var t := fmod(_time * 0.9, 1.0)
		ci.draw_arc(p, 6.0 + t * 16.0, 0, TAU, 32, Color(UiKit.ACCENT, 0.7 * (1.0 - t)), 1.5, true)
		ci.draw_circle(p, 7.0, Color(0, 0, 0, 0.6))
		ci.draw_circle(p, 5.0, UiKit.ACCENT)
	else:
		ci.draw_circle(p, 5.0, Color(0, 0, 0, 0.55))
		ci.draw_circle(p, 3.2, Color(1, 1, 1, 0.9) if key != "generated" and key != "elsewhere" else UiKit.INK_DIM)
	if in_use:
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
		ci.draw_string(UiKit.font("cond", 1), r.position + Vector2(nw + 11, 16), _tag(e.item), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(UiKit.BG, 0.7) if focused else UiKit.INK_FAINT)
		return
	# A place of several: its name, and a chip for each of its tracks.
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
		var border := UiKit.ACCENT if e.item == picked else Color(1, 1, 1, 0.28)
		UiKit.box(ci, cr, fill, 3, border, 1)
		ci.draw_string(cf, Vector2(cr.position.x, cr.position.y + 15), e.chip, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, CHIP_SIZE,
			UiKit.BG if on else UiKit.INK)


# ------------------------------------------------------------------ the card

func _show_card() -> void:
	if _card_item >= 0:
		var id := Game.tracks[_card_item]
		_card_outline.set_outline(outline.call(id), true, Game.is_sprint(id))
	_layout_card()
	_card.queue_redraw()


## The card's parts, top down: picture, words, outline, facts.
func _card_parts() -> Dictionary:
	var w := _card.size.x
	var pad := 22.0
	var img := Rect2(Vector2.ZERO, Vector2(w, w * 9.0 / 16.0))
	var text_y := img.end.y + 30
	var facts_h := 3 * 30.0 + 10
	var outline_r := Rect2(pad, text_y + 92, w - pad * 2, _card.size.y - text_y - 92 - facts_h - 14)
	return {"img": img, "text_y": text_y, "outline": outline_r, "facts_y": outline_r.end.y + 26, "pad": pad}


func _layout_card() -> void:
	if _card == null or _card.size.x <= 0:
		return
	var r: Rect2 = _card_parts().outline
	_card_outline.position = r.position
	_card_outline.size = r.size.max(Vector2(10, 10))
	_card_outline.visible = r.size.y > 60


func _draw_card() -> void:
	var c := _card
	UiKit.box(c, Rect2(Vector2.ZERO, c.size), Color(0.045, 0.05, 0.065, 0.94), 6, UiKit.LINE, 1)
	if _card_item < 0:
		return
	var id := Game.tracks[_card_item]
	var parts := _card_parts()
	var img: Rect2 = parts.img
	var pad: float = parts.pad
	var w := c.size.x - pad * 2
	var tex: Texture2D = postcard.call(id, night)
	if tex:
		c.draw_texture_rect(tex, img.grow(-1), false)
	else:
		c.draw_rect(img.grow(-1), Color(0.08, 0.09, 0.11))
		c.draw_string(UiKit.font("cond", 1), Vector2(img.position.x, img.get_center().y + 5), "RENDERING…",
			HORIZONTAL_ALIGNMENT_CENTER, img.size.x, 13, UiKit.INK_DIM)
	if _card_item == picked:
		var tf := UiKit.font("cond", 1)
		var tw := tf.get_string_size("IN USE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14
		UiKit.box(c, Rect2(Vector2(12, 12), Vector2(tw, 20)), UiKit.ACCENT, 10)
		c.draw_string(tf, Vector2(19, 26), "IN USE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.BG)
	var y: float = parts.text_y
	UiKit.kicker(c, Vector2(pad, y - 4), section(id), w)
	var name := Game.track_name(id).to_upper()
	c.draw_string(UiKit.font("display"), Vector2(pad - 2, y + 36), name, HORIZONTAL_ALIGNMENT_LEFT, w,
		UiKit.fit("display", name, w, 40, 22), UiKit.INK)
	# Where: a small pin, then the place.
	var py := y + 64
	c.draw_circle(Vector2(pad + 5, py - 5), 4.0, UiKit.ACCENT)
	c.draw_circle(Vector2(pad + 5, py - 5), 1.6, Color(0.045, 0.05, 0.065))
	c.draw_string(UiKit.font("body"), Vector2(pad + 16, py), where(id), HORIZONTAL_ALIGNMENT_LEFT, w - 16, 15, UiKit.INK_DIM)
	# Facts.
	var km: float = map_of(id).km
	var snow := precip(id) == Nfs3Horizon.Precip.SNOW
	var facts := [["Length", (UiKit.dist(km) + (" one way" if Game.is_sprint(id) else " a lap")) if km > 0 else "—"],
		["Route", "Point to point" if Game.is_sprint(id) else "Circuit"],
		["Weather", "Clear or snow" if snow else "Clear or rain"]]
	var fy: float = parts.facts_y
	c.draw_line(Vector2(pad, fy - 22), Vector2(c.size.x - pad, fy - 22), UiKit.LINE, 1.0)
	for f in facts:
		c.draw_string(UiKit.font("body"), Vector2(pad, fy), f[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiKit.INK_DIM)
		c.draw_string(UiKit.font("display"), Vector2(pad + 86, fy), f[1], HORIZONTAL_ALIGNMENT_LEFT, w - 86, 19, UiKit.INK)
		fy += 30
