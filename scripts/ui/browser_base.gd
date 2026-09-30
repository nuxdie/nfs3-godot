class_name BrowserBase
extends Control
## The shared frame of the car and track browsers: a panel with a title, type-to-search,
## filter chips and a scrolling list or grid. It is one step of the race setup: moving
## through it with the arrows (or pad) picks the item there, pointing at one only previews
## it, and Enter or a click picks it and goes on. Esc (or a right click) goes back.
## Subclasses fill in the entries, lay them out and draw them.

signal focus_changed(item: int)   # moved to with the keys or pad: picked
signal previewed(item: int)       # pointed at, or the pointer left and it's back on `current`
signal confirmed(item: int)
signal cancelled

const PAD := 24.0

var title := ""
var noun := "items"
var query := ""
var filters: TabStrip         # stepped with Tab / Shift+Tab and the pad's shoulder buttons
var grid := false             # ←→ move through the items rather than calling _side_step()
var head_h := 156.0
## {item: int (-1 for a section header), text: String, rect: Rect2 in list space}
var entries: Array[Dictionary] = []
var focus := -1               # index into entries
var current := -1             # the item picked, tagged in the list
var total := 0                # items before filtering, for the count

var _list: Control
var _scroll := 0.0
var _scroll_to := 0.0
var _content_h := 0.0
var _hover := -1
var _time := 0.0
var _drag_bar := false


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	filters = TabStrip.new(PackedStringArray(), TabStrip.Style.CHIPS)
	filters.changed.connect(func(_i): _rebuild())
	add_child(filters)
	_list = Control.new()
	_list.clip_contents = true
	_list.mouse_filter = Control.MOUSE_FILTER_STOP
	_list.draw.connect(_draw_list)
	_list.gui_input.connect(_on_list_input)
	_list.mouse_exited.connect(_on_list_exited)
	add_child(_list)
	resized.connect(_layout)


# ------------------------------------------------------------------ for subclasses

## The entries matching the query and filters, in order.
func _build_entries() -> Array[Dictionary]:
	return []


## Sets each entry's rect (list space) and returns the content height.
func _layout_entries(_w: float) -> float:
	return 0.0


func _draw_entry(_ci: CanvasItem, _e: Dictionary, _r: Rect2, _focused: bool, _hovered: bool) -> void:
	pass


## ←→ in a list: subclasses use it for a second control (the car sort).
func _side_step(_dir: int) -> void:
	pass


## Key hints for the footer (the menu draws them, with its own).
func hints() -> Array:
	return [["↑↓", "BROWSE"]]


## Extra header controls, laid out by the subclass under the filters.
func _layout_head() -> void:
	pass


# ------------------------------------------------------------------ open / close

func open(item: int) -> void:
	query = ""
	current = item
	visible = true
	_layout()
	_rebuild(item)
	_scroll = _scroll_to
	modulate.a = 0.0
	var x := position.x
	position.x = x - 24
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.18)
	tw.tween_property(self, "position:x", x, 0.25)


func close() -> void:
	visible = false


## Redraw the items (a thumbnail arrived).
func refresh() -> void:
	if visible:
		_list.queue_redraw()


func focused_item() -> int:
	return entries[focus].item if focus >= 0 and focus < entries.size() else -1


func _confirm() -> void:
	if focused_item() >= 0:
		current = focused_item()
		confirmed.emit(current)


func _cancel() -> void:
	cancelled.emit()


# ------------------------------------------------------------------ building

func _rebuild(keep := -2) -> void:
	var was := focused_item() if keep == -2 else keep
	entries = _build_entries()
	_layout_list()
	focus = -1
	for k in entries.size():
		if entries[k].item == was:
			focus = k
	if focus < 0:
		focus = _next_item(-1, 1)
	_ensure_visible()
	if focused_item() != was and focused_item() >= 0:
		current = focused_item()
		focus_changed.emit(current)
	queue_redraw()
	_list.queue_redraw()


func _layout() -> void:
	filters.position = Vector2(PAD, 116)
	_layout_head()
	_list.position = Vector2(0, head_h)
	_list.size = Vector2(size.x, maxf(size.y - head_h, 40))
	_layout_list()


func _layout_list() -> void:
	_content_h = _layout_entries(_list.size.x)
	_scroll_to = clampf(_scroll_to, 0.0, _max_scroll())


func _max_scroll() -> float:
	return maxf(_content_h - _list.size.y, 0.0)


func _next_item(from: int, dir: int) -> int:
	var k := from + dir
	while k >= 0 and k < entries.size():
		if entries[k].item >= 0:
			return k
		k += dir
	return -1


func _ensure_visible() -> void:
	if focus < 0:
		return
	var r: Rect2 = entries[focus].rect
	# Keep a section's header in view with its first item.
	if focus > 0 and entries[focus - 1].item < 0 and entries[focus - 1].rect.position.y < r.position.y:
		r = r.merge(entries[focus - 1].rect)
	if r.position.y - 10 < _scroll_to:
		_scroll_to = r.position.y - 10
	elif r.end.y + 10 > _scroll_to + _list.size.y:
		_scroll_to = r.end.y + 10 - _list.size.y
	_scroll_to = clampf(_scroll_to, 0.0, _max_scroll())


func _set_focus(k: int) -> void:
	if k < 0 or k == focus:
		return
	focus = k
	_ensure_visible()
	current = focused_item()
	focus_changed.emit(current)
	_list.queue_redraw()


## Up/down: to the nearest item in the next row that way (lists and grids alike).
func _move_vertical(dir: int) -> void:
	if focus < 0:
		_set_focus(_next_item(-1, 1))
		return
	var c: Vector2 = entries[focus].rect.get_center()
	var best := -1
	var best_dy := INF
	var best_dx := INF
	for k in entries.size():
		if entries[k].item < 0:
			continue
		var p: Vector2 = entries[k].rect.get_center()
		var dy := (p.y - c.y) * dir
		if dy < 4.0:
			continue
		var dx := absf(p.x - c.x)
		if dy < best_dy - 4.0 or (absf(dy - best_dy) <= 4.0 and dx < best_dx):
			best = k
			best_dy = dy
			best_dx = dx
	_set_focus(best)


func _page(dir: int) -> void:
	if focus < 0:
		return
	var y: float = entries[focus].rect.get_center().y + dir * _list.size.y * 0.85
	var best := focus
	for k in entries.size():
		if entries[k].item >= 0 and absf(entries[k].rect.get_center().y - y) < absf(entries[best].rect.get_center().y - y):
			best = k
	_set_focus(best)


# ------------------------------------------------------------------ input

func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e is InputEventKey:
		if not e.pressed:
			return
		match e.physical_keycode:
			KEY_UP:
				_move_vertical(-1)
			KEY_DOWN:
				_move_vertical(1)
			KEY_LEFT, KEY_RIGHT:
				var d := -1 if e.physical_keycode == KEY_LEFT else 1
				if grid:
					_set_focus(_next_item(focus, d))
				elif not e.echo:
					_side_step(d)
			KEY_PAGEUP, KEY_PAGEDOWN:
				_page(-1 if e.physical_keycode == KEY_PAGEUP else 1)
			KEY_HOME:
				_set_focus(_next_item(-1, 1))
			KEY_END:
				_set_focus(_next_item(entries.size(), -1))
			KEY_ENTER, KEY_KP_ENTER:
				if not e.echo and not e.alt_pressed:
					_confirm()
				elif e.alt_pressed:
					return   # Alt+Enter is fullscreen
			KEY_ESCAPE:
				if e.echo:
					pass
				elif query != "":
					_set_query("")
				else:
					_cancel()
			KEY_TAB:
				filters.step(-1 if e.shift_pressed else 1)
			KEY_BACKSPACE:
				_set_query("" if e.ctrl_pressed else query.left(-1))
			KEY_DELETE:
				_set_query("")
			KEY_F11:
				return
			_:
				if e.unicode >= 32 and not e.ctrl_pressed and not e.alt_pressed and query.length() < 24:
					_set_query(query + char(e.unicode))
				else:
					return
		get_viewport().set_input_as_handled()
		return
	# Pad (and anything else mapped to the ui actions).
	if e.is_action_pressed("ui_up", true):
		_move_vertical(-1)
	elif e.is_action_pressed("ui_down", true):
		_move_vertical(1)
	elif e.is_action_pressed("ui_left", true) or e.is_action_pressed("ui_right", true):
		var d := -1 if e.is_action_pressed("ui_left", true) else 1
		if grid:
			_set_focus(_next_item(focus, d))
		else:
			_side_step(d)
	elif e.is_action_pressed("ui_accept"):
		_confirm()
	elif e.is_action_pressed("ui_cancel"):
		_cancel()
	elif e is InputEventJoypadButton and e.pressed and e.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		filters.step(-1 if e.button_index == JOY_BUTTON_LEFT_SHOULDER else 1)
	else:
		return
	get_viewport().set_input_as_handled()


func _set_query(q: String) -> void:
	if q == query:
		return
	query = q
	_rebuild()


## Words in the query that all have to appear in `haystack` (lower case).
func _matches(haystack: String) -> bool:
	for w in query.to_lower().split(" ", false):
		if not haystack.contains(w):
			return false
	return true


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _head_hot() else Control.CURSOR_ARROW


## True while the pointer is over a subclass's own header control.
func _head_hot() -> bool:
	return false


func _entry_at(p: Vector2) -> int:
	var q := p + Vector2(0, _scroll)
	for k in entries.size():
		if entries[k].item >= 0 and entries[k].rect.has_point(q):
			return k
	return -1


func _bar_rect() -> Rect2:
	var h := _list.size.y
	if _content_h <= h:
		return Rect2()
	var bh := maxf(h * h / _content_h, 30.0)
	return Rect2(_list.size.x - 8, (h - bh) * _scroll / _max_scroll(), 4, bh)


func _on_list_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		if _drag_bar:
			var h := _list.size.y
			var bh := _bar_rect().size.y
			_scroll_to = clampf(_scroll_to + e.relative.y * _max_scroll() / maxf(h - bh, 1.0), 0.0, _max_scroll())
			_scroll = _scroll_to
			_list.queue_redraw()
			return
		var k := _entry_at(e.position)
		if k != _hover:
			_hover = k
			_list.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if k >= 0 else Control.CURSOR_ARROW
			# Pointing at an item previews it; a click picks it.
			if k >= 0 and k != focus:
				focus = k
				previewed.emit(focused_item())
			_list.queue_redraw()
	elif e is InputEventMouseButton:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				if e.pressed and _content_h > _list.size.y and e.position.x > _list.size.x - 16:
					_drag_bar = true
				elif not e.pressed:
					_drag_bar = false
				elif e.pressed:
					var k := _entry_at(e.position)
					if k >= 0:
						focus = k
						_confirm()
			MOUSE_BUTTON_RIGHT:
				if e.pressed:
					_cancel()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if e.pressed:
					var d := -1.0 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
					_scroll_to = clampf(_scroll_to + d * 90.0 * maxf(e.factor, 1.0), 0.0, _max_scroll())
		_list.accept_event()


## The pointer has gone: back to the picked item.
func _on_list_exited() -> void:
	_hover = -1
	if focused_item() != current:
		for k in entries.size():
			if entries[k].item == current:
				focus = k
		previewed.emit(current)
	_list.queue_redraw()


func _process(dt: float) -> void:
	if not visible:
		return
	_time += dt
	if absf(_scroll - _scroll_to) > 0.3:
		_scroll = UiKit.damp(_scroll, _scroll_to, 16.0, dt)
		_list.queue_redraw()
	else:
		_scroll = _scroll_to
	# Caret blink.
	if int(_time * 2.0) != int((_time - dt) * 2.0):
		queue_redraw()


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var w := size.x
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.045, 0.06, 0.93))
	draw_rect(Rect2(0, 0, w, 3), UiKit.ACCENT)
	var tf := UiKit.font("display")
	draw_string(tf, Vector2(PAD, 50), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, UiKit.INK)
	var tw := tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	var shown := entries.filter(func(en: Dictionary) -> bool: return en.item >= 0).size()
	var count := "%d" % total if shown == total else "%d OF %d" % [shown, total]
	draw_string(UiKit.font("cond", 2), Vector2(PAD + tw + 12, 49), count, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiKit.INK_DIM)
	# Search box: typing anywhere goes into it.
	var sr := Rect2(PAD, 66, w - PAD * 2, 38)
	draw_rect(sr, Color(1, 1, 1, 0.06))
	draw_rect(sr, Color(UiKit.ACCENT, 0.7) if query != "" else Color(1, 1, 1, 0.14), false, 1.0)
	var gc := sr.position + Vector2(20, 18)
	draw_arc(gc, 6.0, 0, TAU, 20, UiKit.INK_DIM, 2.0, true)
	draw_line(gc + Vector2(4.5, 4.5), gc + Vector2(9, 9), UiKit.INK_DIM, 2.0, true)
	var bf := UiKit.font("body")
	var tx := sr.position.x + 40
	if query == "":
		draw_string(bf, Vector2(tx, sr.position.y + 25), "Type to search %s" % noun, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			UiKit.INK_FAINT)
	else:
		draw_string(bf, Vector2(tx, sr.position.y + 25), query, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.INK)
		tx += bf.get_string_size(query, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 2
		UiKit.draw_key(self, Vector2(sr.end.x - 104, sr.get_center().y), "ESC", 11, UiKit.INK_DIM)
		draw_string(UiKit.font("cond", 2), Vector2(sr.end.x - 64, sr.get_center().y + 5), "CLEAR", HORIZONTAL_ALIGNMENT_LEFT,
			-1, 13, UiKit.INK_DIM)
	if fmod(_time, 1.0) < 0.5:
		draw_rect(Rect2(tx, sr.position.y + 10, 2, 19), UiKit.ACCENT)


func _draw_list() -> void:
	var l := _list
	var vis := Rect2(0, _scroll, l.size.x, l.size.y)
	for k in entries.size():
		var e := entries[k]
		var r: Rect2 = e.rect
		if not r.intersects(vis):
			continue
		var sr := Rect2(r.position - Vector2(0, _scroll), r.size)
		if e.item < 0:
			var f := UiKit.font("cond", 3)
			var y := sr.end.y - 9
			l.draw_string(f, Vector2(PAD, y), e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.ACCENT)
			var tw := f.get_string_size(e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			l.draw_line(Vector2(PAD + tw + 12, y - 5), Vector2(l.size.x - PAD, y - 5), UiKit.INK_FAINT, 1.0)
		else:
			_draw_entry(l, e, sr, k == focus, k == _hover)
	if _next_item(-1, 1) < 0:
		var f := UiKit.font("display")
		var msg := "NO %s MATCH \"%s\"" % [noun.to_upper(), query.to_upper()] if query != "" else "NOTHING HERE"
		l.draw_string(f, Vector2(PAD, 60), msg, HORIZONTAL_ALIGNMENT_LEFT, l.size.x - PAD * 2, 24, UiKit.INK_DIM)
		l.draw_string(UiKit.font("body"), Vector2(PAD, 88), "Backspace to edit, Esc to clear, Tab for another filter.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiKit.INK_FAINT)
	var br := _bar_rect()
	if br.size.y > 0:
		l.draw_rect(Rect2(br.position.x, 0, br.size.x, l.size.y), Color(1, 1, 1, 0.05))
		l.draw_rect(br, Color(1, 1, 1, 0.35 if _drag_bar else 0.2))
	# Fade the edges where the list runs on.
	if _scroll > 1.0:
		_fade_edge(l, 0.0, 1.0)
	if _scroll < _max_scroll() - 1.0:
		_fade_edge(l, l.size.y, -1.0)


static func _fade_edge(c: Control, y: float, dir: float) -> void:
	var c0 := Color(0.04, 0.045, 0.06, 0.93)
	var c1 := Color(c0, 0.0)
	var h := 24.0 * dir
	var w := c.size.x - 10
	c.draw_polygon(PackedVector2Array([Vector2(0, y), Vector2(w, y), Vector2(w, y + h), Vector2(0, y + h)]),
		PackedColorArray([c0, c0, c1, c1]))
