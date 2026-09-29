class_name TabStrip
extends Control
## A row of choices with one picked: the big mode tabs across the top of the menu (TABS)
## or small filter chips in the browsers (CHIPS). Every choice is visible and a click
## away; the owner steps it from the keyboard or pad with step().

signal changed(index: int)

enum Style { TABS, CHIPS }

var items: PackedStringArray = []
var index := 0
var style := Style.TABS
## Key caps drawn either side of TABS ("Q", "E"): the keys that step it.
var keys := PackedStringArray()

var _rects: Array[Rect2] = []
var _hover := -1
var _sel := Rect2()          # the highlight, gliding to the picked item
var _key_w := 0.0


func _init(p_items: PackedStringArray = [], p_style := Style.TABS) -> void:
	items = p_items
	style = p_style
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size.y = 44.0 if style == Style.TABS else 28.0
	size.y = custom_minimum_size.y
	resized.connect(_measure)
	_measure()


func set_items(p_items: PackedStringArray, p_index := 0) -> void:
	items = p_items
	index = clampi(p_index, 0, maxi(items.size() - 1, 0))
	_measure()
	_sel = _rects[index] if index < _rects.size() else Rect2()


func select(i: int) -> void:
	i = clampi(i, 0, items.size() - 1)
	if i == index:
		return
	index = i
	changed.emit(index)
	queue_redraw()


func step(dir: int) -> void:
	if items.size() > 1:
		select(posmod(index + dir, items.size()))


## Width everything needs, so owners can line things up against it.
func content_width() -> float:
	return (_rects[-1].end.x + _key_w) if not _rects.is_empty() else 0.0


func _font() -> Font:
	return UiKit.font("display") if style == Style.TABS else UiKit.font("cond", 2)


func _font_size() -> int:
	return 22 if style == Style.TABS else 13


func _measure() -> void:
	_rects.clear()
	var f := _font()
	var fs := _font_size()
	var pad := 16.0 if style == Style.TABS else 11.0
	var gap := 2.0 if style == Style.TABS else 6.0
	_key_w = 0.0
	if style == Style.TABS and keys.size() == 2:
		_key_w = UiKit.text_width("cond", keys[0], 13, 1) + 12.0 + 10.0
	var x := _key_w
	for it in items:
		var w := f.get_string_size(it.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + pad * 2.0
		_rects.append(Rect2(x, 0, w, size.y))
		x += w + gap
	custom_minimum_size.x = content_width()
	if _sel == Rect2() and index < _rects.size():
		_sel = _rects[index]
	queue_redraw()


func _process(dt: float) -> void:
	if index >= _rects.size():
		return
	var to := _rects[index]
	if _sel.position.distance_to(to.position) + absf(_sel.size.x - to.size.x) < 0.3:
		return
	var k := 1.0 - exp(-18.0 * dt)
	_sel = Rect2(_sel.position.lerp(to.position, k), _sel.size.lerp(to.size, k))
	queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := _hit(e.position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				var h := _hit(e.position)
				if h >= 0:
					select(h)
				elif style == Style.TABS and keys.size() == 2:
					step(-1 if e.position.x < size.x * 0.5 else 1)
				accept_event()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if style == Style.CHIPS:
					step(-1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
					accept_event()


func _hit(p: Vector2) -> int:
	for i in _rects.size():
		if _rects[i].grow_individual(1, 0, 1, 0).has_point(p):
			return i
	return -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
		_hover = -1
		queue_redraw()


func _draw() -> void:
	var f := _font()
	var fs := _font_size()
	if style == Style.TABS:
		if keys.size() == 2:
			UiKit.draw_key(self, Vector2(0, size.y * 0.5), keys[0], 13, UiKit.INK_DIM)
			UiKit.draw_key(self, Vector2(_rects[-1].end.x + 10.0, size.y * 0.5), keys[1], 13, UiKit.INK_DIM)
		# Picked: a lit slab behind it with an accent bar underneath.
		UiKit.draw_slant(self, _sel, Color(1, 1, 1, 0.08), 0.18)
		UiKit.draw_slant(self, Rect2(_sel.position.x, size.y - 3, _sel.size.x, 3), UiKit.ACCENT, 0.5)
		for i in items.size():
			var r := _rects[i]
			var col := UiKit.INK if i == index else (UiKit.ACCENT if i == _hover else UiKit.INK_DIM)
			draw_string(f, Vector2(r.position.x, r.get_center().y + fs * 0.36), items[i].to_upper(),
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, col)
	else:
		for i in items.size():
			var r := _rects[i]
			if i != index:
				UiKit.draw_slant(self, r, Color(1, 1, 1, 0.14 if i == _hover else 0.06), 0.3)
		UiKit.draw_slant(self, _sel, UiKit.ACCENT, 0.3)
		for i in items.size():
			var r := _rects[i]
			var col := UiKit.BG if i == index else (UiKit.INK if i == _hover else UiKit.INK_DIM)
			draw_string(f, Vector2(r.position.x, r.get_center().y + fs * 0.36), items[i].to_upper(),
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, col)
