extends Node
## Opens the track picker, presses the given keys one by one, a shot after each.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var name: String = args[0] if args.size() > 0 else "t"
	for k in 40:
		await get_tree().process_frame
	var menu := get_tree().current_scene
	menu._go(menu.Screen.TRACK)
	for k in 90:
		await get_tree().process_frame
	_shot("tu_%s_0" % name)
	var n := 1
	for a in args.slice(1):
		if a.begins_with("@") or a.begins_with("!"):
			# Pointer at x,y (the 1280x720 canvas): @ moves there, ! clicks there.
			var xy := a.substr(1).split(",")
			var pos := Vector2(float(xy[0]), float(xy[1]))
			var mv := InputEventMouseMotion.new()
			mv.position = pos
			mv.global_position = pos
			get_viewport().push_input(mv)
			await get_tree().process_frame
			if a.begins_with("!"):
				for pressed in [true, false]:
					var b := InputEventMouseButton.new()
					b.button_index = MOUSE_BUTTON_LEFT
					b.pressed = pressed
					b.position = pos
					b.global_position = pos
					get_viewport().push_input(b)
					await get_tree().process_frame
			for k in 110:
				await get_tree().process_frame
			_shot("tu_%s_%d" % [name, n])
			n += 1
			continue
		for key in a.split("+"):
			var ev := InputEventKey.new()
			ev.pressed = true
			ev.physical_keycode = OS.find_keycode_from_string(key)
			ev.keycode = ev.physical_keycode
			if key.length() == 1:
				ev.unicode = key.to_lower().unicode_at(0)
			Input.parse_input_event(ev)
			await get_tree().process_frame
			var up := ev.duplicate()
			up.pressed = false
			Input.parse_input_event(up)
			await get_tree().process_frame
		for k in 110:
			await get_tree().process_frame
		var m: WorldMap = menu._tracks._map
		print("shot ", n, " center ", m.center, " -> ", m._to_center, " zoom ", m.zoom, " -> ", m._to_zoom, " frame ", m.frame, " fps ", Engine.get_frames_per_second(), " size ", menu._tracks.size, " card ", menu._tracks._card.position, " mapsize ", m.size)
		_shot("tu_%s_%d" % [name, n])
		n += 1
	get_tree().quit()


func _shot(n: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	get_viewport().get_texture().get_image().save_png("res://shots/%s.png" % n)
