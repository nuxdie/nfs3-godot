extends SceneTree
## Throwaway (hp2-drivers): the HP2 driver posed per clip, frames across, clips down.
const ROOT := "/home/n/Games/need-for-speed-hot-pursuit-2/drive_c/Program Files (x86)/Electronic Arts/Need for Speed - Hot Pursuit 2"

func _init() -> void:
	var who := "Driver"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--who="): who = a.trim_prefix("--who=")
	var d := Nfs6Driver.get_actor(ROOT, who)
	if d == null:
		print("no actor"); quit(); return
	print("bones ", d.names.size(), " verts ", d.pos.size(), " tris ", d.indices.size() / 3, " clips ", d.clips.keys())
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = d.texture
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var world := Node3D.new()
	root.add_child(world)
	var names: Array = d.clips.keys()
	names.sort()
	for ci in names.size():
		var c: Dictionary = d.clips[names[ci]]
		var n: int = c.frames
		for k in 5:
			var f := int(round(k * (n - 1) / 4.0))
			var fr := d.pose(c.rot[f], c.pos)
			var sk := d.skin(fr)
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in d.indices:
				st.set_normal(sk[1][i]); st.set_uv(d.uv[i]); st.add_vertex(sk[0][i])
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = mat
			# seen from the passenger side (+X in HP2 space), a bit from the front
			mi.position = Vector3(0, -ci * 1.3, k * 1.1)
			world.add_child(mi)
			var lbl := Label3D.new()
			lbl.text = "%s f%d" % [names[ci], f]
			lbl.position = mi.position + Vector3(0, 0.45, -0.3)
			lbl.font_size = 24
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			world.add_child(lbl)
	var cam := Camera3D.new()
	cam.position = Vector3(9, -names.size() * 0.65 + 0.6, 2.2)
	cam.look_at_from_position(cam.position, Vector3(0, -names.size() * 0.65 + 0.6, 2.2))
	cam.fov = 45
	world.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 60, 0)
	world.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.4, 0.45)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.add_child(env)
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("screenshots/hp2_driver_%s.png" % who)
	print("saved")
	quit()
