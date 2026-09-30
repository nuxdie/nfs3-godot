class_name OptionRow
extends Control
## One setting as a line of type: its name, then every choice as a word (or a digit) with the
## picked one lit and underlined in the accent, the rest dimmed but a click away. A level such
## as a volume is a slider instead; paints are dots of their colours. When the row has focus
## ←→ (keys or pad) step it; the mouse wheel steps it under the pointer.

signal changed(index: int)
signal hovered

const H := 34.0
const PAD := 9.0              # either side of a choice's word: its hit area

var caption := ""
var items: PackedStringArray = []
var index := 0
var focused := false
var disabled := false
var disabled_text := "—"
## Choices past this one are shown but can't be picked (-1: all can).
var max_index := -1
var caption_w := 118.0
## Colour per choice: dots of the colours, the picked one's name under the caption.
var swatches: Array[Color] = []
## A level (0 = the first item, e.g. "Off") rather than a set of choices: drawn as a slider.
var slider := false

var _focus_t := 0.0
var _hover := -1
var _sel := Rect2()           # the underline, gliding to the picked choice
var _rects: Array[Rect2] = []
var _fs := 14
var _dragging := false


func _init(p_caption := "", p_items: PackedStringArray = []) -> void:
	caption = p_caption
	items = p_items
	custom_minimum_size = Vector2(0, H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_measure)


func set_items(p_items: PackedStringArray, p_index := 0) -> void:
	items = p_items
	index = clampi(p_index, 0, maxi(items.size() - 1, 0))
	_measure()
	_sel = _under(index)


func value_text() -> String:
	return items[index] if index < items.size() else ""


func _last() -> int:
	return items.size() - 1 if max_index < 0 else mini(max_index, items.size() - 1)


func select(i: int) -> bool:
	if disabled:
		return false
	i = clampi(i, 0, _last())
	if i == index:
		return false
	index = i
	changed.emit(index)
	queue_redraw()
	return true


## Step the value (no wrapping: the ends are in plain sight); true if it changed.
func step(dir: int) -> bool:
	return select(index + dir)


## Lays the choices out at their words' widths, shrinking the type if they don't all fit.
func _measure() -> void:
	_rects.clear()
	var room := size.x - caption_w - 4.0
	if swatches.size() > 0 and not slider:
		var step_w := minf(28.0, room / maxf(items.size(), 1))
		for i in items.size():
			_rects.append(Rect2(caption_w + i * step_w, 0, step_w, size.y))
		queue_redraw()
		return
	var f := UiKit.font("cond", 1)
	_fs = 14
	var pad := PAD
	while true:
		var total := 0.0
		for it in items:
			total += f.get_string_size(it.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x + pad * 2.0
		if total <= room or _fs <= 11:
			break
		if pad > 5.0:
			pad -= 1.0
		else:
			_fs -= 1
	var x := caption_w - pad
	for it in items:
		var w := f.get_string_size(it.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x + pad * 2.0
		_rects.append(Rect2(x, 0, w, size.y))
		x += w
	queue_redraw()


## The underline under choice `i`.
func _under(i: int) -> Rect2:
	if i < 0 or i >= _rects.size():
		return Rect2()
	var r := _rects[i]
	return Rect2(r.position.x + PAD * 0.6, size.y * 0.5 + 10, r.size.x - PAD * 1.2, 2)


func _bar() -> Rect2:
	return Rect2(caption_w + 2, size.y * 0.5 - 1.5, size.x - caption_w - 64, 3)


func _slider_value_at(x: float) -> int:
	var b := _bar()
	return clampi(roundi((x - b.position.x) / maxf(b.size.x, 1.0) * (items.size() - 1)), 0, items.size() - 1)


func _process(dt: float) -> void:
	var target := 1.0 if focused and not disabled else 0.0
	var to := _under(index)
	var busy := absf(_focus_t - target) > 0.002 or _sel.position.distance_to(to.position) + absf(_sel.size.x - to.size.x) > 0.3
	if not busy:
		return
	_focus_t = UiKit.damp(_focus_t, target, 16.0, dt)
	var k := 1.0 - exp(-22.0 * dt)
	_sel = Rect2(_sel.position.lerp(to.position, k), _sel.size.lerp(to.size, k))
	queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		if _dragging:
			select(_slider_value_at(e.position.x))
			return
		var h := -1
		if slider:
			h = 0 if _bar().grow_individual(8, 12, 8, 12).has_point(e.position) else -1
		else:
			for i in _rects.size():
				if _rects[i].has_point(e.position):
					h = i
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND \
				if h >= 0 and h <= _last() and not disabled else Control.CURSOR_ARROW
			queue_redraw()
	elif e is InputEventMouseButton and not disabled:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				if slider:
					_dragging = e.pressed and _hover >= 0
					if _dragging:
						select(_slider_value_at(e.position.x))
				elif e.pressed and _hover >= 0:
					select(_hover)
				accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				if e.pressed:
					step(-1)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if e.pressed:
					step(1)
				accept_event()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			hovered.emit()
		NOTIFICATION_MOUSE_EXIT:
			_hover = -1
			queue_redraw()


func _draw() -> void:
	var t := _focus_t
	var cy := size.y * 0.5
	UiKit.glow(self, Rect2(-12, 0, size.x + 12, size.y), t)
	var named := not swatches.is_empty() and not disabled
	var cap_col := UiKit.INK_DIM.lerp(UiKit.INK, t)
	if disabled:
		cap_col = UiKit.INK_FAINT
	draw_string(UiKit.font("body"), Vector2(0, cy + (-3 if named else 5)), caption, HORIZONTAL_ALIGNMENT_LEFT,
		caption_w - 12, 15, cap_col)
	if named:
		draw_string(UiKit.font("body"), Vector2(0, cy + 13), value_text(), HORIZONTAL_ALIGNMENT_LEFT, caption_w - 10, 12,
			UiKit.ACCENT)
	if disabled:
		draw_string(UiKit.font("body"), Vector2(caption_w, cy + 5), disabled_text, HORIZONTAL_ALIGNMENT_LEFT,
			size.x - caption_w, 14, UiKit.INK_FAINT)
		return
	if slider:
		_draw_slider(t)
		return
	if not swatches.is_empty():
		for i in mini(_rects.size(), swatches.size()):
			var c := _rects[i].get_center()
			var col := swatches[i]
			if i == index:
				draw_circle(c, 11.0, UiKit.ACCENT, false, 2.0, true)
			elif i == _hover:
				draw_circle(c, 10.0, Color(1, 1, 1, 0.6), false, 1.0, true)
			draw_circle(c, 7.5, Color(col.r, col.g, col.b, 1.0), true, -1.0, true)
			draw_circle(c, 7.5, Color(1, 1, 1, 0.22), false, 1.0, true)
		return
	var f := UiKit.font("cond", 1)
	for i in _rects.size():
		var r := _rects[i]
		var col := UiKit.INK if i == index else (UiKit.INK_FAINT if i > _last() else \
			(UiKit.INK if i == _hover else UiKit.INK_DIM))
		if i == _hover and i != index and i <= _last():
			draw_rect(Rect2(r.position.x + PAD * 0.6, cy + 10, r.size.x - PAD * 1.2, 1), Color(1, 1, 1, 0.35))
		draw_string(f, Vector2(r.position.x, cy + _fs * 0.36), items[i].to_upper(), HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x, _fs, col)
	draw_rect(_sel, UiKit.ACCENT)


func _draw_slider(t: float) -> void:
	var b := _bar()
	var n := maxi(items.size() - 1, 1)
	var k := float(index) / n
	draw_rect(b, Color(1, 1, 1, 0.16))
	if k > 0.0:
		draw_rect(Rect2(b.position, Vector2(b.size.x * k, b.size.y)), UiKit.ACCENT)
	var knob := Vector2(b.position.x + b.size.x * k, b.get_center().y)
	var hot := _hover >= 0 or _dragging or t > 0.5
	draw_circle(knob, 7.0 if hot else 5.5, UiKit.ACCENT if index > 0 else UiKit.INK_DIM, true, -1.0, true)
	draw_string(UiKit.font("cond", 1, true), Vector2(b.end.x + 14, b.get_center().y + 5), value_text().to_upper(),
		HORIZONTAL_ALIGNMENT_RIGHT, size.x - b.end.x - 14, 15, UiKit.INK if index > 0 else UiKit.INK_DIM)
