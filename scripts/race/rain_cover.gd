class_name RainCover
extends Node
## A top-down height map of the track: the topmost surface over every point, so rain and
## snow stop at bridges, tunnel roofs and overhangs, and the road under them stays dry.
## Made by drawing the track's meshes once, straight down, in an orthographic view of their
## own; `is_built` is false for the first couple of frames while that happens.

signal built

const CELL := 1.0         # metres per texel...
const MAX_SIZE := 4096    # ...until the track is too big for that
const MARGIN := 60.0      # beyond the road's walls: the rain only falls near the camera

var is_built := false
var texture: ImageTexture
var rect := Rect2()       # x/z covered
var y_min := 0.0
var y_range := 1.0

var _img: Image
var _n := 0


## Renders the MeshInstance3Ds under `track_root` (skipping additive effect surfaces such as
## light shafts) over the area `path` runs through.
func build(track_root: Node3D, path: TrackPath, additive: Shader) -> void:
	var area := AABB(path.points[0], Vector3.ZERO)
	for i in path.size():
		area = area.expand(path.points[i])
	var reach := 0.0
	for i in path.size():
		reach = maxf(reach, maxf(path.left_width[i], path.right_width[i]))
	area = area.grow(minf(reach, 60.0) + MARGIN)
	var meshes: Array[MeshInstance3D] = []
	var ys := Vector2(INF, -INF)
	for mi: MeshInstance3D in track_root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.is_visible_in_tree() or mi.mesh.get_surface_count() == 0:
			continue
		var m := mi.material_override if mi.material_override else mi.mesh.surface_get_material(0)
		if m is ShaderMaterial and (m as ShaderMaterial).shader == additive:
			continue
		var box := mi.global_transform * mi.get_aabb()
		if not box.intersects(area):
			continue
		meshes.append(mi)
		ys = Vector2(minf(ys.x, box.position.y), maxf(ys.y, box.end.y))
	if meshes.is_empty():
		return
	# Empty texels read 0: below everything, so nothing covers them.
	y_min = ys.x - 5.0
	y_range = maxf(ys.y - y_min, 1.0)
	var side := maxf(area.size.x, area.size.z)
	_n = mini(ceili(side / CELL), MAX_SIZE)
	var centre := area.get_center()
	rect = Rect2(centre.x - side * 0.5, centre.z - side * 0.5, side, side)

	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(_n, _n)
	vp.use_hdr_2d = true   # linear floats out, no sRGB curve on the heights
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = side
	cam.near = 0.1
	cam.far = y_range + 20.0
	# Looking down with the top of the image toward -Z: texel (u, v) is at rect.position + (u, v).
	cam.transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)), Vector3(centre.x, y_min + y_range + 10.0, centre.z))
	vp.add_child(cam)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/cover_height.gdshader")
	mat.set_shader_parameter("y_min", y_min)
	mat.set_shader_parameter("y_range", y_range)
	for mi in meshes:
		var d := MeshInstance3D.new()
		d.mesh = mi.mesh
		d.material_override = mat
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.transform = mi.global_transform
		vp.add_child(d)
	add_child(vp)
	for k in 2:
		await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	_img = vp.get_texture().get_image()
	vp.queue_free()
	_img.convert(Image.FORMAT_RH)
	texture = ImageTexture.create_from_image(_img)
	is_built = true
	built.emit()


## Height of the topmost surface over `x`/`z`, or -INF where there's nothing.
func roof(x: float, z: float) -> float:
	if not is_built:
		return -INF
	var u := int((x - rect.position.x) / rect.size.x * _n)
	var v := int((z - rect.position.y) / rect.size.y * _n)
	if u < 0 or v < 0 or u >= _n or v >= _n:
		return -INF
	var h := _img.get_pixel(u, v).r
	return y_min + h * y_range if h > 0.0 else -INF


## True when something solid is over `p` (more than `clearance` metres above it).
func covered(p: Vector3, clearance := 1.0) -> bool:
	return roof(p.x, p.z) > p.y + clearance
