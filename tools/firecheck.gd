extends SceneTree
## Temporary: photograph an animated-texture spot on a track at two moments.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game = root.get_node("Game")
	var id: String = OS.get_cmdline_user_args()[0]
	var tex_id := int(OS.get_cmdline_user_args()[1])
	var t := Nfs3Track.load_dir(game.track_dir(id))
	print("error: ", t.error)
	var world := Node3D.new()
	root.add_child(world)
	Nfs3TrackBuilder.build(t, world)
	var spot := Vector3.INF
	var n := 0
	for b in t.blocks:
		for obj in b.objects:
			for p in obj:
				if p.anim_frames > 0:
					n += 1
				if p.tex == tex_id and spot == Vector3.INF:
					spot = b.verts[p.v[0]]
					print("anim ", p.anim_frames, " period ", p.anim_period)
	print("animated polys: ", n, " spot ", spot)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = spot + Vector3(8, 4, 8)
	cam.look_at(spot)
	for k in 3:
		for f in 12:
			await process_frame
		root.get_texture().get_image().save_png("/tmp/claude-1000/-home-n-NFSHS-revive-nfs3-godot/d9bd3b54-34d0-45c1-97a2-64f2a2f27d40/scratchpad/fire_%s_%d.png" % [id, k])
	quit()
