class_name WorldMap
extends Control
## The world drawn by shaders/world_map.gdshader, with a camera that glides (and zooms) to
## frame what it's told to. Places go in as latitude/longitude; project() turns them into map
## units (Miller projection: radians across 0..2π, down 0..π, as data/world_map.png) and
## to_px() into this control's pixels for the camera as it is now (or as it's heading).

signal moved

const MAP_PATH := "res://data/world_map.png"
const TOP := 2.0016178          # miller(84°): the picture's top edge
const MIN_ZOOM := 100.0         # px per map unit: the whole world about fits 640 px
const MAX_ZOOM := 9000.0

## Where to fit things (this control's pixels): the rest of it is drawn but may be covered.
var frame := Rect2()
var center := Vector2(PI, 1.2)  # map units at the frame's middle, now
var zoom := MIN_ZOOM
var _to_center := center
var _to_zoom := zoom

static var _tex: Texture2D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/world_map.gdshader")
	mat.set_shader_parameter("map_tex", _texture())
	material = mat
	resized.connect(_push)


static func _texture() -> Texture2D:
	if _tex == null:
		# Read straight from the file: it works without the editor having imported it.
		var img := Image.load_from_file(ProjectSettings.globalize_path(MAP_PATH))
		if img == null or img.is_empty():
			img = Image.create(8, 4, false, Image.FORMAT_RGB8)
		img.generate_mipmaps()
		_tex = ImageTexture.create_from_image(img)
	return _tex


## Map units of a place.
static func project(lat: float, lon: float) -> Vector2:
	var phi := deg_to_rad(clampf(lat, -89.0, 89.0))
	return Vector2(deg_to_rad(lon) + PI, TOP - 1.25 * log(tan(PI / 4.0 + 0.4 * phi)))


## A point in map units on screen (this control's pixels), for the camera now, or for where
## it's heading with `target`.
func to_px(p: Vector2, target := false) -> Vector2:
	var c := _to_center if target else center
	var z := _to_zoom if target else zoom
	return frame.get_center() + (p - c) * z


func to_map(px: Vector2) -> Vector2:
	return (px - frame.get_center()) / zoom + center


## Frame `r` (map units) in `frame`, `pad` px in from its edges (across, down), no closer
## than `max_zoom`.
func fit(r: Rect2, instant := false, pad := Vector2(50, 50), max_zoom := MAX_ZOOM) -> void:
	var area := (frame.size - pad * 2).max(Vector2(40, 40))
	var z := minf(area.x / maxf(r.size.x, 0.0001), area.y / maxf(r.size.y, 0.0001))
	_to_zoom = clampf(z, MIN_ZOOM, max_zoom)
	_to_center = r.get_center()
	if instant:
		center = _to_center
		zoom = _to_zoom
		_push()


func settled() -> bool:
	return center.distance_to(_to_center) * zoom < 0.5 and absf(log(zoom / _to_zoom)) < 0.002


func _process(dt: float) -> void:
	if not is_visible_in_tree() or settled():
		return
	# Zoom in log space, so a long zoom out and back in reads as even. The centre follows in
	# step, weighted so far moves don't swing past the frame.
	var k := 1.0 - exp(-6.5 * dt)
	var lz := lerpf(log(zoom), log(_to_zoom), k)
	zoom = exp(lz)
	center = center.lerp(_to_center, k)
	if settled():
		center = _to_center
		zoom = _to_zoom
	_push()
	moved.emit()


func _push() -> void:
	var mat := material as ShaderMaterial
	mat.set_shader_parameter("center", center)
	mat.set_shader_parameter("zoom", zoom)
	mat.set_shader_parameter("origin", frame.get_center())
	mat.set_shader_parameter("rect_size", size)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
