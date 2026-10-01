extends Node

func _ready() -> void:
	await _wait(30)
	var menu := get_tree().current_scene
	var d: Dealership = menu._dealer
	menu.show_screen("car")
	await _wait(120)
	d._maker_map.filters.select(2)
	await _wait(90)
	_shot("dl_proc_makers")
	d._open_brand("Generated")
	await _wait(150)
	_shot("dl_proc_maker")
	var e := d.entries.filter(func(x: Dictionary) -> bool: return x.item >= 0)
	if e.size() > 1:
		d.previewed.emit(e[1].item)
	await _wait(200)
	_shot("dl_proc_vortex")
	get_tree().quit()


func _wait(n: int) -> void:
	await get_tree().create_timer(n / 60.0).timeout


func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://shots/%s.png" % n)
	print("shot ", n)
