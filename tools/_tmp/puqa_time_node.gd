extends Node
func _ready() -> void:
	for id in OS.get_cmdline_user_args():
		var t0 := Time.get_ticks_msec()
		var t := Nfs5Track.load_file(Game.track_dir(id))
		var t1 := Time.get_ticks_msec()
		t._fit_vroad()
		print("%s load %d ms, of which the fit ~%d ms" % [id, t1 - t0, Time.get_ticks_msec() - t1])
	get_tree().quit()
