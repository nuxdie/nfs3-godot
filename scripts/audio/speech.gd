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

## dispNN's patches -> High Stakes' "dispatch".
const HS_DISPATCH := {54: 56, 55: 57, 58: 72, 59: 73, 60: 75}

const MAX_QUEUE := 5      # older lines are dropped rather than pile up behind the talk

var _banks := {}          # name -> EaBnk, or null if missing
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
	var b := _bank(bank)
	# NFS3's bank, or High Stakes' when NFS3's is missing or lacks the line (the helicopter's).
	if b == null or not b.has(patch):
		if bank.begins_with("disp"):
			bank = "dispatch"
			patch = HS_DISPATCH.get(patch, patch)
		elif bank.begins_with("off"):
			bank = "officer%d" % ("abc".find(bank.right(1)) + 1)
		b = _bank(bank)
	return [bank, patch] if b and b.has(patch) else []


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
	var b := _bank(_decoding[0])
	var p: int = _decoding[1]
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
