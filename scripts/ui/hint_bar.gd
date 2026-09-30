class_name HintBar
extends Control
## A row of "[KEY] ACTION" hints. Those given a callable are buttons as well (drawn a little
## brighter): they light up under the pointer and a click does what the key does. Sizes
## itself to its hints.

const PAD := 10.0
const GAP := 6.0

## [key, text] or [key, text, Callable]; a key of "" shows the text alone.
var hints: Array = []
var font_size := 14

var _rects: Array[Rect2] = []
var _hover := -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.y = 32.0
	size.y = 32.0


func set_hints(h: Array) -> void:
	hints = h
	_rects.clear()
	var x := 0.0
	for hint in hints:
		var w := UiKit.text_width("cond", hint[1], font_size, 1) + PAD * 2.0
		if hint[0] != "":
			w += UiKit.key_width(hint[0], font_size) + 8.0
		_rects.append(Rect2(x, 0, w, size.y))
		x += w + GAP
	custom_minimum_size.x = maxf(x - GAP, 0.0)
	size.x = custom_minimum_size.x
	_hover = -1
	queue_redraw()


func _clickable(i: int) -> bool:
	return i >= 0 and i < hints.size() and hints[i].size() > 2 and (hints[i][2] as Callable).is_valid()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := -1
		for i in _rects.size():
			if _rects[i].has_point(e.position) and _clickable(i):
				h = i
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _hover >= 0:
		accept_event()
		(hints[_hover][2] as Callable).call()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
		_hover = -1
		queue_redraw()


func _draw() -> void:
	var f := UiKit.font("cond", 1)
	var cy := size.y * 0.5
	for i in hints.size():
		var r := _rects[i]
		var hot := i == _hover
		var link := _clickable(i)
		var x := r.position.x + PAD
		var key_col := UiKit.ACCENT if hot else UiKit.INK_DIM
		if hints[i][0] != "":
			x += UiKit.draw_key(self, Vector2(x, cy), hints[i][0], font_size, key_col) + 8.0
		if hot:
			draw_rect(Rect2(x, cy + font_size * 0.36 + 4, r.end.x - PAD - x, 2), UiKit.ACCENT)
		draw_string(f, Vector2(x, cy + font_size * 0.36), hints[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			UiKit.ACCENT if hot else (UiKit.INK if link else UiKit.INK_DIM))
