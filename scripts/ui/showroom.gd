class_name Showroom
extends SubViewportContainer
## The menu's car, on a stage of its own in a transparent 3D view over the track's picture.
##   the stage     a dark gloss floor that fades out into the picture, the car mirrored in it
##                 (a copy of its meshes under the floor), a soft shadow under it, and a dark
##                 studio of softboxes that only shows in the paint's reflections
##   the camera    a director going through a few shots, blending one into the next: a low
##                 front three-quarter, down at the grille, a long-lens profile, the rear
##                 three-quarter, a high one. Each is framed to the car's own size, in the part
##                 of the screen the menu leaves free (set_region()). Dragging takes it over,
##                 round and up and down; a few seconds after letting go the director carries
##                 on from there.
## The car is the race car itself, parked and dropped onto the floor, so it lands and settles
## on its springs.

const FLOOR_Y := -0.595
const DROP_HEIGHT := 0.6          # tyres this far above the floor when a car is dropped in
const SHOT_S := 7.5               # each shot's length
const RESUME_S := 5.0             # after a drag, how long before the director takes back over
const BLEND := 0.55               # how quickly the camera eases into the next shot (1/s)

## [yaw, elevation, distance factor, fov, yaw drift per second] (degrees). Yaw 0 looks at the
## car's nose; the distance factor is on the distance that frames the car in its region.
const SHOTS := [
	[38.0, 7.0, 1.0, 30.0, 2.5],      # the hero: front three-quarter, low
	[-18.0, 2.5, 1.0, 44.0, -1.8],    # down at the grille, a wide lens close in
	[92.0, 5.0, 1.05, 22.0, 1.2],     # profile, long lens
	[148.0, 9.0, 1.0, 30.0, 2.5],     # rear three-quarter
	[-125.0, 30.0, 1.05, 32.0, -3.0], # high, from behind the other side
	[62.0, 3.0, 1.0, 40.0, -2.0],     # low along the flank to the nose
]

var car: Car                      # the car on the stage (null while none)
var sliding := 0.0                # set by the menu's start: the car slides off along the camera's x

var _vp: SubViewport
var _world: Node3D
var _rig: Node3D                  # the lights, turned with the camera so the car stays lit the same
var _cam: Camera3D
var _shadow: MeshInstance3D
var _mirror: Node3D               # the reflection: a copy of each of the car's meshes
var _twins: Array = []            # [source MeshInstance3D, its copy]
var _region := Rect2(0.5, 0.2, 0.4, 0.5)   # where the car goes, as fractions of the view
var _half := Vector3(0.9, 0.7, 2.2)        # the car's half extents
var _slide_from := Vector3.ZERO

# The camera: where it is, and the shot it's easing towards.
var _yaw := 38.0
var _elev := 7.0
var _dist_k := 1.0
var _fov := 30.0
var _shot := 0
var _shot_t := 0.0
var _goal_yaw := 38.0
var _dragging := false
var _manual_t := 0.0              # > 0: the player turned it; counts down to the director again
var _time := 0.0
var _fit_d := 0.0                 # the distance that fits the car in its region, last found


func _init() -> void:
	stretch = true
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X if Game.quality == Game.Quality.HIGH else Viewport.MSAA_2X \
		if Game.quality == Game.Quality.MEDIUM else Viewport.MSAA_DISABLED
	add_child(_vp)
	_world = Node3D.new()
	_vp.add_child(_world)
	_build_studio()
	_build_floor()
	_mirror = Node3D.new()
	_world.add_child(_mirror)
	_mirror.visible = Game.quality != Game.Quality.LOW


## Where on the view the car should stand, as a rect in the view's own pixels.
func set_region(r: Rect2) -> void:
	var s := size if size.x > 0 else Vector2(1280, 720)
	_region = Rect2(r.position / s, r.size / s)


## Puts `data` on the stage in `tint` (the paint), dropped in from a little height.
func show_car(data: Object, tint: Color, upgrade := 0, id := -1) -> void:
	if car:
		car.queue_free()
		car = null
	for t in _twins:
		t[1].queue_free()
	_twins.clear()
	var c := Car.new()
	c.setup(data, tint, upgrade)
	c.handbrake = true
	c.set_headlights(false)
	c.set_meta("car", id)
	_world.add_child(c)
	c.reset_to(Transform3D(Basis(), Vector3(0, FLOOR_Y, 0)), DROP_HEIGHT)
	car = c
	_half = data.half_size
	(_shadow.mesh as PlaneMesh).size = Vector2(_half.x * 2.9, _half.z * 2.5)
	_shadow.visible = true
	_build_twins.call_deferred()


## The car on the stage in another paint, without dropping it in again.
func repaint(tint: Color) -> void:
	if car:
		car.set_paint(tint)


func shown_id() -> int:
	return car.get_meta("car", -1) if car else -1


## The start: the car is frozen where it is, then slides off (the menu tweens `sliding`).
func freeze_for_start() -> void:
	if car:
		car.freeze = true
		_slide_from = car.global_position


# ------------------------------------------------------------------ building

func _build_studio() -> void:
	_rig = Node3D.new()
	_world.add_child(_rig)
	_cam = Camera3D.new()
	_cam.near = 0.1
	_cam.far = 200.0
	_world.add_child(_cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 28, 0)
	key.light_energy = 1.2
	key.light_color = Color(1.0, 0.97, 0.92)
	_rig.add_child(key)
	# High and soft: a low one lights the grey wheel-arch liners and inner panels up blue.
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-48, 165, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.72, 0.82, 1.0)
	_rig.add_child(rim)
	# A warm kicker low from the side, for a line of light along the sills.
	var kick := DirectionalLight3D.new()
	kick.rotation_degrees = Vector3(-12, -100, 0)
	kick.light_energy = 0.25
	kick.light_color = Color(1.0, 0.8, 0.6)
	_rig.add_child(kick)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	# A dark studio with softboxes, that only shows up in reflections and the fill light (the
	# backdrop stays transparent): lit panels mirror crisp highlight shapes and the sides fall
	# into shade, where an even grey dome and fill light made the paint look like porcelain.
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = _studio_shader()
	env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)


func _build_floor() -> void:
	var fl := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	var fm := ShaderMaterial.new()
	fm.shader = _floor_shader()
	fm.set_shader_parameter("opacity", 0.7)
	fm.set_shader_parameter("sheen", 1.0)
	# Transparent layers here draw in reverse order of render_priority (checked: the higher
	# first): the deepest slice first, then the shallower ones, the floor, the shadow last.
	fm.render_priority = -20
	plane.material = fm
	fl.mesh = plane
	fl.position.y = FLOOR_Y
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(fl)
	# Under it, thin dark slices, each dimming what's below it a little more: the car's
	# reflection fades out with depth, strongest where the tyres meet the floor, as on gloss.
	for k in 7:
		var sl := MeshInstance3D.new()
		var sp := PlaneMesh.new()
		sp.size = plane.size
		var sm := ShaderMaterial.new()
		sm.shader = fm.shader
		sm.set_shader_parameter("opacity", 0.4)
		sm.set_shader_parameter("sheen", 0.0)
		sm.render_priority = -12 + k
		sp.material = sm
		sl.mesh = sp
		sl.position.y = FLOOR_Y - 0.06 - k * 0.11
		sl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world.add_child(sl)
	# The floor is solid ground (layer 1, what the wheel rays hit).
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(40, 1, 40)
	gs.shape = gb
	gs.position.y = FLOOR_Y - 0.5
	ground.add_child(gs)
	_world.add_child(ground)
	_shadow = MeshInstance3D.new()
	var q := PlaneMesh.new()
	var sm := ShaderMaterial.new()
	sm.shader = _shadow_shader()
	# Both it and the floor are transparent and coplanar: always draw it after the floor.
	sm.render_priority = -30
	q.material = sm
	_shadow.mesh = q
	_shadow.visible = false
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(_shadow)


## The reflection: every visible mesh of the car copied under the floor, its transform
## mirrored in the floor each frame (Godot flips the culling of a mirrored transform).
func _build_twins() -> void:
	if car == null or not _mirror.visible:
		return
	for n in car.find_children("*", "MeshInstance3D", true, false):
		var src := n as MeshInstance3D
		if src.mesh == null:
			continue
		var t := MeshInstance3D.new()
		t.mesh = src.mesh
		t.material_override = src.material_override
		for k in src.get_surface_override_material_count():
			t.set_surface_override_material(k, src.get_surface_override_material(k))
		t.skeleton = NodePath()
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.layers = src.layers
		_mirror.add_child(t)
		_twins.append([src, t])


# ------------------------------------------------------------------ input

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_dragging = e.pressed
		if e.pressed:
			_manual_t = RESUME_S
	elif e is InputEventMouseMotion and _dragging:
		_yaw -= e.relative.x * 0.35
		_goal_yaw = _yaw
		_elev = clampf(_elev + e.relative.y * 0.2, 1.5, 55.0)
		_manual_t = RESUME_S


# ------------------------------------------------------------------ the director

func _process(dt: float) -> void:
	_time += dt
	if _manual_t > 0.0:
		if not _dragging:
			_manual_t -= dt
			if _manual_t <= 0.0:
				# Carry on with the shot nearest where the player left it.
				_next_shot(true)
	else:
		_shot_t += dt
		if _shot_t > SHOT_S:
			_next_shot(false)
		var s: Array = SHOTS[_shot]
		_goal_yaw += s[4] * dt
		var k := 1.0 - exp(-BLEND * dt)
		_yaw += wrapf(_goal_yaw - _yaw, -180.0, 180.0) * k
		_elev = lerpf(_elev, s[1], k)
		_dist_k = lerpf(_dist_k, s[2], k)
		_fov = lerpf(_fov, s[3], k)
	_frame()
	if car:
		if sliding != 0.0:
			car.global_position = _slide_from + _cam.global_basis.x * sliding
		var xf := car.get_global_transform_interpolated()
		_shadow.position = Vector3(xf.origin.x, FLOOR_Y + 0.005, xf.origin.z)
		_shadow.rotation.y = xf.basis.get_euler().y
		var m := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1)), Vector3(0, 2.0 * FLOOR_Y, 0))
		for t in _twins:
			var src: MeshInstance3D = t[0]
			if is_instance_valid(src):
				t[1].visible = src.is_visible_in_tree()
				t[1].global_transform = m * src.global_transform


func _next_shot(from_here: bool) -> void:
	_shot_t = 0.0
	if from_here:
		# The shot whose angle is nearest, so the camera doesn't swing right round.
		var best := 0
		for i in SHOTS.size():
			if absf(wrapf(SHOTS[i][0] - _yaw, -180, 180)) < absf(wrapf(SHOTS[best][0] - _yaw, -180, 180)):
				best = i
		_shot = best
		_goal_yaw = _yaw
		return
	_shot = (_shot + 1) % SHOTS.size()
	_goal_yaw = _yaw + wrapf(SHOTS[_shot][0] - _yaw, -180.0, 180.0)


## The camera on its orbit, at the distance that fits the car in its region, shifted so the
## car stands in the middle of it. The fit is found by projecting the car's box through the
## camera (so a close, wide lens that makes the nose loom is allowed for), a few steps a frame.
func _frame() -> void:
	var s := size if size.x > 0 else Vector2(1280, 720)
	_cam.fov = _fov
	var tv := tan(deg_to_rad(_fov * 0.5))
	var th := tv * s.x / s.y
	var yaw := deg_to_rad(_yaw)
	var e := deg_to_rad(_elev)
	var target := Vector3(0, FLOOR_Y + _half.y, 0)
	var dir := Vector3(sin(yaw) * cos(e), sin(e), cos(yaw) * cos(e))
	var room := Vector2(_region.size.x * 0.8, _region.size.y * 0.62) * s
	if _fit_d <= 0.0:
		_fit_d = 8.0
	var d := _fit_d
	var box := Rect2()
	for step in 3:
		_place(target, dir, d, 0.0, 0.0)
		box = _screen_box()
		var ratio := maxf(box.size.x / maxf(room.x, 1.0), box.size.y / maxf(room.y, 1.0))
		# Never inside the car's box, whatever the lens.
		d = clampf(d * pow(maxf(ratio, 0.01), 0.9), _half.length() * 1.6, 60.0)
	_fit_d = d
	d *= _dist_k
	_place(target, dir, d, 0.0, 0.0)
	box = _screen_box()
	# Shift the view so the box lands a little above the middle of the region (its
	# reflection takes some of the room under it).
	# Across by sliding the view sideways; up and down by tilting it (sliding it down would
	# take a low camera under the floor).
	var want := (_region.get_center() - Vector2(0, _region.size.y * 0.06)) * s
	var hoff := 0.0
	var tilt := 0.0
	for step in 2:
		var delta := want - box.get_center()
		hoff -= delta.x / s.x * 2.0 * d * th
		tilt += atan(delta.y / s.y * 2.0 * tv)
		_place(target, dir, d, hoff, 0.0, tilt)
		box = _screen_box()
	_rig.rotation.y = yaw


func _place(target: Vector3, dir: Vector3, d: float, hoff: float, voff: float, tilt := 0.0) -> void:
	var pos := target + dir * d
	pos.y = maxf(pos.y + sin(_time * 0.3) * 0.02, FLOOR_Y + 0.2)
	var b := Basis.looking_at(target - pos, Vector3.UP)
	# Tilting up (a positive tilt) lowers the car on the screen.
	b = b * Basis(Vector3.RIGHT, tilt)
	_cam.global_transform = Transform3D(b, pos)
	_cam.h_offset = hoff
	_cam.v_offset = voff


## The car's box (floor to roof) on screen, in the view's pixels.
func _screen_box() -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := -lo
	for k in 8:
		var p := Vector3(_half.x * (1 if k & 1 else -1), FLOOR_Y + _half.y * (2.0 if k & 2 else 0.0), _half.z * (1 if k & 4 else -1))
		if _cam.is_position_behind(p):
			continue
		var q := _cam.unproject_position(p)
		lo = lo.min(q)
		hi = hi.max(q)
	return Rect2(lo, hi - lo) if lo.x < INF else Rect2(Vector2.ZERO, Vector2.ONE)


# ------------------------------------------------------------------ shaders

static func _studio_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type sky;
// Soft-edged panel: 1 inside |p| < half, fading out over `soft`.
float panel(vec2 p, vec2 half, float soft) {
	vec2 q = smoothstep(half + soft, half - soft, abs(p));
	return q.x * q.y;
}
void sky() {
	vec3 d = EYEDIR;
	// Walls: near black, a touch lighter toward the ceiling; the floor darker still.
	vec3 c = mix(vec3(0.012), vec3(0.04, 0.042, 0.05), smoothstep(-0.1, 0.8, d.y));
	// A big softbox overhead, a little in front of the car.
	if (d.y > 0.2) {
		vec2 top = d.xz / d.y;
		c += vec3(2.2, 2.15, 2.05) * panel(top - vec2(0.0, 0.2), vec2(0.55, 0.3), 0.08);
	}
	// Tall strip lights either side, and a warmer low one ahead, for crisp lines down the flanks.
	float az = atan(d.x, -d.z);
	float el = d.y;
	c += vec3(1.5, 1.55, 1.7) * panel(vec2(abs(az) - 1.3, el - 0.2), vec2(0.05, 0.25), 0.03);
	c += vec3(1.1, 1.0, 0.9) * panel(vec2(az - 2.9, el - 0.12), vec2(0.35, 0.05), 0.03);
	COLOR = c;
}
"""
	return s


## A dark gloss floor (and the slices under it): see-through by `opacity` round the car so its
## reflection shows, fading out to nothing further off so the stage melts into the picture
## behind; a sheen towards grazing angles on the floor itself.
static func _floor_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float opacity = 0.45;
uniform float sheen = 1.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float r = length(wp.xz);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0) * sheen * 0.4;
	float pool = 1.0 - smoothstep(2.5, 20.0, r);
	pool *= pool;
	ALBEDO = mix(vec3(0.016, 0.018, 0.024), vec3(0.1, 0.105, 0.12), fresnel * 0.6);
	ALPHA = pool * opacity;
}
"""
	return s


static var _shadow_sh: Shader

static func _shadow_shader() -> Shader:
	if _shadow_sh == null:
		_shadow_sh = Shader.new()
		_shadow_sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled;
void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d * vec2(1.0, 1.0));
	ALBEDO = vec3(0.0);
	ALPHA = pow(1.0 - smoothstep(0.15, 1.0, r), 1.8) * 0.9;
}
"""
	return _shadow_sh
