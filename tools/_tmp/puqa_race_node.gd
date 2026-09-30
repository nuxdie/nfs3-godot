extends Node
## Alongside --autotest: logs every car reset (where, and what it was over) and cars that
## sink more than 3 m under the virtual road.
var hooked := {}
var t := 0.0
var sunk := {}
func _physics_process(dt: float) -> void:
	var race := get_tree().current_scene
	if race == null or not "racers" in race or race.path == null:
		return
	t += dt
	for rr: Dictionary in race.racers:
		var c: Car = rr.car
		if not hooked.has(c):
			hooked[c] = true
			c.was_reset.connect(func() -> void:
				print("RESET t=%.1f %s node=%d pos=%s" % [t, rr.name, rr.get("node", -1), c.global_position.round()]))
		var n: int = rr.get("node", 0)
		var dy: float = c.global_position.y - race.path.points[n].y
		if dy < -3.0 and t - sunk.get(c, -99.0) > 3.0:
			sunk[c] = t
			print("SUNK t=%.1f %s node=%d dy=%.1f lat=%.1f kmh=%d" % [t, rr.name, n, dy, race.path.lateral(c.global_position, n), c.kmh()])
