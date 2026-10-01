extends SceneTree
## ./godot --headless --path . -s tools/_tmp/traffic_probe.gd

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var G = root.get_node("Game")
	if G.tracks.is_empty() and G.hp2_traffic_cars.is_empty():
		G.scan_data()
	print("data ", G.data_root, " hs ", G.hs_root, " pu ", G.pu_root, " hp2 ", G.hp2_root)
	print("nfs3 traffic ", G.traffic_cars.size(), " hs ", G.hs_traffic_cars.size(), " pu ", G.pu_traffic_cars.size(), " hp2 ", G.hp2_traffic_cars.size())
	for t in ["hp2_medit1", "trk000", G.track_id]:
		G.track_id = t
		var m: Array = G.traffic_models()
		print("track ", t, " -> ", m.size(), " models")
		for p in m:
			var d = G.load_car(p, 4)
			print("   ", p.get_file() if not p.contains(":") else p, "  ", d.get_class(), " ", d.get_script().get_global_name(), " ", d.display_name)
	quit()
