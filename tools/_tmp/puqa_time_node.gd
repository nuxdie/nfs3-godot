extends Node
func _ready() -> void:
	for id in OS.get_cmdline_user_args():
		var t0 := Time.get_ticks_msec()
		var t := Nfs5Track.load_file(Game.track_dir(id))
		var t1 := Time.get_ticks_msec()
		var g := t._level_grid()
		var t2 := Time.get_ticks_msec()
		t._fit_vroad(g)
		var t3 := Time.get_ticks_msec()
		t._open_walls(g)
		print("%s load %d ms: grid %d, fit %d, walls %d" % [id, t1 - t0, t2 - t1, t3 - t2, Time.get_ticks_msec() - t3])
	get_tree().quit()
