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
## arms and legs (each body's own: _fit_limbs), slot 56 the hands (1 gloved, 2 bare). The
## game picks them itself where a style doesn't say (most don't: the seat would be empty);
## the styles that do pair driver 1 with arms 1 and gloves, driver 3 with bare hands.
const DRIVER_SLOT := 9
## The arms' and hands' first frames: the steering sweep, from full lock one way to the other.
const STEER_FRAMES := 10
## The driver's body (DriverBodyN) leans into the bend with them: its first frames, full lock
## one way to the other, the middle one straight ahead. (Its "rest" frame, byte 9, has the
## head turned well aside; the frames after the lean lean forward and look round.)
const BODY_FRAMES := 5
const BODY_SIDE := 2   # _Mesh.side of the body's vertices: it follows the arms' sweep
## A lean frame's vertex further than this (m) from the middle frame is broken: in some
## models (the 993's, Boxster's, 550's, GT2's drivers 8-10) the last lean frame has the head
## and shoulders folded away, a third of the body half a metre off. The real lean is ~0.1.
const LEAN_BROKEN := 0.2
## A limb's seam with the body: its nearest vertex pairs, and the most (m) it's moved to close it.
const LIMB_SEAM := 4
const LIMB_SNAP := 0.1
## The limbs each driver wears (by driver, LIMBS_SLOT's variant): 1 driver 1's race suit, 2
## drivers 2-5's jackets, 3 driver 6's suit, 4 drivers 7-10's. And how near (m) the forearms'
## ends must come to the body's for another model's own limbs to be taken instead.
const LIMBS_OF := [0, 1, 2, 2, 2, 2, 3, 4, 4, 4, 4]
const LIMBS_EXACT := 0.002
const LIMBS_SLOT := 43
const SUITED_DRIVERS := [1, 6]
## The in-car view sits at the driver's eyes, inside the model's own cabin, with his head
## (the body's vertices this far below its top, helmet and all) taken away: UV2.x HEAD_MARK,
## which car_driver.gdshader folds away with `hide_head`. The eye: this far below the top
## of the head, over its middle (not out at the eyes: the steeply raked windscreens, the
## 944's, would have it looking out from under the glass, the roof behind it).
const HEAD_DEPTH := 0.25
const HEAD_MARK := -1.0
## The driver's two pairs of arms. Seen from outside, his body's own upper arms and the limbs
## slot's forearms and fists (LeftArmN, RightArmN), which meet them at the elbow; in the
## in-car view, the hands slot's sleeves, made for the eye: from over and behind his
## shoulders, which they'd stand out of seen from outside. The forearms take HEAD_MARK
## (gone in the in-car view with the head), the sleeves IN_CAR_MARK (there only).
const IN_CAR_MARK := -2.0
const EYE_BELOW_TOP := 0.12
## The Carreras' rear spoiler (geometry slot 42): the style picks it lowered (an odd
## variant); the next variant is it raised, which the car shows at speed.
const SPOILER_SLOT := 42
## ... and its way up: "SpoilerW" (level 0x12, the style's variant of slot 6), the lowered
## spoiler's mesh in frames from down to up, the car's blend shapes (spoiler "moving").
const SPOILER_MOVE_LEVEL := 0x12
## The wipers: "WiperNa" the arm, "WiperNb" its blade, N one wiper or the other (slot 0,
## no "tr"). A few cars (the 993, the GT2, the 356 No. 1) have a single wiper in frames from
## parked to the top of its sweep; the rest are drawn parked, and turn here about the arm's
## far end, in the glass's plane, by WIPER_SWEEP in WIPER_FRAMES steps, riding on the glass.
const WIPER_SWEEP := 1.55
const WIPER_FRAMES := 8
## What opens (base info byte 7, the part's group): the doors, left and right (the outside,
## the inside, the window, handle, mirror and decals), the bonnet and the boot lid (engine
## lid on the rear-engined cars), each with its underside (level 0x1E). Every part of a
## group has its hinge as its "tr" origin: a door's front edge, a lid's edge by the glass.
## The files don't say how far: Car opens them by LID_OPEN (radians), doors about the
## upright, lids about the car's width, the free edge going out or up.
const DOOR_LEFT := 6
const DOOR_RIGHT := 7
const BONNET := 8
const BOOT := 9
const LID_GROUPS := [DOOR_LEFT, DOOR_RIGHT, BONNET, BOOT]
const LID_OPEN := {DOOR_LEFT: 1.15, DOOR_RIGHT: 1.15, BONNET: 0.95, BOOT: 0.85}
## What a crash can tear off besides the doors and lids (the parts' "loose" key; Car.tear_off):
## the skirts (front and back aprons, the sills, by geometry slot) and the spoiler.
const BUMPER_FRONT := 30
const BUMPER_REAR := 31
const SILL_LEFT := 32
const SILL_RIGHT := 33
const SPOILER := 34
## ... and the side mirrors (MIRROR_SLOT), off their doors: a door torn off takes its mirror,
## but a mirror can go on its own.
const MIRROR_OFF := {DOOR_LEFT: 35, DOOR_RIGHT: 36}
const SKIRT_SLOTS := {5: BUMPER_FRONT, 4: BUMPER_REAR, 3: SILL_LEFT}
const FIXED_SPOILER_SLOT := 6
## The engine bay and the luggage space (level 0x1D, no group): shown while the lid over
## them (the one at their end of the car) is open.
const BAY_LEVEL := 0x1D
const LID_INSIDE_LEVEL := 0x1E
## UV2.x of a lid's underside: car.gdshader draws only its front faces. It lies a mm or so
## under the lid's skin, and drawn two-sided (as the rest is) it shows through the lid from
## above in specks; and from below the skin would, so it comes forward (LID_INSIDE_BIAS).
const ONE_SIDED_MARK := -3.0
const LID_INSIDE_BIAS := 0.002
## The door windows (slot 35) wind down into the doors, this share of their height, sliding
## in their own plane (in at the top). The files have no way down for them (the game never
## lowers them: one frame, no variants), and no well in the door: its skin and trim meet at
## the pane's foot, the belt line, and the pane's rear top corner reaches past the door's
## back edge. So what goes below the belt is cut away (the parts' "belt", car.gdshader and
## car_glass.gdshader), and all the way down the pane is gone.
const WINDOW_SLOT := 35
const WINDOW_DROP := 1.0
## The belt line: fitted through the pane's vertices this close to its lowest (m).
const WINDOW_BELT_BAND := 0.04
## A material's finish, near its record's end: how much it mirrors the surroundings (0 matte:
## wheel wells, trim, decals; 0.5 the paint and lamp lenses; 1 chrome: the 356s' bumpers,
## the 550's pipes, badges), and its kind (2 a lamp's lens). Each vertex carries them as
## COLOR (r the mirroring, g 1 on a lens, b 0 marking the data present) for car.gdshader.
const MAT_ENV_FROM_END := 28
const MAT_KIND_FROM_END := 4
const LENS_KIND := 2
## A glare effect of this kind (byte 84) is a glint, not a lamp; its normal (at byte 56) points
## back at where it's seen from.
const GLINT_KIND := 4
## Level 0x1E's parts that are outside: a cabriolet's soft top (slot 37) and the hood's
## frame and rear window, or the hood folded (41), each shown when its style picks it.
const CABRIO_TOP_SLOT := 37
const HOOD_SLOT := 41
const CABRIO_SLOTS := [CABRIO_TOP_SLOT, HOOD_SLOT]

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
## The wheel wells (geometry slot 12) reach up to the cabin's floor and rear shelf, a mm or
## so through them in places (the 993 cabriolet's shelf, the 996's rear seats). They face out
## into the arches, so they're drawn one-sided (ONE_SIDED_MARK): seen from the cabin their
## backs don't show through, and seen through the arches they still hide the cabin behind
## them (a depth bias behind the interior's let its footwells show through the arches).
const WHEEL_WELL_SLOT := 12
## The belly pan (geometry slot 11) lies a few cm under the cabin's floor: drawn two-sided,
## its top showed through the footwells from above, the interior's bias putting the carpet
## behind it from a few metres off. It faces down, so it's drawn one-sided as the wells are.
const BOTTOM_SLOT := 11
## The wheels (bias 0 in the files) tuck up under the rear shelf and seats, a few cm behind
## the cabin's walls: behind by the interior's own bias, they'd show through them from above
## in specks. They go back as far as the interior, so there the real depths decide.
const WHEEL_BIAS := 3
## A glare effect's article ("ef") comes once per level of detail, its level at this byte of
## the Base entry; only the first level's carries the "tr" of the moving part it rides on
## (base info byte 7 the part's group: POPUP_GROUP the pop-up headlamps, 9 the boot lid).
const EF_LEVEL_AT := 108
const POPUP_GROUP := 0x11
## The dials' needles (geometry slot 30): base info byte 7 says which moves, SPEEDO_NEEDLE
## with the speed and TACH_NEEDLE the revs (the others, fuel and oil, are modelled in place).
## Each is modelled pointing up its own Y from its "tr" origin, the dial's hub, lying in the
## dial's face; the car turns it about the face's normal. Where it's modelled pointing isn't
## its zero (the 356's point there, the 996's straight up), and the files don't say where
## the dials start: they start at NEEDLE_ZERO turns clockwise from straight up, as most do.
const NEEDLE_SLOT := 30
## The side mirrors (geometry slot 39), an article per side, base info byte 7 MIRROR_LEFT or
## the right one: their glass is the triangles facing back (the in-car view's mirrors).
const MIRROR_SLOT := 39
const MIRROR_LEFT := 6
const MIRROR_RIGHT := 7
const NEEDLE_ZERO := 0.625
## The windows' inner panes: InteriorDoorGlass, InteriorGlass (the windscreen) and
## InteriorRoofGlass.
const INNER_GLASS_SLOTS := [47, 48, 54]
const SPEEDO_NEEDLE := 12
const TACH_NEEDLE := 11
## The exterior's paint: the game paints by alpha, 204 the body colour and 77, 153, 166,
## 179 and 230 the stripes and trims of its paint schemes (the .clr's other colours); here
## they all take the body colour. 255 is unpainted (lamps, badges), 0 cut out.
const PAINT_ALPHA := Vector2i(70, 240)
## The window page's painted rim (204), and its see-through pane (128) which alone is glass.
const WINDOW_RIM_ALPHA := Vector2i(180, 230)
const WINDOW_PANE_ALPHA := Vector2i(90, 170)
## A window page's triangles, in both the bodywork and the glass: their vertices' COLOR.b.
## Each shader tells the pane by its texels' alpha (128), exactly: see _read_model.
const WINDOW_MARK := 0.25
const ATLAS_WIDTH := 512
## The cabin's pages: texels at INTERIOR_ALPHA take the interior colour (the .clr's colour
## 4 for each paint, trim and leather), those at the paint's alpha the body colour (the door
## tops). The interior's are marked CABIN_ALPHA in the skin, which car.gdshader tints with
## `interior_paint` (no paint alpha is left there once the pages are painted).
const INTERIOR_FILES := ["interior.fsh", "extint.fsh"]
const INTERIOR_ALPHA := Vector2i(40, 60)
const CABIN_ALPHA := 224
const STOCK_INTERIOR := Color8(98, 99, 100)
## Paints for the cars without a .clr (the traffic): plain period colours.
const STOCK_PAINTS := [Color8(200, 200, 196), Color8(40, 44, 52), Color8(150, 30, 28), Color8(30, 60, 120),
	Color8(40, 90, 60), Color8(200, 190, 150), Color8(110, 110, 115), Color8(230, 230, 225)]
const RECORD_SIZE := 1648

var model := ""        # the CRP model's name
var style := 0         # its .tpg style index
var driver_count := 0  # how many drivers its model has to choose from (DRIVER_SLOT's variants)
var sim := ""          # the .sim's name
var _geometry := {}    # geometry slot -> the variant its style shows (0 when it doesn't say)
var _textures := {}    # texture slot -> the variant of its images its style shows
var _hood_folded := 0    # a cabriolet's folded hood: its variant of HOOD_SLOT, or 0
var interior_colours: Array[Color] = []   # each paint's interior (colour 4), at double strength as they are
var _intglass_pages := {}   # pages of intglass.fsh, the windows' inner panes
## (`glints` and `exhausts`, Nfs3Car's, come from the glare effects that aren't lamps: kind
## GLINT_KIND, the sun's glint off the chrome, "GlareExhaust" the tail pipes' ends.)
var _window_pages := {}   # page -> its image as the game has it (before _paint_page), for the window pages


## Porsche Unleashed's own effect sprites (GameData/Render): "GLNT" the chrome's glint, "GLAR"
## a lamp's glare (common.fsh), "SMX1" the tail pipe smoke (particle.fsh, the car's "Tail pipe
## smoke" system in carpart.ini); null without the game.
static var _fx := {}
static var _others_viv: Viv      # Sounds/zzzwzzz.viv (_others_engines), and the root it came from
static var _others_root := "-"


static func fx(sprite: String) -> Texture2D:
	if not _fx.has(sprite):
		_fx[sprite] = null
		var render := DataPath.find_ci(Game.pu_root, "Render") if Game.pu_root != "" else ""
		for file in ["common.fsh", "particle.fsh"]:
			var path := DataPath.find_ci(render, file) if render != "" else ""
			if path == "" or not FileAccess.file_exists(path):
				continue
			var img: Image = Fsh.load_file(path).by_name.get(sprite)
			if img:
				img.generate_mipmaps()
				_fx[sprite] = ImageTexture.create_from_image(img)
				break
	return _fx[sprite]


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


## `driver` (1..driver_count) puts that driver in the seat; 0 leaves it to the style.
static func load_car(pu_root: String, rec: Dictionary, driver := 0) -> Nfs5Car:
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
	c._pick_people(crp, driver)
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
	# Both are built (hood_up_parts / the folded one), for the car to raise and lower.
	if _geometry.get(CABRIO_TOP_SLOT, 0) != 0:
		var pair := maxi((int(_geometry.get(HOOD_SLOT, 0)) + 1) / 2, 1)
		_geometry[HOOD_SLOT] = pair * 2 - 1
		_hood_folded = pair * 2


## Who sits in the car where its style doesn't say (DRIVER_SLOT): the suited driver, with
## his arms and gloves. Only on models with the ten drivers; the traffic's one driver is
## variant 0 of the slot, and the police have none. `chosen` (the player's pick, 0 for none)
## overrides the style, his hands with him; his limbs are always the ones made for his body.
func _pick_people(crp: Crp, chosen := 0) -> void:
	for art in crp.articles:
		var base := crp.sub(art, "Base")
		if base != null and crp.data[base.offset + 68] == DRIVER_SLOT:
			driver_count = maxi(driver_count, crp.data[base.offset + 69])
	if driver_count == 0:
		return
	var driver: int = _geometry.get(DRIVER_SLOT, 1)
	if chosen > 0 and chosen <= driver_count and chosen != driver:
		driver = chosen
		_geometry.erase(HANDS_SLOT)
	_geometry[DRIVER_SLOT] = driver
	# (Even where the style says: the 550's pairs driver 2 with driver 1's suit sleeves.)
	_geometry[LIMBS_SLOT] = _fit_limbs(crp, driver)
	if not _geometry.has(HANDS_SLOT):
		_geometry[HANDS_SLOT] = 1 if driver in SUITED_DRIVERS else 2


## Mends the body's lean frames (`lean`, their normals `lean_n`, BODY_FRAMES of them, the
## middle one straight): a vertex LEAN_BROKEN from the middle takes its next frame in's
## place, carried on as far again (the lean goes on the same way, a frame at a time).
static func _mend_lean(lean: Array[PackedVector3Array], lean_n: Array[PackedVector3Array]) -> void:
	var mid := BODY_FRAMES / 2
	for f in [mid - 1, mid + 1] + range(mid - 2, -1, -1) + range(mid + 2, BODY_FRAMES):
		var step := 1 if f < mid else -1   # (toward the middle)
		var near: int = f + step
		var nearer: int = near + step if near != mid else mid
		for i in lean[f].size():
			if lean[f][i].distance_to(lean[mid][i]) > LEAN_BROKEN:
				lean[f][i] = lean[near][i] * 2.0 - lean[nearer][i]
				lean_n[f][i] = lean_n[near][i]


## The limbs (LIMBS_SLOT's variant) made for driver `driver`'s body: each body has its own
## (LIMBS_OF), its forearms and legs meeting the body's sleeves and hem. The one whose
## forearms' ends sit on the body's vertices, in their rest frames; LIMBS_OF's where none
## does (within LIMBS_EXACT), else the nearest; 1 if none is found.
func _fit_limbs(crp: Crp, driver: int) -> int:
	var body := PackedVector3Array()
	var arms := {}   # variant -> the LeftArm's and RightArm's rest vertices
	for art in crp.articles:
		var base := crp.sub(art, "Base")
		if base == null or crp.data[base.offset + 78] != PEOPLE_LEVELS[0]:
			continue
		var slot := crp.data[base.offset + 68]
		var variant := crp.data[base.offset + 69]
		var rest := crp.data[base.offset + 77]
		var name: String = art.name
		if slot == DRIVER_SLOT and variant == driver and not name.to_lower().begins_with("lod"):
			var f := BODY_FRAMES / 2 if crp.data[base.offset + 76] >= BODY_FRAMES else rest
			body = crp.vec3s(crp.sub(art, "vt", PART_LEVEL | f << 4))
		elif slot == LIMBS_SLOT and (name.begins_with("Left") or name.begins_with("Right")):
			var vt := crp.sub(art, "vt", PART_LEVEL | rest << 4)
			if vt != null:
				arms[variant] = arms.get(variant, PackedVector3Array()) + crp.vec3s(vt)
	var best := 1
	var best_gap := INF
	for v: int in arms:
		# (The few vertices nearest the body: the sleeves' ends; the rest are free.)
		var gaps: Array[float] = []
		for p: Vector3 in arms[v]:
			var g := INF
			for q in body:
				g = minf(g, p.distance_squared_to(q))
			gaps.append(g)
		gaps.sort()
		var gap := 0.0
		for i in mini(4, gaps.size()):
			gap += gaps[i]
		if gap < best_gap:
			best_gap = gap
			best = v
	# (Where none meets it, the 935's, the usual pairing: the one in his clothes' colours.)
	if best_gap > LIMBS_EXACT * LIMBS_EXACT * 4 and driver < LIMBS_OF.size() and arms.has(LIMBS_OF[driver]):
		return LIMBS_OF[driver]
	return best


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
		var placed := _fill_page(images[page], Qfs.decompress(bytes), Vector2i(int(det.get("offsetx", "0")), int(det.get("offsety", "0"))),
			_image_wanted.bind(tpg, fi))
		# The licence plate ("lice", marked license=1) is blank: the game letters it.
		for name: String in placed:
			if tpg.get("file%d.%s" % [fi + 1, name.strip_edges().to_lower()], {}).get("license", "0") == "1":
				Plates.letter_pu(images[page], placed[name], Plates.random_text_pu(), cdir.get_base_dir())
		var file_name := str(tpg.header.get("file%d" % (fi + 1), "")).to_lower()
		if fi == 0:
			_paint_page(images[page])
		elif file_name == "intglass.fsh":
			_intglass_pages[page] = true
		elif file_name in INTERIOR_FILES:
			_paint_page(images[page])
			_mark_cabin(images[page])
	# The windows' page: the pane (alpha 128) round which runs the black seal (255) and a
	# rim painted the body colour (204), which the window triangles along the roof show.
	for p in n_pages:
		if tpg.get("tpage%d.details" % (p + 1), {}).get("window", "0") == "1":
			_window_pages[p] = images[p].duplicate()
			_paint_page(images[p], WINDOW_RIM_ALPHA)
	# The soft tops' rear window (cabrio.fsh's "sgla", clear plastic at alpha 128) is glass too.
	for fi in n_files:
		if str(tpg.header.get("file%d" % (fi + 1), "")).to_lower() == "cabrio.fsh":
			var cp := int(tpg.get("file%d.details" % (fi + 1), {}).get("tpage", "0")) - 1
			if cp >= 0 and cp < images.size() and not _window_pages.has(cp):
				_window_pages[cp] = images[cp].duplicate()
	# The cut-out texels (round the door handles, fuel caps, badges, the driver) hold a
	# near-white or black the filtering smears onto the visible edges as a rim: give them
	# their visible neighbours' colour, page by page so that no page bleeds into the next.
	for p in n_pages:
		Nfs3Car._bleed_cutout(images[p], false)
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
	atlas.fill(Color8(DAMAGE_NEUTRAL, DAMAGE_NEUTRAL, DAMAGE_NEUTRAL, 0))
	var seen := {}
	for i in fsh.images.size():
		var off := d.decode_s32(20 + i * 8)
		var p := Vector2i(d.decode_u16(off + 12) & 0x3FF, d.decode_u16(off + 14) & 0x3FF)
		var img: Image = fsh.images[i]
		var page := ext if not seen.has(p) else mirror
		seen[p] = true
		if page < 0 or page >= pages.size() or not at.has(page):
			continue
		img = img.duplicate()
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		_neutral_cutout(img)
		var r := Rect2i(Vector2i.ZERO, img.get_size()).intersection(Rect2i(-p, pages[page].get_size()))
		atlas.blit_rect(img, r, at[page] + p + r.position)
	atlas.generate_mipmaps()
	return ImageTexture.create_from_image(atlas)


## The damage images' cut-out texels (and the atlas round them) in the grey that leaves the
## paint as it is (car.gdshader scales it by 2.6 in linear light: sRGB 167), so that the
## filtering fades a crease's edge out rather than drawing it as a dark or light rim.
const DAMAGE_NEUTRAL := 167

static func _neutral_cutout(img: Image) -> void:
	var d := img.get_data()
	for k in range(0, d.size(), 4):
		if d[k + 3] == 0:
			d[k] = DAMAGE_NEUTRAL
			d[k + 1] = DAMAGE_NEUTRAL
			d[k + 2] = DAMAGE_NEUTRAL
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, d)


## Draws an FSH's images onto `page` where their headers place them (bytes 12, 14 of the
## image header: x, y), those `wanted` (name) -> bool. Variants of one image share a place
## ("det", "det1"... the badges, of different widths): the first drawn of those stays.
## Returns where each drawn image went on the page, by name.
static func _fill_page(page: Image, d: PackedByteArray, offset: Vector2i, wanted: Callable) -> Dictionary:
	var placed := {}
	var fsh := Fsh.from_bytes(d)
	if fsh == null:
		return placed
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
		placed[fsh.names[i]] = Rect2i(p, img.get_size())
	return placed


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


## A cabin page's INTERIOR_ALPHA texels (the leather, carpet and trim, drawn grey) marked
## CABIN_ALPHA, for car.gdshader to tint with the interior colour.
static func _mark_cabin(img: Image) -> void:
	var d := img.get_data()
	for k in range(0, d.size(), 4):
		var a := d[k + 3]
		if a >= INTERIOR_ALPHA.x and a <= INTERIOR_ALPHA.y:
			d[k + 3] = CABIN_ALPHA
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, d)


# ---------------------------------------------------------------- model

## The parts of the car's style at full detail: the body and glass as one mesh each (car
## space), the wheels as one each around their hubs, the lamps from its glare effects.
func _read_model(crp: Crp, tpg: Dictionary, pages: Array[Rect2]) -> void:
	var want := _geometry
	# Glass: the window material, and anything on a page the .tpg marks "window" (the
	# inner panes of the windows use the interior's material on it).
	var mats := {}   # material -> [page, glass, finish (vertex COLOR)]
	for e in crp.misc_of("mt"):
		if e.length >= 44:
			var rm := crp.data.slice(e.offset + 16, e.offset + 32).get_string_from_ascii()
			var page := crp.data.decode_s32(e.offset + 40)
			var window: bool = tpg.get("tpage%d.details" % (page + 1), {}).get("window", "0") == "1"
			var finish := Color(0.5, 0.0, 0.0, 1.0)
			if e.length >= 64:
				var env := clampf(crp.data.decode_float(e.offset + e.length - MAT_ENV_FROM_END), 0.0, 1.0)
				var lens := crp.data.decode_s32(e.offset + e.length - MAT_KIND_FROM_END) == LENS_KIND
				finish = Color(env, 1.0 if lens else 0.0, 0.0, 1.0)
			mats[e.index] = [page, rm == "CarWindow" or window or _window_pages.has(page), finish]
	var body := _Mesh.new()
	var glass := _Mesh.new()
	var people := _Mesh.new()   # the driver and passenger
	var driver_body := PackedInt32Array()   # people's vertices on the driver's body (head included)
	var driver_limbs := {}   # ... and on each of his limbs (name -> PackedInt32Array)
	# Pop-up headlamps: the "HeadLight" part, modelled down. The 914's and 944's rise by the
	# .tpg's headlightextent (m) while the lights are on; the 928's (a negative extent) lie
	# flat in the wings, lenses to the sky, and swing up about their front edge (the part's
	# origin, its hinge) until their back is that far up, lenses ahead.
	var popup_rise := float(tpg.get("header", {}).get("headlightextent", "0"))
	var popup := _Mesh.new()
	var popup_hinge := Vector3.ZERO
	var popup_lamps: Array[int] = []   # the lights on them, turned up with them once they're read
	var spoiler_down := _Mesh.new()
	var spoiler_up := _Mesh.new()
	var spoiler_moving := _Mesh.new()   # SpoilerW, its frames the blend shapes
	var spoiler_fixed := _Mesh.new()    # a spoiler that doesn't rise (slot 6), its own part to lose
	var skirts := {}   # SKIRT_SLOTS' groups -> their _Mesh (the sills both sides in one, split after)
	var wipers := {}       # wiper number -> its arm and blade (_Mesh), in their frames if they have them
	# What opens: group -> its bodywork, its glass (_Mesh) and hinge (car space); the windows
	# by door; the bays by the lid over them. pane_of: a part's mesh -> the mesh its glass goes to.
	var lids := {}
	var lid_hinge := {}
	var windows := {}
	var insides := {}   # a lid's underside: shown only while it's open (it shows through it shut)
	var bays := {}
	var pane_of := {body: glass}
	var spoiler_group := 0   # the spoiler rides on this lid (the boot), or 0
	var pipe_verts := PackedVector3Array()   # the exhaust parts' corners (car space)
	var wiper_arms := {}   # wiper number -> its arm's vertices (car space)
	# A cabriolet's hood, up (the top, its frame and rear window, that window's glass) and
	# folded: shown one or the other ("hood" up / down).
	var hood_up := _Mesh.new()
	var hood_glass := _Mesh.new()
	var hood_folded := _Mesh.new()
	var hood_top := _Mesh.new()          # the soft top itself, folding (blend shapes)
	var hood_top_glass := _Mesh.new()    # its rear window's pane
	var wheel_meshes: Array = [null, null, null, null]
	var needles := {}   # SPEEDO_NEEDLE / TACH_NEEDLE -> [its _Mesh, hub, the dial's normal] (car space)
	var mirrors := {}   # MIRROR_LEFT / MIRROR_RIGHT -> its glass (_Mesh); the first article each side
	var housings := {}  # ... -> [its housing, any glass of it] (_Mesh), riding on the door
	var wheel_hubs: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var full_arms := false   # the style's hands slot has a variant in the model
	for art in crp.articles:
		var base := crp.sub(art, "Base")
		if base != null and crp.data[base.offset + 68] == HANDS_SLOT \
				and crp.data[base.offset + 69] == want.get(HANDS_SLOT, 0):
			full_arms = true
			break
	for art in crp.articles:
		var base := crp.sub(art, "Base")
		if base == null:
			continue
		var bi := crp.data.slice(base.offset + 68, base.offset + 84)
		var ef := crp.sub(art, "ef")
		if ef != null:
			# Like the parts, a style shows its slot's variant of the lamps (the 356 A coupé's
			# and cabriolet's brake lamps, the 996 Turbo's). The 914's and 944's pop-ups are
			# modelled down: their lamps shine from where they rise to.
			var level := crp.data[base.offset + EF_LEVEL_AT] if base.length > EF_LEVEL_AT else PART_LEVEL
			if level == PART_LEVEL and bi[1] == want.get(bi[0], 0):
				var rise := Vector3(0.0, popup_rise, 0.0) if bi[7] == POPUP_GROUP and popup_rise > 0.0 else Vector3.ZERO
				var first := lights.size()
				_add_light(crp, ef, art.name, _transform(crp, crp.sub(art, "tr", PART_LEVEL)).origin + rise, false, bi[7])
				if bi[7] == POPUP_GROUP and popup_rise < 0.0:
					popup_lamps.append_array(range(first, lights.size()))
			continue
		var lvl := bi[10]
		var spoiler_moves: bool = lvl == SPOILER_MOVE_LEVEL and art.name.begins_with("SpoilerW") \
				and want.get(SPOILER_SLOT, 0) % 2 == 1 and bi[8] > 1
		var lid_inside: bool = lvl == LID_INSIDE_LEVEL and bi[7] in [BONNET, BOOT]
		if lvl not in SHOWN_LEVELS and not (lvl == 0x1E and bi[0] in CABRIO_SLOTS) and not spoiler_moves \
				and not lid_inside and lvl != BAY_LEVEL:
			continue
		# Each driver comes once more at lower detail, and drawn with him it would give him a
		# second pair of hands: his stand-in (LODDriverN: body, arms and hands in one, unposed).
		if lvl in PEOPLE_LEVELS and art.name.to_lower().begins_with("lod"):
			continue
		var slot := bi[0]
		var variant := bi[1]
		var raised: bool = slot == SPOILER_SLOT and want.get(slot, 0) % 2 == 1 and variant == want.get(slot, 0) + 1
		var folded: bool = slot == HOOD_SLOT and _hood_folded != 0 and variant == _hood_folded
		# Slot 0 is the parts every version has (doors, mirrors, wipers): their variant 0.
		if variant != want.get(slot, 0) and not raised and not folded:
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
		var leans := lvl == PEOPLE_LEVELS[0] and slot == DRIVER_SLOT and bi[8] >= BODY_FRAMES
		if leans:
			frame = PART_LEVEL | BODY_FRAMES / 2 << 4
		# A cabriolet's soft top folds the same way: frames from raised (byte 9, at rest) to
		# folded behind the seats (the last), the car's blend shapes (hood "top").
		# The moving spoiler and the wipers with frames have theirs from the first.
		var top_frames: Array[PackedVector3Array] = []
		var top_frames_n: Array[PackedVector3Array] = []
		var wiper := int(art.name[5]) if art.name.begins_with("Wiper") and art.name.length() > 5 else -1
		var framed := spoiler_moves or wiper >= 0 and bi[8] > 1
		if _hood_folded != 0 and slot == CABRIO_TOP_SLOT and bi[8] > 1 or framed:
			for f in range(0 if framed else bi[9], bi[8]):
				top_frames.append(crp.vec3s(crp.sub(art, "vt", PART_LEVEL | f << 4)))
				top_frames_n.append(crp.vec3s(crp.sub(art, "nm", PART_LEVEL | f << 4)))
			if top_frames.any(func(fv: PackedVector3Array) -> bool: return fv.size() != top_frames[0].size()) \
					or top_frames[0].is_empty():
				top_frames.clear()
				if spoiler_moves:
					continue
			elif not framed:
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
		if wheel >= 0:
			z_bias = WHEEL_BIAS
		var bias := -z_bias * (DEPTH_BIAS_STEP if z_bias < 0 else DEPTH_BIAS_STEP_BACK)
		var into: _Mesh = people if lvl in PEOPLE_LEVELS else body
		# An arm or hand's steering sweep (people.sweep): its side, and its frames with
		# their normals; the driver's body leans with them. The legs and passenger stay as they are.
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
		# The body's lean, stretched over the arms' frames (theirs at full lock, its too), the
		# other way round: its first frame leans with their last (the shoulder up on the side
		# whose hand is at the top of the wheel), else their sleeves come off the shoulders.
		if into == people and leans:
			var lean: Array[PackedVector3Array] = []
			var lean_n: Array[PackedVector3Array] = []
			for f in BODY_FRAMES:
				lean.append(crp.vec3s(crp.sub(art, "vt", PART_LEVEL | f << 4)))
				lean_n.append(crp.vec3s(crp.sub(art, "nm", PART_LEVEL | f << 4)))
				if lean[f].size() != verts.size() or lean_n[f].size() != verts.size():
					lean.clear()
					break
			if not lean.is_empty():
				_mend_lean(lean, lean_n)
				side = BODY_SIDE
				for f in STEER_FRAMES:
					var t := float(STEER_FRAMES - 1 - f) * (BODY_FRAMES - 1) / (STEER_FRAMES - 1)
					var k := mini(int(t), BODY_FRAMES - 2)
					var p := PackedVector3Array()
					var n := PackedVector3Array()
					p.resize(verts.size())
					n.resize(verts.size())
					for i in verts.size():
						p[i] = lean[k][i].lerp(lean[k + 1][i], t - k)
						n[i] = lean_n[k][i].lerp(lean_n[k + 1][i], t - k)
					sweep.append(p)
					sweep_n.append(n)
		# (Hands with a sweep follow the wheel by it, not by turning with it.)
		var steers := 1.0 if lvl == STEER_LEVEL else 0.75 if slot == HANDS_SLOT and side < 0 else 0.0
		# Where he has both pairs of arms (IN_CAR_MARK), each is drawn in its own view.
		if full_arms and side in [0, 1]:
			steers = IN_CAR_MARK if slot == HANDS_SLOT else HEAD_MARK
		if slot == WHEEL_WELL_SLOT or slot == BOTTOM_SLOT:
			steers = ONE_SIDED_MARK
		if lid_inside:
			# (Drawn only from below, it can come forward like a decal over the skin's back.)
			steers = ONE_SIDED_MARK
			bias = maxf(bias, LID_INSIDE_BIAS)
		if slot == SPOILER_SLOT and want.get(slot, 0) % 2 == 1:
			into = spoiler_up if raised else spoiler_down
		if _hood_folded != 0 and slot in CABRIO_SLOTS:
			into = hood_folded if folded else hood_top if slot == CABRIO_TOP_SLOT else hood_up
		if spoiler_moves:
			into = spoiler_moving
		var wiper_key := -1
		if wiper >= 0:
			# (One in frames on its own: the others' frames are made after.)
			wiper_key = wiper + (100 if not top_frames.is_empty() else 0)
			if not wipers.has(wiper_key):
				wipers[wiper_key] = _Mesh.new()
				wiper_arms[wiper_key] = PackedVector3Array()
			into = wipers[wiper_key]
		if slot == NEEDLE_SLOT and bi[7] in [SPEEDO_NEEDLE, TACH_NEEDLE] and xf.origin != Vector3.ZERO \
				and not needles.has(bi[7]):
			# The face's normal, forward (away from the driver): the needle turns clockwise
			# as he sees it by a positive angle about it.
			var normal := _to_car(xf.basis.z).normalized()
			needles[bi[7]] = [_Mesh.new(), _to_car(xf.origin), normal if normal.z >= 0.0 else -normal]
			into = needles[bi[7]][0]
		# The opening parts: their own meshes, about their group's hinge; the windows within
		# their doors; the bays under the lids.
		var group: int = bi[7] if bi[7] in LID_GROUPS else 0
		if art.name.begins_with("Exhaust"):
			for v in verts:
				pipe_verts.append(_to_car(xf * Vector3(-v.x, v.y, v.z)))
		if group != 0 and not lid_hinge.has(group) and crp.sub(art, "tr", PART_LEVEL) != null:
			lid_hinge[group] = _to_car(xf.origin)
		if lvl == BAY_LEVEL:
			var z := 0.0
			for v in verts:
				z += v.z
			var under := BONNET if z < 0.0 else BOOT   # (the files' front is -Z)
			if not bays.has(under):
				bays[under] = _Mesh.new()
			into = bays[under]
		elif into == body and slot == FIXED_SPOILER_SLOT and lvl != SPOILER_MOVE_LEVEL:
			into = spoiler_fixed
			spoiler_group = group if group == BOOT else spoiler_group
		elif into == body and group == 0 and SKIRT_SLOTS.has(slot):
			if not skirts.has(SKIRT_SLOTS[slot]):
				skirts[SKIRT_SLOTS[slot]] = _Mesh.new()
			into = skirts[SKIRT_SLOTS[slot]]
		elif into == body and slot == MIRROR_SLOT and group in [MIRROR_LEFT, MIRROR_RIGHT]:
			if not housings.has(group):
				housings[group] = [_Mesh.new(), _Mesh.new()]
				pane_of[housings[group][0]] = housings[group][1]
			into = housings[group][0]
		elif group != 0 and into == body:
			var parts: Dictionary = windows if slot == WINDOW_SLOT and group in [DOOR_LEFT, DOOR_RIGHT] \
					else insides if lid_inside else lids
			if not parts.has(group):
				parts[group] = [_Mesh.new(), _Mesh.new()]
				pane_of[parts[group][0]] = parts[group][1]
			into = parts[group][0]
		elif group == BOOT and (into == spoiler_up or into == spoiler_down or into == spoiler_moving):
			spoiler_group = BOOT
		var mirror: _Mesh = null
		if slot == MIRROR_SLOT and bi[7] in [MIRROR_LEFT, MIRROR_RIGHT] and not mirrors.has(bi[7]):
			mirror = _Mesh.new()
			mirrors[bi[7]] = mirror
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
			var p := crp.part(pe, slot == NEEDLE_SLOT)   # (the needles' corners come in order)
			var m: Array = mats.get(p.material, [0, false])
			# The windows from inside: the outside's glass is see-through already. (Some
			# cabins' panes are a translucent tint on intglass.fsh that would draw solid;
			# the needles share that page.)
			if (m[1] or slot in INNER_GLASS_SLOTS and _intglass_pages.has(m[0])) and lvl in INTERIOR_LEVELS:
				continue
			var rect: Rect2 = pages[m[0]] if m[0] >= 0 and m[0] < pages.size() else Rect2(0, 0, 0, 0)
			var vi: PackedInt32Array = p.vertex
			var ui: PackedInt32Array = p.uv
			for t3 in range(0, vi.size() - 2, 3):
				var dst: _Mesh = into
				# A window page's triangles run over its pane, seal and rim alike: they go to both
				# the bodywork and the glass, marked (WINDOW_MARK), and each shader draws only its
				# own texels of them (car.gdshader the seal and rim, car_glass.gdshader the pane).
				var dsts: Array[_Mesh] = []
				if m[1] and wheel < 0:
					var solid: _Mesh = body
					var clear: _Mesh = glass
					if into == hood_up:
						solid = hood_up
						clear = hood_glass
					elif into == hood_top:
						solid = hood_top
						clear = hood_top_glass
					elif into == hood_folded:
						solid = into
						clear = into
					elif pane_of.has(into):
						solid = into
						clear = pane_of[into]
					if _window_pages.has(m[0]) and solid != clear:
						dsts = [solid, clear]
					else:
						dst = clear if _on_pane(m[0], uvs, ui, t3) else solid
				var marked := dsts.size() == 2
				if mirror != null and not m[1]:
					# (Its normal in the game's own space, unmirrored: +Z is back.)
					var a := xf * (verts[vi[t3]] if vi[t3] < verts.size() else Vector3.ZERO)
					var b := xf * (verts[vi[t3 + 1]] if vi[t3 + 1] < verts.size() else Vector3.ZERO)
					var c3 := xf * (verts[vi[t3 + 2]] if vi[t3 + 2] < verts.size() else Vector3.ZERO)
					if (b - a).cross(c3 - a).normalized().z > 0.7:
						dst = mirror
				if not marked:
					dsts = [dst]
				for d: _Mesh in dsts:
					dst = d
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
						var finish: Color = m[2] if m.size() > 2 else Color(0.5, 0.0, 0.0, 1.0)
						if marked:
							finish.b = WINDOW_MARK
						dst.col.append(finish)
						dst.steer.append(steers)
						if wiper_key >= 0 and art.name.ends_with("a"):
							wiper_arms[wiper_key].append(dst.pos[dst.pos.size() - 1])
						if (dst == hood_top or dst == hood_top_glass or framed and dst == into) and not top_frames.is_empty():
							if dst.shapes.is_empty():
								for f in top_frames.size():
									dst.shapes.append(PackedVector3Array())
									dst.shape_nrm.append(PackedVector3Array())
							var at := vi[t3 + c]
							for f in mini(top_frames.size(), dst.shapes.size()):
								var fv := top_frames[f][at] if at < top_frames[f].size() else v
								var fn := top_frames_n[f][at] if at < top_frames_n[f].size() else Vector3.ZERO
								dst.shapes[f].append(_to_car(xf * Vector3(-fv.x, fv.y, fv.z)))
								dst.shape_nrm[f].append(_to_car(xf.basis * Vector3(-fn.x, fn.y, fn.z)).normalized())
						if dst == people:
							var at := vi[t3 + c]
							for f in STEER_FRAMES:
								var fv := sweep[f][at] if side >= 0 and at < sweep[f].size() else v
								var fn := sweep_n[f][at] if side >= 0 and at < sweep_n[f].size() else Vector3.ZERO
								people.frames[f].append(_to_car(xf * Vector3(-fv.x, fv.y, fv.z)))
								people.frame_nrm[f].append(_to_car(xf.basis * Vector3(-fn.x, fn.y, fn.z)).normalized())
							people.side.append(side)
							people.hand.append(1 if slot == HANDS_SLOT else 0)
							people.part_names.append(art.name)  # DRVDBG
							if slot == DRIVER_SLOT and lvl == PEOPLE_LEVELS[0]:
								driver_body.append(people.pos.size() - 1)
							elif slot == LIMBS_SLOT and lvl == PEOPLE_LEVELS[0]:
								if not driver_limbs.has(art.name):
									driver_limbs[art.name] = PackedInt32Array()
								driver_limbs[art.name].append(people.pos.size() - 1)
	# Centre the model on its body, as the FCE models are.
	var box := body.box()
	# (The skirts and spoiler are the body too, for its size.)
	for m: _Mesh in skirts.values() + [spoiler_fixed]:
		if not m.pos.is_empty():
			box = box.merge(m.box())
	var mid := box.get_center()
	body.panelise(box)
	glass.panelise(box)
	half_size = box.size * 0.5
	var hb := {"name": ":hb", "mesh": body.commit(-mid), "center": Vector3.ZERO, "damaged": body.damaged(-mid)}
	var column := body.steering_column()
	for limb: PackedInt32Array in driver_limbs.values():
		people.seat_limb(limb, driver_body)
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
		part.loose = SPOILER
		body_parts.append(part)
	if not spoiler_fixed.pos.is_empty():
		spoiler_fixed.panelise(box)
		body_parts.append({"name": "spoiler", "mesh": spoiler_fixed.commit(-mid), "center": Vector3.ZERO,
			"damaged": spoiler_fixed.damaged(-mid), "spoiler": "fixed", "loose": SPOILER})
	# The skirts, each its own part to lose: the sills split left (+X) and right.
	if skirts.has(SILL_LEFT):
		var sills: _Mesh = skirts[SILL_LEFT]
		skirts[SILL_LEFT] = sills.pick(func(c: Vector3) -> bool: return c.x >= 0.0)
		skirts[SILL_RIGHT] = sills.pick(func(c: Vector3) -> bool: return c.x < 0.0)
	for g: int in skirts:
		var sm: _Mesh = skirts[g]
		if sm.pos.is_empty():
			continue
		sm.panelise(box)
		body_parts.append({"name": "skirt%d" % g, "mesh": sm.commit(-mid), "center": Vector3.ZERO,
			"damaged": sm.damaged(-mid), "loose": g})
	# ... and on its way between them. (It doesn't dent: its frames are the blend shapes.)
	if not spoiler_moving.pos.is_empty() and not spoiler_up.pos.is_empty() and not spoiler_down.pos.is_empty():
		spoiler_moving.face_shape_normals()
		spoiler_moving.clear_under_wing(texture.get_image() if texture != null else null)
		body_parts.append({"name": "spoiler_moving", "mesh": spoiler_moving.commit(-mid), "center": Vector3.ZERO,
			"spoiler": "moving", "spoiler_frames": spoiler_moving.shapes.size(), "loose": SPOILER})
	# The wipers, from parked (blend shape 0) to the top of their sweep (the last).
	for key: int in wipers:
		var wm: _Mesh = wipers[key]
		if wm.pos.is_empty():
			continue
		if wm.shapes.is_empty():
			_sweep_wiper(wm, wiper_arms[key], glass)
		wm.face_shape_normals()
		body_parts.append({"name": "wiper%d" % key, "mesh": wm.commit(-mid), "center": Vector3.ZERO,
			"wiper_frames": wm.shapes.size()})
	# What opens: each door and lid about its hinge (see LID_OPEN), turned the way that takes
	# its free edge out from the body or up; the windows down into their doors; the bays.
	var lid_motion := {}
	for group: int in lids:
		if not lid_hinge.has(group):
			continue
		var lm: _Mesh = lids[group][0]
		var hinge: Vector3 = lid_hinge[group]
		var door := group in [DOOR_LEFT, DOOR_RIGHT]
		var axis := Vector3.UP if door else Vector3.RIGHT
		var c := lm.box().get_center() if not lm.pos.is_empty() else hinge
		var out := Vector3(signf(c.x), 0.0, 0.0) if door else Vector3.UP
		var turn: float = LID_OPEN[group]
		if (Basis(axis, turn) * (c - hinge) - (c - hinge)).dot(out) < 0.0:
			turn = -turn
		lid_motion[group] = {"lid": group, "hinge": hinge - mid, "axis": axis, "open": turn}
		for k in 2:
			var part_mesh: _Mesh = lids[group][k]
			if part_mesh.pos.is_empty():
				continue
			part_mesh.panelise(box)
			var part := {"name": "lid%d%s" % [group, "_glass" if k == 1 else ""], "mesh": part_mesh.commit(-mid),
				"center": Vector3.ZERO, "damaged": part_mesh.damaged(-mid)}.merged(lid_motion[group])
			if k == 1:
				part.glass = true
			body_parts.append(part)
	# The side mirrors, on their doors and to lose apart from them.
	for side: int in housings:
		for k in 2:
			var hm: _Mesh = housings[side][k]
			if hm.pos.is_empty():
				continue
			hm.panelise(box)
			var part := {"name": "mirror%d%s" % [side, "_glass" if k == 1 else ""], "mesh": hm.commit(-mid),
				"center": Vector3.ZERO, "damaged": hm.damaged(-mid), "loose": MIRROR_OFF[side]}
			part.merge(lid_motion.get(side, {}))
			if k == 1:
				part.glass = true
			body_parts.append(part)
	for group: int in windows:
		var wbox := AABB()
		var first := true
		for k in 2:
			for v in (windows[group][k] as _Mesh).pos:
				wbox = AABB(v, Vector3.ZERO) if first else wbox.expand(v)
				first = false
		# The lean: the window's x against its height, fitted (see WINDOW_DROP).
		var n := 0.0
		var sy := 0.0
		var sx := 0.0
		var syy := 0.0
		var sxy := 0.0
		for k in 2:
			for v in (windows[group][k] as _Mesh).pos:
				n += 1.0
				sy += v.y
				sx += v.x
				syy += v.y * v.y
				sxy += v.x * v.y
		var lean := 0.0
		var vy := syy - sy * sy / n
		if vy > 1e-6:
			lean = (sxy - sx * sy / n) / vy   # dx per dy
		var drop := Vector3(-lean, -1.0, 0.0) * wbox.size.y * WINDOW_DROP
		# The belt: y = a + b z (door frame, less `mid`) along the pane's foot, just under
		# its lowest vertices, so the pane wound up is whole.
		var foot := PackedVector3Array()
		for k in 2:
			for v in (windows[group][k] as _Mesh).pos:
				if v.y < wbox.position.y + WINDOW_BELT_BAND:
					foot.append(v - mid)
		var fz := 0.0
		var fy := 0.0
		for v in foot:
			fz += v.z
			fy += v.y
		fz /= foot.size()
		fy /= foot.size()
		var szz := 0.0
		var szy := 0.0
		for v in foot:
			szz += (v.z - fz) * (v.z - fz)
			szy += (v.z - fz) * (v.y - fy)
		var slope := szy / szz if szz > 1e-4 else 0.0
		var belt_a := INF
		for v in foot:
			belt_a = minf(belt_a, v.y - slope * v.z)
		var belt := Vector2(belt_a - 0.002, slope)
		for k in 2:
			var wm: _Mesh = windows[group][k]
			if wm.pos.is_empty():
				continue
			var part := {"name": "window%d%s" % [group, "_glass" if k == 1 else ""], "mesh": wm.commit(-mid),
				"center": Vector3.ZERO, "window": group, "drop": drop, "belt": belt}
			if lid_motion.has(group):
				part.merge(lid_motion[group])
			if k == 1:
				part.glass = true
			body_parts.append(part)
	for group: int in insides:
		for k in 2:
			var im: _Mesh = insides[group][k]
			if im.pos.is_empty() or not lid_motion.has(group):
				continue
			var part := {"name": "lid%d_inside%s" % [group, "_glass" if k == 1 else ""], "mesh": im.commit(-mid),
				"center": Vector3.ZERO, "bay": group}.merged(lid_motion[group])
			if k == 1:
				part.glass = true
			body_parts.append(part)
	for under: int in bays:
		var bm: _Mesh = bays[under]
		if not bm.pos.is_empty():
			body_parts.append({"name": "bay%d" % under, "mesh": bm.commit(-mid), "center": Vector3.ZERO, "bay": under})
	# The spoiler on the engine lid, and the mirrors' glass on the doors, go with them.
	for p in body_parts:
		if p.has("spoiler") and spoiler_group != 0 and lid_motion.has(spoiler_group):
			p.merge(lid_motion[spoiler_group])
	for hp: Array in [[hood_up, "up", false], [hood_glass, "up", true], [hood_folded, "down", false],
			[hood_top, "top", false], [hood_top_glass, "top", true]]:
		var hm: _Mesh = hp[0]
		if hm.pos.is_empty():
			continue
		hm.panelise(box)
		hm.face_shape_normals()
		var part := {"name": "hood_" + hp[1], "mesh": hm.commit(-mid), "center": Vector3.ZERO, "hood": hp[1]}
		# (A folding top doesn't dent: its frames are the blend shapes.)
		if hm.shapes.is_empty():
			part.damaged = hm.damaged(-mid)
		else:
			part.hood_frames = hm.shapes.size()
		if hp[2]:
			part.glass = true
		body_parts.append(part)
	if not popup.pos.is_empty():
		var up := popup
		var up_at := Vector3.ZERO
		# How they go down again (Car animates them): straight down, or turned back about the hinge.
		var motion := {}
		if popup_rise > 0.0:
			up_at = Vector3(0.0, popup_rise, 0.0)
			motion = {"sink": popup_rise}
		else:
			var reach := maxf(popup_hinge.z - popup.box().position.z, -popup_rise)
			var turn := Basis(Vector3.RIGHT, asin(-popup_rise / reach))   # lifts the back (-Z)
			up = popup.turned(turn, popup_hinge)
			for i in popup_lamps:
				lights[i].pos = popup_hinge + turn * (lights[i].pos - popup_hinge)
			motion = {"hinge": popup_hinge - mid, "fold": -turn.get_euler().x}
		popup.panelise(box)
		body_parts.append({"name": "popup_closed", "mesh": popup.commit(-mid), "center": Vector3.ZERO,
			"popup_closed": true, "damaged": popup.damaged(-mid)})
		popup_lights.append({"name": "popup", "mesh": up.commit(-mid), "center": up_at}.merged(motion))
	var eye := _mark_head(people, driver_body)
	if eye != Vector3.INF:
		dash = {"eye": eye - mid, "own_cabin": true}
	if not people.pos.is_empty():
		# They don't dent: no "damaged". Their arms and hands follow the wheel by blend
		# shapes, one per angle in "steer_shapes" (car.gdshader's steer_angle); without a
		# sweep the hands turn with it on the wheel's column.
		var dp := {"name": "driver", "mesh": people.commit(-mid), "center": Vector3.ZERO, "driver": true}
		if hb.has("steering"):
			dp.steering = hb.steering
		if not steer_angles.is_empty():
			dp.steer_shapes = steer_angles
			dp.part_names = people.part_names  # DRVDBG
		body_parts.append(dp)
	for side: int in mirrors:
		var gm: _Mesh = mirrors[side]
		if gm.pos.is_empty():
			continue
		# A point on the glass and its normal (the glass is near enough flat): each triangle's
		# face normal by its area, turned back (the glass faces the driver's way back).
		var point := Vector3.ZERO
		var normal := Vector3.ZERO
		var area := 0.0
		for i in range(0, gm.pos.size() - 2, 3):
			var n := (gm.pos[i + 2] - gm.pos[i]).cross(gm.pos[i + 1] - gm.pos[i])
			var w := n.length()
			point += (gm.pos[i] + gm.pos[i + 1] + gm.pos[i + 2]) / 3.0 * w
			normal += n if n.z <= 0.0 else -n
			area += w
		if area <= 0.0:
			continue
		body_parts.append({"name": "mirror_glass_%s" % ("left" if side == MIRROR_LEFT else "right"),
			"mesh": gm.commit(-mid), "center": Vector3.ZERO, "loose": MIRROR_OFF[side],
			"mirror_glass": {"point": point / area - mid, "normal": normal.normalized()}}.merged(lid_motion.get(side, {})))
	for kind: int in needles:
		var nm: _Mesh = needles[kind][0]
		if nm.pos.is_empty():
			continue
		var hub: Vector3 = needles[kind][1]
		var axis: Vector3 = needles[kind][2]
		# Where it points as modelled: its tip (the corner farthest from the hub), flat on the
		# dial, from straight up on the dial, clockwise as the driver sees it.
		var tip := Vector3.ZERO
		for v in nm.pos:
			if v.distance_squared_to(hub) > tip.length_squared():
				tip = v - hub
		tip -= axis * axis.dot(tip)
		var up := Vector3.UP - axis * axis.y
		var modelled := atan2(axis.dot(up.cross(tip)), up.dot(tip))
		body_parts.append({"name": "needle_rpm" if kind == TACH_NEEDLE else "needle_speed",
			"mesh": nm.commit(-hub), "center": hub - mid, "needle": "rpm" if kind == TACH_NEEDLE else "speed",
			"axis": axis, "zero": NEEDLE_ZERO * TAU - modelled})
	if not glass.pos.is_empty():
		body_parts.append({"name": "glass", "mesh": glass.commit(-mid), "center": Vector3.ZERO, "glass": true,
			"damaged": glass.damaged(-mid)})
	for w in 4:
		if wheel_meshes[w] != null:
			wheels.append({"name": "wheel%d" % w, "mesh": wheel_meshes[w].commit(Vector3.ZERO), "center": wheel_hubs[w] - mid})
	for l in lights:
		l.pos -= mid
	for gl in glints:
		gl.pos -= mid
	for i in exhausts.size():
		exhausts[i] -= mid
	# Without a glint marking them, the pipes' ends: each Exhaust part's rearmost corners.
	if exhausts.is_empty():
		exhausts = _pipe_ends(pipe_verts, mid)


## A parked wiper's sweep, as its blend shapes (see WIPER_SWEEP): turned about the arm's far
## end (the wiper's end away from its middle) in the plane it lies in, the blade's tip going
## up the glass; each vertex over the glass kept as far off it as it's parked (or, parked
## on the scuttle, just clear of it), the glass curving away from that plane.
static func _sweep_wiper(wm: _Mesh, arm: PackedVector3Array, glass: _Mesh) -> void:
	var centre := Vector3.ZERO
	for p in wm.pos:
		centre += p
	centre /= wm.pos.size()
	var pivot := centre
	for p in (arm if not arm.is_empty() else wm.pos):
		if p.distance_squared_to(centre) > pivot.distance_squared_to(centre):
			pivot = p
	var tip := pivot
	for p in wm.pos:
		if p.distance_squared_to(pivot) > tip.distance_squared_to(pivot):
			tip = p
	var reach := tip.distance_to(pivot) + 0.1
	var panes := PackedVector3Array()
	for i in range(0, glass.pos.size() - 2, 3):
		if glass.pos[i].distance_to(pivot) < reach + 0.6:
			panes.append_array([glass.pos[i], glass.pos[i + 1], glass.pos[i + 2]])
	# The plane it sweeps in: the windscreen's round it (its triangles facing forward, by
	# area), else the wiper's own (its blade's rubber stands up off the glass).
	var axis := Vector3.ZERO
	for i in range(0, panes.size() - 2, 3):
		var fn := (panes[i + 2] - panes[i]).cross(panes[i + 1] - panes[i])
		fn = fn if fn.y >= 0.0 else -fn
		if fn.normalized().z > 0.3:
			axis += fn
	if axis.length_squared() < 1e-12:
		for i in range(0, wm.pos.size() - 2, 3):
			var fn := (wm.pos[i + 2] - wm.pos[i]).cross(wm.pos[i + 1] - wm.pos[i])
			axis += fn if fn.y >= 0.0 else -fn
	if axis.length_squared() < 1e-12:
		return
	axis = axis.normalized()
	# Up the glass: its slope, rising towards the back (a raked screen's plane is nearly level).
	var slope := (Vector3.UP - axis * axis.y).normalized()
	var turn := 1.0 if (Basis(axis, 0.1) * (tip - pivot) - (tip - pivot)).dot(slope) > 0.0 else -1.0
	# How far off the glass each vertex rides.
	var low := INF
	for p in wm.pos:
		low = minf(low, (p - pivot).dot(axis))
	var lift := PackedFloat32Array()
	for p in wm.pos:
		var h := _glass_under(p, axis, panes)
		var off := (p - h).dot(axis) if h != Vector3.INF else INF
		lift.append(off if off > 0.0 and off < 0.08 else 0.012 + (p - pivot).dot(axis) - low)
	for f in WIPER_FRAMES:
		var b := Basis(axis, turn * WIPER_SWEEP * f / (WIPER_FRAMES - 1))
		var sp := PackedVector3Array()
		var sn := PackedVector3Array()
		for i in wm.pos.size():
			var q := pivot + b * (wm.pos[i] - pivot)
			if f > 0:
				var h := _glass_under(q, axis, panes)
				if h != Vector3.INF:
					q += axis * clampf(lift[i] - (q - h).dot(axis), -0.04, 0.04)
			sp.append(q)
			sn.append(b * wm.nrm[i])
		wm.shapes.append(sp)
		wm.shape_nrm.append(sn)


## The tail pipes' ends from the exhaust parts' corners: on each side, the middle of those
## within 4 cm of the rearmost (less `mid`).
static func _pipe_ends(verts: PackedVector3Array, mid: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for side in [1.0, -1.0]:
		var back := INF
		for v in verts:
			if signf(v.x) == side or v.x == 0.0 and side > 0.0:
				back = minf(back, v.z)
		if back == INF:
			continue
		var sum := Vector3.ZERO
		var n := 0
		for v in verts:
			if (signf(v.x) == side or v.x == 0.0 and side > 0.0) and v.z < back + 0.04:
				sum += v
				n += 1
		out.append(sum / n - mid)
	return out


## The glass (triangles, three corners each) under `p` along -`axis`, the nearest within
## 15 cm either side, or INF.
static func _glass_under(p: Vector3, axis: Vector3, panes: PackedVector3Array) -> Vector3:
	var best := Vector3.INF
	var from := p + axis * 0.15
	for i in range(0, panes.size() - 2, 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, -axis, panes[i], panes[i + 1], panes[i + 2])
		if hit != null and (hit as Vector3).distance_to(from) < 0.3 \
				and (best == Vector3.INF or (hit as Vector3).distance_to(p) < best.distance_to(p)):
			best = hit
	return best


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


## Marks the driver's head (the triangles of `body`, his body's vertices in `people`, that
## reach within HEAD_DEPTH of its top) with HEAD_MARK, and returns where his eyes are (car
## space, uncentred), or Vector3.INF without a driver.
static func _mark_head(people: _Mesh, body: PackedInt32Array) -> Vector3:
	if body.is_empty():
		return Vector3.INF
	var top := -INF
	for i in body:
		top = maxf(top, people.pos[i].y)
	var mid := Vector3.ZERO
	var n := 0
	for i in body:
		if people.pos[i].y > top - HEAD_DEPTH:
			mid += people.pos[i]
			n += 1
	# The triangles are stored a vertex each, three in a row: a triangle with a corner on the
	# head goes with it, so the neck's edge doesn't leave slivers behind.
	for i in body:
		if people.pos[i].y > top - HEAD_DEPTH:
			var t := i - i % 3
			for k in 3:
				people.steer[t + k] = HEAD_MARK
	mid /= n
	return Vector3(mid.x, top - EYE_BELOW_TOP, mid.z)


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
## reversing lamps (kind 2) white at the back; mirrored ones on both sides.
func _add_light(crp: Crp, e: Crp.Entry, name: String, offset: Vector3, as_brake := false, group := 0) -> void:
	var d := crp.data
	var o := e.offset
	if o + 0x58 > d.size():
		return
	var pos := _to_car(offset + Vector3(d.decode_float(o + 8), d.decode_float(o + 12), d.decode_float(o + 16)))
	var kind := d[o + 84]
	var head := d[o + 87] == 1
	if kind == GLINT_KIND:
		var facing := _to_car(-Vector3(d.decode_float(o + 56), d.decode_float(o + 60), d.decode_float(o + 64))).normalized()
		for side in ([1.0, -1.0] if d.decode_u32(o + 80) != 0 else [1.0]):
			var p := Vector3(pos.x * side, pos.y, pos.z)
			if name.to_lower().contains("exhaust"):
				exhausts.append(p)
			else:
				glints.append({"pos": p, "facing": Vector3(facing.x * side, facing.y, facing.z),
					"lid": group if group in LID_GROUPS else 0})
		return
	var n := name.to_lower()
	# Its colour (B, G, R): amber, red or white.
	var red := d[o + 74] > 200 and d[o + 73] < 60 and d[o + 72] < 60
	var amber := d[o + 74] > 200 and d[o + 73] > 60 and d[o + 73] < 200 and d[o + 72] < 60
	var dname := ""
	if n.contains("siren"):
		# The light bar: red on the left, blue on the right, flashing in turn (Car's sirens).
		dname = "SML" if pos.x >= 0.0 else "SMR"
	elif head or n.contains("headlight"):
		dname = "HFLN"
	elif not as_brake and (kind in [3, 5] or n.contains("signal")):
		# The indicators (kind 3; the 935's 5), amber or (the 356s' at the back) red: Car
		# flashes a side's (I). The 356 A's and 550's red ones are their brake lamps too.
		dname = "IRYN" if red else "IOYN"
		if red and n.contains("brake"):
			_add_light(crp, e, name, offset, true)
	elif n.contains("fog"):
		dname = "FWYN"   # fog lamps, with the headlights in rain and snow (F)
	elif kind == 0 and n.contains("sidelight"):
		dname = "POYN2" if amber else "PWYN2"   # the 928's side markers, with the headlights
	elif kind == 1 or n.contains("brake"):
		dname = "TRLN"
	elif kind == 2 or n.contains("reverse"):
		dname = "RWYN3"
	elif kind == 0 and red:
		dname = "TRLN"   # the 935's tail lamps
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
## The cars you aren't driving play a single loop each of the engine and the exhaust,
## Sounds/zzzwzzz.viv's <set>lden.bnk and <set>ldex.bnk (sd6b's for the sets without; nfs5.exe
## "sd6b%.4s.bnk"): CarAudio's ocar.bnk and ocarex.bnk.
func _read_sounds(pu_root: String, set_name: String) -> void:
	if set_name == "":
		return
	var s := set_name.to_lower()
	var others := _others_engines(pu_root)
	for part in [["lden", "ocar.bnk"], ["ldex", "ocarex.bnk"]]:
		var b := others.get_file(s + part[0] + ".bnk") if others else PackedByteArray()
		if b.is_empty() and others:
			b = others.get_file("sd6b" + part[0] + ".bnk")
		if not b.is_empty():
			sound_files[part[1]] = b
	var viv := Viv.load_file(DataPath.find_ci(pu_root, "Sounds/" + set_name + ".viv"))
	if viv == null:
		return
	var bnk := viv.get_file(s + ".bnk")
	if bnk.is_empty():
		return
	sound_files["careng.bnk"] = bnk
	sound_files["careng.ctb"] = viv.get_file(s + ".ect")
	sound_files["careng.ltb"] = viv.get_file(s + ".elt")


## Sounds/zzzwzzz.viv, read once.
static func _others_engines(pu_root: String) -> Viv:
	if pu_root != _others_root:
		_others_root = pu_root
		_others_viv = Viv.load_file(DataPath.find_ci(pu_root, "Sounds/zzzwzzz.viv"))
	return _others_viv


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
			# (Its HSV: some sections' RGB is left at zero.)
			var i := Color.from_hsv(int(sec["color4.h"]) / 255.0, int(sec.get("color4.s", "0")) / 255.0,
				int(sec.get("color4.v", "0")) / 255.0) if sec.has("color4.h") else STOCK_INTERIOR
			interior_colours.append(Color(i.r * 2.0, i.g * 2.0, i.b * 2.0))
	if colours.is_empty():
		for c: Color in STOCK_PAINTS:
			colours.append(Color(c.r * 2.0, c.g * 2.0, c.b * 2.0))
			interior_colours.append(Color(STOCK_INTERIOR.r * 2.0, STOCK_INTERIOR.g * 2.0, STOCK_INTERIOR.b * 2.0))
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
	var col := PackedColorArray()        # its material's finish (see MAT_ENV_FROM_END)
	# The people's steering sweep: each vertex in each of the arms' and hands' frames (where
	# it is at rest on the parts that don't move), the side (0 left, 1 right, BODY_SIDE, -1 none) and
	# whether it's a hand; each side's rest frame. sweep() makes blend shapes of them.
	var frames: Array[PackedVector3Array] = []
	var frame_nrm: Array[PackedVector3Array] = []
	var side := PackedInt32Array()
	var hand := PackedByteArray()
	var part_names := PackedStringArray()  # DRVDBG
	var side_rest := {}
	var shapes: Array[PackedVector3Array] = []
	var shape_nrm: Array[PackedVector3Array] = []

	func _init() -> void:
		for f in STEER_FRAMES:
			frames.append(PackedVector3Array())
			frame_nrm.append(PackedVector3Array())
	var panels := PackedInt32Array()     # the panel (bit) each vertex is on

	## The triangles whose middle `keep` takes (the parts with no frames or sweep).
	func pick(keep: Callable) -> _Mesh:
		var m := _Mesh.new()
		for i in range(0, pos.size() - 2, 3):
			if not keep.call((pos[i] + pos[i + 1] + pos[i + 2]) / 3.0):
				continue
			for k in 3:
				m.pos.append(pos[i + k])
				m.uv.append(uv[i + k])
				m.bias.append(bias[i + k])
				m.nrm.append(nrm[i + k])
				m.steer.append(steer[i + k])
				m.dent.append(dent[i + k])
				if col.size() == pos.size():
					m.col.append(col[i + k])
		return m

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

	## Moves a limb (vertices `limb`: the legs, a forearm) onto the body (`body`) where they
	## meet, in every frame: in a few models they're off (the 993's legs 2 by 5 cm, placed by
	## their own "tr"; the 935's forearms by 1-3), a gap at the waist or elbow. The shift that
	## closes the few nearest pairs at rest, a few times over as the pairs change; none if it
	## comes to more than LIMB_SNAP.
	func seat_limb(limb: PackedInt32Array, body: PackedInt32Array) -> void:
		if limb.is_empty() or body.is_empty():
			return
		var shift := Vector3.ZERO
		for _pass in 4:
			var pairs: Array = []   # [distance², the limb vertex to its nearest body vertex]
			for i in limb:
				var best := INF
				var to := Vector3.ZERO
				for j in body:
					var d := pos[j] - (pos[i] + shift)
					if d.length_squared() < best:
						best = d.length_squared()
						to = d
				pairs.append([best, to])
			pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
			var step := Vector3.ZERO
			for k in mini(LIMB_SEAM, pairs.size()):
				step += pairs[k][1]
			shift += step / mini(LIMB_SEAM, pairs.size())
		if shift.length() > LIMB_SNAP:
			return
		for i in limb:
			pos[i] += shift
			dent[i] += shift
			for f in frames.size():
				frames[f][i] += shift

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

	## Each blend shape's normals turned to the side its triangle faces in that shape, as
	## _normals() does the rest pose's.
	func face_shape_normals() -> void:
		for f in shapes.size():
			var sp := shapes[f]
			if sp.size() != pos.size() or shape_nrm[f].size() != pos.size():
				continue
			for i in range(0, sp.size() - 2, 3):
				var fn := _face(sp, i)
				for k in 3:
					var n := shape_nrm[f][i + k]
					shape_nrm[f][i + k] = fn if n == Vector3.ZERO else (n if n.dot(fn) >= 0.0 else -n)

	## Under the moving spoiler's wing, once it's up (the 964's and 993's): the plate on the
	## lid that stays where it is through the frames wears the wing's grille (raised, it
	## looked lowered), and the legs the wing rises on, the moving faces drawn in a dark
	## under LEG_DARK, are black slabs; both go, leaving the wing on its end arms over the
	## lid. Still: moving under STILL_SHARE of the most any face does, on a wing that
	## rises at least STILL_RISE m. Returns how many faces it drops.
	const STILL_SHARE := 0.1
	const STILL_RISE := 0.05
	const LEG_DARK := 0.3
	func clear_under_wing(atlas: Image) -> int:
		if shapes.is_empty() or atlas == null or atlas.is_empty():
			return 0
		for sp in shapes:
			if sp.size() != pos.size():
				return 0
		var moves := PackedFloat32Array()
		var most := 0.0
		for i in range(0, pos.size() - 2, 3):
			var m := 0.0
			for sp in shapes:
				for k in 3:
					m = maxf(m, sp[i + k].distance_to(shapes[0][i + k]))
			moves.append(m)
			most = maxf(most, m)
		if most < STILL_RISE:
			return 0
		var size := Vector2(atlas.get_size() - Vector2i.ONE)
		var still := {}
		var legs := {}
		for i in range(0, pos.size() - 2, 3):
			if moves[i / 3] < most * STILL_SHARE:
				still[i] = true
				continue
			var lum := 0.0
			for k in 3:
				lum = maxf(lum, atlas.get_pixelv(Vector2i((uv[i + k].clamp(Vector2.ZERO, Vector2.ONE) * size).round())).get_luminance())
			if lum < LEG_DARK:
				legs[i] = true
		# (No plate, no legs: the Boxster's wing is drawn in its dark all over.)
		if still.is_empty():
			return 0
		legs.merge(still)
		_drop(legs)
		return legs.size()

	## Without the triangles whose first corners `tris` has, frames and all.
	func _drop(tris: Dictionary) -> void:
		if tris.is_empty():
			return
		var keep := func(i: int) -> bool: return not tris.has(i - i % 3)
		pos = _kept(pos, keep)
		nrm = _kept(nrm, keep)
		dent = _kept(dent, keep)
		for f in shapes.size():
			shapes[f] = _kept(shapes[f], keep)
			shape_nrm[f] = _kept(shape_nrm[f], keep)
		var u := PackedVector2Array()
		var c := PackedColorArray()
		var b := PackedFloat32Array()
		var s := PackedFloat32Array()
		for i in uv.size():
			if keep.call(i):
				u.append(uv[i])
				c.append(col[i])
				b.append(bias[i])
				s.append(steer[i])
		uv = u
		col = c
		bias = b
		steer = s

	static func _kept(a: PackedVector3Array, keep: Callable) -> PackedVector3Array:
		var out := PackedVector3Array()
		for i in a.size():
			if keep.call(i):
				out.append(a[i])
		return out

	## A copy turned by `basis` about `pivot` (car space), its damaged copy with it.
	func turned(basis: Basis, pivot: Vector3) -> _Mesh:
		var m := _Mesh.new()
		m.uv = uv
		m.col = col
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
				if s == BODY_SIDE:
					s = angles.keys()[0]
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
	## (`g` is held within them: the grid's angles are rounded, and an end one rounded past
	## the side's last frame would find no pair and fall back to frame 0, the other lock.)
	static func _between(a: PackedFloat32Array, g: float) -> Vector3:
		g = clampf(g, Array(a).min(), Array(a).max())
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
			if col.size() == pos.size():
				st.set_color(col[i])
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
