class_name Reflections
extends Node3D
## The reflections the Mobile renderer doesn't give for free (it has no screen-space ones):
## - a wet NFS3 road darkens and mirrors the sky with a Fresnel sheen, and the nearest cars'
##   lamps glint on it in long streaks; on High it mirrors the scene itself, drawn by a second
##   camera from under the road (only while the road is wet);
## - the procedural track's road (lit, unlike the NFS3 one) gets smoother as it gets wet;
## - car paint reflects the track around the player's car through a reflection probe riding
##   with it (not on Low: it's six extra renders of the scene).

const MAX_LAMPS := 16             # MAX_LAMPS in track.gdshader
const LAMPS := [6, 12, 16]        # by Game.quality
const LAMP_RANGE := 150.0
## Render layer bit of the track copies only the mirror camera draws.
const MIRROR_LAYER := 4
const MIRROR_SCALE := 0.5         # of the main view's 3D resolution
const MIRROR_DISTANCE := 300.0
## Wetness below which the road is drawn dry and the mirror camera sleeps.
const DRY := 0.02
## A probe that updates in slices (Medium) is moved this often; its box is big enough that
## the car stays inside meanwhile.
const PROBE_STEP := 1.0

var path: TrackPath

var _weather: Weather
var _env: Environment
var _track_mat: ShaderMaterial
var _road_mat: ShaderMaterial
var _mirror_mat: ShaderMaterial
var _vp: SubViewport
var _cam: Camera3D
var _probe: ReflectionProbe
var _probe_car: Car
var _probe_t := 0.0
var _node := -1
var _wet := -1.0


## `track_root` holds the track: the NFS3 track's shader material (`track_mat`) or the
## procedural one's road material. `weather` is null in a dry race.
func setup(track_root: Node3D, p_path: TrackPath, env: Environment, track_mat: ShaderMaterial,
		weather: Weather) -> void:
	path = p_path
	_env = env
	_track_mat = track_mat
	_weather = weather
	if track_root.has_meta("road_material"):
		_road_mat = track_root.get_meta("road_material")
	if _track_mat and _weather and Game.quality == Game.Quality.HIGH:
		_build_mirror(track_root)


## Hangs the paint's reflection probe on `car`.
func follow(car: Car) -> void:
	if Game.quality == Game.Quality.LOW:
		return
	_probe_car = car
	_probe = ReflectionProbe.new()
	# The track and scenery: not the cars (it sits inside one), the mirror's copies or the rain.
	_probe.cull_mask = 1
	_probe.max_distance = 250.0
	_probe.enable_shadows = false
	if Game.quality == Game.Quality.HIGH:
		_probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
		_probe.size = Vector3(40.0, 16.0, 40.0)
		_probe.position = Vector3.UP
		car.add_child(_probe)
	else:
		# Moving a probe starts its update over, so it only moves every PROBE_STEP.
		_probe.update_mode = ReflectionProbe.UPDATE_ONCE
		_probe.size = Vector3(110.0, 30.0, 110.0)
		add_child(_probe)
		_probe.global_position = car.global_position + Vector3.UP


func _build_mirror(track_root: Node3D) -> void:
	# Its own copy of the material, before the main one gets the mirror's texture (drawing
	# a viewport's texture into itself would feed back).
	_mirror_mat = _track_mat.duplicate()
	_mirror_mat.set_shader_parameter("mirror_pass", true)
	var geo := track_root.get_node_or_null("Geometry")
	if geo == null:
		return
	for mi: MeshInstance3D in geo.find_children("*", "MeshInstance3D", false, false):
		# Opaque track blocks only: effect glows and the keyframed movers are left out.
		if mi.material_override != _track_mat or mi.get_script() != null:
			continue
		var d := MeshInstance3D.new()
		d.mesh = mi.mesh
		d.material_override = _mirror_mat
		d.layers = MIRROR_LAYER
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.visibility_range_end = MIRROR_DISTANCE
		add_child(d)
		d.global_transform = mi.global_transform
	for c: Camera3D in get_tree().root.find_children("*", "Camera3D", true, false):
		c.cull_mask &= ~MIRROR_LAYER
	_vp = SubViewport.new()
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.positional_shadow_atlas_size = 0
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.cull_mask = MIRROR_LAYER | Car.VISUAL_LAYER
	_vp.add_child(_cam)
	_track_mat.set_shader_parameter("mirror_tex", _vp.get_texture())


func _process(dt: float) -> void:
	var eye_cam := get_viewport().get_camera_3d()
	if eye_cam == null:
		return
	var wet := _weather.road_wetness() if _weather else 0.0
	if _track_mat:
		_update_track(eye_cam, wet)
	elif _road_mat and absf(wet - _wet) > 0.005:
		_road_mat.set_shader_parameter("wetness", wet)
	_wet = wet
	if _probe and _probe.update_mode == ReflectionProbe.UPDATE_ONCE and is_instance_valid(_probe_car):
		_probe_t -= dt
		if _probe_t <= 0.0:
			_probe_t = PROBE_STEP
			_probe.global_position = _probe_car.global_position + Vector3.UP


func _update_track(eye_cam: Camera3D, wet: float) -> void:
	var on := wet > DRY
	_track_mat.set_shader_parameter("wetness", wet if on else 0.0)
	if _vp:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
		_track_mat.set_shader_parameter("has_mirror", on)
	if not on:
		return
	# The sky's colour at the horizon is close to the fog's, which follows the fog regions
	# and lightning flashes.
	var horizon := _env.fog_light_color.srgb_to_linear()
	_track_mat.set_shader_parameter("sky_horizon", Vector3(horizon.r, horizon.g, horizon.b))
	_track_mat.set_shader_parameter("sky_zenith", Vector3(horizon.r, horizon.g, horizon.b) * 0.8)
	_update_lamps(eye_cam.global_position)
	if _vp:
		_update_mirror(eye_cam)


## The lamps nearest the eye that shine its way (a lamp facing off lights the road away
## from the eye) go to the shader's slots.
func _update_lamps(eye: Vector3) -> void:
	var lit: Array = []
	for c in get_parent().get_children():
		if not c is Car:
			continue
		var d: float = c.global_position.distance_to(eye)
		if d > LAMP_RANGE:
			continue
		for lamp: Array in c.lit_lamps():
			var dir: Vector3 = lamp[1]
			if dir != Vector3.ZERO and dir.dot((eye - lamp[0]).normalized()) < -0.3:
				continue
			lit.append([d, lamp])
	lit.sort_custom(func(a, b): return a[0] < b[0])
	var n := mini(lit.size(), LAMPS[Game.quality])
	var pos := PackedVector3Array()
	var dirs := PackedVector3Array()
	var cols := PackedVector3Array()
	# Headlights on a bright day don't glint the way they do at night.
	var k := 1.0 if Game.night else 0.35
	for i in n:
		var lamp: Array = lit[i][1]
		pos.append(lamp[0])
		dirs.append(lamp[1])
		cols.append(lamp[2] * k)
	pos.resize(MAX_LAMPS)
	dirs.resize(MAX_LAMPS)
	cols.resize(MAX_LAMPS)
	_track_mat.set_shader_parameter("lamp_count", n)
	_track_mat.set_shader_parameter("lamp_pos", pos)
	_track_mat.set_shader_parameter("lamp_dir", dirs)
	_track_mat.set_shader_parameter("lamp_color", cols)


## The mirror camera: the eye reflected in the road's plane under it, flipped left-right to
## stay a right-handed camera (the shader flips the image back).
func _update_mirror(eye_cam: Camera3D) -> void:
	var scale := get_viewport().scaling_3d_scale * MIRROR_SCALE
	var size := Vector2i((Vector2(get_window().size) * scale).max(Vector2.ONE))
	if _vp.size != size:
		_vp.size = size
	var eye := eye_cam.global_transform
	_node = path.closest(eye.origin, _node)
	var n: Vector3 = path.ups[_node]
	var d: float = n.dot(path.points[_node])
	var b := eye.basis
	var reflect := func(v: Vector3) -> Vector3: return v - 2.0 * n.dot(v) * n
	_cam.global_transform = Transform3D(
		Basis(-reflect.call(b.x), reflect.call(b.y), reflect.call(b.z)),
		eye.origin - 2.0 * (n.dot(eye.origin) - d) * n)
	_cam.fov = eye_cam.fov
	_cam.near = eye_cam.near
	_cam.far = minf(eye_cam.far, MIRROR_DISTANCE)
	_cam.keep_aspect = eye_cam.keep_aspect
	_mirror_mat.set_shader_parameter("mirror_plane", Vector4(n.x, n.y, n.z, d))
	_mirror_mat.set_shader_parameter("night_tint", _track_mat.get_shader_parameter("night_tint"))
