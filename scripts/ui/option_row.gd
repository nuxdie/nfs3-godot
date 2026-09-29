class_name OptionRow
extends Control
## One race or game setting as a row of segments: caption on the left, every choice
## visible to its right and one click away. When the row has focus ←→ (keys or pad)
## step it; the mouse wheel steps it under the pointer.

signal changed(index: int)
signal hovered

const H := 46.0

var caption := ""
var items: PackedStringArray = []
var index := 0
var focused := false
var disabled := false
var disabled_text := "—"
## Choices past this one are shown but can't be picked (-1: all can).
var max_index := -1
var caption_w := 118.0

var _focus_t := 0.0
var _hover := -1
var _sel := Rect2()


func _init(p_caption := "", p_items: PackedStringArray = []) -> void:
	caption = p_caption
	items = p_items
	custom_minimum_size = Vector2(0, H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(func(): _sel = _seg(index))


func set_items(p_items: PackedStringArray, p_index := 0) -> void:
	items = p_items
	index = clampi(p_index, 0, maxi(items.size() - 1, 0))
	_sel = _seg(index)
	queue_redraw()


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


func _seg(i: int) -> Rect2:
	var n := maxi(items.size(), 1)
	var x0 := caption_w
	var w := (size.x - x0 - 8.0) / n
	return Rect2(x0 + i * w, 8, w - 4.0, H - 16)


func _process(dt: float) -> void:
	var target := 1.0 if focused and not disabled else 0.0
	var to := _seg(index)
	var busy := absf(_focus_t - target) > 0.002 or _sel.position.distance_to(to.position) > 0.3
	if not busy:
		return
	_focus_t = UiKit.damp(_focus_t, target, 14.0, dt)
	var k := 1.0 - exp(-20.0 * dt)
	_sel = Rect2(_sel.position.lerp(to.position, k), to.size)
	queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := -1
		for i in items.size():
			if _seg(i).grow(2).has_point(e.position):
				h = i
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND \
				if h >= 0 and h <= _last() and not disabled else Control.CURSOR_ARROW
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed and not disabled:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				if _hover >= 0:
					select(_hover)
				accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				step(-1)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
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
	var w := size.x
	var t := _focus_t
	var a := 0.45 if disabled else 1.0
	if t > 0.01:
		UiKit.draw_slant(self, Rect2(0, 3, w, H - 6), Color(1, 1, 1, 0.06 * t), 0.12)
		UiKit.draw_slant(self, Rect2(0, 3, 4, H - 6), Color(UiKit.ACCENT, t), 0.12)
	var cap_col := UiKit.ACCENT if t > 0.5 else UiKit.INK_DIM
	draw_string(UiKit.font("cond", 3), Vector2(22 + 4 * t, H * 0.5 + 5), caption.to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
		caption_w - 24, 13, Color(cap_col, cap_col.a * a))
	var f := UiKit.font("cond", 2)
	var fs := 15
	if disabled:
		var r := Rect2(caption_w, 8, w - caption_w - 12, H - 16)
		UiKit.draw_slant(self, r, Color(1, 1, 1, 0.04), 0.3)
		draw_string(f, Vector2(r.position.x, r.get_center().y + fs * 0.36), disabled_text.to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, UiKit.INK_FAINT)
		return
	for i in items.size():
		if i == index:
			continue
		var locked := i > _last()
		var fill := 0.03 if locked else (0.16 if i == _hover else 0.07)
		UiKit.draw_slant(self, _seg(i), Color(1, 1, 1, fill), 0.3)
	UiKit.draw_slant(self, _sel, UiKit.ACCENT.lerp(Color(1, 0.85, 0.4), 0.3 if _hover == index else 0.0), 0.3)
	for i in items.size():
		var r := _seg(i)
		var col := UiKit.BG if i == index else (UiKit.INK_FAINT if i > _last() else \
			(UiKit.INK if i == _hover else UiKit.INK_DIM))
		draw_string(f, Vector2(r.position.x, r.get_center().y + fs * 0.36), items[i].to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, col)
