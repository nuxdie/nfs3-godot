class_name TabStrip
extends Control
## A row of choices with one picked: page tabs (TABS: words, the picked one white with an
## accent line under it, and optional key caps either side for the keys that step them) or
## filters (CHIPS: smaller words, the picked one in the accent). Every choice is visible and a click away; the owner
## steps it from the keyboard or pad with step().

signal changed(index: int)

enum Style { TABS, CHIPS }

var items: PackedStringArray = []
var index := 0
var style := Style.TABS
## Key caps drawn either side of TABS ("Q", "E"): the keys that step it.
var keys := PackedStringArray()
## A short value drawn after a tab's name, in the accent ("$5,340"); "" for none.
var badges := PackedStringArray()
var font_size := 0              # 0: the style's own

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


func set_badges(b: PackedStringArray) -> void:
	if b == badges:
		return
	badges = b
	_measure()


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
	return UiKit.font("cond", 2) if style == Style.TABS else UiKit.font("cond", 1)


func _font_size() -> int:
	if font_size > 0:
		return font_size
	return 17 if style == Style.TABS else 14


func _badge(i: int) -> String:
	return badges[i] if i < badges.size() else ""


func _measure() -> void:
	_rects.clear()
	var f := _font()
	var fs := _font_size()
	var pad := 14.0 if style == Style.TABS else 8.0
	var gap := 6.0 if style == Style.TABS else 4.0
	_key_w = 0.0
	if style == Style.TABS and keys.size() == 2:
		_key_w = UiKit.key_width(keys[0], 12) + 10.0
	var x := _key_w
	for i in items.size():
		var w := f.get_string_size(items[i].to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + pad * 2.0
		if _badge(i) != "":
			w += UiKit.text_width("cond", _badge(i), fs - 2, 1, true) + 10.0
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
	var k := 1.0 - exp(-20.0 * dt)
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
	var cy := size.y * 0.5
	if style == Style.TABS:
		if keys.size() == 2 and not _rects.is_empty():
			UiKit.draw_key(self, Vector2(0, cy), keys[0], 12, UiKit.INK_FAINT)
			UiKit.draw_key(self, Vector2(_rects[-1].end.x + 10.0, cy), keys[1], 12, UiKit.INK_FAINT)
		UiKit.box(self, Rect2(_sel.position.x + 10, size.y - 3, _sel.size.x - 20, 3), UiKit.ACCENT, 1)
		for i in items.size():
			var r := _rects[i]
			var col := UiKit.INK if i == index or i == _hover else UiKit.INK_DIM
			var label := items[i].to_upper()
			var x := r.position.x + 14.0
			draw_string(f, Vector2(x, cy + fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			if _badge(i) != "":
				x += f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10.0
				draw_string(UiKit.font("cond", 1, true), Vector2(x, cy + fs * 0.36), _badge(i), HORIZONTAL_ALIGNMENT_LEFT, -1,
					fs - 2, UiKit.ACCENT if i == index else Color(UiKit.ACCENT, 0.75))
	else:
		# Filters: words, the picked one in the accent with a line under it.
		draw_rect(Rect2(_sel.position.x + 8, size.y - 4, _sel.size.x - 16, 2), UiKit.ACCENT)
		for i in items.size():
			var r := _rects[i]
			var col := UiKit.ACCENT if i == index else (UiKit.INK if i == _hover else UiKit.INK_DIM)
			draw_string(f, Vector2(r.position.x, cy + fs * 0.36), items[i].to_upper(),
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, col)
