extends Node
## Global state: where the NFS3 data lives, what the player picked in the menu,
## input bindings and a small cache of loaded cars.

enum Mode { SINGLE_RACE, HOT_PURSUIT, TIME_TRIAL, FREE_ROAM, SPECTATE }
const MODE_NAMES := ["Single Race", "Hot Pursuit", "Time Trial", "Free Roam", "Spectate"]
enum Quality { LOW, MEDIUM, HIGH }
const QUALITY_NAMES := ["Low", "Medium", "High"]

## Friendly names for the stock NFS3 track folders.
const TRACK_NAMES := {
	"trk000": "Hometown", "trk001": "Redrock Ridge", "trk002": "Atlantica",
	"trk003": "Rocky Pass", "trk004": "Country Woods", "trk005": "Lost Canyons",
	"trk006": "Aquatica", "trk007": "The Summit", "trk008": "Empire City",
}
## High Stakes track folders in the game's order, with their names; ids are HS_PREFIX + the
## folder name, lower case. The last nine are its versions of the NFS3 tracks.
const HS_PREFIX := "hs_"
const HS_TRACK_NAMES := {
	"uk": "Celtic Ruins", "germany": "Landstrasse", "coastal": "Dolphin Cove",
	"park": "Kindiak Park", "france": "Route Adonf", "hills": "Durham Road",
	"snowy": "Snowy Ridge", "gt1": "Raceway", "gt2": "Raceway 2", "gt3": "Raceway 3",
	"hometown": "Hometown HS", "redrock": "Redrock Ridge HS", "atlantic": "Atlantica HS",
	"rockypas": "Rocky Pass HS", "country": "Country Woods HS", "lostcany": "Lost Canyons HS",
	"aquatica": "Aquatica HS", "summit": "The Summit HS", "empire": "Empire City HS",
}
const PROCEDURAL_TRACK := "procedural"
const SETTINGS_PATH := "user://settings.cfg"

var data_root := ""          # folder containing gamedata/
var hs_root := ""            # High Stakes Data/ folder (containing tracks/ and gameart/), or ""
var tracks: Array[String] = []   # track ids (folder names), plus PROCEDURAL_TRACK
var cars: Array[Dictionary] = [] # {id, name, path}; High Stakes ones after NFS3's, ids HS_PREFIX + folder
var cop_cars: Array[String] = []
var traffic_cars: Array[String] = []
var hs_cop_cars: Array[String] = []      # High Stakes' police and traffic, for its tracks
var hs_traffic_cars: Array[String] = []

var mode := Mode.SINGLE_RACE
var track_id := PROCEDURAL_TRACK
var car_index := 0
var laps := 2
var opponents := 3
var traffic := true
var units_kmh := true
var night := false
var weather := false      # the track's rain or snow
var damage := true        # crashes dent the cars and cost power (not in the original)
var quality := Quality.HIGH   # replaced by default_quality() until the player picks one
var camera_mode := 0      # index into ChaseCamera.MODES, kept from race to race
var render_scale := 0.0   # where DynamicResolution left the 3D resolution: the next race starts there
var render_scale_quality := -1   # ...if it's on the same quality preset
var last_results: Array = []

var _car_cache := {}


func _ready() -> void:
	_setup_input()
	quality = default_quality()
	_load_settings()
	scan_data()
	# Developer hook: `godot --path . -- --autotest [track] [mode]` plays a scripted run.
	if "--autotest" in OS.get_cmdline_user_args():
		var t: Node = load("res://tools/autotest.gd").new()
		add_child(t)
	# `godot --path . -- --trackshots <track> [lap fraction ...]` photographs a track's road.
	if "--trackshots" in OS.get_cmdline_user_args():
		add_child(load("res://tools/track_shots.gd").new())
	# `godot --path . -- --postcards [track ...]` re-renders the menu's track pictures.
	if "--postcards" in OS.get_cmdline_user_args():
		add_child(load("res://tools/postcards.gd").new())
	# `godot --path . -- --carshots [traffic|cops|cars]` photographs cars for a contact sheet.
	if "--carshots" in OS.get_cmdline_user_args():
		add_child(load("res://tools/car_shots.gd").new())
	# `godot --path . -- --fxshots [track]` stages slides, dust, scrapes and crashes to photograph.
	if "--fxshots" in OS.get_cmdline_user_args():
		add_child(load("res://tools/fx_shots.gd").new())


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


## Where a Need for Speed: High Stakes install's Data folder may be, first match wins.
func candidate_hs_roots() -> PackedStringArray:
	var res := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var home := OS.get_environment("HOME")
	var lutris := "need-for-speed-high-stakes/drive_c/Program Files (x86)/Electronic Arts/Need for Speed - High Stakes/Data"
	return PackedStringArray([
		OS.get_environment("NFS4_DATA"),
		res.get_base_dir().path_join("OpenNFS/resources/NFS_4/data"),
		res.get_base_dir().path_join(lutris),
		home.path_join("Games").path_join(lutris),
	])


func scan_data() -> void:
	tracks.clear()
	cars.clear()
	cop_cars.clear()
	traffic_cars.clear()
	hs_cop_cars.clear()
	hs_traffic_cars.clear()
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
	_scan_hs()
	tracks.append(PROCEDURAL_TRACK)
	if cars.is_empty():
		for i in ProceduralCar.PRESETS.size():
			cars.append({"id": "proc%d" % i, "name": ProceduralCar.PRESETS[i].name, "path": ""})
	if track_id not in tracks:
		track_id = tracks[0]
	car_index = clampi(car_index, 0, cars.size() - 1)


## Adds the High Stakes tracks, in the game's order and then any others (add-on tracks),
## and its cars.
func _scan_hs() -> void:
	var roots := PackedStringArray([hs_root]) + candidate_hs_roots()
	hs_root = ""
	for r in roots:
		if r != "" and find_ci(r, "tracks") != "" and find_ci(r, "gameart") != "":
			hs_root = r
			break
	if hs_root == "":
		return
	var tdir := find_ci(hs_root, "tracks")
	var found: Array[String] = []
	for t in _sorted_dirs(tdir):
		if Nfs4Track.is_track_dir(tdir.path_join(t)):
			found.append(t.to_lower())
	for t in HS_TRACK_NAMES:
		if t in found:
			tracks.append(HS_PREFIX + t)
	for t in found:
		if not HS_TRACK_NAMES.has(t):
			tracks.append(HS_PREFIX + t)
	_scan_hs_cars(find_ci(hs_root, "cars"))


## High Stakes cars join the list after NFS3's; one NFS3 also has ("Ferrari 550 Maranello")
## is marked "HS". Its police cars and traffic are kept for its own tracks.
func _scan_hs_cars(cdir: String) -> void:
	if cdir == "":
		return
	var nfs3_names := {}
	for c in cars:
		nfs3_names[c.name.to_lower()] = true
	for c in _sorted_dirs(cdir):
		var p := cdir.path_join(c)
		if c.to_lower() == "traffic" or find_ci(p, "car.viv") == "":
			continue
		var n := Nfs3Car.peek_name(p)
		if n == "":
			continue
		if nfs3_names.has(n.to_lower()):
			n += " HS"
		cars.append({"id": HS_PREFIX + c.to_lower(), "name": n, "path": p})
	var pursuit := find_ci(cdir, "traffic/pursuit")
	for c in _sorted_dirs(pursuit):
		if find_ci(pursuit.path_join(c), "car.viv") != "":
			hs_cop_cars.append(pursuit.path_join(c))
	# Its traffic folders are named (sedan2, semi, ...); "choppers" holds the helicopter.
	var traffic_dir := find_ci(cdir, "traffic")
	for c in _sorted_dirs(traffic_dir):
		if c.to_lower() != "pursuit" and find_ci(traffic_dir.path_join(c), "car.viv") != "":
			hs_traffic_cars.append(traffic_dir.path_join(c))


## The police cars for the chosen track: High Stakes' on its tracks, NFS3's on the others
## (either game's when the other has none).
func cop_models() -> Array[String]:
	if (is_hs_track(track_id) or cop_cars.is_empty()) and not hs_cop_cars.is_empty():
		return hs_cop_cars
	return cop_cars


## The traffic for the chosen track, as cop_models(). High Stakes' snowplow only turns out
## on its snowy track.
func traffic_models() -> Array[String]:
	if (is_hs_track(track_id) or traffic_cars.is_empty()) and not hs_traffic_cars.is_empty():
		if track_id == HS_PREFIX + "snowy":
			return hs_traffic_cars
		var out: Array[String] = []
		for p in hs_traffic_cars:
			if p.get_file().to_lower() != "snowplow":
				out.append(p)
		return out
	return traffic_cars


func has_game_data() -> bool:
	return data_root != ""


func is_hs_track(id: String) -> bool:
	return id.begins_with(HS_PREFIX)


func track_name(id: String) -> String:
	if id == PROCEDURAL_TRACK:
		return ProcPlaces.names(ProceduralTrack.SEED).town
	if is_hs_track(id):
		var folder := id.trim_prefix(HS_PREFIX)
		return HS_TRACK_NAMES.get(folder, folder.capitalize())
	return TRACK_NAMES.get(id, id)


## The track's folder, or "" for the procedural track (or a track whose data is gone).
func track_dir(id: String) -> String:
	if id == PROCEDURAL_TRACK:
		return ""
	if is_hs_track(id):
		return find_ci(find_ci(hs_root, "tracks"), id.trim_prefix(HS_PREFIX))
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
			var car := Nfs3Car.load_dir(path)
			if car.error != "" or car.body_parts.is_empty():
				# A damaged car file: race a stand-in rather than an invisible car.
				push_warning("Car %s failed to load (%s), using a stand-in" % [path, car.error])
				var stand_in := ProceduralCar.make(preset % ProceduralCar.PRESETS.size())
				stand_in.display_name = car.display_name if car.display_name != "" else stand_in.display_name
				_car_cache[key] = stand_in
			else:
				_car_cache[key] = car
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
	cf.set_value("game", "night", night)
	cf.set_value("game", "weather", weather)
	cf.set_value("game", "damage", damage)
	cf.set_value("game", "quality", quality)
	cf.set_value("game", "camera", camera_mode)
	cf.save(SETTINGS_PATH)


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	# Hand-edited or stale files: take only values of the right type and range.
	data_root = str(cf.get_value("game", "data_root", ""))
	mode = clampi(_int(cf, "mode", mode), 0, MODE_NAMES.size() - 1) as Mode
	track_id = str(cf.get_value("game", "track", track_id)).to_lower()
	car_index = maxi(_int(cf, "car", 0), 0)
	laps = clampi(_int(cf, "laps", laps), 1, 8)
	opponents = clampi(_int(cf, "opponents", opponents), 0, 7)
	traffic = _bool(cf, "traffic", traffic)
	units_kmh = _bool(cf, "kmh", units_kmh)
	night = _bool(cf, "night", night)
	weather = _bool(cf, "weather", weather)
	damage = _bool(cf, "damage", damage)
	quality = clampi(_int(cf, "quality", quality), 0, QUALITY_NAMES.size() - 1) as Quality
	camera_mode = clampi(_int(cf, "camera", camera_mode), 0, ChaseCamera.MODES.size() - 1)


func _int(cf: ConfigFile, key: String, fallback: int) -> int:
	var v: Variant = cf.get_value("game", key, fallback)
	return int(v) if v is int or v is float else fallback


func _bool(cf: ConfigFile, key: String, fallback: bool) -> bool:
	var v: Variant = cf.get_value("game", key, fallback)
	return v if v is bool else fallback


# ------------------------------------------------------------------ graphics

## Integrated GPUs and dual-core CPUs start on Low: sun shadows and MSAA alone
## cost ~35 ms a frame on e.g. a Haswell HD GT1.
func default_quality() -> Quality:
	var weak_gpu := RenderingServer.get_video_adapter_type() in [
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, RenderingDevice.DEVICE_TYPE_CPU]
	return Quality.LOW if weak_gpu or OS.get_processor_count() <= 2 else Quality.HIGH


var _shader_variants := {}


## The shader at `path` for the current quality: on Low, a copy compiled with
## `#define LOW_QUALITY`, which the heavier shaders use to skip their costliest detail
## (fill rate is what an iGPU runs out of first).
func shader(path: String) -> Shader:
	var base: Shader = load(path)
	if quality != Quality.LOW:
		return base
	if not _shader_variants.has(path):
		var s := Shader.new()
		var code := base.code
		var at := code.find(";", code.find("shader_type")) + 1
		s.code = code.substr(0, at) + "\n#define LOW_QUALITY\n" + code.substr(at)
		_shader_variants[path] = s
	return _shader_variants[path]


## Applies the quality preset to the race's main view and sun.
func apply_quality(vp: Viewport, sun: DirectionalLight3D) -> void:
	Car.lamp_lights = quality != Quality.LOW
	match quality:
		Quality.LOW:
			sun.shadow_enabled = false
			# 3D at 75% resolution (the HUD stays sharp): fill rate is what a weak iGPU runs out of.
			vp.scaling_3d_scale = 0.75
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		Quality.MEDIUM:
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 50.0
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		Quality.HIGH:
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 80.0
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED


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
	_bind("headlights", [KEY_L], [JOY_BUTTON_DPAD_UP])
	_bind("high_beam", [KEY_K], [JOY_BUTTON_DPAD_DOWN])
	_bind("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])
	_bind("handling_feel", [KEY_F6], [])
	_bind("watch_prev", [KEY_Q, KEY_PAGEUP], [])
	_bind("watch_next", [KEY_E, KEY_PAGEDOWN, KEY_TAB], [])
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
