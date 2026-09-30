class_name BigButton
extends Control
## The screen's one main action, bottom right: a slanted slab with its key beside the text
## ("START RACE  [ENTER]"). Pushes out under the pointer; a sheen sweeps across it now and then.

signal pressed

var text := ""
var key := "ENTER"

var _hot := 0.0
var _hover := false
var _time := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func set_text(t: String) -> void:
	text = t
	queue_redraw()


## Lit as though pointed at (the moment it's used from the keyboard).
func flash() -> void:
	_hot = 1.0


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER: _hover = true
		NOTIFICATION_MOUSE_EXIT: _hover = false


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		return
	_time += dt
	_hot = UiKit.damp(_hot, 1.0 if _hover else 0.0, 12.0, dt)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var t := _hot
	# Drop "shadow" slab, then the face; hovering pushes the face out a touch.
	UiKit.draw_slant(self, Rect2(r.position + Vector2(6, 6), r.size), Color(UiKit.ACCENT_HOT, 0.35 + 0.3 * t))
	var face := Rect2(r.position - Vector2(3, 3) * t, r.size)
	UiKit.draw_slant(self, face, UiKit.ACCENT.lerp(Color(1, 0.85, 0.4), t * 0.6))
	var sweep := fmod(_time * 0.45, 1.6) - 0.3
	if sweep > -0.2 and sweep < 1.2:
		var sx := face.position.x + face.size.x * sweep
		var sp := PackedVector2Array([Vector2(sx, face.position.y), Vector2(sx + 40, face.position.y),
			Vector2(sx + 40 - face.size.y * 0.5, face.end.y), Vector2(sx - face.size.y * 0.5, face.end.y)])
		for poly in Geometry2D.intersect_polygons(sp, UiKit.slant_points(face)):
			draw_colored_polygon(poly, Color(1, 1, 1, 0.25))
	var f := UiKit.font("display")
	var kw := UiKit.key_width(key, 12) + 14.0 if key != "" else 0.0
	var fs := 30
	while fs > 18 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > face.size.x - 50 - kw:
		fs -= 2
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := face.position.x + (face.size.x - tw - kw) * 0.5
	var cy := face.get_center().y
	draw_string(f, Vector2(x, cy + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.BG)
	if key != "":
		UiKit.draw_key(self, Vector2(x + tw + 14, cy), key, 12, UiKit.BG)
