class_name NowPlaying
extends CanvasLayer
## A song's title and artist, faded in for a few seconds when it starts, the same over menus,
## loading and races: a note, the title and the artist in one line at the top right, on a
## soft shade so it reads over anything. Whoever owns the top right moves it clear:
## `right` (px in from the right edge) and `top` (its baseline).

const HOLD_S := 4.5
const SLIDE_S := 0.35
const RIGHT := 40.0
const TOP := 40.0

var right := RIGHT
var top := TOP

var _title := ""
var _artist := ""
var _t := -1.0          # time since shown; < 0 hidden
var _delay := 0.0
var _draw := Control.new()


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_on_draw)
	add_child(_draw)


## Shows `title` by `artist` after `delay` seconds (e.g. to let a scene settle first).
func show_title(title: String, artist := "", delay := 0.0) -> void:
	_title = title
	_artist = artist
	_delay = delay
	_t = 0.0 if title != "" else -1.0
	_draw.queue_redraw()


## Back to the corner, for a scene that doesn't move it.
func reset_place() -> void:
	right = RIGHT
	top = TOP
	_draw.queue_redraw()


func _process(dt: float) -> void:
	if _t < 0.0:
		return
	if _delay > 0.0:
		_delay -= dt
		return
	_t += dt
	if _t > HOLD_S + 2.0 * SLIDE_S:
		_t = -1.0
	_draw.queue_redraw()


func _on_draw() -> void:
	if _t < 0.0 or _delay > 0.0:
		return
	# 0 -> 1 coming in, 1 holding, 1 -> 0 going.
	var k := minf(_t / SLIDE_S, 1.0)
	if _t > SLIDE_S + HOLD_S:
		k = 1.0 - (_t - SLIDE_S - HOLD_S) / SLIDE_S
	k = clampf(k, 0.0, 1.0)
	k = 1.0 - pow(1.0 - k, 3.0)
	var tf := UiKit.font("cond", 1)
	var af := UiKit.font("body")
	var title := _title.to_upper()
	var artist := ("  ·  " + _artist) if _artist != "" else ""
	var tw := tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var aw := af.get_string_size(artist, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var end := _draw.size.x - right + (1.0 - k) * 12.0
	var x := end - tw - aw
	var y := top
	UiKit.shade(_draw, Rect2(x - 70, y - 34, tw + aw + 120, 56), 0.6 * k)
	# A quaver.
	var n := Vector2(x - 16, y - 1)
	_draw.draw_circle(n, 3.5, Color(UiKit.ACCENT, k), true, -1.0, true)
	_draw.draw_line(n + Vector2(3, 0), n + Vector2(3, -13), Color(UiKit.ACCENT, k), 1.5)
	_draw.draw_line(n + Vector2(3, -13), n + Vector2(8, -9), Color(UiKit.ACCENT, k), 1.5)
	_draw.draw_string(tf, Vector2(x, y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(UiKit.INK, k))
	_draw.draw_string(af, Vector2(x + tw, y), artist, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Color(UiKit.INK_DIM, UiKit.INK_DIM.a * k))
