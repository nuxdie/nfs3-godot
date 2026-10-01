extends SceneTree
func _initialize() -> void:
	for f in ["res://scripts/race/race.gd", "res://scripts/track/track_path.gd", "res://scripts/io/nfs5_track.gd", "res://scripts/io/nfs3_track.gd", "res://scripts/track/nfs5_track_builder.gd", "res://scripts/track/nfs3_track_builder.gd", "res://scripts/io/crp.gd", "res://scripts/audio/speech.gd"]:
		var s: GDScript = load(f)
		print(f, " -> ", "OK" if s and s.can_instantiate() else "FAILED")
	quit()
