class_name PlayerController
extends Node
## Reads keyboard/gamepad input into the parent Car.

var car: Car
var enabled := false
var _steer := 0.0


func _ready() -> void:
	car = get_parent() as Car
	process_physics_priority = -10


func _physics_process(dt: float) -> void:
	car.hold = false
	if not enabled:
		car.throttle = 0.0
		car.hold = true
		car.steer = 0.0
		return
	car.throttle = Input.get_action_strength("accelerate")
	car.brake = Input.get_action_strength("brake")
	car.handbrake = Input.is_action_pressed("handbrake")
	var target := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	# Keyboard steering ramps in; returning to centre is quicker.
	var rate := 3.2 if absf(target) > absf(_steer) else 6.0
	_steer = move_toward(_steer, target, rate * dt)
	car.steer = _steer
