class_name SettingsPanel
extends Control
## The settings, in pages along the top (a click, or Tab / Shift+Tab): GAMEPLAY, GRAPHICS,
## AUDIO, HUD (its style and each part on or off, with a sketch of the race screen showing
## where they are), CONTROLS (the keys) and GAME DATA (what was found where). Down the left
## the page's options; beside them what the focused one does. Changes apply as they're made
## (in a race too) and are saved on closing.
## The menu shows it as a page of its own (`embedded`); the pause menu over the race, framed.

signal closed
signal changed

const CONTROLS := [
	["Driving", [[["↑", "W"], "Throttle"], [["↓", "S"], "Brake · reverse"], [["←→", "A", "D"], "Steer"], [["SPACE"], "Handbrake"]]],
	["Camera", [[["C"], "Change camera"], [["B"], "Look back"], [["M"], "Mirror on / off"]]],
	["Car", [[["R"], "Reset car"], [["H"], "Horn"], [["L"], "Lights"], [["K"], "High beam"]]],
	["Game", [[["ESC"], "Pause"], [["F1"], "HUD on / off"], [["F11"], "Fullscreen (or Alt+Enter)"]]],
	["Menus", [[["↑↓"], "Move"], [["←→"], "Change a setting"], [["ENTER"], "Choose · start"], [["ESC"], "Back"],
		[["Q", "E"], "Switch tab"], [["TAB"], "Next page or filter"]]],
]
const ROW_H := 38.0
const PAGES := ["Gameplay", "Graphics", "Audio", "HUD", "Controls", "Game data"]
const PAGE_HUD := 3
const PAGE_CONTROLS := 4
const PAGE_DATA := 5
## Where each HUD part sits on a 1280 x 720 screen, for the sketch.
const WIDGET_RECTS := {
	"standings": Rect2(36, 36, 290, 130), "police": Rect2(36, 184, 210, 66), "lap": Rect2(36, 440, 190, 50),
	"map": Rect2(36, 494, 190, 190), "speed": Rect2(1008, 470, 236, 214), "mirror": Rect2(440, 16, 400, 100),
	"messages": Rect2(400, 190, 480, 58), "countdown": Rect2(548, 196, 184, 184), "lights": Rect2(0, 0, 1280, 6),
	"hints": Rect2(420, 654, 440, 30),
}
const WIDGET_HELP := {
	"speed": "The speed, gear and rev counter (or High Stakes' dials).",
	"standings": "Everyone's place and gap to the leader, top left.",
	"police": "In a pursuit: the chase, the heat and your tickets.",
	"lap": "The lap you're on, your best lap and how far round you are.",
	"map": "The track from above with every car on it.",
	"mirror": "The rear-view mirror, top centre. M shows or hides it during a race; on Low quality it starts hidden.",
	"messages": "Banners for lap times, the final lap, places and the police.",
	"countdown": "The 3, 2, 1 before the start.",
	"lights": "The red and blue bar along the top while the police chase you.",
	"hints": "The keys at the start of a race, and the camera's name when you change it.",
}

var in_race := false             # opened from the pause menu: some changes wait for the next race
var embedded := false            # a page of the menu, not an overlay

var _panel: Control
var _tabs: TabStrip
var _page := 0
var _defs: Array[Dictionary] = []   # {id, caption, items, get: Callable, set: Callable, help, later, slider}
var _rows := {}                  # id -> OptionRow
var _pages: Array = []           # per page: [ids]
var _focus := ""
var _all: HintBar                # show all / hide all, on the HUD page
var _back: HintBar               # the overlay's way out


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	draw.connect(func(): if not embedded: draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.012, 0.02, 0.9)))
	gui_input.connect(func(e: InputEvent):
		if not embedded and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT \
				and not _panel.get_rect().has_point(e.position):
			close())
	_panel = Control.new()
	_panel.draw.connect(_draw_panel)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)
	_tabs = TabStrip.new(PackedStringArray(PAGES), TabStrip.Style.TABS)
	_tabs.font_size = 15
	_tabs.custom_minimum_size.y = 38
	_tabs.size.y = 38
	_tabs.set_items(_tabs.items, 0)
	_tabs.changed.connect(_show_page)
	_panel.add_child(_tabs)
	_define()
	for d in _defs:
		var r := OptionRow.new(d.caption, d.items)
		r.caption_w = 150.0
		r.slider = d.get("slider", false)
		r.custom_minimum_size.y = ROW_H
		var id: String = d.id
		r.hovered.connect(func(): _set_focus(id))
		r.changed.connect(func(i: int): _apply(id, i))
		_panel.add_child(r)
		_rows[id] = r
	_all = HintBar.new()
	_all.set_hints([["", "SHOW ALL", func(): _set_all(true)], ["", "HIDE ALL", func(): _set_all(false)]])
	_panel.add_child(_all)
	_back = HintBar.new()
	_back.set_hints([["ESC", "BACK", close]])
	_panel.add_child(_back)
	resized.connect(_layout)


func _define() -> void:
	var vol := PackedStringArray()
	for v in 11:
		vol.append("Off" if v == 0 else str(v))
	var off_on := PackedStringArray(["Off", "On"])
	_defs = [
		{"id": "units", "caption": "Units", "items": PackedStringArray(["km/h", "mph"]),
			"get": func() -> int: return 0 if Game.units_kmh else 1, "set": func(i: int): Game.units_kmh = i == 0,
			"help": "Speedometer and distances in km/h and km, or mph and miles."},
		{"id": "damage", "caption": "Damage", "items": off_on, "later": true,
			"get": func() -> int: return int(Game.damage), "set": func(i: int): Game.damage = i == 1,
			"help": "Crashes dent the cars and cost them power (not in the original)."},
		{"id": "tops", "caption": "Cabriolets", "items": PackedStringArray(["Top down", "Top up"]), "later": true,
			"get": func() -> int: return 0 if Game.tops_down else 1, "set": func(i: int): Game.set_tops_down(i == 0),
			"help": "Porsche Unleashed's cabriolets, roadsters and Speedsters with the hood folded or raised."},
		{"id": "intro", "caption": "Start fly-by", "items": off_on, "later": true,
			"get": func() -> int: return int(Game.intro_flyby), "set": func(i: int): Game.intro_flyby = i == 1,
			"help": "The camera flies round the grid before the countdown. Any key skips it."},
		{"id": "quality", "caption": "Quality", "items": PackedStringArray(Game.QUALITY_NAMES), "later": true,
			"get": func() -> int: return Game.quality, "set": func(i: int): Game.quality = i as Game.Quality,
			"help": "Shadows, anti-aliasing, the cars' lamps lighting the road and the 3D resolution. Low suits integrated graphics."},
		{"id": "display", "caption": "Display", "items": PackedStringArray(["Window", "Fullscreen"]),
			"get": func() -> int: return int(Game.fullscreen), "set": func(i: int): Game.fullscreen = i == 1,
			"help": "A window, or the whole screen. F11 or Alt+Enter switch at any time."},
		{"id": "vsync", "caption": "V-Sync", "items": off_on,
			"get": func() -> int: return int(Game.vsync), "set": func(i: int): Game.vsync = i == 1,
			"help": "Waits for the monitor's refresh: no tearing, a little more input lag."},
		{"id": "volume", "caption": "Master", "items": vol, "slider": true,
			"get": func() -> int: return Game.volume, "set": func(i: int): Game.volume = i,
			"help": "Everything you hear."},
		{"id": "music", "caption": "Music", "items": vol, "slider": true,
			"get": func() -> int: return Game.music_volume, "set": func(i: int): Game.music_volume = i,
			"help": "The music in the menus and races. Off turns it off."},
		{"id": "sfx", "caption": "Effects", "items": vol, "slider": true,
			"get": func() -> int: return Game.sfx_volume, "set": func(i: int): Game.sfx_volume = i,
			"help": "Engines, tyres, crashes, sirens, the weather and the menus' clicks."},
		{"id": "voice", "caption": "Voice", "items": vol, "slider": true,
			"get": func() -> int: return Game.voice_volume, "set": func(i: int): Game.voice_volume = i,
			"help": "The countdown, lap calls and the police's loudhailer and radio."},
		{"id": "hud_on", "caption": "HUD", "items": PackedStringArray(["Hidden", "Shown"]),
			"get": func() -> int: return int(Game.hud_on), "set": func(i: int): Game.hud_on = i == 1,
			"help": "The whole HUD at once. F1 does the same during a race."},
		{"id": "hud_style", "caption": "Dials", "items": PackedStringArray(["Modern", "HS · top", "HS · bottom"]),
			"get": func() -> int: return Game.hud_style, "set": func(i: int): Game.hud_style = i,
			"help": "The speedometer and rev counter: this game's own, or High Stakes' dials, either side of the mirror as it had them or together at the bottom."},
	]
	var widgets := []
	for id: String in Game.HUD_WIDGETS:
		widgets.append(id)
		_defs.append({"id": id, "caption": Game.HUD_WIDGETS[id], "items": off_on,
			"get": func() -> int: return int(not id in Game.hud_hidden),
			"set": func(i: int):
				Game.hud_hidden.erase(id)
				if i == 0:
					Game.hud_hidden.append(id),
			"help": WIDGET_HELP[id]})
	_pages = [["units", "damage", "intro"], ["quality", "display", "vsync"], ["volume", "music", "sfx", "voice"],
		["hud_on", "hud_style"] + widgets, [], []]


func _def(id: String) -> Dictionary:
	for d in _defs:
		if d.id == id:
			return d
	return {}


## `page`: an index into PAGES (3 the HUD's).
func open(page := 0) -> void:
	for d in _defs:
		_rows[d.id].set_items(_rows[d.id].items, d.get.call())
	visible = true
	if not embedded:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	show_page(page)
	if embedded:
		return
	modulate.a = 0.0
	var y := _panel.position.y
	_panel.position.y = y + 16
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.18)
	tw.tween_property(_panel, "position:y", y, 0.25)


func show_page(page: int) -> void:
	_tabs.set_items(_tabs.items, page)
	_show_page(page)


func close() -> void:
	if not visible:
		return
	visible = false
	Game.save_settings()
	closed.emit()


## Key hints for the menu's footer.
func hints() -> Array:
	var h: Array = [["TAB", "NEXT PAGE", func(): _tabs.step(1)]]
	if not _order().is_empty():
		h = [["↑↓", "SELECT"], ["←→", "CHANGE"]] + h
	return h


func _show_page(p: int) -> void:
	_page = p
	var ids := _order()
	for id in _rows:
		_rows[id].visible = id in ids
	_all.visible = p == PAGE_HUD
	if not ids.is_empty():
		_set_focus(ids[0])
	_layout()


func _data_text() -> String:
	var t := ""
	if Game.has_game_data():
		t = "Need for Speed III\n%s\n%d tracks · %d cars · %d police · %d traffic" % [
			Game.data_root, Game.tracks.filter(func(id: String) -> bool: return not Game.is_hs_track(id) and not Game.is_pu_track(id) and id != Game.PROCEDURAL_TRACK).size(),
			Game.cars.filter(func(c: Dictionary) -> bool: return not c.id.begins_with(Game.HS_PREFIX)).size(), Game.cop_cars.size(), Game.traffic_cars.size()]
	else:
		t = "No NFS3 data found, so you get the generated circuit and stand-in cars. Point the NFS3_DATA environment variable at a folder containing gamedata/ (see README)."
	if Game.hs_root != "":
		t += "\n\nHigh Stakes\n%s\n%d tracks · %d cars · %d police · %d traffic" % [Game.hs_root,
			Game.tracks.filter(func(id: String) -> bool: return Game.is_hs_track(id)).size(),
			Game.cars.filter(func(c: Dictionary) -> bool: return c.id.begins_with(Game.HS_PREFIX)).size(),
			Game.hs_cop_cars.size(), Game.hs_traffic_cars.size()]
	if Game.pu_root != "":
		t += "\n\nPorsche Unleashed\n%s\n%d tracks" % [Game.pu_root, Game.tracks.filter(func(id: String) -> bool: return Game.is_pu_track(id)).size()]
	return t


func _apply(id: String, i: int) -> void:
	_def(id).set.call(i)
	Game.apply_display()
	_panel.queue_redraw()
	changed.emit()


func _set_all(on: bool) -> void:
	Game.hud_on = true
	Game.hud_hidden.clear()
	if not on:
		for id: String in Game.HUD_WIDGETS:
			Game.hud_hidden.append(id)
	for d in _defs:
		_rows[d.id].set_items(_rows[d.id].items, d.get.call())
	_panel.queue_redraw()
	changed.emit()


func _set_focus(id: String) -> void:
	_focus = id
	for k in _rows:
		_rows[k].focused = k == id
	_panel.queue_redraw()


func _order() -> Array:
	return _pages[_page]


# ------------------------------------------------------------------ layout

func _pad() -> Vector2:
	return Vector2(14, 0) if embedded else Vector2(36, 28)


func _content_top() -> float:
	return 60.0 if embedded else 124.0


func _col_w() -> float:
	return minf(520.0, (_panel.size.x - _pad().x * 2) * 0.48)


func _right_x() -> float:
	return _pad().x + _col_w() + 48


func _layout() -> void:
	if embedded:
		_panel.position = Vector2.ZERO
		_panel.size = size
	else:
		_panel.size = Vector2(minf(1040.0, size.x - 48), minf(640.0, size.y - 32))
		_panel.position = ((size - _panel.size) * 0.5).round()
	var p := _pad()
	_tabs.position = Vector2(p.x - 28, _content_top() - 52)
	_tabs.size.x = _tabs.custom_minimum_size.x
	_back.visible = not embedded
	_back.position = Vector2(_panel.size.x - p.x - _back.size.x + 8, p.y + 6)
	var cw := _col_w()
	var y := _content_top() + 10
	for id: String in _order():
		_rows[id].position = Vector2(p.x - 14, y)
		_rows[id].size = Vector2(cw + 14, ROW_H)
		y += ROW_H
		if id == "hud_style":
			y += 18   # the widgets under it
	_all.position = Vector2(_right_x() - 10, _sketch_rect().end.y + 8)
	_panel.queue_redraw()


func _sketch_rect() -> Rect2:
	var w := _panel.size.x - _pad().x - _right_x()
	return Rect2(_right_x(), _content_top() + 14, w, w * 9.0 / 16.0)


# ------------------------------------------------------------------ input

func _unhandled_input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var order := _order()
	var at := order.find(_focus)
	var key := e as InputEventKey
	var pad := e as InputEventJoypadButton
	if key and key.pressed and key.physical_keycode == KEY_TAB:
		_tabs.step(-1 if key.shift_pressed else 1)
	elif not embedded and pad and pad.pressed and pad.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		_tabs.step(-1 if pad.button_index == JOY_BUTTON_LEFT_SHOULDER else 1)
	elif e.is_action_pressed("ui_cancel") or (not embedded and pad and pad.pressed and pad.button_index == JOY_BUTTON_Y) \
			or (in_race and e.is_action_pressed("pause")):
		close()
	elif order.is_empty():
		return
	elif e.is_action_pressed("ui_down", true):
		_set_focus(order[posmod(at + 1, order.size())])
	elif e.is_action_pressed("ui_up", true):
		_set_focus(order[posmod(at - 1, order.size())])
	elif e.is_action_pressed("ui_left", true):
		_rows[_focus].step(-1)
	elif e.is_action_pressed("ui_right", true):
		_rows[_focus].step(1)
	else:
		return
	get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ drawing

func _draw_panel() -> void:
	var p := _panel
	var pad := _pad()
	if not embedded:
		p.draw_string(UiKit.font("display"), Vector2(pad.x, pad.y + 30), "SETTINGS", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, UiKit.INK)
	p.draw_line(Vector2(pad.x - 14, _content_top() - 12), Vector2(p.size.x - pad.x + 14, _content_top() - 12), UiKit.LINE, 1.0)
	var cw := _col_w()
	var rx := _right_x()
	var rw := p.size.x - pad.x - rx
	var bf := UiKit.font("body")
	match _page:
		PAGE_CONTROLS:
			_draw_controls(p, Vector2(pad.x, _content_top() + 26), p.size.x - pad.x * 2)
			return
		PAGE_DATA:
			UiKit.kicker(p, Vector2(pad.x, _content_top() + 26), "Where the game data was found", cw * 2)
			p.draw_multiline_string(bf, Vector2(pad.x, _content_top() + 56), _data_text(), HORIZONTAL_ALIGNMENT_LEFT,
				p.size.x - pad.x * 2, 15, -1, UiKit.INK_DIM)
			return
		PAGE_HUD:
			var wy: float = _rows["hud_style"].position.y + ROW_H + 14
			UiKit.kicker(p, Vector2(pad.x - 14, wy), "Its parts", cw)
			_draw_sketch(p)
	# What the focused option does: beside the rows (under the sketch on the HUD page).
	var d := _def(_focus)
	var help: String = d.get("help", "")
	if in_race and d.get("later", false):
		help += " Changes from the next race."
	if help == "":
		return
	var hy := _content_top() + 20 if _page != PAGE_HUD else _all.position.y + 52
	var caption: String = d.get("caption", "")
	UiKit.kicker(p, Vector2(rx, hy + 14), caption, rw)
	p.draw_multiline_string(bf, Vector2(rx, hy + 38), help, HORIZONTAL_ALIGNMENT_LEFT, minf(rw, 460), 16, 4, UiKit.INK_DIM)


func _draw_controls(p: Control, pos: Vector2, w: float) -> void:
	var cols := 3
	var cw := (w - 40.0 * (cols - 1)) / cols
	var col_y := [pos.y, pos.y, pos.y]
	for g in CONTROLS.size():
		var c := g % cols if g < cols else int(col_y.find(col_y.min()))
		var x := pos.x + c * (cw + 40.0)
		var y: float = col_y[c]
		UiKit.kicker(p, Vector2(x, y), CONTROLS[g][0], cw)
		y += 30
		for row in CONTROLS[g][1]:
			var kx := 0.0
			for k in row[0]:
				kx += UiKit.draw_key(p, Vector2(x + kx, y), k, 13) + 4.0
			p.draw_string(UiKit.font("body"), Vector2(x + maxf(kx, 70.0) + 8, y + 5), row[1], HORIZONTAL_ALIGNMENT_LEFT,
				cw - maxf(kx, 70.0) - 8, 15, UiKit.INK_DIM)
			y += 32
		col_y[c] = y + 18


## The race screen in miniature: each HUD part where it sits, lit if it's on, the focused
## one picked out.
func _draw_sketch(p: Control) -> void:
	var sr := _sketch_rect()
	UiKit.box(p, sr, Color(0.12, 0.14, 0.17), 4)
	# A hint of road, so it reads as the race.
	var road := PackedVector2Array([sr.position + Vector2(sr.size.x * 0.46, sr.size.y * 0.45),
		sr.position + Vector2(sr.size.x * 0.54, sr.size.y * 0.45), sr.end, Vector2(sr.position.x, sr.end.y)])
	p.draw_colored_polygon(road, Color(0.2, 0.21, 0.24))
	UiKit.box(p, sr, Color(0, 0, 0, 0), 4, Color(1, 1, 1, 0.2))
	var s := sr.size.x / 1280.0
	for id: String in WIDGET_RECTS:
		var wr: Rect2 = WIDGET_RECTS[id]
		var rects: Array[Rect2] = [wr]
		if id == "speed" and Game.hud_style > 0:
			rects = ClassicGauges.dial_rects(Vector2(1280, 720), Game.hud_style - 1)
		elif id in ["standings", "police"] and Game.hud_style == 1 and Game.hud_shows("speed"):
			# Under High Stakes' speedometer, as in the race.
			wr.position.y += ClassicGauges.dial_height(720) - 8
			rects = [wr]
		for rr0 in rects:
			_sketch_widget(p, Rect2(sr.position + rr0.position * s, rr0.size * s), id)
	if not Game.hud_on:
		UiKit.box(p, sr, Color(0, 0, 0, 0.55), 4)
		p.draw_string(UiKit.font("display"), Vector2(sr.position.x, sr.get_center().y + 10), "HUD HIDDEN",
			HORIZONTAL_ALIGNMENT_CENTER, sr.size.x, 28, UiKit.ACCENT)


## One HUD part in the sketch: lit if it's on, picked out if it's the focused row.
func _sketch_widget(p: Control, rr: Rect2, id: String) -> void:
	var on := Game.hud_shows(id)
	var now := id == _focus
	var col := UiKit.ACCENT if now else (UiKit.INK if on else UiKit.INK_FAINT)
	if on:
		p.draw_rect(rr, Color(col, 0.35 if now else 0.16))
	p.draw_rect(rr, Color(col, 1.0 if now else (0.5 if on else 0.35)), false, 2.0 if now else 1.0)
	if rr.size.y > 12:
		p.draw_string(UiKit.font("cond", 1), Vector2(rr.position.x, rr.get_center().y + 4), Game.HUD_WIDGETS[id].to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, 10, Color(col, 1.0 if on or now else 0.6))
