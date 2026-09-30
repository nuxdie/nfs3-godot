class_name SkidMarks
extends MultiMeshInstance3D
## Every car's skid marks in one draw call: a ring buffer of flat quads laid on the road,
## one per stretch of sliding tyre. Adding a segment writes one instance, so the cost
## doesn't grow with how much rubber is down; the oldest marks are overwritten.

const WIDTH := 0.24
const LIFT := 0.03   # above the road, against z-fighting

var _next := 0
var _warned := false


## Debug: the instances that aren't a plausible mark (too big, not finite, or further than
## `reach` from every point in `near`), as printable lines, and how many are laid.
func odd_marks(near: Array, reach := 1000.0) -> Array:
	var out := []
	var laid := 0
	for i in multimesh.instance_count:
		var xf := multimesh.get_instance_transform(i)
		var sx := xf.basis.x.length()
		var sz := xf.basis.z.length()
		if sx == 0.0 and sz == 0.0:
			continue
		laid += 1
		var far := true
		for p: Vector3 in near:
			far = far and xf.origin.distance_to(p) > reach
		if not (sx < 1.0 and sz < 4.0 and xf.basis.y.length() < 1.1 and xf.origin.is_finite()) or far:
			out.append("  skid #%d  x %s  y %s  z %s  at %s  colour %s" % [i, xf.basis.x, xf.basis.y,
				xf.basis.z, xf.origin, multimesh.get_instance_color(i)])
	out.push_front("  skid marks laid %d of %d, odd %d" % [laid, multimesh.instance_count, out.size()])
	return out


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
	# (Debug: after big dark discs drawn by the marks; one bad segment says where from.)
	if not (xf.basis.is_finite() and xf.origin.is_finite()) or along.length() > 4.0 or width > 1.0 \
			or absf(n.length() - 1.0) > 0.01:
		if not _warned:
			_warned = true
			push_warning("SkidMarks: bad segment a %s b %s n %s width %s" % [a, b, n, width])
		return
	multimesh.set_instance_transform(_next, xf)
	multimesh.set_instance_color(_next, Color(1, 1, 1, alpha))
	multimesh.set_instance_custom_data(_next, Color(variant, 0, 0, 0))
	_next = (_next + 1) % multimesh.instance_count
