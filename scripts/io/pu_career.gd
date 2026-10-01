class_name PuCareer
## Porsche Unleashed's Evolution (FeData/Data/nfs5.trn), as tournaments: its three eras, each
## a tournament of its events, in the same shape as High Stakes' (HsCareer, series "pu").
##
## nfs5.trn: 35 records of 3392 bytes. Each: id; era (0x209..0x20B Classic, Golden, Modern
## tournaments; 0x20C..0x20E the same eras' events); a year and the era's tracks (u16s,
## unused here); four festrings.loc ids (short name, name, description, what cars it
## takes); from 0x30 up to 85 u16 car serials (nfs5.car's first byte) it takes, their count
## at 0xDA; the entry fee (u16 $) at 0xDC; 0xE4 = 2 a race to win the car (the era's bonus
## race); 0xE8 = 1 a rally (placed by the lowest total time, winnings paid at the end);
## 0xE9 = 1 on the open road (traffic and police); the prize for each final place (8 u32 $)
## at 0xEC; the number of opponents at 0x114 and from 0x118 theirs, 88 bytes each (a driver
## number, the car's serial, a count of parts and the parts, then paints); the number of
## races at 0x39C and from 0x3A0 the races, 164 bytes each: the track (u16, nfs5.trk's
## number: TRACKS) and its laps (u16, 0 point to point), reversed (u32 1), the prize for
## each place in it (8 u32 $, then one more not followed up), and the opponents' pace
## (float, 0.45 .. 1).
##
## FeData/Locale/festrings.loc: "LOCH" (languages), "LOCI" (count at +8, then u16 pairs:
## string id, index), "LOCL" (count at +12, then u32 offsets from "LOCL" of the English
## strings, zero-terminated).

const RECORD := 3392
const ERA_NAMES := ["Classic Era", "Golden Era", "Modern Era"]
const ERA_ABOUT := ["From 1950: the 356 to the first 911", "From 1970: the 914, Carrera RS, 911 Turbo and 944",
	"From 1989: the 964, 993, 996 and Boxster"]
## nfs5.trk's track numbers -> GameData/Track names.
const TRACKS := {8: "coastal", 9: "forest", 10: "foothills", 11: "alps", 12: "autobahn", 13: "castle",
	14: "farmland", 16: "industrial", 18: "monaco1", 25: "monaco2", 26: "monaco3", 29: "monaco4", 30: "monaco5",
	32: "skidpad", 34: "canyon"}
## Evolution starts you with this much (enough for a 356 1300, not a 1500 Super).
const START_MONEY := 12000


static func load_root(pu_root: String) -> HsCareer:
	var fe := pu_root.get_base_dir()
	var d := FileAccess.get_file_as_bytes(DataPath.find_ci(fe, "FeData/Data/nfs5.trn"))
	var cars := FileAccess.get_file_as_bytes(DataPath.find_ci(fe, "FeData/Data/nfs5.car"))
	if d.size() < RECORD or cars.is_empty():
		return null
	var text := read_loc(DataPath.find_ci(fe, "FeData/Locale/festrings.loc"))
	# Serial -> car id, the racing cars only (not the police, not traffic).
	var ids := {}
	for i in cars.size() / Nfs5Car.RECORD_SIZE:
		var r := i * Nfs5Car.RECORD_SIZE
		var name := Nfs3Car._c_string(cars, r + 2)
		var sim := Nfs3Car._c_string(cars, r + 177)
		if sim != "" and not name.begins_with("Cop") and not ids.has(cars[r]):
			ids[cars[r]] = Game.PU_PREFIX + sim.to_lower()
	var c := HsCareer.new()
	c.series = "pu"
	c.start_money = START_MONEY
	var eras := [[], [], []]
	for e in d.size() / RECORD:
		var p := e * RECORD
		var era := d.decode_u32(p + 4) - 0x209
		if era < 0 or era > 5:
			continue
		var only_ids := []
		for k in clampi(d.decode_u16(p + 0xDA), 0, 85):
			var s := d.decode_u16(p + 0x30 + k * 2)
			if ids.has(s) and not ids[s] in only_ids:
				only_ids.append(ids[s])
		var field := []
		for k in clampi(d.decode_u32(p + 0x114), 0, 7):
			field.append(ids.get(d.decode_u16(p + 0x118 + k * 88 + 2), ""))
		var races := []
		var pace := 0.0
		for k in clampi(d.decode_u32(p + 0x39C), 0, 15):
			var q := p + 0x3A0 + k * 164
			var prizes := []
			for j in 8:
				prizes.append(float(d.decode_u32(q + 8 + j * 4)))
			var f := d.decode_float(q + 0x2C)
			pace += f
			races.append({"id": Game.PU_PREFIX + TRACKS.get(d.decode_u16(q), "?"), "laps": maxi(d.decode_u16(q + 2), 1),
				"reverse": d.decode_u32(q + 4) == 1, "mirror": false, "night": false, "weather": false,
				# High Stakes' pace scale (0.4 .. 2.9) from Evolution's 0.45 .. 1.
				"pace": 0.4 + clampf((f - 0.45) / 0.55, 0.0, 1.0) * 2.5, "prizes": prizes})
		if races.is_empty():
			continue
		var prizes := []
		for j in 8:
			prizes.append(float(d.decode_u32(p + 0xEC + j * 4)))
		var strings := []
		for j in 4:
			strings.append(text.get(d.decode_u32(p + 0x20 + j * 4), ""))
		var car_race := d.decode_u16(p + 0xE4) == 2
		var id := d.decode_u32(p)
		var circuit := {"id": id, "type": HsCareer.TYPE_CAR_RACE if car_race else HsCareer.TYPE_TOURNAMENT,
			"fee": float(d.decode_u16(p + 0xDC)), "races": races, "opponents": field.size(), "laps": 1,
			"restriction": HsCareer.CARS, "value": 0, "cars": only_ids, "only": strings[3], "field": field,
			"prizes": prizes, "award": -1, "award_id": only_ids[0] if car_race and not only_ids.is_empty() else "",
			"pace": 0.4 + clampf((pace / races.size() - 0.45) / 0.55, 0.0, 1.0) * 2.5, "mam": [0, 0, 0],
			"name": strings[1], "about": strings[2], "rally": d[p + 0xE8] == 1, "traffic": d[p + 0xE9] == 1, "needs": []}
		c.circuits[id] = circuit
		eras[era % 3].append(circuit)
		for car_id in only_ids + field:
			if car_id != "" and not (car_race and car_id == circuit.award_id):
				c.dealer[car_id] = true
	# Each era: its tournaments, then its events, then the race for its bonus car, which
	# opens once the rest are won. Winning an era opens the next.
	for k in 3:
		var list: Array = eras[k]
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if (a.type == HsCareer.TYPE_CAR_RACE) != (b.type == HsCareer.TYPE_CAR_RACE):
				return b.type == HsCareer.TYPE_CAR_RACE
			return a.id < b.id)
		var others: Array = list.filter(func(x: Dictionary) -> bool: return x.type != HsCareer.TYPE_CAR_RACE).map(
			func(x: Dictionary) -> int: return x.id)
		for x: Dictionary in list:
			if x.type == HsCareer.TYPE_CAR_RACE:
				x.needs = others
		c.tournaments.append({"id": k + 1, "name": ERA_NAMES[k], "about": ERA_ABOUT[k], "open": k == 0,
			"circuits": list.map(func(x: Dictionary) -> int: return x.id), "unlocks": [k + 2] if k < 2 else []})
	# The bonus cars aren't sold.
	for x in c.circuits.values():
		if x.award_id != "":
			c.dealer.erase(x.award_id)
	return c


## festrings.loc's English strings: {string id: text}.
static func read_loc(path: String) -> Dictionary:
	var out := {}
	var d := FileAccess.get_file_as_bytes(path) if path != "" else PackedByteArray()
	var li := _find(d, "LOCI")
	var ll := _find(d, "LOCL")
	if li < 0 or ll < 0:
		return out
	var n_ids := d.decode_u32(li + 8)
	var n := d.decode_u32(ll + 12)
	for k in n_ids:
		var at := li + 16 + k * 4
		if at + 4 > d.size():
			break
		var idx := d.decode_u16(at + 2)
		if idx >= n:
			continue
		var o := ll + d.decode_u32(ll + 16 + idx * 4)
		var e := o
		while e < d.size() and d[e] != 0:
			e += 1
		# Windows-1252: the quotes and ellipsis (0x85, 0x92) as plain ones, the rest Latin-1.
		var s := ""
		for b in d.slice(o, e):
			s += {0x85: "...", 0x91: "'", 0x92: "'", 0x93: "\"", 0x94: "\"", 0x96: "-", 0x97: "-"}.get(b, char(b))
		out[d.decode_u16(at)] = s
	return out


static func _find(d: PackedByteArray, tag: String) -> int:
	var t := tag.to_ascii_buffer()
	for i in range(0, mini(d.size() - 4, 1 << 16)):
		if d[i] == t[0] and d[i + 1] == t[1] and d[i + 2] == t[2] and d[i + 3] == t[3]:
			return i
	return -1
