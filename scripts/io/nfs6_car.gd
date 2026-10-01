class_name Nfs6Car
extends Nfs3Car
## Loads a Need for Speed: Hot Pursuit 2 car (Cars/<name>/): car.viv's car.o (EAGL model,
## see Eagl) and car.fsh (its wheel textures), skin.viv's skins (skin00.fsh.. one per paint,
## skincop.fsh the police livery), skeleton.o's bones (lamps, exhausts), car.ini's driving
## model and vehicle.ini's paints. Cars/cars.ini lists them, with the names' text ids
## (Text/text.dbg names the strings of Text/text.eng).

## The parts left out: the lower details, and the police car's light bar and push bar unless
## it's the police car. (Names vary from car to car: these are the ones they share.)
const LOD_MARKS := ["LOD", "MIDLOD"]
const ADDON_MARK := "ADDON"
## Paint texels: where the two most different paints' skins differ by more than this
## (summed over R, G and B, 0..765).
const PAINT_DIFF := 60
const PAINT_ALPHA := 117
## _paint_mask's witnesses: paints this saturated (chroma over mean), and how far (sum of rgb shares) a paint
## texel's colour may stray from theirs.
const WITNESS_SAT := 0.5
const WITNESS_HUE := 0.25

var folder := ""          # Cars/<folder>
var traffic := false
var cop := false          # wearing the police livery (skincop.fsh) and light bar
var hp2_class := 0        # cars.ini's class, 1 (the fastest) .. 5
## The skins' paints in the order of colours (skin00..): their swatches, for the paint choice.
var wheel_texture: Texture2D


## Cars/cars.ini: [{index, folder, name, traffic, class, price}], in its order.
static func car_table(hp2_root: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cdir := DataPath.find_ci(hp2_root, "Cars")
	var ini := Nfs5Car._ini(FileAccess.get_file_as_string(DataPath.find_ci(cdir, "cars.ini")) if cdir != "" else "")
	var text := _text(hp2_root)
	for i in 64:
		var sec: Dictionary = ini.get("car%d" % i, {})
		if not sec.has("name"):
			continue
		var f := DataPath.find_ci(cdir, sec["name"])
		if f == "" or DataPath.find_ci(f, "car.viv") == "":
			continue
		var make: String = text.get(sec.get("mfrname", ""), "").strip_edges()
		var model: String = text.get(sec.get("displayname", ""), "").strip_edges()
		var traffic: bool = sec.get("traffic", "false") == "true"
		var name := (make + " " + model).strip_edges() if not traffic else ""
		if name == "" or model == "":
			name = (sec["name"] as String).capitalize()
		out.append({"index": i, "folder": f, "name": name, "make": make, "model": model, "traffic": traffic,
			"class": int(sec.get("class", "3")), "price": int(sec.get("price", "0")),
			"spec": {"zero_60": text.get(sec.get("stat0to60id", ""), ""), "top_mph": text.get(sec.get("stattsid", ""), ""),
				"top_kph": text.get(sec.get("stattskphid", ""), ""), "bhp": text.get(sec.get("stathpid", ""), "")}})
	return out


## Text/text.dbg (the ids) and text.eng (the English strings), id -> string: two tables of
## the same length, each a list of u32 offsets then the zero-terminated strings.
static var _text_cache := {}


static func _text(hp2_root: String) -> Dictionary:
	if _text_cache.has(hp2_root):
		return _text_cache[hp2_root]
	var out := {}
	var tdir := DataPath.find_ci(hp2_root, "Text")
	var ids := _string_table(DataPath.find_ci(tdir, "text.dbg") if tdir != "" else "")
	var eng := _string_table(DataPath.find_ci(tdir, "text.eng") if tdir != "" else "")
	for i in mini(ids.size(), eng.size()):
		out[ids[i]] = eng[i]
	_text_cache[hp2_root] = out
	return out


static func _string_table(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := FileAccess.get_file_as_bytes(path) if path != "" else PackedByteArray()
	if d.size() < 4:
		return out
	var n := d.decode_u32(0) / 4
	for i in n:
		if i * 4 + 4 > d.size():
			break
		out.append(_c_string(d, d.decode_u32(i * 4)))
	return out


static func load_car(rec: Dictionary, as_cop := false) -> Nfs6Car:
	var c := peek(rec, as_cop)
	if c.error != "":
		return c
	var viv := Viv.load_file(DataPath.find_ci(c.folder, "car.viv"))
	if viv == null:
		c.error = "missing car.viv"
		return c
	var model := Eagl.parse(viv.get_file("car.o"))
	if model.error != "":
		c.error = "car.o: " + model.error
		return c
	var car_fsh := Fsh.from_bytes(viv.get_file("car.fsh")) if viv.files.has("car.fsh") else null
	c._read_textures(Viv.load_file(DataPath.find_ci(c.folder, "skin.viv")), car_fsh)
	c._read_model(model, Nfs5Car._ini(FileAccess.get_file_as_string(DataPath.find_ci(c.folder, "geomdata.ini"))))
	c._read_damage_texture(viv.get_file("damage.fsh"))
	c._read_skeleton(Eagl.parse(viv.get_file("skeleton.o")))
	c._read_sounds()
	return c


## The spec without the model, for the menus' lists.
static func peek(rec: Dictionary, as_cop := false) -> Nfs6Car:
	var c := Nfs6Car.new()
	c.folder = rec.folder
	c.id = "hp2_" + (rec.folder as String).get_file().to_lower()
	c.display_name = rec.name
	c.traffic = rec.traffic
	c.cop = as_cop
	c.hp2_class = rec["class"]
	c.info = {"name": rec.name, "make": rec.make, "model": rec.model}
	var spec: Dictionary = rec.spec
	if spec.bhp != "":
		c.info.power = spec.bhp + " bhp"
	if spec.top_mph != "":
		c.info.top_speed = "%s mph (%s km/h)" % [spec.top_mph, spec.top_kph]
	if spec.zero_60 != "":
		c.info.zero_60 = spec.zero_60 + " s"
	if rec.price > 0:
		c.info.price = "$%d" % rec.price
	var ini_name := "car_cop.ini" if as_cop and DataPath.find_ci(c.folder, "car_cop.ini") != "" else "car.ini"
	c._read_spec(Nfs5Car._ini(FileAccess.get_file_as_string(DataPath.find_ci(c.folder, ini_name))))
	c._read_paints(Nfs5Car._ini(FileAccess.get_file_as_string(DataPath.find_ci(c.folder, "vehicle.ini"))))
	var bounds := Nfs5Car._ini(FileAccess.get_file_as_string(DataPath.find_ci(c.folder, "bounds.ini")))
	var b: Dictionary = bounds.get("boundsnormal", {})
	if b.has("max_x"):
		c.half_size = Vector3(float(b.max_x), (float(b.max_y) - float(b.min_y)) * 0.5, float(b.max_z))
	return c


# ---------------------------------------------------------------- driving model

## car.ini as carp.txt fields: [basic] mass (kg), wheelbase (m), FrontDriveRatio, the
## FrontGripBias; [engineblock] RedLine, MinRPM and torqueCurve_N (N m every 500 rpm from 0);
## [transmission] GearRatios_N (reverse, neutral, forward...); [rearend] FinalGearRatio;
## [tire_front]/[tire_rear] SectionWidth, AspectRatio, WheelDiameter (in), PeakFriction;
## [brake_*] ABS.
func _read_spec(ini: Dictionary) -> void:
	var basic: Dictionary = ini.get("basic", {})
	var eng: Dictionary = ini.get("engineblock", {})
	var tr: Dictionary = ini.get("transmission", {})
	var tf: Dictionary = ini.get("tire_front", {})
	var tre: Dictionary = ini.get("tire_rear", {})
	if basic.is_empty() or eng.is_empty():
		_traffic_spec()
		return
	var mass := float(basic.get("mass", "1400"))
	var redline := float(eng.get("redline", "6500"))
	var tq := PackedFloat32Array()
	for k in 24:
		tq.append(float(eng.get("torquecurve_%d" % k, "0")))
	# Up to the last value above zero (the rest are padding), every 500 rpm -> every 256.
	var last := tq.size() - 1
	while last > 1 and tq[last] <= 0.0:
		last -= 1
	tq = tq.slice(0, last + 1)
	# The curves start at 0 below idle; Car reads from 0 rpm, so hold the first torque down there.
	var first := 0
	while first < tq.size() - 1 and tq[first] <= 0.0:
		first += 1
	for k in first:
		tq[k] = tq[first] * 0.6
	var curve := PackedFloat32Array()
	for i in int(tq.size() * 500.0 / 256.0):
		var x := minf(i * 256.0 / 500.0, tq.size() - 1.0)
		var k := mini(int(x), tq.size() - 2)
		curve.append(lerpf(tq[k], tq[k + 1], x - k))
	var n := clampi(int(tr.get("numberofgears", "8")), 3, 8)
	var ratios := PackedFloat32Array()
	for g in 8:
		ratios.append(absf(float(tr.get("gearratios_%d" % g, "0"))) if g < n else 0.0)
	ratios[1] = 0.0
	var gears := 0
	for g in range(2, 8):
		if ratios[g] > 0.0:
			gears += 1
	var fd := float(ini.get("rearend", {}).get("finalgearratio", "3.5"))
	var width := float(tre.get("sectionwidth", "225"))
	var aspect := float(tre.get("aspectratio", "45"))
	var rim := float(tre.get("wheeldiameter", "17"))
	var radius := rim * 0.0254 * 0.5 + width * aspect / 100000.0
	var v2rpm := PackedFloat32Array()
	for i in ratios.size():
		var r: float = ratios[i] * fd * 60.0 / (TAU * maxf(radius, 0.2))
		v2rpm.append(-r if i == 0 else r)
	var power := 0.0
	for i in curve.size():
		power = maxf(power, curve[i] * i * 256.0 * TAU / 60.0)
	# Top speed: where the drag (AeroDragCoefficient over a typical frontal area) eats the power,
	# capped by the top gear at the redline.
	var cd := float(basic.get("aerodragcoefficient", "0.33"))
	var top := pow(power * 0.85 / (0.5 * 1.2 * cd * 2.0), 1.0 / 3.0)
	if gears > 0 and v2rpm[gears + 1] > 0.0:
		top = minf(top, redline / v2rpm[gears + 1])
	var drive_front := clampf(float(basic.get("frontdriveratio", "0")), 0.0, 1.0)
	if basic.get("drivewheels_0", "1") == "0" and basic.get("drivewheels_1", "1") == "0":
		drive_front = 0.0
	var grip := float(tre.get("peakfriction", "1.4"))
	carp = {
		0: PackedFloat32Array([600 + hp2_class]),
		1: PackedFloat32Array([Nfs5Car._class_of(power, mass)]),
		2: PackedFloat32Array([mass]),
		3: PackedFloat32Array([gears + 2]),
		7: v2rpm, 8: ratios,
		10: curve,
		11: PackedFloat32Array([fd]),
		12: PackedFloat32Array([maxf(float(eng.get("minrpm", "900")) * 0.6, 750.0)]),
		13: PackedFloat32Array([redline]),
		14: PackedFloat32Array([top]),
		15: PackedFloat32Array([top]),
		16: PackedFloat32Array([drive_front]),
		17: PackedFloat32Array([1.0 if ini.get("brake_front", {}).get("abs", "1") == "1" else 0.0]),
		18: PackedFloat32Array([clampf(8.0 + (grip - 1.2) * 4.0, 7.0, 12.0)]),
		24: PackedFloat32Array([float(basic.get("wheelbase", "2.6"))]),
		25: PackedFloat32Array([clampf(float(basic.get("frontgripbias", "0.5")), 0.35, 0.6)]),
		30: PackedFloat32Array([3.2 * clampf(0.55 + 0.45 * grip / 1.5, 0.7, 1.35)]),
		35: PackedFloat32Array([float(tf.get("sectionwidth", width)), float(tf.get("aspectratio", aspect)),
			float(tf.get("wheeldiameter", rim))]),
		36: PackedFloat32Array([width, aspect, rim]),
	}
	if traffic:
		carp[0] = PackedFloat32Array([0.0])


## Traffic's car.ini has no driving model: Porsche Unleashed's stand-in saloon's.
func _traffic_spec() -> void:
	var pu := Nfs5Car.new()
	pu._traffic_spec()
	carp = pu.carp


## vehicle.ini's [paintcolorN] swatches (paintr/g/b), one per skinNN: at double strength over
## the mid-grey paint, as Nfs3Car's colours.
var _paint_names: Array[String] = []


func _read_paints(ini: Dictionary) -> void:
	var text := {}
	for k in 16:
		var sec: Dictionary = ini.get("paintcolor%d" % k, {})
		if not sec.has("paintr"):
			break
		var c := Color8(int(sec.paintr), int(sec.paintg), int(sec.paintb))
		colours.append(Color(c.r * 2.0, c.g * 2.0, c.b * 2.0))
		_paint_names.append(sec.get("paintname", ""))
	# Traffic's are placeholders, every one alike (black): no swatches at all, then.
	if colours.size() >= 2 and colours.all(func(c: Color) -> bool: return c.is_equal_approx(colours[0])):
		colours.clear()
		_paint_names.clear()
	info.colours = []
	for i in colours.size():
		info.colours.append("Colour %d" % (i + 1))


# ---------------------------------------------------------------- textures

## The skin with its paint grey and marked (NFS3's convention, which car.gdshader tints with the
## chosen colour): the paint is where the skins of the two most different paints differ; its grey
## is the lighter one's brightness over its swatch's. HP2's alpha is a reflection mask, not a
## cut-out: everything else turns opaque. The police car keeps its livery as it is; traffic
## (whose skins carry no swatches) paints estimated from its skins (_estimate_swatches).
func _read_textures(skins: Viv, car_fsh: Fsh) -> void:
	var imgs: Array[Image] = []
	for k in 16:
		var f := "skin%02d.fsh" % k
		if skins == null or not skins.files.has(f):
			break
		var fsh := Fsh.from_bytes(skins.files[f])
		if fsh == null or fsh.images.is_empty():
			break
		imgs.append(fsh.images[0])
	var cop_img: Image = null
	if cop and skins and skins.files.has("skincop.fsh"):
		var fsh := Fsh.from_bytes(skins.files["skincop.fsh"])
		if fsh and not fsh.images.is_empty():
			cop_img = fsh.images[0]
	if imgs.is_empty() and car_fsh and car_fsh.by_name.has("skin"):
		imgs.append(car_fsh.by_name["skin"])
	if imgs.is_empty():
		return
	var img: Image
	if cop_img:
		img = _opaque(cop_img)
		colours.clear()
	elif colours.size() >= 2 and imgs.size() >= 2:
		# (The swatches themselves, not the double-strength colours: the grey comes out half as bright.)
		var sw: Array[Color] = []
		for c in colours:
			sw.append(Color(c.r * 0.5, c.g * 0.5, c.b * 0.5))
		img = _paint_mask(imgs, sw)
	elif imgs.size() >= 2 and _estimate_swatches(imgs):
		img = _paint_mask(imgs, _swatches)
	else:
		img = _opaque(imgs[0])
		colours.clear()
	img.generate_mipmaps()
	texture = ImageTexture.create_from_image(img)
	if car_fsh and car_fsh.by_name.has("wl00"):
		var w := _opaque(car_fsh.by_name["wl00"])
		w.generate_mipmaps()
		wheel_texture = ImageTexture.create_from_image(w)


## The skins' paints where vehicle.ini names none (the traffic's six skins, a few cars'): the
## two skins whose average colours differ most mark the paint (as _paint_mask), and each skin's
## swatch is its average colour there. False if no paint stands out.
var _swatches: Array[Color] = []


func _estimate_swatches(imgs: Array[Image]) -> bool:
	var data: Array[PackedByteArray] = []
	var means: Array[Color] = []
	for im in imgs:
		var x := im
		if x.get_format() != Image.FORMAT_RGBA8 or x.get_size() != imgs[0].get_size():
			x = im.duplicate() as Image
			x.convert(Image.FORMAT_RGBA8)
			x.resize(imgs[0].get_width(), imgs[0].get_height())
		var px := x.get_data()
		data.append(px)
		var sum := Vector3.ZERO
		var n := 0
		for i in range(0, px.size(), 64):
			sum += Vector3(px[i], px[i + 1], px[i + 2])
			n += 1
		sum /= maxf(n, 1.0) * 255.0
		means.append(Color(sum.x, sum.y, sum.z))
	var a := 0
	var b := 1
	var best := -1.0
	for i in means.size():
		for j in range(i + 1, means.size()):
			var d := Vector3(means[i].r - means[j].r, means[i].g - means[j].g, means[i].b - means[j].b).length()
			if d > best:
				best = d
				a = i
				b = j
	var sums: Array[Vector3] = []
	sums.resize(data.size())
	sums.fill(Vector3.ZERO)
	var n := 0
	var pa := data[a]
	var pb := data[b]
	for i in range(0, pa.size(), 16):
		if absi(pa[i] - pb[i]) + absi(pa[i + 1] - pb[i + 1]) + absi(pa[i + 2] - pb[i + 2]) <= PAINT_DIFF:
			continue
		n += 1
		for k in data.size():
			sums[k] += Vector3(data[k][i], data[k][i + 1], data[k][i + 2])
	if n < 64:
		return false
	_swatches.clear()
	colours.clear()
	for k in data.size():
		var c := sums[k] / (n * 255.0)
		_swatches.append(Color(c.x, c.y, c.z))
		colours.append(Color(c.x * 2.0, c.y * 2.0, c.z * 2.0))
	info.colours = []
	for i in colours.size():
		info.colours.append("Colour %d" % (i + 1))
	return true


## damage.fsh: a tile of scratches and creases, repeated over the skin's layout as the crumpled
## paint (car.gdshader's damage_tex, where it multiplies by 2.6: white leaves the paint be).
func _read_damage_texture(fsh_bytes: PackedByteArray) -> void:
	var fsh := Fsh.from_bytes(fsh_bytes) if not fsh_bytes.is_empty() else null
	if fsh == null or fsh.images.is_empty() or texture == null:
		return
	var tile: Image = fsh.images[0].duplicate()
	tile.convert(Image.FORMAT_RGBA8)
	var px := tile.get_data()
	for i in range(0, px.size(), 4):
		for k in 3:
			px[i + k] = int(px[i + k] / 2.6)
		px[i + 3] = 255
	tile.set_data(tile.get_width(), tile.get_height(), false, Image.FORMAT_RGBA8, px)
	var w := texture.get_width()
	var h := texture.get_height()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(0, h, tile.get_height()):
		for x in range(0, w, tile.get_width()):
			img.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(x, y))
	img.generate_mipmaps()
	damage_texture = ImageTexture.create_from_image(img)


static func _opaque(src: Image) -> Image:
	var img := src.duplicate() as Image
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var px := img.get_data()
	for i in range(3, px.size(), 4):
		px[i] = 255
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, px)
	return img


static func _luma(c: Color) -> float:
	return c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722


static func _paint_mask(imgs: Array[Image], swatches: Array[Color]) -> Image:
	# The pair of paints furthest apart, and of those two the lighter.
	var a := 0
	var b := 1
	var best := -1.0
	for i in mini(imgs.size(), swatches.size()):
		for j in range(i + 1, mini(imgs.size(), swatches.size())):
			var d := Vector3(swatches[i].r - swatches[j].r, swatches[i].g - swatches[j].g, swatches[i].b - swatches[j].b).length()
			if d > best and imgs[i].get_size() == imgs[j].get_size():
				best = d
				a = i
				b = j
	if _luma(swatches[b]) > _luma(swatches[a]):
		var t := a
		a = b
		b = t
	var light := imgs[a].duplicate() as Image
	if light.get_format() != Image.FORMAT_RGBA8:
		light.convert(Image.FORMAT_RGBA8)
	var other := imgs[b]
	if other.get_format() != Image.FORMAT_RGBA8:
		other = other.duplicate() as Image
		other.convert(Image.FORMAT_RGBA8)
	var px := light.get_data()
	var ox := other.get_data()
	# Witnesses: the skins whose paint is strongly coloured (as measured where the pair
	# differ: vehicle.ini's swatches can be off the skins). A texel that's paint is that colour
	# in most of them; one that isn't (a lamp, a number plate: a darker skin can be darker all
	# over, the black McLaren's) keeps its own colour.
	var wit: Array[PackedByteArray] = []
	var wit_hue: Array[Vector3] = []
	var every: Array[PackedByteArray] = []
	for j in imgs.size():
		if imgs[j].get_size() != light.get_size():
			continue
		var w := imgs[j]
		if w.get_format() != Image.FORMAT_RGBA8:
			w = w.duplicate() as Image
			w.convert(Image.FORMAT_RGBA8)
		var wx := w.get_data()
		every.append(wx)
		var mean := Vector3.ZERO
		for i in range(0, px.size(), 16):
			if absi(px[i] - ox[i]) + absi(px[i + 1] - ox[i + 1]) + absi(px[i + 2] - ox[i + 2]) > PAINT_DIFF:
				mean += Vector3(wx[i], wx[i + 1], wx[i + 2])
		var sum := mean.x + mean.y + mean.z
		if sum <= 0.0 or (maxf(mean.x, maxf(mean.y, mean.z)) - minf(mean.x, minf(mean.y, mean.z))) * 3.0 / sum < WITNESS_SAT:
			continue
		wit.append(wx)
		wit_hue.append(mean / sum)
	# (The swatch at double strength: grey * 2 swatch gives back the skin.)
	var k := 255.0 / maxf(_luma(swatches[a]) * 255.0, 1.0)
	for i in range(0, px.size(), 4):
		var diff := absi(px[i] - ox[i]) + absi(px[i + 1] - ox[i + 1]) + absi(px[i + 2] - ox[i + 2])
		var paint := diff > PAINT_DIFF
		var against := 0
		for j in wit.size():
			if not paint:
				break
			var t := Vector3(wit[j][i], wit[j][i + 1], wit[j][i + 2])
			var sum := t.x + t.y + t.z
			# (Too dark to tell its colour: a shadow drawn in the paint.)
			if sum > 60.0 and absf(t.x / sum - wit_hue[j].x) + absf(t.y / sum - wit_hue[j].y) + absf(t.z / sum - wit_hue[j].z) > WITNESS_HUE:
				against += 1
		# (Most of them: a skin can be off its swatch.)
		if paint and against * 2 > wit.size():
			paint = false
		if paint:
			var grey := clampi(int((px[i] * 0.2126 + px[i + 1] * 0.7152 + px[i + 2] * 0.0722) * k * 0.5), 0, 255)
			px[i] = grey
			px[i + 1] = grey
			px[i + 2] = grey
			px[i + 3] = PAINT_ALPHA
		else:
			px[i + 3] = 255
			# Not paint but not the same in every skin either (a moulding's or an arch's edge,
			# just under PAINT_DIFF): a neutral grey as bright as the middle of them, not the
			# light skin's colour whatever the paint.
			var lo := 255
			var hi := 0
			for e in every:
				lo = mini(lo, e[i + 1])
				hi = maxi(hi, e[i + 1])
			if hi - lo > 16 and every.size() >= 3:
				var v: Array[int] = []
				for e in every:
					v.append(int(e[i] * 0.2126 + e[i + 1] * 0.7152 + e[i + 2] * 0.0722))
				v.sort()
				px[i] = v[v.size() / 2]
				px[i + 1] = px[i]
				px[i + 2] = px[i]
	light.set_data(light.get_width(), light.get_height(), false, Image.FORMAT_RGBA8, px)
	return light


# ---------------------------------------------------------------- model

## HP2's space (Y up, the front towards -Z, the driver's side -X) turned round to ours
## (facing +Z, the left +X): half a turn about Y.
static func _to_car(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, -v.z)


## The body (one mesh), its glass (another, see-through) and the four wheels about their hubs.
## The wheels are the RUBBER parts (textured with wl00 where the car has it); the brake discs and calipers ride with
## the body. The body carries the steering wheel (UV2.x 1, turning about its column: "steering")
## and a damaged copy for CarDamage (see _damaged), panel by panel as geomdata.ini's zones.
func _read_model(model: Eagl, geomdata: Dictionary) -> void:
	var body := _Tris.new()
	var glass := _Tris.new()
	var lens := _Tris.new()   # ALPHA_ADD_ glass: lamp covers HP2 adds as a reflection only
	var wheel_parts: Array[Dictionary] = []
	var brake_parts: Array[Dictionary] = []
	for part in model.model_parts("car"):
		if part.geoprim < 0:
			continue
		var pname: String = (part.name as String).to_upper()
		if LOD_MARKS.any(func(m: String) -> bool: return pname.contains(m)) or part.texture == "wlod":
			continue
		if pname.contains(ADDON_MARK) and not cop:
			continue
		var g := model.geoprim(part.geoprim)
		if g.is_empty() or g.indices.is_empty():
			continue
		# (Traffic's tyres are on its skin, the others' on wl00.)
		if pname.contains("RUBBER") and (part.texture == "wl00" or wheel_texture == null) or traffic and _wheel_shaped(g):
			wheel_parts.append({"name": part.name, "g": g})
			continue
		if part.texture == "wl00":
			brake_parts.append(g)   # the brakes: on the wheel texture, riding with their wheels
			continue
		# (ALPHA_ADD_ glass black in its vertex colour is the lamps' covers and the like, which
		# HP2 adds over them as a reflection only: clear glass, not a dark patch of the skin. A
		# lit one, a light bar's, adds its texture: drawn with the body.)
		if pname.contains("ALPHA_ADD_") and _dark_part(g):
			lens.add(g, Vector3.ZERO)
			continue
		var is_glass := pname.contains("TRANS_") or pname.contains("~EASVEHICLEGLASS")
		# Traffic's windows: HP2 blacks them out with their vertex colour, their UVs pointing at
		# a sliver of the skin with anything in it (a number plate's green edge). The vertex
		# colours can't be drawn here (car.gdshader reads COLOR as Porsche Unleashed's): they
		# take the skin's darkest spot instead.
		if traffic and not is_glass and _dark_part(g):
			g = g.duplicate()
			var uv := PackedVector2Array()
			uv.resize((g.uv as PackedVector2Array).size())
			uv.fill(_darkest_uv())
			g.uv = uv
		var zone := int(geomdata.get((part.name as String).to_lower(), {}).get("damagezoneid", "-1"))
		(glass if is_glass else body).add(g, Vector3.ZERO, zone, pname.contains("STEERINGWHEEL"))
	if body.pos.is_empty():
		error = "no body in car.o"
		return
	# The steering wheel's column (SteeringColumn: some cars mark the column or its shroud
	# with the wheel; that stays put). Before commit, as it may stop part of it turning.
	var turns := PackedInt32Array()
	for i in range(0, body.pos.size() - 2, 3):
		if body.uv2[i].x > 0.5:
			turns.append(i)
	var column := SteeringColumn.fit(body.pos, turns)
	for i: int in column.get("dropped", PackedInt32Array()):
		for k in 3:
			body.uv2[i + k] = Vector2.ZERO
	var part := {"name": "body", "mesh": body.commit(), "center": Vector3.ZERO, "damaged": _damaged(body)}
	if not column.is_empty():
		part.steering = {"pivot": column.pivot, "axis": column.axis}
		# The in-car view from the modelled cabin (HP2 had none): the eye behind the wheel, up
		# the seat's height above its hub, but under the roof (the top of the car over it).
		var col: Dictionary = part.steering
		var eye: Vector3 = col.pivot + Vector3(0.0, 0.0, -EYE_BEHIND_WHEEL) + Vector3.UP * EYE_ABOVE_WHEEL
		var roof := -INF
		for v in body.pos:
			if absf(v.x - eye.x) < 0.2 and absf(v.z - eye.z) < 0.25:
				roof = maxf(roof, v.y)
		# (An open car's highest point there, a headrest or the hood folded, is lower: no roof.)
		if roof > eye.y - 0.05:
			eye.y = minf(eye.y, roof - EYE_BELOW_ROOF)
		# Clear of the seat: forward until nothing's within a head's reach (the seats sit
		# further forward in some cars than others), but no closer to the wheel than that.
		while eye.z < col.pivot.z - EYE_NEAREST_WHEEL:
			var clear := true
			for v in body.pos:
				if v.distance_squared_to(eye) < EYE_CLEARANCE * EYE_CLEARANCE:
					clear = false
					break
			if clear:
				break
			eye.z += 0.03
		dash = {"eye": eye, "own_cabin": true}
	body_parts.append(part)
	if not glass.pos.is_empty():
		body_parts.append({"name": "glass", "mesh": glass.commit(), "center": Vector3.ZERO, "glass": true})
	if not lens.pos.is_empty():
		body_parts.append({"name": "lens", "mesh": lens.commit(), "center": Vector3.ZERO, "glass": true, "clarity": 1.0})
	# The wheels in Nfs3Car's order: front left, front right, rear left, rear right (+X the left, +Z the front).
	if wheel_parts.size() == 4:
		var placed: Array[Dictionary] = []
		for w in wheel_parts:
			var wlo := Vector3.INF
			var whi := -Vector3.INF
			for p: Vector3 in w.g.pos:
				wlo = wlo.min(_to_car(p))
				whi = whi.max(_to_car(p))
			var center := (wlo + whi) * 0.5
			var t := _Tris.new()
			t.add(w.g, center)
			var slot := (0 if center.z > 0.0 else 2) + (0 if center.x > 0.0 else 1)
			placed.append({"name": w.name, "mesh": t.commit(), "center": center, "slot": slot})
		# Each brake with the wheel nearest it, about the same hub.
		var brakes := {}
		for b in brake_parts:
			var mid := Vector3.ZERO
			for p: Vector3 in b.pos:
				mid += _to_car(p)
			mid /= maxf((b.pos as PackedVector3Array).size(), 1.0)
			var near := 0
			for k in placed.size():
				if mid.distance_to(placed[k].center) < mid.distance_to(placed[near].center):
					near = k
			if not brakes.has(near):
				brakes[near] = _Tris.new()
			brakes[near].add(b, placed[near].center)
		for k in brakes:
			placed[k].brake = brakes[k].commit()
		placed.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.slot < y.slot)
		var slots := placed.map(func(x: Dictionary) -> int: return x.slot)
		if slots == [0, 1, 2, 3]:
			wheels = placed
		else:
			for w in placed:
				body_parts.append(w)
	else:
		# No clean set of four: drawn with the body, as they are.
		for w in wheel_parts:
			var t := _Tris.new()
			t.add(w.g, Vector3.ZERO)
			body_parts.append({"name": w.name, "mesh": t.commit(), "center": Vector3.ZERO})
	if half_size == Vector3(0.9, 0.6, 2.2):
		var box := AABB(body.pos[0], Vector3.ZERO)
		for p in body.pos:
			box = box.expand(p)
		half_size = box.size * 0.5


## Whether the part's vertex colours are near black on average (HP2 draws it dark whatever
## its texture).
static func _dark_part(g: Dictionary) -> bool:
	var col: PackedColorArray = g.colour
	if col.is_empty():
		return false
	var sum := 0.0
	for c in col:
		sum += c.get_luminance()
	return sum / col.size() < 0.12


## The middle of the skin's darkest patch (on a 32 x 32 shrink, so a lone texel doesn't count).
var _darkest := Vector2(-1, -1)


func _darkest_uv() -> Vector2:
	if _darkest.x >= 0.0 or texture == null:
		return _darkest if _darkest.x >= 0.0 else Vector2(0.5, 0.5)
	var img := texture.get_image()
	img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(32, 32, Image.INTERPOLATE_BILINEAR)
	var best := INF
	_darkest = Vector2(0.5, 0.5)
	for y in 32:
		for x in 32:
			var c := img.get_pixel(x, y)
			if c.a > 0.9 and c.get_luminance() < best:
				best = c.get_luminance()
				_darkest = Vector2((x + 0.5) / 32.0, (y + 0.5) / 32.0)
	return _darkest


## A part shaped like a wheel (some traffic's aren't named RUBBER): as tall as it's long, narrow,
## low down and out at the side.
static func _wheel_shaped(g: Dictionary) -> bool:
	var pos: PackedVector3Array = g.pos
	if pos.size() > 400:
		return false
	var box := AABB(pos[0], Vector3.ZERO)
	for p in pos:
		box = box.expand(p)
	var c := box.get_center()
	return absf(box.size.y - box.size.z) < 0.12 and box.size.y > 0.4 and box.size.x < 0.45 \
		and absf(c.x) > 0.4 and c.y < 0.0


## Triangles in our space, unindexed, as SurfaceTool would commit them (CarDamage's damaged
## copy goes vertex for vertex): each wound so the side its normals face is the front
## (clockwise as seen from there).
class _Tris:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var zone := PackedInt32Array()   # geomdata.ini's damage zone of the part, -1 none

	func add(g: Dictionary, offset: Vector3, part_zone := -1, steering := false) -> void:
		var gp: PackedVector3Array = g.pos
		var gn: PackedVector3Array = g.normal
		var gu: PackedVector2Array = g.uv
		var idx: PackedInt32Array = g.indices
		for t in range(0, idx.size() - 2, 3):
			var tri := [idx[t], idx[t + 1], idx[t + 2]]
			var a := Nfs6Car._to_car(gp[tri[0]])
			var b := Nfs6Car._to_car(gp[tri[1]])
			var c := Nfs6Car._to_car(gp[tri[2]])
			var n := Nfs6Car._to_car(gn[tri[0]] + gn[tri[1]] + gn[tri[2]])
			if (b - a).cross(c - a).dot(n) > 0.0:
				tri = [tri[0], tri[2], tri[1]]
			for k in 3:
				var i: int = tri[k]
				pos.append(Nfs6Car._to_car(gp[i]) - offset)
				nrm.append(Nfs6Car._to_car(gn[i]).normalized())
				uv.append(gu[i])
				uv2.append(Vector2(1.0 if steering else 0.0, 0.0))
				zone.append(part_zone)

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m


const EYE_BEHIND_WHEEL := 0.6
const EYE_ABOVE_WHEEL := 0.36
const EYE_BELOW_ROOF := 0.13
const EYE_NEAREST_WHEEL := 0.35
const EYE_CLEARANCE := 0.15


## HP2 bends its cars at run time (each vertex skinned to its zone's damage bone), so there's no
## damaged model to bend toward: one is made here. A vertex is on the panels (bits) of every
## zone whose part has a vertex where it is (so the panels stay joined at their seams), and
## its damaged place is pushed in toward the middle of the car by a crumple that depends
## only on where it is (every copy of it goes the same way).
const CRUMPLE := Vector2(0.06, 0.16)   # m pushed in, least and most


static func _damaged(t: _Tris) -> Dictionary:
	var at := {}
	for i in t.pos.size():
		if t.zone[i] >= 0:
			var q := Vector3i((t.pos[i] * 100.0).round())
			at[q] = int(at.get(q, 0)) | (1 << t.zone[i])
	var panels := PackedInt32Array()
	var dpos := PackedVector3Array()
	var dnrm := PackedVector3Array()
	panels.resize(t.pos.size())
	dpos.resize(t.pos.size())
	dnrm.resize(t.pos.size())
	for i in t.pos.size():
		var r := t.pos[i]
		panels[i] = at.get(Vector3i((r * 100.0).round()), 0)
		var w1 := sin(r.x * 9.1 + sin(r.z * 7.3) * 2.0) * cos(r.z * 11.7 + r.y * 5.3)
		var w2 := sin(r.z * 17.3 + r.x * 3.1) * cos(r.y * 13.9 - r.x * 8.7)
		var crumple := lerpf(CRUMPLE.x, CRUMPLE.y, 0.5 + 0.35 * w1 + 0.15 * w2)
		var inward := Vector3(-r.x, -0.35 * r.y, -r.z * 0.5)
		dpos[i] = r + (inward.normalized() if inward.length() > 0.01 else Vector3.ZERO) * crumple
		dnrm[i] = (t.nrm[i] + Vector3(w2, w1, -w2) * 0.45).normalized()
	return {"pos": dpos, "normal": dnrm, "panels": panels}


## skeleton.o's bones: a record of 0x70 bytes each from the skeleton's +0x30, the bone's
## inverse bind matrix at +0x10 (row-major, its translation the last row): where the bone sits
## is minus that translation (the matrices carry no turn). Lamps and tail pipes are bones.
func _read_skeleton(sk: Eagl) -> void:
	if sk.error != "" or not sk.symbols.has("__Skeleton:::Root"):
		return
	var base: int = sk.symbols["__Skeleton:::Root"] + 0x30
	var at := {}
	for s: String in sk.symbols:
		if not s.begins_with("__Bone:::Root."):
			continue
		var idx := sk.u32(sk.symbols[s])
		var r := base + idx * 0x70
		if r + 0x50 > sk.data.size() or sk.u32(r + 12) != idx:
			continue
		var t := Vector3(sk.data.decode_float(r + 0x40), sk.data.decode_float(r + 0x44), sk.data.decode_float(r + 0x48))
		at[s.trim_prefix("__Bone:::Root.").to_upper()] = _to_car(-t)
	var add := func(bone: String, kind: String, colour: String, flash := "N") -> void:
		if at.has(bone):
			lights.append({"pos": at[bone], "kind": kind, "colour": colour, "breakable": true, "flash": flash,
				"intensity": 5, "time": 5, "delay": 0})
	for side in ["LEFT", "RIGHT"]:
		add.call("LIGHT_HEAD_%s1" % side, "H", "W")
		add.call("LIGHT_TAIL_%s1" % side, "T", "R")
		add.call("LIGHT_TAIL_%s1" % side, "B", "R")
		add.call("LIGHT_TAIL_%s2" % side, "R", "W")
	add.call("LIGHT_TAIL", "B", "R")
	if cop:
		add.call("LIGHT_COP_R", "S", "R", "O")
		add.call("LIGHT_COP_B", "S", "B", "E")
		add.call("LIGHT_COP_W", "S", "W", "O")
	for k in range(1, 5):
		if at.has("EXHAUST_%d" % k):
			exhausts.append(at["EXHAUST_%d" % k])


# ---------------------------------------------------------------- sounds

## Audio/Sfx's archives, read once per install: careng.viv, oppbnk.viv, hornz.viv, cartable.viv.
static var _sfx_root := "-"
## Engines oppbnk.viv has no bank for, and the one standing in (car.ini names them
## "Cams/Pan/Snub" and "CamarosExhst/SnubEng").
const OPP_ALIASES := {"4cr": "cam", "csn": "css"}
static var _sfx := {}

## The engine the way CarAudio plays High Stakes' (careng.bnk with careng.ctb / .ltb):
## car.ini's [audio] enginetype picks Audio/Sfx/car.ini's [car<n>], whose engcode/exhcode
## name twelve one-recording banks in careng.viv, <code><c|l><e|x><lo|id, md, hi>: off the
## throttle (c) or on it (l), engine or exhaust, low, middle and high rpm. cartable.viv's
## engine.ltb gives patches 0..5 (l: e lo, md, hi, then x) and engine.ctb 6..11 (c: e id,
## md, hi, then x) their volume over engine speed; the exhaust's are the tables' channels 4..
## (engine.htb / .btb are the load ones again, 12..17: unused here). The cars around you
## loop oppbnk.viv's <code>.bnk (ocar.bnk: patch 0 off the throttle, 1 on it); traffic all
## share genopp.bnk. horntype is hornz.ini's [horn<n>], a bank in hornz.viv (horn.bnk).
func _read_sounds() -> void:
	var sfx_dir := DataPath.find_ci(folder.get_base_dir().get_base_dir(), "Audio/Sfx")
	if sfx_dir == "":
		return
	var vivs := _sfx_archives(sfx_dir)
	var ini := Nfs5Car._ini(FileAccess.get_file_as_string(DataPath.find_ci(folder, "car.ini")))
	var audio: Dictionary = ini.get("audio", {})
	var horns := Nfs5Car._ini(FileAccess.get_file_as_string(DataPath.find_ci(sfx_dir, "hornz.ini")))
	var horn: String = horns.get("horn%s" % audio.get("horntype", ""), {}).get("name", "genhorn")
	if vivs.hornz:
		sound_files["horn.bnk"] = vivs.hornz.get_file(horn.to_lower() + ".bnk")
	if traffic:
		var gen := DataPath.find_ci(sfx_dir, "genopp.bnk")
		if gen != "":
			sound_files["ocar.bnk"] = FileAccess.get_file_as_bytes(gen)
		return
	var engines := Nfs5Car._ini(FileAccess.get_file_as_string(DataPath.find_ci(sfx_dir, "car.ini")))
	var eng: Dictionary = engines.get("car%s" % audio.get("enginetype", "4"), {})
	var code: String = eng.get("engcode", "").to_lower()
	var exh: String = eng.get("exhcode", code).to_lower()
	if code == "":
		return
	if vivs.opp:
		sound_files["ocar.bnk"] = vivs.opp.get_file(OPP_ALIASES.get(code, code) + ".bnk")
	if vivs.careng == null or vivs.table == null:
		return
	var parts := {}
	var names := ["lelo", "lemd", "lehi", "lxlo", "lxmd", "lxhi", "ceid", "cemd", "cehi", "cxid", "cxmd", "cxhi"]
	for i in names.size():
		var n: String = names[i]
		var data: PackedByteArray = vivs.careng.get_file((exh if n[1] == "x" else code) + n + ".bnk")
		if not data.is_empty():
			parts[i] = EaBnk.parse(data)
	if parts.size() < names.size():
		return
	_sound_banks["careng.bnk"] = EaBnk.join(parts)
	sound_files["careng.ctb"] = vivs.table.get_file("engine.ctb")
	sound_files["careng.ltb"] = vivs.table.get_file("engine.ltb")


static func _sfx_archives(sfx_dir: String) -> Dictionary:
	if sfx_dir != _sfx_root:
		_sfx_root = sfx_dir
		_sfx = {}
		for k in [["careng", "careng.viv"], ["opp", "oppbnk.viv"], ["hornz", "hornz.viv"], ["table", "cartable.viv"]]:
			_sfx[k[0]] = Viv.load_file(DataPath.find_ci(sfx_dir, k[1]))
	return _sfx

