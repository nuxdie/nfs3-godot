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

var gen: EaBnk
var siren: EaBnk
var rain: EaBnk
var countdown: EaBnk
var fe: EaBnk          # fesfx.bnk, the menus' clicks (MenuSounds)
var traffic_car: EaBnk
var traffic_truck: EaBnk

static var _cached: GameSounds
static var _cached_key := "-"


## Null with neither game's data.
static func shared() -> GameSounds:
	var key := Game.data_root + "|" + Game.hs_root
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
	_cached = s if s.gen or s.siren or s.rain or s.countdown else null
	return _cached


static func _bank(file: String) -> EaBnk:
	for path in [DataPath.find_ci(Game.data_root, "gamedata/audio/sfx/" + file),
			DataPath.find_ci(Game.hs_root, "audio/sfx/" + file)]:
		if path != "":
			var b := EaBnk.parse(FileAccess.get_file_as_bytes(path))
			if b:
				return b
	return null


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
