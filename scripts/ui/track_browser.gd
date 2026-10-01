class_name TrackBrowser
extends MapBrowser
## Every track pinned on one world map, where it's set (the real place, or where the game's
## made-up one would be), whichever game it's from. The map glides to frame the region of the
## track in focus; a search frames what matches. A place with several tracks (Monte Carlo's
## five, a High Stakes remake beside its NFS III original) has one pin and a chip for each.
## The card on the right shows the track in focus: its picture, outline and facts.

## The regions and what each frames: [south, west, north, east] in degrees.
const REGIONS := [["WORLD", [-22.0, -155.0, 60.0, 150.0]], ["NORTH AMERICA", [17.0, -125.0, 52.5, -65.0]],
	["EUROPE", [35.5, -6.5, 58.0, 16.5]], ["JAPAN", [33.5, 136.0, 38.0, 142.0]]]

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
	# Gran Turismo 2's: the real venues where they are, its made-up courses by Polyphony
	# Digital in Tokyo (circuits, the expressway, the rally stages up in the mountains).
	"lagunaseca": ["Laguna Seca", "Monterey, California, USA", 36.58, -121.75, 1],
	"seattle": ["Seattle", "Seattle, Washington, USA", 47.6, -122.33, 1],
	"pikespeak": ["Pikes Peak", "Colorado Springs, Colorado, USA", 38.84, -105.04, 1],
	"rome": ["Rome", "Rome, Italy", 41.9, 12.5, 2],
	"grindelwald": ["Grindelwald", "Bernese Oberland, Switzerland", 46.62, 8.04, 2],
	"tahiti": ["Tahiti", "French Polynesia", -17.65, -149.4, 0],
	"gtcircuits": ["Gran Turismo's circuits", "Made up for the game: pinned by Polyphony Digital, Tokyo", 35.66, 139.7, 3],
	"gtvalleys": ["Gran Turismo's circuits", "Made up for the game: pinned west of Tokyo", 35.25, 138.4, 3],
	"gtspeedways": ["Gran Turismo's speedways", "Made up for the game: pinned north of Tokyo", 36.6, 139.9, 3],
	"gtexpressway": ["Special Stage Route 5", "Made up for the game: a Tokyo expressway at night", 35.62, 139.78, 3],
	"gtrally": ["Gran Turismo's rally stages", "Made up for the game: pinned in the Japanese Alps", 36.25, 137.7, 3],
	"elsewhere": ["Elsewhere", "Add-on tracks", 30.0, -48.0, 0],
}
## Each track's place, and its chip there when the place has several ("" otherwise).
const TRACK_PLACES := {
	"gt2_laguna": ["lagunaseca", ""], "gt2_seattle": ["seattle", "FULL"], "gt2_seatt_s": ["seattle", "SHORT"],
	"gt2_pikes": ["pikespeak", "CLIMB"], "gt2_pikes_rev": ["pikespeak", "DOWNHILL"],
	"gt2_roma": ["rome", "FULL"], "gt2_roma_short": ["rome", "SHORT"], "gt2_roma_night": ["rome", "NIGHT"],
	"gt2_grindel": ["grindelwald", ""],
	"gt2_tahiti_t": ["tahiti", "ROAD"], "gt2_tahiti_d_new": ["tahiti", "DIRT"], "gt2_tahiti_test7": ["tahiti", "MAZE"],
	"gt2_highway": ["gtexpressway", "SPECIAL STAGE"], "gt2_shortway": ["gtexpressway", "CLUBMAN"],
	"gt2_nn_dirt_2": ["gtrally", "SMOKEY SOUTH"], "gt2_no_name_dirt": ["gtrally", "SMOKEY NORTH"],
	"gt2_nn_dirt_3": ["gtrally", "GREEN FOREST"],
	"gt2_autumn": ["gtcircuits", "AUTUMN RING"], "gt2_mini": ["gtcircuits", "AUTUMN MINI"],
	"gt2_cart": ["gtcircuits", "MOTOR SPORTS LAND"], "gt2_circuit": ["gtvalleys", "GRAND VALLEY"],
	"gt2_short": ["gtvalleys", "GRAND VALLEY EAST"], "gt2_mountain": ["gtcircuits", "TRIAL MOUNTAIN"],
	"gt2_test_in2": ["gtcircuits", "DEEP FOREST"], "gt2_new_parmas": ["gtvalleys", "APRICOT HILL"],
	"gt2_parma": ["gtvalleys", "MIDFIELD"], "gt2_sprint2": ["gtvalleys", "RED ROCK VALLEY"],
	"gt2_testline": ["gtspeedways", "HIGH SPEED RING"], "gt2_s_speed": ["gtspeedways", "SUPER SPEEDWAY"],
	"gt2_speed": ["gtspeedways", "TEST COURSE"], "gt2_maxspeed": ["gtspeedways", "MAX SPEED"],
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
const GAME_TAGS := ["NFS III", "HS", "PU", "HP2", "GEN", "GT2"]
const GAME_TITLES := ["NEED FOR SPEED III", "HIGH STAKES", "PORSCHE UNLEASHED", "HOT PURSUIT 2", "GENERATED", "GRAN TURISMO 2"]
const HEAD_BOTTOM := 132.0

var night := false
## (id: String, night: bool) -> Texture2D or null, and (id) -> PackedVector3Array.
var postcard: Callable
var outline: Callable

var _maps := {}               # id -> {pts: PackedVector2Array in 0..1, km: float}
var _precip := {}             # id -> Nfs3Horizon.Precip
var _card: Control
var _card_outline: TrackMap
var _card_item := -1


func _init() -> void:
	super()
	title = "TRACKS"
	noun = "tracks"
	head_h = HEAD_BOTTOM
	map_top = HEAD_BOTTOM
	total = Game.tracks.size()
	_card = Control.new()
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.draw.connect(_draw_card)
	add_child(_card)
	_card_outline = TrackMap.new()
	_card_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_card_outline)
	set_regions(REGIONS)


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


# ------------------------------------------------------------------ the map's hooks

func _place_table() -> Dictionary:
	return PLACES


func _item_ids() -> Array:
	return range(Game.tracks.size())


func _item_place(item: int) -> Array:
	return place_of(Game.tracks[item])


func _item_text(item: int) -> String:
	return Game.track_name(Game.tracks[item])


func _item_tag(item: int) -> String:
	var id := Game.tracks[item]
	return "" if id == Game.PROCEDURAL_TRACK else GAME_TAGS[Game.track_game(id)]


func _item_hay(item: int) -> String:
	var id := Game.tracks[item]
	return "%s %s %s" % [Game.track_name(id), section(id), "snow" if precip(id) == Nfs3Horizon.Precip.SNOW else ""]


func _place_faint(key: String) -> bool:
	return key == "generated" or key == "elsewhere"


# ------------------------------------------------------------------ open / layout

func open(item: int) -> void:
	_card_item = -1
	super(item)


func refresh() -> void:
	super()
	_card.queue_redraw()


func _layout() -> void:
	var cw := _card_w()
	side_w = cw + SIDE_GAP
	head_w = minf(size.x - side_w, 520.0)
	super()
	_card.position = Vector2(size.x - cw, 0)
	_card.size = Vector2(cw, size.y)
	_layout_card()


func _card_w() -> float:
	return clampf(size.x * 0.3, 320.0, 440.0)


func _process(dt: float) -> void:
	super(dt)
	if visible and focused_item() != _card_item:
		_card_item = focused_item()
		_show_card()


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
