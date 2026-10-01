extends Node

func _ready() -> void:
	await get_tree().create_timer(0.5).timeout
	var g := Game.tracks.filter(func(t): return Game.is_gt2_track(t))
	print("tracks ", Game.tracks.size(), " gt2 ", g.size(), " ", g.slice(0, 5), " image ", Game.gt2_image)
	get_tree().quit()
