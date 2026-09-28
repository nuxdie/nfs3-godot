class_name Guardrails
extends Node3D
## The guardrails and railings along the road's edge, bent by the cars that hit them. The
## invisible walls still do the stopping; the rail only shows the blow: pushed out around
## the point of impact, its top leaning further than its posts and sagging a little, and
## scuffed. Nothing is straightened until the race is restarted.
##
## Panels are cut into narrow columns so a hit bends them in a curve, and meshed a few
## track blocks to a chunk. Neighbouring panels share their corners and every vertex moves
## by where it stands, so the rail stays joined.

const RADIUS := 2.2         # m along the rail that a full hit bends
const DEPTH := 0.45         # m a full hit pushes the top out at the centre
const MAX_BEND := 0.9       # m any point can be pushed over the race
const SAG := 0.35           # the top drops this share of how far it is pushed out
const POST_BEND := 0.3      # share of the push the foot of the panel takes
const SCUFF := 0.35         # how much darker the most battered metal gets
const REACH := 3.0          # m above or below the rail that a contact still bends it

var _chunks: Array[Dictionary] = []  # {mi, mesh, box, arrays, rest, lean, shade}


func _ready() -> void:
	add_to_group("guardrails")


## A chunk of rail: `arrays` are a Mesh.ARRAY_MAX array (non-indexed triangles), `lean` per
## vertex is its height up the panel (0 at the foot, 1 at the top).
func add_chunk(arrays: Array, lean: PackedFloat32Array, material: Material, draw_distance: float) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = draw_distance
	mi.visibility_range_end_margin = 40.0
	add_child(mi)
	_chunks.append({"mi": mi, "mesh": mesh, "box": mesh.get_aabb(), "arrays": arrays,
		"rest": (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate(), "lean": lean,
		"shade": (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).duplicate()})


## A car hit something at world point `at`, pushing it along `push`; `strength` 0..1.
func hit(at: Vector3, push: Vector3, strength: float) -> void:
	push.y = 0.0
	if push.length_squared() < 1e-4 or strength <= 0.0:
		return
	push = push.normalized()
	var radius := RADIUS * lerpf(0.6, 1.0, strength)
	var depth := DEPTH * lerpf(0.15, 1.0, strength)
	var reach := AABB(at - Vector3(radius, REACH, radius), Vector3(radius, REACH, radius) * 2.0)
	for ch in _chunks:
		if (ch.box as AABB).intersects(reach):
			_bend(ch, at, push, radius, depth)


func _bend(ch: Dictionary, at: Vector3, push: Vector3, radius: float, depth: float) -> void:
	var arrays: Array = ch.arrays
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var rest: PackedVector3Array = ch.rest
	var lean: PackedFloat32Array = ch.lean
	var shade: PackedColorArray = ch.shade
	var moved := false
	for i in verts.size():
		var r := rest[i]
		if absf(r.y - at.y) > REACH:
			continue
		var d := Vector2(r.x - at.x, r.z - at.z).length()
		if d >= radius:
			continue
		var f := 1.0 - d / radius
		f = f * f * (3.0 - 2.0 * f)
		var h := lean[i]
		var off := verts[i] - r + push * depth * f * lerpf(POST_BEND, 1.0, h)
		off = off.limit_length(MAX_BEND)
		off.y = -Vector2(off.x, off.z).length() * SAG * h
		verts[i] = r + off
		var c := colors[i]
		var scuff := 1.0 - SCUFF * clampf(off.length() / MAX_BEND * 2.0, 0.0, 1.0)
		colors[i] = Color(shade[i].r * scuff, shade[i].g * scuff, shade[i].b * scuff, c.a)
		moved = true
	if not moved:
		return
	# Bent metal catches the light facet by facet.
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for t in range(0, verts.size() - 2, 3):
		var fn := (verts[t + 2] - verts[t]).cross(verts[t + 1] - verts[t])
		if fn.length_squared() > 1e-12:
			fn = fn.normalized()
			for k in 3:
				normals[t + k] = fn
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh: ArrayMesh = ch.mesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
