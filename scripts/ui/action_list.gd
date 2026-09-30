class_name ActionList
extends Control
## A column (or row) of menu actions: up/down (left/right when horizontal) moves, accept
## activates, the mouse hovers and clicks. The one in focus is filled with the accent. Used by
## the pause and results screens. Set as big type; the one in focus bright, with the accent's
## wash behind it and a chevron. Handles its own input while visible.

signal activated(index: int)

var items: PackedStringArray = []
var horizontal := false
var focus := 0
var item_size := Vector2(300, 50)
var gap := 8.0

## Vertical lists could step each item right (0: a straight column).
const STAIR := 0.0

var _t: Array[float] = []     # per-item animated highlight
var _hover := -1


func _init(p_items: PackedStringArray = [], p_horizontal := false) -> void:
	items = p_items
	horizontal = p_horizontal
	_t.resize(items.size())
	_t.fill(0.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_size()


func _update_size() -> void:
	var n := items.size()
	custom_minimum_size = Vector2(item_size.x * n + gap * (n - 1), item_size.y) if horizontal \
		else Vector2(item_size.x + (n - 1) * item_size.y * STAIR, item_size.y * n + gap * (n - 1))
	size = custom_minimum_size


func set_item_size(s: Vector2) -> void:
	item_size = s
	_update_size()


func _item_rect(i: int) -> Rect2:
	var o := Vector2(i * (item_size.x + gap), 0) if horizontal else Vector2(i * item_size.y * STAIR, i * (item_size.y + gap))
	return Rect2(o, item_size)


func _item_at(p: Vector2) -> int:
	for i in items.size():
		if _item_rect(i).has_point(p):
			return i
	return -1


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := _item_at(e.position)
		if h != _hover:
			_hover = h
			if h >= 0:
				focus = h
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var h := _item_at(e.position)
		if h >= 0:
			focus = h
			accept_event()
			activated.emit(h)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1


func _unhandled_input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var prev := "ui_left" if horizontal else "ui_up"
	var next := "ui_right" if horizontal else "ui_down"
	# Taken first: an activated item can take this list out of the tree (quit to the menu,
	# restart), and then it has no viewport left to mark the event handled in.
	var vp := get_viewport()
	if e.is_action_pressed(prev, true):
		focus = posmod(focus - 1, items.size())
	elif e.is_action_pressed(next, true):
		focus = posmod(focus + 1, items.size())
	elif e.is_action_pressed("ui_accept"):
		activated.emit(focus)
	else:
		return
	vp.set_input_as_handled()


func _process(dt: float) -> void:
	for i in items.size():
		_t[i] = UiKit.damp(_t[i], 1.0 if i == focus else 0.0, 16.0, dt)
	queue_redraw()


func _draw() -> void:
	var f := UiKit.font("display")
	var fs := int(item_size.y * 0.56)
	for i in items.size():
		var r := _item_rect(i)
		var t := _t[i]
		UiKit.glow(self, r, t)
		if i == _hover and t < 0.5:
			UiKit.glow(self, r, 0.4, UiKit.INK, false)
		var col := UiKit.INK_DIM.lerp(UiKit.INK, t)
		var x := r.position.x + 18 + 6 * t
		draw_string(f, Vector2(x, r.get_center().y + fs * 0.36), items[i].to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
			r.size.x - 50, fs, col)
		if t > 0.05:
			UiKit.chevron(self, Vector2(r.end.x - 22 - 6 * (1.0 - t), r.get_center().y), 1, Color(UiKit.ACCENT, t), 6.0, 2.5)
