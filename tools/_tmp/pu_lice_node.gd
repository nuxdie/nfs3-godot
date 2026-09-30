extends Node
func _ready() -> void:
	for e in [false, true]:
		Plates.texture("4ABC123" if not e else "AB51CDE", e).get_image().save_png("/tmp/claude-1000/-home-n-NFSHS-revive-nfs3-godot/9e47c93c-88b2-4a2f-9e30-f86fba48e7ee/scratchpad/hs_let_%s.png" % ("euro" if e else "us"))
	var root := "/home/n/Games/need-for-speed-porsche-unleashed/drive_c/Program Files (x86)/Electronic Arts/Need for Speed - Porsche Unleashed/GameData"
	for m in ["993_sf2", "356a_sf2"]:
		var img := Image.load_from_file("/tmp/claude-1000/-home-n-NFSHS-revive-nfs3-godot/9e47c93c-88b2-4a2f-9e30-f86fba48e7ee/scratchpad/lice/%s.png" % m)
		img.convert(Image.FORMAT_RGBA8)
		Plates.letter_pu(img, Rect2i(Vector2i.ZERO, img.get_size()), "ABC 123", root)
		img.save_png("/tmp/claude-1000/-home-n-NFSHS-revive-nfs3-godot/9e47c93c-88b2-4a2f-9e30-f86fba48e7ee/scratchpad/let_%s.png" % m)
	get_tree().quit()
