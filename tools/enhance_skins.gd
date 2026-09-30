extends Node
## Makes the sharper car skins SkinHD swaps in, with Real-ESRGAN (ncnn-vulkan build):
##   godot --path . -- --enhanceskins [cars|pu|hs|traffic|all] [id ...] [--esrgan=DIR] [--force]
## DIR holds realesrgan-ncnn-vulkan and its models/ (default tools/realesrgan, from
## github.com/xinntao/Real-ESRGAN/releases: realesrgan-ncnn-vulkan-*-ubuntu/windows/macos).
## The set "cars" (default) is the cars you can pick, "pu" / "hs" their Porsche Unleashed /
## High Stakes ones, "all" those and the traffic and cops. Porsche Unleashed cars are done
## with their own driver and with the one you picked (their skins carry the driver).
## Skins already upscaled (and not since changed) are skipped unless --force.


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().current_scene.queue_free()
	var args := Array(OS.get_cmdline_user_args())
	var pos := args.filter(func(a: String) -> bool: return not a.begins_with("--"))
	var set_name: String = pos[0] if pos.size() > 0 else "cars"
	var ids := pos.slice(1)
	var dir := ProjectSettings.globalize_path("res://tools/realesrgan")
	for a: String in args:
		if a.begins_with("--esrgan="):
			dir = a.get_slice("=", 1)
	var force := "--force" in args
	var exe := dir.path_join("realesrgan-ncnn-vulkan" + (".exe" if OS.get_name() == "Windows" else ""))
	if not FileAccess.file_exists(exe):
		printerr("No Real-ESRGAN at %s (--esrgan=DIR)" % exe)
		get_tree().quit(1)
		return
	var picked: Array = Game.cars.map(func(c): return c.path).filter(func(p: String) -> bool: return p != "")
	var paths: Array = []
	match set_name:
		"pu": paths = picked.filter(func(p: String) -> bool: return Game.is_pu_path(p))
		"hs": paths = picked.filter(func(p: String) -> bool: return not Game.is_pu_path(p))
		"traffic": paths = Game.traffic_cars + Game.hs_traffic_cars + Game.pu_traffic_cars
		"all": paths = picked + Game.traffic_cars + Game.hs_traffic_cars + Game.pu_traffic_cars \
				+ Game.cop_cars + Game.hs_cop_cars + Game.pu_cop_cars
		_: paths = picked
	if not ids.is_empty():
		var id_of := {}
		for c in Game.cars:
			id_of[c.path] = c.id
		paths = paths.filter(func(p: String) -> bool: return p.get_file() in ids or id_of.get(p, "") in ids)
	var tmp := OS.get_user_data_dir().path_join("skins_hd_tmp")
	DirAccess.make_dir_recursive_absolute(tmp)
	SkinHD.enabled = false   # the loader's own skins, not their upscales
	var made := 0
	var t0 := Time.get_ticks_msec()
	for p: String in paths:
		var whos := [0]
		if Game.is_pu_path(p) and Game.driver != 0:
			whos.append(Game.driver)
		for who: int in whos:
			var data: Object = Game.load_car(p, 0, who)
			var tex: Texture2D = data.get("texture")
			if tex == null:
				continue
			var cache := SkinHD.key(p, who)
			if SkinHD.find(tex, cache) != null and not force:
				print("%-28s  cached" % p)
				continue
			var t := Time.get_ticks_msec()
			var err := SkinHD.make(tex, cache, exe, dir.path_join("models"), tmp)
			print("%-28s  %s  %.1f s" % [p + ("#%d" % who if who else ""), err if err != "" else "ok", (Time.get_ticks_msec() - t) / 1000.0])
			made += int(err == "")
	print("%d skins upscaled in %.0f s, cache %s" % [made, (Time.get_ticks_msec() - t0) / 1000.0,
			ProjectSettings.globalize_path(SkinHD.DIR)])
	get_tree().quit()
