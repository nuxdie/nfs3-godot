extends Node
## Scripted play-through: starts a race, drives the player's car through the input
## actions, saves screenshots to shots/ and prints telemetry, then quits.
## --ram (procedural track): instead drives the car into a few of the track's props that
## knock over and a guardrail, one every few seconds, with a screenshot of each.

var t := 0.0
var shots := [3.0, 8.0, 14.0, 22.0, 32.0]
var duration := 34.0
var race: Node


var _ai: AIController


func _ready() -> void:
	# Runs after the ghost AI (-20) has written its decisions to the car and before the
	# PlayerController (-10) reads the input actions back.
	process_physics_priority = -15
	var args := OS.get_cmdline_user_args()
	# Positional after --autotest: track, mode, car. Flags (--night, --duration=N, ...) go anywhere.
	var pos := Array(args.slice(args.find("--autotest") + 1)).filter(func(a: String) -> bool: return not a.begins_with("--"))
	if pos.size() > 0:
		Game.track_id = pos[0]
	if pos.size() > 1:
		Game.mode = int(pos[1])
	if pos.size() > 2:
		Game.car_index = int(pos[2])
	Game.night = "--night" in args
	for arg in args:
		if arg.begins_with("--duration="):
			duration = float(arg.trim_prefix("--duration="))
	Game.weather = "--weather" in args
	# --classic: the plain NFS3 handling, without body sway and progressive grip (F6 in game).
	if "--no-traffic" in args:
		Game.traffic = false
	Car.body_sway = not "--classic" in args
	Car.progressive_grip = Car.body_sway
	Game.laps = 2
	Game.opponents = 3
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	if Game.track_id == "menu":
		# Just photograph the front end.
		if "--settings" in args:
			get_tree().current_scene.open_settings.call_deferred()
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
	var r: Dictionary = race.player_racer()
	if "--ram" in OS.get_cmdline_user_args() and race.state == 2:
		_ram(p, dt)
	elif race.spectating():
		# Nothing to drive: flick through the field for a while instead.
		if race.state == 2 and t < 30.0 and int(t / 6.0) != int((t - dt) / 6.0):
			race._watch_step(1)
	elif race.path and r.size() > 0:
		_drive(p)
	if int(t * 2) != int((t - dt) * 2):
		print("t=%.1f state=%d kmh=%d gear=%d rpm=%d wheels=%d lap=%d node=%d pos=%d slip=%.2f" % [t, race.state, p.kmh(), p.gear, p.rpm, p.grounded_wheels, r.get("lap", -9), r.get("node", -1), race.position_of(p), p.slip])
		if race.spectating():
			var rs := []
			for rr: Dictionary in race.racers:
				rs.append("%s L%d%s %dkmh" % [rr.name.left(10), rr.lap, "F" if rr.finished else "", rr.car.kmh()])
			print("  field ", " | ".join(rs))
		if not race.cops.is_empty():
			var cs := []
			for c: Car in race.cops:
				var ai: AIController = race._controller(c)
				cs.append("%s%s%d@%dm/%dkmh" % ["B" if c.has_meta("backup") else "", "C" if ai.chasing else ("H" if ai.home >= 0 else "P"),
					ai.chase_slot, c.global_position.distance_to(p.global_position), c.kmh()])
			print("  cops heat=%d tickets=%d flat=%s roadblock=%d spikes=%d %s" % [race.heat, race.tickets, p.tyres_flat(), race.roadblock.size(), race.spikes.size(), " ".join(cs)])
	if shots.size() > 0 and t >= shots[0]:
		# No framebuffer to read back in --headless runs; telemetry only.
		if DisplayServer.get_name() != "headless":
			var img := get_viewport().get_texture().get_image()
			# --tag=NAME keeps parallel runs (other tracks, weather) from overwriting each other.
			var tag := ""
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--tag="):
					tag = arg.trim_prefix("--tag=") + "_"
			var path := "shots/auto_%s%02d.png" % [tag, int(shots[0])]
			img.save_png(path)
			print("shot ", path)
		shots.pop_front()
	if t > duration:
		get_tree().quit()


## Let a ghost AIController pick throttle/brake/steer (it brakes for bends and backs off
## walls), then feed those decisions through the real input actions so the player's
## controls path is what actually drives the car.
func _drive(p: Car) -> void:
	if _ai == null:
		_ai = AIController.new()
		_ai.role = AIController.Role.RACER
		_ai.path = race.path
		_ai.others = race.racers.map(func(x): return x.car) + race.traffic_cars + race.cops
		_ai.process_physics_priority = -20
		p.add_child(_ai)
		# add_child ran _ready, which resets the priority to -10.
		_ai.process_physics_priority = -20
	_ai.enabled = race.state == 2
	for a in ["accelerate", "brake", "steer_left", "steer_right", "handbrake"]:
		Input.action_release(a)
	if not _ai.enabled:
		return
	if p.throttle > 0.01:
		Input.action_press("accelerate", p.throttle)
	if p.brake > 0.01:
		Input.action_press("brake", p.brake)
	if p.steer > 0.01:
		Input.action_press("steer_right", p.steer)
	elif p.steer < -0.01:
		Input.action_press("steer_left", -p.steer)


var _ram_t := 0.0
var _ram_k := -1
var _ram_targets := []


## Every 4 s puts the car 22 m off a target, heading for it at 25 m/s.
func _ram(p: Car, dt: float) -> void:
	for a in ["accelerate", "brake", "steer_left", "steer_right", "handbrake"]:
		Input.action_release(a)
	if _ram_targets.is_empty():
		var br := get_tree().root.find_child("Breakables", true, false) as Breakables
		var gr := get_tree().root.find_child("Guardrails", true, false) as Guardrails
		if br:
			var n := br._items.size()
			for k in [0, n / 4, n / 2, 3 * n / 4, n - 1]:
				_ram_targets.append(["prop %d/%d" % [k, n], (br._items[k][0] as Transform3D).origin])
		for c: Car in race.parked_cars.slice(0, 1):
			_ram_targets.append(["parked car", c.global_position])
		if gr and not gr._chunks.is_empty():
			var box: AABB = gr._chunks[gr._chunks.size() / 2].box
			var mid := box.get_center()
			# A point on the rail itself: the vertex nearest the chunk's middle.
			var best := Vector3.INF
			for v: Vector3 in gr._chunks[gr._chunks.size() / 2].rest:
				if v.distance_to(mid) < best.distance_to(mid):
					best = v
			_ram_targets.append(["guardrail", best])
	_ram_t -= dt
	if _ram_t <= 0.0:
		_ram_report()
		_ram_k += 1
		if _ram_k == _ram_targets.size():
			_ram_look_at_bend()
		if _ram_k >= _ram_targets.size():
			return
		_ram_t = 4.0
		var target: Vector3 = _ram_targets[_ram_k][1]
		var i: int = race.path.closest(target)
		# From the road 24 m back, straight at it.
		var rail: bool = _ram_targets[_ram_k][0] == "guardrail"
		var start: Vector3 = race.path.points[race.path.idx(i - (2 if rail else 4))]
		var dir := Vector3(target.x - start.x, 0.0, target.z - start.z).normalized()
		p.reset_to(Transform3D(Basis.looking_at(-dir, Vector3.UP), start), 0.3)
		p.linear_velocity = dir * (35.0 if rail else 25.0)
		print("ram %s at %s" % [_ram_targets[_ram_k][0], target])
	Input.action_press("accelerate", 0.4)
	if absf(_ram_t - 3.0) < dt * 0.5 and DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png("shots/ram_%d.png" % _ram_k)


func _ram_report() -> void:
	if _ram_k < 0 or _ram_k >= _ram_targets.size():
		return
	var br := get_tree().root.find_child("Breakables", true, false) as Breakables
	var gr := get_tree().root.find_child("Guardrails", true, false) as Guardrails
	var loose := 0
	if br:
		for c in br.get_children():
			if c is KnockableProp:
				loose += 1
	var bent := 0
	if gr:
		for ch: Dictionary in gr._chunks:
			var v: PackedVector3Array = ch.arrays[Mesh.ARRAY_VERTEX]
			var rest: PackedVector3Array = ch.rest
			for k in v.size():
				if v[k].distance_to(rest[k]) > 0.02:
					bent += 1
	var frozen: int = race.parked_cars.filter(func(c: Car) -> bool: return c.freeze).size()
	print("  after %s: %d props knocked loose, %d guardrail vertices bent, %d/%d parked cars asleep" % [
		_ram_targets[_ram_k][0], loose, bent, frozen, race.parked_cars.size()])


## A last shot of the most bent guardrail, from a camera of its own.
func _ram_look_at_bend() -> void:
	var gr := get_tree().root.find_child("Guardrails", true, false) as Guardrails
	if gr == null or DisplayServer.get_name() == "headless":
		return
	var worst := 0.0
	var at := Vector3.ZERO
	var out := Vector3.ZERO
	for ch: Dictionary in gr._chunks:
		var v: PackedVector3Array = ch.arrays[Mesh.ARRAY_VERTEX]
		var rest: PackedVector3Array = ch.rest
		for k in v.size():
			var d := v[k].distance_to(rest[k])
			if d > worst:
				worst = d
				at = rest[k]
				out = v[k] - rest[k]
	if worst <= 0.0:
		return
	out.y = 0.0
	var cam := Camera3D.new()
	get_tree().current_scene.add_child(cam)
	var side := out.normalized().cross(Vector3.UP)
	cam.global_position = at - out.normalized() * 4.0 + side * 3.0 + Vector3.UP * 1.6
	cam.look_at(at, Vector3.UP)
	cam.make_current()
	for k in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("shots/ram_bend.png")
	print("bend shot: %.2f m at %s" % [worst, at])
