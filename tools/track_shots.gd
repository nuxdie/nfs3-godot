extends Node
## Photographs a track from the road at points round the lap, without a race:
##   godot --path . -- --trackshots <track> [lap fraction ...] [--night] [--weather]
##       [--up=M] [--back=M] [--ahead=M] [--side=M] [--tag=NAME]
## Saves shots/track_<tag><fraction>.png. The eye stands --back m behind the node and --up m
## over the road, --side m to the right, and looks at the road --ahead m on.


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Just the track: no menu over it.
	get_tree().current_scene.queue_free()
	var args := Array(OS.get_cmdline_user_args())
	var pos := args.filter(func(a: String) -> bool: return not a.begins_with("--"))
	var opt := {"up": 2.2, "back": 7.0, "ahead": 45.0, "side": 0.0}
	var tag := ""
	for a: String in args:
		for k in opt:
			if a.begins_with("--%s=" % k):
				opt[k] = float(a.get_slice("=", 1))
		if a.begins_with("--tag="):
			tag = a.get_slice("=", 1) + "_"
	var id: String = pos[0] if pos.size() > 0 else "procedural"
	var fracs := []
	for k in range(1, pos.size()):
		fracs.append(float(pos[k]))
	if fracs.is_empty():
		fracs = [0.0, 0.2, 0.4, 0.6, 0.8]
	if id == Game.PROCEDURAL_TRACK:
		var lay := ProceduralTrack.make_layout(1998)
		for k in [ProceduralTrack.Kind.TUNNEL, ProceduralTrack.Kind.BRIDGE]:
			for r in ProceduralTrack._runs(lay.kind, k):
				print("%s at %.3f..%.3f" % ["tunnel" if k == ProceduralTrack.Kind.TUNNEL else "bridge",
					float(r[0]) / lay.n, float(r[0] + r[1]) / lay.n])
	var t0 := Time.get_ticks_msec()
	var w := TrackWorld.load_track(id)
	print("built %s in %d ms: %d nodes, %.0f m" % [id, Time.get_ticks_msec() - t0, w.path.size(), w.path.length])
	add_child(w.root)
	w.light(self, "--night" in args, "--weather" in args, get_viewport())
	var cam := Camera3D.new()
	cam.far = 6000.0
	add_child(cam)
	cam.make_current()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	for f: float in fracs:
		var path := w.path
		var i := int(f * path.size()) % path.size()
		var back: int = int(opt.back / 6.0)
		var ahead: int = int(opt.ahead / 6.0)
		var at: Vector3 = path.points[path.idx(i - back)] + path.rights[i] * opt.side + Vector3.UP * opt.up
		var look: Vector3 = path.points[path.idx(i + ahead)] + Vector3.UP * 1.0
		cam.global_position = at
		cam.look_at(look, Vector3.UP)
		for k in 8:
			await get_tree().process_frame
		var file := "shots/track_%s%03d.png" % [tag, int(round(f * 1000))]
		get_viewport().get_texture().get_image().save_png(file)
		print("shot %s  draw calls %d, %dk triangles, %d objects" % [file,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	get_tree().quit()
