class_name CarStats
extends Control
## Four segmented performance bars (speed, acceleration, handling, braking) read
## from a car's carp data; they glide to the new values when the car changes.

const NAMES := ["TOP SPEED", "ACCELERATION", "HANDLING", "BRAKING"]
const SEGMENTS := 20

var _target := [0.0, 0.0, 0.0, 0.0]
var _shown := [0.0, 0.0, 0.0, 0.0]
var _readout := ["", "", "", ""]
## Weight and gearbox, for the caption above the bars.
var spec := ""


## Normalised 0..1 ratings against the spread of the stock NFS3 cars.
static func ratings(data: Object) -> Array:
	var tq: PackedFloat32Array = data.carp.get(10, PackedFloat32Array([400.0]))
	var peak := 0.0
	for v in tq:
		peak = maxf(peak, v)
	var mass: float = maxf(data.carp_value(2, 1400.0), 600.0)
	var top_kmh: float = data.carp_value(15, 70.0) * 3.6
	return [
		inverse_lerp(150.0, 370.0, top_kmh),
		inverse_lerp(0.15, 0.75, peak / mass),
		inverse_lerp(2.4, 4.0, data.carp_value(30, 3.2)),
		inverse_lerp(7.0, 12.2, data.carp_value(18, 10.0)),
	]


func set_car(data: Object, kmh: bool) -> void:
	var r := ratings(data)
	for i in 4:
		_target[i] = clampf(r[i], 0.04, 1.0)
	var top: float = data.carp_value(15, 70.0) * 3.6
	_readout[0] = "%d KM/H" % roundi(top) if kmh else "%d MPH" % roundi(top / 1.609)
	var tq: PackedFloat32Array = data.carp.get(10, PackedFloat32Array([400.0]))
	var peak := 0.0
	for v in tq:
		peak = maxf(peak, v)
	var ratios: PackedFloat32Array = data.carp.get(8, PackedFloat32Array())
	var gears := 0
	for g in range(2, ratios.size()):
		gears += int(ratios[g] > 0.0)
	_readout[1] = "%d NM" % roundi(peak)
	spec = "%d KG" % roundi(data.carp_value(2, 1400.0))
	if gears > 0:
		spec += "   ·   %d-SPEED" % gears
	queue_redraw()


func _process(dt: float) -> void:
	var busy := false
	for i in 4:
		# Stagger so the bars ripple rather than move as one block.
		var rate := 7.0 - i * 1.1
		var v := UiKit.damp(_shown[i], _target[i], rate, dt)
		busy = busy or absf(v - _shown[i]) > 0.0005
		_shown[i] = v
	if busy:
		queue_redraw()


func _draw() -> void:
	var cols := 2
	var gap := Vector2(28, 12)
	var cw := (size.x - gap.x * (cols - 1)) / cols
	var rh := (size.y - gap.y) / 2.0
	var f := UiKit.font("cond", 2)
	for i in 4:
		var o := Vector2((i % cols) * (cw + gap.x), (i / cols) * (rh + gap.y))
		draw_string(f, o + Vector2(0, 13), NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.INK_DIM)
		draw_string(f, o + Vector2(0, 13), _readout[i], HORIZONTAL_ALIGNMENT_RIGHT, cw, 12, UiKit.INK)
		var sw := (cw - (SEGMENTS - 1) * 2.0) / SEGMENTS
		var lit: float = _shown[i] * SEGMENTS
		for s in SEGMENTS:
			var r := Rect2(o + Vector2(s * (sw + 2.0), 20), Vector2(sw, 8))
			var fill := clampf(lit - s, 0.0, 1.0)
			draw_colored_polygon(UiKit.slant_points(r, 0.35), Color(1, 1, 1, 0.1))
			if fill > 0.0:
				var c := UiKit.ACCENT.lerp(UiKit.ACCENT_HOT, float(s) / SEGMENTS)
				draw_colored_polygon(UiKit.slant_points(r, 0.35), Color(c, fill))
