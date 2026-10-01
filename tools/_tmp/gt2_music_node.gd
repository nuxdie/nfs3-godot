extends Node
## Plays GT2's songs in the real menu and shoots the music browser: shots/mu_gt2*.png.

func _ready() -> void:
	await _wait(30)
	var menu := get_tree().current_scene
	menu.show_screen("music")
	var gt2: Array[String] = []
	gt2.assign((MusicPlayer.RACE_SONGS + MusicPlayer.MENU_SONGS).filter(func(s: String) -> bool: return s.begins_with("gt2:")))
	print("available ", gt2.filter(func(s: String) -> bool: return Game.music.available(s)))
	Game.music.play_list(gt2, "gt2:spu_08")
	await _wait(300)
	print("song ", Game.music.current_song(), " pos ", Game.music.position_s(), " len ", Game.music.length_s())
	_shot("mu_gt2")
	Game.music.skip(1)
	await _wait(180)
	print("song ", Game.music.current_song(), " pos ", Game.music.position_s())
	get_tree().quit()


func _wait(n: int) -> void:
	await get_tree().create_timer(n / 60.0).timeout


func _shot(n: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://shots/%s.png" % n)
	print("shot ", n)
