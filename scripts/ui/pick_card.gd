class_name PickCard
extends Control
## What's picked for one part of the race (the track, the car) as a title lockup that opens
## its picker: an amber kicker ("TRACK · NEED FOR SPEED III"), the name large, a line of facts
## under it, and "CHANGE [T] ›" at the right, brighter under the pointer or with focus. A
## click, or Enter while it has focus, presses it. draw_lockup() sets the same lockup
## anywhere else a track or car is shown.

signal pressed
signal hovered

const H := 92.0

var kicker := ""
var title := ""
var subtitle := ""
var key := ""
## A track outline beside the title (0..1, aspect kept); `open` for a point-to-point run.
var outline := PackedVector2Array()
var open := false
var focused := false

var _hover := false
var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size.y = H


func set_content(p_kicker: String, p_title: String, p_subtitle: String) -> void:
	kicker = p_kicker
	title = p_title
	subtitle = p_subtitle
	queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_hover = true
			hovered.emit()
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			_hover = false
			queue_redraw()


func _process(dt: float) -> void:
	var to := 1.0 if focused else 0.0
	if absf(_t - to) > 0.002:
		_t = UiKit.damp(_t, to, 16.0, dt)
		queue_redraw()


## A lockup at `pos` (its top left), `w` wide: kicker, title (up to `size`), facts. Returns the
## title's right end, for anything set after it.
static func draw_lockup(ci: CanvasItem, pos: Vector2, w: float, p_kicker: String, p_title: String, p_sub: String,
		size := 44, title_col := UiKit.INK) -> float:
	UiKit.kicker(ci, pos + Vector2(0, 13), p_kicker, w)
	var up := p_title.to_upper()
	var fs := UiKit.fit("display", up, w, size, 20)
	var df := UiKit.font("display")
	ci.draw_string(df, pos + Vector2(-2, 18 + fs * 0.92), up, HORIZONTAL_ALIGNMENT_LEFT, w, fs, title_col)
	ci.draw_string(UiKit.font("body"), pos + Vector2(0, 18 + fs * 0.92 + 24), p_sub, HORIZONTAL_ALIGNMENT_LEFT, w, 15,
		UiKit.INK_DIM)
	return pos.x + minf(df.get_string_size(up, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, w)


func _draw() -> void:
	var t := maxf(_t, 0.45 * float(_hover))
	UiKit.glow(self, Rect2(-12, 0, size.x + 12, size.y), t, UiKit.ACCENT if _t > 0.01 else UiKit.INK, _t > 0.01)
	# "CHANGE [T] ›" at the right, level with the title.
	var hot := _hover or _t > 0.5
	var cf := UiKit.font("cond", 1)
	var ty := 18 + 40 * 0.92 - 12
	var right := size.x - 4
	UiKit.chevron(self, Vector2(right - 4, ty), 1, UiKit.ACCENT if hot else UiKit.INK_DIM, 5.0, 2.0)
	right -= 16
	if key != "":
		var kw := UiKit.key_width(key, 12)
		UiKit.draw_key(self, Vector2(right - kw, ty), key, 12, UiKit.INK if hot else UiKit.INK_DIM)
		right -= kw + 8
	var cw := UiKit.text_width("cond", "CHANGE", 13, 1)
	draw_string(cf, Vector2(right - cw, ty + 5), "CHANGE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		UiKit.ACCENT if hot else UiKit.INK_DIM)
	right -= cw + 16
	var map_w := 0.0 if outline.size() < 3 else 58.0
	var end := draw_lockup(self, Vector2.ZERO, right - map_w, kicker, title, subtitle)
	if map_w > 0.0:
		_draw_outline(Rect2(end + 14, 18, 44, 36))


func _draw_outline(box: Rect2) -> void:
	var ext := Vector2.ZERO
	for p in outline:
		ext = ext.max(p)
	var s := minf(box.size.x / maxf(ext.x, 0.01), box.size.y / maxf(ext.y, 0.01))
	var off := box.position + (box.size - ext * s) * 0.5
	var sp := PackedVector2Array()
	for p in outline:
		sp.append(off + p * s)
	if not open:
		sp.append(sp[0])
	draw_polyline(sp, Color(UiKit.ACCENT, 0.9), 1.6, true)
	if open:
		UiKit.route_ends(self, sp[0], sp[1] - sp[0], sp[-1], 0.55)
