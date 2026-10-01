class_name KnockableProp
extends RigidBody3D
## A road sign or post that stands frozen until a car touches it, then flies off. While
## standing it is invisible to the cars' physics (a trigger area detects them instead), so
## a hit costs the car only a little speed instead of a dead stop against a post.

const MASS := 40.0
## Share of its speed a car keeps after knocking a sign over.
const CAR_SPEED_KEPT := 0.92

## Played (all together) when it's knocked over, louder the faster the car: Hot Pursuit 2's
## props have theirs (Hp2PropSounds); the others none.
var knock_sounds: Array = []

var _trigger: Area3D
var _knocked := false


## In the prop's local space, whose origin is the post's foot: `mesh`, `reach` (the part a
## car body can touch, e.g. just the post) and `hull` (all of its points, for the loose body).
## `mesh` may be null (its nodes added as children instead) and `material` null (the mesh's
## own surface materials).
func setup(mesh: ArrayMesh, material: Material, reach: AABB, hull: PackedVector3Array,
		draw_distance: float) -> void:
	mass = MASS
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 0
	collision_mask = 0
	can_sleep = true

	if mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = draw_distance
		add_child(mi)

	var shape := ConvexPolygonShape3D.new()
	shape.points = hull
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)

	_trigger = Area3D.new()
	_trigger.collision_layer = 0
	_trigger.collision_mask = 2  # cars
	_trigger.monitorable = false
	var tcs := CollisionShape3D.new()
	var tshape := BoxShape3D.new()
	tshape.size = reach.size.max(Vector3(0.15, 0.2, 0.15))
	tcs.shape = tshape
	tcs.position = reach.get_center()
	_trigger.add_child(tcs)
	_trigger.body_entered.connect(_on_body_entered)
	add_child(_trigger)


func _on_body_entered(body: Node3D) -> void:
	if _knocked or not body is Car:
		return
	_knocked = true
	# Physics state can't change while the space is flushing its queries.
	_knock.call_deferred(body)


func _knock(car: Car) -> void:
	_trigger.queue_free()
	freeze = false
	# From now on it is loose debris: it lands on the road and cars can bump it.
	collision_layer = 2
	collision_mask = 1 | 2 | Nfs3TrackBuilder.SCENERY_LAYER
	var v := car.linear_velocity
	var speed := v.length()
	var up := Vector3.UP
	linear_velocity = v * 1.1 + up * (2.0 + speed * 0.12)
	# Topple away from the car: spin about the axis across its path.
	var axis := v.cross(up).normalized() if speed > 0.5 else Vector3.RIGHT
	angular_velocity = -axis * (2.0 + speed * 0.25)
	car.linear_velocity *= CAR_SPEED_KEPT
	for snd: AudioStream in knock_sounds:
		GameSounds.play_once(self, snd, linear_to_db(clampf(speed / 25.0, 0.3, 1.0)), randf_range(0.94, 1.06))
