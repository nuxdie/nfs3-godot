class_name MusicPlayer
extends AudioStreamPlayer
## The games' music, streamed: both games' race songs shuffled together in a race (starting
## with the track's own song), both games' menu tunes shuffled together in the menus; when
## a song has played through the next one follows. Each song's title and artist slide in
## briefly (NowPlaying). Blocks are decoded as the stream needs them, so a song costs no
## loading time and little memory. Game owns one, across scenes.
##
## NFS3 (gamedata/audio/pc): <song>rock.mus / <song>tech.mus with their .lin, one song per
## track (the tracks without one borrow another), rock or techno picked at random each race;
## show1..8.mus with their .map for the menus (show8 is a copy of show1); srv2.mus, a rock
## song the game never plays.
## High Stakes (Data/Audio/Music): game1..16.asf in races; menu1..4.asf, show.asf (the
## showcase), garage1.asf and credits.asf in the menus.
##
## Songs are named "nfs3:<file>" or "hs:<file>" (no extension); only those whose files are
## there play.

## NFS3 track -> its song's file prefix.
const NFS3_SONGS := {
	"trk000": "home", "trk001": "lost", "trk002": "atla", "trk003": "alpi", "trk004": "home",
	"trk005": "lost", "trk006": "atla", "trk007": "alpi", "trk008": "empr",
}
## High Stakes' versions of the NFS3 tracks, by folder, play the same songs.
const HS_REMAKES := {
	"hometown": "trk000", "redrock": "trk001", "atlantic": "trk002", "rockypas": "trk003",
	"country": "trk004", "lostcany": "trk005", "aquatica": "trk006", "summit": "trk007",
	"empire": "trk008",
}
## Artist and title of each song, by file, from RacingSoundtracks.com's lists of the two
## games' PC files.
const SONGS := {
	"nfs3:homerock": ["Saki Kaskas", "Little Sweaty Sow"],
	"nfs3:hometech": ["Rom Di Prisco", "Hydrus 606"],
	"nfs3:lostrock": ["Matt Ragan", "Snorkeling Cactus Weasels"],
	"nfs3:losttech": ["Rom Di Prisco", "Cetus 808"],
	"nfs3:atlarock": ["Matt Ragan", "Rear Flutterblast #19"],
	"nfs3:atlatech": ["Rom Di Prisco", "Aquila 303"],
	"nfs3:alpirock": ["Matt Ragan", "Snow Bags"],
	"nfs3:alpitech": ["Saki Kaskas", "Knossos"],
	"nfs3:emprrock": ["Saki Kaskas", "Flimsy"],
	"nfs3:emprtech": ["Alistair Hirst", "Warped"],
	"nfs3:srv2": ["Matt Ragan", "Gear Grinder"],
	"nfs3:show1": ["Alistair Hirst", "Whacked"],
	"nfs3:show2": ["Rom Di Prisco", "Romulus 3"],
	"nfs3:show3": ["Rom Di Prisco", "Minotaur"],
	"nfs3:show4": ["Rom Di Prisco", "Pi"],
	"nfs3:show5": ["Rom Di Prisco", "Triton-1"],
	"nfs3:show6": ["Crispin Hands", "Monster"],
	"nfs3:show7": ["Alistair Hirst", "Whipped"],
	"hs:game1": ["Saki Kaskas", "Amorphous Being"],
	"hs:game2": ["Lunatic Calm", "Roll the Dice"],
	"hs:game3": ["Rom Di Prisco", "Rock This"],
	"hs:game4": ["Dylan Rhymes", "Naked and Ashamed (Remix)"],
	"hs:game5": ["Junkie XL", "War"],
	"hs:game6": ["Crispin Hands", "Bionic"],
	"hs:game7": ["The Funk Lab", "I Am Electro"],
	"hs:game8": ["Rom Di Prisco", "Liquid Plasma"],
	"hs:game9": ["Junkie XL", "Fight"],
	"hs:game10": ["DJ Icey", "Clutch"],
	"hs:game11": ["Surreal Madrid", "Insanity Sauce"],
	"hs:game12": ["Dastrix", "Dude in the Moon (Luna Mix)"],
	"hs:game13": ["Junkie XL", "Def Beat"],
	"hs:game14": ["The Experiment", "Cost of Freedom"],
	"hs:game15": ["Rom Di Prisco", "Road Warrior"],
	"hs:game16": ["Junkie XL", "No Remorse"],
	"hs:menu1": ["Rom Di Prisco", "Cygnus Rift"],
	"hs:menu2": ["Rom Di Prisco", "Paradigm Shifter"],
	"hs:menu3": ["Rom Di Prisco", "Photon Rez"],
	"hs:menu4": ["Rom Di Prisco", "Quantum Singularity"],
	"hs:show": ["Saki Kaskas", "Callista"],
	"hs:garage1": ["Saki Kaskas", "Bulbular Swirl"],
	"hs:credits": ["Crispin Hands", "Runnin'"],
}
const RACE_SONGS: Array[String] = [
	"nfs3:homerock", "nfs3:hometech", "nfs3:lostrock", "nfs3:losttech", "nfs3:atlarock",
	"nfs3:atlatech", "nfs3:alpirock", "nfs3:alpitech", "nfs3:emprrock", "nfs3:emprtech",
	"nfs3:srv2",
	"hs:game1", "hs:game2", "hs:game3", "hs:game4", "hs:game5", "hs:game6", "hs:game7",
	"hs:game8", "hs:game9", "hs:game10", "hs:game11", "hs:game12", "hs:game13", "hs:game14",
	"hs:game15", "hs:game16",
]
const MENU_SONGS: Array[String] = [
	"nfs3:show1", "nfs3:show2", "nfs3:show3", "nfs3:show4", "nfs3:show5", "nfs3:show6",
	"nfs3:show7",
	"hs:menu1", "hs:menu2", "hs:menu3", "hs:menu4", "hs:show", "hs:garage1", "hs:credits",
]
const BUFFER_S := 0.5
const FADE_S := 1.0
## A song shorter than this plays its loop again before the next one (some NFS3 techno
## songs run barely a minute straight through).
const MIN_SONG_S := 120.0

var now_playing := NowPlaying.new()

var _music: EaMusic
var _playback: AudioStreamGeneratorPlayback
var _pending := PackedVector2Array()
var _pending_at := 0
var _key := ""          # what's playing: "race:<track>" or "menu"
var _fade := 1.0        # fading out the old song before the new one starts
var _next: EaMusic
var _next_song := ""
var _pool: Array[String] = []    # the set the songs come from
var _queue: Array[String] = []   # what's still to play of it, in order
var _song := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps playing over the pause menu
	bus = Game.BUS_MUSIC
	add_child(now_playing)


## The track's song (a new pick each race) and then all the race songs shuffled, or for ""
## the menu tunes shuffled.
func play_for(track_id: String) -> void:
	var key := "race:" + track_id if track_id != "" else "menu"
	if key == _key and key == "menu" and _music:
		return
	_key = key
	_pool.assign((RACE_SONGS if track_id != "" else MENU_SONGS).filter(_exists))
	_queue.clear()
	var first := _race_song(track_id) if track_id != "" else ""
	var m := _open(first) if first != "" else null
	if m == null and not _pool.is_empty():
		first = _take_next()
		m = _open(first)
	# The rest of the set, shuffled, before any repeats.
	_queue.assign(_pool.filter(func(s: String) -> bool: return s != first and not _queue.has(s)))
	_queue.shuffle()
	if _music == null or not playing:
		_begin(m, first)
	else:
		# Fade the old song out first (_process starts this one when it's gone).
		_next = m
		_next_song = first
		_fade = minf(_fade, 0.999)


func stop_music() -> void:
	_key = ""
	_next = null
	_pool.clear()
	_queue.clear()
	_begin(null, "")


func _begin(m: EaMusic, song: String) -> void:
	stop()
	_music = m
	_pending = PackedVector2Array()
	_pending_at = 0
	_fade = 1.0
	if m == null:
		_song = ""
		return
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = m.rate
	gen.buffer_length = BUFFER_S
	stream = gen
	play()
	_playback = get_stream_playback()
	_announce(song, 1.0)


func _announce(song: String, delay := 0.0) -> void:
	_song = song
	var info: Array = SONGS.get(song, ["", ""])
	now_playing.show_title(info[1], info[0], delay)


func _process(dt: float) -> void:
	if _fade < 1.0:
		_fade -= dt / FADE_S
		if _fade <= 0.0:
			_begin(_next, _next_song)
			_next = null
	volume_db = linear_to_db(maxf(clampf(_fade, 0.0, 1.0), 0.0001))
	if _music == null or _playback == null or not playing:
		return
	# Top the buffer up, a decoded block at a time.
	var room := _playback.get_frames_available()
	while room > 0:
		if _pending_at >= _pending.size():
			_pending = _music.next_block()
			_pending_at = 0
			if _pending.is_empty():
				_song_over()
				return
		var n := mini(room, _pending.size() - _pending_at)
		if _pending_at == 0 and n == _pending.size():
			_playback.push_buffer(_pending)
		else:
			_playback.push_buffer(_pending.slice(_pending_at, _pending_at + n))
		_pending_at += n
		room -= n


## The song played through (or its data ran out): on to the next, straight after it when
## it plays at the same rate, else with a fresh stream.
func _song_over() -> void:
	var ok := _music.finished and _music.played > 0
	var rate := _music.rate
	_music = null
	if not ok or _pool.is_empty() or _fade < 1.0:   # (fading out: the new song is on its way)
		return
	var song := _take_next()
	var m := _open(song)
	if m == null:
		return
	if m.rate == rate:
		_music = m
		_announce(song)
	else:
		_begin(m, song)


## The next song off the queue, reshuffling the pool when it runs out (never the one
## just played twice in a row).
func _take_next() -> String:
	if _queue.is_empty():
		_queue = _pool.duplicate()
		_queue.shuffle()
		if _queue.size() > 1 and _queue[0] == _song:
			_queue.push_back(_queue.pop_front())
	var s: String = _queue.pop_front()
	return s


## The track's own NFS3 song (its High Stakes remake's too), or "".
func _race_song(track_id: String) -> String:
	var nfs3 := track_id
	if Game.is_hs_track(track_id):
		nfs3 = HS_REMAKES.get(track_id.trim_prefix(Game.HS_PREFIX), "")
	if not NFS3_SONGS.has(nfs3):
		return ""
	var song: String = "nfs3:" + NFS3_SONGS[nfs3] + ("rock" if randf() < 0.5 else "tech")
	return song if _exists(song) else ""


func _exists(song: String) -> bool:
	var file := song.get_slice(":", 1)
	if song.begins_with("nfs3:"):
		var dir := _nfs3_dir()
		return dir != "" and DataPath.find_ci(dir, file + ".mus") != ""
	return Game.hs_root != "" and DataPath.find_ci(Game.hs_root, "audio/music/" + file + ".asf") != ""


## The song, set up to end after one time through (at least MIN_SONG_S), or null.
func _open(song: String) -> EaMusic:
	var file := song.get_slice(":", 1)
	var m := _nfs3(file) if song.begins_with("nfs3:") else _hs(file + ".asf")
	if m:
		m.min_length_s = MIN_SONG_S
	return m


func _nfs3_dir() -> String:
	return DataPath.find_ci(Game.data_root, "gamedata/audio/pc") if Game.data_root != "" else ""


## An NFS3 song, with its .lin if it has one (the song straight through), else its .map.
func _nfs3(song: String) -> EaMusic:
	var dir := _nfs3_dir()
	if dir == "":
		return null
	var mus := DataPath.find_ci(dir, song + ".mus")
	var map := DataPath.find_ci(dir, song + ".lin")
	if map == "":
		map = DataPath.find_ci(dir, song + ".map")
	return EaMusic.open_mus(mus, map)


func _hs(file: String) -> EaMusic:
	if Game.hs_root == "":
		return null
	return EaMusic.open_asf(DataPath.find_ci(Game.hs_root, "audio/music/" + file))
