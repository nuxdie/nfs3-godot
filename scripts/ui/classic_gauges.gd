class_name ClassicGauges
extends Control
## High Stakes' own dials (GameArt/hud98.qfs) in place of the HUD's tach, at the size its
## hud0.pos gives them: the dual-scale speedometer (mph outside, km/h inside, from its
## atlas) and the rev counter for the car's redline ("650B": 6,500 rpm, 0-9 on its face),
## needles drawn over them. Settings -> HUD -> Dials: "HS · top" puts them where hud0.pos
## does, either side of the rear-view mirror (the gaps to it kept, so they hug the mirror on
## a wide screen too); "HS · bottom" puts them side by side at the bottom centre.

## Where the atlas ("4444") keeps the big speedometer, and each dial's needle geometry:
## centre (in the image), and the angle (clockwise from straight up) at the start and end of
## its scale.
const SPEEDO_REGION := Rect2i(153, 68, 103, 94)
const SPEEDO_CENTRE := Vector2(50, 52)
const SPEEDO_SWEEP := Vector2(-135.0, 135.0)   # degrees at 0 and 250 mph
const SPEEDO_TOP := 250.0                      # mph at the end of the scale
const TACH_CENTRE := Vector2(40, 40)
const TACH_SWEEP := Vector2(-135.0, 120.0)     # degrees at 0 and 9,000 rpm
const TACH_TOP := 9000.0

## Placements for dial_rects(): as High Stakes had them, or together at the bottom.
enum Placement { TOP, BOTTOM }
## hud0.pos: each dial 15.8% of the screen high; the speedometer ends 5.2% of the width short
## of the mirror (at 4:3), the rev counter starts 6.4% past it.
const HEIGHT := 0.158
const GAP_LEFT := 0.0516 * 640.0 / 480.0
const GAP_RIGHT := 0.064 * 640.0 / 480.0
const MIRROR_HALF := 200.0      # Hud's mirror: 400 px wide, centred at the top

var car: Car
var placement := Placement.TOP
var _speedo: Texture2D
var _tachs := {}   # "650" -> Texture2D


static func available() -> bool:
	return Game.hs_root != "" and Game.find_ci(Game.find_ci(Game.hs_root, "gameart"), "hud98.qfs") != ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fsh := Fsh.load_file(Game.find_ci(Game.find_ci(Game.hs_root, "gameart"), "hud98.qfs"))
	if fsh == null:
		return
	var atlas: Image = fsh.by_name.get("4444")
	if atlas:
		_speedo = ImageTexture.create_from_image(atlas.get_region(SPEEDO_REGION))
	for i in fsh.names.size():
		var n: String = fsh.names[i]
		if n.length() == 4 and n.ends_with("B") and n.left(3).is_valid_int():
			_tachs[n.left(3)] = ImageTexture.create_from_image(fsh.images[i])


func _process(_dt: float) -> void:
	queue_redraw()


## The dial for the car's redline: the nearest 500 rpm step at or above it, 4,000 to 9,000.
func _tach() -> Texture2D:
	var r := clampi(int(ceil(car.redline / 500.0)) * 50, 400, 900)
	while r >= 400 and not _tachs.has(str(r)):
		r -= 50
	return _tachs.get(str(r))


static func dial_height(screen_h: float) -> float:
	return screen_h * HEIGHT


## Where the speedometer and the rev counter go on a screen of `s`, for `p` (Placement).
static func dial_rects(s: Vector2, p: int) -> Array[Rect2]:
	var h := dial_height(s.y)
	var sw := h * 103.0 / 94.0
	var tw := h * 80.0 / 72.0
	var cx := s.x * 0.5
	if p == Placement.BOTTOM:
		var y := s.y - h - 14.0
		return [Rect2(cx - 6.0 - sw, y, sw, h), Rect2(cx + 6.0, y, tw, h)]
	var gl := GAP_LEFT * s.y
	var gr := GAP_RIGHT * s.y
	return [Rect2(cx - MIRROR_HALF - gl - sw, 0, sw, h), Rect2(cx + MIRROR_HALF + gr, 0, tw, h)]


func _draw() -> void:
	if car == null or not is_instance_valid(car):
		return
	var rs := dial_rects(size, placement)
	var h := rs[0].size.y
	var tach := _tach()
	if tach:
		draw_texture_rect(tach, rs[1], false)
		_needle(rs[1], TACH_CENTRE / Vector2(80, 72), TACH_SWEEP, car.rpm / TACH_TOP, h * 0.42)
	if _speedo:
		draw_texture_rect(_speedo, rs[0], false)
		_needle(rs[0], SPEEDO_CENTRE / Vector2(103, 94), SPEEDO_SWEEP, absf(car.speed) * 2.2369 / SPEEDO_TOP, h * 0.4)


func _needle(r: Rect2, centre: Vector2, sweep: Vector2, f: float, length: float) -> void:
	var c := r.position + centre * r.size
	var a := deg_to_rad(lerpf(sweep.x, sweep.y, clampf(f, 0.0, 1.05)))
	var tip := c + Vector2(sin(a), -cos(a)) * length
	draw_line(c, tip, Color(0, 0, 0, 0.5), 4.0, true)
	draw_line(c, tip, Color(1.0, 0.25, 0.1), 2.0, true)
	draw_circle(c, 3.5, Color(0.1, 0.1, 0.1))
