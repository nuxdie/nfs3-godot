extends Node
## Alongside --autotest: once racing, moves the player along each of the track's side
## roads (a slice every 0.25 s, facing along it, at speed) and logs the race's own resets
## and the progress node, to see a shortcut through end to end.
var t := 0.0
var step := 0
var mine := false
var slices: Array = []
func _physics_process(dt: float) -> void:
	var race := get_tree().current_scene
	if race == null or not "racers" in race or race.path == null or race.state != 2:
		return
	var p: Car = race.player
	if slices.is_empty():
		# The side roads: the track's again (the race keeps only the path's lookup of them).
		var tr := Nfs5Track.load_file(Game.track_dir(Game.track_id))
		for road: Array in [tr.side_roads[0], tr.side_roads[8], tr.side_roads[1]]:
			slices.append_array(road)
		p.was_reset.connect(func() -> void:
			if not mine:
				print("RACE RESET at step %d node %d" % [step, race.player_racer().node]))
		print("shortcut slices: %d" % slices.size())
	t += dt
	if t < 0.25:
		return
	t = 0.0
	if step >= slices.size():
		print("done: node %d progress %.0f lap %d" % [race.player_racer().node, race.player_racer().progress, race.player_racer().lap])
		get_tree().quit()
		return
	var vr: Nfs3Track.VRoad = slices[step]
	mine = true
	p.reset_to(Transform3D(Basis.looking_at(-vr.forward, Vector3.UP), vr.pos + Vector3.UP * 0.5), 0.3)
	mine = false
	p.linear_velocity = vr.forward * 15.0
	if step % 5 == 0 or step == slices.size() - 1:
		print("step %d: player node %d (progress %.0f), %.0f m off the lap, on side road %s" % [step, race.player_racer().node,
			race.player_racer().progress, absf(race.path.lateral(p.global_position, race.player_racer().node)), race.path.on_side_road(p.global_position)])
	step += 1
