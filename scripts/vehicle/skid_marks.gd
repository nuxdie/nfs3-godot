class_name SkidMarks
extends MultiMeshInstance3D
## Every car's skid marks in one draw call: a ring buffer of flat quads laid on the road,
## one per stretch of sliding tyre. Adding a segment writes one instance, so the cost
## doesn't grow with how much rubber is down; the oldest marks are overwritten.

const WIDTH := 0.24
const LIFT := 0.03   # above the road, against z-fighting

var _next := 0


## `atlas`: the four NFS3 skid textures side by side (Nfs3Sfx.skid_atlas), or null for
## plain procedural marks.
func _init(capacity: int, atlas: Texture2D = null) -> void:
	name = "SkidMarks"
	var plane := PlaneMesh.new()   # 1x1 in XZ, facing +Y
	plane.size = Vector2.ONE
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/skid_marks.gdshader")
	m.render_priority = 10
	if atlas:
		m.set_shader_parameter("skid_atlas", atlas)
		m.set_shader_parameter("use_atlas", true)
	plane.material = m

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true   # x: which skid texture
	mm.mesh = plane
	mm.instance_count = capacity
	# All drawn from the start: unwritten instances are zero-scaled, so they draw nothing.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Spans the whole track; a fixed box spares recomputing bounds on every new segment.
	mm.custom_aabb = AABB(Vector3(-1e5, -1e4, -1e5), Vector3(2e5, 2e4, 2e5))
	multimesh = mm


## One segment of tread from `a` to `b` on ground with normal `n`; `alpha` 0..1.
## `variant` picks the NFS3 texture: 0/1 dense tread, 2/3 streaky. `width`: the tyre's, m.
func add(a: Vector3, b: Vector3, n: Vector3, alpha: float, variant := 0, width := WIDTH) -> void:
	var along := b - a
	var side := n.cross(along).normalized() * width
	var xf := Transform3D(Basis(side, n, along), (a + b) * 0.5 + n * LIFT)
	multimesh.set_instance_transform(_next, xf)
	multimesh.set_instance_color(_next, Color(1, 1, 1, alpha))
	multimesh.set_instance_custom_data(_next, Color(variant, 0, 0, 0))
	_next = (_next + 1) % multimesh.instance_count
