class_name StepBar
extends Control
## The way through a setup, across the top: where it started (the mode; a click goes back to
## the home screen), then the steps, numbered, each with what has been picked in it. The
## current step is lit and any step is a click away.

signal chosen(step: int)   # -1: the crumb

const CRUMB_GAP := 26.0

var crumb := ""
var crumb_color := UiKit.ACCENT
var labels := PackedStringArray()
var values := PackedStringArray()
var index := 0

var _crumb_rect := Rect2()
var _rects: Array[Rect2] = []
var _hover := -2               # -2 none, -1 the crumb, else a step
var _sel := Rect2()            # the lit step's underline, gliding between steps


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_measure)


func set_steps(p_crumb: String, p_labels: PackedStringArray, p_values: PackedStringArray, p_index: int) -> void:
	var jump := labels != p_labels or crumb != p_crumb
	crumb = p_crumb
	labels = p_labels
	values = p_values
	index = p_index
	_measure()
	if jump and index < _rects.size():
		_sel = _rects[index]
	queue_redraw()


func set_values(p_values: PackedStringArray) -> void:
	values = p_values
	queue_redraw()


func _measure() -> void:
	var cw := UiKit.text_width("display", crumb, 22) + 36.0
	_crumb_rect = Rect2(0, 0, cw, size.y)
	_rects.clear()
	var x := cw + CRUMB_GAP
	var n := maxi(labels.size(), 1)
	var w := clampf((size.x - x) / n, 150.0, 280.0)
	for i in labels.size():
		_rects.append(Rect2(x + i * w, 0, w - 10.0, size.y))


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
		var h := -1 if _crumb_rect.has_point(e.position) else -2
		for i in _rects.size():
			if _rects[i].has_point(e.position):
				h = i
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h > -2 else Control.CURSOR_ARROW
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _hover > -2:
		accept_event()
		chosen.emit(_hover)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != -2:
		_hover = -2
		queue_redraw()


func _draw() -> void:
	var cy := size.y * 0.5
	# The crumb: "‹ SINGLE RACE".
	var cr := _crumb_rect
	var hot := _hover == -1
	if hot:
		UiKit.draw_slant(self, cr.grow_individual(0, -6, 0, -6), Color(crumb_color, 0.14), 0.15)
	var ax := cr.position.x + 12
	var col := crumb_color if not hot else crumb_color.lightened(0.3)
	draw_polyline(PackedVector2Array([Vector2(ax + 5, cy - 7), Vector2(ax - 1, cy), Vector2(ax + 5, cy + 7)]), col, 2.5, true)
	draw_string(UiKit.font("display"), Vector2(ax + 14, cy + 8), crumb, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
	draw_line(Vector2(cr.end.x + CRUMB_GAP * 0.5, cy - 14), Vector2(cr.end.x + CRUMB_GAP * 0.5 - 6, cy + 14), UiKit.INK_FAINT, 1.0)
	# The steps.
	if index < _rects.size():
		UiKit.draw_slant(self, Rect2(_sel.position.x, size.y - 3, _sel.size.x, 3), UiKit.ACCENT, 0.5)
	var lf := UiKit.font("cond", 3)
	var vf := UiKit.font("display")
	for i in _rects.size():
		var r := _rects[i]
		var now := i == index
		var over := i == _hover
		if now or over:
			UiKit.draw_slant(self, r, Color(1, 1, 1, 0.08 if now else 0.05), 0.18)
		var nr := Rect2(r.position.x + 10, cy - 13, 26, 26)
		if now:
			UiKit.draw_slant(self, nr, UiKit.ACCENT, 0.15)
		else:
			draw_polyline(UiKit.slant_points(nr, 0.15) + PackedVector2Array([UiKit.slant_points(nr, 0.15)[0]]),
				UiKit.ACCENT if over else UiKit.INK_DIM, 1.0, true)
		draw_string(vf, Vector2(nr.position.x, cy + 7), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, nr.size.x, 19,
			UiKit.BG if now else (UiKit.ACCENT if over else UiKit.INK_DIM))
		var x := nr.end.x + 10
		var w := r.end.x - x - 6
		draw_string(lf, Vector2(x, cy - 5), labels[i], HORIZONTAL_ALIGNMENT_LEFT, w, 12,
			UiKit.ACCENT if now or over else UiKit.INK_DIM)
		var v := values[i].to_upper() if i < values.size() else ""
		var fs := 18
		while fs > 13 and vf.get_string_size(v, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
			fs -= 1
		draw_string(vf, Vector2(x, cy + 15), v, HORIZONTAL_ALIGNMENT_LEFT, w, fs, UiKit.INK if now or over else UiKit.INK_DIM)
