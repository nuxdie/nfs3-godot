class_name Breakables
extends Node3D
## The procedural track's props that give when a car hits them: signs and their posts,
## chevrons, cones, sawhorses, fence panels, mailboxes. While standing each is drawn along
## with the rest of its kind (a MultiMesh instance, or a piece of a merged mesh) and all the
## cars meet is a trigger box round its foot, so hundreds of them cost no draw calls. A car
## touching one takes it out of where it was drawn and puts a loose copy in its place that
## flies off (a KnockableProp, as the NFS3 tracks' signs are).

const DRAW_DISTANCE := 350.0
const MAX_HULL := 64         # points of a loose copy's collision hull

## Each item: [frame (its foot), take (Callable: hides the standing prop and returns
## [ArrayMesh, material or null] or a Node3D to fly off as it is)].
var _items: Array = []


## A prop standing at `xf` (its foot, Y up) that a car touches within `reach` (in its frame).
## `take` is called once, when it's hit.
func add(xf: Transform3D, reach: AABB, take: Callable) -> void:
	_items.append([xf, take])
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2   # cars
	area.monitorable = false
	area.transform = xf.orthonormalized()
	var shape := BoxShape3D.new()
	shape.size = reach.size.max(Vector3(0.15, 0.2, 0.15))
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = reach.get_center()
	area.add_child(cs)
	area.body_entered.connect(_on_body_entered.bind(_items.size() - 1, area))
	add_child(area)


func _on_body_entered(body: Node3D, index: int, area: Area3D) -> void:
	if not body is Car or _items[index] == null:
		return
	# Physics state can't change while the space is flushing its queries.
	_knock.call_deferred(body, index, area)


func _knock(car: Car, index: int, area: Area3D) -> void:
	var item: Array = _items[index]
	if item == null:
		return
	_items[index] = null
	area.queue_free()
	var xf: Transform3D = item[0]
	var got: Variant = item[1].call()
	var prop := KnockableProp.new()
	prop.transform = xf.orthonormalized()
	if got is Node3D:
		var node: Node3D = got
		var at := node.global_transform
		prop.setup(null, null, AABB(), _hull_of_node(node, xf), DRAW_DISTANCE)
		add_child(prop)
		node.get_parent().remove_child(node)
		prop.add_child(node)
		node.global_transform = at
	else:
		var mesh: ArrayMesh = got[0]
		prop.setup(mesh, got[1], AABB(), _hull(mesh), DRAW_DISTANCE)
		add_child(prop)
	prop._knock(car)


static func _hull(mesh: ArrayMesh) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for s in mesh.get_surface_count():
		pts.append_array(mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	return _thin(pts)


static func _hull_of_node(node: Node3D, xf: Transform3D) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var to_local := xf.orthonormalized().affine_inverse()
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var box := m.get_aabb()
		for k in 8:
			pts.append(to_local * (m.global_transform * box.get_endpoint(k)))
	if pts.is_empty():
		pts = PackedVector3Array([Vector3(-0.3, 0, -0.1), Vector3(0.3, 0, 0.1), Vector3(0, 2, 0)])
	return _thin(pts)


static func _thin(pts: PackedVector3Array) -> PackedVector3Array:
	if pts.size() <= MAX_HULL:
		return pts
	var out := PackedVector3Array()
	var step := float(pts.size()) / MAX_HULL
	for k in MAX_HULL:
		out.append(pts[int(k * step)])
	return out


## The standing prop's `index` in `mm`, hidden: [its mesh, its material (in the mesh)].
static func take_instance(mm: MultiMesh, index: int) -> void:
	var xf := mm.get_instance_transform(index)
	mm.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ZERO), xf.origin))


## A copy of `meshes` (each [Mesh, Transform3D placing it in the prop's frame]) as one mesh,
## a surface each, keeping their materials.
static func combine(meshes: Array) -> ArrayMesh:
	var out := ArrayMesh.new()
	for mt: Array in meshes:
		var mesh: Mesh = mt[0]
		var xf: Transform3D = mt[1]
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for k in v.size():
				v[k] = xf * v[k]
			arrays[Mesh.ARRAY_VERTEX] = v
			if arrays[Mesh.ARRAY_NORMAL] != null:
				var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				for k in n.size():
					n[k] = (xf.basis * n[k]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = n
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
	return out


# --- Merged meshes a piece can be taken out of -----------------------------------------------

## A merged mesh (non-indexed triangles) that pieces can be taken out of: {mesh, arrays}.
static func chunk(arrays: Array, material: Material) -> Dictionary:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return {"mesh": mesh, "arrays": arrays, "mat": material}


## Takes vertices `from`..`from + count` out of `ch` (collapsed to a point) and returns them
## as a mesh in the frame `xf`.
static func take_piece(ch: Dictionary, from: int, count: int, xf: Transform3D) -> ArrayMesh:
	var arrays: Array = ch.arrays
	var piece := []
	piece.resize(Mesh.ARRAY_MAX)
	var to_local := xf.affine_inverse()
	for a in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR]:
		if arrays[a] == null:
			continue
		piece[a] = arrays[a].slice(from, from + count)
	var v: PackedVector3Array = piece[Mesh.ARRAY_VERTEX]
	for k in v.size():
		v[k] = to_local * v[k]
	piece[Mesh.ARRAY_VERTEX] = v
	if piece[Mesh.ARRAY_NORMAL] != null:
		var n: PackedVector3Array = piece[Mesh.ARRAY_NORMAL]
		for k in n.size():
			n[k] = (to_local.basis * n[k]).normalized()
		piece[Mesh.ARRAY_NORMAL] = n
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, piece)
	out.surface_set_material(0, ch.mat)
	# Gone from where it stood.
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var p := verts[from]
	for k in range(from, from + count):
		verts[k] = p
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh: ArrayMesh = ch.mesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, ch.mat)
	return out
