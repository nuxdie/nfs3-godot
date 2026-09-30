class_name PlayerController
extends Node
## Reads keyboard/gamepad input into the parent Car.

var car: Car
var enabled := false


func _ready() -> void:
	car = get_parent() as Car
	process_physics_priority = -10
	car.set_manual(Game.manual_gears)


func _physics_process(_dt: float) -> void:
	car.hold = false
	car.horn = Input.is_action_pressed("horn")
	if not enabled:
		car.throttle = 0.0
		car.hold = true
		car.steer = 0.0
		return
	car.throttle = Input.get_action_strength("accelerate")
	car.brake = Input.get_action_strength("brake")
	car.handbrake = Input.is_action_pressed("handbrake")
	# Kept until the car can act on it (not in the middle of a shift).
	if Input.is_action_just_pressed("shift_up"):
		car.shift_request = 1
	elif Input.is_action_just_pressed("shift_down"):
		car.shift_request = -1
	# The car ramps the wheel in and out at its own rates (Car: turn-in and turn-out ramps).
	car.steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
