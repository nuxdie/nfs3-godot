extends Node
## `godot --headless --path . -s tools/_tmp/hp2_speech_check.gd -- <out>`: every line the race
## says, resolved with Speech.hp2 on, decoded and saved.
func _ready() -> void:
	if true:
		var out: String = OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else "/tmp"
		var sp := Speech.new()
		sp.hp2 = true
		var asks := [["off00a", range(16, 24)], ["off00b", [26, 32, 36, 38, 40, 44, 50, 51, 53, 54, 55, 57, 60, 61, 62, 63]],
			["off00c", [16, 30, 49]], ["disp00", [36, 37, 41, 44, 52, 58]], ["copspch", [0, 16, 19, 32]],
			["helicop", [0, 34, 69, 96]], ["lapeng", [0, 5, 7, 16, 19, 21, 23, 27, 28]], ["vocasst", [1, 17]]]
		for a in asks:
			for p: int in a[1]:
				var r := sp.resolve(a[0], p)
				var line := "%s %d -> %s" % [a[0], p, r]
				if not r.is_empty() and (r[0] as String).begins_with("hp2:"):
					var w := sp._hp2_dat((r[0] as String).trim_prefix("hp2:")).clip(r[1])
					line += " %.2fs" % (w.get_length() if w else -1.0)
					if w:
						w.save_to_wav(out.path_join("%s_%d.wav" % [a[0], p]))
				print(line)
		sp.free()
		get_tree().quit()
