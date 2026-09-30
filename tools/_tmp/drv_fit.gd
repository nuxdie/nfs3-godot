extends SceneTree
var done := false
func _process(_d: float) -> bool:
	if done: return true
	done = true
	var g = get_root().get_node("/root/Game")
	g.scan_data()
	var cdir := DataPath.find_ci(g.pu_root, "Carmodel")
	var c = load("res://scripts/io/nfs5_car.gd").new()
	for m in OS.get_cmdline_user_args():
		print("MODEL ", m)
		var crp := Crp.load_file(DataPath.find_ci(cdir, m + ".crp"))
		for d in range(1, 11): c._fit_limbs(crp, d)
	quit()
	return true
