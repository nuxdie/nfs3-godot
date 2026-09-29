class_name PickerRow
extends Control
## The track or car in the race setup: a thumbnail (or class badge), the name and a line
## of detail. Clicking it opens its browser; the ‹ › hot-spots (or ←→ when focused) step
## to the previous or next one without leaving the setup.

signal browse
signal stepped(dir: int)
signal hovered

const H := 84.0

var caption := ""
var title := ""
var subtitle := ""
var hotkey := ""             # key cap shown with the browse hint ("T")
var browse_text := ""        # "ALL 29"
var thumb: Texture2D
var badge := ""              # big letter in place of a thumbnail ("A")
var badge_color := UiKit.ACCENT
var focused := false

var _focus_t := 0.0
var _hover := false
var _hover_arrow := -1
var _flash := [0.0, 0.0]
var _slide := 0.0


func _init(p_caption := "", p_hotkey := "") -> void:
	caption = p_caption
	hotkey = p_hotkey
	custom_minimum_size = Vector2(0, H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## The value changed: slide the new name in from the side it came from.
func set_value(p_title: String, p_subtitle: String, dir := 0) -> void:
	title = p_title
	subtitle = p_subtitle
	if dir != 0:
		_slide = -dir * 22.0
		_flash[0 if dir < 0 else 1] = 1.0
	queue_redraw()


func _arrow_rects() -> Array[Rect2]:
	var aw := 30.0
	return [Rect2(size.x - aw * 2 - 8, 0, aw, size.y), Rect2(size.x - aw - 4, 0, aw, size.y)]


func _process(dt: float) -> void:
	var target := 1.0 if focused or _hover else 0.0
	var busy: bool = absf(_focus_t - target) > 0.002 or absf(_slide) > 0.3 or _flash[0] > 0.0 or _flash[1] > 0.0
	if not busy:
		return
	_focus_t = UiKit.damp(_focus_t, target, 14.0, dt)
	_slide = UiKit.damp(_slide, 0.0, 16.0, dt)
	_flash[0] = maxf(_flash[0] - dt * 4.0, 0.0)
	_flash[1] = maxf(_flash[1] - dt * 4.0, 0.0)
	queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var ar := _arrow_rects()
		var h := 0 if ar[0].has_point(e.position) else (1 if ar[1].has_point(e.position) else -1)
		if h != _hover_arrow:
			_hover_arrow = h
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				if _hover_arrow >= 0:
					stepped.emit(-1 if _hover_arrow == 0 else 1)
				else:
					browse.emit()
				accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				stepped.emit(-1)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				stepped.emit(1)
				accept_event()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_hover = true
			hovered.emit()
		NOTIFICATION_MOUSE_EXIT:
			_hover = false
			_hover_arrow = -1
			queue_redraw()


func _draw() -> void:
	var w := size.x
	var t := _focus_t
	var lit := 1.0 if focused else 0.0
	UiKit.draw_slant(self, Rect2(0, 4, w, H - 8), Color(1, 1, 1, 0.035 + 0.05 * t), 0.08)
	if focused:
		UiKit.draw_slant(self, Rect2(0, 4, 4, H - 8), UiKit.ACCENT, 0.08)
	# Thumbnail (a track's postcard) or a class badge.
	var tr := Rect2(18, 12, 107, H - 24)
	var x0 := 18.0
	if thumb:
		draw_texture_rect(thumb, tr, false, Color(1, 1, 1, 0.75 + 0.25 * t))
		draw_rect(tr, Color(1, 1, 1, 0.12 + 0.3 * lit), false, 1.0)
		x0 = tr.end.x + 16
	elif badge != "":
		var br := Rect2(18, 14, H - 28, H - 28)
		UiKit.draw_slant(self, br, Color(badge_color, 0.9), 0.15)
		draw_string(UiKit.font("display"), Vector2(br.position.x, br.get_center().y + 13), badge,
			HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 36, UiKit.BG)
		x0 = br.end.x + 16
	var right := _arrow_rects()[0].position.x - 8
	var cap_col := UiKit.ACCENT if focused else UiKit.INK_DIM
	var cf := UiKit.font("cond", 3)
	draw_string(cf, Vector2(x0, 27), caption.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cap_col)
	# Browse hint beside the caption: the hot key and how many there are to choose from.
	var cw := cf.get_string_size(caption.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var hx := x0 + cw + 12
	var hint_a := 0.35 + 0.65 * t
	if hotkey != "":
		hx += UiKit.draw_key(self, Vector2(hx, 22), hotkey, 11, Color(UiKit.INK, hint_a)) + 6
	draw_string(UiKit.font("cond", 2), Vector2(hx, 27), browse_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
		Color(UiKit.INK_DIM, UiKit.INK_DIM.a * hint_a))
	var vf := UiKit.font("display")
	var max_w := right - x0
	var fs := 28
	var txt := title.to_upper()
	while fs > 16 and vf.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		fs -= 2
	var fade := 1.0 - clampf(absf(_slide) / 26.0, 0.0, 1.0) * 0.8
	draw_string(vf, Vector2(x0 + _slide, 55), txt, HORIZONTAL_ALIGNMENT_LEFT, max_w, fs, Color(UiKit.INK, fade))
	draw_string(UiKit.font("cond", 2), Vector2(x0, 73), subtitle.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, max_w, 12,
		UiKit.INK_DIM)
	var ar := _arrow_rects()
	for i in 2:
		var hot := _hover_arrow == i
		var fl: float = _flash[i]
		var col := UiKit.INK.lerp(UiKit.ACCENT, maxf(fl, 1.0 if hot else 0.0))
		var al := 0.45 + 0.4 * t + (0.2 if hot else 0.0)
		if hot:
			UiKit.draw_slant(self, ar[i].grow_individual(0, -14, 0, -14), Color(1, 1, 1, 0.08), 0.15)
		var c: Vector2 = ar[i].get_center() + Vector2((-4.0 if i == 0 else 4.0) * fl, 0)
		var d := -1.0 if i == 0 else 1.0
		draw_polyline(PackedVector2Array([c + Vector2(-4 * d, -8), c + Vector2(4 * d, 0), c + Vector2(-4 * d, 8)]),
			Color(col, minf(al, 1.0)), 2.5, true)
