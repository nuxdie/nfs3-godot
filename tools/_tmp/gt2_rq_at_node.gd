extends Node
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var w := TrackWorld.load_track(args[0], false, 0)
	var t := Gt2Track.load_dir(Game.track_dir(args[0]))
	for k in range(1, args.size()):
		var f := float(args[k])
		var i := int(f * w.path.size()) % w.path.size()
		var p: Vector3 = w.path.points[i]
		var best := -1
		var bd := INF
		for c in t._chunk_at.size():
			var dd := t._centre(c).distance_to(p)
			if dd < bd:
				bd = dd
				best = c
		print("%s f=%.3f p=%s chunk %d mask %x" % [args[0], f, p, best, t._d.decode_u32(t._chunk_at[best] + 0x0C)])
	get_tree().quit()
