class_name Hp2PropSounds
## What Hot Pursuit 2's props sound like knocked over. Its level.dat goes on past the props
## (Nfs6Track._add_level): a count and per prop type 20 bytes, the first int its physics record;
## then the physics records, 0x78 bytes each: mass (float) at 0x2C, the material at 0x38
## (0 metal: gas pumps, parking meters; 3 rubber: traffic barrels; 4 wood: signs, chairs,
## tables, bamboo; 5 is two heavy things in Medit), a name at 0x54 ("sign", "gaspump",
## "table", "chair", "tbarrel", "meter", "bamboo"). Audio/Sfx/boomobj.ini gives some of those
## names their crash, a patch of Audio/Sfx/gen.bnk (colpatch, all its layers together, at up
## to colmaxvol); the rest sound by their material (MATERIAL_PATCH: by ear from boomobj's own
## picks: 85 a gas pump's metal, 102 a traffic barrel, 87 a board, 88 a crate).

const MATERIAL_PATCH := {0: 85, 3: 102, 4: 87, 5: 88}
const DEFAULT_PATCH := 87
const DESC_SIZE := 0x78

static var _bank: EaBnk          # its own gen.bnk: this runs on the track loader's thread
static var _bank_root := "-"


## Per prop type of the course in `level_dir` (Tracks/<area>/Level0N), its sounds: [] none.
static func for_level(level_dir: String) -> Array:
	var out := []
	var hp2_root := level_dir.get_base_dir().get_base_dir().get_base_dir()
	var d := FileAccess.get_file_as_bytes(DataPath.find_ci(level_dir, "level.dat"))
	if d.size() < 8:
		return out
	if hp2_root != _bank_root:
		_bank_root = hp2_root
		var gen := DataPath.find_ci(hp2_root, "Audio/Sfx/gen.bnk")
		_bank = EaBnk.parse(FileAccess.get_file_as_bytes(gen)) if gen != "" else null
	if _bank == null:
		return out
	var boom := Nfs5Car._ini(FileAccess.get_file_as_string(DataPath.find_ci(hp2_root, "Audio/Sfx/boomobj.ini")))
	var by_name := {}
	for sec: Dictionary in boom.values():
		if sec.has("name") and int(sec.get("colpatch", "-1")) >= 0:
			by_name[(sec.name as String).to_lower()] = int(sec.colpatch)
	var p := 4 + d.decode_u32(0) * 36
	if p + 4 > d.size():
		return out
	var types := d.decode_u32(p)
	p += 4
	var descs := p + types * 20
	for t in types:
		var a := d.decode_s32(p + t * 20) if p + t * 20 + 4 <= d.size() else -1
		var r := descs + a * DESC_SIZE
		var patch := DEFAULT_PATCH
		if a >= 0 and r + DESC_SIZE <= d.size():
			var name := d.slice(r + 0x54, r + 0x74).get_string_from_ascii().to_lower()
			patch = by_name.get(name, MATERIAL_PATCH.get(d.decode_s32(r + 0x38), DEFAULT_PATCH))
		var sounds: Array[AudioStream] = []
		for l in _bank.layer_count(patch):
			var s := _bank.stream(patch, l)
			if s:
				sounds.append(s)
		out.append(sounds)
	return out
