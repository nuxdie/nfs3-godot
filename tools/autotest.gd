extends Node
## Scripted play-through: starts a race, holds throttle, steers with a simple
## lane-keeper, saves screenshots to shots/ and prints telemetry, then quits.

var t := 0.0
var shots := [3.0, 8.0, 14.0, 22.0, 32.0]
var duration := 34.0
var race: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--autotest")
	if args.size() > i + 1:
		Game.track_id = args[i + 1]
	if args.size() > i + 2:
		Game.mode = int(args[i + 2])
	if args.size() > i + 3:
		Game.car_index = int(args[i + 3])
	Game.laps = 2
	Game.opponents = 3
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	if Game.track_id == "menu":
		# Just photograph the front end.
		for k in 60:
			await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png("shots/menu.png")
		get_tree().quit()
		return
	get_tree().change_scene_to_file.call_deferred("res://scenes/race.tscn")


func _physics_process(dt: float) -> void:
	race = get_tree().current_scene
	if race == null or not race.has_method("player_racer") or race.player == null:
		return
	t += dt
	var p: Car = race.player
	# Let a hidden AI steer, but feed its decisions through the real input actions.
	var r: Dictionary = race.player_racer()
	if race.path and r.size() > 0:
		var n: int = race.path.idx(r.node + 10)
		var local: Vector3 = p.global_transform.affine_inverse() * race.path.points[n]
		var ang: float = atan2(-local.x, maxf(local.z, 0.1))
		Input.action_release("steer_left")
		Input.action_release("steer_right")
		if ang > 0.05:
			Input.action_press("steer_right", clampf(ang * 2.0, 0.0, 1.0))
		elif ang < -0.05:
			Input.action_press("steer_left", clampf(-ang * 2.0, 0.0, 1.0))
		Input.action_press("accelerate")
	if int(t * 2) != int((t - dt) * 2):
		print("t=%.1f state=%d kmh=%d gear=%d rpm=%d wheels=%d lap=%d node=%d pos=%d slip=%.2f" % [t, race.state, p.kmh(), p.gear, p.rpm, p.grounded_wheels, r.get("lap", -9), r.get("node", -1), race.position_of(p), p.slip])
	if shots.size() > 0 and t >= shots[0]:
		# No framebuffer to read back in --headless runs; telemetry only.
		if DisplayServer.get_name() != "headless":
			var img := get_viewport().get_texture().get_image()
			var path := "shots/auto_%02d.png" % int(shots[0])
			img.save_png(path)
			print("shot ", path)
		shots.pop_front()
	if t > duration:
		get_tree().quit()
