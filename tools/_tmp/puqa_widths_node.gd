extends Node
## `-- <track> from to step`: per node, the lanes' edges and the walls each side.
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var w := TrackWorld.load_track(a[0])
	var p := w.path
	var s := []
	for i in range(int(a[1]), int(a[2]), int(a[3])):
		s.append("%d: L %.0f/%.1f R %.0f/%.1f" % [i, p.lane_count(i, -1) * p.lane_width_left[i], p.left_width[i],
			p.lane_count(i, 1) * p.lane_width_right[i], p.right_width[i]])
	print("  ".join(s))
	get_tree().quit()
