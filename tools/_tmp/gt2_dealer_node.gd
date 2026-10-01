extends Node
## The dealership on GT2's makers: shots/dl_gt2_*.png.

func _ready() -> void:
	Game.career_path = "user://career_autotest.cfg"
	Game._career_loaded = false
	Game.career_data()
	Game.set_career_series("hs")
	await _wait(30)
	var menu := get_tree().current_scene
	var d: Dealership = menu._dealer
	menu.show_screen("car")
	await _wait(120)
	_shot("dl_gt2_makers")
	d._maker_map.filters.select(3)
	await _wait(90)
	_shot("dl_gt2_japan")
	d._maker_map.filters.select(1)
	await _wait(90)
	_shot("dl_gt2_europe")
	d._open_brand("Mazda")
	await _wait(60)
	_shot("dl_gt2_mazda")
	get_tree().quit()


func _wait(n: int) -> void:
	await get_tree().create_timer(n / 60.0).timeout


func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://shots/%s.png" % n)
	print("shot ", n)
