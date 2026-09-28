class_name TrackMap
extends Control
## Top-down outline of a lap that traces itself in when the track changes, with a
## dot lapping it. Fed the centreline in Godot space (x/z used).

var length_m := 0.0
var _pts := PackedVector2Array()   # normalised to 0..1, aspect kept
var _aspect := 1.0
var _reveal := 1.0
var _lap_t := 0.0


func set_outline(points: PackedVector3Array) -> void:
	_pts.clear()
	length_m = 0.0
	if points.size() < 3:
		queue_redraw()
		return
	var lo := Vector2(INF, INF)
	var hi := -lo
	for i in points.size():
		var p := Vector2(points[i].x, points[i].z)
		lo = lo.min(p)
		hi = hi.max(p)
		length_m += points[i].distance_to(points[(i + 1) % points.size()])
	var span := hi - lo
	var s := maxf(span.x, span.y)
	_aspect = span.x / maxf(span.y, 0.001)
	for p3 in points:
		_pts.append((Vector2(p3.x, p3.z) - lo) / s)
	_reveal = 0.0
	_lap_t = 0.0
	queue_redraw()


func _process(dt: float) -> void:
	if _pts.is_empty():
		return
	_reveal = minf(_reveal + dt * 1.6, 1.0)
	_lap_t = fmod(_lap_t + dt / 9.0, 1.0)
	queue_redraw()


func _to_screen() -> PackedVector2Array:
	var pad := 10.0
	var area := size - Vector2(pad, pad) * 2
	# Points span 0..1 on their long side; fit that box into the area and centre it.
	var norm := Vector2(1.0, 1.0 / _aspect) if _aspect >= 1.0 else Vector2(_aspect, 1.0)
	var s := minf(area.x / norm.x, area.y / norm.y)
	var off := Vector2(pad, pad) + (area - norm * s) * 0.5
	var out := PackedVector2Array()
	for p in _pts:
		out.append(off + p * s)
	return out


func _draw() -> void:
	if _pts.is_empty():
		var f := UiKit.font("cond", 2)
		draw_string(f, Vector2(0, size.y * 0.5), "NO MAP", HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, UiKit.INK_FAINT)
		return
	var sp := _to_screen()
	sp.append(sp[0])
	draw_polyline(sp, Color(1, 1, 1, 0.1), 7.0, true)
	var n := int((sp.size() - 1) * _reveal)
	if n >= 1:
		var part := sp.slice(0, n + 1)
		draw_polyline(part, Color(UiKit.ACCENT, 0.25), 6.0, true)
		draw_polyline(part, UiKit.ACCENT, 2.2, true)
	# Start/finish: a short bar across the road.
	var dir := (sp[1] - sp[0]).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	draw_line(sp[0] - nrm * 7, sp[0] + nrm * 7, UiKit.INK, 3.0)
	if _reveal >= 1.0:
		var fi := _lap_t * (sp.size() - 1)
		var i := int(fi)
		var p := sp[i].lerp(sp[mini(i + 1, sp.size() - 1)], fi - i)
		draw_circle(p, 7.0, Color(UiKit.ACCENT, 0.25))
		draw_circle(p, 3.5, UiKit.INK)
