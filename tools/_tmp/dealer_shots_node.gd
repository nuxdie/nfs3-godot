extends Node
## The dealership in its states: shots/dl_*.png.

func _ready() -> void:
	var series: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "hs"
	Game.career_path = "user://career_autotest.cfg"
	Game._career_loaded = false
	Game.career_data()
	Game.set_career_series(series)
	await _wait(30)
	var menu := get_tree().current_scene
	var d: Dealership = menu._dealer
	menu.show_screen("car")
	await _wait(90)
	_shot("dl_race_brand")
	d._up()
	await _wait(60)
	_shot("dl_race_makers")
	d._open_brand("Porsche")
	await _wait(60)
	_shot("dl_race_porsche")
	d._open_brand("Ferrari")
	await _wait(60)
	_shot("dl_race_ferrari")
	d._set_query("corv")
	await _wait(40)
	_shot("dl_race_search")
	d._set_query("")
	menu._back()
	await _wait(20)
	menu.show_screen("garage")
	await _wait(90)
	_shot("dl_%s_garage" % series)
	d._up()
	await _wait(40)
	_shot("dl_%s_makers" % series)
	d._move_vertical(1)
	d._confirm()
	await _wait(60)
	_shot("dl_%s_maker" % series)
	menu.show_screen("circuit")
	await _wait(90)
	_shot("dl_%s_entry" % series)
	get_tree().quit()


func _wait(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://shots/%s.png" % n)
	print("shot ", n)
