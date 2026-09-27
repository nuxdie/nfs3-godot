extends Node
## Global state: where the NFS3 data lives, what the player picked in the menu,
## input bindings and a small cache of loaded cars.

enum Mode { SINGLE_RACE, HOT_PURSUIT, TIME_TRIAL, FREE_ROAM }
const MODE_NAMES := ["Single Race", "Hot Pursuit", "Time Trial", "Free Roam"]

## Friendly names for the stock NFS3 track folders.
const TRACK_NAMES := {
	"trk000": "Hometown", "trk001": "Redrock Ridge", "trk002": "Atlantica",
	"trk003": "Rocky Pass", "trk004": "Country Woods", "trk005": "Lost Canyons",
	"trk006": "Aquatica", "trk007": "The Summit", "trk008": "Empire City",
}
const PROCEDURAL_TRACK := "procedural"
const SETTINGS_PATH := "user://settings.cfg"

var data_root := ""          # folder containing gamedata/
var tracks: Array[String] = []   # track ids (folder names), plus PROCEDURAL_TRACK
var cars: Array[Dictionary] = [] # {id, name, path}
var cop_cars: Array[String] = []
var traffic_cars: Array[String] = []

var mode := Mode.SINGLE_RACE
var track_id := PROCEDURAL_TRACK
var car_index := 0
var laps := 2
var opponents := 3
var traffic := true
var units_kmh := true
var last_results: Array = []

var _car_cache := {}


func _ready() -> void:
	_setup_input()
	_load_settings()
	scan_data()
	# Developer hook: `godot --path . -- --autotest [track] [mode]` plays a scripted run.
	if "--autotest" in OS.get_cmdline_user_args():
		var t: Node = load("res://tools/autotest.gd").new()
		add_child(t)


# ------------------------------------------------------------------ data files

func candidate_roots() -> PackedStringArray:
	var res := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var home := OS.get_environment("HOME")
	return PackedStringArray([
		OS.get_environment("NFS3_DATA"),
		res.get_base_dir().path_join("OpenNFS/resources/NFS_3"),
		res.path_join("nfs3_data"),
		home.path_join("Games/need-for-speed-iii-hot-pursuit/drive_c/Program Files (x86)/Electronic Arts/Need for Speed III - Hot Pursuit"),
	])


func scan_data() -> void:
	tracks.clear()
	cars.clear()
	cop_cars.clear()
	traffic_cars.clear()
	var roots := PackedStringArray([data_root]) + candidate_roots()
	data_root = ""
	for r in roots:
		if r != "" and find_ci(r, "gamedata/tracks") != "":
			data_root = r
			break
	if data_root != "":
		var tdir := find_ci(data_root, "gamedata/tracks")
		for t in _sorted_dirs(tdir):
			# Ids are lower-case ("trk000") whatever the install's folder case ("Trk000").
			if find_ci(tdir.path_join(t), t.to_lower().replace("k0", "") + ".frd") != "":
				tracks.append(t.to_lower())
		var cdir := find_ci(data_root, "gamedata/carmodel")
		if cdir != "":
			for c in _sorted_dirs(cdir):
				var p := cdir.path_join(c)
				if find_ci(p, "car.viv") == "":
					continue
				var n := Nfs3Car.peek_name(p)
				if n == "":
					continue
				cars.append({"id": c, "name": n, "path": p})
			var pursuit := find_ci(cdir, "traffic/pursuit")
			for c in _sorted_dirs(pursuit):
				if find_ci(pursuit.path_join(c), "car.viv") != "":
					cop_cars.append(pursuit.path_join(c))
			var traffic_dir := find_ci(cdir, "traffic")
			for c in _sorted_dirs(traffic_dir):
				if c.is_valid_int() and find_ci(traffic_dir.path_join(c), "car.viv") != "":
					traffic_cars.append(traffic_dir.path_join(c))
	tracks.append(PROCEDURAL_TRACK)
	if cars.is_empty():
		for i in ProceduralCar.PRESETS.size():
			cars.append({"id": "proc%d" % i, "name": ProceduralCar.PRESETS[i].name, "path": ""})
	if track_id not in tracks:
		track_id = tracks[0]
	car_index = clampi(car_index, 0, cars.size() - 1)


func has_game_data() -> bool:
	return data_root != ""


func track_name(id: String) -> String:
	if id == PROCEDURAL_TRACK:
		return "Procedural Circuit"
	return TRACK_NAMES.get(id, id)


func track_dir(id: String) -> String:
	return find_ci(find_ci(data_root, "gamedata/tracks"), id)


## Case-insensitive path lookup (the Windows install uses mixed case).
## Returns the real absolute path, or "" when it doesn't exist.
func find_ci(base: String, rel: String) -> String:
	return DataPath.find_ci(base, rel)


func _sorted_dirs(path: String) -> PackedStringArray:
	if path == "":
		return PackedStringArray()
	var d := DirAccess.open(path)
	if d == null:
		return PackedStringArray()
	var out := d.get_directories()
	out.sort()
	return out


## Loaded car data (cached). `path` == "" means a procedural car preset.
func load_car(path: String, preset := 0) -> Object:
	var key := path if path != "" else "preset%d" % preset
	if not _car_cache.has(key):
		if path == "":
			_car_cache[key] = ProceduralCar.make(preset)
		else:
			_car_cache[key] = Nfs3Car.load_dir(path)
	return _car_cache[key]


func player_car_data() -> Object:
	var c: Dictionary = cars[car_index]
	return load_car(c.path, car_index)


# ------------------------------------------------------------------ settings

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "data_root", data_root)
	cf.set_value("game", "mode", mode)
	cf.set_value("game", "track", track_id)
	cf.set_value("game", "car", car_index)
	cf.set_value("game", "laps", laps)
	cf.set_value("game", "opponents", opponents)
	cf.set_value("game", "traffic", traffic)
	cf.set_value("game", "kmh", units_kmh)
	cf.save(SETTINGS_PATH)


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	data_root = cf.get_value("game", "data_root", "")
	mode = cf.get_value("game", "mode", mode)
	track_id = str(cf.get_value("game", "track", track_id)).to_lower()
	car_index = cf.get_value("game", "car", 0)
	laps = cf.get_value("game", "laps", laps)
	opponents = cf.get_value("game", "opponents", opponents)
	traffic = cf.get_value("game", "traffic", traffic)
	units_kmh = cf.get_value("game", "kmh", units_kmh)


# ------------------------------------------------------------------ input

func _setup_input() -> void:
	_bind("accelerate", [KEY_UP, KEY_W], [JOY_BUTTON_A], JOY_AXIS_TRIGGER_RIGHT)
	_bind("brake", [KEY_DOWN, KEY_S], [JOY_BUTTON_X], JOY_AXIS_TRIGGER_LEFT)
	_bind("steer_left", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT])
	_bind("steer_right", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT])
	_bind("handbrake", [KEY_SPACE], [JOY_BUTTON_B])
	_bind("camera", [KEY_C], [JOY_BUTTON_Y])
	_bind("look_back", [KEY_B], [JOY_BUTTON_LEFT_SHOULDER])
	_bind("reset_car", [KEY_R], [JOY_BUTTON_BACK])
	_bind("horn", [KEY_H], [JOY_BUTTON_RIGHT_SHOULDER])
	_bind("mirror", [KEY_M], [])
	_bind("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])
	# Analog steering on the left stick.
	for dir in [["steer_left", -1.0], ["steer_right", 1.0]]:
		var ev := InputEventJoypadMotion.new()
		ev.axis = JOY_AXIS_LEFT_X
		ev.axis_value = dir[1]
		InputMap.action_add_event(dir[0], ev)


func _bind(action: String, keys: Array, buttons: Array, axis := -1) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var ev := InputEventJoypadButton.new()
		ev.button_index = b
		InputMap.action_add_event(action, ev)
	if axis >= 0:
		var ev := InputEventJoypadMotion.new()
		ev.axis = axis
		ev.axis_value = 1.0
		InputMap.action_add_event(action, ev)
