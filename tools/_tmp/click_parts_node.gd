extends Node
## Scans the menu showroom's view for clickable car parts, clicks one of each, screenshots.
## Args after --: car id substring.

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
	await get_tree().create_timer(1.5).timeout
	for shot in ["hero", "tail"]:
		sr._cut_to(shot)
		sr._manual_t = 100.0
		await get_tree().create_timer(0.5).timeout
		var found := {}
		var t0 := Time.get_ticks_usec()
		var n := 0
		for y in range(0, int(sr.size.y), 12):
			for x in range(0, int(sr.size.x), 12):
				var p := sr._part_at(Vector2(x, y))
				n += 1
				if not p.is_empty():
					var k := "%s:%s" % p
					if not found.has(k):
						found[k] = []
					found[k].append(Vector2(x, y))
		print(shot, " picks ", n, " avg us ", (Time.get_ticks_usec() - t0) / n)
		for k in found:
			var pts: Array = found[k]
			var c := Vector2.ZERO
			for q in pts:
				c += q
			print("  ", k, " n=", pts.size(), " centre=", c / pts.size())
		_snap("cp_%s_0" % shot)
		for k in found:
			var pts: Array = found[k]
			sr._click(pts[pts.size() / 2])
		await get_tree().create_timer(2.5).timeout
		_snap("cp_%s_1" % shot)
		sr._settle(true)
	get_tree().quit()


func _snap(n: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://shots/%s.png" % n)
	print("shot ", n)
