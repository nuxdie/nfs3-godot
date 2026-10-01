class_name GameSounds
## The games' shared sound banks, from NFS3 (gamedata/audio/sfx) or else High Stakes
## (Data/Audio/Sfx); both number their patches the same way. Loaded once per data folder.
##   gen.bnk     0 road noise; 10 horn; 29..37 impacts, light to heavy; 40 body scraping
##               along the ground or a wall; tyres sliding: 41 on gravel, 42 on tarmac,
##               43 on snow, 44 on grass, 45 on wet tarmac
##   siren.bnk   0 the police siren
##   genocar.bnk, otruck.bnk   engines (0) and horns (1) for traffic: cars, and trucks and buses
##   rain.bnk    4 rain on the car; 6, 7 thunder
##   speech/english/cnteng.bnk (NFS3 only)   0..3 the countdown: "three", "two", "one", "go"
## (The numbers follow High Stakes' AudioCmn_SFX / ChooseImpactSample / ChooseLoopedSample.)
##
## Porsche Unleashed (GameData/Sounds) numbers its own way; its cars use its sounds, and they
## stand in for the others' when neither NFS3 nor High Stakes is there (what the exe doesn't
## say was told from the sounds themselves):
##   snd_coll.bnk  (`pu`, PU_PATCHES) 6, 8 the siren's wail, 9 its yelp; 10 a car's horn, 11 a
##               truck's; 16..28 the road under the wheels (17 tarmac, 21 rough); 31 wind;
##               tyres sliding: 40..47, by surface (nfs5.exe 0x4a93c0: 42, 46, 47 squeal on
##               tarmac, 44 and 45 duller, 40, 41, 43 on loose ground); 48..126 knocks and
##               crashes in threes, one set per thing hit (nfs5.exe 0x4a8e60, 64..66 when it's
##               nothing in particular), each patch's layers split by how hard (tags 0x01..0x02,
##               0..127); 118 a long metal scrape
##   zzzwzzz.viv   each engine set's <set>lden / ldex.bnk, the cars you aren't driving (Nfs5Car)
##   fesfx.bnk     the menus' stereo blips: 3, 6 and 8 the shortest (PU_MENU)
##
## Hot Pursuit 2 (Audio/Sfx) keeps High Stakes' gen.bnk numbers for the road (0), horn (10),
## scraping (40) and the tyres (41..45), most of them the same recordings; its crashes are
## its own, 32..36 (HP2_IMPACTS, light to heavy by their length, each two layers played
## together: the crunch and a thump), and 80..117 are things by the road being hit
## (boomobj.ini's colpatch). Its cars use it (`hp2`), and its siren.bnk (`hp2_siren`, 0 the wail).

const ROAD := 0
const HORN := 10
const IMPACT_LIGHT := 29
const IMPACT_MEDIUM := 32
const IMPACT_HEAVY := 33
const IMPACT_HARD := 34
const IMPACT_WALL := 37
const SCRAPE := 40
const TYRES_GRAVEL := 41
const TYRES_TARMAC := 42
const TYRES_SNOW := 43
const TYRES_WET := 45
const SIREN := 0
const RAIN := 4
const THUNDER := [6, 7]
## Porsche Unleashed's snd_coll.bnk patches for the ones above.
const PU_PATCHES := {ROAD: 17, HORN: 10, SCRAPE: 118, TYRES_GRAVEL: 41, TYRES_TARMAC: 42,
	TYRES_SNOW: 40, TYRES_WET: 44}
const PU_SIREN := 6
const PU_TRUCK_HORN := 11
const PU_IMPACTS := [64, 65, 66]
## Hot Pursuit 2's gen.bnk crashes, for IMPACT_LIGHT, IMPACT_HARD, IMPACT_MEDIUM, IMPACT_WALL, IMPACT_HEAVY.
const HP2_IMPACTS := {IMPACT_LIGHT: 32, IMPACT_HARD: 33, IMPACT_MEDIUM: 34, IMPACT_WALL: 35, IMPACT_HEAVY: 36}
## Its fesfx.bnk's patches for MenuSounds' CLICK, SELECT and TICK.
const PU_MENU := [6, 3, 8]

var gen: EaBnk
var siren: EaBnk
var rain: EaBnk
var countdown: EaBnk
var fe: EaBnk          # fesfx.bnk, the menus' clicks (MenuSounds)
var traffic_car: EaBnk
var traffic_truck: EaBnk
var pu: EaBnk          # Porsche Unleashed's snd_coll.bnk (PU_PATCHES)
var pu_fe: EaBnk       # its fesfx.bnk (PU_MENU)
var hp2: EaBnk         # Hot Pursuit 2's gen.bnk (HP2_IMPACTS)
var hp2_siren: EaBnk

static var _cached: GameSounds
static var _cached_key := "-"


## Null with none of the games' data.
static func shared() -> GameSounds:
	var key := Game.data_root + "|" + Game.hs_root + "|" + Game.pu_root + "|" + Game.hp2_root
	if key == _cached_key:
		return _cached
	_cached_key = key
	var s := GameSounds.new()
	s.gen = _bank("gen.bnk")
	s.siren = _bank("siren.bnk")
	s.rain = _bank("rain.bnk")
	s.fe = _bank("fesfx.bnk")
	s.traffic_car = _bank("genocar.bnk")
	s.traffic_truck = _bank("otruck.bnk")
	var cnt := DataPath.find_ci(Game.data_root, "gamedata/audio/speech/english/cnteng.bnk")
	if cnt != "":
		s.countdown = EaBnk.parse(FileAccess.get_file_as_bytes(cnt))
	if Game.pu_root != "":
		s.pu = _pu_bank("snd_coll.bnk")
		s.pu_fe = _pu_bank("fesfx.bnk")
	if Game.hp2_root != "":
		s.hp2 = _hp2_bank("gen.bnk")
		s.hp2_siren = _hp2_bank("siren.bnk")
	_cached = s if s.gen or s.siren or s.rain or s.countdown or s.pu or s.hp2 else null
	return _cached


static func _bank(file: String) -> EaBnk:
	for path in [DataPath.find_ci(Game.data_root, "gamedata/audio/sfx/" + file),
			DataPath.find_ci(Game.hs_root, "audio/sfx/" + file)]:
		if path != "":
			var b := EaBnk.parse(FileAccess.get_file_as_bytes(path))
			if b:
				return b
	return null


static func _pu_bank(file: String) -> EaBnk:
	var path := DataPath.find_ci(Game.pu_root, "Sounds/" + file)
	return EaBnk.parse(FileAccess.get_file_as_bytes(path)) if path != "" else null


static func _hp2_bank(file: String) -> EaBnk:
	var path := DataPath.find_ci(Game.hp2_root, "Audio/Sfx/" + file)
	return EaBnk.parse(FileAccess.get_file_as_bytes(path)) if path != "" else null


## Plays `stream` once, not placed in the scene (speech), then frees the player.
static func say(parent: Node, stream: AudioStream, volume_db := 0.0) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	p.bus = Game.BUS_VOICE
	p.finished.connect(p.queue_free)
	parent.add_child(p)
	p.play()


## Plays `stream` once from `parent`'s position (following it), then frees the player.
static func play_once(parent: Node3D, stream: AudioStream, volume_db: float, pitch := 1.0, bus := Game.BUS_SFX) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = 12.0
	p.max_distance = 250.0
	p.bus = bus
	p.finished.connect(p.queue_free)
	parent.add_child(p)
	p.play()
