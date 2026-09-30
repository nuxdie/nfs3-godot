class_name Showroom
extends SubViewportContainer
## The menu's car (and the loading screen's), on a stage of its own in a transparent 3D view
## over the track's picture.
##   the stage     a dark gloss floor that fades out into the picture, the car mirrored in it
##                 (a copy of its meshes under the floor), a soft shadow under it, and a dark
##                 studio of softboxes that only shows in the paint's reflections, the
##                 track's picture (set_backdrop()) wrapped round it at the horizon
##   the camera    a director cutting between close-ups, each a slow move on one part of the
##                 car: the grille, a headlamp, the wheels, a tail lamp, the flank on a long
##                 lens, the roof from above. Most show something working as the camera's on
##                 it: the headlights (pop-ups rising), the brake and reversing lamps, the
##                 spoiler, the soft top folding, the hazards, the wipers. What's chosen in
##                 the menu shows on the car without breaking the shot: a new car drops in,
##                 a paint goes on, its lamps light by night, its wipers go in the rain.
##                 Dragging turns the camera about what it's looking at; a few seconds after
##                 letting go the director carries on.
##   the mirrors   a Porsche Unleashed car's side mirrors reflect: each glass shows what the
##                 camera would see in it, from a camera mirrored in the glass's plane
##   the start     rev(): a low wide shot of the nose, headlights on, the engine revved
##                 (its own sounds, CarAudio) with the body rocking on its mounts.
## The car is the race car itself, parked and dropped onto the floor, so it lands and settles
## on its springs, its driver at the wheel, turning it (and the front wheels) on the shots
## that show them. The loading screen's (`loading`) runs its few slow shots off a clock it
## hands over to the race scene's.

const FLOOR_Y := -0.595
const DROP_HEIGHT := 0.6          # tyres this far above the floor when a car is dropped in
const RESUME_S := 4.0             # after a drag, how long before the director takes back over
const REV_S := 2.0                # rev(): how long before the race can take over
const GLASS_LAYER := 1 << 19      # the side mirrors' glass: left out of their own views

## The shots. `at` (and `to`, where the camera tracks along) is what it looks at, on the car's
## box: x -1..1 right to left side, y 0..1 floor to roof, z -1..1 tail to nose. The camera is
## `yaw` degrees round from the nose (+ toward the car's left), `elev` up, `dist` metres off
## (for a car 4.4 m long), each going from its first value to its second over the shot's
## `len`; `roll` tips the frame; `frame` moves what it looks at off the middle of the car's
## region (by fractions of it); `on_driver` looks at the driver's head instead of `at`, where
## the car has a driver, `on_mirror` at the side mirror's glass on the camera's side; `fixed` keeps it on the side it's written for (where the
## driver shows best), where the others are taken from either side. `needs` names a part the car must have for the shot. `steer`
## has the driver turn the wheel: [how far (of full lock), how quickly (rad/s)], a slow
## swing from one side to the other.
const SHOTS := {
	"hero": {"at": Vector3(0, 0.42, 0.25), "to": Vector3(0, 0.42, 0.05), "yaw": [30.0, 44.0], "elev": [4.0, 6.0],
		"dist": [6.4, 5.4], "fov": [34.0, 32.0], "steer": [0.8, 0.9], "len": 5.0},
	"grille": {"at": Vector3(0, 0.3, 1.0), "to": Vector3(0, 0.36, 1.0), "yaw": [-16.0, 8.0], "elev": [2.0, 4.5],
		"dist": [2.3, 1.8], "fov": [42.0, 46.0], "roll": 3.0, "steer": [1.0, 1.1], "len": 4.5},
	"headlamp": {"at": Vector3(0.62, 0.42, 0.92), "yaw": [26.0, 46.0], "elev": [5.0, 8.0],
		"dist": [1.7, 1.3], "fov": [36.0, 32.0], "len": 4.5, "needs": "lamps"},
	"wheel": {"at": Vector3(1.0, 0.28, 0.62), "to": Vector3(1.0, 0.28, -0.62), "yaw": [78.0, 102.0], "elev": [3.0, 3.0],
		"dist": [2.2, 2.2], "fov": [42.0, 42.0], "steer": [1.0, 1.3], "len": 5.0},
	"flank": {"at": Vector3(1.0, 0.5, 0.95), "to": Vector3(1.0, 0.5, -0.95), "yaw": [88.0, 92.0], "elev": [5.0, 6.0],
		"dist": [15.0, 15.0], "fov": [10.0, 10.0], "len": 5.0},
	"tail": {"at": Vector3(0.62, 0.55, -0.95), "yaw": [152.0, 134.0], "elev": [7.0, 9.0],
		"dist": [1.8, 1.45], "fov": [36.0, 34.0], "len": 4.5},
	"spoiler": {"at": Vector3(0, 0.72, -0.9), "yaw": [165.0, 196.0], "elev": [16.0, 22.0],
		"dist": [2.7, 2.3], "fov": [34.0, 34.0], "len": 4.5, "needs": "spoiler"},
	"top": {"at": Vector3(0, 0.85, -0.1), "yaw": [118.0, 146.0], "elev": [26.0, 34.0],
		"dist": [3.8, 3.3], "fov": [36.0, 36.0], "len": 5.5, "needs": "top"},
	"hazards": {"at": Vector3(0.7, 0.45, -0.95), "yaw": [150.0, 140.0], "elev": [3.0, 4.0],
		"dist": [2.1, 1.75], "fov": [38.0, 38.0], "roll": -3.0, "len": 4.0, "needs": "signals"},
	"wipers": {"at": Vector3(0, 0.74, 0.3), "yaw": [12.0, -10.0], "elev": [24.0, 19.0],
		"dist": [2.5, 2.2], "fov": [34.0, 34.0], "len": 5.0, "needs": "wipers"},
	# Porsche Unleashed's: the driver's door swinging open, its window winding down; the
	# bonnet up over the luggage space (or engine); the engine lid (or boot) up at the back.
	"door": {"at": Vector3(1.0, 0.5, 0.15), "yaw": [62.0, 42.0], "elev": [9.0, 12.0],
		"dist": [3.6, 3.1], "fov": [38.0, 38.0], "fixed": true, "len": 6.0, "needs": "door"},
	"bonnet": {"at": Vector3(0, 0.55, 0.7), "yaw": [-28.0, -8.0], "elev": [20.0, 26.0],
		"dist": [3.4, 3.0], "fov": [36.0, 36.0], "len": 5.5, "needs": "bonnet"},
	"engine": {"at": Vector3(0, 0.6, -0.75), "yaw": [196.0, 166.0], "elev": [22.0, 28.0],
		"dist": [3.3, 2.9], "fov": [36.0, 36.0], "len": 5.5, "needs": "boot"},
	"paint": {"at": Vector3(1.0, 0.62, 0.3), "to": Vector3(1.0, 0.6, -0.35), "yaw": [52.0, 76.0], "elev": [10.0, 13.0],
		"dist": [2.4, 2.0], "fov": [30.0, 30.0], "roll": -4.0, "len": 4.5},
	"driver": {"at": Vector3(0.4, 0.8, 0.1), "on_driver": true, "yaw": [30.0, 48.0], "elev": [22.0, 26.0],
		"frame": Vector2(0.0, 0.1), "dist": [2.6, 2.2], "fov": [32.0, 32.0], "steer": [1.0, 1.0], "fixed": true, "len": 5.0},
	"mirror": {"at": Vector3(1.0, 0.7, 0.3), "on_mirror": true, "yaw": [150.0, 136.0], "elev": [6.0, 9.0],
		"dist": [1.15, 0.9], "fov": [32.0, 30.0], "roll": -3.0, "fixed": true, "len": 4.5, "needs": "mirrors"},
	"overhead": {"at": Vector3(0, 0.5, 0), "yaw": [-10.0, 20.0], "elev": [74.0, 70.0],
		"dist": [7.2, 6.4], "fov": [36.0, 36.0], "len": 5.0},
	"rev": {"at": Vector3(0.45, 0.4, 0.95), "yaw": [-24.0, -18.0], "elev": [1.5, 2.5],
		"dist": [1.9, 1.45], "fov": [40.0, 44.0], "roll": 5.0, "frame": Vector2(0.0, 0.2), "len": 9.0},
	# The loading screen's: wider, slower, the driver in sight.
	"l_hero": {"at": Vector3(0, 0.45, 0.1), "yaw": [34.0, 50.0], "elev": [5.0, 6.0],
		"dist": [5.6, 4.8], "fov": [32.0, 32.0], "steer": [0.6, 0.7], "len": 6.0},
	"l_driver": {"at": Vector3(0.35, 0.75, 0.1), "on_driver": true, "yaw": [50.0, 66.0], "elev": [7.0, 9.0],
		"dist": [3.4, 2.9], "fov": [30.0, 30.0], "steer": [0.7, 0.8], "len": 6.0},
	"l_rear": {"at": Vector3(0, 0.5, -0.3), "yaw": [150.0, 136.0], "elev": [6.0, 7.0],
		"dist": [5.2, 4.6], "fov": [30.0, 30.0], "len": 6.0},
}
## The menu's round of them (those the car can't show are skipped), and the loading screen's.
const ROUND := ["hero", "headlamp", "wheel", "tail", "spoiler", "driver", "door", "flank", "mirror", "top",
	"bonnet", "grille", "hazards", "engine", "paint", "wipers", "overhead"]
const LOADING_ROUND := ["l_hero", "l_driver", "l_rear"]
var car: Car                      # the car on the stage (null while none)
var loading := false              # the loading screen's: the driver in, its own slow round
var night := false                # the lights on (the menu's time of day)
var rain := false                 # the wipers going and the top up (the menu's weather)

var _vp: SubViewport
var _world: Node3D
var _sky_mat: ShaderMaterial
var _backdrop: Texture2D
var _backdrop_tw: Tween
var _rig: Node3D                  # the lights, turned with the camera so the car stays lit the same
var _cam: Camera3D
var _shadow: MeshInstance3D
var _mirror: Node3D               # the reflection: a copy of each of the car's meshes
var _twins: Array = []            # [source MeshInstance3D, its copy]
var _glass: Array[Dictionary] = []   # the side mirrors: {node, point, normal (car-local), vp, cam}
var _region := Rect2(0.5, 0.2, 0.4, 0.5)   # where the car goes, as fractions of the view
var _half := Vector3(0.9, 0.7, 2.2)        # the car's half extents
var _head := Vector3.INF                   # the driver's head, on the stage (INF: no driver)

# The director: the shot on, how far into it, which side of the car.
var _shot := "hero"
var _shot_t := 0.0
var _side := 1.0
var _round_i := 0
var _beats_done := {}
var _dragging := false
var _manual_t := 0.0              # > 0: the player turned it; counts down to the director again
var _drag := Vector2.ZERO         # the player's turn on top of the shot: yaw, elevation (degrees)
var _time := 0.0
# rev()
var _rev_t := -1.0
var _rev_xf: Transform3D
var _rev_rock := 0.0
var _audio: CarAudio


func _init() -> void:
	stretch = true
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.audio_listener_enable_3d = true
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


func _exit_tree() -> void:
	if not loading:
		Car.precipitation = 0.0


## The director's clock (the loading screen's, carried over from the menu's).
func set_clock(t: float) -> void:
	_time = t


## Where on the view the car should stand, as a rect in the view's own pixels.
func set_region(r: Rect2) -> void:
	var s := size if size.x > 0 else Vector2(1280, 720)
	_region = Rect2(r.position / s, r.size / s)


## Puts `data` on the stage in `tint` (the paint), dropped in from a little height (`drop`).
func show_car(data: Object, tint: Color, upgrade := 0, id := -1, drop := DROP_HEIGHT) -> void:
	if car:
		car.queue_free()
		car = null
	for t in _twins:
		t[1].queue_free()
	_twins.clear()
	for g in _glass:
		g.vp.queue_free()
	_glass.clear()
	var c := Car.new()
	c.setup(data, tint, upgrade)
	c.handbrake = true
	c.fold_speed = 1.6
	c.set_meta("car", id)
	_world.add_child(c)
	c.reset_to(Transform3D(Basis(), Vector3(0, FLOOR_Y, 0)), drop)
	car = c
	_head = _find_head(c)
	_half = data.half_size
	(_shadow.mesh as PlaneMesh).size = Vector2(_half.x * 2.9, _half.z * 2.5)
	_shadow.visible = true
	_settle(true)
	_build_twins.call_deferred()
	_build_mirrors()


## Cuts to the shot of the driver at the wheel, where the car has one.
func show_driver() -> void:
	if car and _head != Vector3.INF:
		_cut_to("driver")


## The car on the stage in another paint, without dropping it in again.
func repaint(tint: Color) -> void:
	if car:
		car.set_paint(tint)


## The picture behind the stage (the track's), for the paint to reflect: wrapped round the
## studio at the horizon, its top row carried up the sky and its bottom one down the floor.
## A new one fades in over the old.
func set_backdrop(tex: Texture2D) -> void:
	if tex == _backdrop:
		return
	_sky_mat.set_shader_parameter("photo_from", _backdrop)
	_sky_mat.set_shader_parameter("has_from", 1.0 if _backdrop else 0.0)
	_sky_mat.set_shader_parameter("photo_to", tex)
	_sky_mat.set_shader_parameter("has_to", 1.0 if tex else 0.0)
	_sky_mat.set_shader_parameter("fade", 0.0)
	_backdrop = tex
	if _backdrop_tw:
		_backdrop_tw.kill()
	_backdrop_tw = create_tween()
	_backdrop_tw.tween_property(_sky_mat, "shader_parameter/fade", 1.0, 0.4)


func shown_id() -> int:
	return car.get_meta("car", -1) if car else -1


## The menu's time of day and weather: the car lit and its wipers going to suit.
func set_conditions(is_night: bool, is_rain: bool) -> void:
	night = is_night
	rain = is_rain
	_settle(false)


## The start: a low shot of the nose, headlights on, and the engine revved. Returns how long
## until the race can take over.
func rev() -> float:
	if car == null:
		return 0.3
	_rev_t = 0.0
	_manual_t = 0.0
	_drag = Vector2.ZERO
	_cut_to("rev")
	car.freeze = true
	# Its revs and pedals are ours now.
	car.set_physics_process(false)
	car.is_player = true
	car.hold = false
	car.brake = 0.0
	car.gear = 1
	car.indicate = 0
	car.set_headlights(true)
	_rev_xf = car.global_transform
	_audio = CarAudio.new()
	car.add_child(_audio)
	return REV_S


## The car as chosen: lamps by night, wipers and top up in the rain; with `now` straight there.
func _settle(now: bool) -> void:
	if car == null or _rev_t >= 0.0:
		return
	car.hold = false
	car.brake = 0.0
	car.gear = 1
	car.indicate = 0
	car.spoiler_raise = false
	car.set_headlights(night or loading and Game.night, now)
	for g in Nfs5Car.LID_GROUPS:
		car.set_open(g, false, now)
	if not loading:
		car.set_top_down(not rain, now)
		for side in [Nfs5Car.DOOR_LEFT, Nfs5Car.DOOR_RIGHT]:
			car.set_window_down(side, not rain and car.has_soft_top(), now)
		Car.precipitation = 0.6 if rain else 0.0


## The driver's head, where the car stands: the top of the people's mesh (the driver's, the
## side the steering wheel's on when there's a passenger too), or INF.
func _find_head(c: Car) -> Vector3:
	var dm: Material = c._driver_mat
	if dm == null:
		return Vector3.INF
	for n in c.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.material_override != dm or mi.mesh == null:
			continue
		var v: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		if v.is_empty():
			continue
		var top := -INF
		for p in v:
			top = maxf(top, p.y)
		# The heads: what's in the top 12 cm (well below a head's height, above any shoulder).
		# Two people sit apart across the car: split them at the widest gap and keep the
		# driver's, on the +X side (the model's left) in both games' cars.
		var xs: Array[float] = []
		for p in v:
			if p.y > top - 0.12:
				xs.append(p.x)
		xs.sort()
		var cut := -INF
		var gap := 0.3
		for i in range(1, xs.size()):
			if xs[i] - xs[i - 1] > gap:
				gap = xs[i] - xs[i - 1]
				cut = (xs[i] + xs[i - 1]) * 0.5
		var sum := Vector3.ZERO
		var k := 0
		for p in v:
			if p.y > top - 0.12 and p.x > cut:
				sum += p
				k += 1
		var head := sum / maxi(k, 1)
		return c.to_local(mi.global_transform * head)
	return Vector3.INF


## Whether the car has what shot `name` shows.
func _can_show(name: String) -> bool:
	var need: String = SHOTS[name].get("needs", "")
	if car == null or need == "":
		return true
	match need:
		"lamps": return not (car._lamps.is_empty() and car._popups.is_empty())
		"spoiler": return not car._spoiler_up.is_empty()
		"top": return car.has_soft_top()
		"signals": return not car._signals.is_empty()
		"wipers": return not car._wipers.is_empty()
		"mirrors": return not _glass.is_empty()
		"door": return car.can_open(Nfs5Car.DOOR_LEFT)
		"bonnet": return car.can_open(Nfs5Car.BONNET)
		"boot": return car.can_open(Nfs5Car.BOOT)
	return true


## What happens on the car while shot `name` is on it, `t` s in: each beat once.
func _beats(name: String, t: float) -> void:
	var b := func(at: float, key: String) -> bool:
		if t < at or _beats_done.has(key):
			return false
		_beats_done[key] = true
		return true
	match name:
		"headlamp":
			# The lights go the other way from how they're set, and back.
			if b.call(0.6, "a"):
				car.set_headlights(not car.headlights_on)
			if b.call(2.8, "b"):
				car.set_headlights(not car.headlights_on)
		"tail":
			if b.call(0.5, "brake"):
				car.hold = true
			if b.call(2.0, "off"):
				car.hold = false
				car.brake = 0.0
			if b.call(2.5, "reverse"):
				car.gear = -1
			if b.call(3.8, "drive"):
				car.gear = 1
		"spoiler":
			if b.call(0.5, "up"):
				car.spoiler_raise = true
			if b.call(3.0, "down"):
				car.spoiler_raise = false
		"top":
			if b.call(0.4, "fold"):
				car.set_top_down(not car.top_down)
		"hazards":
			if b.call(0.3, "on"):
				car.indicate = 2
		"wipers":
			if b.call(0.2, "on"):
				Car.precipitation = 0.8
		"door":
			if b.call(0.6, "open"):
				car.set_open(Nfs5Car.DOOR_LEFT, true)
			if b.call(1.4, "window"):
				car.set_window_down(Nfs5Car.DOOR_LEFT, true)
			if b.call(4.6, "shut"):
				car.set_open(Nfs5Car.DOOR_LEFT, false)
		"bonnet":
			if b.call(0.5, "open"):
				car.set_open(Nfs5Car.BONNET, true)
			if b.call(4.2, "shut"):
				car.set_open(Nfs5Car.BONNET, false)
		"engine":
			if b.call(0.5, "open"):
				car.set_open(Nfs5Car.BOOT, true)
			if b.call(4.2, "shut"):
				car.set_open(Nfs5Car.BOOT, false)


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
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = _studio_shader()
	env.sky = Sky.new()
	env.sky.sky_material = _sky_mat
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
		# Not the lamps' glows: camera-facing, they'd mirror as blobs of light.
		if src.mesh == null or src.mesh is QuadMesh:
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


## The side mirrors' views: a view each, into this stage's world, shown on its glass.
func _build_mirrors() -> void:
	if Game.quality == Game.Quality.LOW:
		return
	for g in car._cabin_mirror_glass:
		var vp := SubViewport.new()
		vp.world_3d = _vp.find_world_3d()
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var cam := Camera3D.new()
		cam.far = 60.0
		cam.cull_mask &= ~GLASS_LAYER
		vp.add_child(cam)
		# Not straight under this container, which would show it over the stage.
		_world.add_child(vp)
		var m := ShaderMaterial.new()
		m.shader = _mirror_shader()
		m.set_shader_parameter("view", vp.get_texture())
		(g.node as MeshInstance3D).material_override = m
		(g.node as MeshInstance3D).layers = GLASS_LAYER
		_glass.append({"node": g.node, "point": g.point, "normal": g.normal, "vp": vp, "cam": cam})


## Each mirror's camera: the stage's camera reflected in the glass's plane (its x turned
## round, so it's a proper camera and its picture comes out flipped across: the glass reads
## it back flipped), clipped at the glass so what's behind it stays out. Only while the
## glass is on screen and faces the camera.
func _update_mirrors() -> void:
	if _glass.is_empty() or car == null:
		return
	var xf := car.get_global_transform_interpolated()
	var o := _cam.global_position
	var b := _cam.global_basis
	var px := Vector2i((size if size.x > 0 else Vector2(1280, 720)) * (1.0 if Game.quality == Game.Quality.HIGH else 0.5))
	for g in _glass:
		var n: Vector3 = (xf.basis * (g.normal as Vector3)).normalized()
		var p: Vector3 = xf * (g.point as Vector3)
		var vp: SubViewport = g.vp
		var on := is_visible_in_tree() and (o - p).dot(n) > 0.02 and _cam.is_position_in_frustum(p) \
			and (g.node as Node3D).is_visible_in_tree()
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
		if not on:
			continue
		if vp.size != px:
			vp.size = px
		var cam: Camera3D = g.cam
		var r := func(v: Vector3) -> Vector3: return v - 2.0 * v.dot(n) * n
		var o2 := o - 2.0 * (o - p).dot(n) * n
		var b2 := Basis(-r.call(b.x), r.call(b.y), r.call(b.z))
		cam.global_transform = Transform3D(b2, o2)
		cam.fov = _cam.fov
		cam.h_offset = -_cam.h_offset
		cam.near = maxf((p - o2).dot(-b2.z) - 0.08, 0.05)


# ------------------------------------------------------------------ input

func _gui_input(e: InputEvent) -> void:
	if loading or _rev_t >= 0.0:
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_dragging = e.pressed
		if e.pressed:
			_manual_t = RESUME_S
	elif e is InputEventMouseMotion and _dragging:
		_drag.x -= e.relative.x * 0.3
		_drag.y = clampf(_drag.y + e.relative.y * 0.2, -30.0, 60.0)
		_manual_t = RESUME_S


# ------------------------------------------------------------------ the director

func _process(dt: float) -> void:
	_time += dt
	if loading:
		# Off the clock alone, so the race scene's loading screen carries on the same shot.
		var n := LOADING_ROUND.size()
		var total := 0.0
		for k in n:
			total += SHOTS[LOADING_ROUND[k]].len
		var t := fmod(_time, total)
		for k in n:
			var l: float = SHOTS[LOADING_ROUND[k]].len
			if t < l or k == n - 1:
				_shot = LOADING_ROUND[k]
				_shot_t = t
				break
			t -= l
		_side = 1.0
	elif _manual_t > 0.0:
		if not _dragging:
			_manual_t -= dt
			if _manual_t <= 0.0:
				_next_shot()
	else:
		_shot_t += dt
		if car:
			_beats(_shot, _shot_t)
		if _shot_t > SHOTS[_shot].len and _rev_t < 0.0:
			_next_shot()
	# The player's turn eases back out once the director has it again.
	if _manual_t <= 0.0 and not _dragging:
		_drag = _drag.lerp(Vector2.ZERO, 1.0 - exp(-dt * 3.0))
	if _rev_t >= 0.0:
		_rev(dt)
	elif car:
		# The driver at the wheel: a slow swing lock to lock where the shot shows it, else straight.
		var st: Array = SHOTS[_shot].get("steer", [0.0, 0.0])
		car.steer = st[0] * sin(_shot_t * st[1])
	_frame()
	_update_mirrors()
	if car:
		var xf := car.get_global_transform_interpolated()
		_shadow.position = Vector3(xf.origin.x, FLOOR_Y + 0.005, xf.origin.z)
		_shadow.rotation.y = xf.basis.get_euler().y
		var m := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1)), Vector3(0, 2.0 * FLOOR_Y, 0))
		for t in _twins:
			var src: MeshInstance3D = t[0]
			if is_instance_valid(src):
				t[1].visible = src.is_visible_in_tree()
				t[1].global_transform = m * src.global_transform


## The next shot: the next of the round the car can show.
func _next_shot() -> void:
	var name := ""
	for k in ROUND.size():
		var cand: String = ROUND[(_round_i + k) % ROUND.size()]
		if _can_show(cand) and cand != _shot:
			_round_i = (_round_i + k + 1) % ROUND.size()
			name = cand
			break
	_cut_to(name if name != "" else "hero")


func _cut_to(name: String) -> void:
	_shot = name
	_shot_t = 0.0
	_beats_done.clear()
	# Either side of the car, as it comes.
	_side = -1.0 if randf() < 0.4 and name != "rev" and not SHOTS[name].get("fixed", false) else 1.0
	_settle(false)


## The shot's camera, `u` of the way through it, where the player's turned it to, framed so
## what it looks at stands in the car's region of the view (by sliding the view across and
## tilting it, which keeps a low camera off the floor).
func _frame() -> void:
	var sh: Dictionary = SHOTS[_shot]
	var len: float = sh.len
	var u := clampf(_shot_t / len, 0.0, 1.0)
	# A slow move that settles: mostly steady, easing out at the end.
	u = lerpf(u, 1.0 - (1.0 - u) * (1.0 - u), 0.5)
	var k := _half.z / 2.2
	var at: Vector3 = sh.at
	if sh.has("to"):
		at = at.lerp(sh.to, u)
	var target := Vector3(at.x * _half.x * _side, FLOOR_Y + at.y * _half.y * 2.0, at.z * _half.z)
	if sh.get("on_driver", false) and _head != Vector3.INF and car:
		target = car.global_transform * _head
	elif sh.get("on_mirror", false) and car:
		for g in _glass:
			if signf((g.point as Vector3).x) == _side:
				target = car.global_transform * (g.point as Vector3)
	var yaw := deg_to_rad(lerpf(sh.yaw[0], sh.yaw[1], u) * _side + _drag.x + sin(_time * 0.37) * 0.6)
	var e := deg_to_rad(clampf(lerpf(sh.elev[0], sh.elev[1], u) + _drag.y + sin(_time * 0.29) * 0.4, -5.0, 85.0))
	var d: float = lerpf(sh.dist[0], sh.dist[1], u) * k
	var fov: float = lerpf(sh.fov[0], sh.fov[1], u)
	var roll := deg_to_rad(float(sh.get("roll", 0.0)) * _side)
	var dir := Vector3(sin(yaw) * cos(e), sin(e), cos(yaw) * cos(e))
	# Never inside the car, nor under the floor.
	var box := AABB(Vector3(-_half.x - 0.12, FLOOR_Y - 1.0, -_half.z - 0.12), Vector3(_half.x + 0.12, 1.0 + _half.y * 2.0 + 0.12, _half.z + 0.12) * Vector3(2, 1, 2))
	for step in 40:
		if not box.has_point(target + dir * d):
			break
		d += 0.1
	var shake := Vector3.ZERO
	if _rev_t >= 0.0 and car:
		var r := clampf(car.rpm / maxf(car.redline, 1000.0), 0.0, 1.2)
		shake = Vector3(sin(_time * 53.0), sin(_time * 61.0 + 1.0), sin(_time * 47.0 + 2.0)) * 0.006 * r * r
	var s := size if size.x > 0 else Vector2(1280, 720)
	_cam.fov = fov
	var tv := tan(deg_to_rad(fov * 0.5))
	var th := tv * s.x / s.y
	var want := (_region.get_center() + _region.size * (sh.get("frame", Vector2.ZERO) as Vector2)) * s
	var hoff := 0.0
	var tilt := 0.0
	_place(target, dir, d, shake, 0.0, 0.0, 0.0)
	for step in 2:
		if _cam.is_position_behind(target):
			break
		var delta := want - _cam.unproject_position(target)
		hoff -= delta.x / s.x * 2.0 * d * th
		tilt += atan(delta.y / s.y * 2.0 * tv)
		_place(target, dir, d, shake, hoff, tilt, 0.0)
	_place(target, dir, d, shake, hoff, tilt, roll)
	_rig.rotation.y = yaw


func _place(target: Vector3, dir: Vector3, d: float, shake: Vector3, hoff: float, tilt: float, roll: float) -> void:
	var pos := target + dir * d
	pos.y = maxf(pos.y + sin(_time * 0.3) * 0.01, FLOOR_Y + 0.1)
	var b := Basis.looking_at(target - pos, Vector3.UP)
	# Tilting up (a positive tilt) lowers what it looks at on the screen.
	b = b * Basis(Vector3.RIGHT, tilt) * Basis(Vector3.BACK, roll)
	_cam.global_transform = Transform3D(b, pos + shake)
	_cam.h_offset = hoff


## rev(): the revs over time, blipped twice then held against the limiter; the body rocks
## on its mounts against the engine's torque, and shivers at idle.
func _rev(dt: float) -> void:
	_rev_t += dt
	if car == null:
		return
	var R := car.redline
	var t := _rev_t
	var goal := car.idle_rpm
	var gas := 0.0
	if t > 0.25 and t < 0.45:
		goal = R * 0.72
		gas = 1.0
	elif t >= 0.8 and t < 0.98:
		goal = R * 0.6
		gas = 1.0
	elif t >= 1.15:
		# Flat out, bouncing off the limiter.
		goal = R * (0.97 if fmod(t, 0.09) < 0.06 else 0.9)
		gas = 1.0
	var was := car.rpm
	car.rpm = lerpf(car.rpm, goal, 1.0 - exp(-dt * (14.0 if goal > car.rpm else 5.0)))
	car.throttle = gas
	var push := clampf((car.rpm - was) / maxf(dt, 0.001) / R, -3.0, 3.0)
	_rev_rock = lerpf(_rev_rock, push * 0.012, 1.0 - exp(-dt * 10.0))
	var shiver := sin(_time * 70.0) * 0.0015 * (0.3 + car.rpm / R)
	var tw := Basis(Vector3.BACK, _rev_rock + shiver) * Basis(Vector3.RIGHT, -absf(_rev_rock) * 0.3)
	car.global_transform = Transform3D(_rev_xf.basis * tw, _rev_xf.origin)


# ------------------------------------------------------------------ shaders

static func _studio_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type sky;
uniform sampler2D photo_from : source_color, filter_linear, repeat_disable;
uniform sampler2D photo_to : source_color, filter_linear, repeat_disable;
uniform float has_from = 0.0;
uniform float has_to = 0.0;
uniform float fade = 1.0;
// The picture round the horizon: across it once each way round (so it meets itself nose
// and tail), from a little below the horizon to well up; above and below, its top and
// bottom rows smeared out, the ground darkening toward straight down.
vec4 photo(sampler2D t, float has, vec3 d) {
	float u = abs(atan(d.x, -d.z)) / PI;
	float v = clamp((0.55 - d.y) / 0.8, 0.02, 0.98);
	vec3 c = textureLod(t, vec2(u, v), 0.0).rgb * mix(0.3, 1.0, smoothstep(-0.7, -0.2, d.y));
	return vec4(c * has, has);
}
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
	// The track's picture over the walls, the softboxes still catching in it.
	vec4 a = photo(photo_from, has_from, d);
	vec4 b = photo(photo_to, has_to, d);
	vec4 p = mix(a, b, fade);
	COLOR = mix(c, p.rgb / max(p.a, 1e-4) * 0.8 + c * 0.5, p.a);
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


static var _mirror_sh: Shader

## A side mirror's glass: its view (see _update_mirrors()), read back flipped across, a
## shade darker; where the view has nothing (the studio's clear backdrop) a dark grey.
static func _mirror_shader() -> Shader:
	if _mirror_sh == null:
		_mirror_sh = Shader.new()
		_mirror_sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D view : source_color, filter_linear;
void fragment() {
	vec4 c = texture(view, vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y));
	ALBEDO = mix(vec3(0.05, 0.055, 0.065), c.rgb * 0.85, c.a);
}
"""
	return _mirror_sh


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
