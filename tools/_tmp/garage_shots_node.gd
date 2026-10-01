extends Node
## The garage on your (damaged) car, then a paint tried on it: shots/gs_<series>_*.png.

func _ready() -> void:
	var series: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "hs"
	Game.career_path = "user://career_autotest.cfg"
	Game._career_loaded = false
	Game.career_data()
	Game.set_career_series(series)
	for k in 30:
		await get_tree().process_frame
	var menu := get_tree().current_scene
	menu.show_screen("garage")
	var mine: Array = Game.garage_cars()
	menu._dealer.open(mine[0])
	for k in 150:
		await get_tree().process_frame
	_shot("gs_%s_own" % series)
	menu._set_paint(mine[0], 2)
	for k in 20:
		await get_tree().process_frame
	_shot("gs_%s_try" % series)
	get_tree().quit()


func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://shots/%s.png" % n)
