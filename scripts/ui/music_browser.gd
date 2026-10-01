class_name MusicBrowser
extends BrowserBase
## The music: every song found, grouped by game and where it plays (races, menus), with the
## one playing lit. Enter (or a click) plays a song and the list carries on from it in order;
## ←→ skip back and on, Space pauses. Beside the list, what's playing: title, artist, where
## it is in the song and the music's spectrum, with buttons for the same.

const ROW_H := 46.0
const BANDS := 28
const SECTIONS := [["NEED FOR SPEED III", "RACES"], ["NEED FOR SPEED III", "MENUS"], ["HIGH STAKES", "RACES"],
	["HIGH STAKES", "MENUS"], ["PORSCHE UNLEASHED", "RACES"], ["PORSCHE UNLEASHED", "MENUS"],
	["HOT PURSUIT 2", "RACES"], ["HOT PURSUIT 2", "MENUS"]]

var songs: Array[String] = []   # items: every song there is, in the sections' order
## Where the card with what's playing goes, in panel space (the menu sets it).
var card_rect := Rect2()

var _card: Control
var _buttons: HintBar
var _levels := PackedFloat32Array()
var _analyzer: AudioEffectSpectrumAnalyzerInstance
var _analyzer_at := -1


func _init() -> void:
	super()
	title = "MUSIC"
	noun = "songs"
	head_h = 140.0
	var mp := Game.music
	for sec in SECTIONS:
		for s: String in (MusicPlayer.RACE_SONGS if sec[1] == "RACES" else MusicPlayer.MENU_SONGS):
			if _section(s) == sec and mp.available(s):
				songs.append(s)
	total = songs.size()
	var chips := PackedStringArray(["ALL"])
	for g in Game.GAME_NAMES.size():
		if songs.any(func(s: String) -> bool: return MusicPlayer.game_of(s) == g):
			chips.append(Game.GAME_NAMES[g])
	if chips.size() == 2:
		chips = PackedStringArray(["ALL"])
	filters.set_items(chips, 0)
	_levels.resize(BANDS)
	_card = Control.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.draw.connect(_draw_card)
	add_child(_card)
	_buttons = HintBar.new()
	_buttons.font_size = 15
	_card.add_child(_buttons)
	confirmed.connect(_play)
	mp.song_changed.connect(func(_s: String): _refresh_playing())


func hints() -> Array:
	var h: Array = [["↑↓", "BROWSE"], ["ENTER", "PLAY"]]
	if filters.items.size() > 1:
		h.append(["TAB", "GAME"])
	return h + [["", "TYPE TO SEARCH"]]


func open(_item: int) -> void:
	var at := songs.find(Game.music.current_song())
	super(at)
	picked = -1
	_hook_analyzer(true)
	_refresh_playing()


func close() -> void:
	if visible:
		_hook_analyzer(false)
	super()


func _exit_tree() -> void:
	_hook_analyzer(false)


# ------------------------------------------------------------------ playing

## The songs in the list as it's filtered, in order.
func _listed() -> Array[String]:
	var out: Array[String] = []
	for e in entries:
		if e.item >= 0:
			out.append(songs[e.item])
	return out


func _play(i: int) -> void:
	Game.music.play_list(_listed(), songs[i], false)


func _shuffle() -> void:
	Game.music.play_list(_listed(), "", true)
	_refresh_playing()


func _toggle_pause() -> void:
	if Game.music.current_song() == "":
		_shuffle()
	else:
		Game.music.set_paused(not Game.music.paused())
	_refresh_playing()


func _skip(dir: int) -> void:
	Game.music.skip(dir)
	_refresh_playing()


func _refresh_playing() -> void:
	var paused := Game.music.paused()
	_buttons.set_hints([["←", "PREVIOUS", _skip.bind(-1)], ["SPACE", "PLAY" if paused or Game.music.current_song() == "" else "PAUSE",
		_toggle_pause], ["→", "NEXT", _skip.bind(1)], ["", "SHUFFLE", _shuffle]])
	_layout_card()
	_list.queue_redraw()
	_card.queue_redraw()


## A spectrum analyser on the music bus while the list is open.
func _hook_analyzer(on: bool) -> void:
	var bus := AudioServer.get_bus_index(Game.BUS_MUSIC)
	if _analyzer_at >= 0 and bus >= 0 and _analyzer_at < AudioServer.get_bus_effect_count(bus) \
			and AudioServer.get_bus_effect(bus, _analyzer_at) is AudioEffectSpectrumAnalyzer:
		AudioServer.remove_bus_effect(bus, _analyzer_at)
	_analyzer = null
	_analyzer_at = -1
	if on and bus >= 0:
		var fx := AudioEffectSpectrumAnalyzer.new()
		fx.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
		AudioServer.add_bus_effect(bus, fx)
		_analyzer_at = AudioServer.get_bus_effect_count(bus) - 1
		_analyzer = AudioServer.get_bus_effect_instance(bus, _analyzer_at) as AudioEffectSpectrumAnalyzerInstance


# ------------------------------------------------------------------ input

func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	var k := e as InputEventKey
	if k and k.pressed and not k.echo:
		match k.physical_keycode:
			KEY_LEFT, KEY_RIGHT:
				_skip(-1 if k.physical_keycode == KEY_LEFT else 1)
			KEY_SPACE:
				if query != "":   # (a space in the search)
					super(e)
					return
				_toggle_pause()
			KEY_MEDIANEXT, KEY_MEDIAPREVIOUS:
				_skip(1 if k.physical_keycode == KEY_MEDIANEXT else -1)
			KEY_MEDIAPLAY:
				_toggle_pause()
			KEY_Q, KEY_E:
				if query == "":   # the menu's tabs (a search can have them once it's begun)
					return
				super(e)
				return
			_:
				super(e)
				return
		get_viewport().set_input_as_handled()
		return
	if e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_X:
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	super(e)


func _side_step(dir: int, _shift := false, _ctrl := false) -> void:
	_skip(dir)


# ------------------------------------------------------------------ the list

func _section(s: String) -> Array:
	var g := MusicPlayer.game_of(s)
	return [SECTIONS[g * 2][0], "RACES" if MusicPlayer.RACE_SONGS.has(s) else "MENUS"]


func _build_entries() -> Array[Dictionary]:
	var game := filters.items[filters.index]
	var out: Array[Dictionary] = []
	var last := ""
	for i in songs.size():
		var s := songs[i]
		if game != "ALL" and Game.GAME_NAMES[MusicPlayer.game_of(s)] != game:
			continue
		var sec := _section(s)
		var info: Array = MusicPlayer.SONGS.get(s, ["", s])
		if query != "" and not _matches(("%s %s %s %s" % [info[1], info[0], sec[0], sec[1]]).to_lower()):
			continue
		var head := "%s · %s" % sec
		if head != last:
			last = head
			out.append({"item": -1, "text": head})
		out.append({"item": i, "text": info[1]})
	return out


func _layout_entries(w: float) -> float:
	var y := 4.0
	for e in entries:
		var h := 38.0 if e.item < 0 else ROW_H
		e.rect = Rect2(0, y, w - 14, h)
		y += h
	return y + 8.0


func _draw_entry(ci: CanvasItem, e: Dictionary, r: Rect2, focused: bool, hovered: bool) -> void:
	var s := songs[e.item]
	var on := s == Game.music.current_song()
	if focused:
		UiKit.glow(ci, r, 1.0)
	elif hovered:
		UiKit.glow(ci, r, 0.4, UiKit.INK, false)
	ci.draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), Color(1, 1, 1, 0.05))
	var cy := r.get_center().y
	# Playing: three bars bobbing (still while paused); else a note.
	var ix := r.position.x + 16
	if on:
		for b in 3:
			var hb := 5.0 + (9.0 * (0.5 + 0.5 * sin(_time * (7.0 + b * 2.3) + b * 1.7)) if not Game.music.paused() else 3.0 + b * 3.0)
			ci.draw_rect(Rect2(ix + b * 5, cy + 8 - hb, 3, hb), UiKit.ACCENT)
	else:
		var c := Color(UiKit.INK, 0.5 if focused or hovered else 0.25)
		ci.draw_circle(Vector2(ix + 4, cy + 4), 3.2, c, true, -1.0, true)
		ci.draw_line(Vector2(ix + 7, cy + 4), Vector2(ix + 7, cy - 8), c, 1.4)
		ci.draw_line(Vector2(ix + 7, cy - 8), Vector2(ix + 11, cy - 5), c, 1.4)
	var x := ix + 30
	var max_w := r.end.x - x - 12
	var info: Array = MusicPlayer.SONGS.get(s, ["", s])
	var name := str(info[1]).to_upper()
	var fs := UiKit.fit("display", name, max_w, 18, 13)
	ci.draw_string(UiKit.font("display"), Vector2(x, cy + 1), name, HORIZONTAL_ALIGNMENT_LEFT, max_w, fs,
		UiKit.ACCENT if on else (UiKit.INK if focused or hovered else Color(UiKit.INK, 0.85)))
	ci.draw_string(UiKit.font("body"), Vector2(x, cy + 18), info[0], HORIZONTAL_ALIGNMENT_LEFT, max_w, 13, UiKit.INK_DIM)


# ------------------------------------------------------------------ the card

func _layout() -> void:
	super()
	_layout_card()


func _layout_card() -> void:
	if _card == null:
		return
	_card.position = card_rect.position
	_card.size = card_rect.size
	_buttons.position = Vector2(-10, 372)


func _process(dt: float) -> void:
	super(dt)
	if not visible:
		return
	# The spectrum: log-spaced bands, 40 Hz to 14 kHz, rising fast and falling slow.
	var playing := Game.music.current_song() != "" and not Game.music.paused()
	for b in BANDS:
		var v := 0.0
		if _analyzer and playing:
			var f0 := 40.0 * pow(14000.0 / 40.0, float(b) / BANDS)
			var f1 := 40.0 * pow(14000.0 / 40.0, float(b + 1) / BANDS)
			var mag := _analyzer.get_magnitude_for_frequency_range(f0, f1).length()
			v = clampf((linear_to_db(maxf(mag, 1e-6)) + 60.0) / 60.0, 0.0, 1.0)
		_levels[b] = v if v > _levels[b] else maxf(_levels[b] - dt * 1.6, v)
	_card.queue_redraw()
	if Game.music.current_song() != "":
		_list.queue_redraw()


func _draw_card() -> void:
	var c := _card
	var w := c.size.x
	if w < 120:
		return
	var mp := Game.music
	var s := mp.current_song()
	var info: Array = MusicPlayer.SONGS.get(s, ["", ""])
	var off := Game.music_volume == 0
	var status := "MUSIC IS OFF" if off else ("NOTHING PLAYING" if s == "" else ("PAUSED" if mp.paused() else "NOW PLAYING"))
	UiKit.kicker(c, Vector2(0, 18), status, w, UiKit.INK_DIM if s == "" or mp.paused() else UiKit.ACCENT)
	if s == "":
		c.draw_string(UiKit.font("body"), Vector2(0, 66), "Pick a song on the left, or shuffle the list.", HORIZONTAL_ALIGNMENT_LEFT,
			w, 16, UiKit.INK_DIM)
	else:
		var name := str(info[1]).to_upper()
		c.draw_string(UiKit.font("display"), Vector2(-2, 70), name, HORIZONTAL_ALIGNMENT_LEFT, w,
			UiKit.fit("display", name, w, 44, 22), UiKit.INK)
		c.draw_string(UiKit.font("body"), Vector2(0, 100), info[0], HORIZONTAL_ALIGNMENT_LEFT, w, 19, UiKit.INK)
		var sec := _section(s)
		c.draw_string(UiKit.font("cond", 1), Vector2(0, 126), "%s  ·  %s" % [sec[0], "IN RACES" if sec[1] == "RACES" else "IN THE MENUS"],
			HORIZONTAL_ALIGNMENT_LEFT, w, 13, UiKit.INK_DIM)
		# Where it is in the song (the NFS3 songs' sections don't say how long they run).
		var pos := mp.position_s()
		var length := mp.length_s()
		var bar := Rect2(0, 150, w, 4)
		UiKit.box(c, bar, Color(1, 1, 1, 0.12), 2)
		if length > 0:
			UiKit.box(c, Rect2(bar.position, Vector2(w * clampf(pos / length, 0, 1), 4)), UiKit.ACCENT, 2)
		var tf := UiKit.font("cond", 1, true)
		c.draw_string(tf, Vector2(0, 176), _clock(pos), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiKit.INK_DIM)
		c.draw_string(tf, Vector2(w - 80, 176), _clock(length) if length > 0 else "", HORIZONTAL_ALIGNMENT_RIGHT, 80, 14,
			UiKit.INK_DIM)
		c.draw_string(tf, Vector2(0, 176), "SHUFFLED" if mp.shuffled() else "IN ORDER", HORIZONTAL_ALIGNMENT_CENTER, w, 13,
			UiKit.INK_FAINT)
	# The spectrum.
	var sr := Rect2(0, 206, w, 140)
	if s != "":
		var bw := sr.size.x / BANDS
		for b in BANDS:
			var h := maxf(sr.size.y * _levels[b], 2.0)
			var col := UiKit.ACCENT.lerp(UiKit.ACCENT_HOT, _levels[b])
			c.draw_rect(Rect2(sr.position.x + b * bw + 1, sr.end.y - h, bw - 3, h), Color(col, 0.35 + 0.6 * _levels[b]))
		c.draw_rect(Rect2(sr.position.x, sr.end.y + 3, sr.size.x, 1), UiKit.LINE)
	if off:
		c.draw_string(UiKit.font("body"), Vector2(0, 440), "Turn it up in Settings → Audio.", HORIZONTAL_ALIGNMENT_LEFT,
			w, 15, UiKit.INK_DIM)


static func _clock(t: float) -> String:
	var n := int(t)
	return "%d:%02d" % [n / 60, n % 60]
