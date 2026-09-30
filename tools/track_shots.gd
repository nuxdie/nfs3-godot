extends Node
## Photographs a track from the road at points round the lap, without a race:
##   godot --path . -- --trackshots <track> [lap fraction ...] [--night] [--weather]
##       [--up=M] [--back=M] [--ahead=M] [--side=M] [--lookside=M] [--tag=NAME] [--hazards]
##       [--clearmap=FROM-TO] [--eye=X,Y,Z --at=X,Y,Z [--every=S]]
## Saves shots/track_<tag><fraction>.png. The eye stands --back m behind the node and --up m
## over the road, --side m to the right, and looks at the road --ahead m on (--lookside m to
## the right of it). --clearmap prints where the AI's obstacle scan finds room for a car on
## virtual road nodes FROM to TO.


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Just the track: no menu over it.
	get_tree().current_scene.queue_free()
	var args := Array(OS.get_cmdline_user_args())
	var pos := args.filter(func(a: String) -> bool: return not a.begins_with("--"))
	var opt := {"up": 2.2, "back": 7.0, "ahead": 45.0, "side": 0.0, "lookside": 0.0}
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
		var lay := ProceduralTrack.make_layout(ProceduralTrack.SEED)
		for k in [ProceduralTrack.Kind.TUNNEL, ProceduralTrack.Kind.BRIDGE]:
			for r in ProceduralTrack._runs(lay.kind, k):
				print("%s at %.3f..%.3f" % ["tunnel" if k == ProceduralTrack.Kind.TUNNEL else "bridge",
					float(r[0]) / lay.n, float(r[0] + r[1]) / lay.n])
		for b in lay.branches:
			print("%s at %.4f%s, %s" % [b.kind, float(b.from) / lay.n,
				"..%.4f" % (float(b.to) / lay.n) if b.to >= 0 else "", "right" if b.side > 0.0 else "left"])
	var t0 := Time.get_ticks_msec()
	var layout := 0
	for a: String in args:
		if a.begins_with("--layout="):
			layout = int(a.get_slice("=", 1))
	var w := TrackWorld.load_track(id, "--night" in args, layout)
	print("built %s in %d ms: %d nodes, %.0f m" % [id, Time.get_ticks_msec() - t0, w.path.size(), w.path.length])
	add_child(w.root)
	if "--hazards" in args and id == Game.PROCEDURAL_TRACK:
		_hazards(w.root)
	for a: String in args:
		if a.begins_with("--clearmap="):
			for k in 2:
				await get_tree().physics_frame
			w.path.scan_obstacles(get_viewport().world_3d.direct_space_state)
			var r := a.get_slice("=", 1)
			_clear_map(w.path, int(r.get_slice("-", 0)), int(r.get_slice("-", 1)))
	w.light(self, "--night" in args, "--weather" in args, get_viewport())
	var cam := Camera3D.new()
	cam.far = 6000.0
	add_child(cam)
	cam.make_current()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	# --eye=X,Y,Z --at=X,Y,Z: from a fixed point instead, a shot every --every=S seconds
	# (animated objects move on), one per lap fraction given.
	var eye: Variant = _vec_arg(args, "--eye=")
	if eye != null:
		cam.global_position = eye
		cam.look_at(_vec_arg(args, "--at="), Vector3.UP)
		var every := 0.5
		for a: String in args:
			if a.begins_with("--every="):
				every = float(a.get_slice("=", 1))
		for k in 8:
			await get_tree().process_frame
		for s in fracs.size():
			if s > 0:
				await get_tree().create_timer(every).timeout
			var file := "shots/track_%seye%d.png" % [tag, s]
			get_viewport().get_texture().get_image().save_png(file)
			print("shot ", file)
		get_tree().quit()
		return
	for f: float in fracs:
		var path := w.path
		var i := int(f * path.size()) % path.size()
		var back: int = int(opt.back / 6.0)
		var ahead: int = int(opt.ahead / 6.0)
		var at: Vector3 = path.points[path.idx(i - back)] + path.rights[i] * opt.side + Vector3.UP * opt.up
		var look: Vector3 = path.points[path.idx(i + ahead)] + path.rights[path.idx(i + ahead)] * opt.lookside + Vector3.UP * 1.0
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


## The Vector3 of a "--name=X,Y,Z" argument, or null.
func _vec_arg(args: Array, prefix: String) -> Variant:
	for a: String in args:
		if a.begins_with(prefix):
			var v := a.trim_prefix(prefix).split_floats(",")
			return Vector3(v[0], v[1], v[2])
	return null


## Prints what scan_obstacles found on nodes `from`..`to`: a column per metre across the road
## (left to right, within the walls), "#" where a car doesn't fit, "." where it does.
func _clear_map(path: TrackPath, from: int, to: int) -> void:
	for i in range(from, to + 1):
		i = path.idx(i)
		var s := ""
		for k in 2 * TrackPath.SPAN + 1:
			var off := k - TrackPath.SPAN
			if off < -path.left_width[i] or off > path.right_width[i]:
				s += " "
			else:
				s += "." if not path.obstructed[i] or (path.clear_bits[i] >> k) & 1 else "#"
		print("clear %4d L%5.1f R%5.1f |%s|" % [i, path.left_width[i], path.right_width[i], s])


## Lists the procedural track's solid scenery standing inside the walls the AI drives between
## (what a racer on its line could hit).
func _hazards(root: Node3D) -> void:
	var lay := ProceduralTrack.make_layout(ProceduralTrack.SEED)
	var body: StaticBody3D = root.get_node("Scenery")
	var count := 0
	for o in body.get_shape_owners():
		var p := body.shape_owner_get_transform(o).origin
		var i := lay.closest(p.x, p.z)
		if i < 0 or lay.kind[i] != ProceduralTrack.Kind.OPEN:
			continue
		var lat := (Vector3(p.x, 0, p.z) - Vector3(lay.pts[i].x, 0, lay.pts[i].z)).dot(lay.flat_right[i])
		var wall := lay.wall_r[i] if lat > 0.0 else lay.wall_l[i]
		var shape := body.shape_owner_get_shape(o, 0)
		var r := 0.0
		if shape is BoxShape3D:
			r = maxf(shape.size.x, shape.size.z) * 0.5
		elif shape is CylinderShape3D or shape is SphereShape3D:
			r = shape.radius
		if absf(lat) - r < wall:
			count += 1
			print("hazard at node %d (%.3f): %s %.1f m out (r %.1f), wall %.1f" % [i, float(i) / lay.n,
				shape.get_class(), lat, r, wall])
	print("%d hazards" % count)
