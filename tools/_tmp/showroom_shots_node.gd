extends Node
## Screenshots of the menu showroom's shots, then the start's rev and the loading screen.
## Args after --: car id substring (optional), "night", "rain".

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	await get_tree().create_timer(1.5).timeout
	var menu := get_tree().current_scene
	var sr: Showroom = menu._showroom
	var want := args[0] if args.size() > 0 else ""
	if want != "":
		for i in Game.cars.size():
			if str(Game.cars[i].id).to_lower().contains(want):
				menu._car_i = i
				menu._show_car_now(i)
				print("car ", Game.cars[i].id)
				break
	sr.set_conditions("night" in args, "rain" in args)
	await get_tree().create_timer(1.5).timeout
	print("parts: lamps=%s spoiler=%s top=%s signals=%s wipers=%s" % [sr._can_show("headlamp"), sr._can_show("spoiler"),
		sr._can_show("top"), sr._can_show("hazards"), sr._can_show("wipers")])
	for name in Showroom.ROUND:
		if not sr._can_show(name):
			continue
		sr._cut_to(name)
		await get_tree().create_timer(minf(Showroom.SHOTS[name].len * 0.6, 3.0)).timeout
		_snap("sr_" + name)
		if name == "driver":
			print("head ", sr._head, " side ", sr._side, " cam ", sr._cam.global_position, " head on screen ", sr._cam.unproject_position(sr.car.global_transform * sr._head))
	menu._starting = true
	menu._launch()   # (not _start(): that saves the settings)
	for k in 4:
		await get_tree().create_timer(0.45).timeout
		_snap("sr_rev%d" % k)
	await get_tree().create_timer(1.5).timeout
	_snap("sr_load0")
	await get_tree().create_timer(3.0).timeout
	_snap("sr_load1")
	get_tree().quit()


func _snap(n: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/%s.png" % n)
	print("shot ", n)
