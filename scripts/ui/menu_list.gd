class_name MenuList
extends Control
## The home screen's list: big entries, each with a line on what it is and maybe a value
## on the right (the tournament money). Up/down or the pointer move through it, Enter or a
## click picks. Handles its own input while visible.

signal activated(index: int)
signal focus_changed(index: int)

const BIG_H := 54.0
const SMALL_H := 36.0
const HERO_H := 72.0
const GAP := 6.0

## {title, note, value, kind: "hero" | "big" | "small", gap: extra space above, color}
var items: Array[Dictionary] = []
var focus := 0

var _t: Array[float] = []     # per-item animated highlight
var _hover := -1
var _rects: Array[Rect2] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_items(p_items: Array[Dictionary], p_focus := 0) -> void:
	items = p_items
	focus = clampi(p_focus, 0, maxi(items.size() - 1, 0))
	_t.resize(items.size())
	for i in items.size():
		_t[i] = 1.0 if i == focus else 0.0
	_measure()


func _measure() -> void:
	_rects.clear()
	var y := 0.0
	for it in items:
		y += float(it.get("gap", 0.0))
		var h: float = {"hero": HERO_H, "small": SMALL_H}.get(it.get("kind", "big"), BIG_H)
		_rects.append(Rect2(0, y, size.x, h))
		y += h + GAP
	custom_minimum_size.y = y
	queue_redraw()


func content_height() -> float:
	return _rects[-1].end.y if not _rects.is_empty() else 0.0


func _set_focus(i: int) -> void:
	if i == focus or i < 0 or i >= items.size():
		return
	focus = i
	focus_changed.emit(i)


func _item_at(p: Vector2) -> int:
	for i in _rects.size():
		if _rects[i].has_point(p):
			return i
	return -1


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := _item_at(e.position)
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
			_set_focus(h)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var h := _item_at(e.position)
		if h >= 0:
			accept_event()
			_set_focus(h)
			activated.emit(h)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1
	elif what == NOTIFICATION_RESIZED:
		_measure()


func _unhandled_input(e: InputEvent) -> void:
	if not is_visible_in_tree() or items.is_empty():
		return
	var vp := get_viewport()
	if e.is_action_pressed("ui_up", true):
		_set_focus(posmod(focus - 1, items.size()))
	elif e.is_action_pressed("ui_down", true):
		_set_focus(posmod(focus + 1, items.size()))
	elif e.is_action_pressed("ui_accept") and not (e is InputEventKey and (e.echo or e.alt_pressed)):
		activated.emit(focus)
	else:
		return
	vp.set_input_as_handled()


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		return
	var busy := false
	for i in items.size():
		var to := 1.0 if i == focus else 0.0
		if absf(_t[i] - to) > 0.002:
			_t[i] = UiKit.damp(_t[i], to, 16.0, dt)
			busy = true
	if busy:
		queue_redraw()


func _draw() -> void:
	var df := UiKit.font("display")
	var nf := UiKit.font("body")
	for i in items.size():
		var it := items[i]
		var r := _rects[i]
		var t := _t[i]
		var kind: String = it.get("kind", "big")
		var accent: Color = it.get("color", UiKit.ACCENT)
		var slant := 0.18 if kind != "small" else 0.22
		UiKit.draw_slant(self, r, Color(1, 1, 1, 0.07 if kind == "hero" else 0.045), slant)
		if t > 0.01:
			UiKit.draw_slant(self, Rect2(r.position, Vector2(lerpf(8.0, r.size.x, t), r.size.y)), Color(accent, t), slant)
		UiKit.draw_slant(self, Rect2(r.position, Vector2(5, r.size.y)), accent, slant)
		var ink := UiKit.INK.lerp(UiKit.BG, t)
		var dim := Color(UiKit.INK_DIM.lerp(Color(UiKit.BG, 0.75), t))
		var x := r.position.x + r.size.y * slant + 16 + 6 * t
		var right := r.end.x - 18
		var value: String = it.get("value", "")
		if value != "":
			var vf := UiKit.font("cond", 2)
			var vs := 15 if kind != "small" else 13
			draw_string(vf, Vector2(x, r.position.y + (26 if kind != "small" else r.size.y * 0.5 + 5)), value.to_upper(),
				HORIZONTAL_ALIGNMENT_RIGHT, right - x, vs, Color(accent, 1.0 - t).lerp(UiKit.BG, t))
		match kind:
			"small":
				draw_string(df, Vector2(x, r.get_center().y + 7), it.title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink)
			"hero":
				draw_string(UiKit.font("cond", 3), Vector2(x, r.position.y + 20), str(it.get("over", "")).to_upper(),
					HORIZONTAL_ALIGNMENT_LEFT, right - x, 12, Color(accent, 1.0 - t).lerp(UiKit.BG, t))
				draw_string(df, Vector2(x, r.position.y + 46), it.title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, right - x, 28, ink)
				draw_string(nf, Vector2(x, r.position.y + 63), it.get("note", ""), HORIZONTAL_ALIGNMENT_LEFT, right - x, 13, dim)
			_:
				draw_string(df, Vector2(x, r.position.y + 28), it.title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, right - x, 25, ink)
				draw_string(nf, Vector2(x, r.position.y + 45), it.get("note", ""), HORIZONTAL_ALIGNMENT_LEFT, right - x, 13, dim)
