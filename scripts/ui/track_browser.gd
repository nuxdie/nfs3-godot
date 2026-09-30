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
	head_h = 140.0
	total = Game.tracks.size()
	var chips := PackedStringArray(["ALL"])
	var games := PackedStringArray()
	for g in Game.GAME_NAMES.size():
		if Game.tracks.any(func(id: String) -> bool: return id != Game.PROCEDURAL_TRACK and Game.track_game(id) == g):
			games.append(Game.GAME_NAMES[g])
	if games.size() > 1:
		chips.append_array(games)
	filters.set_items(chips, 0)


func hints() -> Array:
	return [["←→", "BROWSE"], ["TAB", "GAME"]] if filters.items.size() > 1 else [["←→", "BROWSE"]]


func section(id: String) -> String:
	if id == Game.PROCEDURAL_TRACK:
		return "GENERATED"
	if Game.is_pu_track(id):
		return "PORSCHE UNLEASHED · POINT TO POINT" if Game.is_sprint(id) else "PORSCHE UNLEASHED · CIRCUITS"
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
				if i + 1 < pts.size() or not Game.is_sprint(id):
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
	for sec in ["NEED FOR SPEED III", "HIGH STAKES", "HIGH STAKES · NFS III REMAKES",
			"PORSCHE UNLEASHED · POINT TO POINT", "PORSCHE UNLEASHED · CIRCUITS", "GENERATED"]:
		if (game == "NFS III" and sec != "NEED FOR SPEED III") or (game == "HIGH STAKES" and not sec.begins_with("HIGH")) \
				or (game == "PORSCHE" and not sec.begins_with("PORSCHE")):
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
	var cw := (w - 14 - GAP * (cols - 1)) / cols
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
			e.rect = Rect2(col * (cw + GAP), y, cw, ch)
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
		UiKit.box(ci, img, Color(0.08, 0.09, 0.11), 4)
		ci.draw_string(UiKit.font("cond", 1), Vector2(img.position.x, img.get_center().y + 5), "RENDERING…",
			HORIZONTAL_ALIGNMENT_CENTER, img.size.x, 13, UiKit.INK_DIM)
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
		var open := Game.is_sprint(id)
		if not open:
			sp.append(sp[0])
		ci.draw_polyline(sp, Color(0, 0, 0, 0.55), 4.0, true)
		ci.draw_polyline(sp, UiKit.ACCENT if focused else Color(1, 1, 1, 0.85), 1.6, true)
		if open:
			UiKit.route_ends(ci, sp[0], sp[1] - sp[0], sp[-1], 0.6)
	if e.item == picked:
		var tf := UiKit.font("cond", 1)
		var tw := tf.get_string_size("IN USE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14
		UiKit.box(ci, Rect2(img.position + Vector2(8, 8), Vector2(tw, 20)), UiKit.ACCENT, 10)
		ci.draw_string(tf, img.position + Vector2(15, 22), "IN USE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.BG)
	if focused:
		UiKit.box(ci, img.grow(2), Color(0, 0, 0, 0), 5, UiKit.ACCENT, 3)
	elif hovered:
		UiKit.box(ci, img.grow(1), Color(0, 0, 0, 0), 4, Color(1, 1, 1, 0.5), 1)
	# Caption.
	var name := Game.track_name(id).to_upper()
	var nf := UiKit.font("display")
	var fs := UiKit.fit("display", name, r.size.x, 19, 14)
	ci.draw_string(nf, Vector2(r.position.x, img.end.y + 22), name, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, fs,
		UiKit.ACCENT if focused else UiKit.INK)
	var km: float = m.km
	var sub := UiKit.dist(km) if km > 0 else ""
	if Game.is_sprint(id):
		sub += "  ·  point to point" if sub != "" else "Point to point"
	if precip(id) == Nfs3Horizon.Precip.SNOW:
		sub += "  ·  snow"
	ci.draw_string(UiKit.font("body"), Vector2(r.position.x, img.end.y + 40), sub, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 13,
		UiKit.INK_DIM)
