extends SceneTree
## Lists GT2's songs and decodes 20 s of one to a WAV: ./godot --headless --path . -s tools/_tmp/gt2_music_probe.gd

func _init() -> void:
	var img := Gt2Vol.find_image(ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir().path_join("Gran Turismo 2 [SCUS 94455, SCUS 94488]"))
	var vol := Gt2Vol.open(img)
	var t0 := Time.get_ticks_msec()
	var songs := Gt2Music.songs(vol, 0.0)
	print("map ms ", Time.get_ticks_msec() - t0, " ", songs)
	var m := Gt2Music.open(vol, 1)
	var pcm := PackedByteArray()
	t0 = Time.get_ticks_msec()
	var frames := 0
	while frames < 37800 * 20:
		var b := m.next_block()
		if b.is_empty():
			break
		frames += b.size()
		for f in b:
			var o := pcm.size()
			pcm.resize(o + 4)
			pcm.encode_s16(o, int(f.x * 32767))
			pcm.encode_s16(o + 2, int(f.y * 32767))
	print("decoded ", frames / 37800.0, " s in ms ", Time.get_ticks_msec() - t0)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = true
	w.mix_rate = 37800
	w.data = pcm
	w.save_to_wav("/tmp/claude-1000/-home-n-NFSHS-revive-nfs3-godot/f0b80688-5c8f-4d8c-8592-b4bc1de5eb94/scratchpad/gt2_song1.wav")
	quit()
