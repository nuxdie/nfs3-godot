class_name HsCareer
## High Stakes' tournaments (Data/Text/tierdef.cdb, circdef.cdb, with mam.dat and man.dat).
##
## tierdef.cdb: 108-byte records, the first a header. Each: id, a 40-byte name, whether
## it's open from the start, its number of circuits and their ids, then three unlock
## triples (the tournaments winning it opens, one per difficulty; the first is used).
##
## circdef.cdb: 336-byte records, the first a header. Each: id; type (0 a tournament
## circuit, 1 a knockout, 2 a one-off race for a car); entry fee (float $); races;
## opponents; laps; the car restriction and its value (see the enum below); the prize for
## each finishing place (8 floats $; for type 2 the car won instead, AWARD_CARS); ?; three
## mam.dat rows for the opponents (+96 and +100 used for things not followed up, +104 how
## strong a car each gets); the opponents' pace (float, 0.4 .. 2.9); and per race a track
## (in High Stakes' numbering, Game.HS_SLIDES) and four flags. The flags are read as
## reverse, mirror, night and weather: which is which isn't settled. No field says traffic.
##
## mam.dat: 11 rows of {min, mid, max} percentages (three columns of 11 ints). man.dat: the
## makes a "Manufacturer" restriction names, a line each.
##
## The restriction, prize car and mam rows are read off nfshs.exe (the PC release): its
## circuit screen, its entry check and how it deals the opponents' cars (Game.circuit_allows,
## Game.deal_field).

const TIER_SIZE := 108
const CIRCUIT_SIZE := 336
const TYPE_TOURNAMENT := 0
const TYPE_KNOCKOUT := 1
const TYPE_CAR_RACE := 2
## A circuit's car restriction, its value in brackets: a class [0..3: AAA, AA, A, B], that
## class and under, any car, a model [fedata serial], a make [man.dat line], any model
## (as open), or a car lent for it (none of yours).
enum { CLASS, CLASS_AND_UNDER, OPEN, MODEL, MANUFACTURER, OPEN_MODEL, LOANER }
const CLASS_NAMES := ["AAA", "AA", "A", "B"]
## A car race's prize (its first "prize", 1..9) as the serial of the car won; -1 none. A
## tournament circuit whose first prize is as small (the Pro Cups: 1, 2, 9) gives that car
## to its winner instead of money. The ninth, La Niña's cup, isn't in the program's table:
## La Niña is taken to be its car.
const AWARD_CARS := [41, 42, -1, -1, 4, 35, 31, 16, 39]
## Below this a circuit's first "prize" is an AWARD_CARS number, not dollars.
const AWARD_MAX := 100.0

var tournaments: Array[Dictionary] = []   # {id, name, open, circuits: [id], unlocks: [id]}
## id -> {id, type, fee, races: [{track, reverse, mirror, night, weather}], opponents, laps,
## restriction, value, prizes: [$], award (serial of the car the winner gets, or -1), pace,
## mam: [3 row indices]}
var circuits := {}
var mam: Array[Vector3i] = []             # mam.dat's rows, {min, mid, max}
var makes := PackedStringArray()          # man.dat's lines


static func load_dir(text_dir: String) -> HsCareer:
	var tier := FileAccess.get_file_as_bytes(DataPath.find_ci(text_dir, "tierdef.cdb"))
	var circ := FileAccess.get_file_as_bytes(DataPath.find_ci(text_dir, "circdef.cdb"))
	if tier.size() < TIER_SIZE * 2 or circ.size() < CIRCUIT_SIZE * 2:
		return null
	var c := HsCareer.new()
	for i in range(1, tier.size() / TIER_SIZE):
		var p := i * TIER_SIZE
		var name := Nfs3Car._c_string(tier, p + 4).strip_edges()
		var n := tier.decode_s32(p + 48)
		var ids := []
		for k in clampi(n, 0, 6):
			ids.append(tier.decode_s32(p + 52 + k * 4))
		var unlocks := []
		for k in 3:
			var u := tier.decode_s32(p + 76 + k * 4)
			if u > 0:
				unlocks.append(u)
		c.tournaments.append({"id": tier.decode_s32(p), "name": name, "open": tier.decode_s32(p + 44) == 1,
			"circuits": ids, "unlocks": unlocks})
	for i in range(1, circ.size() / CIRCUIT_SIZE):
		var p := i * CIRCUIT_SIZE
		var type := circ.decode_s32(p + 4)
		var n_races := clampi(circ.decode_s32(p + 12), 0, 8)
		var opponents := clampi(circ.decode_s32(p + 16), 1, 7)
		var prizes := []
		for k in opponents + 1:
			prizes.append(circ.decode_float(p + 32 + k * 4) if type != TYPE_CAR_RACE else 0.0)
		var races := []
		for k in n_races:
			var q := p + 112 + k * 28
			races.append({"track": circ.decode_s32(q), "reverse": circ.decode_s32(q + 4) != 0,
				"mirror": circ.decode_s32(q + 8) != 0, "night": circ.decode_s32(q + 12) != 0,
				"weather": circ.decode_s32(q + 16) != 0})
		var award := -1
		var first := circ.decode_float(p + 32)
		if type == TYPE_CAR_RACE or (first > 0.0 and first < AWARD_MAX):
			var k := roundi(first) - 1
			award = AWARD_CARS[k] if k >= 0 and k < AWARD_CARS.size() else -1
			if type != TYPE_CAR_RACE:
				prizes[0] = 0.0
		var rows := []
		for k in 3:
			rows.append(circ.decode_s32(p + 96 + k * 4))
		c.circuits[circ.decode_s32(p)] = {"id": circ.decode_s32(p), "type": type, "fee": circ.decode_float(p + 8),
			"races": races, "opponents": opponents, "laps": clampi(circ.decode_s32(p + 20), 1, 8),
			"restriction": clampi(circ.decode_s32(p + 24), CLASS, LOANER), "value": circ.decode_s32(p + 28),
			"prizes": prizes, "award": award, "pace": circ.decode_float(p + 108), "mam": rows}
	var m := FileAccess.get_file_as_bytes(DataPath.find_ci(text_dir, "mam.dat"))
	var n_rows := m.size() / 12
	for r in n_rows:
		c.mam.append(Vector3i(m.decode_s32(r * 4), m.decode_s32((n_rows + r) * 4), m.decode_s32((n_rows * 2 + r) * 4)))
	for line in FileAccess.get_file_as_string(DataPath.find_ci(text_dir, "man.dat")).split("\n", false):
		if line.strip_edges() != "":
			c.makes.append(line.strip_edges())
	return c


## A mam.dat row as {min, mid, max} percent ({1, 50, 99} if there's no such row).
func mam_row(i: int) -> Vector3i:
	return mam[i] if i >= 0 and i < mam.size() else Vector3i(1, 50, 99)


## What circuit `c` lets you enter with, for its screen ("Class A and under", "Chevrolet"...;
## "" for any car).
func restriction_text(c: Dictionary) -> String:
	var v: int = c.value
	match c.restriction:
		CLASS:
			return "Class %s" % CLASS_NAMES[clampi(v, 0, 3)]
		CLASS_AND_UNDER:
			return "Class %s and under" % CLASS_NAMES[clampi(v, 0, 3)] if v > 0 else ""
		MODEL:
			return Game.serial_name(v)
		MANUFACTURER:
			return makes[v] if v >= 0 and v < makes.size() else ""
		LOANER:
			return "Loaned car"
	return ""


## High Stakes' track number `n` as a track id ("hs_germany"), or "" if it isn't installed.
static func track_id(n: int) -> String:
	for folder in Game.HS_SLIDES:
		if Game.HS_SLIDES[folder] == n and (Game.HS_PREFIX + folder) in Game.tracks:
			return Game.HS_PREFIX + folder
	return ""
