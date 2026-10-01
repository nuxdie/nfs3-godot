class_name Hp2Ambience
extends Node3D
## Hot Pursuit 2's sounds by the road: Tracks/<area>/audiopts.ini places them, [soundpointN]
## each, in the physics' space (Z the other way round from the meshes): Xpos/Ypos/Zpos, the
## patch of the area's track.bnk (SFXnum, -1 none), heard within `dist` m at up to `maxvol`
## (0..127), looping (oneshot=0: wind in the trees, waves, a waterfall, the town) or now and
## then (oneshot=1: a bird, a dog, church bells). dbgcomments names it. SFXrand, density,
## playcode and lapnum are left unread (the one-shots here come every few seconds at random).
## audio.ini's [trackvol] volume scales them all.

const ONESHOT_GAP := Vector2(4.0, 14.0)   # s between a one-shot's plays, at random

var _bank: EaBnk
var _oneshots: Array[Dictionary] = []   # {player, wait}


## The area's ambience for the course in `level_dir` (Tracks/<area>/Level0N), or null.
static func make(level_dir: String, mirrored := false) -> Hp2Ambience:
	var area := level_dir.get_base_dir()
	var bank := EaBnk.parse(FileAccess.get_file_as_bytes(DataPath.find_ci(area, "track.bnk")))
	var points := Nfs5Car._ini(FileAccess.get_file_as_string(DataPath.find_ci(area, "audiopts.ini")))
	if bank == null or points.is_empty():
		return null
	var vol: Dictionary = Nfs5Car._ini(FileAccess.get_file_as_string(DataPath.find_ci(area, "audio.ini"))).get("trackvol", {})
	var a := Hp2Ambience.new()
	a.name = "Hp2Ambience"
	a._bank = bank
	var track_gain := clampf(float(vol.get("volume", "100")) / 100.0, 0.0, 1.0)
	for k: String in points:
		var p: Dictionary = points[k]
		var patch := int(p.get("sfxnum", "-1"))
		if not k.begins_with("soundpoint") or patch < 0 or bank.stream(patch) == null:
			continue
		var pos := Vector3(float(p.get("xpos", "0")), float(p.get("ypos", "0")), -float(p.get("zpos", "0")))
		if mirrored:
			pos.x = -pos.x
		var dist := maxf(float(p.get("dist", "100")), 10.0)
		var gain := clampf(float(p.get("maxvol", "127")) / 127.0, 0.0, 1.0) * bank.volume(patch) * track_gain
		if gain <= 0.01:
			continue
		var pl := AudioStreamPlayer3D.new()
		pl.stream = bank.stream(patch)
		pl.position = pos
		pl.max_distance = dist
		pl.unit_size = dist * 0.25
		pl.volume_db = linear_to_db(gain)
		pl.bus = Game.BUS_SFX
		pl.set_meta("comment", p.get("dbgcomments", ""))
		a.add_child(pl)
		if p.get("oneshot", "0") == "1" or bank.stream(patch).loop_mode == AudioStreamWAV.LOOP_DISABLED:
			a._oneshots.append({"player": pl, "wait": randf_range(0.0, ONESHOT_GAP.y)})
		else:
			pl.autoplay = true
	return a


func _process(dt: float) -> void:
	for o in _oneshots:
		o.wait -= dt
		if o.wait <= 0.0:
			o.wait = randf_range(ONESHOT_GAP.x, ONESHOT_GAP.y)
			var pl: AudioStreamPlayer3D = o.player
			if not pl.playing:
				pl.play()
