class_name BigButton
extends Control
## The screen's one main action, bottom right: a slanted amber slab with its key beside the
## text ("START RACE  [ENTER]"). Lifts a touch under the pointer. Disabled, it's a dim outline
## and a click does nothing (the screen says why elsewhere).

signal pressed

var text := ""
var key := "ENTER"
var enabled := true

var _hot := 0.0
var _hover := false
var _flash := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func set_text(t: String) -> void:
	text = t
	queue_redraw()


func set_enabled(on: bool) -> void:
	enabled = on
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW
	queue_redraw()


## Lit as though pointed at (the moment it's used from the keyboard).
func flash() -> void:
	_flash = 1.0


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if enabled:
			pressed.emit()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER: _hover = true
		NOTIFICATION_MOUSE_EXIT: _hover = false


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		return
	var to := 1.0 if _hover and enabled else 0.0
	if absf(_hot - to) < 0.002 and _flash <= 0.0:
		return
	_hot = UiKit.damp(_hot, to, 14.0, dt)
	_flash = maxf(_flash - dt * 3.0, 0.0)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var t := maxf(_hot, _flash)
	var f := UiKit.font("display")
	var kw := UiKit.key_width(key, 12) + 14.0 if key != "" else 0.0
	var fs := UiKit.fit("display", text, r.size.x - 60 - kw, 26, 16)
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if not enabled:
		draw_polyline(UiKit.slant_points(r, 0.18) + PackedVector2Array([UiKit.slant_points(r, 0.18)[0]]),
			Color(1, 1, 1, 0.25), 1.0, true)
		var x0 := r.position.x + (r.size.x - tw - kw) * 0.5
		draw_string(f, Vector2(x0, r.get_center().y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.INK_FAINT)
		if key != "":
			UiKit.draw_key(self, Vector2(x0 + tw + 14, r.get_center().y), key, 12, UiKit.INK_FAINT)
		return
	var face := Rect2(r.position - Vector2(0, 2) * t, r.size)
	UiKit.draw_slant(self, Rect2(r.position + Vector2(0, 3), r.size), Color(UiKit.ACCENT_HOT, 0.3 + 0.25 * t), 0.18)
	UiKit.draw_slant(self, face, UiKit.ACCENT.lerp(Color(1, 0.84, 0.4), t * 0.5), 0.18)
	var x := face.position.x + (face.size.x - tw - kw) * 0.5
	var cy := face.get_center().y
	draw_string(f, Vector2(x, cy + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.BG)
	if key != "":
		UiKit.draw_key(self, Vector2(x + tw + 14, cy), key, 12, UiKit.BG)
