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
## High Stakes' own numbering of its tracks (its menu slides, FeArt/slides/tN_00.qfs).
const HS_SLIDES := {
	"germany": 0, "uk": 1, "france": 2, "hills": 3, "coastal": 4, "park": 5, "snowy": 6,
	"gt1": 7, "gt2": 8, "gt3": 9, "hometown": 10, "redrock": 11, "atlantic": 12, "rockypas": 13,
	"country": 14, "lostcany": 15, "aquatica": 16, "summit": 17, "empire": 18,
}
## Porsche Unleashed tracks (GameData/Track/<name>.crp) in the game's order, with their
## names; ids are PU_PREFIX + the name.
const PU_PREFIX := "pu_"
const PU_TRACK_NAMES := {
	"farmland": "Normandie", "forest": "Schwarzwald", "foothills": "Corsica",
	"coastal": "Côte d'Azur", "canyon": "Pyrénées", "alps": "Alps", "castle": "Auvergne",
	"autobahn": "Autobahn", "industrial": "Zone Industrielle",
	"monaco1": "Monte Carlo 1", "monaco2": "Monte Carlo 2", "monaco3": "Monte Carlo 3",
	"monaco4": "Monte Carlo 4", "monaco5": "Monte Carlo 5", "skidpad": "Skid Pad",
}
const PROCEDURAL_TRACK := "procedural"
const SETTINGS_PATH := "user://settings.cfg"

var data_root := ""          # folder containing gamedata/
var hs_root := ""            # High Stakes Data/ folder (containing tracks/ and gameart/), or ""
var pu_root := ""            # Porsche Unleashed GameData/ folder (containing Track/ and Carmodel/), or ""
var _pu_cars := {}           # car path "pu:<n>" -> its FeData/Data/nfs5.car record (Nfs5Car.car_table)
var pu_cop_cars: Array[String] = []      # Porsche Unleashed's police and traffic ("pu:<n>"), for its tracks
var pu_traffic_cars: Array[String] = []
var tracks: Array[String] = []   # track ids (folder names), plus PROCEDURAL_TRACK
var cars: Array[Dictionary] = [] # {id, name, path}; High Stakes ones after NFS3's, ids HS_PREFIX + folder
var cop_cars: Array[String] = []
var traffic_cars: Array[String] = []
var hs_cop_cars: Array[String] = []      # High Stakes' police and traffic, for its tracks
var hs_traffic_cars: Array[String] = []
var hs_helicopter := ""                  # High Stakes' police helicopter's folder (car.viv with hel.fce), or ""

var mode := Mode.SINGLE_RACE
var track_id := PROCEDURAL_TRACK
var car_index := 0
var laps := 2
var opponents := 3
var upgrades := {}          # car id -> High Stakes upgrade level 1..3 (Car.UPGRADES); absent is stock
var paints := {}            # car id -> which of its paint colours (FCE colour list); absent is the first
var driver := 0             # who drives your Porsche Unleashed cars (1..10, Nfs5Car's); 0 the car's own
var rival_upgrades := 0     # 0 stock, 1 as upgraded as yours, 2 fully upgraded
var rival_class := 0        # 0 rivals of your car's class (nearest classes if too few), 1 any
var intro_flyby := true     # the track's fly-by round the grid before the countdown
var hud_style := 0          # 0 this game's tach; High Stakes' own dials (ClassicGauges): 1 at the top as it had them, 2 bottom centre
## The race HUD's parts, each of which can be hidden (Settings -> HUD): id -> caption.
const HUD_WIDGETS := {
	"speed": "Speed", "standings": "Standings", "police": "Police", "lap": "Lap", "map": "Map",
	"mirror": "Mirror", "messages": "Messages", "countdown": "Countdown", "lights": "Light bar", "hints": "Key hints",
}
var hud_on := true          # the whole HUD (F1 in a race)
var hud_hidden: Array[String] = []   # HUD_WIDGETS ids turned off
## The way round the track (both games' reverse and mirror options): an index into LAYOUTS.
var layout := 0
const LAYOUTS := ["Forward", "Reverse", "Mirror", "Mir. rev."]
var traffic := true
var units_kmh := true
var night := false
var weather := false      # the track's rain or snow
var damage := true        # crashes dent the cars and cost power (not in the original)
var manual_gears := false # the player shifts by hand (shift_up / shift_down) on the car's manual gearing
var tops_down := true     # Porsche Unleashed's cabriolets start a race with the hood folded (T raises it)
var quality := Quality.HIGH   # replaced by default_quality() until the player picks one
var camera_mode := 0      # index into ChaseCamera.MODES, kept from race to race
var fullscreen := false
var vsync := true
var volume := 8           # master volume in tenths, 0..10
var music_volume := 6     # the music's, 0..10 (0 turns it off)
var sfx_volume := 10      # engines, tyres, crashes, sirens and menu clicks, 0..10
var ambience_volume := 10 # the world around the track: rain, thunder, 0..10
var voice_volume := 10    # the countdown, lap calls and the police, 0..10
const BUS_MUSIC := &"Music"   # the audio buses the dials set, all sending to Master
const BUS_SFX := &"SFX"
const BUS_AMBIENCE := &"Ambience"
const BUS_VOICE := &"Voice"
var music: MusicPlayer    # plays across scenes: the track's song in a race, else the menu music
var render_scale := 0.0   # where DynamicResolution left the 3D resolution: the next race starts there
var render_scale_quality := -1   # ...if it's on the same quality preset
var last_results: Array = []

var _car_cache := {}
var _spec_cache := {}
var _saved_car_id := ""   # the car picked last time, found again by id after the list is scanned


func _ready() -> void:
	_setup_input()
	quality = default_quality()
	_migrate_user_dir()
	_load_settings()
	scan_data()
	apply_display()
	music = MusicPlayer.new()
	add_child(music)
	add_child(MenuSounds.new())
	get_tree().scene_changed.connect(_on_scene_changed)
	_on_scene_changed.call_deferred()
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
	# `godot --path . -- --enhanceskins [cars|pu|hs|traffic|all]` upscales car skins (SkinHD).
	if "--enhanceskins" in OS.get_cmdline_user_args():
		add_child(load("res://tools/enhance_skins.gd").new())
	# `godot --path . -- --fxshots [track]` stages slides, dust, scrapes and crashes to photograph.
	if "--fxshots" in OS.get_cmdline_user_args():
		add_child(load("res://tools/fx_shots.gd").new())
	# `godot --headless --path . -- --careertest` plays the tournaments through on paper.
	if "--careertest" in OS.get_cmdline_user_args():
		add_child(load("res://tools/career_test.gd").new())
	# `godot --headless --path . -- --handling [car ...]` runs skidpad, lane change and braking tests.
	if "--handling" in OS.get_cmdline_user_args():
		add_child(load("res://tools/car_handling.gd").new())
	# `godot --path . -- --hsqa <track>` photographs a High Stakes track with its collision shown.
	if "--hsqa" in OS.get_cmdline_user_args():
		add_child(load("res://tools/hs_qa.gd").new())


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


## Where a Need for Speed: Porsche Unleashed install's GameData folder may be, first match wins.
func candidate_pu_roots() -> PackedStringArray:
	var res := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var home := OS.get_environment("HOME")
	var lutris := "need-for-speed-porsche-unleashed/drive_c/Program Files (x86)/Electronic Arts/Need for Speed - Porsche Unleashed/GameData"
	return PackedStringArray([
		OS.get_environment("NFS5_DATA"),
		res.get_base_dir().path_join("OpenNFS/resources/NFS_5/GameData"),
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
	hs_helicopter = ""
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
	_scan_pu()
	tracks.append(PROCEDURAL_TRACK)
	if cars.is_empty():
		for i in ProceduralCar.PRESETS.size():
			cars.append({"id": "proc%d" % i, "name": ProceduralCar.PRESETS[i].name, "path": ""})
	if track_id not in tracks:
		track_id = tracks[0]
	for i in cars.size():
		if cars[i].id == _saved_car_id:
			car_index = i
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


## Adds the Porsche Unleashed tracks, in the game's order.
func _scan_pu() -> void:
	var roots := PackedStringArray([pu_root]) + candidate_pu_roots()
	pu_root = ""
	for r in roots:
		if r != "" and find_ci(r, "track") != "" and find_ci(r, "carmodel") != "":
			pu_root = r
			break
	if pu_root == "":
		return
	var tdir := find_ci(pu_root, "track")
	for t in PU_TRACK_NAMES:
		if find_ci(tdir, t + ".crp") != "" and find_ci(tdir, t + ".fsh") != "":
			tracks.append(PU_PREFIX + t)
	# Its cars, in the car table's order (by era), leaving out the Factory Driver's copies of
	# three of them; its police cars and traffic are kept for its tracks.
	_pu_cars.clear()
	pu_cop_cars.clear()
	pu_traffic_cars.clear()
	var cdir := find_ci(pu_root, "carmodel")
	for rec in Nfs5Car.car_table(pu_root):
		var m: String = rec.model.to_lower()
		if rec.name.begins_with("Cop"):
			# The 356 cruisers' records name the plain 356 B; theirs is cop356 (with its light bar).
			if m == "356b":
				rec.model = "cop356_german" if rec.name.contains("German") else "cop356"
				rec.style = 0
				m = rec.model
		if m in ["fboxster", "f901", "f996"] or find_ci(cdir, m + ".crp") == "":
			continue
		var path := "pu:%d" % rec.index
		_pu_cars[path] = rec
		if rec.name.begins_with("Cop"):
			pu_cop_cars.append(path)
		elif rec.sim == "":
			pu_traffic_cars.append(path)
		else:
			cars.append({"id": PU_PREFIX + rec.sim.to_lower(), "name": Nfs5Car._display_name(rec.name), "path": path})


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
	var choppers := find_ci(traffic_dir, "choppers")
	for c in _sorted_dirs(choppers):
		if find_ci(choppers.path_join(c), "car.viv") != "":
			hs_helicopter = choppers.path_join(c)
			break


## The police cars for the chosen track: High Stakes' on its tracks, NFS3's on the others
## (either game's when the other has none).
func cop_models() -> Array[String]:
	if is_pu_track(track_id) and not pu_cop_cars.is_empty():
		return pu_cop_cars
	if (is_hs_track(track_id) or cop_cars.is_empty()) and not hs_cop_cars.is_empty():
		return hs_cop_cars
	return cop_cars


## The traffic for the chosen track, as cop_models(). High Stakes' snowplow only turns out
## on its snowy track.
func traffic_models() -> Array[String]:
	if is_pu_track(track_id) and not pu_traffic_cars.is_empty():
		# Its snowplough (EAS4) only turns out in the Alps.
		if track_id == PU_PREFIX + "alps":
			return pu_traffic_cars
		return pu_traffic_cars.filter(func(p: String) -> bool: return _pu_cars[p].model.to_lower() != "eas4")
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


## High Stakes' remake of NFS3 track `id` (its id), or "" (its signs' mirrored copies
## serve the NFS3 track's mirrored layout).
func hs_remake(id: String) -> String:
	var folder: Variant = MusicPlayer.HS_REMAKES.find_key(id)
	return HS_PREFIX + folder if folder != null and hs_root != "" else ""


func is_pu_track(id: String) -> bool:
	return id.begins_with(PU_PREFIX)


## Whether the track is a point-to-point run (Porsche Unleashed's, but for the Monte Carlo
## circuits and the skid pad), raced once from start to finish.
func is_sprint(id: String) -> bool:
	return is_pu_track(id) and not id.trim_prefix(PU_PREFIX).begins_with("monaco") and id != PU_PREFIX + "skidpad"


## Laps of the race on the chosen track: one on a point-to-point run.
func race_laps() -> int:
	return 1 if is_sprint(track_id) else laps


func track_name(id: String) -> String:
	if id == PROCEDURAL_TRACK:
		return ProcPlaces.names(ProceduralTrack.SEED).town
	if is_hs_track(id):
		var folder := id.trim_prefix(HS_PREFIX)
		return HS_TRACK_NAMES.get(folder, folder.capitalize())
	if is_pu_track(id):
		var pu := id.trim_prefix(PU_PREFIX)
		return PU_TRACK_NAMES.get(pu, pu.capitalize())
	return TRACK_NAMES.get(id, id)


## The track's folder, or "" for the procedural track (or a track whose data is gone).
## A Porsche Unleashed track's is its .crp file (they share one folder).
func track_dir(id: String) -> String:
	if id == PROCEDURAL_TRACK:
		return ""
	if is_hs_track(id):
		return find_ci(find_ci(hs_root, "tracks"), id.trim_prefix(HS_PREFIX))
	if is_pu_track(id):
		return find_ci(find_ci(pu_root, "track"), id.trim_prefix(PU_PREFIX) + ".crp")
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


## Loaded car data (cached). `path` == "" means a procedural car preset. `who` puts that
## driver in a Porsche Unleashed car (0: its own).
func load_car(path: String, preset := 0, who := 0) -> Object:
	var key := _car_key(path, preset, who)
	if not _car_cache.has(key):
		if path == "":
			_car_cache[key] = ProceduralCar.make(preset)
		else:
			var car: Nfs3Car = Nfs5Car.load_car(pu_root, _pu_cars[path], who) if is_pu_path(path) else Nfs3Car.load_dir(path)
			if car.error != "" or car.body_parts.is_empty():
				# A damaged car file: race a stand-in rather than an invisible car.
				push_warning("Car %s failed to load (%s), using a stand-in" % [path, car.error])
				var stand_in := ProceduralCar.make(preset % ProceduralCar.PRESETS.size())
				stand_in.display_name = car.display_name if car.display_name != "" else stand_in.display_name
				_car_cache[key] = stand_in
			else:
				# Its sharper skin, if one's been made (not on Low: 4x the memory).
				if quality != Quality.LOW:
					SkinHD.apply(car, path, who if is_pu_path(path) else 0)
				_car_cache[key] = car
	return _car_cache[key]


func _car_key(path: String, preset: int, who: int) -> String:
	if path == "":
		return "preset%d" % preset
	return path + "#driver%d" % who if who > 0 and is_pu_path(path) else path


## Car `i` as you drive it: with your driver.
func own_car(i: int) -> Object:
	return load_car(cars[i].path, i, driver)


## Whether own_car(i) is loaded already.
func own_car_loaded(i: int) -> bool:
	return _car_cache.has(_car_key(cars[i].path, i, driver))


## Just the car's name and carp.txt (no mesh or skin), for menus that list every car:
## cheap enough to read all of them at once.
func car_spec(i: int) -> Object:
	var c: Dictionary = cars[i]
	if _car_cache.has(c.path if c.path != "" else "preset%d" % i):
		return load_car(c.path, i)
	if not _spec_cache.has(i):
		_spec_cache[i] = ProceduralCar.make(i % ProceduralCar.PRESETS.size()) if c.path == "" \
			else Nfs5Car.peek(pu_root, _pu_cars[c.path]) if is_pu_path(c.path) else Nfs3Car.peek_spec(c.path)
	return _spec_cache[i]


## 0..2 for classes A..C, 3 for anything else (the Knockout and stand-ins).
func car_class(i: int) -> int:
	var spec := car_spec(i)
	var v: float = spec.carp_value(1, 3.0)
	return clampi(int(v), 0, 3)


## Porsche Unleashed's photos of its tracks: FeData/Trackart/<name>sp.fsh, some names cut short.
const PU_TRACK_ART := {"canyon": "canysp", "farmland": "farmsp", "foothills": "foothisp", "industrial": "industsp"}


## A Porsche Unleashed track's first photo (256 x 192), or null.
func pu_track_photo(id: String) -> Image:
	var name := id.trim_prefix(PU_PREFIX)
	var file: String = PU_TRACK_ART.get(name, name + "sp") + ".fsh"
	var fsh := Fsh.load_file(find_ci(pu_root.get_base_dir(), "FeData/Trackart/" + file)) if pu_root != "" else null
	return fsh.images[0] if fsh and fsh.images.size() > 0 else null


## Which game a car or track comes from: 0 NFS III (and the stand-ins), 1 High Stakes,
## 2 Porsche Unleashed.
const GAME_NAMES := ["NFS III", "HIGH STAKES", "PORSCHE"]


func car_game(i: int) -> int:
	return 2 if is_pu_car(i) else 1 if is_hs_car(i) else 0


func track_game(id: String) -> int:
	return 2 if is_pu_track(id) else 1 if is_hs_track(id) else 0


func is_pu_path(path: String) -> bool:
	return path.begins_with("pu:") and _pu_cars.has(path)


func is_pu_car(i: int) -> bool:
	return str(cars[i].id).begins_with(PU_PREFIX)


func is_hs_car(i: int) -> bool:
	return str(cars[i].id).begins_with(HS_PREFIX)


func is_pursuit_car(i: int) -> bool:
	return str(cars[i].name).begins_with("Pursuit")


var _rank_cache := {}


## Car `i`'s High Stakes ranking (Nfs3Car.read_rank: class, serial, ratings, upgradable).
## An NFS3 car High Stakes has too (the same serial) goes by High Stakes' figures for it;
## the stand-ins have none ({}).
func car_rank(i: int) -> Dictionary:
	if not _rank_cache.has(i):
		var spec := car_spec(i)
		var r: Dictionary = spec.rank if "rank" in spec else {}
		if not r.is_empty() and not is_hs_car(i):
			for k in cars.size():
				if is_hs_car(k) and not is_pursuit_car(k) and car_spec(k).rank.get("serial", -1) == r.serial:
					r = car_spec(k).rank
					break
		_rank_cache[i] = r
	return _rank_cache[i]


## Car `i`'s High Stakes class: 0..3 for AAA, AA, A, B; -1 none (the Knockout). The
## stand-ins go by their carp class a class down (A as AA...).
func hs_class(i: int) -> int:
	var r := car_rank(i)
	if r.has("class"):
		return r.class
	var c := car_class(i)
	return c + 1 if c < 3 else -1


## Car `i`'s overall rating (High Stakes' 1..20 bar) at upgrade `level`.
func car_rating(i: int, level := 0) -> int:
	var ratings: Array = car_rank(i).get("ratings", [10])
	return ratings[clampi(level, 0, ratings.size() - 1)]


## Car `i`'s serial number (fedata's), what a "Model" restriction names.
func car_serial(i: int) -> int:
	return int(car_rank(i).get("serial", car_spec(i).carp_value(0, -1.0)))


## The name of the car with serial `serial` (High Stakes' own first), or "".
func serial_name(serial: int) -> String:
	var found := ""
	for i in cars.size():
		if not is_pursuit_car(i) and car_serial(i) == serial:
			if is_hs_car(i):
				return cars[i].name
			if found == "":
				found = cars[i].name
	return found


var _hs_props := {}


## A High Stakes GameArt model ("cone", "median", "haybale", "flare", "cop0" the officer),
## cached; null without High Stakes data.
func hs_prop(name: String, part := "") -> ArrayMesh:
	if hs_root == "":
		return null
	if not _hs_props.has(name):
		_hs_props[name] = Fce4.load_prop(find_ci(hs_root, "gameart"), name, part)
	return _hs_props[name]


## Whether the race HUD shows widget `id` (HUD_WIDGETS).
func hud_shows(id: String) -> bool:
	return hud_on and not id in hud_hidden


## Car `i`'s upgrade level (0 stock).
func upgrade_of(i: int) -> int:
	return int(upgrades.get(cars[i].id, 0)) if i >= 0 and i < cars.size() else 0


func set_upgrade(i: int, level: int) -> void:
	if level <= 0:
		upgrades.erase(cars[i].id)
	else:
		upgrades[cars[i].id] = level


func layout_reversed(l := layout) -> bool:
	return l == 1 or l == 3


## Mirrored only where the track comes from game data (the procedural one has no mirror).
func layout_mirrored(l := layout) -> bool:
	return l >= 2


## Car `i`'s chosen paint (index into its colours).
func paint_of(i: int) -> int:
	return int(paints.get(cars[i].id, 0)) if i >= 0 and i < cars.size() else 0


## The tint Car.setup takes for car `i`'s chosen paint (none: the file's first).
func paint_tint(i: int, data: Object) -> Color:
	var p := paint_of(i)
	return data.colours[p] if p > 0 and p < data.colours.size() else Color(0, 0, 0, 0)


## A rival's upgrade level by the setting (the player's car is `car_index`).
func rival_upgrade() -> int:
	match rival_upgrades:
		1: return upgrade_of(car_index)
		2: return Car.UPGRADES.size()
	return 0


## The cars a single race's rivals are picked from (not the player's own, not the police
## ones), shuffled, the first `n` of them the ones to take. With rival_class "Yours" those
## of the player's High Stakes class (hs_class) come first, then the nearer classes.
func rival_pool(n: int) -> Array:
	var pool: Array = range(cars.size()).filter(func(i: int) -> bool:
		return i != car_index and not is_pursuit_car(i))
	pool.shuffle()
	if rival_class == 1:
		return pool
	var class_of := func(i: int) -> int:
		var c := hs_class(i)
		return c if c >= 0 else 4
	var mine: int = class_of.call(car_index)
	var by_gap := {}
	for i: int in pool:
		var gap := absi(class_of.call(i) - mine)
		if not by_gap.has(gap):
			by_gap[gap] = []
		by_gap[gap].append(i)
	var out := []
	var gaps := by_gap.keys()
	gaps.sort()
	for gap: int in gaps:
		if gap > 0 and out.size() >= n:
			break
		out.append_array(by_gap[gap])
	return out


func player_car_data() -> Object:
	return own_car(car_index)


# ------------------------------------------------------------------ settings

func save_settings() -> void:
	# Mid-circuit, the player's own race settings, not the circuit's.
	var circuit := {}
	if not _before_circuit.is_empty():
		circuit = _race_settings()
		_set_race_settings(_before_circuit)
	var cf := ConfigFile.new()
	cf.set_value("game", "data_root", data_root)
	cf.set_value("game", "mode", mode)
	cf.set_value("game", "track", track_id)
	cf.set_value("game", "car", car_index)
	cf.set_value("game", "car_id", cars[car_index].id if car_index < cars.size() else "")
	cf.set_value("game", "laps", laps)
	cf.set_value("game", "opponents", opponents)
	cf.set_value("game", "upgrades", upgrades)
	cf.set_value("game", "paints", paints)
	cf.set_value("game", "driver", driver)
	cf.set_value("game", "rival_upgrades", rival_upgrades)
	cf.set_value("game", "rival_class", rival_class)
	cf.set_value("game", "intro", intro_flyby)
	cf.set_value("game", "hud", hud_style)
	cf.set_value("game", "hud_on", hud_on)
	cf.set_value("game", "hud_hidden", PackedStringArray(hud_hidden))
	cf.set_value("game", "layout", layout)
	cf.set_value("game", "traffic", traffic)
	cf.set_value("game", "kmh", units_kmh)
	cf.set_value("game", "night", night)
	cf.set_value("game", "weather", weather)
	cf.set_value("game", "damage", damage)
	cf.set_value("game", "manual_gears", manual_gears)
	cf.set_value("game", "tops_down", tops_down)
	cf.set_value("game", "quality", quality)
	cf.set_value("game", "camera", camera_mode)
	cf.set_value("game", "fullscreen", fullscreen)
	cf.set_value("game", "vsync", vsync)
	cf.set_value("game", "volume", volume)
	cf.set_value("game", "music_volume", music_volume)
	cf.set_value("game", "sfx_volume", sfx_volume)
	cf.set_value("game", "ambience_volume", ambience_volume)
	cf.set_value("game", "voice_volume", voice_volume)
	cf.save(SETTINGS_PATH)
	if not circuit.is_empty():
		_set_race_settings(circuit)


## The game was "NFS3 Revival" until it took in High Stakes, and Godot keeps user:// under
## the project's name: the first time, the settings, tournament progress and rendered track
## postcards are copied over from the old name's folder (which is left as it was).
func _migrate_user_dir() -> void:
	var here := ProjectSettings.globalize_path("user://").trim_suffix("/")
	var old := here.get_base_dir().path_join("NFS3 Revival")
	if old == here or FileAccess.file_exists(here.path_join("settings.cfg")) or not DirAccess.dir_exists_absolute(old):
		return
	for f in ["settings.cfg", "career.cfg"]:
		if FileAccess.file_exists(old.path_join(f)):
			DirAccess.copy_absolute(old.path_join(f), here.path_join(f))
	var cards := old.path_join("postcards")
	if DirAccess.dir_exists_absolute(cards):
		DirAccess.make_dir_recursive_absolute(here.path_join("postcards"))
		for f in DirAccess.get_files_at(cards):
			DirAccess.copy_absolute(cards.path_join(f), here.path_join("postcards").path_join(f))


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	# Hand-edited or stale files: take only values of the right type and range.
	data_root = str(cf.get_value("game", "data_root", ""))
	mode = clampi(_int(cf, "mode", mode), 0, MODE_NAMES.size() - 1) as Mode
	track_id = str(cf.get_value("game", "track", track_id)).to_lower()
	car_index = maxi(_int(cf, "car", 0), 0)
	_saved_car_id = str(cf.get_value("game", "car_id", ""))
	laps = clampi(_int(cf, "laps", laps), 1, 8)
	opponents = clampi(_int(cf, "opponents", opponents), 0, 7)
	var ups: Variant = cf.get_value("game", "upgrades", {})
	if ups is Dictionary:
		for k in ups:
			if ups[k] is int:
				upgrades[str(k)] = clampi(ups[k], 0, Car.UPGRADES.size())
	rival_upgrades = clampi(_int(cf, "rival_upgrades", rival_upgrades), 0, 2)
	rival_class = clampi(_int(cf, "rival_class", rival_class), 0, 1)
	var pts: Variant = cf.get_value("game", "paints", {})
	if pts is Dictionary:
		for k in pts:
			if pts[k] is int:
				paints[str(k)] = clampi(pts[k], 0, 15)
	driver = clampi(_int(cf, "driver", driver), 0, 10)
	intro_flyby = _bool(cf, "intro", intro_flyby)
	hud_style = clampi(_int(cf, "hud", hud_style), 0, 2)
	hud_on = _bool(cf, "hud_on", hud_on)
	var hidden: Variant = cf.get_value("game", "hud_hidden", PackedStringArray())
	if hidden is PackedStringArray:
		hud_hidden.clear()
		for id in hidden:
			if HUD_WIDGETS.has(id):
				hud_hidden.append(id)
	layout = clampi(_int(cf, "layout", layout), 0, LAYOUTS.size() - 1)
	traffic = _bool(cf, "traffic", traffic)
	units_kmh = _bool(cf, "kmh", units_kmh)
	night = _bool(cf, "night", night)
	weather = _bool(cf, "weather", weather)
	damage = _bool(cf, "damage", damage)
	manual_gears = _bool(cf, "manual_gears", manual_gears)
	tops_down = _bool(cf, "tops_down", tops_down)
	quality = clampi(_int(cf, "quality", quality), 0, QUALITY_NAMES.size() - 1) as Quality
	camera_mode = clampi(_int(cf, "camera", camera_mode), 0, ChaseCamera.MODES.size() - 1)
	fullscreen = _bool(cf, "fullscreen", fullscreen)
	vsync = _bool(cf, "vsync", vsync)
	volume = clampi(_int(cf, "volume", volume), 0, 10)
	music_volume = clampi(_int(cf, "music_volume", music_volume), 0, 10)
	sfx_volume = clampi(_int(cf, "sfx_volume", sfx_volume), 0, 10)
	ambience_volume = clampi(_int(cf, "ambience_volume", sfx_volume), 0, 10)
	voice_volume = clampi(_int(cf, "voice_volume", voice_volume), 0, 10)


func _int(cf: ConfigFile, key: String, fallback: int) -> int:
	var v: Variant = cf.get_value("game", key, fallback)
	return int(v) if v is int or v is float else fallback


func _bool(cf: ConfigFile, key: String, fallback: bool) -> bool:
	var v: Variant = cf.get_value("game", key, fallback)
	return v if v is bool else fallback


# ------------------------------------------------------------------ graphics

## A race plays its track's song, everything else the menu music.
func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	music.play_for(track_id if scene.scene_file_path.ends_with("race.tscn") else "")


## Window mode, v-sync and the volumes, from the settings.
func apply_display() -> void:
	AudioServer.set_bus_volume_linear(0, volume / 10.0)
	for b: Array in [[BUS_MUSIC, music_volume], [BUS_SFX, sfx_volume], [BUS_AMBIENCE, ambience_volume], [BUS_VOICE, voice_volume]]:
		AudioServer.set_bus_volume_linear(_bus(b[0]), b[1] / 10.0)
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	var have := DisplayServer.window_get_mode()
	if (have == DisplayServer.WINDOW_MODE_FULLSCREEN or have == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN) != fullscreen:
		DisplayServer.window_set_mode(want)


## The bus's index, made (sending to Master) the first time it's asked for.
func _bus(bus_name: StringName) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		i = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, &"Master")
	return i


## F11 / Alt+Enter toggle fullscreen anywhere.
func _unhandled_key_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k and k.pressed and not k.echo and (k.physical_keycode == KEY_F11 or (k.physical_keycode == KEY_ENTER and k.alt_pressed)):
		fullscreen = not fullscreen
		apply_display()
		save_settings()
		get_viewport().set_input_as_handled()

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
			# MSAA smooths only the triangles' edges; SMAA on top catches the rest (the cars'
			# alpha cut-outs, the lines drawn in the low-res skins and textures).
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA


# ------------------------------------------------------------------ input

func _setup_input() -> void:
	_bind("accelerate", [KEY_UP, KEY_W], [JOY_BUTTON_A], JOY_AXIS_TRIGGER_RIGHT)
	_bind("brake", [KEY_DOWN, KEY_S], [JOY_BUTTON_X], JOY_AXIS_TRIGGER_LEFT)
	_bind("steer_left", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT])
	_bind("steer_right", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT])
	_bind("handbrake", [KEY_SPACE], [JOY_BUTTON_B])
	_bind("shift_up", [KEY_SHIFT], [JOY_BUTTON_RIGHT_STICK])
	_bind("shift_down", [KEY_CTRL], [JOY_BUTTON_LEFT_STICK])
	_bind("camera", [KEY_C], [JOY_BUTTON_Y])
	_bind("look_back", [KEY_B], [JOY_BUTTON_LEFT_SHOULDER])
	_bind("reset_car", [KEY_R], [JOY_BUTTON_BACK])
	_bind("horn", [KEY_H], [JOY_BUTTON_RIGHT_SHOULDER])
	_bind("mirror", [KEY_M], [])
	_bind("headlights", [KEY_L], [JOY_BUTTON_DPAD_UP])
	_bind("high_beam", [KEY_K], [JOY_BUTTON_DPAD_DOWN])
	_bind("soft_top", [KEY_T], [])
	_bind("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])
	_bind("handling_feel", [KEY_F6], [])
	_bind("toggle_hud", [KEY_F1], [])
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


# ------------------------------------------------------------------ tournaments

## High Stakes' tournaments (HsCareer), kept in user://career.cfg: your money, the cars you
## own (the garage: bought from the dealer at High Stakes' own prices, or won), each one's
## upgrades and crash damage, the circuits' best results and the tournaments opened. Entry
## fees, cars, upgrades and repairs cost money; prizes and selling cars bring it in.
const CAREER_PATH := "user://career.cfg"
const CAREER_START_MONEY := 25000
const CIRCUIT_POINTS := [10, 8, 6, 5, 4, 3, 2, 1]
## Mending a wreck costs this share of the car's price (less damage, less). A car sells for
## this share of what was paid for it and its upgrades, less what mending it would cost.
const REPAIR_SHARE := 0.15
const RESALE_SHARE := 0.6

var career_path := CAREER_PATH   # (tests point this elsewhere)
var career_money := CAREER_START_MONEY
var career_won := {}        # circuit id -> best final place (1 = won; 1..3 a trophy)
var career_open := {}       # tournament ids opened by winning others
var career_garage := {}     # car id -> {upgrade: 0..3, damage: 0..1}, the cars you own
## The circuit being raced, between its races: {tournament, circuit, race (index), field
## ([{car, upgrade}]), points (key -> points; key "you" or the field index), last (key ->
## place in the last race), gained (key -> points from it), out (field indices knocked out,
## in order), you_out}. {} outside a tournament. Ending it puts back the race settings the
## circuit took over (_before_circuit).
var circuit_run := {}:
	set(v):
		if v.is_empty() and not _before_circuit.is_empty():
			_set_race_settings(_before_circuit)
			_before_circuit = {}
		circuit_run = v
## The player's own race settings while a circuit has them (_race_settings()), {} otherwise:
## what save_settings writes in their place, so a circuit's never become the player's.
var _before_circuit := {}
var menu_screen := ""       # the front end's screen to come back to after a race ("tournaments")
var _career: HsCareer
var _career_loaded := false


func career_data() -> HsCareer:
	if not _career_loaded:
		_career_loaded = true
		if hs_root != "":
			_career = HsCareer.load_dir(find_ci(hs_root, "text"))
		var cf := ConfigFile.new()
		if cf.load(career_path) == OK:
			var m: Variant = cf.get_value("career", "money", career_money)
			career_money = int(m) if m is int or m is float else career_money
			var w: Variant = cf.get_value("career", "won", {})
			career_won = w if w is Dictionary else {}
			var o: Variant = cf.get_value("career", "open", {})
			career_open = o if o is Dictionary else {}
			var g: Variant = cf.get_value("career", "garage", {})
			if g is Dictionary:
				for id in g:
					if g[id] is Dictionary:
						career_garage[str(id)] = {"upgrade": clampi(int(g[id].get("upgrade", 0)), 0, Car.UPGRADES.size()),
							"damage": clampf(float(g[id].get("damage", 0.0)), 0.0, 1.0)}
	return _career


func save_career() -> void:
	var cf := ConfigFile.new()
	cf.set_value("career", "money", career_money)
	cf.set_value("career", "won", career_won)
	cf.set_value("career", "open", career_open)
	cf.set_value("career", "garage", career_garage)
	cf.save(career_path)


## Starts the tournaments over: the starting money, no cars, nothing won or opened.
func new_career() -> void:
	career_money = CAREER_START_MONEY
	career_won = {}
	career_open = {}
	career_garage = {}
	circuit_run = {}
	save_career()


func tournament_open(t: Dictionary) -> bool:
	return t.open or career_open.has(t.id)


## Every circuit of tournament `t` won: its trophy.
func tournament_won(t: Dictionary) -> bool:
	return not t.circuits.is_empty() and t.circuits.all(func(id) -> bool: return int(career_won.get(id, 99)) == 1)


## Circuit `cid`'s trophy: 1 gold, 2 silver, 3 bronze for its best finish; 0 none.
func circuit_trophy(cid: int) -> int:
	var p := int(career_won.get(cid, 0))
	return p if p >= 1 and p <= 3 else 0


## Whether car `i` may enter circuit `c`, by its restriction as High Stakes checks it: its
## class, that class and under (AAA the top, so "under" is the higher numbers), a model, a
## make (by man.dat's names); a loaner circuit takes none of yours. Never a police car.
func circuit_allows(c: Dictionary, i: int) -> bool:
	if is_pursuit_car(i):
		return false
	var v: int = c.value
	match c.restriction:
		HsCareer.CLASS:
			return hs_class(i) == v
		HsCareer.CLASS_AND_UNDER:
			return hs_class(i) >= v
		HsCareer.MODEL:
			return car_serial(i) == v
		HsCareer.MANUFACTURER:
			if v < 0 or v >= _career.makes.size():
				return false
			var make := _career.makes[v]
			var info: Dictionary = car_spec(i).info if "info" in car_spec(i) else {}
			return str(info.get("make", "")).begins_with(make) or str(cars[i].name).begins_with(make)
		HsCareer.LOANER:
			return false
	return true


## Serials (fedata's) of the bonus cars High Stakes keeps out of its fields (the bonus
## Camaro and Porsche, La Niña, the MHRT Commodore), and of the three the Tournament of
## Champions races instead (CLK-GTR, McLaren F1 GTR, the bonus Porsche).
const BONUS_SERIALS := [41, 42, 39, 24]
const CHAMPION_SERIALS := [18, 2, 42]
const CHAMPIONS_CIRCUIT := 32


## With High Stakes' cars installed the tournaments deal and sell only those.
func _hs_cars_only() -> bool:
	return range(cars.size()).any(func(k: int) -> bool: return is_hs_car(k))


# ------------------------------------------------------------------ the garage

func _car_by_id(id: String) -> int:
	for i in cars.size():
		if cars[i].id == id:
			return i
	return -1


func owns(i: int) -> bool:
	return i >= 0 and i < cars.size() and career_garage.has(cars[i].id)


## The cars you own (indices), cheapest first.
func garage_cars() -> Array:
	var out := []
	for id: String in career_garage:
		var i := _car_by_id(id)
		if i >= 0:
			out.append(i)
	out.sort_custom(func(a: int, b: int) -> bool: return career_price(a) < career_price(b))
	return out


## The cars the dealer sells: those the tournaments deal into their fields (High Stakes'
## own when installed; not the police's, the bonus cars or the Knockout), cheapest first.
## The bonus cars are won.
func dealer_cars() -> Array:
	var hs_only := _hs_cars_only()
	var out := []
	for i in cars.size():
		if is_pursuit_car(i) or (hs_only and not is_hs_car(i)) or hs_class(i) < 0 or car_serial(i) in BONUS_SERIALS:
			continue
		out.append(i)
	out.sort_custom(func(a: int, b: int) -> bool: return career_price(a) < career_price(b))
	return out


## What the dealer asks for car `i`: High Stakes' price for it (fedata), or for a car
## without one what High Stakes asks for one rated as it is.
func career_price(i: int) -> int:
	var p := int(car_rank(i).get("price", 0))
	if p > 0:
		return p
	return roundi(20000.0 * pow(1.22, car_rating(i) - 3) / 1000.0) * 1000


## What upgrade `level` (1..3) of car `i` costs (fedata's figures); 0 if it takes none.
func upgrade_cost(i: int, level: int) -> int:
	if not car_rank(i).get("upgradable", false) or level < 1 or level > Car.UPGRADES.size():
		return 0
	var costs: Array = car_rank(i).get("upgrade_costs", [])
	if level - 1 < costs.size() and int(costs[level - 1]) > 0:
		return int(costs[level - 1])
	return roundi(career_price(i) * [0.2, 0.25, 0.4][level - 1] / 50.0) * 50


func garage_upgrade(i: int) -> int:
	return int(career_garage[cars[i].id].upgrade) if owns(i) else 0


func garage_damage(i: int) -> float:
	return float(career_garage[cars[i].id].damage) if owns(i) else 0.0


func set_garage_damage(i: int, d: float) -> void:
	if owns(i):
		career_garage[cars[i].id].damage = clampf(d, 0.0, 1.0)


## What mending car `i` costs, to the $10.
func repair_cost(i: int) -> int:
	return roundi(garage_damage(i) * career_price(i) * REPAIR_SHARE / 10.0) * 10


## What the dealer gives for car `i`, to the $100.
func resale_value(i: int) -> int:
	var paid := career_price(i)
	for level in range(1, garage_upgrade(i) + 1):
		paid += upgrade_cost(i, level)
	return maxi(roundi(paid * RESALE_SHARE / 100.0) * 100 - repair_cost(i), 0)


## Buys car `i` from the dealer: "" done, else why not.
func buy_car(i: int) -> String:
	if owns(i):
		return "You already own it"
	if not i in dealer_cars():
		return "Not for sale: win it"
	var price := career_price(i)
	if career_money < price:
		return "$%s: not enough money" % TournamentPanel.money(price)
	career_money -= price
	career_garage[cars[i].id] = {"upgrade": 0, "damage": 0.0}
	save_career()
	return ""


func sell_car(i: int) -> String:
	if not owns(i):
		return "Not yours to sell"
	career_money += resale_value(i)
	career_garage.erase(cars[i].id)
	save_career()
	return ""


## Fits car `i`'s next upgrade.
func upgrade_car(i: int) -> String:
	var level := garage_upgrade(i) + 1
	var cost := upgrade_cost(i, level)
	if not owns(i):
		return "Not yours"
	if cost <= 0:
		return "No more upgrades for this car" if level > 1 else "This car takes no upgrades"
	if career_money < cost:
		return "$%s: not enough money" % TournamentPanel.money(cost)
	career_money -= cost
	career_garage[cars[i].id].upgrade = level
	save_career()
	return ""


func repair_car(i: int) -> String:
	var cost := repair_cost(i)
	if cost <= 0:
		return "Nothing to repair"
	if career_money < cost:
		return "$%s: not enough money" % TournamentPanel.money(cost)
	career_money -= cost
	set_garage_damage(i, 0.0)
	save_career()
	return ""


## The car with serial `serial` into the garage (High Stakes' own first); already owning
## one, its price instead. Returns its index, or -1 if there's no such car.
func award_car(serial: int) -> int:
	var found := -1
	for i in cars.size():
		if not is_pursuit_car(i) and car_serial(i) == serial and (found < 0 or is_hs_car(i)):
			found = i
	if found < 0:
		return -1
	if owns(found):
		career_money += career_price(found)
	else:
		career_garage[cars[found].id] = {"upgrade": 0, "damage": 0.0}
	return found


## Nothing to race and not enough money to buy anything: only a new career goes on.
func career_broke() -> bool:
	if not career_garage.is_empty():
		return false
	var cheapest := dealer_cars()
	return cheapest.is_empty() or career_money < career_price(cheapest[0])


## The player's car's upgrade level in this race: its garage's in a tournament.
func player_upgrade() -> int:
	return garage_upgrade(car_index) if not circuit_run.is_empty() else upgrade_of(car_index)


# ------------------------------------------------------------------ circuits

## Circuit `c`'s opponents, [{car, upgrade}], dealt as High Stakes deals them. The cars:
## every one the circuit allows at each upgrade level it takes (only High Stakes' own when
## they're installed, not the bonus cars, not the Knockout), ranked by their rating there,
## weakest first; an open circuit leaves out those rated over one above your car. Each
## opponent takes the one at a percentile drawn from the circuit's third mam row: mid - 50
## plus two throws of 0..50, thrown again until it's within min..max. A car race's
## opponent drives the car it's for; the Tournament of Champions deals its race cars in
## order. As in the original the same car can come up more than once.
func deal_field(c: Dictionary) -> Array:
	var hs_only := _hs_cars_only()
	var champions: bool = c.id == CHAMPIONS_CIRCUIT
	var mine := car_rating(car_index, garage_upgrade(car_index))
	var entries := []
	for i in cars.size():
		if is_pursuit_car(i) or (hs_only and not is_hs_car(i)):
			continue
		var serial := car_serial(i)
		if champions:
			if not serial in CHAMPION_SERIALS:
				continue
		elif c.type == HsCareer.TYPE_CAR_RACE and c.award >= 0:
			if serial != c.award:
				continue
		elif serial in BONUS_SERIALS or hs_class(i) < 0 or not circuit_allows(c, i):
			continue
		for level in (Car.UPGRADES.size() + 1 if car_rank(i).get("upgradable", false) else 1):
			var rating := car_rating(i, level)
			if c.restriction == HsCareer.OPEN and rating > mine + 1:
				continue
			entries.append({"car": i, "upgrade": level, "rating": rating})
	entries.shuffle()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.rating < b.rating)
	var field := []
	var row := _career.mam_row(c.mam[2])
	for k in c.opponents:
		if entries.is_empty():
			field.append({"car": car_index, "upgrade": garage_upgrade(car_index)})
			continue
		var at := mini(k, entries.size() - 1)
		if not champions:
			var roll := row.y
			for tries in 100:
				roll = row.y - 50 + randi() % 51 + randi() % 51
				if roll >= row.x and roll <= row.z:
					break
			roll = clampi(roll, row.x, row.z)
			at = clampi(roundi((entries.size() - 1) * roll * 0.01), 0, entries.size() - 1)
		field.append({"car": entries[at].car, "upgrade": entries[at].upgrade})
	return field


## Enters circuit `cid` of tournament `t` with the chosen car (one of yours): pays the fee,
## deals the field and sets up its first race. "" on success, else why not.
func start_circuit(t: Dictionary, cid: int) -> String:
	var c: Dictionary = _career.circuits.get(cid, {})
	if c.is_empty():
		return "Unknown circuit"
	if not owns(car_index):
		return "Buy the car first"
	if not circuit_allows(c, car_index):
		var only := _career.restriction_text(c)
		return "%s only" % only if only != "" else "Not with this car"
	if career_money < c.fee:
		return "Entry fee $%s: not enough money" % TournamentPanel.money(c.fee)
	for r: Dictionary in c.races:
		if HsCareer.track_id(r.track) == "":
			return "A track of this circuit isn't installed"
	career_money -= int(c.fee)
	var field := deal_field(c)
	circuit_run = {"tournament": t.id, "circuit": cid, "race": 0, "field": field, "points": {}, "last": {}, "gained": {},
		"out": [], "you_out": false}
	save_career()
	_apply_circuit_race()
	return ""


## On to the circuit's next race (after circuit_race_done): its settings.
func next_circuit_race() -> void:
	_apply_circuit_race()


## The race settings for the circuit's current race.
func _apply_circuit_race() -> void:
	var c: Dictionary = _career.circuits[circuit_run.circuit]
	var r: Dictionary = c.races[circuit_run.race]
	if _before_circuit.is_empty():
		_before_circuit = _race_settings()
	mode = Mode.SINGLE_RACE
	track_id = HsCareer.track_id(r.track)
	layout = int(r.reverse) + 2 * int(r.mirror)
	night = r.night
	weather = r.weather
	laps = c.laps
	# The circuit record has no traffic field (what was read as one is the restriction).
	traffic = false
	opponents = circuit_run.field.size() - circuit_run.out.size()


## The race settings a circuit takes over, as _set_race_settings() takes them.
func _race_settings() -> Dictionary:
	return {"mode": mode, "track_id": track_id, "layout": layout, "night": night, "weather": weather,
		"laps": laps, "traffic": traffic, "opponents": opponents}


func _set_race_settings(s: Dictionary) -> void:
	for k: String in s:
		set(k, s[k])


## The rivals still in: {car (index), upgrade, key (field index)}.
func circuit_rivals() -> Array:
	var out := []
	for k in circuit_run.field.size():
		if not k in circuit_run.out:
			out.append({"car": circuit_run.field[k].car, "upgrade": circuit_run.field[k].upgrade, "key": k})
	return out


## The grid of the circuit's next race, pole first (keys: "you" or field indices). The first
## race you start at the back, as in High Stakes; after it the standings set the grid, the
## leader on pole, a tie to whoever beat the other last time.
func circuit_grid() -> Array:
	var keys: Array = circuit_rivals().map(func(r: Dictionary) -> int: return r.key)
	if circuit_run.race == 0:
		return keys + ["you"]
	keys.append("you")
	var pts: Dictionary = circuit_run.points
	var last: Dictionary = circuit_run.last
	keys.sort_custom(func(a, b) -> bool:
		if int(pts.get(a, 0)) != int(pts.get(b, 0)):
			return int(pts.get(a, 0)) > int(pts.get(b, 0))
		return int(last.get(a, 99)) < int(last.get(b, 99)))
	return keys


## The opponents' pace as an AI skill.
func circuit_skill() -> float:
	var c: Dictionary = _career.circuits[circuit_run.circuit]
	return lerpf(0.88, 1.08, clampf((c.pace - 0.4) / 2.5, 0.0, 1.0))


## A rival's name in the standings: its car (the field can hold the same car twice).
func circuit_name(key: Variant) -> String:
	return "You" if key is String else cars[circuit_run.field[key].car].name


## A race of the circuit is over, `order` its finishing order (keys: "you" or field indices).
## Scores it, knocks out the last in a knockout, and when the circuit is over pays the prize
## (or gives the car), opens what it opens. Returns {standings: [{key, points, gained, race
## (this race's place, 0 not in it), out}] in order, done, place, prize, award (car index
## or -1), message, trophy (1..3 for a podium at the end, else 0), tournament (the name of
## the tournament this completes, or ""), opened: [names of the tournaments it opens]}.
func circuit_race_done(order: Array) -> Dictionary:
	var c: Dictionary = _career.circuits[circuit_run.circuit]
	var pts: Dictionary = circuit_run.points
	circuit_run.last = {}
	circuit_run.gained = {}
	for i in order.size():
		var gain: int = CIRCUIT_POINTS[i] if i < CIRCUIT_POINTS.size() else 0
		pts[order[i]] = int(pts.get(order[i], 0)) + gain
		circuit_run.last[order[i]] = i + 1
		circuit_run.gained[order[i]] = gain
	var message := ""
	if c.type == HsCareer.TYPE_KNOCKOUT and order.size() > 1:
		var last = order[order.size() - 1]
		if last is String:
			circuit_run.you_out = true
			message = "You're knocked out"
		else:
			circuit_run.out.append(last)
			message = "%s knocked out" % circuit_name(last)
	circuit_run.race += 1
	var done: bool = circuit_run.race >= c.races.size() or circuit_run.you_out or \
		(c.type == HsCareer.TYPE_KNOCKOUT and circuit_run.out.size() >= circuit_run.field.size())
	# The standings: by points; in a knockout those still in first, then those knocked out,
	# the later out the higher.
	var out_order: Array = circuit_run.out.duplicate()
	if circuit_run.you_out:
		out_order.append("you")
	out_order.reverse()
	var keys: Array = (["you"] + range(circuit_run.field.size())).filter(func(k) -> bool: return not k in out_order)
	keys.sort_custom(func(a, b) -> bool:
		if int(pts.get(a, 0)) != int(pts.get(b, 0)):
			return int(pts.get(a, 0)) > int(pts.get(b, 0))
		return int(circuit_run.last.get(a, 99)) < int(circuit_run.last.get(b, 99)))
	keys += out_order
	var place := keys.find("you") + 1
	if c.type == HsCareer.TYPE_CAR_RACE:
		place = order.find("you") + 1
	var standings := []
	for k in keys:
		standings.append({"key": k, "points": int(pts.get(k, 0)), "gained": int(circuit_run.gained.get(k, 0)),
			"race": int(circuit_run.last.get(k, 0)), "out": k in out_order})
	var result := {"standings": standings, "done": done, "place": place, "prize": 0, "award": -1, "message": message,
		"trophy": 0, "tournament": "", "opened": []}
	if not done:
		return result
	if place - 1 < c.prizes.size():
		result.prize = int(c.prizes[place - 1])
	career_money += result.prize
	if place == 1 and c.award >= 0:
		result.award = award_car(c.award)
		if result.award >= 0:
			message = "%s is yours" % cars[result.award].name
	var had_trophy := tournament_won_by_id(circuit_run.tournament)
	career_won[c.id] = mini(int(career_won.get(c.id, 99)), place)
	result.trophy = place if place <= 3 and c.type != HsCareer.TYPE_CAR_RACE else 0
	# Every circuit of the tournament won: its trophy, and it opens the next ones.
	for t in _career.tournaments:
		if t.id == circuit_run.tournament and tournament_won(t):
			if not had_trophy:
				result.tournament = t.name
			for u in t.unlocks:
				if not career_open.has(u):
					career_open[u] = true
					for o in _career.tournaments:
						if o.id == u:
							result.opened.append(o.name)
	save_career()
	result.message = message
	return result


func tournament_won_by_id(id: int) -> bool:
	for t in _career.tournaments:
		if t.id == id:
			return tournament_won(t)
	return false
