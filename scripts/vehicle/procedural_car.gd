class_name ProceduralCar
## Stand-in car data (same interface as Nfs3Car) built from primitives, used
## when no NFS3 install is available and for generic cop/traffic cars.

const PRESETS := [
	{"name": "Stinger GT", "color": Color(0.85, 0.1, 0.08), "mass": 1400.0, "top": 80.0, "torque": 520.0, "len": 2.2, "wid": 0.95, "hgt": 0.6},
	{"name": "Vortex V12", "color": Color(0.95, 0.75, 0.1), "mass": 1550.0, "top": 90.0, "torque": 600.0, "len": 2.35, "wid": 1.0, "hgt": 0.55},
	{"name": "Aero RS", "color": Color(0.1, 0.35, 0.9), "mass": 1250.0, "top": 76.0, "torque": 430.0, "len": 2.1, "wid": 0.92, "hgt": 0.6},
	{"name": "Interceptor", "color": Color(0.08, 0.08, 0.1), "mass": 1700.0, "top": 82.0, "torque": 560.0, "len": 2.4, "wid": 1.0, "hgt": 0.7},
	{"name": "Sedan", "color": Color(0.6, 0.62, 0.55), "mass": 1500.0, "top": 50.0, "torque": 300.0, "len": 2.3, "wid": 0.95, "hgt": 0.8},
]

var id := ""
var display_name := ""
var texture: Texture2D = null
var body_parts: Array[Dictionary] = []
var wheels: Array[Dictionary] = []
var half_size := Vector3.ONE
var colours: Array[Color] = []
var lights: Array[Dictionary] = []
var carp := {}
var error := ""
var body_color := Color.WHITE


static func make(preset: int, tint := Color(0, 0, 0, 0)) -> ProceduralCar:
	var p: Dictionary = PRESETS[clampi(preset, 0, PRESETS.size() - 1)]
	var c := ProceduralCar.new()
	c.id = "proc%d" % preset
	c.display_name = p.name
	c.body_color = p.color if tint.a == 0 else tint
	c.colours = [c.body_color]
	var L: float = p.len
	var W: float = p.wid
	var H: float = p.hgt
	c.half_size = Vector3(W, H, L)
	c.carp = {
		2: PackedFloat32Array([p.mass]),
		7: PackedFloat32Array([-220, 0, 230, 150, 110, 88, 70, 0]),
		8: PackedFloat32Array([2.1, 0, 2.3, 1.5, 1.12, 0.88, 0.7, 0]),
		10: _torque_curve(p.torque),
		11: PackedFloat32Array([3.8]),
		12: PackedFloat32Array([1000]),
		13: PackedFloat32Array([7000]),
		15: PackedFloat32Array([p.top]),
		18: PackedFloat32Array([10.0]),
		30: PackedFloat32Array([3.2]),
	}
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c.body_color
	mat.metallic = 0.4
	mat.roughness = 0.3
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.07, 0.1)
	glass.roughness = 0.1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(0, -H * 0.35, 0), Vector3(W, H * 0.4, L))
	_box(st, Vector3(0, H * 0.3, -L * 0.1), Vector3(W * 0.8, H * 0.3, L * 0.45))
	st.generate_normals()
	var body := st.commit()
	body.surface_set_material(0, mat)
	var gst := SurfaceTool.new()
	gst.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(gst, Vector3(0, H * 0.32, -L * 0.1), Vector3(W * 0.82, H * 0.24, L * 0.46))
	gst.generate_normals()
	gst.commit(body)
	body.surface_set_material(1, glass)
	c.body_parts.append({"name": "body", "mesh": body, "center": Vector3.ZERO})
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.33
	wheel.bottom_radius = 0.33
	wheel.height = 0.25
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.05, 0.05, 0.05)
	wheel.material = wm
	var am := ArrayMesh.new()
	var arr := wheel.get_mesh_arrays()
	# Lay the cylinder on its side (axle along X).
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var rot := Basis(Vector3.FORWARD, PI / 2)
	for i in verts.size():
		verts[i] = rot * verts[i]
		norms[i] = rot * norms[i]
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.surface_set_material(0, wm)
	var wx := W + 0.02   # tyres stand just proud of the body sides
	var wz := L * 0.62
	var wy := -H * 0.55
	for slot in 4:
		var x := wx if slot % 2 == 0 else -wx
		var z := wz if slot < 2 else -wz
		c.wheels.append({"name": "wheel", "mesh": am, "center": Vector3(x, wy, z), "slot": slot})
	return c


static func _torque_curve(peak: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in 41:
		var rpm := i * 256.0
		out.append(peak * clampf(0.55 + 0.45 * sin(clampf(rpm / 5500.0, 0.0, 1.4) * PI * 0.5), 0.0, 1.0) * (1.0 - clampf((rpm - 6500.0) / 4000.0, 0.0, 0.6)))
	return out


func carp_value(key: int, default := 0.0, index := 0) -> float:
	if carp.has(key) and carp[key].size() > index:
		return carp[key][index]
	return default


static func _box(st: SurfaceTool, c: Vector3, h: Vector3) -> void:
	var p := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	]
	for f in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]:
		# Faces are listed counter-clockwise seen from outside; Godot's front faces are clockwise.
		for k in [0, 2, 1, 0, 3, 2]:
			st.add_vertex(p[f[k]])
