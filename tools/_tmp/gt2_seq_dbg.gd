extends SceneTree

func _init() -> void:
	var img := Gt2Vol.find_image(ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir().path_join("Gran Turismo 2 [SCUS 94455, SCUS 94488]"))
	var vol := Gt2Vol.open(img)
	print("vol")
	var m := Gt2Seq.new()
	var t0 := Time.get_ticks_msec()
	print("ins ", m._parse_ins(vol.read("sound/gtmseq.ins")), " ", Time.get_ticks_msec() - t0)
	print("seq ", m._parse_seq(vol.read("sound/spu_08.seq")), " ", Time.get_ticks_msec() - t0, " events ", m._events.size(), " end ", m._end_frame)
	t0 = Time.get_ticks_msec()
	var s: Array = m._sample(m._programs[2][0])
	print("sample ", (s[0] as PackedFloat32Array).size(), " loop ", s[1], " ms ", Time.get_ticks_msec() - t0)
	m._end_frame = 22050 * 12
	m._render()
	quit()
