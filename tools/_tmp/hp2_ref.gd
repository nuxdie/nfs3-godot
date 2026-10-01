extends SceneTree
func _init():
	var HS := "/home/n/NFSHS-revive/need-for-speed-high-stakes/drive_c/Program Files (x86)/Electronic Arts/Need for Speed - High Stakes/Data/Audio/Speech/English/"
	var b := EaBnk.parse(FileAccess.get_file_as_bytes(HS + "lapeng.bnk"))
	b.stream(5).save_to_wav("/tmp/claude-1000/-home-n-NFSHS-revive-nfs3-godot/f3cfe65d-4a75-4154-a6f6-da7389c5a13e/scratchpad/t/ref_finallap.wav")
	quit()
