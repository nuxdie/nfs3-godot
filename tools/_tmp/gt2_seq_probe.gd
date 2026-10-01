extends SceneTree
## Renders GT2's sequenced songs to WAVs: ./godot --headless --path . -s tools/_tmp/gt2_seq_probe.gd -- [names]

func _init() -> void:
	var img := Gt2Vol.find_image(ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir().path_join("Gran Turismo 2 [SCUS 94455, SCUS 94488]"))
	var vol := Gt2Vol.open(img)
	var names := OS.get_cmdline_user_args()
	if names.is_empty():
		names = PackedStringArray(["spu_08"])
	for n in names:
		var t0 := Time.get_ticks_msec()
		var m := Gt2Seq.open(vol, n)
		if m == null:
			print(n, " failed")
			continue
		WorkerThreadPool.wait_for_task_completion(m._task)
		print(n, " rendered ", m._out.size() / 22050.0, " s (loop at ", m._loop_frame / 22050.0, ") tail ", m._tail.size() / 22050.0, " in ms ", Time.get_ticks_msec() - t0)
		var pcm := PackedByteArray()
		pcm.resize(m._out.size() * 4)
		var peak := 0.0
		for i in m._out.size():
			var f: Vector2 = m._out[i]
			peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
			pcm.encode_s16(i * 4, clampi(int(f.x * 32767), -32768, 32767))
			pcm.encode_s16(i * 4 + 2, clampi(int(f.y * 32767), -32768, 32767))
		print("   peak ", peak)
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.stereo = true
		w.mix_rate = 22050
		w.data = pcm
		w.save_to_wav("/tmp/claude-1000/-home-n-NFSHS-revive-nfs3-godot/f0b80688-5c8f-4d8c-8592-b4bc1de5eb94/scratchpad/seq_%s.wav" % n)
	quit()
