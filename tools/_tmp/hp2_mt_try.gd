extends SceneTree
const SP := "/home/n/NFSHS-revive/need-for-speed-hot-pursuit-2/drive_c/Program Files (x86)/Electronic Arts/Need for Speed - Hot Pursuit 2/Audio/Speech/English/"
func stats(name: String, d: PackedByteArray):
	var clip := 0
	var sum := 0.0
	for i in d.size() / 2:
		var x := absi(d.decode_s16(i * 2))
		if x >= 32767: clip += 1
		sum += x * x
	print(name, " n ", d.size() / 2, " rms ", int(sqrt(sum / max(d.size() / 2, 1))), " clipped ", clip)
func _init():
	EaMicroTalk.dbg_mode = 3
	var d := Viv.load_file(SP + "frontend.viv").get_file("busted.dat")
	# blocks of clip 0
	var p := 0
	var blocks := []
	var total := 0
	while p < d.size():
		var id := d.slice(p, p + 4).get_string_from_ascii()
		var size := d.decode_u32(p + 4)
		if id == "SCDl":
			blocks.append([p, size]); total += d.decode_u32(p + 8)
		if id == "SCEl": break
		p += size
	print("blocks ", blocks.size(), " total ", total, " first ", blocks.slice(0, 3))
	var bl := []
	for b in blocks:
		bl.append([b[0] + 16, d.decode_u32(b[0] + 8)])
	var r := EaMicroTalk.decode_blocks(d, bl)
	stats("blocks", r)
	var w3 := AudioStreamWAV.new(); w3.format = AudioStreamWAV.FORMAT_16_BITS; w3.mix_rate = 24000; w3.data = r; w3.save_to_wav("/tmp/claude-1000/-home-n-NFSHS-revive-nfs3-godot/f3cfe65d-4a75-4154-a6f6-da7389c5a13e/scratchpad/t/blocks.wav")
	for skip in []:
		var cat := PackedByteArray()
		var per := PackedByteArray()
		for b in blocks:
			cat.append_array(d.slice(b[0] + skip, b[0] + b[1]))
			per.append_array(EaMicroTalk.decode(d.slice(b[0] + skip, b[0] + b[1]), 0, d.decode_u32(b[0] + 8)))
		var c := EaMicroTalk.decode(cat, 0, total)
		var w2 := AudioStreamWAV.new(); w2.format = AudioStreamWAV.FORMAT_16_BITS; w2.mix_rate = 24000; w2.data = per; w2.save_to_wav("/tmp/claude-1000/-home-n-NFSHS-revive-nfs3-godot/f3cfe65d-4a75-4154-a6f6-da7389c5a13e/scratchpad/try_per%d.wav" % skip)
		stats("concat+%d" % skip, c)
		stats("perblock+%d" % skip, per)
		var w := AudioStreamWAV.new(); w.format = AudioStreamWAV.FORMAT_16_BITS; w.mix_rate = 24000; w.data = c
		w.save_to_wav("/tmp/claude-1000/-home-n-NFSHS-revive-nfs3-godot/f3cfe65d-4a75-4154-a6f6-da7389c5a13e/scratchpad/try_cat%d.wav" % skip)
	# NFS3 reference: a speech bank clip
	print(EaMicroTalk.dbg_flags)
	quit()
