class_name SettingsPanel
extends Control
## The settings overlay: graphics, display, sound and gameplay options down the left,
## the controls and where the game data was found down the right. Changes apply as
## they're made and are saved on closing.

signal closed
signal changed

const CONTROLS := [
	[["↑↓", "W", "S"], "Throttle · brake"], [["←→", "A", "D"], "Steer"], [["SPACE"], "Handbrake"],
	[["C"], "Change camera"], [["B"], "Look back"], [["R"], "Reset car"], [["H"], "Horn"],
	[["L", "K"], "Lights · high beam"], [["M"], "Mirror"], [["ESC"], "Pause"], [["F11"], "Fullscreen"],
]

enum Opt { GRAPHICS, DISPLAY, VSYNC, VOLUME, UNITS, DAMAGE }

var _panel: Control
var _rows: Array[OptionRow] = []
var _focus := 0
var _status: Label
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
	var vol := PackedStringArray()
	for v in 11:
		vol.append("OFF" if v == 0 else str(v))
	var defs := [
		["Graphics", PackedStringArray(Game.QUALITY_NAMES)],
		["Display", PackedStringArray(["Window", "Fullscreen"])],
		["V-Sync", PackedStringArray(["Off", "On"])],
		["Volume", vol],
		["Speed", PackedStringArray(["km/h", "mph"])],
		["Damage", PackedStringArray(["Off", "On"])],
	]
	for i in defs.size():
		var r := OptionRow.new(defs[i][0], defs[i][1])
		r.caption_w = 104.0
		r.hovered.connect(func(): _set_focus(i))
		r.changed.connect(func(_v): _apply())
		_panel.add_child(r)
		_rows.append(r)
	_status = UiKit.label("", "body", 13, UiKit.INK_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_status)
	resized.connect(_layout)


func open() -> void:
	_rows[Opt.GRAPHICS].set_items(_rows[Opt.GRAPHICS].items, Game.quality)
	_rows[Opt.DISPLAY].set_items(_rows[Opt.DISPLAY].items, int(Game.fullscreen))
	_rows[Opt.VSYNC].set_items(_rows[Opt.VSYNC].items, int(Game.vsync))
	_rows[Opt.VOLUME].set_items(_rows[Opt.VOLUME].items, Game.volume)
	_rows[Opt.UNITS].set_items(_rows[Opt.UNITS].items, 0 if Game.units_kmh else 1)
	_rows[Opt.DAMAGE].set_items(_rows[Opt.DAMAGE].items, int(Game.damage))
	_status.text = _data_text()
	visible = true
	_set_focus(0)
	_layout()
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


func _apply() -> void:
	Game.quality = _rows[Opt.GRAPHICS].index as Game.Quality
	Game.fullscreen = _rows[Opt.DISPLAY].index == 1
	Game.vsync = _rows[Opt.VSYNC].index == 1
	Game.volume = _rows[Opt.VOLUME].index
	Game.units_kmh = _rows[Opt.UNITS].index == 0
	Game.damage = _rows[Opt.DAMAGE].index == 1
	Game.apply_display()
	changed.emit()


func _set_focus(i: int) -> void:
	_focus = i
	for k in _rows.size():
		_rows[k].focused = k == i


func _col_w() -> float:
	return (_panel.size.x - 84 - 40) * 0.5


func _layout() -> void:
	_panel.size = Vector2(minf(980.0, size.x - 64), minf(560.0, size.y - 48))
	_panel.position = ((size - _panel.size) * 0.5).round()
	var cw := _col_w()
	for i in _rows.size():
		_rows[i].position = Vector2(20, 112 + i * (OptionRow.H + 4))
		_rows[i].size = Vector2(cw + 22, OptionRow.H)
	var rx := 42 + cw + 40
	_status.position = Vector2(rx, 112 + 6 * 30 + 54)
	_status.size = Vector2(cw, 120)


func _back_rect() -> Rect2:
	return Rect2(_panel.size.x - 130, 30, 92, 32)


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
	if e.is_action_pressed("ui_down", true):
		_set_focus(posmod(_focus + 1, _rows.size()))
	elif e.is_action_pressed("ui_up", true):
		_set_focus(posmod(_focus - 1, _rows.size()))
	elif e.is_action_pressed("ui_left", true):
		_rows[_focus].step(-1)
	elif e.is_action_pressed("ui_right", true):
		_rows[_focus].step(1)
	elif e.is_action_pressed("ui_cancel") or (e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_TAB) \
			or (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_Y):
		close()
	else:
		return
	get_viewport().set_input_as_handled()


func _draw_panel() -> void:
	var p := _panel
	var r := Rect2(Vector2.ZERO, p.size)
	p.draw_rect(r, Color(0.05, 0.055, 0.075, 0.98))
	p.draw_rect(Rect2(0, 0, r.size.x, 3), UiKit.ACCENT)
	p.draw_string(UiKit.font("display"), Vector2(42, 62), "SETTINGS", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, UiKit.INK)
	var br := _back_rect()
	if _back_hot:
		UiKit.draw_slant(p, br, Color(UiKit.ACCENT, 0.12), 0.15)
	var kw := UiKit.draw_key(p, br.position + Vector2(8, 16), "ESC", 12, UiKit.ACCENT if _back_hot else UiKit.INK)
	p.draw_string(UiKit.font("cond", 2), br.position + Vector2(16 + kw, 21), "BACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		UiKit.ACCENT if _back_hot else UiKit.INK_DIM)
	var cw := _col_w()
	_section(p, "OPTIONS", Vector2(42, 100), cw)
	var rx := 42 + cw + 40
	_section(p, "CONTROLS", Vector2(rx, 100), cw)
	for i in CONTROLS.size():
		var pos := Vector2(rx + (i % 2) * cw * 0.5, 126 + (i / 2) * 30)
		var kx := 0.0
		for k in CONTROLS[i][0]:
			kx += UiKit.draw_key(p, pos + Vector2(kx, 0), k, 12) + 4.0
		p.draw_string(UiKit.font("body"), pos + Vector2(kx + 6, 5), CONTROLS[i][1], HORIZONTAL_ALIGNMENT_LEFT,
			cw * 0.5 - kx - 12, 14, UiKit.INK_DIM)
	_section(p, "GAME DATA", Vector2(rx, 112 + 6 * 30 + 36), cw)


static func _section(ci: CanvasItem, title: String, pos: Vector2, w: float) -> void:
	var f := UiKit.font("cond", 3)
	ci.draw_string(f, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.ACCENT)
	var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	ci.draw_line(pos + Vector2(tw + 12, -5), pos + Vector2(w, -5), UiKit.INK_FAINT, 1.0)
