class_name MusicPlayer
extends AudioStreamPlayer
## The games' music, streamed: all the games' race songs shuffled together in a race (starting
## with the track's own song), all their menu tunes shuffled together in the menus; when
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
## Porsche Unleashed (GameData/Music/zzzymus.viv): .asf songs named "<file>-<title>-<artist>",
## game01..14 in races, menu01..05 in the menus (win, lose and vic, the results screen's
## stings, aren't played).
## Hot Pursuit 2 (Audio/Music, music.ini naming them): track0..14 in races (the licensed
## songs and the game's own), track15..22, instrumental versions of the first eight, in
## the menus. The same split-block EA ADPCM as Porsche Unleashed's, at 32 kHz.
##
## Gran Turismo 2 (MUSIC.DAT on its disc image, Gt2Music): CD-XA audio, a song per channel
## ("gt2:<channel>"). The disc names none of them: the US release's six race songs (after
## RacingSoundtracks.com's list) are told apart by length and, for the two of 3:38, by tempo
## (Sex Type Thing 134 bpm, I Think I'm Paranoid 113). The other eight, a minute or two
## each, are its front-end pieces (Isamu Ohira's): five matched by their spectral motion
## against the previews of the GRAN TURISMO 2 ORIGINAL GAME SOUNDTRACK album, three unnamed;
## its jingles, seconds long, aren't played. Its credits songs aren't on this disc.
## Its GT Mode screens' and Arcade mode's tunes are sequenced (Gt2Seq: sound/spu_02..10.seq,
## arcade.seq, played on the game's own instruments), "gt2:<file>", in the menus. Five matched
## to the album the same way; the rest go by their screen (SUBMANIAC's names for them).
##
## Songs are named "nfs3:<file>", "hs:<file>", "pu:<file>", "hp2:<file>" (no extension) or
## "gt2:<channel>"; only those whose files are there play.
##
## The menu's music browser plays any of them (play_list), pauses, skips back and forth
## (skip, remembering what played) and shows where the song is (position_s, length_s).

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
	"pu:game01": ["Morphadron", "Rezidue"],
	"pu:game02": ["Captain Ginger", "MetroGnome"],
	"pu:game03": ["Cypher", "Choose Your Enemy"],
	"pu:game04": ["Morphadron", "Let the Music Move You"],
	"pu:game05": ["Morphadron", "The UK Sound"],
	"pu:game06": ["Cypher", "Sentient"],
	"pu:game07": ["Morphadron", "R U Ready"],
	"pu:game08": ["Morphadron", "Rock This Place"],
	"pu:game09": ["Cypher", "Twin"],
	"pu:game10": ["Morphadron", "Funky Phreakout"],
	"pu:game11": ["Cypher", "Injector"],
	"pu:game12": ["Morphadron", "The Moebius"],
	"pu:game13": ["Morphadron", "Activator"],
	"pu:game14": ["Morphadron", "Stealth Run"],
	"pu:menu01": ["Captain Ginger", "Psychonaught"],
	"pu:menu02": ["Cypher", "Aircon"],
	"pu:menu03": ["Morphadron", "Dr. Know"],
	"pu:menu04": ["Morphadron", "Cold Fusion Power"],
	"pu:menu05": ["Cypher", "Orion is Lonely"],
	"hp2:track0": ["Bush", "The People That We Love"],
	"hp2:track1": ["The Buzzhorn", "Ordinary"],
	"hp2:track2": ["Course of Nature", "Wall of Shame"],
	"hp2:track3": ["Hot Action Cop", "Fever For The Flava"],
	"hp2:track4": ["Hot Action Cop", "Going Down On It"],
	"hp2:track5": ["Pulse Ultra", "Build Your Cages"],
	"hp2:track6": ["Rush", "One Little Victory"],
	"hp2:track7": ["Uncle Kracker", "Keep It Coming"],
	"hp2:track8": ["Matt Ragan", "Bundle of Clang"],
	"hp2:track9": ["Matt Ragan", "Cone Of Silence"],
	"hp2:track10": ["Matt Ragan", "Flam Dance"],
	"hp2:track11": ["Humble Brothers", "Black Hole"],
	"hp2:track12": ["Humble Brothers", "Brakestand"],
	"hp2:track13": ["Humble Brothers", "Sphere"],
	"hp2:track14": ["ROM", "Cykloid"],
	"hp2:track15": ["Bush", "The People That We Love (Instrumental)"],
	"hp2:track16": ["The Buzzhorn", "Ordinary (Instrumental)"],
	"hp2:track17": ["Course of Nature", "Wall of Shame (Instrumental)"],
	"hp2:track18": ["Hot Action Cop", "Fever For The Flava (Instrumental)"],
	"hp2:track19": ["Hot Action Cop", "Going Down On It (Instrumental)"],
	"hp2:track20": ["Pulse Ultra", "Build Your Cages (Instrumental)"],
	"hp2:track21": ["Rush", "One Little Victory (Instrumental)"],
	"hp2:track22": ["Uncle Kracker", "Keep It Coming (Instrumental)"],
	"gt2:1": ["Apollo 440", "Cold Rock The Mic"],
	"gt2:2": ["Garbage", "I Think I'm Paranoid"],
	"gt2:3": ["Rob Zombie", "Dragula (Hot Rod Herman Remix)"],
	"gt2:4": ["Soul Coughing", "Super Bon Bon"],
	"gt2:5": ["Stone Temple Pilots", "Sex Type Thing"],
	"gt2:6": ["The Crystal Method", "Now Is The Time (Millennium Mix)"],
	# (Its front-end pieces, matched against the soundtrack album's previews; three matched none.)
	"gt2:7": ["Isamu Ohira", "Welcome Back G.T."],
	"gt2:8": ["Isamu Ohira", "The \"Real\" Motorious City"],
	"gt2:9": ["Isamu Ohira", "You Made It!"],
	"gt2:10": ["Isamu Ohira", "From The East"],
	"gt2:18": ["Isamu Ohira", "Gold Rush"],
	"gt2:19": ["Isamu Ohira", "Front-end piece 1"], "gt2:20": ["Isamu Ohira", "Front-end piece 2"],
	"gt2:21": ["Isamu Ohira", "Front-end piece 3"],
	"gt2:arcade": ["Isamu Ohira", "Windroad"],
	"gt2:spu_02": ["Isamu Ohira", "Car Wash theme"],
	"gt2:spu_03": ["Isamu Ohira", "From The East"],
	"gt2:spu_04": ["Isamu Ohira", "North City theme"],
	"gt2:spu_05": ["Isamu Ohira", "South City theme"],
	"gt2:spu_06": ["Isamu Ohira", "West City theme"],
	"gt2:spu_07": ["Isamu Ohira", "Get Ready?"],
	"gt2:spu_08": ["Isamu Ohira", "Soul of Garage"],
	"gt2:spu_09": ["Isamu Ohira", "Map theme"],
	"gt2:spu_10": ["Isamu Ohira", "Poker Face"],
}
const RACE_SONGS: Array[String] = [
	"nfs3:homerock", "nfs3:hometech", "nfs3:lostrock", "nfs3:losttech", "nfs3:atlarock",
	"nfs3:atlatech", "nfs3:alpirock", "nfs3:alpitech", "nfs3:emprrock", "nfs3:emprtech",
	"nfs3:srv2",
	"hs:game1", "hs:game2", "hs:game3", "hs:game4", "hs:game5", "hs:game6", "hs:game7",
	"hs:game8", "hs:game9", "hs:game10", "hs:game11", "hs:game12", "hs:game13", "hs:game14",
	"hs:game15", "hs:game16",
	"pu:game01", "pu:game02", "pu:game03", "pu:game04", "pu:game05", "pu:game06", "pu:game07",
	"pu:game08", "pu:game09", "pu:game10", "pu:game11", "pu:game12", "pu:game13", "pu:game14",
	"hp2:track0", "hp2:track1", "hp2:track2", "hp2:track3", "hp2:track4", "hp2:track5",
	"hp2:track6", "hp2:track7", "hp2:track8", "hp2:track9", "hp2:track10", "hp2:track11",
	"hp2:track12", "hp2:track13", "hp2:track14",
	"gt2:1", "gt2:2", "gt2:3", "gt2:4", "gt2:5", "gt2:6",
]
const MENU_SONGS: Array[String] = [
	"nfs3:show1", "nfs3:show2", "nfs3:show3", "nfs3:show4", "nfs3:show5", "nfs3:show6",
	"nfs3:show7",
	"hs:menu1", "hs:menu2", "hs:menu3", "hs:menu4", "hs:show", "hs:garage1", "hs:credits",
	"pu:menu01", "pu:menu02", "pu:menu03", "pu:menu04", "pu:menu05",
	"hp2:track15", "hp2:track16", "hp2:track17", "hp2:track18", "hp2:track19", "hp2:track20",
	"hp2:track21", "hp2:track22",
	"gt2:7", "gt2:8", "gt2:9", "gt2:10", "gt2:18", "gt2:19", "gt2:20", "gt2:21",
	"gt2:arcade", "gt2:spu_02", "gt2:spu_03", "gt2:spu_04", "gt2:spu_05", "gt2:spu_06",
	"gt2:spu_07", "gt2:spu_08", "gt2:spu_09", "gt2:spu_10",
]
const BUFFER_S := 0.5
const FADE_S := 1.0
## A song shorter than this plays its loop again before the next one (some NFS3 techno
## songs run barely a minute straight through).
const MIN_SONG_S := 120.0

signal song_changed(song: String)

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
var _in_order := false           # the pool plays through in its order (a list picked in the browser)
var _history: Array[String] = [] # what played before, latest last (for skip back)
var _going_back := false
var _pu_viv := ""                # Porsche Unleashed's music archive, and its directory
var _pu_index := {}


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
	_in_order = false
	stream_paused = false
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
	_switch(m, first)


## `songs` from now on: from `first` on in their order, or (`shuffled`) at random after
## `first` ("" for the current song to play on, or a random one if none is).
func play_list(songs: Array[String], first := "", shuffled := false) -> void:
	_key = "list"
	_in_order = not shuffled
	_pool.assign(songs.filter(_exists))
	if _pool.is_empty():
		return
	if first == "" and _music == null:
		first = _pool.pick_random()
	var from := _pool.find(first if first != "" else _song)
	_queue.assign(_pool.slice(from + 1) + _pool.slice(0, maxi(from, 0)) if from >= 0 else _pool)
	_queue.erase(first if first != "" else _song)
	if shuffled:
		_queue.shuffle()
	if first != "":
		_switch(_open(first), first)
	elif stream_paused:
		stream_paused = false


func shuffled() -> bool:
	return not _in_order


## To the next song (1), or (-1) back to the start of this one, or to the one before if it
## has only just begun.
func skip(dir: int) -> void:
	if _pool.is_empty():
		return
	var song := ""
	if dir < 0:
		if position_s() > 3.0 or _history.is_empty():
			song = _song
		else:
			song = _history.pop_back()
			if _song != "":
				_queue.push_front(_song)
			_going_back = true
	else:
		song = _take_next()
	_switch(_open(song), song)


func set_paused(p: bool) -> void:
	if p and _next:   # (fading over to it: straight there)
		_begin(_next, _next_song)
		_next = null
	stream_paused = p and _music != null


func paused() -> bool:
	return stream_paused


## The song playing, or on its way in.
func current_song() -> String:
	return _next_song if _next else _song


## How far into the song it's heard (s).
func position_s() -> float:
	if _music == null or _playback == null or _next:
		return 0.0
	var pushed := _music.played - (_pending.size() - _pending_at)
	var buffered := int(BUFFER_S * _music.rate) - _playback.get_frames_available()
	return maxf(float(pushed - buffered) / _music.rate, 0.0)


## The song's length as it'll play (s), or 0 where that isn't known ahead (NFS3's sections).
func length_s() -> float:
	var m := _next if _next else _music
	if m == null or m.length_frames <= 0:
		return 0.0
	var once := float(m.length_frames) / m.rate
	return once * ceilf(MIN_SONG_S / once) if once < MIN_SONG_S else once


func available(song: String) -> bool:
	return _exists(song)


## "NFS III", "HIGH STAKES", "PORSCHE", "HOT PURSUIT 2" or "GRAN TURISMO 2" (as Game.GAME_NAMES).
static func game_of(song: String) -> int:
	return 1 if song.begins_with("hs:") else 2 if song.begins_with("pu:") else 3 if song.begins_with("hp2:") \
		else 5 if song.begins_with("gt2:") else 0


## Straight to `m` if nothing's playing, else after fading out what is.
func _switch(m: EaMusic, song: String) -> void:
	if m == null:
		return
	if _music == null or not playing or stream_paused:
		_begin(m, song)
	else:
		# Fade the old song out first (_process starts this one when it's gone).
		_next = m
		_next_song = song
		_fade = minf(_fade, 0.999)


func stop_music() -> void:
	_key = ""
	_next = null
	_pool.clear()
	_queue.clear()
	_begin(null, "")


func _begin(m: EaMusic, song: String) -> void:
	stop()
	stream_paused = false
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
	if _song != "" and _song != song and not _going_back:
		_history.push_back(_song)
		if _history.size() > 50:
			_history.pop_front()
	_going_back = false
	_song = song
	song_changed.emit(song)
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
		if not _in_order:
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
	if song.begins_with("pu:"):
		return _pu_entry(file) != ""
	if song.begins_with("hp2:"):
		return _hp2_path(file) != ""
	if song.begins_with("gt2:"):
		if not file.is_valid_int():
			return Game.gt2_vol() != null and Game.gt2_vol().has("sound/%s.seq" % file)
		return Gt2Music.songs(Game.gt2_vol(), 0.0).has(file.to_int())
	return Game.hs_root != "" and DataPath.find_ci(Game.hs_root, "audio/music/" + file + ".asf") != ""


## The song, set up to end after one time through (at least MIN_SONG_S), or null.
func _open(song: String) -> EaMusic:
	var file := song.get_slice(":", 1)
	var m: EaMusic
	if song.begins_with("nfs3:"):
		m = _nfs3(file)
	elif song.begins_with("pu:"):
		m = _pu(file)
	elif song.begins_with("hp2:"):
		m = EaMusic.open_asf(_hp2_path(file))
	elif song.begins_with("gt2:"):
		m = Gt2Music.open(Game.gt2_vol(), file.to_int()) if file.is_valid_int() else Gt2Seq.open(Game.gt2_vol(), file)
	else:
		m = _hs(file + ".asf")
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


## Porsche Unleashed's song `file`, read out of its archive.
func _pu(file: String) -> EaMusic:
	var entry := _pu_entry(file)
	return EaMusic.open_asf_bytes(Viv.read_entry(_pu_viv, _pu_index[entry])) if entry != "" else null


## The archive's entry for `file` ("game01" -> "game01-rezidue-morphadron"), or "".
func _pu_entry(file: String) -> String:
	var viv := DataPath.find_ci(Game.pu_root, "music/zzzymus.viv") if Game.pu_root != "" else ""
	if viv != _pu_viv:
		_pu_viv = viv
		_pu_index = Viv.index(viv) if viv != "" else {}
	for e: String in _pu_index:
		if e.get_slice("-", 0) == file:
			return e
	return ""


## Hot Pursuit 2's song `file` ("track0"), or "".
func _hp2_path(file: String) -> String:
	return DataPath.find_ci(Game.hp2_root, "audio/music/" + file + ".asf") if Game.hp2_root != "" else ""
