class_name NowPlaying
extends CanvasLayer
## A song's title and artist, faded in low in the middle of the screen for a few seconds when it
## starts, over menus and races alike (between the HUD's map and tach, above the key hints).

const HOLD_S := 4.0
const SLIDE_S := 0.35
const W := 300.0
const H := 76.0
const BOTTOM := 92.0     # its bottom edge, up from the screen's

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
	var size := _draw.size
	var tf := UiKit.font("display")
	var af := UiKit.font("cond_med", 1)
	var w := maxf(W, maxf(tf.get_string_size(_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x,
			af.get_string_size(_artist, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x) + 56.0)
	var r := Rect2((size.x - w) * 0.5, size.y - BOTTOM - H + (1.0 - k) * 16.0, w, H)
	UiKit.draw_slant(_draw, Rect2(r.position + Vector2(5, 5), r.size), Color(0, 0, 0, 0.3 * k))
	UiKit.draw_slant(_draw, r, Color(UiKit.PANEL, UiKit.PANEL.a * k))
	UiKit.draw_slant(_draw, Rect2(r.position, Vector2(6, H)), Color(UiKit.ACCENT, k))
	var x := r.position.x + 24.0
	_draw.draw_string(UiKit.font("cond", 3), Vector2(x, r.position.y + 19), "NOW PLAYING",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(UiKit.ACCENT, k))
	_draw.draw_string(tf, Vector2(x - 2, r.position.y + 45), _title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26,
			Color(UiKit.INK, k))
	_draw.draw_string(af, Vector2(x - 5, r.position.y + 65), _artist, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			Color(UiKit.INK_DIM, UiKit.INK_DIM.a * k))
