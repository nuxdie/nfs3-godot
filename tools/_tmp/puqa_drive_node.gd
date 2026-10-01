extends Node
## Alongside --autotest on a Porsche Unleashed track: drives the player's car (real physics)
## along every route: the lap from the grid to the finish, then each side road (shortcut,
## alternative route) from a run-up on the lap through its slices and back onto the lap.
## Logs the race's own resets (with why), getting stuck, leaving the route, and progress
## jumps. Ends with a summary line per route.
##   --only=lap | --only=side | --only=<side road index>

const RUNUP := 80.0
const RUNOUT := 70.0
const STUCK_T := 4.0
const JUNCTION := 25.0
var adj: Array = []

var race: Node
var routes: Array[Dictionary] = []
var ri := -1
var pts := PackedVector3Array()
var cum := PackedFloat32Array()
var ci := 0
var rt := 0.0
var stuck_t := 0.0
var back_t := 0.0
var tries := 0
var mine := false
var issues: Array[String] = []
var last_pos := Vector3.ZERO
var last_xf := Transform3D()
var last_lap := 0
var last_prog := 0.0
var summary: Array[String] = []
var only := ""
var max_off := 0.0
var behind_t := 0.0
var respawned := false    # --respawn: the race's _respawn once, halfway along each side road
var probing := false
var notes: Array[String] = []
var shift := 0.0          # m right of the route, to get round something standing on it
var shift_until := 0.0    # m along the route
var trace := Vector3.INF   # --trace=x,z,r: telemetry within r m of x,z
var trace_t := 0.0


func _ready() -> void:
	process_physics_priority = -5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--trace="):
			var f := a.trim_prefix("--trace=").split_floats(",")
			trace = Vector3(f[0], f[1], f[2])
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	var a := Array(OS.get_cmdline_user_args()).filter(func(s: String) -> bool: return not s.begins_with("--"))
	Game.track_id = a[0]
	Game.layout = int(a[1]) if a.size() > 1 else 0
	Game.mode = Game.Mode.TIME_TRIAL
	Game.opponents = 0
	Game.traffic = false
	Game.laps = 1
	Game.intro_flyby = false
	Game.weather = false
	Game.night = false


func _physics_process(dt: float) -> void:
	race = get_tree().current_scene
	if race == null or not "racers" in race or race.path == null or race.state != 2:
		return
	var p: Car = race.player
	var r: Dictionary = race.player_racer()
	r.max_lap = 1000   # never finishes: every route gets driven
	if routes.is_empty():
		_build_routes(p)
		p.was_reset.connect(_on_reset)
		_next_route(p)
		return
	if ri >= routes.size():
		return
	rt += dt
	# Lap counter / progress sanity (a teleport of ours sets them itself).
	var prog: float = r.progress
	if r.lap != last_lap:
		var ev := "lap %d->%d at %.0f/%.0f m %s (node %d)" % [last_lap, r.lap, cum[ci], cum[-1], _v(p.global_position), r.node]
		if routes[ri].teleport:
			issues.append(ev)
		else:
			print("  info ", ev)
		last_lap = r.lap
	elif race.path.closed and absf(prog - last_prog) > 150.0 and absf(prog - last_prog) < race.path.length - 150.0 \
			or not race.path.closed and absf(prog - last_prog) > 150.0:
		notes.append("progress jump %.0f -> %.0f at %s" % [last_prog, prog, _v(p.global_position)])
	last_prog = prog
	last_pos = p.global_position
	last_xf = p.global_transform
	# Where along the route.
	var best := ci
	var bd := INF
	for k in range(ci, mini(ci + 60, pts.size())):
		var d := _seg_dist(p.global_position, k)
		if d < bd:
			bd = d
			best = k
	ci = best
	max_off = maxf(max_off, bd)
	if ci >= pts.size() - 2 or cum[-1] - cum[ci] < 6.0:
		_finish_route(p, "")
		return
	if rt > cum[-1] / 4.0 + 60.0:
		_finish_route(p, "TIMEOUT at %.0f/%.0f m %s" % [cum[ci], cum[-1], _v(p.global_position)])
		return
	if bd > 18.0:
		issues.append("off route %.0f m at %.0f/%.0f m %s" % [bd, cum[ci], cum[-1], _v(p.global_position)])
		_jump(p, ci + 3)
		return
	# Stuck: back off and try again, then put it past.
	if absf(p.speed) < 1.5 and back_t <= 0.0:
		stuck_t += dt
	else:
		stuck_t = maxf(stuck_t - dt * 0.5, 0.0)
	if stuck_t > STUCK_T:
		stuck_t = 0.0
		tries += 1
		if tries <= 3:
			# Back off and go round it: on the other side each try.
			back_t = 1.8
			shift = [3.5, -3.5, 6.0][tries - 1]
			shift_until = cum[ci] + 40.0
		else:
			issues.append("STUCK at %.0f/%.0f m %s" % [cum[ci], cum[-1], _v(p.global_position)])
			tries = 0
			_jump(p, _ahead(ci, 15.0))
			return
	if trace != Vector3.INF and Vector2(p.global_position.x - trace.x, p.global_position.z - trace.y).length() < trace.z:
		trace_t -= dt
		if trace_t <= 0.0:
			trace_t = 0.25
			_trace(p)
	# Steer towards a point ahead on the route.
	var look := clampf(absf(p.speed) * 0.7, 7.0, 28.0)
	var tgt := _at(cum[ci] + look)
	if cum[ci] < shift_until:
		tgt += _dir(ci).cross(Vector3.UP) * shift
	elif tries > 0 and cum[ci] > shift_until + 30.0:
		tries = 0
	var fwd := p.forward_dir()
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var d := tgt - p.global_position
	var ang := atan2(d.dot(right), d.dot(fwd))
	# Speed for the bends ahead.
	if "--respawn" in OS.get_cmdline_user_args() and routes[ri].teleport and not respawned and cum[ci] > cum[-1] * 0.5:
		respawned = true
		var before := p.global_position
		probing = true
		race._respawn(p)
		probing = false
		var moved := before.distance_to(p.global_position)
		var line := "respawn at %.0f/%.0f m %s -> %s: moved %.1f m, on side road %s" % [cum[ci], cum[-1], _v(before), _v(p.global_position), moved, race.path.on_side_road(p.global_position)]
		if moved > 15.0:
			issues.append(line)
		else:
			notes.append(line)
		_jump.call_deferred(p, ci)
		return
	# A U-turn where a one-way ramp meets the road the wrong way round: not the track's fault.
	if absf(ang) > 1.6:
		behind_t += dt
		if behind_t > 2.5:
			behind_t = 0.0
			notes.append("U-turn skipped at %.0f m %s" % [cum[ci], _v(p.global_position)])
			_jump(p, _ahead(ci, 15.0))
			return
	else:
		behind_t = 0.0
	var turn := 0.0
	var h0 := _dir(ci)
	var k := ci
	while k < pts.size() - 1 and cum[k] - cum[ci] < absf(p.speed) * 2.5 + 25.0:
		turn = maxf(turn, absf(h0.angle_to(_dir(k))))
		k += 1
	var vt := clampf(30.0 - 16.0 * turn, 8.0, 30.0)
	if back_t > 0.0:
		back_t -= dt
		p.throttle = 0.0
		p.brake = 1.0
		p.steer = -signf(ang)
		p.handbrake = false
		return
	p.steer = clampf(ang * 2.2, -1.0, 1.0)
	p.throttle = clampf((vt - p.speed) * 0.4, 0.0, 1.0)
	p.brake = clampf((p.speed - vt - 1.0) * 0.3, 0.0, 1.0)
	p.handbrake = false


func _build_routes(p: Car) -> void:
	var path: TrackPath = race.path
	var r: Dictionary = race.player_racer()
	var n0: int = path.closest(p.global_position)
	if only == "" or only == "lap":
		var lap := PackedVector3Array()
		lap.append(p.global_position)
		if path.closed:
			for k in path.size() + 15:
				lap.append(path.points[path.idx(n0 + k)])
		else:
			for k in range(n0, mini(path.ahead(path.finish_node, 1, 20.0), path.size() - 1) + 1):
				lap.append(path.points[k])
		routes.append({"name": "lap", "pts": lap, "teleport": false})
	if only == "lap":
		return
	var t := Nfs5Track.load_file(Game.track_dir(Game.track_id))
	if Game.layout_mirrored():
		t.mirror_world()
	print("side roads: %d" % t.side_roads.size())
	# The road network: the lap's nodes, then every side road's slices; consecutive ones
	# joined, and each side road's ends to the nearest node of every other road in reach.
	var L := path.size()
	var pos := PackedVector3Array(path.points)
	var road_of := PackedInt32Array()
	road_of.resize(L)
	road_of.fill(-1)
	var first := PackedInt32Array()
	for si in t.side_roads.size():
		first.append(pos.size())
		for vr: Nfs3Track.VRoad in t.side_roads[si]:
			pos.append(vr.pos)
			road_of.append(si)
	adj.resize(pos.size())
	for i in pos.size():
		adj[i] = []
	var link := func(i: int, j: int) -> void:
		var w := pos[i].distance_to(pos[j])
		adj[i].append([j, w])
		adj[j].append([i, w])
	for i in L - (0 if path.closed else 1):
		link.call(i, (i + 1) % L)
	for si in t.side_roads.size():
		var n: int = t.side_roads[si].size()
		for k in n - 1:
			link.call(first[si] + k, first[si] + k + 1)
		for e in [first[si], first[si] + n - 1]:
			var best := {}   # road -> [node, dist]
			for j in pos.size():
				if road_of[j] == si:
					continue
				var d := pos[j].distance_to(pos[e])
				if d < JUNCTION and (not best.has(road_of[j]) or d < best[road_of[j]][1]):
					best[road_of[j]] = [j, d]
			for rd in best:
				link.call(e, best[rd][0])
	var seen := {}
	for si in t.side_roads.size():
		if only != "" and only != "side" and only != str(si):
			continue
		var n: int = t.side_roads[si].size()
		var cands := []
		for flip in [false, true]:
			var s0: int = first[si] + (n - 1 if flip else 0)
			var e0: int = first[si] + (0 if flip else n - 1)
			var own := {}
			for k in n:
				own[first[si] + k] = true
			var pre := _to_lap(s0, own, road_of)
			var post := _to_lap(e0, own, road_of)
			if pre.is_empty() and post.is_empty():
				continue
			var nodes := PackedInt32Array()
			if not pre.is_empty():
				pre.reverse()
				nodes.append_array(pre.slice(0, pre.size() - 1))
			for k in n:
				nodes.append(first[si] + (n - 1 - k if flip else k))
			if not post.is_empty():
				nodes.append_array(post.slice(1))
			# Prefer: back onto the lap at both ends, the way the race runs.
			var score := 0.0
			if pre.is_empty():
				score += 1000.0
			if post.is_empty():
				score += 500.0
			if not pre.is_empty() and not post.is_empty():
				var f: float = path.cumulative[nodes[-1]] - path.cumulative[nodes[0]]
				if path.closed:
					f = fposmod(f, path.length)
					score += 100.0 if f > path.length * 0.5 else 0.0
				elif f < 0.0:
					score += 100.0
			for k in range(1, nodes.size() - 1):
				if road_of[nodes[k]] != road_of[nodes[k + 1]] or road_of[nodes[k]] != road_of[nodes[k - 1]]:
					var d0 := pos[nodes[k]] - pos[nodes[maxi(k - 3, 0)]]
					var d1 := pos[nodes[mini(k + 3, nodes.size() - 1)]] - pos[nodes[k]]
					if Vector2(d0.x, d0.z).angle_to(Vector2(d1.x, d1.z)) > 1.8 or Vector2(d0.x, d0.z).angle_to(Vector2(d1.x, d1.z)) < -1.8:
						score += 50.0
			cands.append([score, nodes, not pre.is_empty(), not post.is_empty()])
		if cands.is_empty():
			summary.append("FAIL side %d: no way to it from the lap" % si)
			continue
		cands.sort_custom(func(x, y): return x[0] < y[0])
		var nodes: PackedInt32Array = cands[0][1]
		var sig := []
		for nd in nodes:
			if road_of[nd] >= 0 and (sig.is_empty() or sig[-1] != road_of[nd]):
				sig.append(road_of[nd])
		var key := ">".join(sig.map(func(x): return str(x)))
		if seen.has(key):
			continue
		seen[key] = true
		var route := PackedVector3Array()
		var len := 0.0
		if cands[0][2]:
			var m := path.ahead(nodes[0], -1, RUNUP)
			while m != nodes[0]:
				route.append(path.points[m])
				m = path.idx(m + 1)
		for k in nodes.size():
			route.append(pos[nodes[k]])
			if k > 0:
				len += pos[nodes[k - 1]].distance_to(pos[nodes[k]])
		if cands[0][3]:
			var m := path.idx(nodes[-1] + 1)
			var end := path.ahead(nodes[-1], 1, RUNOUT)
			while m != end:
				route.append(path.points[m])
				m = path.idx(m + 1)
		routes.append({"name": "side %s (%.0f m, %s -> %s)" % [key, len,
			"lap %d" % nodes[0] if cands[0][2] else "DEAD END", "lap %d" % nodes[-1] if cands[0][3] else "DEAD END"],
			"pts": route, "teleport": true})


## Shortest way from node `from` to the lap over the network, not through `avoid`: the
## nodes from `from` to the lap node, or empty.
func _to_lap(from: int, avoid: Dictionary, road_of: PackedInt32Array) -> PackedInt32Array:
	var dist := {from: 0.0}
	var prev := {}
	var heap := [[0.0, from]]
	while not heap.is_empty():
		var best := 0
		for k in heap.size():
			if heap[k][0] < heap[best][0]:
				best = k
		var top: Array = heap[best]
		heap.remove_at(best)
		var u: int = top[1]
		if top[0] > dist[u]:
			continue
		if road_of[u] < 0:
			var out := PackedInt32Array([u])
			while prev.has(out[-1]):
				out.append(prev[out[-1]])
			out.reverse()
			return out
		for e: Array in adj[u]:
			var v: int = e[0]
			if avoid.has(v) and v != from:
				continue
			var d: float = top[0] + e[1]
			if d < dist.get(v, INF):
				dist[v] = d
				prev[v] = u
				heap.append([d, v])
	return PackedInt32Array()


func _next_route(p: Car) -> void:
	ri += 1
	if ri >= routes.size():
		print("==== SUMMARY %s layout %d" % [Game.track_id, Game.layout])
		for s in summary:
			print(s)
		get_tree().quit()
		return
	var rr: Dictionary = routes[ri]
	pts = rr.pts
	cum = PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		cum.append(cum[-1] + pts[k - 1].distance_to(pts[k]))
	ci = 0
	rt = 0.0
	stuck_t = 0.0
	back_t = 0.0
	tries = 0
	shift_until = 0.0
	max_off = 0.0
	issues.clear()
	notes.clear()
	respawned = false
	behind_t = 0.0
	print("---- route %s: %.0f m" % [rr.name, cum[-1]])
	if rr.teleport:
		_jump(p, 0)
		p.linear_velocity = _dir(0) * 12.0
	var r: Dictionary = race.player_racer()
	last_lap = r.lap
	last_prog = r.progress


func _finish_route(p: Car, why: String) -> void:
	if why != "":
		issues.append(why)
	var line := "%s %s: %.0f s, max off route %.1f m%s%s" % ["OK  " if issues.is_empty() else "FAIL", routes[ri].name, rt, max_off,
		"" if issues.is_empty() else "\n | " + "\n | ".join(issues), "" if notes.is_empty() else "\n . " + "\n . ".join(notes)]
	print(line)
	summary.append(line)
	_next_route(p)


## Puts the car on the route at index `k` (facing along it), and the race's idea of where it is with it.
func _jump(p: Car, k: int) -> void:
	k = clampi(k, 0, pts.size() - 2)
	ci = k
	var f := _dir(k)
	mine = true
	p.reset_to(Transform3D(Basis.looking_at(-f, Vector3.UP), pts[k] + Vector3.UP * 0.6), 0.3)
	mine = false
	var path: TrackPath = race.path
	var r: Dictionary = race.player_racer()
	r.node = path.closest(pts[k])
	r.progress = path.progress_at(pts[k], r.node)
	last_prog = r.progress
	last_lap = r.lap
	stuck_t = 0.0


func _on_reset() -> void:
	if mine or probing:
		return
	var path: TrackPath = race.path
	var n: int = path.closest(last_pos, race.player_racer().node)
	var off: float = absf(path.lateral(last_pos, n))
	var wall: float = maxf(path.wall_width(n, -1.0), path.wall_width(n, 1.0))
	var why := []
	if last_pos.y < path.points[n].y - 25.0:
		why.append("fell (%.1f m under node %d)" % [path.points[n].y - last_pos.y, n])
	if off > wall + path.lost_margin:
		why.append("lost (%.0f m off node %d, wall %.0f, side road %s)" % [off, n, wall, path.on_side_road(last_pos)])
	if last_xf.basis.y.y < 0.3:
		why.append("upside down")
	if race._water_depth(race.player) > 0.0 or race._water_t.has(race.player):
		why.append("water")
	if why.is_empty():
		why.append("?? off %.0f" % off)
	issues.append("RACE RESET at %.0f/%.0f m %s: %s" % [cum[ci], cum[-1], _v(last_pos), ", ".join(why)])
	# Back where it was on the route, to carry on.
	_jump.call_deferred(race.player, _ahead(ci, 5.0))


func _trace(p: Car) -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 1.0, 5.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = p.global_transform.translated_local(Vector3.UP * 0.9)
	q.collision_mask = 0xFFFF
	q.exclude = [p.get_rid()]
	var hits := []
	for h in get_viewport().world_3d.direct_space_state.intersect_shape(q, 8):
		hits.append("%s/%s" % [h.collider.name, h.shape])
	print("  trace %.0f m %s v=%.1f thr=%.1f brk=%.1f st=%.2f wheels=%d up=%.2f hits=%s" % [cum[ci], _v(p.global_position),
		p.speed, p.throttle, p.brake, p.steer, p.grounded_wheels, p.global_basis.y.y, hits])


func _ahead(k: int, m: float) -> int:
	var j := k
	while j < pts.size() - 2 and cum[j] - cum[k] < m:
		j += 1
	return j


func _at(s: float) -> Vector3:
	var k := ci
	while k < pts.size() - 2 and cum[k + 1] < s:
		k += 1
	var seg := cum[k + 1] - cum[k]
	return pts[k].lerp(pts[k + 1], clampf((s - cum[k]) / maxf(seg, 0.01), 0.0, 1.0))


func _dir(k: int) -> Vector3:
	k = clampi(k, 0, pts.size() - 2)
	var d := pts[k + 1] - pts[k]
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else Vector3.FORWARD


func _seg_dist(p: Vector3, k: int) -> float:
	var b := pts[mini(k + 1, pts.size() - 1)]
	return Geometry3D.get_closest_point_to_segment(p, pts[k], b).distance_to(p)


func _v(v: Vector3) -> String:
	return "(%.0f, %.0f, %.0f)" % [v.x, v.y, v.z]
