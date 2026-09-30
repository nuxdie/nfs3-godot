class_name TrackBrowser
extends BrowserBase
## Every track as a card with its postcard and outline, grouped by game. The backdrop and
## the map beside the panel follow the card with focus.

## High Stakes' versions of the NFS3 tracks, for their own section.
const REMAKES := ["hometown", "redrock", "atlantic", "rockypas", "country", "lostcany", "aquatica", "summit", "empire"]
const GAP := 14.0

var night := false
## (id: String, night: bool) -> Texture2D or null, and (id) -> PackedVector3Array.
var postcard: Callable
var outline: Callable

var _maps := {}               # id -> {pts: PackedVector2Array in 0..1, km: float}
var _precip := {}             # id -> Nfs3Horizon.Precip


func _init() -> void:
	super()
	title = "TRACKS"
	noun = "tracks"
	grid = true
	head_h = 158.0
	total = Game.tracks.size()
	var chips := PackedStringArray(["ALL"])
	var has_hs := Game.tracks.any(func(id: String) -> bool: return Game.is_hs_track(id))
	var has_nfs3 := Game.tracks.any(func(id: String) -> bool: return not Game.is_hs_track(id) and id != Game.PROCEDURAL_TRACK)
	if has_hs and has_nfs3:
		chips.append_array(["NFS III", "HIGH STAKES"])
	filters.set_items(chips, 0)


func hints() -> Array:
	return [["←→", "BROWSE"], ["TAB", "GAME"]] if filters.items.size() > 1 else [["←→", "BROWSE"]]


func section(id: String) -> String:
	if id == Game.PROCEDURAL_TRACK:
		return "GENERATED"
	if not Game.is_hs_track(id):
		return "NEED FOR SPEED III"
	if id.trim_prefix(Game.HS_PREFIX) in REMAKES:
		return "HIGH STAKES · NFS III REMAKES"
	return "HIGH STAKES"


func precip(id: String) -> int:
	if not _precip.has(id):
		var dir := Game.track_dir(id)
		_precip[id] = Nfs3Horizon.peek_precip(dir) if dir != "" else Nfs3Horizon.Precip.RAIN
	return _precip[id]


## The outline scaled into 0..1 (aspect kept) and the lap length.
func map_of(id: String) -> Dictionary:
	if not _maps.has(id):
		var pts: PackedVector3Array = outline.call(id)
		var out := PackedVector2Array()
		var len_m := 0.0
		if pts.size() > 2:
			var lo := Vector2(INF, INF)
			var hi := -lo
			for i in pts.size():
				var p := Vector2(pts[i].x, pts[i].z)
				lo = lo.min(p)
				hi = hi.max(p)
				len_m += pts[i].distance_to(pts[(i + 1) % pts.size()])
			var s := maxf(hi.x - lo.x, hi.y - lo.y)
			for p3 in pts:
				out.append((Vector2(p3.x, p3.z) - lo) / s)
		_maps[id] = {"pts": out, "km": len_m / 1000.0}
	return _maps[id]


func _build_entries() -> Array[Dictionary]:
	var game := filters.items[filters.index]
	var out: Array[Dictionary] = []
	var last := ""
	# Sections in a fixed order, tracks in the game's order within them.
	for sec in ["NEED FOR SPEED III", "HIGH STAKES", "HIGH STAKES · NFS III REMAKES", "GENERATED"]:
		if (game == "NFS III" and sec != "NEED FOR SPEED III") or (game == "HIGH STAKES" and not sec.begins_with("HIGH")):
			continue
		for i in Game.tracks.size():
			var id := Game.tracks[i]
			if section(id) != sec:
				continue
			var hay := "%s %s %s" % [Game.track_name(id), sec, "snow" if precip(id) == Nfs3Horizon.Precip.SNOW else ""]
			if query != "" and not _matches(hay.to_lower()):
				continue
			if sec != last:
				last = sec
				out.append({"item": -1, "text": sec})
			out.append({"item": i, "text": Game.track_name(id)})
	return out


func _columns(w: float) -> int:
	return 4 if w > 1000.0 else 3


func _layout_entries(w: float) -> float:
	var cols := _columns(w)
	var cw := (w - PAD * 2 - 8 - GAP * (cols - 1)) / cols
	var ch := cw * 9.0 / 16.0 + 46.0
	var y := 0.0
	var col := 0
	for e in entries:
		if e.item < 0:
			if col > 0:
				y += ch + GAP
			col = 0
			e.rect = Rect2(0, y, w, 38)
			y += 38 + 6
		else:
			e.rect = Rect2(PAD + col * (cw + GAP), y, cw, ch)
			col += 1
			if col == cols:
				col = 0
				y += ch + GAP
	if col > 0:
		y += ch + GAP
	return y + 8.0


func _draw_entry(ci: CanvasItem, e: Dictionary, r: Rect2, focused: bool, hovered: bool) -> void:
	var id := Game.tracks[e.item]
	var img := Rect2(r.position, Vector2(r.size.x, r.size.x * 9.0 / 16.0))
	var tex: Texture2D = postcard.call(id, night)
	var lit := 1.0 if focused else (0.85 if hovered else 0.6)
	if tex:
		ci.draw_texture_rect(tex, img, false, Color(lit, lit, lit))
	else:
		ci.draw_rect(img, Color(0.08, 0.09, 0.11))
		ci.draw_string(UiKit.font("cond", 2), Vector2(img.position.x, img.get_center().y + 5), "RENDERING…",
			HORIZONTAL_ALIGNMENT_CENTER, img.size.x, 12, UiKit.INK_FAINT)
	# The outline in the corner, over a dark wash.
	var m := map_of(id)
	var pts: PackedVector2Array = m.pts
	if pts.size() > 2:
		var box := Rect2(img.end.x - 70, img.position.y + 8, 62, 44)
		var ext := Vector2.ZERO
		for p in pts:
			ext = ext.max(p)
		var s := minf(box.size.x / maxf(ext.x, 0.01), box.size.y / maxf(ext.y, 0.01))
		var off := box.position + (box.size - ext * s) * 0.5
		var sp := PackedVector2Array()
		for p in pts:
			sp.append(off + p * s)
		sp.append(sp[0])
		ci.draw_polyline(sp, Color(0, 0, 0, 0.55), 4.0, true)
		ci.draw_polyline(sp, UiKit.ACCENT if focused else Color(1, 1, 1, 0.85), 1.6, true)
	if e.item == current:
		var tf := UiKit.font("cond", 2)
		var tw := tf.get_string_size("SELECTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12
		ci.draw_rect(Rect2(img.position + Vector2(8, 8), Vector2(tw, 18)), UiKit.ACCENT)
		ci.draw_string(tf, img.position + Vector2(14, 21), "SELECTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiKit.BG)
	if focused:
		ci.draw_rect(img.grow(1), UiKit.ACCENT, false, 3.0)
	elif hovered:
		ci.draw_rect(img, Color(1, 1, 1, 0.5), false, 1.0)
	# Caption.
	var name := Game.track_name(id).to_upper()
	var nf := UiKit.font("display")
	var fs := 20
	while fs > 14 and nf.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > r.size.x:
		fs -= 1
	ci.draw_string(nf, Vector2(r.position.x, img.end.y + 22), name, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, fs,
		UiKit.ACCENT if focused else UiKit.INK)
	var km: float = m.km
	var sub := ("%.1f KM" % km if Game.units_kmh else "%.1f MI" % (km / 1.609)) if km > 0 else ""
	if precip(id) == Nfs3Horizon.Precip.SNOW:
		sub += "  ·  SNOW"
	ci.draw_string(UiKit.font("cond", 2), Vector2(r.position.x, img.end.y + 40), sub, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 12,
		UiKit.INK_DIM)
