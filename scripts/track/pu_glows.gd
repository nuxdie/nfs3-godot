class_name PuGlows
## Porsche Unleashed's light flares on its tracks: at each light (Nfs5Track.lights: street
## lamps, tunnel lights, windows, beacons), the flare its type picks from
## GameData/Render/flare.dat, drawn at night (pu_glow.gdshader).
##
## flare.dat: 140-byte records, each its type and two sprites (common.fsh entries, "null"
## for none; all 4 characters backwards), then per sprite at 28 its colour (ARGB) and at 52
## its size, and at 80 a blink: its phase, ticks on and ticks off (0 on: steady; the
## Autobahn's chasing arrows, beacons, alternating warning lights).

const SHADER := preload("res://shaders/pu_glow.gdshader")
const RECORD := 140
## A flare size's half width (m) a unit: a street lamp's ("stry") wide glow 3 m, its core 0.6.
const SIZE_SCALE := 0.04

static var _flares := {}   # pu_root -> {type -> {sprites: [name, name], colours, sizes, blink}}


## The lights of `t` as flares under a new node, or null when there are none.
static func build(t: Nfs5Track, pu_root: String) -> Node3D:
	return glows(t.lights, pu_root)


## `lights` ({type, pos}, as Nfs5Track.lights) as flares under a new node, or null.
static func glows(lights: Array, pu_root: String) -> Node3D:
	if lights.is_empty() or pu_root == "":
		return null
	var flares := _load(pu_root)
	var per_sprite := {}   # sprite -> [[position, colour, custom], ...]
	for li: Dictionary in lights:
		var f: Dictionary = flares.get(li.type, {})
		if f.is_empty():
			continue
		for k in 2:
			var sprite: String = f.sprites[k]
			var c: Color = f.colours[k]
			if sprite == "null" or c.a <= 0.0 or f.sizes[k] <= 0.0:
				continue
			var b: Vector3 = f.blink
			per_sprite.get_or_add(sprite, []).append([li.pos, c,
				Color(f.sizes[k] * SIZE_SCALE, b.x, b.y, b.z)])
	if per_sprite.is_empty():
		return null
	var root := Node3D.new()
	root.name = "Glows"
	for sprite: String in per_sprite:
		var tex := Nfs5Car.fx(sprite)
		if tex == null:
			continue
		var list: Array = per_sprite[sprite]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		var quad := QuadMesh.new()
		quad.size = Vector2(2.0, 2.0)
		mm.mesh = quad
		mm.instance_count = list.size()
		var box := AABB(list[0][0], Vector3.ZERO)
		for i in list.size():
			mm.set_instance_transform(i, Transform3D(Basis(), list[i][0]))
			mm.set_instance_color(i, list[i][1])
			mm.set_instance_custom_data(i, list[i][2])
			box = box.expand(list[i][0])
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("sprite", tex)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = sprite.validate_node_name()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = box.grow(10.0)
		root.add_child(mmi)
	return root if root.get_child_count() > 0 else null


static func _load(pu_root: String) -> Dictionary:
	if _flares.has(pu_root):
		return _flares[pu_root]
	var out := {}
	var path := DataPath.find_ci(pu_root, "Render/flare.dat")
	var d := FileAccess.get_file_as_bytes(path) if path != "" else PackedByteArray()
	for at in range(0, d.size() - RECORD + 1, RECORD):
		var argb := func(o: int) -> Color:
			var v := d.decode_u32(at + o)
			return Color8((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF, (v >> 24) & 0xFF)
		out[_name(d, at)] = {
			"sprites": [_name(d, at + 4), _name(d, at + 8)],
			"colours": [argb.call(28), argb.call(32)],
			"sizes": [d.decode_float(at + 52), d.decode_float(at + 56)],
			"blink": Vector3(d.decode_u32(at + 80), d.decode_u32(at + 84), d.decode_u32(at + 88)),
		}
	_flares[pu_root] = out
	return out


static func _name(d: PackedByteArray, at: int) -> String:
	var b := d.slice(at, at + 4)
	b.reverse()
	return b.get_string_from_ascii()
