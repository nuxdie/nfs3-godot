class_name Speech
extends AudioStreamPlayer
## NFS3's voices (gamedata/audio/speech/english/*.bnk, MicroTalk-coded: EaMicroTalk): one
## line at a time, queued, each decoded on a worker thread before it plays (a couple of
## seconds of speech takes ~60 ms to decode). The race owns one. What the banks hold (found by
## transcribing them):
##   lapeng    0..2 best lap; 3, 4 lap record; 5, 6 final lap; 7..12 "lap 2".."lap 7";
##             16..18 first ("you've won the race"); 19, 20 second; 21, 22 third; 23..27 fourth
##             to eighth; 28 "you placed last"
##   copspch   0..9 the cop's loudhailer ("Police! Pull over!"); 16..18 a warning; 19 the final
##             warning; 32..34 under arrest
##   dispNN    the dispatcher on track NN (00..03, 08): 16..27 calls to all units / unit NN;
##             33, 34 acknowledged; 36..43 "go ahead, unit NN"; 48..51 backup; 52, 53 spikes
##             cleared; 54, 55 spike strip deployed; 58, 59 roadblock cleared; 60 roadblock set up;
##             64.., 96.. "at" / "from" places along the track
##   offNNa..c the officers on track NN, three voices: 16..23 "<unit> to County" (the units the
##             dispatcher's 20..27 and 36..43 name, in order); 26, 27 the suspect crashed; 30, 31
##             my car's disabled; 32..35 lost him; 36..39 got him again; 40..43 backup; 44..47
##             apprehended; 49 missed the spikes; 50 ran the roadblock; 51, 52 ask for a
##             roadblock; 53, 54 roadblock set; 55, 56 ask for spikes; 57..59 spikes down;
##             60..63 "he's going more than 100 / 120 / 140 / 160"
##   vocasst   the co-driver: 1..7 "first place!".."seventh place!", 8 "last place!", 9 eighth;
##             10, 11 "you're in the lead!"; 17..30 / 33..44 "you're N seconds back / behind";
##             48..73 speeds, 50..300; 74 "you're cookin'!"
##   helicop   (High Stakes) the helicopter: 0..2 "Air One / Air 3 / Rotor 1 to Central";
##             34..37 airborne, on the way; 64 lost him; 69..76 "I have the suspect in sight";
##             81, 82 he ran the roadblock; 96..105 "he's doing more than 100".."280"
## High Stakes has lapeng, vocasst, copspch and cnteng too, the same lines under the same
## numbers, and one radio for all tracks: "dispatch" (as dispNN but spikes deployed at 56, 57,
## roadblock cleared 72..74 and set 75; "go ahead, Air One / Air 3 / Rotor 1" at 44..46) and
## "officer1".."officer3" (as offNNa..c). NFS3's banks are used when it's installed, else
## High Stakes' stand in (resolve()). Nothing without either.

## Hot Pursuit 2's speech (Hp2Speech, .dat files in Audio/Speech/English/*.viv) says them on
## its own tracks (`hp2`), as hp2_line finds them; what it hasn't got of the police radio
## goes unsaid there rather than in another game's voices. Its officers are 19, 27 and 31
## (offNNa..c), its dispatcher "County", the helicopter "Rotor One", the announcer frontend.viv's.

## dispNN's patches -> High Stakes' "dispatch".
const HS_DISPATCH := {54: 56, 55: 57, 58: 72, 59: 73, 60: 75}

const MAX_QUEUE := 5      # older lines are dropped rather than pile up behind the talk

## On Hot Pursuit 2's tracks its voices say the lines it has (_hp2_line), NFS3's or High
## Stakes' the rest; with neither of those installed, HP2's stand in everywhere.
var hp2 := false

var _banks := {}          # name -> EaBnk, or null if missing
var _hp2_dats := {}       # "radio/19arrest" -> Hp2Speech, or null if missing
var _hp2_index := {}      # speech .viv name -> its directory (Viv.index)
var _queue: Array = []    # [bank name, patch, volume_db]
var _task := -1
var _decoding: Array = []
var _result: AudioStream


func _ready() -> void:
	bus = Game.BUS_VOICE
	finished.connect(_next)


## Queues one line; `patches` may be a list to pick one from at random.
func say(bank: String, patches: Variant, volume_db := 0.0) -> void:
	var p: int = patches.pick_random() if patches is Array else patches
	var r := resolve(bank, p)
	if r.is_empty():
		return
	_queue.append([r[0], r[1], volume_db])
	while _queue.size() > MAX_QUEUE:
		_queue.pop_front()
	if not playing and _task < 0:
		_next()


## Whether a line is playing or waiting.
func busy() -> bool:
	return playing or _task >= 0 or not _queue.is_empty()


## [bank, patch] to play for NFS3's `bank` and `patch`, standing in High Stakes' radio for
## NFS3's where it has to; [] if neither game has the line.
func resolve(bank: String, patch: int) -> Array:
	if hp2:
		var h := _hp2_line(bank, patch)
		if not h.is_empty() or hp2_owns(bank):
			return h
	var b := _bank(bank)
	# NFS3's bank, or High Stakes' when NFS3's is missing or lacks the line (the helicopter's).
	if b == null or not b.has(patch):
		if bank.begins_with("disp"):
			bank = "dispatch"
			patch = HS_DISPATCH.get(patch, patch)
		elif bank.begins_with("off"):
			bank = "officer%d" % ("abc".find(bank.right(1)) + 1)
		b = _bank(bank)
	if b and b.has(patch):
		return [bank, patch]
	return [] if hp2 or Game.hp2_root == "" else _hp2_line(bank, patch)


func _bank(name: String) -> EaBnk:
	if not _banks.has(name):
		var path := DataPath.find_ci(Game.data_root, "gamedata/audio/speech/english/%s.bnk" % name)
		if path == "":
			path = DataPath.find_ci(Game.hs_root, "audio/speech/english/%s.bnk" % name)
		_banks[name] = EaBnk.parse(FileAccess.get_file_as_bytes(path)) if path != "" else null
	return _banks[name]


func _next() -> void:
	if _queue.is_empty() or _task >= 0:
		return
	_decoding = _queue.pop_front()
	var name: String = _decoding[0]
	var p: int = _decoding[1]
	if name.begins_with("hp2:"):
		var s := _hp2_dat(name.trim_prefix("hp2:"))
		_task = WorkerThreadPool.add_task(func() -> void: _result = s.clip(p))
		return
	var b := _bank(name)
	# Only this node touches the speech banks, and one task at a time, so the bank's cache is safe.
	_task = WorkerThreadPool.add_task(func() -> void: _result = b.stream(p))


func _process(_dt: float) -> void:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	if _result:
		stream = _result
		volume_db = _decoding[2]
		play()
	else:
		_next()


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


# ---------------------------------------------------------------- Hot Pursuit 2

## Hot Pursuit 2's officers for offNNa..c.
const HP2_OFFICERS := ["19", "27", "31"]


## HP2's .dat for NFS3's `bank` and `patch` and which of its clips: ["<viv>/<dat>", clips]
## where clips is null (any), a list, or Vector2i(field, value) (Hp2Speech.clips_where); []
## if it hasn't the line.
static func hp2_line(bank: String, patch: int) -> Array:
	if bank.begins_with("off"):
		var o: String = HP2_OFFICERS[maxi("abc".find(bank.right(1)), 0)]
		if patch >= 16 and patch <= 23:
			return ["radio/%saddcount" % o, Vector2i(1, (patch - 16) % 6)]   # "27 County"
		var dat: String = {26: "suscrash", 27: "suscrash", 32: "suslost", 33: "suslost", 34: "suslost",
			35: "suslost", 36: "bpidb", 37: "bpidb", 38: "gothimagain", 39: "bpidb", 40: "backupreq",
			41: "backupreq", 42: "backupreqa", 43: "backupreqa", 44: "arresta", 45: "arresta",
			46: "arresta", 47: "arresta", 50: "roadblockfailb", 51: "roadblockreq", 52: "roadblockreq",
			53: "rdblokset", 54: "rdblokseta", 55: "spikestripreq", 56: "spikestripreq",
			57: "spikestripset", 58: "spikestripset", 59: "spikestripset"}.get(patch, "")
		if dat != "":
			return ["radio/" + o + dat, null]
		if patch >= 60 and patch <= 63:
			return ["radio/%sspeedb" % o, Vector2i(0, patch - 60)]   # "he's going 100 plus"
		return []
	if bank.begins_with("disp") or bank == "dispatch":
		if patch >= 36 and patch <= 43:
			return ["radio/dispadddown", Vector2i(1, (patch - 36) % 6)]   # "copy 27"
		if patch >= 44 and patch <= 46:
			return ["radio/disprtrdeployed", null]
		if patch == 52 or patch == 53:
			return ["radio/dispspkstripsetb", null]
		if patch == 58 or patch == 59:
			return ["radio/disprdblkupdate", null]
		return []
	match bank:
		"copspch":
			if patch < 20:   # the loudhailer and its warnings: "cease and desist!"
				return ["radio/bullhorn", null]
			if patch >= 32 and patch <= 34:
				return ["radio/19arrest", Vector2i(1, 0)]   # "you are under arrest"
		"helicop":
			if patch <= 2:
				return ["radio/rotoraddcounty", null]
			if patch >= 34 and patch <= 37:
				return ["radio/rotorsusacts", [2, 3, 8, 10]]   # "he's not stopping"...
			if patch >= 69 and patch <= 76:
				return ["radio/rotorsusacts", [5, 6, 7, 9]]    # "I've got him on infrared"
			if patch >= 96 and patch <= 105:
				return ["radio/rotorsusacts", [8, 10, 12]]     # "he's really moving down there"
		"lapeng":
			if patch <= 4:
				return ["frontend/duringracea", [0, 1, 2, 3]]   # "best lap!"
			if patch <= 6:
				return ["frontend/duringracea", [4, 5, 6, 7, 8]]   # "final lap!"
			if patch >= 16 and patch <= 28:
				# endRaceA: 0..3, 13..15, 53..55 first, then one or two per place (the rest
				# name "Player One" / "Player 2"); endRaceB 0, 1, 4 last.
				var by_place := {16: [0, 1, 2, 3, 13, 14, 15, 53, 54, 55], 19: [21, 22], 21: [28, 29, 30],
					23: [33], 24: [37, 38], 25: [41], 26: [44], 27: [47]}
				var k: int = patch
				while k >= 16 and not by_place.has(k):
					k -= 1
				if patch == 28:
					return ["frontend/endraceb", [0, 1, 4]]
				return ["frontend/endracea", by_place[k]]
	return []


## ["hp2:<viv>/<dat>", clip] for NFS3's `bank` and `patch`, or [] if HP2 has no such line.
func _hp2_line(bank: String, patch: int) -> Array:
	var line := hp2_line(bank, patch)
	if line.is_empty():
		return []
	var s := _hp2_dat(line[0])
	if s == null:
		return []
	var clips: Array
	if line[1] is Vector2i:
		clips = s.clips_where(line[1].x, line[1].y)
	else:
		clips = line[1] if line[1] is Array else range(s.count())
	clips = clips.filter(func(c: int) -> bool: return c < s.count())
	return ["hp2:" + line[0], clips.pick_random()] if not clips.is_empty() else []


## Whether HP2 has a say in `bank` on its tracks: the police radio is all its (or silent).
static func hp2_owns(bank: String) -> bool:
	return bank.begins_with("off") or bank.begins_with("disp") or bank in ["copspch", "helicop"]


func _hp2_dat(key: String) -> Hp2Speech:
	if not _hp2_dats.has(key):
		var viv := key.get_slice("/", 0)
		if not _hp2_index.has(viv):
			var path := DataPath.find_ci(Game.hp2_root, "Audio/Speech/English/%s.viv" % viv) if Game.hp2_root != "" else ""
			_hp2_index[viv] = [path, Viv.index(path) if path != "" else {}]
		var at: Array = _hp2_index[viv]
		var entry: Variant = at[1].get(key.get_slice("/", 1) + ".dat")
		var s := Hp2Speech.parse(Viv.read_entry(at[0], entry)) if entry != null else null
		if s:
			if not _hp2_index.has("speechdr"):
				var path := DataPath.find_ci(Game.hp2_root, "Audio/Speech/English/speechdr.viv")
				_hp2_index["speechdr"] = [path, Viv.index(path) if path != "" else {}]
			var hdr: Array = _hp2_index.speechdr
			var h: Variant = hdr[1].get("files\\%s\\%s.hdr" % [viv, key.get_slice("/", 1)])
			if h != null:
				s.set_header(Viv.read_entry(hdr[0], h))
		_hp2_dats[key] = s
	return _hp2_dats[key]

