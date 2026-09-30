class_name Nfs5Car
extends Nfs3Car
## A Need for Speed: Porsche Unleashed car, as the same data an NFS3 or High Stakes car
## gives (Nfs3Car): the model from GameData/Carmodel/<model>.crp, its driving model from
## GameData/Simulation/Cardata/<sim>.sim, and its showroom figures from
## FeData/Locale/<locale>.loc; FeData/Data/nfs5.car ties them together (see car_table).
##
## One CRP holds every version of a model (coupé, targa, cabriolet, turbo...): its .tpg's
## [styleN] sections pick, per geometry slot, which of the slot's variants a version shows
## (a variant the model hasn't got hides the slot), and the car table gives each car its
## style. Its textures are small images the game packs into texture pages at the positions
## their FSH headers give (the .tpg says which file goes on which page, the first page
## mirrored for the car's other side); materials pick a page. Here the pages go into one
## atlas, the car's skin, painted like High Stakes' skins (see _paint_page).

## Porsche Unleashed's model is in metres, front towards -Z: turned round to face +Z.
const PART_LEVEL := 1
## Base info "level index" byte of the parts drawn: bodywork, decals, the interior seen
## through the windows (its own glass left out), wipers, spoilers, steering wheel, wheels,
## the driver and passenger (in their rest frame: see _read_model). Not
## the engine bay and boot (0x1D), the insides of the lids (0x1E), the aerial (0x1C) or
## 0x12: the treads and "SpoilerW", a copy of the lowered spoiler that would fight it.
const SHOWN_LEVELS := [0x1A, 0x18, 0x19, 0x1B, 0x10, 0x49, 0x22, 0x81, 0x89]
## What turns with the steering (car.gdshader, UV2.x): the steering wheel (its level) and
## the driver's hands on it (their geometry slot).
const STEER_LEVEL := 0x49
const HANDS_SLOT := 56
## The people (levels 0x81 the driver, 0x89 the passenger), drawn apart in car_driver.gdshader.
const PEOPLE_LEVELS := [0x81, 0x89]
## Who drives: geometry slot 9 picks one of ten (1 and 6 in race suit and helmet, the others
## in their own clothes, their faces and outfits from head.fsh and suit.fsh), slot 43 the
## arms and legs, slot 56 the hands (1 gloved, 2 bare). The game picks them itself where a
## style doesn't say (most don't: the seat would be empty); the styles that do pair driver 1
## with arms 1 and gloves, driver 3 with bare hands.
const DRIVER_SLOT := 9
## The arms' and hands' first frames: the steering sweep, from full lock one way to the other.
const STEER_FRAMES := 10
const LIMBS_SLOT := 43
const SUITED_DRIVERS := [1, 6]
## The Carreras' rear spoiler (geometry slot 42): the style picks it lowered (an odd
## variant); the next variant is it raised, which the car shows at speed.
const SPOILER_SLOT := 42
## Level 0x1E's parts that are outside: a cabriolet's soft top (slot 37) and the hood's
## frame and rear window, or the hood folded (41), each shown when its style picks it.
const CABRIO_TOP_SLOT := 37
const HOOD_SLOT := 41
const CABRIO_SLOTS := [CABRIO_TOP_SLOT, HOOD_SLOT]
## The cabriolets race with their tops down (Game's setting; the styles have them up).
static var hood_down := true
## Base info byte 6, signed: how far the game biases a part's depth (the decals, badges and
## lamp lenses -3 and the door handles -10 lie on the bodywork; the interior +3 behind
## it). car.gdshader moves each vertex toward the eye by this share of its distance per
## step (UV2.y): the depth changes, not where it's drawn. The interior goes back further:
## its headlining touches the roof and the cabin's walls the doors from inside.
const DEPTH_BIAS_STEP := 0.0005
const DEPTH_BIAS_STEP_BACK := 0.003
const INTERIOR_LEVELS := [0x19, 0x1B, 0x49, 0x81, 0x89]
## Wheel types 0..3 (base info byte 4): front left, front right, rear left, rear right; the
## wheels' shadows and treads have geometry types from here on.
const WHEEL_SHADOW_GEOM := 18
## The exterior's paint: the game paints by alpha, 204 the body colour and 77, 153, 166,
## 179 and 230 the stripes and trims of its paint schemes (the .clr's other colours); here
## they all take the body colour. 255 is unpainted (lamps, badges), 0 cut out.
const PAINT_ALPHA := Vector2i(70, 240)
## The window page's painted rim (204), and its see-through pane (128) which alone is glass.
const WINDOW_RIM_ALPHA := Vector2i(180, 230)
const WINDOW_PANE_ALPHA := Vector2i(90, 170)
const ATLAS_WIDTH := 512
## Paints for the cars without a .clr (the traffic): plain period colours.
const STOCK_PAINTS := [Color8(200, 200, 196), Color8(40, 44, 52), Color8(150, 30, 28), Color8(30, 60, 120),
	Color8(40, 90, 60), Color8(200, 190, 150), Color8(110, 110, 115), Color8(230, 230, 225)]
const RECORD_SIZE := 1648

var model := ""        # the CRP model's name
var style := 0         # its .tpg style index
var sim := ""          # the .sim's name
var _geometry := {}    # geometry slot -> the variant its style shows (0 when it doesn't say)
var _textures := {}    # texture slot -> the variant of its images its style shows
var _window_pages := {}   # page -> its image as the game has it (before _paint_page), for the window pages


## FeData/Data/nfs5.car: [{index, name, model, sim, style, locale, price, showroom}], the
## traffic's ("Eden", "EAS") with no driving model (sim "").
static func car_table(pu_root: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var path := DataPath.find_ci(pu_root.get_base_dir(), "FeData/Data/nfs5.car")
	var d := FileAccess.get_file_as_bytes(path) if path != "" else PackedByteArray()
	for i in d.size() / RECORD_SIZE:
		var r := i * RECORD_SIZE
		var rec := {
			"index": i, "name": _c_string(d, r + 2).strip_edges(), "locale": _c_string(d, r + 77),
			"model": _c_string(d, r + 127), "sim": _c_string(d, r + 177), "showroom": _c_string(d, r + 227),
			"style": d[r + 448], "price": d.decode_u32(r + 520), "sound": _c_string(d, r + 377),
		}
		if rec.model != "":
			out.append(rec)
	return out


static func load_car(pu_root: String, rec: Dictionary) -> Nfs5Car:
	var c := Nfs5Car.new()
	c.id = "pu_" + rec.sim.to_lower()
	c.display_name = _display_name(rec.name)
	c.model = rec.model
	c.style = rec.style
	c.sim = rec.sim
	var cdir := DataPath.find_ci(pu_root, "Carmodel")
	var crp := Crp.load_file(DataPath.find_ci(cdir, rec.model + ".crp"))
	if crp.error != "":
		c.error = crp.error
		return c
	c._read_spec(pu_root, rec)
	var tpg := _ini(FileAccess.get_file_as_string(DataPath.find_ci(cdir, rec.model + ".tpg")))
	c._read_style(tpg)
	c._pick_people(crp)
	var pages := c._pages(crp, tpg, cdir)
	c._read_model(crp, tpg, pages)
	c._read_colours(DataPath.find_ci(cdir, rec.model + ".clr"))
	c._read_sounds(pu_root, rec.get("sound", ""))
	if rec.sim == "":
		# Traffic: as heavy as its size says (the buses and the pickup).
		var l := c.half_size.z * 2.0
		c.carp[2] = PackedFloat32Array([clampf(1300.0 * pow(l / 4.4, 3.0), 900.0, 11000.0)])
	return c


## The spec without the model, for the menus' lists.
static func peek(pu_root: String, rec: Dictionary) -> Nfs5Car:
	var c := Nfs5Car.new()
	c.id = "pu_" + rec.sim.to_lower()
	c.display_name = _display_name(rec.name)
	c.sim = rec.sim
	c.style = rec.style
	c.model = rec.model
	c._read_spec(pu_root, rec)
	return c


## The model year of a car table name ("'94 911 ..."), or 0.
static func _year(n: String) -> int:
	var full := _display_name(n)
	return int(full.substr(0, 4)) if full.substr(0, 4).is_valid_int() else 0


## "'94 911 Carrera Coupé (993)" -> "1994 911 Carrera Coupé (993)".
static func _display_name(n: String) -> String:
	if n.begins_with("'") and n.length() > 3 and n.substr(1, 2).is_valid_int():
		var yy := int(n.substr(1, 2))
		return "%d%s" % [1900 + yy if yy >= 40 else 2000 + yy, n.substr(3)]
	return n


# ---------------------------------------------------------------- driving model

## The .sim (328 bytes: the name, then floats) as carp.txt fields: mass (kg) @0x40,
## wheelbase (mm) @0x44, forward gears @0x50, the AWD front share (%) @0x5C, gear ratios
## from reverse @0x60 (reverse, neutral, up to 6 forward), final drive @0x80, tyre width
## (mm), aspect (%) and rim (in) @0x84, top speed (mph) @0x90, redline @0x94, torque (lb ft)
## every 500 rpm from 0 @0x9C (up to 20), grip @0xF4 and braking (m/s²) @0x104. The
## showroom's layout (front, mid or rear engine) gives the weight split, its tyres each
## axle's size.
func _read_spec(pu_root: String, rec: Dictionary) -> void:
	if rec.sim == "":
		_traffic_spec()
		return
	var sim_path := DataPath.find_ci(pu_root, "Simulation/Cardata/" + rec.sim + ".sim")
	if sim_path == "":
		sim_path = _sim_anagram(pu_root, rec.sim)
	var d := FileAccess.get_file_as_bytes(sim_path) if sim_path != "" else PackedByteArray()
	info = _read_locale(pu_root, rec)
	info.price = "$%d" % rec.price if rec.price > 0 else ""
	if d.size() < 0x110:
		error = "missing " + rec.sim + ".sim"
		return
	var f := func(o: int) -> float: return d.decode_float(o)
	var mph := 0.44704
	var gears := clampi(d.decode_s32(0x50), 1, 6)
	var ratios := PackedFloat32Array([absf(f.call(0x60)), 0.0])
	for g in 6:
		ratios.append(f.call(0x68 + g * 4) if g < gears else 0.0)
	var fd: float = f.call(0x80)
	var width: float = f.call(0x84)
	var aspect: float = f.call(0x88)
	var rim: float = f.call(0x8C)
	var top: float = f.call(0x90) * mph
	var redline: float = f.call(0x94)
	# Torque every 500 rpm (lb ft) -> every 256 rpm (N m).
	var tq := PackedFloat32Array()
	for k in 20:
		var v: float = f.call(0x9C + k * 4)
		if v <= 0.0:
			break
		tq.append(v * 1.3558)
	var curve := PackedFloat32Array()
	if tq.size() >= 2:
		for i in int(tq.size() * 500.0 / 256.0):
			var x := minf(i * 256.0 / 500.0, tq.size() - 1.0)
			var k := mini(int(x), tq.size() - 2)
			curve.append(lerpf(tq[k], tq[k + 1], x - k))
	var radius := rim * 0.0254 * 0.5 + width * aspect / 100000.0
	var v2rpm := PackedFloat32Array()
	for i in ratios.size():
		var r: float = ratios[i] * fd * 60.0 / (TAU * maxf(radius, 0.2))
		v2rpm.append(-r if i == 0 else r)
	var layout: String = info.get("layout", "").to_lower()
	var weight_front := 0.4 if layout.begins_with("rear") else 0.46 if layout.begins_with("mid") else 0.5
	var front_share: float = clampf(f.call(0x5C) / 100.0, 0.0, 1.0)
	if layout.contains("all-wheel") or layout.contains("4-wheel") or layout.contains("four"):
		front_share = maxf(front_share, 0.3)
	elif layout.contains("front-drive"):
		front_share = 1.0
	var grip: float = f.call(0xF4)
	var brake: float = f.call(0x104)
	var mass: float = f.call(0x40)
	var power := 0.0
	for i in curve.size():
		power = maxf(power, curve[i] * i * 256.0 * TAU / 60.0)
	carp = {
		0: PackedFloat32Array([500 + rec.index]),
		1: PackedFloat32Array([_class_of(power, mass)]),
		2: PackedFloat32Array([mass]),
		3: PackedFloat32Array([gears + 2]),
		7: v2rpm, 8: ratios,
		10: curve,
		11: PackedFloat32Array([fd]),
		12: PackedFloat32Array([900.0]),
		13: PackedFloat32Array([redline]),
		14: PackedFloat32Array([top]),
		15: PackedFloat32Array([top]),
		16: PackedFloat32Array([front_share]),
		17: PackedFloat32Array([1.0 if _year(rec.name) >= 1985 else 0.0]),
		18: PackedFloat32Array([clampf(brake, 5.0, 12.0) if brake > 0.0 else 9.0]),
		24: PackedFloat32Array([f.call(0x44) / 1000.0]),
		25: PackedFloat32Array([weight_front]),
		30: PackedFloat32Array([3.2 * clampf(0.55 + 0.45 * grip / 1.8, 0.7, 1.35) if grip > 0.0 else 3.2]),
		35: _tyre(info.get("tyres_front", ""), width, aspect, rim),
		36: _tyre(info.get("tyres_rear", ""), width, aspect, rim),
	}


## The car table names one car's .sim with its letters out of order (993coupeS436 for the
## file 993coupe4s36): the file with the same letters, or "".
static func _sim_anagram(pu_root: String, sim: String) -> String:
	var dir := DataPath.find_ci(pu_root, "Simulation/Cardata")
	var want := Array(sim.to_lower().split(""))
	want.sort()
	for f in (DirAccess.get_files_at(dir) if dir != "" else PackedStringArray()):
		if f.get_extension().to_lower() != "sim":
			continue
		var have := Array(f.get_basename().to_lower().split(""))
		have.sort()
		if have == want:
			return dir.path_join(f)
	return ""


## Traffic has no driving model: an ordinary saloon's (about 110 kW, four gears).
func _traffic_spec() -> void:
	var curve := PackedFloat32Array()
	for i in 24:
		var rpm := i * 256.0
		curve.append(lerpf(120.0, 190.0, clampf(rpm / 3500.0, 0.0, 1.0)) * (1.0 - 0.4 * clampf((rpm - 4500.0) / 1500.0, 0.0, 1.0)))
	carp = {
		1: PackedFloat32Array([3.0]), 2: PackedFloat32Array([1300.0]), 3: PackedFloat32Array([6.0]),
		8: PackedFloat32Array([3.5, 0.0, 3.5, 2.1, 1.4, 1.0, 0.0, 0.0]), 10: curve,
		11: PackedFloat32Array([3.9]), 13: PackedFloat32Array([6000.0]), 14: PackedFloat32Array([50.0]),
		15: PackedFloat32Array([50.0]), 18: PackedFloat32Array([8.0]), 24: PackedFloat32Array([2.6]),
		35: PackedFloat32Array([195.0, 65.0, 15.0]), 36: PackedFloat32Array([195.0, 65.0, 15.0]),
	}
	var radius := 15 * 0.0254 * 0.5 + 195.0 * 65.0 / 100000.0
	var v2rpm := PackedFloat32Array()
	for r: float in carp[8]:
		v2rpm.append(r * 3.9 * 60.0 / (TAU * radius))
	v2rpm[0] = -v2rpm[0]
	carp[7] = v2rpm


## "205/55 ZR 16" -> [205, 55, 16], else the .sim's size.
static func _tyre(s: String, width: float, aspect: float, rim: float) -> PackedFloat32Array:
	var m := RegEx.create_from_string("(\\d{3})\\s*/\\s*(\\d{2})\\D*(\\d{2})").search(s)
	if m:
		return PackedFloat32Array([float(m.get_string(1)), float(m.get_string(2)), float(m.get_string(3))])
	return PackedFloat32Array([width, aspect, rim])


## NFS3's classes by power to weight (W/kg): A (0) the quickest, C (2) the slowest.
static func _class_of(power: float, mass: float) -> float:
	var pw := power / maxf(mass, 500.0)
	return 0.0 if pw > 180.0 else 1.0 if pw > 95.0 else 2.0


## The showroom's figures (the English part of FeData/Locale/<locale>.loc): engine,
## displacement, power, torque, 0-60, top speed, weight, length, width, height, wheelbase,
## redline, compression, layout, brakes (front, rear), rims (front, rear), tyres (front,
## rear), the gear ratios, final drive, reverse, gearbox, transmission.
static func _read_locale(pu_root: String, rec: Dictionary) -> Dictionary:
	var out := {"name": _display_name(rec.name), "make": "Porsche", "model": _display_name(rec.name).substr(5)}
	var path := DataPath.find_ci(pu_root.get_base_dir(), "FeData/Locale/" + rec.locale + ".loc")
	var d := FileAccess.get_file_as_bytes(path) if path != "" else PackedByteArray()
	var strings: Array[String] = []
	var cur := ""
	for b in d:
		if b >= 32 and b < 127 or b >= 160:
			cur += char(b)
		else:
			if cur.length() >= 1:
				strings.append(cur)
			cur = ""
	var first := strings.find("American")
	if first < 0:
		return out
	var s := strings.slice(first + 1)
	var end := s.find("LOCL")
	if end >= 0:
		s = s.slice(0, end)
	var keys := ["engine", "displacement", "power", "torque", "zero_60", "top_speed", "weight",
		"length", "width", "height", "wheelbase", "redline", "compression", "layout",
		"brakes", "brakes_rear", "rims", "rims_rear", "tyres_front", "tyres_rear"]
	for i in mini(keys.size(), s.size()):
		out[keys[i]] = s[i]
	if s.size() >= 2:
		out.gearbox = s[s.size() - 2]
		out.transmission = s[s.size() - 1]
	out.tyres = "%s, %s" % [out.get("tyres_front", ""), out.get("tyres_rear", "")]
	if out.has("zero_60"):
		out.zero_60 = out.zero_60 + " s"
	return out


# ---------------------------------------------------------------- textures

## A minimal INI reader: {section: {key: value}}, all lower case.
static func _ini(text: String) -> Dictionary:
	var out := {}
	var sec := {}
	out[""] = sec
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			# A section can come twice (993's [file5.glai]): the keys add up.
			var sname := line.substr(1, line.length() - 2).to_lower()
			if not out.has(sname):
				out[sname] = {}
			sec = out[sname]
		elif "=" in line:
			sec[line.get_slice("=", 0).strip_edges().to_lower()] = line.substr(line.find("=") + 1).strip_edges()
	return out


## The style's [styleN] section: "geometryK=slot, typeK=variant" picks a part variant per
## geometry slot, "textureK=slot, typeK=variant" a texture variant per texture slot.
func _read_style(tpg: Dictionary) -> void:
	var st: Dictionary = tpg.get("style%d" % (style + 1), {})
	for k in 64:
		if st.has("geometry%d" % k):
			_geometry[int(st["geometry%d" % k])] = int(st.get("type%d" % k, "0"))
		if st.has("texture%d" % k):
			_textures[int(st["texture%d" % k])] = int(st.get("type%d" % k, "0"))
	# A cabriolet (its style shows a soft top, slot 37): slot 41's variants come in pairs,
	# the hood's frame and rear window (odd) and the hood folded behind the seats (the
	# next, even). The styles mix them (the 964's top up over a folded hood, a gap behind
	# it; the Boxster's none): up, the top and the pair's odd one; down, the folded one alone.
	if _geometry.get(CABRIO_TOP_SLOT, 0) != 0:
		var hood: int = _geometry.get(HOOD_SLOT, 0)
		var pair := maxi((hood + 1) / 2, 1)
		if hood_down:
			_geometry[CABRIO_TOP_SLOT] = 0
			_geometry[HOOD_SLOT] = pair * 2
		else:
			_geometry[HOOD_SLOT] = pair * 2 - 1


## Who sits in the car where its style doesn't say (DRIVER_SLOT): the suited driver, with
## his arms and gloves. Only on models with the ten drivers; the traffic's one driver is
## variant 0 of the slot, and the police have none.
func _pick_people(crp: Crp) -> void:
	var drivers := false
	for art in crp.articles:
		var base := crp.sub(art, "Base")
		if base != null and crp.data[base.offset + 68] == DRIVER_SLOT and crp.data[base.offset + 69] > 0:
			drivers = true
			break
	if not drivers:
		return
	var driver: int = _geometry.get(DRIVER_SLOT, 1)
	_geometry[DRIVER_SLOT] = driver
	if not _geometry.has(LIMBS_SLOT):
		_geometry[LIMBS_SLOT] = 1
	if not _geometry.has(HANDS_SLOT):
		_geometry[HANDS_SLOT] = 1 if driver in SUITED_DRIVERS else 2


## Whether the race draws texture file `fi`'s image `name`. Its [fileN.name] section, if
## any, says when: on the style's geometry or texture variants ("countN" conditions, any
## one will do: badge det3 when texture slot 22 is 3, the roof's top2 when the roof slot's
## variant is 3), and only in the showroom ("frontend=1": the sharp wheels, the clear
## glass), the test drive ("testdrive=1") or with the lights on at night ("night=1": the
## lit dials). The images a variant replaces share its place on the page.
func _image_wanted(name: String, tpg: Dictionary, fi: int) -> bool:
	var sec: Dictionary = tpg.get("file%d.%s" % [fi + 1, name.strip_edges().to_lower()], {})
	if sec.is_empty():
		return true
	if sec.get("frontend", "0") == "1" or sec.get("testdrive", "0") == "1" or sec.get("night", "0") == "1":
		return false
	var n := int(sec.get("count", "0"))
	if n == 0:
		return true
	for k in range(1, n + 1):
		var t := int(sec.get("type%d" % k, "0"))
		if sec.has("geometry%d" % k) and _geometry.get(int(sec["geometry%d" % k]), 0) == t:
			return true
		if sec.has("texture%d" % k) and _textures.get(int(sec["texture%d" % k]), 0) == t:
			return true
	return false


## The car's texture pages as one atlas: sets `texture` and returns each page's rect in it
## (UV units), by page index. Page N is filled from the file the .tpg puts on it: the
## CRP's "sf" entry N-1 of the car's own, or a shared file in Carmodel ("global").
func _pages(crp: Crp, tpg: Dictionary, cdir: String) -> Array[Rect2]:
	var n_pages := int(tpg.get("header", {}).get("numtpages", "0"))
	var n_files := int(tpg.get("header", {}).get("numfiles", "0"))
	var images: Array[Image] = []
	for p in n_pages:
		var det: Dictionary = tpg.get("tpage%d.details" % (p + 1), {})
		var img := Image.create(maxi(int(det.get("width", "64")), 8), maxi(int(det.get("height", "64")), 8), false, Image.FORMAT_RGBA8)
		img.fill(Color(0.5, 0.5, 0.5, 1.0))
		images.append(img)
	var sf := {}
	for e in crp.misc_of("sf"):
		sf[e.index] = e
	for fi in n_files:
		var det: Dictionary = tpg.get("file%d.details" % (fi + 1), {})
		var page := int(det.get("tpage", "0")) - 1
		if page < 0 or page >= images.size():
			continue
		var bytes := PackedByteArray()
		if det.has("global"):
			var fname: String = tpg.header.get("file%d" % (fi + 1), "")
			var p := DataPath.find_ci(cdir, fname)
			bytes = FileAccess.get_file_as_bytes(p) if p != "" else PackedByteArray()
		elif sf.has(fi):
			bytes = crp.data.slice(sf[fi].offset, sf[fi].offset + sf[fi].length)
		if bytes.is_empty():
			continue
		_fill_page(images[page], Qfs.decompress(bytes), Vector2i(int(det.get("offsetx", "0")), int(det.get("offsety", "0"))),
			_image_wanted.bind(tpg, fi))
		if fi == 0:
			_paint_page(images[page])
	# The windows' page: the pane (alpha 128) round which runs the black seal (255) and a
	# rim painted the body colour (204), which the window triangles along the roof show.
	for p in n_pages:
		if tpg.get("tpage%d.details" % (p + 1), {}).get("window", "0") == "1":
			_window_pages[p] = images[p].duplicate()
			_paint_page(images[p], WINDOW_RIM_ALPHA)
	# Copied pages ("sourcetpage"): the other side of the car, mirrored by its UVs.
	for p in n_pages:
		var det: Dictionary = tpg.get("tpage%d.details" % (p + 1), {})
		var src := int(det.get("sourcetpage", "0")) - 1
		if src >= 0 and src < images.size():
			images[p] = images[src].duplicate()
	# Shelf-pack the pages into one atlas, tallest first.
	var order := range(images.size())
	order.sort_custom(func(a: int, b: int) -> bool: return images[a].get_height() > images[b].get_height())
	var at := {}
	var x := 0
	var y := 0
	var row_h := 0
	for p: int in order:
		var im := images[p]
		if x + im.get_width() > ATLAS_WIDTH:
			x = 0
			y += row_h
			row_h = 0
		at[p] = Vector2i(x, y)
		x += im.get_width()
		row_h = maxi(row_h, im.get_height())
	var h := 8
	while h < y + row_h:
		h *= 2
	var atlas := Image.create(ATLAS_WIDTH, h, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.5, 0.5, 0.5, 1.0))
	var rects: Array[Rect2] = []
	for p in images.size():
		atlas.blit_rect(images[p], Rect2i(Vector2i.ZERO, images[p].get_size()), at[p])
		rects.append(Rect2(Vector2(at[p]) / Vector2(ATLAS_WIDTH, h), Vector2(images[p].get_size()) / Vector2(ATLAS_WIDTH, h)))
	atlas.generate_mipmaps()
	texture = ImageTexture.create_from_image(atlas)
	damage_texture = _damage_atlas(tpg, cdir, images, at, atlas.get_size())
	return rects


## The crumpled paint a crash shows (car.gdshader blends it in as a panel bends): the
## model's <model>d.fsh, grey creases drawn over the exterior page and its mirror (the
## car's other side) where its images' headers place them, in the skin's layout. Its
## images come in pairs at each place: the first for the page, the second for the mirror.
## Transparent everywhere else; null without the file.
func _damage_atlas(tpg: Dictionary, cdir: String, pages: Array[Image], at: Dictionary, size: Vector2i) -> Texture2D:
	var path := DataPath.find_ci(cdir, model + "d.fsh")
	var raw := FileAccess.get_file_as_bytes(path) if path != "" else PackedByteArray()
	var fsh := Fsh.from_bytes(raw) if not raw.is_empty() else null
	var ext := int(tpg.get("file1.details", {}).get("tpage", "0")) - 1
	if fsh == null or ext < 0 or ext >= pages.size():
		return null
	var d := Qfs.decompress(raw)
	if fsh.images.size() != d.decode_s32(8):
		return null
	var mirror := int(tpg.get("tpage%d.details" % (ext + 1), {}).get("mirrortpage", "0")) - 1
	var atlas := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var seen := {}
	for i in fsh.images.size():
		var off := d.decode_s32(20 + i * 8)
		var p := Vector2i(d.decode_u16(off + 12) & 0x3FF, d.decode_u16(off + 14) & 0x3FF)
		var img: Image = fsh.images[i]
		var page := ext if not seen.has(p) else mirror
		seen[p] = true
		if page < 0 or page >= pages.size() or not at.has(page):
			continue
		if img.get_format() != Image.FORMAT_RGBA8:
			img = img.duplicate()
			img.convert(Image.FORMAT_RGBA8)
		var r := Rect2i(Vector2i.ZERO, img.get_size()).intersection(Rect2i(-p, pages[page].get_size()))
		atlas.blit_rect(img, r, at[page] + p + r.position)
	atlas.generate_mipmaps()
	return ImageTexture.create_from_image(atlas)


## Draws an FSH's images onto `page` where their headers place them (bytes 12, 14 of the
## image header: x, y), those `wanted` (name) -> bool. Variants of one image share a place
## ("det", "det1"... the badges, of different widths): the first drawn of those stays.
static func _fill_page(page: Image, d: PackedByteArray, offset: Vector2i, wanted: Callable) -> void:
	var fsh := Fsh.from_bytes(d)
	if fsh == null:
		return
	var pos := {}
	for i in d.decode_s32(8):
		var name := d.slice(16 + i * 8, 20 + i * 8).get_string_from_ascii()
		var off := d.decode_s32(20 + i * 8)
		if off + 16 <= d.size():
			pos[name] = Vector2i(d.decode_u16(off + 12) & 0x3FF, d.decode_u16(off + 14) & 0x3FF)
	var taken := {}
	for i in fsh.names.size():
		if not wanted.call(fsh.names[i]):
			continue
		var img: Image = fsh.images[i]
		var p: Vector2i = pos.get(fsh.names[i], Vector2i.ZERO) + offset
		if taken.has(p):
			continue
		taken[p] = true
		if img.get_format() != Image.FORMAT_RGBA8:
			img = img.duplicate()
			img.convert(Image.FORMAT_RGBA8)
		page.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), p)


## The exterior page to the car shader's convention (NFS3's skins): the paint is mid-grey
## with a mid alpha; the game's is near-white at ~204. Its texels with alpha in `paint`.
static func _paint_page(img: Image, paint := PAINT_ALPHA) -> void:
	var d := img.get_data()
	for k in range(0, d.size(), 4):
		var a := d[k + 3]
		if a >= paint.x and a <= paint.y:
			for c in 3:
				d[k + c] = d[k + c] / 2
			d[k + 3] = 117
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, d)


# ---------------------------------------------------------------- model

## The parts of the car's style at full detail: the body and glass as one mesh each (car
## space), the wheels as one each around their hubs, the lamps from its glare effects.
func _read_model(crp: Crp, tpg: Dictionary, pages: Array[Rect2]) -> void:
	var want := _geometry
	# Glass: the window material, and anything on a page the .tpg marks "window" (the
	# inner panes of the windows use the interior's material on it).
	var mats := {}   # material -> [page, glass]
	for e in crp.misc_of("mt"):
		if e.length >= 44:
			var rm := crp.data.slice(e.offset + 16, e.offset + 32).get_string_from_ascii()
			var page := crp.data.decode_s32(e.offset + 40)
			var window: bool = tpg.get("tpage%d.details" % (page + 1), {}).get("window", "0") == "1"
			mats[e.index] = [page, rm == "CarWindow" or window]
	var body := _Mesh.new()
	var glass := _Mesh.new()
	var people := _Mesh.new()   # the driver and passenger
	# Pop-up headlamps: the "HeadLight" part. The 914's and 944's are modelled down in the
	# body and rise by the .tpg's headlightextent (m) while the lights are on; the 928's
	# (a negative extent) are modelled up, and fold back flat about their hinge (the part's
	# origin), lenses to the sky, while they're off.
	var popup_rise := float(tpg.get("header", {}).get("headlightextent", "0"))
	var popup := _Mesh.new()
	var popup_hinge := Vector3.ZERO
	var spoiler_down := _Mesh.new()
	var spoiler_up := _Mesh.new()
	var wheel_meshes: Array = [null, null, null, null]
	var wheel_hubs: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	for art in crp.articles:
		var base := crp.sub(art, "Base")
		if base == null:
			continue
		var bi := crp.data.slice(base.offset + 68, base.offset + 84)
		var ef := crp.sub(art, "ef")
		if ef != null:
			_add_light(crp, ef, art.name, _transform(crp, crp.sub(art, "tr")).origin)
			continue
		var lvl := bi[10]
		if lvl not in SHOWN_LEVELS and not (lvl == 0x1E and bi[0] in CABRIO_SLOTS):
			continue
		var slot := bi[0]
		var variant := bi[1]
		var raised: bool = slot == SPOILER_SLOT and want.get(slot, 0) % 2 == 1 and variant == want.get(slot, 0) + 1
		# Slot 0 is the parts every version has (doors, mirrors, wipers): their variant 0.
		if variant != want.get(slot, 0) and not raised:
			continue
		var wheel := bi[4] if bi[4] < 4 else -1
		if wheel >= 0 and bi[7] >= WHEEL_SHADOW_GEOM:
			continue
		# The people's bodies, arms and hands are animated: frames of vertices (and normals)
		# at the level's index + frame << 4, a steering sweep (the right arm's gear change
		# after it); base info byte 8 counts them, byte 9 is the one at rest, hands level on
		# the rim. Frame 0 is at full lock.
		var frame := PART_LEVEL
		if lvl in PEOPLE_LEVELS and bi[8] > 1 and crp.sub(art, "vt", PART_LEVEL | bi[9] << 4) != null:
			frame = PART_LEVEL | bi[9] << 4
		var vt := crp.sub(art, "vt", frame)
		if vt == null:
			continue
		var xf := _transform(crp, crp.sub(art, "tr", PART_LEVEL))
		var verts := crp.vec3s(vt)   # X mirrored, undone below: parts move in the game's own space
		# Its damaged copy (the level's index + 0x8000): how far each vertex moves in a crash.
		var dented := crp.vec3s(crp.sub(art, "vt", PART_LEVEL | 0x8000))
		if dented.size() == verts.size():
			for i in verts.size():
				dented[i] += verts[i]
		else:
			dented = verts
		var uvs := crp.uvs(crp.sub(art, "uv", PART_LEVEL))
		# The model's own normals ("nm", one per vertex): smooth where the panels curve.
		var normals := crp.vec3s(crp.sub(art, "nm", frame))
		if normals.size() != verts.size():
			normals = PackedVector3Array()
		var z_bias := (bi[6] ^ 0x80) - 0x80
		var bias := -z_bias * (DEPTH_BIAS_STEP if z_bias < 0 else DEPTH_BIAS_STEP_BACK)
		var into: _Mesh = people if lvl in PEOPLE_LEVELS else body
		# An arm or hand's steering sweep (people.sweep): its side, and its frames with
		# their normals. The body, legs and passenger stay as they are.
		var side := -1
		var sweep: Array[PackedVector3Array] = []
		var sweep_n: Array[PackedVector3Array] = []
		if into == people and bi[8] >= STEER_FRAMES and (art.name.begins_with("Left") or art.name.begins_with("Right")):
			for f in STEER_FRAMES:
				sweep.append(crp.vec3s(crp.sub(art, "vt", PART_LEVEL | f << 4)))
				sweep_n.append(crp.vec3s(crp.sub(art, "nm", PART_LEVEL | f << 4)))
				if sweep[f].size() != verts.size():
					sweep.clear()
					break
			if not sweep.is_empty():
				side = 0 if art.name.begins_with("Left") else 1
				people.side_rest[side] = bi[9]
		# (Hands with a sweep follow the wheel by it, not by turning with it.)
		var steers := 1.0 if lvl == STEER_LEVEL else 0.75 if slot == HANDS_SLOT and side < 0 else 0.0
		if slot == SPOILER_SLOT and want.get(slot, 0) % 2 == 1:
			into = spoiler_up if raised else spoiler_down
		if popup_rise != 0.0 and art.name == "HeadLight":
			into = popup
			popup_hinge = _to_car(xf.origin)
		if wheel >= 0:
			if wheel_meshes[wheel] != null:
				continue
			wheel_meshes[wheel] = _Mesh.new()
			into = wheel_meshes[wheel]
			wheel_hubs[wheel] = _to_car(xf.origin)
			xf.origin = Vector3.ZERO
		for k in 256:
			var pe := crp.sub(art, "pr", PART_LEVEL << 12 | k)
			if pe == null:
				break
			var p := crp.part(pe)
			var m: Array = mats.get(p.material, [0, false])
			if m[1] and lvl in INTERIOR_LEVELS:
				continue   # the windows from inside: the outside's glass is see-through already
			var rect: Rect2 = pages[m[0]] if m[0] >= 0 and m[0] < pages.size() else Rect2(0, 0, 0, 0)
			var vi: PackedInt32Array = p.vertex
			var ui: PackedInt32Array = p.uv
			for t3 in range(0, vi.size() - 2, 3):
				var dst: _Mesh = into
				if m[1] and wheel < 0:
					dst = glass if _on_pane(m[0], uvs, ui, t3) else body
				for c in [0, 2, 1]:
					var v := verts[vi[t3 + c]] if vi[t3 + c] < verts.size() else Vector3.ZERO
					var dv := dented[vi[t3 + c]] if vi[t3 + c] < dented.size() else v
					dst.pos.append(_to_car(xf * Vector3(-v.x, v.y, v.z)))
					if not normals.is_empty():
						var n := normals[vi[t3 + c]] if vi[t3 + c] < normals.size() else Vector3.ZERO
						dst.nrm.append(_to_car(xf.basis * Vector3(-n.x, n.y, n.z)).normalized())
					else:
						dst.nrm.append(Vector3.ZERO)
					dst.dent.append(_to_car(xf * Vector3(-dv.x, dv.y, dv.z)))
					var uv := uvs[ui[t3 + c]] if ui.size() > t3 + c and ui[t3 + c] < uvs.size() else Vector2.ZERO
					dst.uv.append(rect.position + uv.clamp(Vector2.ZERO, Vector2.ONE) * rect.size)
					dst.bias.append(bias)
					dst.steer.append(steers)
					if dst == people:
						var at := vi[t3 + c]
						for f in STEER_FRAMES:
							var fv := sweep[f][at] if side >= 0 and at < sweep[f].size() else v
							var fn := sweep_n[f][at] if side >= 0 and at < sweep_n[f].size() else Vector3.ZERO
							people.frames[f].append(_to_car(xf * Vector3(-fv.x, fv.y, fv.z)))
							people.frame_nrm[f].append(_to_car(xf.basis * Vector3(-fn.x, fn.y, fn.z)).normalized())
						people.side.append(side)
						people.hand.append(1 if slot == HANDS_SLOT else 0)
	# Centre the model on its body, as the FCE models are.
	var box := body.box()
	var mid := box.get_center()
	body.panelise(box)
	glass.panelise(box)
	half_size = box.size * 0.5
	var hb := {"name": ":hb", "mesh": body.commit(-mid), "center": Vector3.ZERO, "damaged": body.damaged(-mid)}
	var column := body.steering_column()
	var steer_angles := people.sweep(column)
	if not column.is_empty():
		column.pivot -= mid
		hb.steering = column
	body_parts.append(hb)
	# (A lowered spoiler without a raised one just stays down.)
	for sp: Array in [[spoiler_down, "down"], [spoiler_up, "up"]]:
		if sp[0].pos.is_empty():
			continue
		sp[0].panelise(box)
		var part := {"name": "spoiler_" + sp[1], "mesh": sp[0].commit(-mid), "center": Vector3.ZERO,
			"damaged": sp[0].damaged(-mid)}
		if not spoiler_up.pos.is_empty():
			part.spoiler = sp[1]
		body_parts.append(part)
	if not popup.pos.is_empty():
		var down := popup if popup_rise > 0.0 else popup.turned(Basis(Vector3.RIGHT, -PI / 2.0), popup_hinge)
		var up_at := Vector3(0.0, popup_rise, 0.0) if popup_rise > 0.0 else Vector3.ZERO
		down.panelise(box)
		body_parts.append({"name": "popup_closed", "mesh": down.commit(-mid), "center": Vector3.ZERO,
			"popup_closed": true, "damaged": down.damaged(-mid)})
		popup_lights.append({"name": "popup", "mesh": popup.commit(-mid), "center": up_at})
	if not people.pos.is_empty():
		# They don't dent: no "damaged". Their arms and hands follow the wheel by blend
		# shapes, one per angle in "steer_shapes" (car.gdshader's steer_angle); without a
		# sweep the hands turn with it on the wheel's column.
		var dp := {"name": "driver", "mesh": people.commit(-mid), "center": Vector3.ZERO, "driver": true}
		if hb.has("steering"):
			dp.steering = hb.steering
		if not steer_angles.is_empty():
			dp.steer_shapes = steer_angles
		body_parts.append(dp)
	if not glass.pos.is_empty():
		body_parts.append({"name": "glass", "mesh": glass.commit(-mid), "center": Vector3.ZERO, "glass": true,
			"damaged": glass.damaged(-mid)})
	for w in 4:
		if wheel_meshes[w] != null:
			wheels.append({"name": "wheel%d" % w, "mesh": wheel_meshes[w].commit(Vector3.ZERO), "center": wheel_hubs[w] - mid})
	for l in lights:
		l.pos -= mid


## Whether the triangle at `t3` of a window material's part lies on the see-through pane
## of its page, by the texel under its middle: the seal and the painted rim round it are
## solid bodywork. Pages other than the window page are all glass.
func _on_pane(page: int, uvs: PackedVector2Array, ui: PackedInt32Array, t3: int) -> bool:
	var img: Image = _window_pages.get(page)
	if img == null or ui.size() < t3 + 3:
		return true
	var c := Vector2.ZERO
	for k in 3:
		c += uvs[ui[t3 + k]] if ui[t3 + k] < uvs.size() else Vector2.ZERO
	c = (c / 3.0).clamp(Vector2.ZERO, Vector2.ONE) * Vector2(img.get_size() - Vector2i.ONE)
	var a := int(img.get_pixel(int(c.x), int(c.y)).a8)
	return a >= WINDOW_PANE_ALPHA.x and a <= WINDOW_PANE_ALPHA.y


## Porsche Unleashed's car space (left-handed, front towards -Z) to ours: facing +Z, its
## left (+X) stays our left, so only Z turns over.
static func _to_car(v: Vector3) -> Vector3:
	return Vector3(v.x, v.y, -v.z)


## A part's "tr" matrix in the game's space: D3D row vectors, so its rows are the basis
## columns and the fourth row the translation.
func _transform(crp: Crp, e: Crp.Entry) -> Transform3D:
	if e == null:
		return Transform3D.IDENTITY
	var f := crp.data.slice(e.offset, e.offset + 64).to_float32_array()
	return Transform3D(Basis(Vector3(f[0], f[1], f[2]), Vector3(f[4], f[5], f[6]), Vector3(f[8], f[9], f[10])),
		Vector3(f[12], f[13], f[14]))


## A glare effect as an NFS3 light dummy: headlights white, brake and tail lights red,
## reverse lights white at the back; mirrored ones on both sides.
func _add_light(crp: Crp, e: Crp.Entry, name: String, offset: Vector3) -> void:
	var d := crp.data
	var o := e.offset
	if o + 0x58 > d.size():
		return
	var pos := _to_car(offset + Vector3(d.decode_float(o + 8), d.decode_float(o + 12), d.decode_float(o + 16)))
	var kind := d[o + 84]
	var head := d[o + 87] == 1
	var n := name.to_lower()
	var dname := ""
	if n.contains("siren"):
		# The light bar: red on the left, blue on the right, flashing in turn (Car's sirens).
		dname = "SML" if pos.x >= 0.0 else "SMR"
	elif head or n.contains("headlight"):
		dname = "HFLN"
	elif kind == 1 or n.contains("brake"):
		dname = "TRLN"
	else:
		return
	var mirrored := d.decode_u32(o + 80) != 0
	for side in ([1.0, -1.0] if mirrored else [1.0]):
		var p := Vector3(pos.x * side, pos.y, pos.z)
		var l := Nfs3Car.decode_light(("SML" if p.x >= 0.0 else "SMR") + "N" if dname.begins_with("S") else dname)
		l.pos = p
		lights.append(l)


## The engine: GameData/Sounds/<set>.viv (the car table names the set) holds a bank and
## High Stakes' engine tables (AudioEng, "CRDl"), the engine's (.ect off the throttle, .elt
## on it: its recordings at different revs, the exhaust's from patch 64) and the intake's
## (.cct, .clt). The engine's go to CarAudio as High Stakes' careng.ctb and careng.ltb.
func _read_sounds(pu_root: String, set_name: String) -> void:
	if set_name == "":
		return
	var viv := Viv.load_file(DataPath.find_ci(pu_root, "Sounds/" + set_name + ".viv"))
	if viv == null:
		return
	var s := set_name.to_lower()
	var bnk := viv.get_file(s + ".bnk")
	if bnk.is_empty():
		return
	sound_files["careng.bnk"] = bnk
	sound_files["careng.ctb"] = viv.get_file(s + ".ect")
	sound_files["careng.ltb"] = viv.get_file(s + ".elt")


## The .clr's paints: each section's first colour. It's there twice, as hue, saturation
## and value (0-255 each) and as RGB, but the RGB is often stale or zero (15 of the 996's
## 20 paints read black): the HSV is the one to go by.
func _read_colours(path: String) -> void:
	var ini := _ini(FileAccess.get_file_as_string(path)) if path != "" else {}
	for k in range(1, 32):
		var sec: Dictionary = ini.get("section%d" % k, {})
		if sec.has("color1.h") or sec.has("color1.r"):
			# At double strength over the mid-grey paint, as Nfs3Car's colours.
			var c := Color.from_hsv(int(sec["color1.h"]) / 255.0, int(sec.get("color1.s", "0")) / 255.0,
				int(sec.get("color1.v", "0")) / 255.0) if sec.has("color1.h") \
				else Color8(int(sec["color1.r"]), int(sec["color1.g"]), int(sec["color1.b"]))
			colours.append(Color(c.r * 2.0, c.g * 2.0, c.b * 2.0))
	if colours.is_empty():
		for c: Color in STOCK_PAINTS:
			colours.append(Color(c.r * 2.0, c.g * 2.0, c.b * 2.0))
	info.colours = []
	for i in colours.size():
		info.colours.append("Colour %d" % (i + 1))


class _Mesh:
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var bias := PackedFloat32Array()     # the part's depth bias (DEPTH_BIAS_STEP), as UV2.y
	var nrm := PackedVector3Array()      # the model's normal, or zero for the face's
	var steer := PackedFloat32Array()    # UV2.x: 1 the steering wheel, 0.75 the hands on it (both turn), 0
	var dent := PackedVector3Array()     # each vertex in the damaged copy
	# The people's steering sweep: each vertex in each of the arms' and hands' frames (where
	# it is at rest on the parts that don't move), the side (0 left, 1 right, -1 none) and
	# whether it's a hand; each side's rest frame. sweep() makes blend shapes of them.
	var frames: Array[PackedVector3Array] = []
	var frame_nrm: Array[PackedVector3Array] = []
	var side := PackedInt32Array()
	var hand := PackedByteArray()
	var side_rest := {}
	var shapes: Array[PackedVector3Array] = []
	var shape_nrm: Array[PackedVector3Array] = []

	func _init() -> void:
		for f in STEER_FRAMES:
			frames.append(PackedVector3Array())
			frame_nrm.append(PackedVector3Array())
	var panels := PackedInt32Array()     # the panel (bit) each vertex is on

	func box() -> AABB:
		if pos.is_empty():
			return AABB(Vector3(-0.9, 0.0, -2.2), Vector3(1.8, 1.3, 4.4))
		var b := AABB(pos[0], Vector3.ZERO)
		for p in pos:
			b = b.expand(p)
		return b

	## Panels for CarDamage, which bends a panel at a time: the car cut in three along its
	## length, in two across and in two up. By where each vertex is, so the corners that
	## triangles share (they're stored once per triangle) move together and don't tear apart.
	func panelise(box: AABB) -> void:
		panels.resize(pos.size())
		for i in pos.size():
			var c := (pos[i] - box.position) / box.size.max(Vector3.ONE * 0.01)
			panels[i] = 1 << (clampi(int(c.z * 3.0), 0, 2) * 4 + clampi(int(c.x * 2.0), 0, 1) * 2 + clampi(int(c.y * 2.0), 0, 1))

	## The steering wheel's column, for car.gdshader: {pivot (the wheel's middle), axis
	## (through its face, pointing forward)}, or {} without one. The axis is the wheel's
	## triangles' normals summed by area, each turned forward (it's a ring seen from both
	## sides); the hands don't count.
	func steering_column() -> Dictionary:
		var n := Vector3.ZERO
		var b := AABB()
		var first := true
		for i in range(0, pos.size() - 2, 3):
			if steer[i] < 1.0:
				continue
			var fn := (pos[i + 2] - pos[i]).cross(pos[i + 1] - pos[i])
			n += fn if fn.z >= 0.0 else -fn
			for k in 3:
				b = AABB(pos[i + k], Vector3.ZERO) if first else b.expand(pos[i + k])
				first = false
		if first or n.length_squared() < 1e-12:
			return {}
		return {"pivot": b.get_center(), "axis": n.normalized()}

	## A copy turned by `basis` about `pivot` (car space), its damaged copy with it.
	func turned(basis: Basis, pivot: Vector3) -> _Mesh:
		var m := _Mesh.new()
		m.uv = uv
		m.bias = bias
		m.steer = steer
		for i in pos.size():
			m.pos.append(pivot + basis * (pos[i] - pivot))
			m.dent.append(pivot + basis * (dent[i] - pivot))
			m.nrm.append(basis * nrm[i])
		return m

	## Triangle i's (its first corner's) face normal, facing out as Godot's winding does.
	static func _face(v: PackedVector3Array, i: int) -> Vector3:
		return (v[i + 2] - v[i]).cross(v[i + 1] - v[i]).normalized()

	## The shading normals: the model's, turned to the side its triangle faces (the few
	## that point the other way), or the face's where it has none.
	func _normals() -> PackedVector3Array:
		return _shading(pos, nrm)

	static func _shading(p: PackedVector3Array, nm: PackedVector3Array) -> PackedVector3Array:
		var out := PackedVector3Array()
		out.resize(p.size())
		for i in range(0, p.size() - 2, 3):
			var fn := _face(p, i)
			for k in 3:
				var n := nm[i + k]
				out[i + k] = fn if n == Vector3.ZERO else (n if n.dot(fn) >= 0.0 else -n)
		return out

	## The steering sweep as blend shapes (`shapes`), returning the wheel angle each is at
	## (ascending; + about the column's axis by the right-hand rule, as car.gdshader turns
	## the wheel), or [] without a sweep. Each side's frames are at the angle its hands are
	## turned from their rest frame about the column; the two sides' angles differ, so both
	## are resampled at every angle either has (within the range both reach).
	func sweep(column: Dictionary) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		if column.is_empty() or side_rest.is_empty():
			return out
		var axis: Vector3 = column.axis
		var angles := {}   # side -> PackedFloat32Array per frame
		for s: int in side_rest:
			var ref := _hand_dir(s, int(side_rest[s]), column)
			if ref == Vector3.ZERO:
				continue
			var a := PackedFloat32Array()
			for f in STEER_FRAMES:
				var d := _hand_dir(s, f, column)
				a.append(atan2(axis.dot(ref.cross(d)), ref.dot(d)))
			angles[s] = a
		if angles.is_empty():
			return out
		var lo := -INF
		var hi := INF
		for s: int in angles:
			var a: PackedFloat32Array = angles[s]
			lo = maxf(lo, Array(a).min())
			hi = minf(hi, Array(a).max())
		var grid := {}
		for s: int in angles:
			for g in angles[s]:
				if g >= lo - 1e-4 and g <= hi + 1e-4:
					grid[snappedf(g, 1e-4)] = true
		var keys: Array = grid.keys()
		keys.sort()
		if keys.size() < 2:
			return out
		for g: float in keys:
			var p := PackedVector3Array()
			var n := PackedVector3Array()
			p.resize(pos.size())
			n.resize(pos.size())
			for i in pos.size():
				var s := side[i]
				if not angles.has(s):
					p[i] = pos[i]
					n[i] = nrm[i]
					continue
				var fw := _between(angles[s], g)
				var f0 := int(fw.x)
				var f1 := int(fw.y)
				p[i] = frames[f0][i].lerp(frames[f1][i], fw.z)
				n[i] = frame_nrm[f0][i].lerp(frame_nrm[f1][i], fw.z)
			shapes.append(p)
			shape_nrm.append(_shading(p, n))
			out.append(g)
		return out

	## Where side `s`'s hands are in frame `f`, from the column's middle, flat across it.
	func _hand_dir(s: int, f: int, column: Dictionary) -> Vector3:
		var c := Vector3.ZERO
		var n := 0
		for i in pos.size():
			if side[i] == s and hand[i] == 1:
				c += frames[f][i]
				n += 1
		if n == 0:
			return Vector3.ZERO
		var axis: Vector3 = column.axis
		var pivot: Vector3 = column.pivot
		var d := c / n - pivot
		return d - axis * axis.dot(d)

	## The two frames (x, y) whose angles in `a` bracket `g`, and how far (z) from x to y.
	static func _between(a: PackedFloat32Array, g: float) -> Vector3:
		var best := Vector3(0, 0, 0)
		var gap := INF
		for f in a.size():
			for h in a.size():
				if a[f] <= g and g <= a[h] and a[h] - a[f] < gap:
					gap = a[h] - a[f]
					best = Vector3(f, h, 0.0 if gap < 1e-6 else (g - a[f]) / gap)
		return best

	## CarDamage's view of the damaged copy: {pos, normal, panels}; the normal is the
	## smooth one turned as far as its triangle turns in the dent.
	func damaged(offset: Vector3) -> Dictionary:
		var p := PackedVector3Array()
		var n := PackedVector3Array()
		p.resize(dent.size())
		n.resize(dent.size())
		var rest := _normals()
		for i in range(0, dent.size() - 2, 3):
			var turn := _face(dent, i) - _face(pos, i)
			for k in 3:
				p[i + k] = dent[i + k] + offset
				n[i + k] = (rest[i + k] + turn).normalized()
		return {"pos": p, "normal": n, "panels": panels}

	func commit(offset: Vector3) -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var normals := _normals()
		for i in pos.size():
			st.set_uv(uv[i])
			st.set_uv2(Vector2(steer[i], bias[i]))
			st.set_normal(normals[i])
			st.add_vertex(pos[i] + offset)
		if shapes.is_empty():
			return st.commit()
		# The steering sweep, one blend shape per angle (normalized: a pose between two is
		# their weights summing to 1).
		var arrays := st.commit_to_arrays()
		var mesh := ArrayMesh.new()
		mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
		var blends := []
		for k in shapes.size():
			mesh.add_blend_shape("steer%d" % k)
			var b := []
			b.resize(Mesh.ARRAY_MAX)
			var p := PackedVector3Array()
			p.resize(shapes[k].size())
			for i in p.size():
				p[i] = shapes[k][i] + offset
			b[Mesh.ARRAY_VERTEX] = p
			b[Mesh.ARRAY_NORMAL] = shape_nrm[k]
			blends.append(b)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blends)
		return mesh
