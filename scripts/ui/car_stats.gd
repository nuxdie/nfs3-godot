class_name CarStats
extends Control
## Four performance bars (speed, acceleration, handling, braking) read from a car's carp
## data, each with its figure; they glide to the new values when the car changes.

const NAMES := ["TOP SPEED", "ACCELERATION", "HANDLING", "BRAKING"]
const SEGMENTS := 20

## The bars two by two, or (1) one under another.
var columns := 2

var _target := [0.0, 0.0, 0.0, 0.0]
var _shown := [0.0, 0.0, 0.0, 0.0]
var _readout := ["", "", "", ""]
## Weight and gearbox, for the caption above the bars.
var spec := ""
## The same as words in sentence case: ["Class C", "1518 kg", "6-speed", "RWD"].
var spec_parts := PackedStringArray()


## Normalised 0..1 ratings against the spread of the stock NFS3 cars, with `upgrade` (High
## Stakes' upgrade level) applied.
static func ratings(data: Object, upgrade := 0) -> Array:
	var up := Car.upgrade_mults(upgrade)
	var top_kmh: float = data.carp_value(15, 70.0) * 3.6 * up.w
	var t100 := zero_to_100(data, upgrade)
	var accel := inverse_lerp(8.0, 3.0, t100)
	if t100 < 0.0:
		var tq: PackedFloat32Array = data.carp.get(10, PackedFloat32Array([400.0]))
		var peak := 0.0
		for v in tq:
			peak = maxf(peak, v)
		accel = inverse_lerp(0.15, 0.75, peak * up.x / maxf(data.carp_value(2, 1400.0), 600.0))
	# Cornering grip as Car.corner_grip() has it: grip [30] x tyre factor [66], less any
	# understeer [80].
	var corner: float = data.carp_value(30, 3.2) * data.carp_value(66, 1.0) / clampf(data.carp_value(80, 1.0), 1.0, 1.25)
	return [
		inverse_lerp(150.0, 370.0, top_kmh),
		accel,
		inverse_lerp(2.6, 4.0, corner * up.z),
		inverse_lerp(7.0, 12.2, data.carp_value(18, 10.0) * up.y),
	]


## Seconds from 0 to 100 km/h by the original game's own acceleration table (m/s^2 at every
## 1 m/s, carp.txt fields 67..74), or -1 without one.
static func zero_to_100(data: Object, upgrade := 0) -> float:
	var acc := PackedFloat32Array()
	for k in range(67, 75):
		acc.append_array(data.carp.get(k, PackedFloat32Array()))
	if acc.size() < 28:
		return -1.0
	var t := 0.0
	for v in 28:
		t += (27.78 - v if v == 27 else 1.0) / maxf(acc[v], 0.3)
	return t / Car.upgrade_mults(upgrade).x


func set_car(data: Object, kmh: bool, upgrade := 0) -> void:
	var up := Car.upgrade_mults(upgrade)
	var r := ratings(data, upgrade)
	for i in 4:
		_target[i] = clampf(r[i], 0.04, 1.0)
	var top: float = data.carp_value(15, 70.0) * 3.6 * up.w
	_readout[0] = "%d KM/H" % roundi(top) if kmh else "%d MPH" % roundi(top / 1.609)
	var t100 := zero_to_100(data, upgrade)
	if t100 > 0.0:
		_readout[1] = ("0-100  %.1f S" if kmh else "0-62  %.1f S") % t100
	else:
		var tq: PackedFloat32Array = data.carp.get(10, PackedFloat32Array([400.0]))
		var peak := 0.0
		for v in tq:
			peak = maxf(peak, v)
		_readout[1] = "%d NM" % roundi(peak)
	var ratios: PackedFloat32Array = data.carp.get(8, PackedFloat32Array())
	var gears := 0
	for g in range(2, ratios.size()):
		gears += int(ratios[g] > 0.0)
	spec_parts = PackedStringArray()
	var cls := int(data.carp_value(1, -1.0))
	if data.carp.has(1) and cls >= 0 and cls <= 2:
		spec_parts.append("Class %s" % "ABC"[cls])
	spec_parts.append("%d kg" % roundi(data.carp_value(2, 1400.0)))
	if gears > 0:
		spec_parts.append("%d-speed" % gears)
	if data.carp.has(16):
		var fd: float = data.carp_value(16)
		spec_parts.append("FWD" if fd >= 1.0 else ("AWD" if fd > 0.0 else "RWD"))
	spec = "   ·   ".join(spec_parts).to_upper()
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
	var cols := columns
	var gap := Vector2(28, 10 if cols == 2 else 6)
	var cw := (size.x - gap.x * (cols - 1)) / cols
	var rh := (size.y - gap.y * (4 / cols - 1)) / (4 / cols)
	var lf := UiKit.font("cond", 1)
	var vf := UiKit.font("cond", 1, true)
	for i in 4:
		var o := Vector2((i % cols) * (cw + gap.x), (i / cols) * (rh + gap.y))
		var rw := UiKit.text_width("cond", _readout[i], 14, 1, true)
		var name: String = NAMES[i]
		draw_string(lf, o + Vector2(0, 14), name, HORIZONTAL_ALIGNMENT_LEFT, cw - rw - 8,
			UiKit.fit("cond", name, cw - rw - 8, 13, 10, 1), UiKit.INK_DIM)
		draw_string(vf, o + Vector2(0, 14), _readout[i], HORIZONTAL_ALIGNMENT_RIGHT, cw, 14, UiKit.INK)
		var bar := Rect2(o + Vector2(0, 21), Vector2(cw, 5))
		UiKit.box(self, bar, Color(1, 1, 1, 0.1), 2)
		var v: float = _shown[i]
		if v > 0.0:
			UiKit.box(self, Rect2(bar.position, Vector2(bar.size.x * v, bar.size.y)), UiKit.ACCENT.lerp(UiKit.ACCENT_HOT, v * 0.6), 2)
