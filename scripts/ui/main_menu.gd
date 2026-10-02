extends Control
## The front end. A bar along the top holds its three places, each a click (or Q / E) away:
##   RACE      the race as it's set up, ready to start with Enter: the mode, the track with
##             the way round, time and weather, the rules (laps, rivals, traffic) and the car
##             with its paint and upgrades. The track and the car open a picker each, which
##             comes back here with the pick (Esc keeps the old one).
##   CAREER    High Stakes' tournaments and the garage their cars live in, with the money and
##             trophies. Entering a circuit goes on to choosing (or buying) a car for it.
##   MUSIC     every song of the games found, to play, skip and pause (MusicBrowser).
##   SETTINGS  gameplay, graphics, audio, the race HUD, the controls and the game data found.
## The chosen car stands on a turntable over the track's picture. Mouse, keyboard and pad
## work throughout: every action is on screen as something to click, with its key beside it.

enum Screen { RACE, TRACK, CAR, CAREER, GARAGE, SETTINGS, MUSIC }

const MODE_NOTES := [
	"Up to seven rivals over one to eight laps.",
	"One rival, and every cop in the county after you both.",
	"Just you and the clock. No rivals, no traffic.",
	"No laps and no rivals: cruise with the traffic and the patrols.",
	"Sit back and watch the AI race your car and its rivals.",
]
const START_TEXT := ["START RACE", "START PURSUIT", "START TRIAL", "START DRIVING", "WATCH RACE"]
## What each race setting does, on the line under the setup while it has focus.
const HELP := {
	"Mode": "What kind of event: pick one and the rules below follow it.",
	"Track": "Where you race. Enter or T opens every track to choose from.",
	"Car": "What you drive. Enter or C opens the dealers: every car, by its maker.",
	"Paint": "The colours this car came in.",
	"Upgrades": "High Stakes' tuning, each level on top of the last: suspension, then aero, then engine.",
	"Layout": "Reverse runs the lap the other way round. Mirror flips the whole track, left for right.",
	"Time": "Race by day, or at night by headlights.",
	"Weather": "The track's own weather: rain on most, snow on some.",
	"Laps": "How many laps the race runs.",
	"Rivals": "AI cars on the grid with you.",
	"Rival cars": "How the AI's cars are tuned: stock, with the same upgrades as yours, or fully upgraded.",
	"Rival class": "Which cars the AI drives: ones of your car's class (the nearest if there aren't enough), or any.",
	"Traffic": "Everyday cars in their lanes, both ways. They pull over for sirens.",
}
const M := 40.0               # screen margin
const BAR_H := 64.0           # the top bar
const TOP := 84.0             # content starts here
const FOOT := 72.0            # the footer: hints and the main button
const ROW_H := 34.0
const HEAD_H := 30.0
const CAR_PREVIEW_DELAY := 0.14   # s a browsed car must keep focus before its model loads
const QUIT_ARM_MS := 2500         # how long a first Esc keeps the quit armed

var _screen := Screen.RACE
var _mode := 0
var _tour := {}                  # a tournament's circuit being entered: {t, cid}; {} otherwise

# Chrome.
var _nav: TabStrip
var _nav_screens: Array[Screen] = []
var _sub: TabStrip               # the career's: tournaments, garage
var _quit_btn: HintBar
var _crumb: HintBar              # in a picker: back where it came from
var _hints: HintBar
var _next_btn: BigButton

# The race setup.
var _hub: Control
var _mode_row: OptionRow
var _track_card: PickCard
var _car_card: PickCard
var _layout_row: OptionRow       # which way round the track: forward, reverse, mirrored (Game.LAYOUTS)
var _time_row: OptionRow
var _weather: OptionRow
var _laps: OptionRow
var _opp: OptionRow
var _rival_cars: OptionRow
var _rival_class: OptionRow
var _traffic: OptionRow
var _paint_row: OptionRow        # the car's paint, by the names its fedata gives them, remembered per car
var _upgrade_row: OptionRow      # High Stakes' upgrades for the chosen car, remembered per car
var _driver_row: OptionRow       # who drives your Porsche Unleashed cars (Game.driver)
var _pick_paint: OptionRow       # the same for the car on show in the picker (and the paint in the garage)
var _pick_trim: OptionRow
var _left: Array = []            # the left column: [heading, [controls]]; y of each heading set by _layout_hub()
var _right: Array = []           # the car panel, likewise
var _hub_focus: Control
var _help_y := 0.0
var _opp_value := 3              # remembered across modes that hide it

var _track_i := 0                # picked
var _car_i := 0
var _track_shown := 0            # shown: the picked one, or the one pointed at in a picker
var _car_shown := 0
var _pick_from := -1             # what was picked when a picker opened, for Esc

var _overlay: Control
var _stats: CarStats
var _sheet: CarSheet             # the shown car's whole story, in the car picker and the garage
var _settings: SettingsPanel
var _tracks: TrackBrowser
var _dealer: Dealership         # the cars by maker: the race's pick and the career's garage
var _tournaments: TournamentPanel
var _music_list: MusicBrowser
var _fade: ColorRect
var _photo_back: TextureRect
var _photo_front: TextureRect
var _photo_drift: Node2D         # carries the photos' drift: a Control's position snaps to whole pixels

var _showroom: Showroom         # the car on its stage, in 3D
var _car_pending := -1           # car to load into the showroom once browsing settles on it
var _car_pending_t := 0.0

var _photos := {}                # track id -> Texture2D (or null)
var _postcards: TrackPostcards   # rendered stills of the tracks, filled in in the background
var _outlines := {}              # track id -> PackedVector3Array
var _time := 0.0
var _quit_armed_until := 0      # ticks (ms): a second Esc (or click on Quit) before this quits
var _starting := false
var _toast := ""
var _toast_t := 0.0
var _toast_col := UiKit.ACCENT


func _ready() -> void:
	theme = UiKit.theme()
	_track_i = maxi(Game.tracks.find(Game.track_id), 0)
	_car_i = Game.car_index
	_track_shown = _track_i
	_car_shown = _car_i
	_mode = Game.mode
	_postcards = TrackPostcards.new()
	add_child(_postcards)
	_build_backdrop()
	_showroom = Showroom.new()
	_showroom.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_showroom)
	_build_overlay()
	_build_hub()
	# The captions and ratings go over the setup's surfaces.
	move_child(_overlay, _hub.get_index())
	_build_browsers()
	_settings = SettingsPanel.new()
	_settings.embedded = true
	_settings.closed.connect(func(): if _screen == Screen.SETTINGS: _go(Screen.RACE))
	_settings.changed.connect(_on_settings_changed)
	add_child(_settings)
	_build_chrome()
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	resized.connect(_layout)
	_postcards.rendered.connect(_on_postcard_rendered)
	for id in Game.tracks:
		_postcards.request(id)
	if Game.music:
		# In the menu bar, left of Quit.
		Game.music.now_playing.right = 140.0
		Game.music.now_playing.top = 37.0
	_set_track(_track_i)
	_set_car(_car_i)
	_car_conditions()
	_show_car_now(_car_i)
	_go(Screen.RACE, false)
	# Back from a tournament's last race: on the tournaments.
	if Game.menu_screen == "tournaments" and Game.career_data():
		_go(Screen.CAREER, false)
	Game.menu_screen = ""
	_intro()


func _exit_tree() -> void:
	if Game.music:
		Game.music.now_playing.reset_place()


# ------------------------------------------------------------------ building

func _build_backdrop() -> void:
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_photo_drift = Node2D.new()
	add_child(_photo_drift)
	for i in 2:
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.modulate.a = 0.0
		_photo_drift.add_child(tr)
		if i == 0:
			_photo_back = tr
		else:
			_photo_front = tr
	var shade := Control.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.draw.connect(_draw_shade.bind(shade))
	add_child(shade)


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_stats = CarStats.new()
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_stats)
	_sheet = CarSheet.new()
	_overlay.add_child(_sheet)


func _build_hub() -> void:
	_hub = Control.new()
	_hub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hub.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hub.draw.connect(_draw_hub)
	add_child(_hub)
	var nums := func(from: int, to: int) -> PackedStringArray:
		var out := PackedStringArray()
		for n in range(from, to + 1):
			out.append(str(n))
		return out
	var short_modes := PackedStringArray(["Race", "Pursuit", "Trial", "Free roam", "Spectate"])
	_mode_row = OptionRow.new("Mode", short_modes)
	_mode_row.index = _mode
	_mode_row.changed.connect(func(i: int): _mode = i; _configure_hub())
	_track_card = PickCard.new()
	_track_card.key = "T"
	_track_card.pressed.connect(_open_track_picker)
	_car_card = PickCard.new()
	_car_card.key = "C"
	_car_card.pressed.connect(_open_car_picker)
	_layout_row = OptionRow.new("Layout", PackedStringArray(Game.LAYOUTS))
	_layout_row.index = Game.layout
	_time_row = OptionRow.new("Time", PackedStringArray(["Day", "Night"]))
	_time_row.index = int(Game.night)
	_time_row.changed.connect(func(_i): _show_backdrop(true); _tracks.night = _time_row.index == 1; _refresh_track_card(); _car_conditions())
	_weather = OptionRow.new("Weather", PackedStringArray(["Clear", "Rain"]))
	_weather.index = int(Game.weather)
	_weather.changed.connect(func(_i): _tint_backdrop(); _car_conditions())
	_opp_value = Game.opponents
	_laps = OptionRow.new("Laps", nums.call(1, 8))
	_laps.index = Game.laps - 1
	_laps.changed.connect(func(_i): _refresh_track_card())
	_opp = OptionRow.new("Rivals", nums.call(0, 7))
	_opp.index = Game.opponents
	_opp.changed.connect(func(i: int): _opp_value = i; _configure_hub())
	_rival_cars = OptionRow.new("Rival cars", PackedStringArray(["Stock", "Like yours", "Full"]))
	_rival_cars.index = Game.rival_upgrades
	_rival_cars.changed.connect(func(i: int): Game.rival_upgrades = i)
	_rival_class = OptionRow.new("Rival class", PackedStringArray(["Same as yours", "Any"]))
	_rival_class.index = Game.rival_class
	_rival_class.changed.connect(func(i: int): Game.rival_class = i)
	_traffic = OptionRow.new("Traffic", PackedStringArray(["Off", "On"]))
	_traffic.index = int(Game.traffic)
	_paint_row = OptionRow.new("Paint", PackedStringArray(["Factory"]))
	_paint_row.changed.connect(func(i: int): _set_paint(_car_i, i))
	_upgrade_row = OptionRow.new("Upgrades", PackedStringArray(Car.UPGRADE_NAMES))
	_upgrade_row.index = Game.upgrade_of(_car_i)
	_upgrade_row.changed.connect(func(i: int): _set_trim(_car_i, i))
	_driver_row = OptionRow.new("Driver", _driver_names())
	_driver_row.index = Game.driver
	_driver_row.disabled_text = "The car's own"
	_driver_row.changed.connect(_set_driver)
	# The same two in the car picker (the paint in the garage too), under the car on show.
	_pick_paint = OptionRow.new("Paint", PackedStringArray(["Factory"]))
	_pick_paint.caption_w = 64.0
	_pick_paint.changed.connect(func(i: int): _set_paint(_car_shown, i))
	add_child(_pick_paint)
	_pick_trim = OptionRow.new("Trim", PackedStringArray(Car.UPGRADE_NAMES))
	_pick_trim.caption_w = 56.0
	_pick_trim.changed.connect(func(i: int): _set_trim(_car_shown, i))
	add_child(_pick_trim)
	_left = [["", [_mode_row]], ["", [_track_card, _layout_row, _time_row, _weather]],
		["RACE", [_laps, _opp, _rival_cars, _rival_class, _traffic]]]
	_right = [["CAR", [_car_card, _paint_row, _upgrade_row, _driver_row]]]
	for col in [_left, _right]:
		for s in col:
			for c: Control in s[1]:
				if c is OptionRow:
					c.custom_minimum_size.y = ROW_H
					c.caption_w = 104.0
					c.changed.connect(func(_v): _hub.queue_redraw(); _refresh_home_bits())
				c.hovered.connect(func(): _set_hub_focus(c))
				_hub.add_child(c)
	_hub_focus = _mode_row


func _build_browsers() -> void:
	var postcard := func(id: String, night: bool) -> Texture2D:
		var tex := _postcards.get_postcard(id, night)
		return tex if tex else _track_photo(id)
	_tracks = TrackBrowser.new()
	_tracks.title = "CHOOSE A TRACK"
	_tracks.postcard = postcard
	_tracks.outline = _outline
	_tracks.focus_changed.connect(_set_track)
	_tracks.previewed.connect(func(i: int): _track_shown = i; _show_track(true))
	_tracks.confirmed.connect(func(i: int): _set_track(i); _go(Screen.RACE))
	_tracks.cancelled.connect(_back)
	add_child(_tracks)
	_dealer = Dealership.new()
	_dealer.paint_names = _paint_names
	# Browsing a race's cars picks them (Esc puts the old one back); the career's only shows them.
	_dealer.focus_changed.connect(func(i: int):
		if i >= 0 and _screen == Screen.CAR:
			_set_car(i)
		elif i >= 0:
			_preview_car_later(i))
	_dealer.previewed.connect(_preview_car_later)
	_dealer.confirmed.connect(func(i: int): _set_car(i); _go(Screen.RACE))
	_dealer.cancelled.connect(_back)
	_dealer.paint_step.connect(func(d: int): _pick_paint.step(d))
	_dealer.trim_step.connect(func(d: int): _pick_trim.step(d))
	_dealer.changed.connect(_on_dealer_changed)
	_dealer.chosen.connect(func(i: int): _car_i = i; _enter_circuit())
	add_child(_dealer)
	_tournaments = TournamentPanel.new()
	_tournaments.postcard = postcard
	_tournaments.focus_changed.connect(_on_circuit_focus)
	_tournaments.chosen.connect(func(t: Dictionary, cid: int): _tour = {"t": t, "cid": cid}; _go(Screen.GARAGE))
	_tournaments.garage.connect(func(): _tour = {}; _go(Screen.GARAGE))
	_tournaments.back.connect(_back)
	_tournaments.changed.connect(_refresh_chrome)
	add_child(_tournaments)
	_music_list = MusicBrowser.new()
	_music_list.cancelled.connect(_back)
	add_child(_music_list)


func _build_chrome() -> void:
	_nav = TabStrip.new(PackedStringArray(), TabStrip.Style.TABS)
	_nav.custom_minimum_size.y = BAR_H - 12
	_nav.size.y = BAR_H - 12
	_nav.keys = PackedStringArray(["Q", "E"])
	_nav.changed.connect(func(i: int): _go(_nav_screens[i]))
	add_child(_nav)
	var names := PackedStringArray(["Race"])
	_nav_screens = [Screen.RACE]
	if Game.career_data():
		names.append("Career")
		_nav_screens.append(Screen.CAREER)
	names.append("Music")
	_nav_screens.append(Screen.MUSIC)
	names.append("Settings")
	_nav_screens.append(Screen.SETTINGS)
	_nav.set_items(names, 0)
	_sub = TabStrip.new(PackedStringArray(["Tournaments", "Garage"]), TabStrip.Style.TABS)
	_sub.font_size = 15
	_sub.custom_minimum_size.y = 36
	_sub.size.y = 36
	_sub.changed.connect(func(i: int): _tour = {}; _go(Screen.CAREER if i == 0 else Screen.GARAGE))
	add_child(_sub)
	_quit_btn = HintBar.new()
	_quit_btn.set_hints([["", "QUIT", _request_quit]])
	add_child(_quit_btn)
	_crumb = HintBar.new()
	add_child(_crumb)
	_hints = HintBar.new()
	add_child(_hints)
	_next_btn = BigButton.new()
	_next_btn.pressed.connect(_next)
	add_child(_next_btn)


# ------------------------------------------------------------------ layout

func _layout() -> void:
	var W := size.x
	var H := size.y
	for tr in [_photo_back, _photo_front]:
		tr.size = size * 1.08
		tr.position = -size * 0.04
	_nav.position = Vector2(M + 196, 6)
	_crumb.position = Vector2(M + 196, (BAR_H - _crumb.size.y) * 0.5)
	_quit_btn.position = Vector2(W - M - _quit_btn.size.x + 8, (BAR_H - _quit_btn.size.y) * 0.5)
	_sub.position = Vector2(M - 14, TOP - 6)
	_hints.position = Vector2(M - 10, H - 36 - _hints.size.y * 0.5)
	_next_btn.size = Vector2(280, 50)
	_next_btn.position = Vector2(W - M - _next_btn.size.x, H - 22 - _next_btn.size.y)
	var body_h := H - TOP - FOOT - 6
	_layout_hub()
	_tracks.position = Vector2(M, TOP)
	_tracks.size = Vector2(W - M * 2, body_h)
	_tournaments.position = Vector2(M, TOP + 44)
	_tournaments.size = Vector2(W - M * 2, body_h - 44)
	# (Under the career's tabs while visiting the garage.)
	var tabs := 44.0 if _screen == Screen.GARAGE and not _in_entry() else 0.0
	_dealer.position = Vector2(M, TOP + tabs)
	# The makers' map wants room (the car beside it smaller); a race's list has the figures'
	# columns; the career's is narrower, the car beside it bigger.
	var dw := minf(560.0, W * 0.43) if _screen == Screen.CAR else minf(470.0, W * 0.37)
	if _dealer.visible and _dealer.at_makers():
		dw = minf(760.0, W * 0.52)
	_dealer.size = Vector2(dw, body_h - tabs)
	_settings.position = Vector2(M, TOP)
	_settings.size = Vector2(W - M * 2, body_h)
	_music_list.position = Vector2(M, TOP)
	_music_list.size = Vector2(minf(620.0, W * 0.48), body_h)
	_music_list.card_rect = Rect2(_music_list.size.x + 60, 40, W - M * 2 - _music_list.size.x - 60, body_h - 40)
	_stats.size = Vector2(_car_panel_w(), 56)
	var sheet_x: float = _dealer.position.x + _dealer.size.x + 40
	_sheet.position = Vector2(sheet_x, TOP + 2)
	_sheet.size = Vector2(W - M - sheet_x, H - TOP - FOOT - 14)
	var fr := _sheet.finish_rect()
	fr.position += _sheet.position
	var half := fr.size.x * (0.56 if _pick_trim.visible else 1.0)
	_pick_paint.position = Vector2(fr.position.x, fr.position.y + 3)
	_pick_paint.size = Vector2(half - 16, 34)
	_pick_trim.position = Vector2(fr.position.x + half + 8, fr.position.y + 3)
	_pick_trim.size = Vector2(fr.end.x - fr.position.x - half - 8, 34)
	match _screen:
		Screen.RACE:
			_stats.position = Vector2(W - M - _car_panel_w(), _car_card.position.y + _car_card.size.y + 14)
		_:
			_stats.position = Vector2(W - M - _car_panel_w(), H - FOOT - 22 - _stats.size.y)
	_place_car()
	_overlay.queue_redraw()
	_hub.queue_redraw()


func _left_w() -> float:
	return minf(440.0, size.x * 0.36)


func _car_panel_w() -> float:
	return minf(430.0, size.x * 0.34)


## The setup, set as type straight on the picture. Down the left the mode, the track lockup
## with its layout, time and weather, and the race's rules under a kicker; bottom right,
## under the car on its turntable, the car lockup with its ratings, paint and upgrades.
func _layout_hub() -> void:
	var lw := _left_w()
	var y := TOP + 4
	for s in _left:
		var rows: Array = s[1].filter(func(c: Control) -> bool: return c.visible)
		s.resize(2)
		if rows.is_empty():
			s.append(-1.0)
			continue
		if s[0] != "":
			s.append(y + 13)   # the kicker's baseline
			y += 22
		else:
			s.append(-1.0)
		for c: Control in rows:
			var h := PickCard.H if c is PickCard else ROW_H
			c.position = Vector2(M, y)
			c.size = Vector2(lw, h)
			y += h
			if c == _mode_row:
				y += 22.0   # its note
		y += 20.0
	_help_y = y
	# The car, from the bottom up, above the footer.
	var cw := _car_panel_w()
	var x := size.x - M - cw
	y = size.y - FOOT - 16 - 3 * ROW_H - 12 - 56 - 14 - PickCard.H
	_right[0].resize(2)
	_right[0].append(y)
	_car_card.position = Vector2(x, y)
	_car_card.size = Vector2(cw, PickCard.H)
	y += PickCard.H + 14 + 56 + 12
	for c: OptionRow in [_paint_row, _upgrade_row, _driver_row]:
		c.position = Vector2(x, y)
		c.size = Vector2(cw, ROW_H)
		y += ROW_H


## Tells the showroom where the car goes: the space right of whatever is down the left, above
## what's under it (on the race, above the car's lockup; by its sheet, between the figures
## and the spec sheet).
func _place_car() -> void:
	if not _showroom:
		return
	var W := size.x
	var r := Rect2()
	match _screen:
		Screen.CAR, Screen.GARAGE:
			r = _sheet.car_rect()
			r.position += _sheet.position
		_:
			var x := M + _left_w() + 30
			var bottom: float = _right[0][2] - 12 if _right.size() > 0 and _right[0].size() > 2 else size.y * 0.55
			r = Rect2(x, TOP, W - M - x, bottom - TOP)
	_showroom.set_region(r)


# ------------------------------------------------------------------ screens

func _top_level(s: Screen) -> bool:
	return s == Screen.RACE or s == Screen.CAREER or s == Screen.SETTINGS or s == Screen.MUSIC \
		or (s == Screen.GARAGE and _tour.is_empty())


func _in_career() -> bool:
	return _screen == Screen.CAREER or _screen == Screen.GARAGE


## Choosing a car for a circuit (rather than visiting the garage).
func _in_entry() -> bool:
	return _screen == Screen.GARAGE and not _tour.is_empty()


## Show screen `s`: its panel, the bar and hints for it, and the main button.
func _go(s: Screen, animate := true) -> void:
	if _starting:
		return
	if s != Screen.GARAGE:
		_tour = {}
	var was := _screen
	if was == Screen.SETTINGS and s != Screen.SETTINGS:
		_settings.close()
	_screen = s
	_hub.visible = s == Screen.RACE
	_stats.visible = s == Screen.RACE
	_sheet.visible = s == Screen.CAR or s == Screen.GARAGE
	_sheet.finish = _sheet.visible
	_pick_paint.visible = _sheet.visible
	# The garage's upgrades are bought there, not chosen.
	_pick_trim.visible = s == Screen.CAR
	if s == Screen.TRACK and not _tracks.visible:
		_tracks.night = _time_row.index == 1
		_tracks.open(_track_i)
	elif s != Screen.TRACK:
		_tracks.close()
	if s == Screen.CAR and not (_dealer.visible and not _dealer.career):
		_dealer.career = false
		_dealer.circuit = {}
		_dealer.open(_car_i)
	elif s == Screen.GARAGE:
		_dealer.career = true
		_dealer.circuit = Game.career_data().circuits.get(_tour.cid, {}) if not _tour.is_empty() else {}
		_dealer.open(_car_i)
	elif s != Screen.CAR:
		_dealer.close()
		_showroom.calm = false
	if s == Screen.CAREER and not _tournaments.visible:
		_tournaments.open()
	elif s != Screen.CAREER:
		_tournaments.close()
	if s == Screen.MUSIC and not _music_list.visible:
		_music_list.open(0)
	elif s != Screen.MUSIC:
		_music_list.close()
	if s == Screen.SETTINGS and not _settings.visible:
		_settings.open(0)
	elif s != Screen.SETTINGS:
		_settings.visible = false
	if s == Screen.RACE:
		_configure_hub()
	if not _in_career():
		_track_shown = _track_i
		_show_track(animate)
	if s != Screen.GARAGE:
		_preview_car_later(_car_i)
	# The car stands in the showroom on the screens that are about it.
	var show_car := s == Screen.RACE or s == Screen.CAR or s == Screen.GARAGE
	create_tween().tween_property(_showroom, "modulate:a", 1.0 if show_car else 0.0, 0.2 if animate else 0.0)
	_refresh_chrome()
	_layout()
	_show_backdrop(animate)
	_tint_backdrop()
	# (The pickers slide themselves in.)
	if animate and was != s and s != Screen.TRACK and s != Screen.CAR and s != Screen.GARAGE and s != Screen.MUSIC:
		var panel: Control = {Screen.RACE: _hub, Screen.CAREER: _tournaments, Screen.SETTINGS: _settings}[s]
		panel.modulate.a = 0.0
		create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(panel, "modulate:a", 1.0, 0.18)


## The top bar, the career's tabs, the hints and the main button, for the screen as it is.
func _refresh_chrome() -> void:
	var top := _top_level(_screen)
	_nav.visible = top
	_quit_btn.visible = top
	_crumb.visible = not top
	var ni := _nav_screens.find(Screen.CAREER if _in_career() else _screen)
	if top and ni >= 0 and ni != _nav.index:
		_nav.set_items(_nav.items, ni)
	if Game.career_data():
		var badges := PackedStringArray()
		for sc in _nav_screens:
			badges.append(UiKit.money(Game.career_money) if sc == Screen.CAREER and Game.career_series != "nfs3" else "")
		_nav.set_badges(badges)
	_sub.visible = _in_career() and not _in_entry()
	if _sub.visible:
		var n := Game.career_garage.size()
		_sub.set_badges(PackedStringArray(["", str(n)]))
		if _sub.index != int(_screen == Screen.GARAGE):
			_sub.set_items(_sub.items, int(_screen == Screen.GARAGE))
	match _screen:
		Screen.TRACK, Screen.CAR:
			_crumb.set_hints([["ESC", "BACK TO RACE", _back]])
		Screen.GARAGE:
			_crumb.set_hints([["ESC", "BACK TO TOURNAMENTS", _back]])
	_update_hints()
	var text := _next_text()
	_next_btn.visible = text != ""
	_next_btn.set_text(text)
	_next_btn.set_enabled(_next_enabled())
	_layout()


func _update_hints() -> void:
	var h: Array = []
	match _screen:
		Screen.RACE:
			h = [["↑↓", "SELECT"], ["←→", "CHANGE"], ["T", "TRACK", _open_track_picker], ["C", "CAR", _open_car_picker],
				["DRAG", "ROTATE CAR"]]
		Screen.TRACK:
			h = _tracks.hints() + [["", "TYPE TO SEARCH"]]
		Screen.CAR, Screen.GARAGE:
			h = _dealer.hints() + [["DRAG", "ROTATE CAR"]]
		Screen.CAREER:
			h = [["↑↓", "CIRCUIT"], ["←→", "TOURNAMENT"], ["G", "GARAGE", func(): _tour = {}; _go(Screen.GARAGE)],
				["N", "NEW CAREER", _tournaments.new_career]]
			if Game.career_series_list().size() > 1:
				h.insert(2, ["TAB", "GAME", _tournaments.next_series])
		Screen.SETTINGS:
			h = _settings.hints()
		Screen.MUSIC:
			h = _music_list.hints()
	if _top_level(_screen):
		h.append(["Q E", "SWITCH TAB"])
	_hints.set_hints(h)


func _next_text() -> String:
	match _screen:
		Screen.RACE: return START_TEXT[_mode]
		Screen.TRACK: return "USE THIS TRACK"
		Screen.CAREER: return "CHOOSE A CAR"
		Screen.CAR, Screen.GARAGE: return _dealer.primary_text()
	return ""


func _next_enabled() -> bool:
	match _screen:
		Screen.CAREER: return _tournaments.blocked() == ""
		Screen.CAR, Screen.GARAGE: return _dealer.primary_ok()
	return true


## The main button (Enter where nothing else takes it).
func _next() -> void:
	if _starting:
		return
	_next_btn.flash()
	match _screen:
		Screen.RACE: _start()
		Screen.TRACK: _set_track(_track_i); _go(Screen.RACE)
		Screen.CAREER: _tournaments.choose()
		Screen.CAR, Screen.GARAGE: _dealer.primary()


## Back a step: out of a picker (keeping what was picked before), out of a circuit's car
## choice, or from the other tabs to the race. On the race: quit, asked twice.
func _back() -> void:
	if _starting:
		return
	match _screen:
		Screen.RACE:
			_request_quit()
		Screen.TRACK:
			if _pick_from >= 0:
				_set_track(_pick_from)
			_go(Screen.RACE)
		Screen.CAR:
			if _pick_from >= 0:
				_set_car(_pick_from)
			_go(Screen.RACE)
		Screen.GARAGE:
			_go(Screen.CAREER)
		_:
			_go(Screen.RACE)


func _open_track_picker() -> void:
	if _screen != Screen.RACE:
		return
	_pick_from = _track_i
	_go(Screen.TRACK)


func _open_car_picker() -> void:
	if _screen != Screen.RACE:
		return
	_pick_from = _car_i
	_go(Screen.CAR)


## The dealership's focus moved, a maker opened, or (in the career) the money or cars
## changed: the main button, the hints and the bar.
func _on_dealer_changed() -> void:
	# On the makers' map the car keeps to its wide shots, off the map.
	_showroom.calm = _dealer.visible and _dealer.at_makers()
	if _screen == Screen.CAR or _screen == Screen.GARAGE:
		_refresh_chrome()
		_overlay.queue_redraw()


# ------------------------------------------------------------------ the race setup

## The rows that apply to the mode: hidden, not greyed out, where they don't.
func _configure_hub() -> void:
	var m := _mode
	_mode_row.set_items(_mode_row.items, m)
	_opp.visible = m != Game.Mode.TIME_TRIAL and m != Game.Mode.FREE_ROAM
	_rival_cars.visible = _opp.visible
	_rival_class.visible = _opp.visible
	_rival_cars.disabled = _opp_value == 0
	_rival_class.disabled = _opp_value == 0
	_rival_cars.disabled_text = "No rivals"
	_rival_class.disabled_text = "No rivals"
	# A point-to-point run is raced once.
	_laps.visible = m != Game.Mode.FREE_ROAM and not Game.is_sprint(Game.tracks[_track_i])
	_traffic.visible = m != Game.Mode.TIME_TRIAL
	_left[2][0] = "TRAFFIC" if m == Game.Mode.FREE_ROAM else "RACE"
	if not _hub_focus.visible:
		_hub_focus = _mode_row
	_set_hub_focus(_hub_focus)
	_refresh_track_card()
	_layout()
	if _screen == Screen.RACE:
		_next_btn.set_text(_next_text())
	_overlay.queue_redraw()


## The car's paints and upgrades (which only load with the car) and its lockup.
func _refresh_car_rows() -> void:
	_upgrade_row.set_items(_upgrade_row.items, Game.upgrade_of(_car_i))
	var names := _paint_names(_car_i)
	_paint_row.swatches = _paint_swatches(_car_i)
	_paint_row.set_items(names, mini(Game.paint_of(_car_i), names.size() - 1))
	# Only a Porsche Unleashed car has drivers to choose from (once its model is in).
	var count := 0
	if Game.own_car_loaded(_car_i):
		var data: Object = Game.own_car(_car_i)
		count = int(data.get("driver_count")) if "driver_count" in data else 0
	_driver_row.disabled = count == 0
	_driver_row.max_index = count
	_refresh_car_card()


## The race's car lockup, from the sheet (which has just read the car).
func _refresh_car_card() -> void:
	if _sheet.car == _car_i:
		_car_card.set_content(_sheet.kicker_text(), _sheet.title_text(), _sheet.headline())


## What the sheet says the car is to you, before its maker.
func _sheet_context(i: int) -> String:
	match _screen:
		Screen.GARAGE: return "In your garage" if Game.owns(i) else "At the dealer"
		Screen.CAR: return ""
	return ""


func _refresh_track_card() -> void:
	var id := Game.tracks[_track_i]
	var m := _tracks.map_of(id)
	_track_card.outline = m.pts
	_track_card.open = Game.is_sprint(id)
	var bits := PackedStringArray()
	var km: float = m.km
	if km > 0:
		if Game.is_sprint(id):
			bits.append(UiKit.dist(km) + ", point to point")
		else:
			bits.append(UiKit.dist(km) + " a lap")
			if _laps.visible:
				bits.append("%s over %d lap%s" % [UiKit.dist(km * (_laps.index + 1)), _laps.index + 1, "" if _laps.index == 0 else "s"])
	if _tracks.precip(id) == Nfs3Horizon.Precip.SNOW:
		bits.append("snow country")
	# The game it's from (whether it's a lap or a run is in the line under the name).
	var sec := _tracks.section(id).split(" · ")[0]
	_track_card.set_content("Track  ·  " + sec, Game.track_name(id), " · ".join(bits))


## The bits of the chrome that follow the setup (the start button's words).
func _refresh_home_bits() -> void:
	if _screen == Screen.RACE:
		_next_btn.set_text(_next_text())


func _hub_nav() -> Array[Control]:
	var out: Array[Control] = []
	for col in [_left, _right]:
		for s in col:
			for c: Control in s[1]:
				if c.visible:
					out.append(c)
	return out


func _set_hub_focus(c: Control) -> void:
	_hub_focus = c
	for x in _hub_nav():
		x.focused = x == c
	_hub.queue_redraw()


func _move_hub_focus(dir: int) -> void:
	var nav := _hub_nav()
	_set_hub_focus(nav[posmod(nav.find(_hub_focus) + dir, nav.size())])


func _hub_caption(c: Control) -> String:
	if c == _track_card:
		return "Track"
	if c == _car_card:
		return "Car"
	return (c as OptionRow).caption if c is OptionRow else ""


func _draw_hub() -> void:
	var h := _hub
	var lw := _left_w()
	for s in _left:
		if s.size() > 2 and s[2] >= 0.0:
			UiKit.kicker(h, Vector2(M, s[2]), s[0], lw)
	# The mode's note under it.
	h.draw_string(UiKit.font("body"), Vector2(M + _mode_row.caption_w, _mode_row.position.y + ROW_H + 12), MODE_NOTES[_mode],
		HORIZONTAL_ALIGNMENT_LEFT, lw - _mode_row.caption_w, 14, UiKit.INK_DIM)
	# What the focused setting does, at the foot of the column.
	var help: String = HELP.get(_hub_caption(_hub_focus), "")
	if help != "":
		var y := maxf(_help_y, size.y - FOOT - 50)
		h.draw_multiline_string(UiKit.font("body"), Vector2(M, y + 13), help, HORIZONTAL_ALIGNMENT_LEFT, lw, 14, 2,
			Color(UiKit.INK, 0.55))


# ------------------------------------------------------------------ drawing

func _draw_shade(c: Control) -> void:
	var W := c.size.x
	var H := c.size.y
	var clear := Color(UiKit.BG, 0.0)
	# Scrims so type reads over any picture: down the left, along the top and the bottom, and
	# into the bottom right corner where the car's lockup sits.
	_grad_rect(c, Rect2(0, 0, 760, H), Color(UiKit.BG, 0.95), clear, true)
	_grad_rect(c, Rect2(0, 0, W, 140), Color(UiKit.BG, 0.85), clear, false)
	_grad_rect(c, Rect2(0, H - 360, W, 360), clear, Color(UiKit.BG, 0.97), false)
	var corner := Rect2(W - 900, H * 0.35, 900, H * 0.65)
	c.draw_polygon(PackedVector2Array([corner.position, Vector2(corner.end.x, corner.position.y), corner.end,
		Vector2(corner.position.x, corner.end.y)]), PackedColorArray([clear, clear, Color(UiKit.BG, 0.9), clear]))


static func _grad_rect(ci: CanvasItem, r: Rect2, from: Color, to: Color, horizontal: bool) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var cols := PackedColorArray([from, to, to, from]) if horizontal else PackedColorArray([from, from, to, to])
	ci.draw_polygon(pts, cols)

func _draw_overlay() -> void:
	var o := _overlay
	var W := o.size.x
	var H := o.size.y
	# Logo.
	var lf := UiKit.font("display")
	o.draw_string(lf, Vector2(M, 44), "NFS", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UiKit.ACCENT)
	var lw := lf.get_string_size("NFS", HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	o.draw_string(UiKit.font("cond_med", 5), Vector2(M + lw + 8, 43), "REVIVAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, UiKit.INK)
	o.draw_line(Vector2(M + 180, 22), Vector2(M + 180, 42), UiKit.LINE, 1.0)
	o.draw_line(Vector2(M - 14, BAR_H), Vector2(W - M + 14, BAR_H), UiKit.LINE, 1.0)
	# In a picker: what it's for, after the way back.
	if _crumb.visible:
		var title: String = {Screen.TRACK: "Choose a track", Screen.CAR: "Choose a car", Screen.GARAGE: _entry_title()}.get(_screen, "")
		o.draw_string(UiKit.font("body"), Vector2(_crumb.position.x + _crumb.size.x + 16, 38), title,
			HORIZONTAL_ALIGNMENT_LEFT, W - M - _crumb.position.x - _crumb.size.x - 16, 16, UiKit.INK_DIM)
	# Hot Pursuit: a light bar sweeping along the top edge.
	if _pursuit_lights():
		var phase := fmod(_time * 2.2, 2.0)
		var col := UiKit.COP_RED if phase < 1.0 else UiKit.COP_BLUE
		var a := 0.6 * absf(sin(_time * 14.0))
		_grad_rect(o, Rect2(0, 0, W * 0.5, 3), Color(col, a if phase < 1.0 else 0.0), Color(col, 0.0), true)
		_grad_rect(o, Rect2(W * 0.5, 0, W * 0.5, 3), Color(col, 0.0), Color(col, a if phase >= 1.0 else 0.0), true)
	match _screen:
		Screen.RACE:
			if not Game.has_game_data():
				o.draw_multiline_string(UiKit.font("body"), Vector2(W * 0.5, TOP + 20), "No NFS3 data found: you get the "
					+ "generated circuit and stand-in cars. Settings → Game data says where it looks.", HORIZONTAL_ALIGNMENT_LEFT,
					W * 0.5 - M, 15, 3, UiKit.ACCENT)
		Screen.CAREER:
			if not _next_enabled():
				var why := _tournaments.blocked()
				o.draw_string(UiKit.font("body"), Vector2(M, _next_btn.get_center().y + 5), why,
					HORIZONTAL_ALIGNMENT_RIGHT, _next_btn.position.x - M - 20, 15, UiKit.COP_RED)
	if _toast_t > 0.0:
		var a := clampf(_toast_t * 3.0, 0.0, 1.0)
		var f := UiKit.font("body_bold")
		var y := _next_btn.position.y - 16 if _next_btn.visible else H - 30
		o.draw_string(f, Vector2(W * 0.4, y), _toast, HORIZONTAL_ALIGNMENT_RIGHT, W * 0.6 - M, 15, Color(_toast_col, a))


## "European Tour · circuit 1 · any car · entry free", over the car choice for a circuit.
func _entry_title() -> String:
	if _tour.is_empty():
		return ""
	var t: Dictionary = _tour.t
	var c: Dictionary = Game.career_data().circuits.get(_tour.cid, {})
	var which: String = c.name if c.has("name") else "circuit %d" % (t.get("circuits", []).find(_tour.cid) + 1)
	var bits := PackedStringArray(["Choose a car for %s, %s" % [t.get("name", ""), which]])
	var only := Game.career_data().restriction_text(c)
	if only != "":
		bits.append(only)
	return "  ·  ".join(bits)


func _pursuit_lights() -> bool:
	return _mode == Game.Mode.HOT_PURSUIT and (_screen == Screen.RACE or _screen == Screen.TRACK or _screen == Screen.CAR)


# ------------------------------------------------------------------ setup

func _intro() -> void:
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_fade, "color:a", 0.0, 0.5).from(1.0)
	for c in [_overlay, _hub, _nav, _hints]:
		c.modulate.a = 0.0
		tw.tween_property(c, "modulate:a", 1.0, 0.45).set_delay(0.15)


func _outline(id: String) -> PackedVector3Array:
	if not _outlines.has(id):
		_outlines[id] = ProceduralTrack.outline() if id == Game.PROCEDURAL_TRACK \
			else Nfs3Track.peek_outline(Game.track_dir(id))
	return _outlines[id]

func _set_track(i: int) -> void:
	_track_i = i
	_track_shown = i
	# The generated circuit can be driven either way but has no mirror image.
	_layout_row.max_index = 1 if Game.tracks[i] == Game.PROCEDURAL_TRACK else -1
	_layout_row.set_items(_layout_row.items, mini(_layout_row.index, 1) if _layout_row.max_index == 1 else _layout_row.index)
	# The weather is the track's own: rain on most, snow on some.
	var snow := _tracks.precip(Game.tracks[i]) == Nfs3Horizon.Precip.SNOW
	_weather.set_items(PackedStringArray(["Clear", "Snow" if snow else "Rain"]), _weather.index)
	_show_track(true)
	_refresh_track_card()


## The backdrop for the shown track.
func _show_track(animate: bool) -> void:
	_show_backdrop(animate)
	_overlay.queue_redraw()


func _on_circuit_focus() -> void:
	var id := _tournaments.focus_track()
	var i := Game.tracks.find(id)
	if i >= 0:
		_track_shown = i
		_show_backdrop(true)
	if _screen == Screen.CAREER:
		_next_btn.set_enabled(_next_enabled())
		_overlay.queue_redraw()


func _set_car(i: int) -> void:
	_car_i = i
	_preview_car_later(i)
	_refresh_car_rows()


## Car `i`'s paints by name ("Torch Red"...), as many as its model has colours.
func _paint_names(i: int) -> PackedStringArray:
	var spec := Game.car_spec(i)
	var names: Array = spec.info.get("colours", []) if "info" in spec else []
	var out := PackedStringArray()
	for n: String in names:
		out.append(n if n != "" else "Colour %d" % (out.size() + 1))
	if out.is_empty():
		out.append("Factory")
	return out

## ...and their colours (the paint areas are mid-grey, so the car files' colours are held
## at double strength: halved here to show as they come out on the car).
func _paint_swatches(i: int) -> Array[Color]:
	var out: Array[Color] = []
	# Only once its model is in (loading it for every car browsed past would stall the list).
	if not Game.own_car_loaded(i):
		return out
	var data: Object = Game.own_car(i)
	for c: Color in data.colours:
		out.append(Color(minf(c.r * 0.5, 1.0), minf(c.g * 0.5, 1.0), minf(c.b * 0.5, 1.0)))
	if out.size() != _paint_names(i).size():
		out.clear()
	return out

## A browsed car: its caption and ratings at once, the model once focus rests on it.
func _preview_car_later(i: int) -> void:
	_car_shown = i
	_show_backdrop(true)
	_stats.set_car(Game.car_spec(i), Game.units_kmh, _upgrade_shown(i))
	_sheet.show_car(i, _upgrade_shown(i), _sheet_context(i))
	_car_pending = i if _showroom.shown_id() != i or not is_equal_approx(_showroom.shown_wear(), _wear_shown(i)) else -1
	_car_pending_t = CAR_PREVIEW_DELAY
	if i == _car_i:
		_refresh_car_card()
	_refresh_pick_rows()
	_overlay.queue_redraw()


## Car `i` in paint `p` (remembered per car): repainted on the stand where it's the one on show.
func _set_paint(i: int, p: int) -> void:
	# Your tournament car keeps its paint: in the garage another is only tried on (a respray).
	if _screen == Screen.GARAGE and Game.owns(i):
		_dealer.try_paint(p)
		if _showroom.shown_id() == i:
			_showroom.repaint(Game.paint_tint(i, Game.own_car(i), p))
		return
	Game.paints[Game.cars[i].id] = p
	if _showroom.shown_id() == i:
		var data: Object = Game.own_car(i)
		_showroom.repaint(Game.paint_tint(i, data))
	if i == _car_i:
		_paint_row.set_items(_paint_row.items, p)
	if i == _car_shown:
		_pick_paint.set_items(_pick_paint.items, p)


## The Driver row's choices: the car's own, then Porsche Unleashed's ten by number (1 and 6
## in race suit and helmet, the rest in their own clothes).
func _driver_names() -> PackedStringArray:
	var out := PackedStringArray(["Auto"])
	for d in range(1, 11):
		out.append(str(d))
	return out


## Your driver (in every Porsche Unleashed car): the car on show is loaded again with him
## at the wheel, and the camera goes to him.
func _set_driver(d: int) -> void:
	Game.driver = d
	var i := _showroom.shown_id() if _showroom else -1
	if i >= 0:
		_show_car_now(i)
		_showroom.show_driver()


## Car `i` with its upgrades at `level` (remembered per car): its figures follow.
func _set_trim(i: int, level: int) -> void:
	Game.set_upgrade(i, level)
	if i == _car_i:
		_upgrade_row.set_items(_upgrade_row.items, level)
	if i == _car_shown:
		_pick_trim.set_items(_pick_trim.items, level)
		_stats.set_car(Game.car_spec(i), Game.units_kmh, _upgrade_shown(i))
		_sheet.show_car(i, _upgrade_shown(i), _sheet_context(i))
	if i == _car_i:
		_refresh_car_card()


## The picker's paint and trim, for the car on show.
func _refresh_pick_rows() -> void:
	var i := _car_shown
	var names := _paint_names(i)
	_pick_paint.swatches = _paint_swatches(i)
	_pick_paint.set_items(names, mini(_paint_shown(i), names.size() - 1))
	# (A paint only tried on goes when the focus does.)
	if _showroom.shown_id() == i and _showroom.car:
		_showroom.repaint(Game.paint_tint(i, Game.own_car(i), _paint_shown(i)))
	_pick_trim.set_items(_pick_trim.items, Game.upgrade_of(i))


## The upgrade level car `i`'s ratings show: in the garage, as it's fitted there.
func _upgrade_shown(i: int) -> int:
	return Game.garage_upgrade(i) if _screen == Screen.GARAGE else Game.upgrade_of(i)


## The paint car `i` shows: in the garage yours wear their own (or one being tried on).
func _paint_shown(i: int) -> int:
	if _screen == Screen.GARAGE and Game.owns(i):
		var t := _dealer.paint_tried(i)
		return t if t >= 0 else Game.garage_paint(i)
	return Game.paint_of(i)


## The damage car `i` shows dented on the stand: in the garage, what it carries.
func _wear_shown(i: int) -> float:
	return Game.garage_damage(i) if _screen == Screen.GARAGE else 0.0


## The showroom's car lit for the time of day and wiping the rain chosen.
func _car_conditions() -> void:
	_showroom.set_conditions(_time_row.index == 1, _weather.index == 1)


func _show_car_now(i: int) -> void:
	_car_shown = i
	_car_pending = -1
	var data: Object = Game.own_car(i)
	_stats.set_car(data, Game.units_kmh, _upgrade_shown(i))
	_showroom.show_car(data, Game.paint_tint(i, data, _paint_shown(i)), _upgrade_shown(i), i, Showroom.DROP_HEIGHT, _wear_shown(i))
	# Its colours are known now.
	_refresh_pick_rows()
	_dealer.queue_redraw()
	if i == _car_i:
		_refresh_car_rows()
	_overlay.queue_redraw()

## The shown track's rendered postcard for the time of day; the blurred front-end slide
## until that has been rendered.
func _show_backdrop(animate: bool) -> void:
	var id := Game.tracks[_track_shown]
	var tex := _postcards.get_postcard(id, _time_row.index == 1)
	if tex == null:
		tex = _track_photo(id)
	# Choosing a car: a High Stakes car's own showroom photo behind it.
	if _screen == Screen.CAR and _showcase_photo(_car_shown):
		tex = _showcase_photo(_car_shown)
	if tex == _photo_front.texture:
		return
	# Cross-fade: the old photo becomes the back layer, the new one fades in over it.
	_photo_back.texture = _photo_front.texture
	_photo_back.modulate.a = _photo_front.modulate.a
	_photo_front.texture = tex
	_photo_front.modulate.a = 0.0
	_showroom.set_backdrop(tex)
	if tex:
		create_tween().tween_property(_photo_front, "modulate:a", 1.0, 0.35 if animate else 0.9)
	create_tween().tween_property(_photo_back, "modulate:a", 0.0, 0.45)
	_tint_backdrop()

func _on_postcard_rendered(id: String) -> void:
	if id == Game.tracks[_track_shown]:
		_show_backdrop(true)
	if id == Game.tracks[_track_i]:
		_refresh_track_card()
	_tracks.refresh()
	_tournaments.queue_redraw()


func _tint_backdrop() -> void:
	var night := _time_row.index == 1
	var tint := Color(0.22, 0.27, 0.45) if night else Color(0.42, 0.42, 0.45)
	if _photo_front.texture and not _photos.values().has(_photo_front.texture):
		# A render already has the time of day in it: just dim it behind the showroom.
		tint = Color(0.72, 0.72, 0.75)
	if _screen == Screen.TRACK:
		tint = Color(0.5, 0.5, 0.53)
	elif _screen == Screen.CAREER:
		tint = Color(0.42, 0.42, 0.45)
	elif _screen == Screen.SETTINGS or _screen == Screen.MUSIC:
		tint = Color(0.25, 0.25, 0.28)
	if _weather.index == 1 and not _in_career():
		tint = tint.darkened(0.25).lerp(Color(0.3, 0.33, 0.36), 0.3)
	for tr in [_photo_back, _photo_front]:
		create_tween().tween_property(tr, "self_modulate", tint, 0.4)


## High Stakes' showroom photos of the cars, by car id.
var _showcase := {}


## High Stakes' showroom photo of car `i` (Showcase/art/sl<car>01.qfs), or null.
func _showcase_photo(i: int) -> Texture2D:
	if not Game.is_hs_car(i) or Game.hs_root == "":
		return null
	var id: String = Game.cars[i].id.trim_prefix(Game.HS_PREFIX)
	if not _showcase.has(id):
		var fsh := Fsh.load_file(Game.find_ci(Game.find_ci(Game.hs_root, "showcase/art"), "sl%s01.qfs" % id))
		_showcase[id] = ImageTexture.create_from_image(fsh.images[0]) if fsh and not fsh.images.is_empty() else null
	return _showcase[id]

## The track's front-end slide, cropped to the photo, heavily blurred and used as mood
## lighting behind the showroom (the baked-in map and logo blur away).
func _track_photo(id: String) -> Texture2D:
	if _photos.has(id):
		return _photos[id]
	var tex: Texture2D = null
	var fsh: Fsh = null
	var top := 60
	if Game.is_pu_track(id) or Game.is_hp2_track(id):
		# Porsche Unleashed's (Hot Pursuit 2's) photo of the track, its middle.
		var photo := Game.hp2_track_photo(id) if Game.is_hp2_track(id) else Game.pu_track_photo(id)
		if photo:
			var img := photo.get_region(Rect2i(0, photo.get_height() / 2 - 64, 256, 128))
			img.convert(Image.FORMAT_RGBA8)
			img.resize(48, 24, Image.INTERPOLATE_BILINEAR)
			img.resize(96, 48, Image.INTERPOLATE_BILINEAR)
			img.resize(384, 192, Image.INTERPOLATE_CUBIC)
			tex = ImageTexture.create_from_image(img)
	elif Game.is_hs_track(id):
		# High Stakes' own slides (FeArt/slides/tN_00.qfs), numbered in its track order.
		var n: int = Game.HS_SLIDES.get(id.trim_prefix(Game.HS_PREFIX), -1)
		if n >= 0:
			fsh = Fsh.load_file(Game.find_ci(Game.find_ci(Game.hs_root, "feart"), "slides/t%d_00.qfs" % n))
			top = 40
	elif id != Game.PROCEDURAL_TRACK and Game.has_game_data():
		var n := id.trim_prefix("trk").to_int()
		fsh = Fsh.load_file(Game.find_ci(Game.data_root, "fedata/art/slides/t%d_00.qfs" % n))
	if fsh and fsh.images.size() > 0 and fsh.images[0].get_width() >= 640:
		var img: Image = fsh.images[0].get_region(Rect2i(0, top, 640, 322))
		img.convert(Image.FORMAT_RGBA8)
		img.resize(48, 24, Image.INTERPOLATE_BILINEAR)
		img.resize(96, 48, Image.INTERPOLATE_BILINEAR)
		img.resize(384, 192, Image.INTERPOLATE_CUBIC)
		tex = ImageTexture.create_from_image(img)
	_photos[id] = tex
	return tex

func _on_settings_changed() -> void:
	_stats.set_car(Game.car_spec(_car_shown), Game.units_kmh, _upgrade_shown(_car_shown))
	_refresh_track_card()
	_overlay.queue_redraw()


# ------------------------------------------------------------------ for the tools

## `page`: 0 the first, 3 the race HUD (tools/autotest.gd).
func open_settings(page := 0) -> void:
	_go(Screen.SETTINGS, false)
	_settings.show_page(page)


## For tools/autotest.gd: "race" (or "home", "options"), "track", "car", "tournaments",
## "garage", "circuit" (the car choice for the first tournament circuit open) or "settings".
func show_screen(name: String) -> void:
	match name:
		"track": _open_track_picker()
		"car": _open_car_picker()
		"tournaments": _go(Screen.CAREER, false)
		"garage":
			_tour = {}
			_go(Screen.GARAGE, false)
		"circuit":
			_go(Screen.CAREER, false)
			_tournaments.choose()
		"settings": _go(Screen.SETTINGS, false)
		"music": _go(Screen.MUSIC, false)
		_: _go(Screen.RACE, false)


func _open_tournaments() -> void:
	if Game.career_data():
		show_screen("tournaments")


func _open_cars() -> void:
	show_screen("car")


# ------------------------------------------------------------------ input

func _say(text: String, col := UiKit.ACCENT) -> void:
	_toast = text
	_toast_col = col
	_toast_t = 3.0
	_overlay.queue_redraw()


## Whether a first Esc has armed the quit (for tools/ too).
func _quit_armed() -> bool:
	return Time.get_ticks_msec() < _quit_armed_until


## Esc twice quits: the first arms it for a moment (the toast and the Quit button say so),
## the second, while armed, quits. Settings and the career are saved as they change.
func _request_quit() -> void:
	if _quit_armed():
		get_tree().quit()
		return
	_quit_armed_until = Time.get_ticks_msec() + QUIT_ARM_MS
	_say("Press Esc again to quit", UiKit.COP_RED)
	_show_quit_armed(true)


func _show_quit_armed(armed: bool) -> void:
	_quit_btn.set_hints([["", "PRESS AGAIN TO QUIT" if armed else "QUIT", _request_quit]])
	_layout()


func _unhandled_input(e: InputEvent) -> void:
	if _starting:
		return
	var key := e as InputEventKey
	if key:
		if not key.pressed:
			return
		var k := key.physical_keycode
		if k == KEY_ESCAPE:
			if not key.echo:
				_back()
		elif (k == KEY_Q or k == KEY_E) and not key.echo and _nav.visible:
			_nav.step(-1 if k == KEY_Q else 1)
		elif _screen == Screen.RACE:
			match k:
				KEY_UP: _move_hub_focus(-1)
				KEY_DOWN: _move_hub_focus(1)
				KEY_LEFT, KEY_RIGHT:
					if _hub_focus is OptionRow:
						(_hub_focus as OptionRow).step(-1 if k == KEY_LEFT else 1)
				KEY_T: _open_track_picker()
				KEY_C: _open_car_picker()
				KEY_ENTER, KEY_KP_ENTER:
					if key.alt_pressed or key.echo:
						return
					_activate_hub_focus()
				_: return
		elif k in [KEY_ENTER, KEY_KP_ENTER] and not key.echo and not key.alt_pressed and _screen != Screen.SETTINGS:
			_next()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	var pad := e as InputEventJoypadButton
	if pad and pad.pressed and pad.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER] and _nav.visible:
		_nav.step(-1 if pad.button_index == JOY_BUTTON_LEFT_SHOULDER else 1)
	elif e.is_action_pressed("ui_cancel"):
		_back()
	elif _screen != Screen.RACE:
		return
	elif e.is_action_pressed("ui_down", true):
		_move_hub_focus(1)
	elif e.is_action_pressed("ui_up", true):
		_move_hub_focus(-1)
	elif e.is_action_pressed("ui_left", true) and _hub_focus is OptionRow:
		(_hub_focus as OptionRow).step(-1)
	elif e.is_action_pressed("ui_right", true) and _hub_focus is OptionRow:
		(_hub_focus as OptionRow).step(1)
	elif e.is_action_pressed("ui_accept"):
		_activate_hub_focus()
	else:
		return
	get_viewport().set_input_as_handled()


## Enter on the setup: a card opens its picker, anything else starts the race.
func _activate_hub_focus() -> void:
	if _hub_focus == _track_card:
		_open_track_picker()
	elif _hub_focus == _car_card:
		_open_car_picker()
	else:
		_next()


func _gui_input(e: InputEvent) -> void:
	# A right click anywhere that doesn't take it: back.
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT and not _top_level(_screen):
		_back()
		accept_event()


func _process(dt: float) -> void:
	_time += dt
	if _car_pending >= 0 and not _starting:
		_car_pending_t -= dt
		if _car_pending_t <= 0.0:
			_show_car_now(_car_pending)
	# Slow drift on the backdrop keeps the scene alive.
	_photo_drift.position = Vector2(sin(_time * 0.07), cos(_time * 0.05)) * size * 0.02
	if _pursuit_lights():
		_overlay.queue_redraw()
	if _toast_t > 0.0:
		_toast_t -= dt
		_overlay.queue_redraw()
	if _quit_armed_until > 0 and not _quit_armed():
		_quit_armed_until = 0
		_show_quit_armed(false)


func _start() -> void:
	if _starting:
		return
	_starting = true
	Game.circuit_run = {}
	Game.mode = _mode as Game.Mode
	Game.track_id = Game.tracks[_track_i]
	Game.car_index = _car_i
	Game.laps = _laps.index + 1
	Game.opponents = _opp_value
	Game.traffic = _traffic.index == 1
	Game.night = _time_row.index == 1 or Game.night_only(Game.track_id)
	Game.weather = _weather.index == 1
	Game.layout = _layout_row.index
	Game.save_settings()
	_launch()


## Into the chosen tournament circuit (Game.start_circuit sets its first race up) with the
## car chosen here; the rest is the circuit's.
func _enter_circuit() -> void:
	Game.car_index = _car_i
	var err := Game.start_circuit(_tour.t, _tour.cid)
	if err != "":
		_say(err, UiKit.COP_RED)
		return
	_starting = true
	_launch()


## The race scene, after the car's engine is revved and the loading screen fades in.
func _launch() -> void:
	_next_btn.flash()
	var rev := _showroom.rev()
	# The race's loading screen fades in over the menu; the race scene opens on the same one.
	var loading := LoadingScreen.new()
	loading.stage("Getting ready", 0.0, 0.03)
	loading.modulate.a = 0.0
	add_child(loading)
	var tw := create_tween()
	tw.tween_property(loading, "modulate:a", 1.0, 0.4).set_delay(maxf(rev - 0.45, 0.0))
	await tw.finished
	loading.hand_over()
	# Let it reach the screen before the scene change (which blocks while it loads).
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/race.tscn")
