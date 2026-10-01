class_name Gt2Car
extends Nfs3Car
## Loads a Gran Turismo 2 car out of GT2.VOL (Gt2Vol): carobj/<id>.cdo, its model, and
## carobj/<id>.cdp, its texture; .carinfoa (the US names, paint swatches and which palette
## each paint is), .carcolor/.cclatain (the paints' names) and carparam/usa_gtmode_data.dat
## (engine, gearbox, weight, drivetrain and tyres) for the rest. Car ids are five letters
## (Gt2Car.id_name of the u32 the files hold); the last says which version of a car it is
## ("n" the road car, "r" its racing kit, "s"/"t" race versions).
##
## The model (.cdo, after pez2k's GT2ModelTool and Nenkai's 010 template): a header with the
## wheels (menu radius/width, then each wheel's X, Y, Z: front left, front right, rear left,
## rear right), at 0x868 the LOD count and table, then the LODs: counts (vertices, normals,
## triangles, quads, -, -, textured triangles, textured quads), offsets, bounds, scale (a
## power of two: 2^(scale - 16)), then from +0x50 the vertices (s16 x, y, z, w; 1/4096 m),
## normals (three signed 10-bit fields), and the faces: 16 bytes plain, 28 textured (UVs and
## the palette). Y up, the front towards -Z, the left -X; quads are in turn round their edge.
## The wheels aren't in the model (the game builds them): they're made here (_wheel).
##
## The texture (.cdp): 256 x 224 at 4 bits, and per paint 16 palettes of 16 colours: each
## face picks its palette (0 the rims, 14/15 the brake lamps off/on). Colour 0 is see-through.

const UNITS := 1.0 / 4096.0
const PAGE := Vector2i(256, 224)
## The texture laid out once per palette in a 4 x 4 grid, each copy with a margin of its
## edge texels round it (filtering and mipmaps don't reach the neighbours), and a strip at
## the bottom of flat colours (the untextured faces'), 4 x 4 texels each.
const GUTTER := 8
const CELL := PAGE + Vector2i(GUTTER, GUTTER) * 2
const FLAT_Y := CELL.y * 4
const ATLAS := Vector2i(CELL.x * 4, CELL.y * 4 + 16)
## car.gdshader's paint mark: texels at this alpha are paint (clearcoated). Here they keep
## their colour, each paint its own texture (paint_texture), the tint white.
const PAINT_ALPHA := 117
## The rim's picture: palette 0's top left corner.
const RIM := Rect2(0, 0, 48, 48)
const RUBBER := Color(0.07, 0.07, 0.075)
const MAKERS := ["Acura", "Alfa Romeo", "Aston Martin", "Audi", "BMW", "Chevrolet", "Citroen", "Daihatsu",
	"Dodge", "Fiat", "Ford", "Honda", "Isuzu", "Jaguar", "Lancia", "", "Lister", "Lotus", "Mazda",
	"Mercedes-Benz", "", "Rover", "Mitsubishi", "Nissan", "Opel", "Peugeot", "Plymouth", "Renault",
	"RUF", "Shelby", "Subaru", "Suzuki", "Tommykaira", "Toyota", "TVR", "Vauxhall", "Vector",
	"Venturi", "Volkswagen"]
const DRIVES := ["FR", "FF", "4WD", "MR", "RR"]
## CarAudio's engine table index at the redline (its ESP_SCALE).
const ESP_SCALE := 416.0

var gt2_id := ""
var year := 0
## The body's textured faces, for finding the lamps: {first, count (its vertices in the mesh),
## pal, uv (Rect2i of its texels), brake (GT2's brake lamp flag), center}.
var _faces: Array[Dictionary] = []
var _sound := -1          # engine/<_sound>.es (the intake) and _n0/_t0 (the stock exhaust)
var _turbo := false
var _voices: Array[Dictionary] = []
var _cdp := PackedByteArray()          # the texture file, for paint_texture
var _flats: Array[Color] = []
var _paint_of := PackedInt32Array()    # colours[k]'s paint in the .cdp
var _paint_textures := {}              # k -> Texture2D

static var _tables := {}   # GT2.VOL path -> {db, strings} (carparam, once)


## Car id <-> its five letters (pez2k's CarNameConversion): 6 bits a letter, last letter lowest.
static func id_name(id: int) -> String:
	const SET := "-0123456789abcdefghijklmnopqrstuvwxyz"
	var s := ""
	for i in 5:
		s = SET[(id >> (i * 6)) & 0x3F] + s
	return s


## The cars to list: [{id, name, make, colours: [{swatch, palette, name}], ...}], in
## .carinfoa's order. Each car's road version, and the race cars there's no road version of;
## not the ones the US game leaves out.
static func car_table(vol: Gt2Vol) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var info := vol.read(".carinfoa")
	var ccol := vol.read(".carcolor")
	var latin := vol.read(".cclatain")
	if info.size() < 8 or info.slice(0, 3).get_string_from_ascii() != "CAR":
		return out
	var db := _db(vol)
	var all: Array[Dictionary] = []
	var road := {}
	for i in info.decode_u32(4):
		var p := (i + 1) * 8
		var id := id_name(info.decode_u32(p))
		var at := info.decode_u16(p + 4)
		var misc := info.decode_u16(p + 6)
		var n_col := ((misc & 0x3C) >> 2) + 1
		var name := _pascal(info, at + n_col * 3).replace(char(0x7F), "").strip_edges()
		if misc & 0x100 or name == "" or name == "Delete" or not vol.has("carobj/%s.cdo.gz" % id):
			continue   # (0x100: not in the US game)
		var colours: Array[Dictionary] = []
		var names_at := ccol.decode_u16(i * 2 + 8) if ccol.size() >= i * 2 + 10 else -1
		for k in n_col:
			var c := {"swatch": _bgr555(info.decode_u16(at + k * 2)), "palette": info[at + n_col * 2 + k], "name": ""}
			if names_at >= 0 and latin.size() > 0:
				c.name = _string(latin, ccol.decode_u16(names_at + k * 2))
			colours.append(c)
		var rec := {"id": id, "name": name, "colours": colours, "make": "", "year": 0, "price": 0}
		var car: Dictionary = db.cars.get(id, {})
		if not car.is_empty():
			rec.make = MAKERS[car.maker] if car.maker < MAKERS.size() else ""
			rec.year = car.year + (1900 if car.year >= 50 else 2000) if car.year > 0 else 0
			rec.price = car.price
		if rec.make != "" and not name.to_lower().begins_with(rec.make.to_lower()):
			rec.name = rec.make + " " + name
		all.append(rec)
		if id.ends_with("n"):
			road[id.left(4)] = true
	for rec in all:
		if rec.id.ends_with("n") or not road.has(rec.id.left(4)):
			out.append(rec)
	return out


static func _pascal(d: PackedByteArray, at: int) -> String:
	if at >= d.size():
		return ""
	return d.slice(at + 1, at + 1 + d[at]).get_string_from_ascii()


## String `k` of a table of u16 offsets followed by the strings.
static func _string(d: PackedByteArray, k: int) -> String:
	if k * 2 + 4 > d.size():
		return ""
	var a := d.decode_u16(k * 2)
	var b := d.decode_u16(k * 2 + 2)
	if b < a:
		b = d.size()
	return d.slice(a, b).get_string_from_ascii().strip_edges()


static func _bgr555(c: int) -> Color:
	return Color8((c & 0x1F) * 8, ((c >> 5) & 0x1F) * 8, ((c >> 10) & 0x1F) * 8)


# ---------------------------------------------------------------- the car database

## carparam/usa_gtmode_data.dat (pez2k's GT2DataSplitter): "GTDT", then (start, size) of
## each table at 8 * (k + 1): brakes, ..., chassis 3, ..., engine 6, ..., drivetrain 13,
## ..., gearbox 17, ..., front tyres 22, rear tyres 23, tyre sizes 24, ..., cars 30. A car's
## record (0x48 bytes) holds the index of its stock part in each table, in its own order
## (the LSD before the gearbox: parts[18] is the gearbox).
static func _db(vol: Gt2Vol) -> Dictionary:
	if _tables.has(vol.path):
		return _tables[vol.path]
	var d := vol.read("carparam/usa_gtmode_data.dat.gz")
	var db := {"d": d, "cars": {}, "tables": [], "strings": _strings(vol.read("carparam/usa_unistrdb.dat.gz"))}
	if d.size() > 0x100 and d.slice(0, 4).get_string_from_ascii() == "GTDT":
		for k in 31:
			db.tables.append(Vector2i(d.decode_u32(8 * (k + 1)), d.decode_u32(8 * (k + 1) + 4)))
		var t: Vector2i = db.tables[30]
		for i in t.y / 0x48:
			var p := t.x + i * 0x48
			var parts := PackedInt32Array()
			for k in 30:
				parts.append(d.decode_u16(p + 4 + k * 2))
			db.cars[id_name(d.decode_u32(p))] = {"parts": parts, "maker": d.decode_u16(p + 0x3A),
				"year": d[p + 0x41], "price": d.decode_u32(p + 0x44)}
	_tables[vol.path] = db
	return db


## carparam/usa_unistrdb.dat: at 8 the count, then each string as a u16 length - 1 and
## that many UTF-16 characters (and a terminator).
static func _strings(d: PackedByteArray) -> PackedStringArray:
	var out := PackedStringArray()
	if d.size() < 10:
		return out
	var p := 10
	for i in d.decode_u16(8):
		if p + 2 > d.size():
			break
		var n := (d.decode_u16(p) + 1) * 2
		out.append(d.slice(p + 2, p + 2 + n).get_string_from_utf16().strip_edges())
		p += 2 + n
	return out


## Where record `index` of table `k` is (its size `size`), or -1.
static func _rec(db: Dictionary, k: int, size: int, index: int) -> int:
	if k >= db.tables.size():
		return -1
	var t: Vector2i = db.tables[k]
	return t.x + index * size if index >= 0 and (index + 1) * size <= t.y else -1


# ---------------------------------------------------------------- loading

static func load_car(vol: Gt2Vol, rec: Dictionary) -> Gt2Car:
	var c := peek(vol, rec)
	var cdo := vol.read("carobj/%s.cdo.gz" % rec.id)
	var cdp := vol.read("carobj/%s.cdp.gz" % rec.id)
	if cdo.size() < 0x900 or cdo.slice(0, 2).get_string_from_ascii() != "GT":
		c.error = "bad carobj/%s.cdo" % rec.id
		return c
	if cdp.size() < 0x43A0 + PAGE.x * PAGE.y / 2:
		c.error = "bad carobj/%s.cdp" % rec.id
		return c
	var flats: Array[Color] = []
	c._read_model(cdo, flats)
	c._cdp = cdp
	c._flats = flats
	c._paint_of = _paints_in(cdp, rec)
	c.texture = c.paint_texture(0)
	c._find_lamps(cdp, vol.read("carobj/%s.cnp.gz" % rec.id))
	if c._sound >= 0:
		var stem := "engine/%05d" % c._sound
		c.sound_files["intake"] = vol.read(stem + ".es")
		# The stock exhaust for its aspiration, the other where that one's a stand-in.
		for suffix in (["_t0", "_n0"] if c._turbo else ["_n0", "_t0"]):
			var es := vol.read(stem + suffix + ".es")
			if _es_samples(es).size() > 2:
				c.sound_files["exhaust"] = es
				break
	return c


## The spec without the model, for the menus' lists.
static func peek(vol: Gt2Vol, rec: Dictionary) -> Gt2Car:
	var c := Gt2Car.new()
	c.gt2_id = rec.id
	c.id = "gt2_" + rec.id
	c.display_name = rec.name
	c.year = rec.year
	c.info = {"name": rec.name, "make": rec.make, "model": (rec.name as String).trim_prefix(rec.make + " ")}
	if rec.price > 0:
		c.info.price = "%d Cr." % rec.price
	if rec.year > 0:
		c.info.year = str(rec.year)
	c.info.colours = []
	for col: Dictionary in rec.colours:
		var sw := Color(col.swatch.r * 2.0, col.swatch.g * 2.0, col.swatch.b * 2.0)
		# (Two paints with one swatch, a two-tone and its plain version: Car finds a paint's
		# texture by its colour, so each one's is kept apart by a hair.)
		while sw in c.colours:
			sw.b += 1.0 / 1024.0
		c.colours.append(sw)
		c.info.colours.append(col.name if col.name != "" else "Colour %d" % (c.info.colours.size() + 1))
	c._read_spec(_db(vol))
	return c


## The car's stock parts as carp.txt fields (as Nfs6Car._read_spec): the engine's torque curve
## (kgf m x 100 at up to 16 points, rpm / 100), redline and rev limit; the gearbox (ratios
## x 1000, the final drive); the chassis' weight (kg), weight on the front (%), wheelbase (mm);
## the drivetrain (FR, FF, 4WD, MR, RR); the tyres' size and compound.
func _read_spec(db: Dictionary) -> void:
	var car: Dictionary = db.cars.get(gt2_id, {})
	var d: PackedByteArray = db.get("d", PackedByteArray())
	var parts: PackedInt32Array = car.get("parts", PackedInt32Array([-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
		-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1]))
	# Engine (76 bytes).
	var e := _rec(db, 6, 76, parts[6])
	var rpms := PackedFloat32Array()
	var tqs := PackedFloat32Array()
	var redline := 7000.0
	var limit := 7500.0
	var shown_ps := 0
	if e >= 0:
		var n := clampi(d[e + 0x4B], 2, 16)
		for k in n:
			var t := d.decode_s16(e + 0x0C + k * 2)
			var r := d[e + 0x3B + k]
			if t <= 0 or r == 255:
				break
			rpms.append(r * 100.0)
			tqs.append(t * 0.0980665)   # kgf m x 100 -> N m
		redline = maxf(d[e + 0x3A] * 100.0, 3000.0)
		limit = maxf(d[e + 0x39] * 100.0, redline)
		shown_ps = d.decode_u16(e + 0x2E)
		_sound = d.decode_u16(e + 0x0A)
		var asp := d.decode_u16(e + 0x08)
		var strings: PackedStringArray = db.get("strings", PackedStringArray())
		_turbo = asp < strings.size() and strings[asp].to_upper().contains("TURBO")
	if rpms.size() < 2:
		rpms = PackedFloat32Array([1000.0, 4000.0, 7000.0])
		tqs = PackedFloat32Array([150.0, 200.0, 170.0])
	# Every 256 rpm from 0 to the limit; held at 60 % of the first point below it.
	var curve := PackedFloat32Array()
	var power := 0.0
	for i in int(limit / 256.0) + 2:
		var rpm := i * 256.0
		var tq := tqs[0] * lerpf(0.6, 1.0, clampf(rpm / rpms[0], 0.0, 1.0))
		if rpm >= rpms[rpms.size() - 1]:
			tq = tqs[tqs.size() - 1] * clampf(1.0 - (rpm - rpms[rpms.size() - 1]) / 4000.0, 0.3, 1.0)
		else:
			for k in rpms.size() - 1:
				if rpm >= rpms[k] and rpm < rpms[k + 1]:
					tq = lerpf(tqs[k], tqs[k + 1], (rpm - rpms[k]) / (rpms[k + 1] - rpms[k]))
					break
		curve.append(tq)
		if rpm <= limit:
			power = maxf(power, tq * rpm * TAU / 60.0)
	# Chassis (20 bytes).
	var ch := _rec(db, 3, 20, parts[3])
	var mass := 1200.0
	var front := 0.55
	var wheelbase := 2.5
	if ch >= 0:
		front = clampf(d[ch + 4] / 100.0, 0.3, 0.7)
		wheelbase = d.decode_u16(ch + 0x0C) / 1000.0
		mass = maxf(d.decode_u16(ch + 0x0E), 500.0)
	# Gearbox (36 bytes): ratios x 1000, reverse first; race boxes (all -1) set by the game.
	var g := _rec(db, 17, 36, parts[18])
	var n_gears := 5
	var fwd := PackedFloat32Array()
	var reverse := 3.5
	var fd := 4.1
	if g >= 0:
		n_gears = clampi(d[g + 9], 3, 7)
		reverse = d.decode_s16(g + 10) / 1000.0
		for k in n_gears:
			fwd.append(d.decode_s16(g + 12 + k * 2) / 1000.0)
		fd = d.decode_s16(g + 0x1A) / 1000.0
	if fwd.is_empty() or fwd[0] <= 0.0:
		fwd.clear()
		for k in n_gears:
			fwd.append(3.2 * pow(0.82 / 3.2, k / float(n_gears - 1)))
		reverse = 3.3
	if fd <= 0.5:
		fd = 4.1
	if reverse <= 0.0:
		reverse = 3.3
	# Drivetrain (16 bytes).
	var dt := _rec(db, 13, 16, parts[13])
	var drive: String = DRIVES[clampi(d[dt + 8], 0, 4)] if dt >= 0 else "FR"
	var drive_front := 1.0 if drive == "FF" else 0.4 if drive == "4WD" else 0.0
	# Tyres: the size table (4 bytes: rim inches, width / 10, profile / 5) and the compound.
	var tyre := PackedFloat32Array([195.0, 55.0, 15.0])
	var compound := 0
	var tf := _rec(db, 22, 16, parts[22])
	if tf >= 0:
		compound = d[tf + 12]
		var ts := _rec(db, 24, 4, d[tf + 10])
		if ts >= 0 and d[ts] > 0:
			tyre = PackedFloat32Array([d[ts + 1] * 10.0 + 5.0, d[ts + 2] * 5.0, float(d[ts])])
	var radius := tyre[2] * 0.0254 * 0.5 + tyre[0] * tyre[1] / 100000.0
	var ratios := PackedFloat32Array([reverse, 0.0])
	ratios.append_array(fwd)
	while ratios.size() < 8:
		ratios.append(0.0)
	var v2rpm := PackedFloat32Array()
	for i in ratios.size():
		var r: float = ratios[i] * fd * 60.0 / (TAU * radius)
		v2rpm.append(-r if i == 0 else r)
	var top := pow(power * 0.85 / (0.5 * 1.2 * 0.32 * 2.0), 1.0 / 3.0)
	if v2rpm[n_gears + 1] > 0.0:
		top = minf(top, limit / v2rpm[n_gears + 1])
	var grip := 3.2 * (1.0 + 0.05 * clampi(compound, 0, 8))
	carp = {
		0: PackedFloat32Array([700.0]),
		1: PackedFloat32Array([0.0 if power / mass > 180.0 else 1.0 if power / mass > 95.0 else 2.0]),   # (as Nfs5Car's)
		2: PackedFloat32Array([mass]),
		3: PackedFloat32Array([n_gears + 2]),
		7: v2rpm, 8: ratios,
		10: curve,
		11: PackedFloat32Array([fd]),
		12: PackedFloat32Array([800.0]),
		13: PackedFloat32Array([redline]),
		14: PackedFloat32Array([top]),
		15: PackedFloat32Array([top]),
		16: PackedFloat32Array([drive_front]),
		17: PackedFloat32Array([1.0, 1.0]),
		18: PackedFloat32Array([clampf(9.0 + compound * 0.4, 8.0, 12.0)]),
		24: PackedFloat32Array([wheelbase]),
		25: PackedFloat32Array([front]),
		30: PackedFloat32Array([grip]),
		35: tyre, 36: tyre,
	}
	var ps := shown_ps if shown_ps > 0 else roundi(power / 735.5)
	info.power = "%d bhp" % roundi(ps * 0.986)
	info.torque = "%d N m" % roundi(Array(tqs).max())
	info.weight = "%d kg" % roundi(mass)
	info.drive = drive
	info.top_speed = "%d mph (%d km/h)" % [roundi(top * 2.23694), roundi(top * 3.6)]


# ---------------------------------------------------------------- the model

## LOD 0 as the body (one mesh, GT2's space turned to ours: facing +Z, the left +X, centred
## on its bounds) and four made wheels. `flats` collects the untextured faces' colours (their
## texels in the atlas' strip).
func _read_model(d: PackedByteArray, flats: Array[Color]) -> void:
	var lod_count := d.decode_u32(0x868)
	if lod_count < 1:
		error = "no LODs"
		return
	var p := 0x868 + 4 + 24
	var vc := d.decode_u16(p)
	var nc := d.decode_u16(p + 2)
	var tc := d.decode_u16(p + 4)
	var qc := d.decode_u16(p + 6)
	var utc := d.decode_u16(p + 12)
	var uqc := d.decode_u16(p + 14)
	var scale := pow(2.0, d.decode_u16(p + 0x4C) - 16) * UNITS
	var q := p + 0x50
	var verts := PackedVector3Array()
	for i in vc:
		verts.append(_to_car(Vector3(d.decode_s16(q), d.decode_s16(q + 2), d.decode_s16(q + 4)) * scale))
		q += 8
	var normals := PackedVector3Array()
	for i in nc:
		var u := d.decode_u32(q)
		normals.append(_to_car(Vector3(_s10(u >> 2), _s10(u >> 12), _s10(u >> 22))).normalized())
		q += 4
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for v in verts:
		lo = lo.min(v)
		hi = hi.max(v)
	var mid := (lo + hi) * 0.5
	mid.x = 0.0
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	for kind in 4:
		var count: int = [tc, qc, utc, uqc][kind]
		var quad := kind % 2 == 1
		var textured := kind >= 2
		for f in count:
			var vi := [d[q], d[q + 1], d[q + 2], d[q + 3]]
			var w0 := d.decode_u16(q + 4)
			var nd := d.decode_u32(q + 8)
			var ni := [(w0 >> 5) & 0x1FF, (nd >> 1) & 0x1FF, (nd >> 10) & 0x1FF, (nd >> 19) & 0x1FF]
			var face_uv: Array[Vector2] = []
			var face := {}
			if textured:
				var raw := d.decode_u16(q + 18)
				var pal := clampi((raw >> 4) + (raw & 0x3F), 0, 15)
				var cell := Vector2(CELL.x * (pal % 4) + GUTTER, CELL.y * (pal / 4) + GUTTER)
				var texels := Rect2i(d[q + 16], d[q + 17], 0, 0)
				for at in ([16, 20, 24, 26] if quad else [16, 20, 24]):
					face_uv.append((cell + Vector2(d[q + at], d[q + at + 1]) + Vector2(0.5, 0.5)) / Vector2(ATLAS))
					texels = texels.expand(Vector2i(d[q + at], d[q + at + 1]))
				if not quad:
					face_uv.append(face_uv[0])
				face = {"first": pos.size(), "pal": pal, "uv": texels, "brake": (d.decode_u16(q + 6) >> 12) & 4 != 0}
			else:
				var col := d.decode_u32(q + 12)
				var c := Color8(col & 0xFF, (col >> 8) & 0xFF, (col >> 16) & 0xFF)
				var k := flats.find(c)
				if k < 0:
					k = flats.size()
					flats.append(c)
				var t := (Vector2((k % (ATLAS.x / 4)) * 4 + 2, FLAT_Y + (k / (ATLAS.x / 4)) * 4 + 2)) / Vector2(ATLAS)
				face_uv.assign([t, t, t, t])
			q += 28 if textured else 16
			var corners := [0, 1, 2, 3] if quad else [0, 1, 2]
			if vi.slice(0, corners.size()).any(func(x: int) -> bool: return x >= vc):
				continue
			for tri in ([[0, 1, 2], [0, 2, 3]] if quad else [[0, 1, 2]]):
				# GT2 winds its faces anticlockwise seen from the front; Godot clockwise.
				for k in [tri[0], tri[2], tri[1]]:
					pos.append(verts[vi[k]] - mid)
					nrm.append(normals[ni[k]] if ni[k] < nc else Vector3.UP)
					uv.append(face_uv[k])
			if not face.is_empty():
				face.count = pos.size() - face.first
				var sum := Vector3.ZERO
				for k in corners.size():
					sum += verts[vi[k]] - mid
				face.center = sum / corners.size()
				_faces.append(face)
	if pos.is_empty():
		error = "empty model"
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	body_parts.append({"name": "body", "mesh": mesh, "center": Vector3.ZERO})
	half_size = (hi - lo) * 0.5
	# The wheels: the header's menu sizes (front, rear) and positions (FL, FR, RL, RR).
	for slot in 4:
		var front := slot < 2
		var r := d.decode_u16(0x18 if front else 0x1C) * UNITS
		var w := d.decode_u16(0x1A if front else 0x1E) * UNITS
		var at := 0x20 + slot * 8
		var hub := _to_car(Vector3(d.decode_s16(at), d.decode_s16(at + 2), d.decode_s16(at + 4)) * UNITS) - mid
		if r < 0.1:
			r = 0.3
			w = 0.2
		wheels.append({"name": "wheel%d" % slot, "mesh": _wheel(r, w, hub.x > 0.0), "center": hub})


# ---------------------------------------------------------------- the engine

## The engine's loops for CarAudio: [{stream, table (512 volumes, as High Stakes' .ctb:
## rpm / redline x 416), exhaust, gain, rpm (what it was recorded at: CarAudio plays it at
## the car's rpm over that)}], made when first asked for.
##
## engine/<n>.es ("ENGN", after SUBMANIAC's notes): 0x08 the header's size, 0x10 the samples'
## total size, 0x18 their count, 0x1C where their records are: 16 bytes each, fade-in rpm,
## the rpm it was recorded at, fade-out rpm, volume, u32 sample rate (the PS1 sound chip's
## pitch: 4096 is 44.1 kHz; SUBMANIAC took it for Hz / 10), u32 offset (from the header's end). The samples are Sony's 4-bit ADPCM (VAG). GT2 crossfades neighbouring
## recordings as the engine revs, the intake (<n>.es) and the exhaust (_n0..3 / _t0..3, by
## silencer and aspiration) together; a file of two placeholder samples means none.
func engine_voices() -> Array[Dictionary]:
	if not _voices.is_empty() or sound_files.is_empty():
		return _voices
	var redline := maxf(carp_value(13, 7000.0), 3000.0)
	for part in ["intake", "exhaust"]:
		var es: PackedByteArray = sound_files.get(part, PackedByteArray())
		var samples := _es_samples(es)
		if samples.size() <= 2:
			continue
		for k in samples.size():
			var smp: Dictionary = samples[k]
			var table := PackedByteArray()
			table.resize(512)
			for i in 512:
				var rpm := i / ESP_SCALE * redline
				table.encode_s8(i, roundi(127.0 * _es_share(samples, k, rpm)))
			var wav := AudioStreamWAV.new()
			wav.format = AudioStreamWAV.FORMAT_16_BITS
			wav.mix_rate = smp.rate
			wav.data = _vag(es, smp.from, smp.to)
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_end = wav.data.size() / 2
			_voices.append({"stream": wav, "table": table, "exhaust": part == "exhaust",
				"gain": clampf(smp.volume / 12000.0, 0.2, 1.4), "rpm": smp.rpm})
	return _voices


## An .es file's samples by rpm: [{rpm, volume, rate, from, to}], or [] if it isn't one.
static func _es_samples(es: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if es.size() < 0x30 or es.slice(0, 4).get_string_from_ascii() != "ENGN":
		return out
	var head := es.decode_u32(0x08)
	var total := es.decode_u32(0x10)
	var n := es.decode_u32(0x18)
	var at := es.decode_u32(0x1C)
	for k in n:
		var p := at + k * 16
		if p + 16 > es.size():
			break
		out.append({"rpm": maxf(es.decode_u16(p + 2), es.decode_u16(p)), "volume": es.decode_u16(p + 6),
			"rate": roundi(es.decode_u32(p + 8) * 44100.0 / 4096.0), "from": head + es.decode_u32(p + 12)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.from < b.from)
	for k in out.size():
		out[k].to = mini(out[k + 1].from if k + 1 < out.size() else head + total, es.size())
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.rpm < b.rpm)
	return out


## Sample `k`'s share at `rpm`: full at its own rpm, fading (equal power) into its neighbours'.
static func _es_share(samples: Array[Dictionary], k: int, rpm: float) -> float:
	var at: float = samples[k].rpm
	if rpm <= at:
		if k == 0:
			return 1.0
		var below: float = samples[k - 1].rpm
		return sin(clampf((rpm - below) / maxf(at - below, 1.0), 0.0, 1.0) * PI * 0.5)
	if k == samples.size() - 1:
		return 1.0
	var above: float = samples[k + 1].rpm
	return cos(clampf((rpm - at) / maxf(above - at, 1.0), 0.0, 1.0) * PI * 0.5)


## Sony ADPCM (VAG) from `from` to `to` as 16-bit PCM: 16-byte frames of a byte of predictor
## (high nibble) and shift (low), a flags byte, and 28 4-bit samples.
static func _vag(d: PackedByteArray, from: int, to: int) -> PackedByteArray:
	const F0 := [0, 60, 115, 98, 122]
	const F1 := [0, 0, -52, -55, -60]
	var out := PackedByteArray()
	out.resize((to - from) / 16 * 28 * 2)
	var o := 0
	var s1 := 0
	var s2 := 0
	for f in range(from, to - 15, 16):
		var pred := mini(d[f] >> 4, 4)
		var shift := d[f] & 15
		var f0: int = F0[pred]
		var f1: int = F1[pred]
		for i in 28:
			var nib := (d[f + 2 + (i >> 1)] >> ((i & 1) * 4)) & 15
			var t := nib << 12
			if t & 0x8000:
				t -= 0x10000
			var v := (t >> shift) + ((s1 * f0 + s2 * f1 + 32) >> 6)
			v = clampi(v, -32768, 32767)
			s2 = s1
			s1 = v
			out.encode_s16(o, v)
			o += 2
		if d[f + 1] & 1 and f > from:
			break
	out.resize(o)
	return out


# ---------------------------------------------------------------- the lamps

## A lamp face's texels: this much of its texel box (a fraction) lit, ...
const LAMP_SHARE := 0.1
## ... a texel lit where the night texture (.cnp) is this much brighter (0..1) than the day's.
const NIGHT_GAIN := 0.15
## Lamp faces this near each other (m, between their middles) make one lamp.
const LAMP_GAP := 0.3


## GT2 has no lamp positions: the headlamps are the faces at the front its night texture
## lights up, the tail and brake lamps those it flags as brake lamps (palette 14, 15 when
## braking); one lamp per huddle of them, a huddle in the middle (a high stop lamp) a brake
## lamp only. Their faces take COLOR (0, 1, 1), car.gdshader's lens mark (and the "lenses"
## meta tells Car its own guess isn't wanted).
func _find_lamps(day: PackedByteArray, night: PackedByteArray) -> void:
	if body_parts.is_empty():
		return
	var heads: Array[Dictionary] = []
	var rears: Array[Dictionary] = []
	var brighter := _night_gains(day, night) if night.size() >= 0x43A0 + PAGE.x * PAGE.y / 2 else PackedByteArray()
	for f in _faces:
		if f.brake and f.center.z < 0.0:
			rears.append(f)
		elif not brighter.is_empty() and f.center.z > 0.0:
			var r: Rect2i = f.uv
			var n := 0
			for y in range(r.position.y, mini(r.end.y + 1, PAGE.y)):
				for x in range(r.position.x, mini(r.end.x + 1, PAGE.x)):
					var i := 0x43A0 + y * PAGE.x / 2 + x / 2
					var sh := (x & 1) * 4
					n += brighter[f.pal * 256 + ((day[i] >> sh) & 15) * 16 + ((night[i] >> sh) & 15)]
			if n > LAMP_SHARE * (r.size.x + 1) * (r.size.y + 1):
				heads.append(f)
	for h in _huddles(heads):
		lights.append(_lamp("HWYN", h))
	for h in _huddles(rears):
		if absf(h.x) > 0.2:
			lights.append(_lamp("TRYN", h))
		lights.append(_lamp("BRYN", h))
	if lights.is_empty():
		return
	var mesh: ArrayMesh = body_parts[0].mesh
	var arrays := mesh.surface_get_arrays(0)
	var cols := PackedColorArray()
	cols.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	cols.fill(Color.WHITE)
	for f in heads + rears:
		for i in range(f.first, f.first + f.count):
			cols[i] = Color(0.0, 1.0, 1.0)
	arrays[Mesh.ARRAY_COLOR] = cols
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	set_meta("lenses", true)


static func _lamp(code: String, at: Vector3) -> Dictionary:
	var l := Nfs3Car.decode_light(code)
	l.pos = at
	return l


## Per palette, day colour * 16 + night colour: 1 where the night's (first paint) is
## NIGHT_GAIN brighter than the day's.
static func _night_gains(day: PackedByteArray, night: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(16 * 256)
	for pal in 16:
		for a in 16:
			var da := _luma(day.decode_u16(0x20 + pal * 32 + a * 2))
			for b in 16:
				var nb := _luma(night.decode_u16(0x20 + pal * 32 + b * 2))
				out[pal * 256 + a * 16 + b] = 1 if nb > da + NIGHT_GAIN else 0
	return out


static func _luma(c: int) -> float:
	return ((c & 31) + ((c >> 5) & 31) + ((c >> 10) & 31)) / 93.0


## The middles of the huddles of `faces` (each face joins the first huddle within LAMP_GAP).
static func _huddles(faces: Array[Dictionary]) -> Array[Vector3]:
	var sums: Array[Vector3] = []
	var counts: Array[int] = []
	for f in faces:
		var c: Vector3 = f.center
		var k := 0
		while k < sums.size() and (sums[k] / counts[k]).distance_to(c) > LAMP_GAP:
			k += 1
		if k == sums.size():
			sums.append(Vector3.ZERO)
			counts.append(0)
		sums[k] += c
		counts[k] += 1
	var out: Array[Vector3] = []
	for k in sums.size():
		out.append(sums[k] / counts[k])
	return out


## GT2's space (Y up, the front -Z, the left -X) to ours (facing +Z, the left +X).
static func _to_car(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, -v.z)


static func _s10(u: int) -> int:
	var x := u & 0x3FF
	return (x ^ 0x200) - 0x200


## A wheel about its hub along X, its face (the rim's picture) outward (+X on the left):
## tread and sidewalls rubber, the rim disc as big as GT2's rim to tyre (about two thirds).
static func _wheel(r: float, w: float, left: bool) -> ArrayMesh:
	const SEG := 20
	var out := 1.0 if left else -1.0
	var rim_r := r * 0.68
	# (Arrays: a lambda would only add to its own copy of a packed array.)
	var pos := []
	var nrm := []
	var uv := []
	var rubber := Vector2(ATLAS.x - 2, FLAT_Y + 14) / Vector2(ATLAS)
	var rim_c := (Vector2(GUTTER, GUTTER) + RIM.get_center()) / Vector2(ATLAS)
	var rim_s := RIM.size.x * 0.5 / ATLAS.x
	var rim_t := RIM.size.y * 0.5 / ATLAS.y
	var tri := func(a: Vector3, b: Vector3, c: Vector3, n: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
		# Clockwise seen from where `n` points (Godot's front).
		if (b - a).cross(c - a).dot(n) > 0.0:
			var t := b
			b = c
			c = t
			var tu := ub
			ub = uc
			uc = tu
		pos.append_array([a, b, c])
		nrm.append_array([n, n, n])
		uv.append_array([ua, ub, uc])
	for i in SEG:
		var a0 := TAU * i / SEG
		var a1 := TAU * (i + 1) / SEG
		var d0 := Vector3(0, cos(a0), sin(a0))
		var d1 := Vector3(0, cos(a1), sin(a1))
		var xo := Vector3(w * 0.5 * out, 0, 0)
		var xi := -xo
		# Tread.
		tri.call(xo + d0 * r, xi + d0 * r, xi + d1 * r, (d0 + d1).normalized(), rubber, rubber, rubber)
		tri.call(xo + d0 * r, xi + d1 * r, xo + d1 * r, (d0 + d1).normalized(), rubber, rubber, rubber)
		# Outer sidewall (rim_r..r), a touch inset, and the rim disc.
		var n_out := Vector3(out, 0, 0)
		var xs := xo * 0.85
		tri.call(xo + d0 * r, xo + d1 * r, xs + d1 * rim_r, n_out, rubber, rubber, rubber)
		tri.call(xo + d0 * r, xs + d1 * rim_r, xs + d0 * rim_r, n_out, rubber, rubber, rubber)
		var u0 := rim_c + Vector2(d0.z * rim_s * out, -d0.y * rim_t)
		var u1 := rim_c + Vector2(d1.z * rim_s * out, -d1.y * rim_t)
		tri.call(xs, xs + d0 * rim_r, xs + d1 * rim_r, n_out, rim_c, u0, u1)
		# Inner side, plain rubber.
		tri.call(xi, xi + d0 * r, xi + d1 * r, -n_out, rubber, rubber, rubber)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(pos)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(nrm)
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(uv)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ---------------------------------------------------------------- the texture

## Paint `k`'s texture (k: an index into colours), made when first asked for: Car swaps it
## in for the chosen paint, the tint left white, so two-tones and liveries are as the game
## has them.
func paint_texture(k: int) -> Texture2D:
	k = clampi(k, 0, maxi(_paint_of.size() - 1, 0))
	if not _paint_textures.has(k) and not _cdp.is_empty():
		_paint_textures[k] = _read_texture(_cdp, _paint_of, k, _flats)
	return _paint_textures.get(k)


## Each of the record's colours' paint in the .cdp: the one with its palette id (else in order).
static func _paints_in(cdp: PackedByteArray, rec: Dictionary) -> PackedInt32Array:
	var n_paints := clampi(cdp.decode_u16(0), 1, 16)
	var ids := cdp.slice(2, 2 + n_paints)
	var out := PackedInt32Array()
	for k in rec.colours.size():
		var at := ids.find(rec.colours[k].palette)
		out.append(at if at >= 0 else mini(k, n_paints - 1))
	if out.is_empty():
		out.append(0)
	return out


## The atlas (see CELL) in paint `k`'s colours: each palette's copy of the texture, colour 0
## see-through, the colours that change from paint to paint marked as paint (PAINT_ALPHA);
## the flat colours below, and the rubber.
static func _read_texture(cdp: PackedByteArray, paint_of: PackedInt32Array, k: int, flats: Array[Color]) -> Texture2D:
	var lut := PackedByteArray()
	lut.resize(16 * 16 * 4)
	for pal in 16:
		for e in 16:
			var raw := cdp.decode_u16(0x20 + paint_of[k] * 0x240 + pal * 32 + e * 2)
			var c := _bgr555(raw)
			var a := 0 if raw == 0 else PAINT_ALPHA if _is_paint(cdp, paint_of, pal, e) else 255
			var o := (pal * 16 + e) * 4
			lut[o] = c.r8
			lut[o + 1] = c.g8
			lut[o + 2] = c.b8
			lut[o + 3] = a
	var atlas := Image.create_empty(ATLAS.x, ATLAS.y, false, Image.FORMAT_RGBA8)
	var px := cdp.slice(0x43A0, 0x43A0 + PAGE.x * PAGE.y / 2)
	for pal in 16:
		var data := PackedByteArray()
		data.resize(PAGE.x * PAGE.y * 4)
		var base := pal * 64
		var o := 0
		for b in px:
			var i0 := base + (b & 15) * 4
			var i1 := base + (b >> 4) * 4
			data[o] = lut[i0]
			data[o + 1] = lut[i0 + 1]
			data[o + 2] = lut[i0 + 2]
			data[o + 3] = lut[i0 + 3]
			data[o + 4] = lut[i1]
			data[o + 5] = lut[i1 + 1]
			data[o + 6] = lut[i1 + 2]
			data[o + 7] = lut[i1 + 3]
			o += 8
		var page := Image.create_from_data(PAGE.x, PAGE.y, false, Image.FORMAT_RGBA8, data)
		# The page, and round it its edge texels stretched over the margins.
		var at := Vector2i(CELL.x * (pal % 4), CELL.y * (pal / 4))
		for side in [[Rect2i(0, 0, PAGE.x, 1), Rect2i(GUTTER, 0, PAGE.x, GUTTER)],
				[Rect2i(0, PAGE.y - 1, PAGE.x, 1), Rect2i(GUTTER, GUTTER + PAGE.y, PAGE.x, GUTTER)],
				[Rect2i(0, 0, 1, PAGE.y), Rect2i(0, GUTTER, GUTTER, PAGE.y)],
				[Rect2i(PAGE.x - 1, 0, 1, PAGE.y), Rect2i(GUTTER + PAGE.x, GUTTER, GUTTER, PAGE.y)],
				[Rect2i(0, 0, 1, 1), Rect2i(0, 0, GUTTER, GUTTER)],
				[Rect2i(PAGE.x - 1, 0, 1, 1), Rect2i(GUTTER + PAGE.x, 0, GUTTER, GUTTER)],
				[Rect2i(0, PAGE.y - 1, 1, 1), Rect2i(0, GUTTER + PAGE.y, GUTTER, GUTTER)],
				[Rect2i(PAGE.x - 1, PAGE.y - 1, 1, 1), Rect2i(GUTTER + PAGE.x, GUTTER + PAGE.y, GUTTER, GUTTER)]]:
			var edge := page.get_region(side[0])
			edge.resize(side[1].size.x, side[1].size.y, Image.INTERPOLATE_NEAREST)
			atlas.blit_rect(edge, Rect2i(Vector2i.ZERO, side[1].size), at + side[1].position)
		atlas.blit_rect(page, Rect2i(Vector2i.ZERO, PAGE), at + Vector2i(GUTTER, GUTTER))
	for f in flats.size():
		var c := flats[f]
		atlas.fill_rect(Rect2i((f % (ATLAS.x / 4)) * 4, FLAT_Y + (f / (ATLAS.x / 4)) * 4, 4, 4), Color(c.r, c.g, c.b, 1.0))
	atlas.fill_rect(Rect2i(ATLAS.x - 4, FLAT_Y + 12, 4, 4), RUBBER)
	atlas.generate_mipmaps()
	return ImageTexture.create_from_image(atlas)


## Whether palette `pal`'s colour `e` changes from paint to paint (the bodywork, its stripes
## and liveries; not trim, glass or lamps).
static func _is_paint(cdp: PackedByteArray, paint_of: PackedInt32Array, pal: int, e: int) -> bool:
	var first := cdp.decode_u16(0x20 + paint_of[0] * 0x240 + pal * 32 + e * 2)
	for k in range(1, paint_of.size()):
		if cdp.decode_u16(0x20 + paint_of[k] * 0x240 + pal * 32 + e * 2) != first:
			return true
	return false
