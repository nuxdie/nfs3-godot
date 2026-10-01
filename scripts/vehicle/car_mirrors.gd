class_name CarMirrors
extends Node
## The in-car view's side mirrors (High Stakes' dash.fce "driver mirror" and "passenger
## mirror") and its rear-view mirror (Car._build_rear_mirror):
## each glass shows the scene from the driver's eye reflected in its plane, drawn
## into a small view of its own and shown on the glass. A flat glass that size, a metre from
## the eye, would show a sliver of road a few metres back, so it's drawn as if convex: the
## view WIDEN times as wide, squeezed onto it. Eye and glass both ride
## with the car (turning the head only turns the camera), so each mirror's camera, fitted to
## its glass, keeps its place in the car and the projection is worked out once. The car's
## own outside is drawn for the side mirrors alone (Car.OWN_VIEW_LAYER). A mirror renders only while its
## glass is on screen, and a side mirror not at all on Low: the glass keeps its painted texel.

## Pixels along the longer side of a mirror's view, per quality (Low has none).
const RESOLUTION := [0, 192, 320]
const FAR := [0.0, 250.0, 400.0]
## A reflection is a shade darker than the scene it shows.
const TINT := Color(0.82, 0.84, 0.86)
## How much wider a mirror shows than a flat glass would.
const WIDEN := 2.5
## How far below level a side mirror looks, radians.
const AIM_DOWN := 0.05
## The most the rear-view mirror looks down (see setup), radians: its view is barely 8 degrees
## tall, and much lower its bottom is the cabin's own rear seats.
const REAR_AIM_DOWN_MAX := 0.12
## Where the car's rear corner sits across a mirror, from its inner edge: set as a driver
## would, a sliver of the car's own flank in it.
const FLANK := 0.15
## The rear-view mirror (a glass marked "rear"): its own view sizes, since it stands in for
## the HUD's mirror and draws on Low too; near flat, it looks straight back through the
## cabin (the seats and the rear window's frame in it, not its own housing).
const REAR_RESOLUTION := [256, 320, 448]
const REAR_WIDEN := 1.3

var _car: Car
var _mirrors: Array[Dictionary] = []   # {glass, vp, cam, local (the camera, car-local), corners, mat, off (the glass's own look, while it sleeps)}


## `glass`: per mirror {node (the glass MeshInstance3D), point, normal} (car-local, the
## normal facing the eye), + rear true for the rear-view mirror; `eye` car-local;
## `half_size` the car's.
func setup(car: Car, glass: Array[Dictionary], eye: Vector3, half_size: Vector3) -> void:
	_car = car
	var q := int(Game.quality)
	for g in glass:
		var rear: bool = g.get("rear", false)
		if (REAR_RESOLUTION if rear else RESOLUTION)[q] == 0:
			continue
		var node: MeshInstance3D = g.node
		var mat_off := node.material_override
		var to_car := (node.get_parent() as Node3D).transform * node.transform
		var n: Vector3 = g.normal
		var eye_image: Vector3 = eye - 2.0 * (eye - (g.point as Vector3)).dot(n) * n
		var pts := PackedVector3Array()
		var box := AABB()
		for v in node.mesh.get_faces():
			var p := to_car * v
			box = AABB(p, Vector3.ZERO) if pts.is_empty() else box.expand(p)
			pts.append(p)
		if pts.is_empty() or (eye - (g.point as Vector3)).dot(n) <= 0.01:
			continue
		# The flat glass's view: from the eye's image through the middle of the glass, up the
		# car's up, fitted to the glass. It says where on the glass each point of the view goes.
		var flat := Transform3D(Basis.looking_at(box.get_center() - eye_image, Vector3.UP), eye_image)
		var inv := flat.affine_inverse()
		var depth := 0.0
		for p in pts:
			depth = maxf(depth, -(inv * p).z)
		if depth <= 0.01:
			continue
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in pts:
			var c := inv * p
			var s := Vector2(c.x, c.y) / -c.z
			lo = lo.min(s)
			hi = hi.max(s)
		var aspect := (hi.x - lo.x) / (hi.y - lo.y)
		var long_side: int = (REAR_RESOLUTION if rear else RESOLUTION)[q]
		var size := Vector2i(long_side, maxi(int(long_side / aspect), 16)) if aspect >= 1.0 \
			else Vector2i(maxi(int(long_side * aspect), 16), long_side)
		aspect = float(size.x) / float(size.y)
		# What it shows: WIDEN times as wide, level (a side mirror a touch down), and turned so the car's
		# rear corner on that side sits FLANK in from the inner edge.
		var widen := REAR_WIDEN if rear else WIDEN
		var half_h := atan((hi.x - lo.x) * widen * 0.5)
		var side := signf(eye_image.x)
		var corner := Vector2(side * half_size.x, -half_size.z) - Vector2(eye_image.x, eye_image.z)
		var turn := half_h * (1.0 - 2.0 * FLANK)
		var level := corner.normalized().rotated(turn)
		if side * level.x < side * corner.normalized().rotated(-turn).x:
			level = corner.normalized().rotated(-turn)
		var down := AIM_DOWN
		if rear:
			# Set as a driver would, through the rear window: on the car's tail halfway between
			# the eye's height and its image's. (The image sits up by the header: looking level
			# from there, a roof sloping down behind the seats filled the middle of the view with
			# its lining; down to the eye's height, it showed only road.)
			level = Vector2(0.0, -1.0)
			down = clampf(atan2((eye_image.y - eye.y) * 0.5, eye_image.z + half_size.z), 0.0, REAR_AIM_DOWN_MAX)
		var ahead := Vector3(level.x, 0.0, level.y) * cos(down) + Vector3.DOWN * sin(down)
		var local := Transform3D(Basis.looking_at(ahead, Vector3.UP), eye_image)
		# Its near plane just past the glass: what lies between the image and the glass (the
		# mirror's own housing) mustn't show.
		var near := 0.0
		for p in pts:
			near = maxf(near, -(local.affine_inverse() * p).z)
		# (A modelled rear-view mirror's glass isn't turned as the view is: its housing reaches
		# a little past it.)
		near += 0.03 if rear else 0.005
		var vp := SubViewport.new()
		vp.size = size
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.positional_shadow_atlas_size = 0
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_FRUSTUM
		cam.size = (hi.y - lo.y) * widen * near
		cam.near = near
		cam.far = FAR[maxi(q, 1)]
		cam.cull_mask &= ~(Car.REAR_MIRROR_LAYER | Reflections.MIRROR_LAYER)
		# A side mirror shows the car's own flank, and not the dash; the rear-view mirror the
		# cabin behind (the dash's back seats and rear window, not the body's shell around it).
		cam.cull_mask &= ~(Car.OWN_VIEW_LAYER if rear else Car.DASH_LAYER)
		vp.add_child(cam)
		# Glass vertex (its own space) -> the flat view's clip space, the glass filling it:
		# where on the wide view the shader reads.
		var proj := Projection.create_frustum_aspect(hi.y - lo.y, aspect, (lo + hi) * 0.5, 1.0, cam.far)
		var mat := ShaderMaterial.new()
		mat.shader = Game.shader("res://shaders/car_mirror.gdshader")
		mat.set_shader_parameter("mirror_tex", vp.get_texture())
		mat.set_shader_parameter("mirror_mvp", proj * Projection(inv * to_car))
		mat.set_shader_parameter("tint", TINT)
		var corners := PackedVector3Array()
		for k in 8:
			corners.append(box.get_endpoint(k))
		_mirrors.append({"glass": node, "vp": vp, "cam": cam, "local": local, "corners": corners, "mat": mat,
			"off": mat_off})


## Stops the mirror whose glass is `node` (its car's lost it): its view goes, the glass
## keeps its own look.
func drop(node: Node) -> void:
	for m in _mirrors.duplicate():
		if m.glass == node:
			(m.glass as MeshInstance3D).material_override = m.off
			(m.vp as Node).queue_free()
			_mirrors.erase(m)


func _process(_dt: float) -> void:
	if _mirrors.is_empty():
		return
	var inside := _car.is_visible_in_tree() and (get_parent() as Node3D).is_visible_in_tree()
	var eye_cam := get_viewport().get_camera_3d()
	var xf := _car.global_transform
	for m in _mirrors:
		var on := inside and eye_cam != null
		if on:
			on = false
			for c in m.corners:
				if eye_cam.is_position_in_frustum(xf * (c as Vector3)):
					on = true
					break
		var vp: SubViewport = m.vp
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
		(m.glass as MeshInstance3D).material_override = m.mat if on else m.off
		if on:
			(m.cam as Camera3D).global_transform = xf * (m.local as Transform3D)
