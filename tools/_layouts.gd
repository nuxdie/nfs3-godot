extends Node
func _ready() -> void:
	var out := FileAccess.open("/tmp/claude-1000/-home-n-NFSHS-revive-nfs3-godot/98f68080-592c-4c34-83f8-01cce78d15b5/scratchpad/proc.txt", FileAccess.WRITE)
	var args := Array(OS.get_cmdline_user_args()).filter(func(a: String) -> bool: return a.is_valid_int())
	var raw := "--raw" in OS.get_cmdline_user_args()
	for a: String in args:
		var s := int(a)
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var t0 := Time.get_ticks_msec()
		var plan: ProceduralTrack.Plan = ProceduralTrack._plan(rng) if raw else ProceduralTrack._centreline(rng)
		printerr("seed %d %d ms: %s" % [s, Time.get_ticks_msec() - t0, _why(plan.pts)])
		out.store_line("s%d %d" % [s, plan.pts.size()])
		var n := plan.pts.size()
		var line := plan.pts
		for i in n:
			var p := plan.pts[i]
			var ca := line[(i - 1 + n) % n] - line[(i - 3 + n) % n]
			var cb := line[(i + 3) % n] - line[(i + 1) % n]
			var tight := absf(ca.angle_to(cb)) > 4.0 * 6.0 / ProceduralTrack.MIN_RADIUS
			out.store_line("%f %d %f %d" % [p.x, plan.zone[i], p.y, (4 if tight else 1 if i == plan.tunnel else 2 if i == plan.river else 3 if i == plan.lake else 0)])
	out.close()
	get_tree().quit()

func _why(line: PackedVector2Array) -> String:
	var n := line.size()
	var r := "len %d" % (n * 6)
	var tight := 0
	for i in n:
		var a := line[(i - 1 + n) % n] - line[(i - 3 + n) % n]
		var b := line[(i + 3) % n] - line[(i + 1) % n]
		if absf(a.angle_to(b)) > 4.0 * 6.0 / ProceduralTrack.MIN_RADIUS:
			tight += 1
	var close := 0
	for i in range(0, n, 3):
		for k in range(0, n, 3):
			var gap := absi(k - i)
			if mini(gap, n - gap) > ProceduralTrack.GAP_NODES and line[k].distance_to(line[i]) < ProceduralTrack.MIN_GAP:
				close += 1
	return r + " tight %d close %d" % [tight, close]
