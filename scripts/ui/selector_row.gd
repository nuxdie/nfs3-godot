class_name SelectorRow
extends Control
## One "‹ value ›" setting row: a small caption over a big value, stepped with
## left/right (keys, pad or the arrow hot-spots) and highlighted when focused.
## The owning menu moves focus; the row only draws itself and handles the mouse.

signal changed(index: int)
signal hovered

var caption := ""
var items: PackedStringArray = []
var index := 0
var wrap := true
var focused := false
var last_dir := 0          # direction of the most recent step
var disabled := false
var disabled_text := "—"

var _focus_t := 0.0     # 0..1 animated highlight
var _slide := 0.0       # value text offset, eases to 0 after a change
var _flash_l := 0.0
var _flash_r := 0.0
var _hover_l := false
var _hover_r := false

const H := 60.0


func _init(p_caption := "", p_items: PackedStringArray = []) -> void:
	caption = p_caption
	items = p_items
	custom_minimum_size = Vector2(0, H)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_items(p_items: PackedStringArray, p_index := 0) -> void:
	items = p_items
	index = clampi(p_index, 0, maxi(items.size() - 1, 0))
	queue_redraw()


func value_text() -> String:
	return items[index] if index < items.size() else ""


## Step the value; returns true if it changed.
func step(dir: int) -> bool:
	if disabled or items.size() < 2:
		return false
	var n := index + dir
	if wrap:
		n = posmod(n, items.size())
	else:
		n = clampi(n, 0, items.size() - 1)
	if n == index:
		return false
	index = n
	last_dir = dir
	_slide = -dir * 26.0
	if dir < 0:
		_flash_l = 1.0
	else:
		_flash_r = 1.0
	changed.emit(index)
	queue_redraw()
	return true


func _process(dt: float) -> void:
	var target := 1.0 if focused and not disabled else 0.0
	var busy := absf(_focus_t - target) > 0.002 or absf(_slide) > 0.3 or _flash_l > 0.0 or _flash_r > 0.0
	if not busy:
		return
	_focus_t = UiKit.damp(_focus_t, target, 14.0, dt)
	_slide = UiKit.damp(_slide, 0.0, 16.0, dt)
	_flash_l = maxf(_flash_l - dt * 4.0, 0.0)
	_flash_r = maxf(_flash_r - dt * 4.0, 0.0)
	queue_redraw()


func _arrow_rects() -> Array[Rect2]:
	var aw := 34.0
	return [Rect2(size.x - aw * 2 - 6, 0, aw, size.y), Rect2(size.x - aw - 2, 0, aw, size.y)]


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var ar := _arrow_rects()
		var l: bool = ar[0].has_point(e.position)
		var r: bool = ar[1].has_point(e.position)
		if l != _hover_l or r != _hover_r:
			_hover_l = l
			_hover_r = r
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed and not disabled:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				var ar := _arrow_rects()
				step(-1 if ar[0].has_point(e.position) else 1)
				accept_event()
			MOUSE_BUTTON_RIGHT:
				step(-1)
				accept_event()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			hovered.emit()
		NOTIFICATION_MOUSE_EXIT:
			_hover_l = false
			_hover_r = false
			queue_redraw()


func _draw() -> void:
	var w := size.x
	var t := _focus_t
	var a := 0.4 if disabled else 1.0
	# Highlight: a slanted panel that grows in from the left, with an accent edge.
	if t > 0.01:
		var hr := Rect2(0, 3, lerpf(w * 0.4, w, t), H - 6)
		UiKit.draw_slant(self, hr, Color(1, 1, 1, 0.075 * t), 0.12)
		var grad := PackedColorArray([Color(UiKit.ACCENT, 0.22 * t), Color(UiKit.ACCENT, 0.0)])
		var gp := UiKit.slant_points(Rect2(0, 3, w * 0.55, H - 6), 0.12)
		draw_polygon(gp, PackedColorArray([grad[0], grad[1], grad[1], grad[0]]))
		UiKit.draw_slant(self, Rect2(0, 3, 5, H - 6), Color(UiKit.ACCENT, t), 0.12)
	var x0 := 22.0 + 6.0 * t
	var cap_col := UiKit.ACCENT if t > 0.5 else UiKit.INK_DIM
	draw_string(UiKit.font("cond", 3), Vector2(x0, 21), caption.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(cap_col, cap_col.a * a))
	var val := disabled_text if disabled else value_text()
	var vf := UiKit.font("display")
	var max_w := w - x0 - 90.0
	var fs := 30
	while fs > 18 and vf.get_string_size(val.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		fs -= 2
	var fade := 1.0 - clampf(absf(_slide) / 30.0, 0.0, 1.0) * 0.8
	draw_string(vf, Vector2(x0 + _slide, 50), val.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, max_w, fs,
		Color(UiKit.INK, a * fade))
	# Arrows (only obvious when focused or hovered; always clickable).
	if not disabled and items.size() > 1:
		var ar := _arrow_rects()
		for i in 2:
			var hot: bool = _hover_l if i == 0 else _hover_r
			var fl: float = _flash_l if i == 0 else _flash_r
			var edge_ok: bool = wrap or (index > 0 if i == 0 else index < items.size() - 1)
			var al := (0.8 * t + (0.3 if hot else 0.0)) * (1.0 if edge_ok else 0.25)
			var col := UiKit.INK.lerp(UiKit.ACCENT, maxf(fl, 1.0 if hot else 0.0))
			var c: Vector2 = ar[i].get_center() + Vector2(0, 2) + Vector2((-4.0 if i == 0 else 4.0) * fl, 0)
			var d := -1.0 if i == 0 else 1.0
			draw_polyline(PackedVector2Array([c + Vector2(-4 * d, -8), c + Vector2(4 * d, 0), c + Vector2(-4 * d, 8)]),
				Color(col, minf(al, 1.0)), 2.5, true)
