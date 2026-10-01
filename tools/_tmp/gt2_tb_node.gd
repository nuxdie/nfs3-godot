extends Node

func _ready() -> void:
	await get_tree().create_timer(0.5).timeout
	var menu := get_tree().current_scene
	menu.show_screen("track")
	await get_tree().create_timer(2.0).timeout
	var tb: TrackBrowser = null
	for n in menu.find_children("*", "TrackBrowser", true, false):
		tb = n
	if tb:
		tb.filters.select(3)
		await get_tree().create_timer(2.0).timeout
		get_viewport().get_texture().get_image().save_png("res://shots/tb_gt2_japan.png")
		tb.filters.select(0)
		await get_tree().create_timer(2.0).timeout
		get_viewport().get_texture().get_image().save_png("res://shots/tb_gt2_world.png")
		print("shots done")
	else:
		print("no track browser")
	get_tree().quit()
