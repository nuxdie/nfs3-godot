extends Node
const T := "/home/n/NFSHS-revive/need-for-speed-hot-pursuit-2/drive_c/Program Files (x86)/Electronic Arts/Need for Speed - Hot Pursuit 2/Tracks/"
func _ready() -> void:
	for area in ["Parkland", "Tropics", "Alpine", "Medit"]:
		var ai := Nfs6Track._read_ai(T + area + "/Level00/aipaths.dat")
		var pts: Array[Vector3] = []
		for p in ai:
			var f: PackedFloat32Array = p.pts
			for k in range(0, f.size() / 7, 4):
				pts.append(Vector3(f[k * 7], f[k * 7 + 1], f[k * 7 + 2]))
		var ini := Nfs5Car._ini(FileAccess.get_file_as_string(T + area + "/audiopts.ini"))
		var same := []
		var flip := []
		for k in ini:
			var s: Dictionary = ini[k]
			if not s.has("xpos"): continue
			var v := Vector3(float(s.xpos), float(s.ypos), float(s.zpos))
			var d1 := INF
			var d2 := INF
			for q in pts:
				d1 = minf(d1, v.distance_to(q))
				d2 = minf(d2, Vector3(v.x, v.y, -v.z).distance_to(q))
			same.append(d1); flip.append(d2)
		same.sort(); flip.sort()
		print(area, " n=", same.size(), " median same ", same[same.size() / 2], " flipped ", flip[flip.size() / 2])
		var b := EaBnk.parse(FileAccess.get_file_as_bytes(T + area + "/track.bnk"))
		var ok := 0
		var loops := 0
		for p in b.patch_ids():
			var st := b.stream(p)
			if st: ok += 1
			if st and st.loop_mode != AudioStreamWAV.LOOP_DISABLED: loops += 1
		print("  track.bnk patches ", b.patch_ids().size(), " decoded ", ok, " looped ", loops)
	get_tree().quit()
