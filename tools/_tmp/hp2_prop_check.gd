extends Node
## Each HP2 course's prop types -> knock sound patch (Hp2PropSounds), and how many props.
const T := "/home/n/NFSHS-revive/need-for-speed-hot-pursuit-2/drive_c/Program Files (x86)/Electronic Arts/Need for Speed - Hot Pursuit 2/Tracks/"
func _ready() -> void:
	for area in ["Parkland", "Tropics", "Alpine", "Medit"]:
		var s := Hp2PropSounds.for_level(T + area + "/Level00")
		var line: String = area + ":"
		for i in s.size():
			line += " %d:%d" % [i, s[i].size()]
		print(line)
	get_tree().quit()
