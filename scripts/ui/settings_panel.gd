class_name SettingsPanel
extends Control
## The settings overlay, in two pages (Q / E or the tabs). GENERAL: graphics, sound and
## gameplay down the left, the controls and where the game data was found down the right.
## HUD: the race HUD's style and each of its parts on or off, with a sketch of the screen
## showing where they are. A line under the options says what the focused one does.
## Changes apply as they're made (in a race too, from the pause menu) and are saved on closing.

signal closed
signal changed

const CONTROLS := [
	[["↑↓", "W", "S"], "Throttle · brake"], [["←→", "A", "D"], "Steer"], [["SPACE"], "Handbrake"],
	[["C"], "Change camera"], [["B"], "Look back"], [["R"], "Reset car"], [["H"], "Horn"],
	[["L", "K"], "Lights · high beam"], [["M"], "Mirror"], [["F1"], "HUD on / off"], [["ESC"], "Pause"],
	[["F11"], "Fullscreen"],
]
const ROW_H := 34.0
const HEAD_H := 30.0
const TOP := 112.0
const PAGES := ["GENERAL", "HUD"]
## Where each HUD part sits on a 1280 x 720 screen, for the sketch.
const WIDGET_RECTS := {
	"standings": Rect2(36, 36, 290, 130), "police": Rect2(36, 184, 210, 66), "lap": Rect2(36, 440, 190, 50),
	"map": Rect2(36, 494, 190, 190), "speed": Rect2(1008, 470, 236, 214), "mirror": Rect2(440, 16, 400, 100),
	"messages": Rect2(400, 190, 480, 58), "countdown": Rect2(548, 196, 184, 184), "lights": Rect2(0, 0, 1280, 6),
	"hints": Rect2(420, 654, 440, 30),
}
const WIDGET_HELP := {
	"speed": "The speed, gear and rev counter (or High Stakes' dials, top right).",
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

var _panel: Control
var _tabs: TabStrip
var _page := 0
var _defs: Array[Dictionary] = []   # {id, caption, items, get: Callable, set: Callable, help, later}
var _rows := {}                  # id -> OptionRow
var _groups: Array = []          # [page, title, [ids]]
var _focus := ""
var _status: Label
var _all: HintBar                # show all / hide all, on the HUD page
var _back_hot := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	draw.connect(func(): draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.012, 0.02, 0.8)))
	gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT \
				and not _panel.get_rect().has_point(e.position):
			close())
	_panel = Control.new()
	_panel.draw.connect(_draw_panel)
	_panel.gui_input.connect(_on_panel_input)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	_tabs = TabStrip.new(PackedStringArray(PAGES), TabStrip.Style.TABS)
	_tabs.keys = PackedStringArray(["Q", "E"])
	_tabs.set_items(_tabs.items, 0)
	_tabs.changed.connect(_show_page)
	_panel.add_child(_tabs)
	_define()
	for d in _defs:
		var r := OptionRow.new(d.caption, d.items)
		r.caption_w = 118.0
		r.custom_minimum_size.y = ROW_H
		var id: String = d.id
		r.hovered.connect(func(): _set_focus(id))
		r.changed.connect(func(i: int): _apply(id, i))
		_panel.add_child(r)
		_rows[id] = r
	_status = UiKit.label("", "body", 13, UiKit.INK_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_status)
	_all = HintBar.new()
	_all.set_hints([["", "SHOW ALL", func(): _set_all(true)], ["", "HIDE ALL", func(): _set_all(false)]])
	_panel.add_child(_all)
	resized.connect(_layout)


func _define() -> void:
	var vol := PackedStringArray()
	for v in 11:
		vol.append("OFF" if v == 0 else str(v))
	var off_on := PackedStringArray(["Off", "On"])
	_defs = [
		{"id": "quality", "caption": "Quality", "items": PackedStringArray(Game.QUALITY_NAMES), "later": true,
			"get": func() -> int: return Game.quality, "set": func(i: int): Game.quality = i as Game.Quality,
			"help": "Shadows, anti-aliasing, the cars' lamps lighting the road and the 3D resolution. Low suits integrated graphics."},
		{"id": "display", "caption": "Display", "items": PackedStringArray(["Window", "Fullscreen"]),
			"get": func() -> int: return int(Game.fullscreen), "set": func(i: int): Game.fullscreen = i == 1,
			"help": "A window, or the whole screen (F11 or Alt+Enter switch at any time)."},
		{"id": "vsync", "caption": "V-Sync", "items": off_on,
			"get": func() -> int: return int(Game.vsync), "set": func(i: int): Game.vsync = i == 1,
			"help": "Waits for the monitor's refresh: no tearing, a little more input lag."},
		{"id": "volume", "caption": "Volume", "items": vol,
			"get": func() -> int: return Game.volume, "set": func(i: int): Game.volume = i,
			"help": "Everything you hear."},
		{"id": "music", "caption": "Music", "items": vol,
			"get": func() -> int: return Game.music_volume, "set": func(i: int): Game.music_volume = i,
			"help": "The music in the menus and races. Off turns it off."},
		{"id": "sfx", "caption": "Effects", "items": vol,
			"get": func() -> int: return Game.sfx_volume, "set": func(i: int): Game.sfx_volume = i,
			"help": "Engines, tyres, crashes, sirens, the weather and the menus' clicks."},
		{"id": "voice", "caption": "Voice", "items": vol,
			"get": func() -> int: return Game.voice_volume, "set": func(i: int): Game.voice_volume = i,
			"help": "The countdown, lap calls and the police's loudhailer and radio."},
		{"id": "units", "caption": "Units", "items": PackedStringArray(["km/h", "mph"]),
			"get": func() -> int: return 0 if Game.units_kmh else 1, "set": func(i: int): Game.units_kmh = i == 0,
			"help": "Speedometer and distances in km/h and km, or mph and miles."},
		{"id": "damage", "caption": "Damage", "items": off_on, "later": true,
			"get": func() -> int: return int(Game.damage), "set": func(i: int): Game.damage = i == 1,
			"help": "Crashes dent the cars and cost them power (not in the original)."},
		{"id": "rivals", "caption": "Rival cars", "items": PackedStringArray(["Stock", "Like yours", "Full"]), "later": true,
			"get": func() -> int: return Game.rival_upgrades, "set": func(i: int): Game.rival_upgrades = i,
			"help": "How the AI's cars are tuned: stock, with the same upgrades as yours, or fully upgraded."},
		{"id": "rival_class", "caption": "Rival class", "items": PackedStringArray(["Yours", "Any"]), "later": true,
			"get": func() -> int: return Game.rival_class, "set": func(i: int): Game.rival_class = i,
			"help": "Which cars the AI drives: ones of your car's class (the nearest classes if there aren't enough), or any car."},
		{"id": "intro", "caption": "Intro", "items": PackedStringArray(["Off", "Fly-by"]), "later": true,
			"get": func() -> int: return int(Game.intro_flyby), "set": func(i: int): Game.intro_flyby = i == 1,
			"help": "The camera flies round the grid before the countdown. Any key skips it."},
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
	_groups = [[0, "GRAPHICS", ["quality", "display", "vsync"]], [0, "SOUND", ["volume", "music", "sfx", "voice"]],
		[0, "GAMEPLAY", ["units", "damage", "rivals", "rival_class", "intro"]], [1, "HUD", ["hud_on", "hud_style"]],
		[1, "WIDGETS", widgets]]


func _def(id: String) -> Dictionary:
	for d in _defs:
		if d.id == id:
			return d
	return {}


## `page`: 0 general, 1 the HUD's.
func open(page := 0) -> void:
	for d in _defs:
		_rows[d.id].set_items(_rows[d.id].items, d.get.call())
	_status.text = _data_text()
	visible = true
	_tabs.set_items(_tabs.items, page)
	_show_page(page)
	modulate.a = 0.0
	var y := _panel.position.y
	_panel.position.y = y + 24
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.2)
	tw.tween_property(_panel, "position:y", y, 0.3)


func close() -> void:
	if not visible:
		return
	visible = false
	Game.save_settings()
	closed.emit()


func _show_page(p: int) -> void:
	_page = p
	var ids := _order()
	for id in _rows:
		_rows[id].visible = id in ids
	_status.visible = p == 0
	_all.visible = p == 1
	_set_focus(ids[0])
	_layout()


func _data_text() -> String:
	var t := ""
	if Game.has_game_data():
		t = "NFS III: %s\n%d tracks · %d cars · %d police · %d traffic" % [
			Game.data_root, Game.tracks.filter(func(id: String) -> bool: return not Game.is_hs_track(id) and id != Game.PROCEDURAL_TRACK).size(),
			Game.cars.filter(func(c: Dictionary) -> bool: return not c.id.begins_with(Game.HS_PREFIX)).size(), Game.cop_cars.size(), Game.traffic_cars.size()]
	else:
		t = "No NFS3 data found, so you get the generated circuit and stand-in cars. Point the NFS3_DATA environment variable at a folder containing gamedata/ (see README)."
	if Game.hs_root != "":
		t += "\n\nHigh Stakes: %s\n%d tracks · %d cars · %d police · %d traffic" % [Game.hs_root,
			Game.tracks.filter(func(id: String) -> bool: return Game.is_hs_track(id)).size(),
			Game.cars.filter(func(c: Dictionary) -> bool: return c.id.begins_with(Game.HS_PREFIX)).size(),
			Game.hs_cop_cars.size(), Game.hs_traffic_cars.size()]
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


func _col_w() -> float:
	return (_panel.size.x - 84 - 48) * 0.5


## This page's groups: [title, [ids], top y (panel space)], and last where the help goes.
func _page_groups() -> Array:
	var out := []
	var y := TOP
	for g in _groups:
		if g[0] != _page:
			continue
		out.append([g[1], g[2], y])
		y += HEAD_H + g[2].size() * ROW_H + 8
	out.append(["", [], y])
	return out


func _order() -> Array:
	var out := []
	for g in _groups:
		if g[0] == _page:
			out.append_array(g[2])
	return out


func _layout() -> void:
	_panel.size = Vector2(minf(1000.0, size.x - 48), minf(660.0, size.y - 24))
	_panel.position = ((size - _panel.size) * 0.5).round()
	_tabs.position = Vector2(250, 36)
	_tabs.size = Vector2(_tabs.custom_minimum_size.x, 44)
	var cw := _col_w()
	for g in _page_groups():
		var y: float = g[2] + HEAD_H - 8
		for id: String in g[1]:
			_rows[id].position = Vector2(20, y)
			_rows[id].size = Vector2(cw + 22, ROW_H)
			y += ROW_H
	var rx := 42 + cw + 48
	_status.position = Vector2(rx, TOP + 6 * 30 + 64)
	_status.size = Vector2(cw, 140)
	_all.position = Vector2(rx - 8, _sketch_rect().end.y + 14)


func _sketch_rect() -> Rect2:
	var cw := _col_w()
	return Rect2(42 + cw + 48, TOP + 26, cw, cw * 9.0 / 16.0)


func _back_rect() -> Rect2:
	return Rect2(_panel.size.x - 130, 36, 92, 32)


func _on_panel_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var hot := _back_rect().has_point(e.position)
		if hot != _back_hot:
			_back_hot = hot
			_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hot else Control.CURSOR_ARROW
			_panel.queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _back_rect().has_point(e.position):
		close()


func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	var order := _order()
	var at := order.find(_focus)
	var key := e as InputEventKey
	var pad := e as InputEventJoypadButton
	if e.is_action_pressed("ui_down", true):
		_set_focus(order[posmod(at + 1, order.size())])
	elif e.is_action_pressed("ui_up", true):
		_set_focus(order[posmod(at - 1, order.size())])
	elif e.is_action_pressed("ui_left", true):
		_rows[_focus].step(-1)
	elif e.is_action_pressed("ui_right", true):
		_rows[_focus].step(1)
	elif key and key.pressed and not key.echo and key.physical_keycode in [KEY_Q, KEY_E]:
		_tabs.step(-1 if key.physical_keycode == KEY_Q else 1)
	elif pad and pad.pressed and pad.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		_tabs.step(-1 if pad.button_index == JOY_BUTTON_LEFT_SHOULDER else 1)
	elif e.is_action_pressed("ui_cancel") or (key and key.pressed and not key.echo and key.physical_keycode == KEY_TAB) \
			or (pad and pad.pressed and pad.button_index == JOY_BUTTON_Y) or (in_race and e.is_action_pressed("pause")):
		close()
	else:
		return
	get_viewport().set_input_as_handled()


func _draw_panel() -> void:
	var p := _panel
	var r := Rect2(Vector2.ZERO, p.size)
	p.draw_rect(r, Color(0.05, 0.055, 0.075, 0.98))
	p.draw_rect(Rect2(0, 0, r.size.x, 3), UiKit.ACCENT)
	p.draw_string(UiKit.font("display"), Vector2(42, 70), "SETTINGS", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, UiKit.INK)
	var br := _back_rect()
	if _back_hot:
		UiKit.draw_slant(p, br, Color(UiKit.ACCENT, 0.12), 0.15)
	var kw := UiKit.draw_key(p, br.position + Vector2(8, 16), "ESC", 12, UiKit.ACCENT if _back_hot else UiKit.INK)
	p.draw_string(UiKit.font("cond", 2), br.position + Vector2(16 + kw, 21), "BACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		UiKit.ACCENT if _back_hot else UiKit.INK_DIM)
	var cw := _col_w()
	var groups := _page_groups()
	for k in groups.size() - 1:
		_section(p, groups[k][0], Vector2(42, groups[k][2] + 12), cw)
	# What the focused option does.
	var d := _def(_focus)
	var help: String = d.get("help", "")
	if in_race and d.get("later", false):
		help += " Changes from the next race."
	var hy: float = groups[-1][2] + 4
	p.draw_rect(Rect2(42, hy, 3, 40), UiKit.ACCENT)
	p.draw_multiline_string(UiKit.font("body"), Vector2(56, hy + 15), help, HORIZONTAL_ALIGNMENT_LEFT, cw - 20, 14, 3,
		UiKit.INK_DIM)
	var rx := 42 + cw + 48
	if _page == 0:
		_section(p, "CONTROLS", Vector2(rx, TOP + 12), cw)
		for i in CONTROLS.size():
			var pos := Vector2(rx + (i % 2) * cw * 0.5, TOP + 40 + (i / 2) * 30)
			var kx := 0.0
			for k in CONTROLS[i][0]:
				kx += UiKit.draw_key(p, pos + Vector2(kx, 0), k, 12) + 4.0
			p.draw_string(UiKit.font("body"), pos + Vector2(kx + 6, 5), CONTROLS[i][1], HORIZONTAL_ALIGNMENT_LEFT,
				cw * 0.5 - kx - 12, 14, UiKit.INK_DIM)
		_section(p, "GAME DATA", Vector2(rx, TOP + 6 * 30 + 48), cw)
	else:
		_section(p, "ON SCREEN", Vector2(rx, TOP + 12), cw)
		_draw_sketch(p)


## The race screen in miniature: each HUD part where it sits, lit if it's on, the focused
## one picked out.
func _draw_sketch(p: Control) -> void:
	var sr := _sketch_rect()
	p.draw_rect(sr, Color(0.12, 0.14, 0.17))
	# A hint of road, so it reads as the race.
	var road := PackedVector2Array([sr.position + Vector2(sr.size.x * 0.46, sr.size.y * 0.45),
		sr.position + Vector2(sr.size.x * 0.54, sr.size.y * 0.45), sr.end, Vector2(sr.position.x, sr.end.y)])
	p.draw_colored_polygon(road, Color(0.2, 0.21, 0.24))
	p.draw_rect(sr, Color(1, 1, 1, 0.2), false, 1.0)
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
		p.draw_rect(sr, Color(0, 0, 0, 0.55))
		p.draw_string(UiKit.font("display"), Vector2(sr.position.x, sr.get_center().y + 10), "HUD HIDDEN",
			HORIZONTAL_ALIGNMENT_CENTER, sr.size.x, 28, UiKit.ACCENT)
	p.draw_string(UiKit.font("body"), Vector2(sr.position.x, _all.position.y + 58),
		"F1 in a race hides or shows it all.", HORIZONTAL_ALIGNMENT_LEFT, sr.size.x, 13, UiKit.INK_FAINT)


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


static func _section(ci: CanvasItem, title: String, pos: Vector2, w: float) -> void:
	var f := UiKit.font("cond", 3)
	ci.draw_string(f, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.ACCENT)
	var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	ci.draw_line(pos + Vector2(tw + 12, -5), pos + Vector2(w, -5), UiKit.INK_FAINT, 1.0)
