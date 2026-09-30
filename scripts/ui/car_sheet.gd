class_name CarSheet
extends Control
## A car shown the way a magazine would: everything its files say, set as type around the
## showroom's turntable (the menu stands the car in car_rect()).
##   the lockup      the make as a kicker (with its class and game), the model large, and a
##                   line with its status and price new
##   the headlines   power, top speed, 0-100 and weight as big figures: the speed and
##                   acceleration the game's own physics give it (in the player's units, with
##                   its upgrades), the original's claims in small type under them
##   the lineage     the maker's history as a timeline of dated models
##   the sheet       three columns: ENGINE (with the shape of its torque curve), CHASSIS, and
##                   HOW IT DRIVES (the ratings against the other cars)
## Fields a car's files leave empty or "n/a" are left out, never shown blank.

const HEAD_H := 92.0           # the lockup
const FINISH_H := 40.0         # its paint and trim, under the car (when `finish`)
const SHEET_H := 172.0         # the three columns
const LINE_H := 34.0           # the lineage

var car := -1
var upgrade := 0
## Before the kicker: "In your garage", "At the dealer" ("" for none).
var context := ""
## Leave room under the car for its paint and trim (the menu puts them in finish_rect()).
var finish := false

var _ratings := [0.0, 0.0, 0.0, 0.0]   # top speed, acceleration, handling, braking, 0..1 against the others
var _shown := [0.0, 0.0, 0.0, 0.0]     # ...as the bars show them, gliding
var _info := {}
var _heads: Array = []         # [label, value, unit, note]
var _cols: Array = []          # [[heading, [[label, value]]]]
var _history: Array = []       # [[year, model]]
var _torque := PackedFloat32Array()
var _kick := ""
var _title := ""
var _sub := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func show_car(i: int, p_upgrade := 0, p_context := "") -> void:
	car = i
	upgrade = p_upgrade
	context = p_context
	var spec := Game.car_spec(i)
	_ratings = CarStats.ratings(spec, upgrade)
	_info = spec.info if "info" in spec else {}
	_read(spec)
	queue_redraw()


func _process(dt: float) -> void:
	var busy := false
	for k in 4:
		var v := UiKit.damp(_shown[k], clampf(_ratings[k], 0.03, 1.0), 8.0 - k, dt)
		busy = busy or absf(v - _shown[k]) > 0.0005
		_shown[k] = v
	if busy:
		queue_redraw()


## The lockup's kicker, and the headlines on one line ("305 bhp · 233 km/h · 0-100 4.9 s ·
## 1,518 kg"), for where there's only room for a line (the race's car).
func kicker_text() -> String:
	return _kick


func title_text() -> String:
	return _title


func headline() -> String:
	var out := PackedStringArray()
	for h in _heads:
		if h[1] == "":
			continue
		if h[0].begins_with("0-"):
			out.append("%s %s %s" % [h[0].split(" ")[0], h[1], h[2]])
		else:
			out.append(("%s %s" % [h[1], h[2]]).strip_edges())
	return " · ".join(out)


## Where the car should stand: under the lockup, left of the headline figures (local space).
func car_rect() -> Rect2:
	var m := _middle()
	return Rect2(m.position, Vector2(m.size.x - _heads_w() - 12, m.size.y))


## Under the car: where its paint and trim go.
func finish_rect() -> Rect2:
	var m := _middle()
	return Rect2(0, m.end.y, size.x, FINISH_H)


## Between the lockup and what's under the car.
func _middle() -> Rect2:
	var bottom := size.y - SHEET_H - (LINE_H if not _history.is_empty() else 0.0) - (FINISH_H if finish else 0.0)
	return Rect2(0, HEAD_H, size.x, maxf(bottom - HEAD_H, 60.0))


func _heads_w() -> float:
	return minf(190.0, size.x * 0.3)


func _gap() -> float:
	return 30.0


func _col_x(k: int) -> float:
	return k * (_col_w() + _gap())


func _col_w(_k := 0) -> float:
	return (size.x - _gap()) * 0.5


# ------------------------------------------------------------------ reading

func _v(k: String) -> String:
	var v := str(_info.get(k, "")).strip_edges()
	return "" if v.to_lower() in ["n/a", "na", "-", "?"] else v


## The same without its asides ("143 mph (141 auto)" -> "143 mph"), for the short notes.
func _short(k: String) -> String:
	var v := _v(k)
	return v.left(v.find("(")).strip_edges() if v.find("(") > 0 else v


func _read(spec: Object) -> void:
	var game: String = ["Need for Speed III", "High Stakes", "Porsche Unleashed"][Game.car_game(car)]
	var make := _v("make")
	var model := _v("model")
	var name: String = Game.cars[car].name
	# The make over the model ("LAMBORGHINI" / "DIABLO SV"); a name that doesn't start with
	# its make ("1967 911 S Coupé") stays whole.
	_title = model if make != "" and model != "" and name.to_lower().begins_with(make.to_lower()) else name
	var kick := PackedStringArray()
	if context != "":
		kick.append(context)
	if make != "":
		kick.append(make)
	var cls := int(spec.carp_value(1, -1.0)) if "carp" in spec and spec.carp.has(1) else -1
	if Game.is_pursuit_car(car):
		kick.append("Police")
	elif cls >= 0 and cls <= 2:
		kick.append("Class " + "ABC"[cls])
	kick.append(game)
	_kick = "  ·  ".join(kick)
	var sub := PackedStringArray()
	if _v("status") != "":
		sub.append(_v("status").capitalize())
	var price := _v("price").replace(" usd", "").replace(" USD", "")
	if price.trim_prefix("$").is_valid_int():
		price = "$" + _thousands(price.trim_prefix("$").to_int())
	if price != "":
		sub.append(price + " new")
	if upgrade > 0:
		sub.append("with %s upgrades" % Car.UPGRADE_NAMES[upgrade].to_lower())
	_sub = "  ·  ".join(sub)
	# The headlines: the power, then what the game's own physics make of it (in the player's
	# units, with its upgrades), each over a bar against the other cars; the original's
	# claims in small type.
	var up := Car.upgrade_mults(upgrade)
	var top_kmh: float = spec.carp_value(15, 70.0) * 3.6 * up.w
	var t100 := CarStats.zero_to_100(spec, upgrade)
	_heads = []
	var power := _v("power")
	var bhp := power.to_lower().split("bhp")[0].strip_edges() if power.to_lower().contains("bhp") else ""
	if bhp.is_valid_float():
		_heads.append(["Power", bhp, "bhp", power.substr(power.to_lower().find("bhp") + 3).strip_edges(), -1])
	elif power != "":
		_heads.append(["Power", power, "", "", -1])
	_heads.append(["Top speed", "%d" % roundi(top_kmh if Game.units_kmh else top_kmh / 1.609), "km/h" if Game.units_kmh else "mph",
		("claimed " + _short("top_speed")) if _short("top_speed") != "" else "", 0])
	if t100 > 0.0:
		var claim := _short("zero_100") if Game.units_kmh and _v("zero_100") != "" else _short("zero_60")
		_heads.append(["0-100 km/h" if Game.units_kmh else "0-62 mph", "%.1f" % t100, "s",
			("claimed %s %s" % ["0-100" if Game.units_kmh and _v("zero_100") != "" else "0-60", claim.replace(" sec", " s")]) if claim != "" else "", 1])
	elif _v("zero_60") != "":
		# No acceleration table in its files: the maker's own figure, said to be one.
		_heads.append(["0-60 mph", _v("zero_60").replace(" sec", "").replace(" s", "").strip_edges(), "s", "the maker's figure", 1])
	else:
		_heads.append(["Acceleration", "", "", "", 1])
	_heads.append(["Handling", "", "", "cornering grip", 2])
	_heads.append(["Braking", "", "", "", 3])
	# The sheet.
	var drive := ""
	if "carp" in spec and spec.carp.has(16):
		var fd: float = spec.carp_value(16)
		drive = "Front-wheel drive" if fd >= 1.0 else ("All-wheel drive" if fd > 0.0 else "Rear-wheel drive")
	var gears := _v("gearbox")
	var box := " · ".join(_nonempty([_v("transmission").capitalize(), gears]))
	var dims := _nonempty([_v("length"), _v("width"), _v("height")])
	# "4163 × 1610 × 1320 mm": the unit once, at the end.
	if dims.size() > 1:
		var unit := ""
		for u in [" mm", "mm", " in.", " in"]:
			if dims[-1].ends_with(u):
				unit = u
				break
		if unit != "":
			for k in dims.size():
				dims[k] = dims[k].trim_suffix(unit).strip_edges()
			dims[-1] += unit if unit.begins_with(" ") else " " + unit
	var brakes := _v("brakes")
	if _v("brakes_rear") != "" and _v("brakes_rear") != brakes:
		brakes += " / " + _v("brakes_rear")
	var tyres := _v("tyres")
	if _v("tyres_front") != "":
		tyres = _v("tyres_front") + ((" / " + _v("tyres_rear")) if _v("tyres_rear") not in ["", _v("tyres_front")] else "")
	_cols = [
		["Engine", [["Type", _v("engine")], ["Capacity", _v("displacement")], ["Power", power], ["Torque", _v("torque")],
			["Redline", _v("redline")], ["Compression", _v("compression")], ["Torque curve", "~"]]],
		["Chassis", [["Gearbox", box], ["Layout", _v("layout") if _v("layout") != "" else drive],
			["Weight", _weight_text(spec)],
			["Size", " × ".join(dims)], ["Wheelbase", _v("wheelbase")], ["Brakes", brakes], ["Tyres", tyres], ["Rims", _v("rims")]]],
	]
	_torque = spec.carp.get(10, PackedFloat32Array()) if "carp" in spec else PackedFloat32Array()
	for c in _cols:
		c[1] = c[1].filter(func(row: Array) -> bool: return row[1] != "" and (row[1] != "~" or _torque.size() > 2))
	# The lineage: only when its heading is this car's maker (some files carry another's).
	_history = []
	var hist: Array = _info.get("history", [])
	if hist.size() > 1 and (make == "" or str(hist[0]).to_lower().contains(make.to_lower().split(" ")[0])):
		for line in hist.slice(1):
			var parts := str(line).rsplit(" - ", true, 1)
			if parts.size() == 2 and parts[1].strip_edges().is_valid_int():
				_history.append([parts[1].strip_edges(), parts[0].strip_edges()])


## The weight: the game's (in the player's units), with the original's and its split.
func _weight_text(spec: Object) -> String:
	var kg: float = spec.carp_value(2, 1400.0)
	var t := ("%s kg" % _thousands(roundi(kg))) if Game.units_kmh else ("%s lb" % _thousands(roundi(kg * 2.2046)))
	if _v("weight_split") != "":
		t += "  ·  %s front/rear" % _v("weight_split").replace(" / ", "/").replace("%", "")
	return t


static func _nonempty(a: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for x in a:
		if str(x) != "":
			out.append(str(x))
	return out


static func _thousands(n: int) -> String:
	return UiKit.money(n).trim_prefix("$")


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if car < 0:
		return
	var w := size.x
	PickCard.draw_lockup(self, Vector2.ZERO, w, _kick, _title, _sub, 46)
	var m := _middle()
	_draw_heads(Rect2(m.end.x - _heads_w(), m.position.y + 8, _heads_w(), m.size.y - 8))
	if not _history.is_empty():
		_draw_lineage(Rect2(0, size.y - SHEET_H - LINE_H, w, LINE_H - 10))
	var y := size.y - SHEET_H
	for k in _cols.size():
		var x := _col_x(k)
		var cw := _col_w(k)
		UiKit.kicker(self, Vector2(x, y + 14), _cols[k][0], cw)
		draw_line(Vector2(x, y + 22), Vector2(x + cw, y + 22), UiKit.LINE, 1.0)
		_draw_rows(_cols[k][1], Vector2(x, y + 42), cw, k == 0)


## The performance down the side of the car: the label, the figure large with its unit, and
## for what the game rates, a bar against the other cars; the original's claim in small type.
func _draw_heads(r: Rect2) -> void:
	var n := _heads.size()
	if n == 0:
		return
	var step := minf(58.0, r.size.y / n)
	var vf := UiKit.font("display", 0, true)
	var lf := UiKit.font("cond", 1)
	for k in n:
		var h: Array = _heads[k]
		var y := r.position.y + k * step
		var rated: int = h[4]
		draw_string(lf, Vector2(r.position.x, y + 10), h[0].to_upper(), HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 12, UiKit.INK_DIM)
		var base := y + minf(step - 12.0, 36.0)
		if h[1] != "":
			var fs := UiKit.fit("display", h[1], r.size.x - 44, 26 if step >= 50.0 else 22, 16)
			draw_string(vf, Vector2(r.position.x - 1, base), h[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.INK)
			var vw := vf.get_string_size(h[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(lf, Vector2(r.position.x + vw + 4, base), h[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.ACCENT)
			if h[3] != "":
				var nx := r.position.x + vw + 8 + UiKit.text_width("cond", h[2], 13, 1)
				draw_string(UiKit.font("body"), Vector2(nx, base), h[3], HORIZONTAL_ALIGNMENT_LEFT, r.end.x - nx,
					UiKit.fit("body", h[3], r.end.x - nx, 11, 9), UiKit.INK_DIM)
		if rated >= 0:
			# The bar, just under the figure (or where the figure would be).
			var by := base + 6 if h[1] != "" else y + 20
			var bar := Rect2(r.position.x, by, r.size.x, 4)
			draw_rect(bar, Color(1, 1, 1, 0.12))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * _shown[rated], bar.size.y)),
				UiKit.ACCENT.lerp(UiKit.ACCENT_HOT, _shown[rated] * 0.6))
			if h[1] == "" and h[3] != "":
				draw_string(UiKit.font("body"), Vector2(r.position.x, by + 16), h[3], HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 11,
					UiKit.INK_DIM)


func _draw_rows(rows: Array, pos: Vector2, w: float, _curve: bool) -> void:
	var lf := UiKit.font("body")
	var lw := 88.0
	var y := pos.y
	var bottom := size.y + 4.0
	for row in rows:
		if y > bottom:
			break
		var v: String = row[1]
		draw_string(lf, Vector2(pos.x, y), row[0], HORIZONTAL_ALIGNMENT_LEFT, lw - 6, 13, UiKit.INK_DIM)
		if v == "~":
			_draw_torque(Rect2(pos.x + lw, y - 12, minf(w - lw, 110), 14))
			y += 19.0
			continue
		var vw := w - lw
		var fs := UiKit.fit("body", v, vw, 13, 12)
		if lf.get_string_size(v, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > vw and y + 19.0 <= bottom:
			# Too long for one line: two, rather than smaller type or cut off.
			draw_multiline_string(lf, Vector2(pos.x + lw, y), v, HORIZONTAL_ALIGNMENT_LEFT, vw, 12, 2, UiKit.INK)
			y += 34.0
		else:
			draw_string(lf, Vector2(pos.x + lw, y), v, HORIZONTAL_ALIGNMENT_LEFT, vw, fs, UiKit.INK)
			y += 19.0


## The torque curve's shape from idle to the redline, as a line: where the engine pulls.
func _draw_torque(r: Rect2) -> void:
	if _torque.size() < 3:
		return
	var peak := 0.0
	for t in _torque:
		peak = maxf(peak, t)
	var pts := PackedVector2Array()
	for i in _torque.size():
		pts.append(Vector2(r.position.x + r.size.x * i / (_torque.size() - 1.0),
			r.end.y - r.size.y * clampf(_torque[i] / maxf(peak, 1.0), 0.0, 1.0)))
	draw_line(Vector2(r.position.x, r.end.y), r.end, UiKit.LINE, 1.0)
	draw_polyline(pts, UiKit.ACCENT, 1.5, true)


## The maker's models by year on a line, dot by dot, this car's family (the last) lit.
func _draw_lineage(r: Rect2) -> void:
	var n := _history.size()
	var y := r.position.y + 8
	draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), UiKit.LINE, 1.0)
	var step := r.size.x / n
	var yf := UiKit.font("cond", 1, true)
	var f := UiKit.font("body")
	for k in n:
		var x := r.position.x + k * step
		var last := k == n - 1
		draw_circle(Vector2(x + 3, y), 3.5 if last else 2.5, UiKit.ACCENT if last else UiKit.INK_DIM, true, -1.0, true)
		var year: String = _history[k][0]
		var yw := yf.get_string_size(year, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(yf, Vector2(x, y + 20), year, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.ACCENT if last else UiKit.INK)
		var label: String = _history[k][1]
		var lw := step - yw - 12
		draw_string(f, Vector2(x + yw + 4, y + 20), label, HORIZONTAL_ALIGNMENT_LEFT, lw, UiKit.fit("body", label, lw, 12, 9),
			UiKit.INK if last else UiKit.INK_DIM)
