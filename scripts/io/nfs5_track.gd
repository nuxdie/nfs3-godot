class_name Nfs5Track
extends Nfs3Track
## A Need for Speed: Porsche Unleashed track: GameData/Track/<name>.crp (geometry and the
## virtual road, see Crp) with <name>.fsh (its textures). Game.track_dir() gives the .crp's
## path. The geometry isn't cut into NFS3's blocks of quads with per-texture UVs but is
## articles of triangles with their own UVs and baked colours per corner, so it's kept
## as such (in `chunks`, drawn by Nfs5TrackBuilder); the virtual road and the images fill
## the usual Nfs3Track fields for the race, the AI and the menus.
##
## The virtual road ("SimD", 80 bytes a slice: position, up, forward and right vectors,
## the lanes each side, the distance to the road's left and right edges and each side's
## lane width) is the road network: "SimT" gives each of its segments' slice counts. The
## segments of a lap follow on end to start across the junctions between them. The Monte
## Carlo circuits and the skid pad close into a loop; the others are point-to-point runs
## whose start and finish lines are the triggers of <name>_fstart.scn (and _bstart.scn for
## the other way), type 2 the start and 1 the finish.

const SIMD_SIZE := 80
## Slices per chunk: the articles are named for the slice their chunk starts at, in steps
## of 8 ("CNK0016L", "RD1136C").
const SLICES_PER_CHUNK := 8
## An article's base flags: ground the car can be on (the "secondary" terrain: verges,
## fields, cliffs); with ROAD also, the road itself ("primary"). 0x8000 marks the objects a
## car knocks over (cones, crates, signs), 0x2000 the far scenery (mountains, the sea).
const BASE_GROUND := 0x10
const BASE_ROAD := 0x10000
## The knock-over objects' library: their meshes sit at the origin, for the game to place.
const BASE_SMACKABLE := 0x8000
## How far (m, beyond its own size) an article may be from the slice its name gives.
const NAMED_REACH := 150.0
## Ends of consecutive segments of a lap are this close (m) across a junction.
const JUNCTION_REACH := 25.0
## Slices kept before the start and past the finish of a point-to-point run: the grid
## lines up behind the start, and the cars run out past the finish.
const RUN_OFF := 45
## Scenery further than this (m) from its chunk's slices, or bigger, is drawn from any
## distance: the mountains and valleys on the horizon.
const BACKDROP_REACH := 350.0
## _fit_vroad: how far (m) from the first slice its road may be, how far from where the
## last slice's was (by its own height) the next's, the least offset worth moving a slice
## for, how level (normal's y) a surface to follow, and its lookup grid's cell size.
const FIT_REACH := 7.0
const FIT_TRACK := 1.5
const FIT_MIN := 0.25
const FIT_LEVEL := 0.7
const FIT_SPAN := 2
const FIT_CELL := 4.0
## _open_walls: how far (m) past the lanes a wall may go, the step it goes out by, and the
## rise and drop the ground may take at a step and still carry on, how far above and below
## the slice it may go (the walls reach 6 m over it and 3 m under); over how many
## slices each way a wall goes by the nearest.
const EDGE_REACH := 40.0
const EDGE_STEP := 1.0
const EDGE_RISE := 1.0
const EDGE_DROP := 1.0
const EDGE_UP := 4.0
const EDGE_DOWN := 2.5
const EDGE_SPAN := 2
## _open_walls: how far along the road (m) a slice is another stretch of it (the far side of
## a hairpin, a road doubling back), which a wall stops halfway to; how far along and
## above or below its slice a point is beside it; the share of a bend's radius a wall
## on its inside may reach, and over how many slices each way the bend is measured.
const EDGE_OTHER := 40.0
const EDGE_BESIDE := 4.0
const EDGE_BEND := 0.8
const EDGE_BEND_SPAN := 3

enum Kind { ROAD, GROUND, SCENERY }


## Triangles of one kind: three corners each, and a texture (images index) per triangle.
class Piece:
	var kind := 0
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var colour := PackedColorArray()
	var tex := PackedInt32Array()


## Per chunk: {center, pieces: [Piece ROAD, Piece GROUND, Piece SCENERY]}.
var chunks: Array[Dictionary] = []
## Scenery on the horizon (see BACKDROP_REACH), one Piece per kind.
var backdrop: Array = []
## Whether the virtual road closes into a lap; if not, the start and finish nodes of each
## way round: [forward start, forward finish, backward start, backward finish].
var closed := true
var sprint := PackedInt32Array()
## Its camera animations ("CmAn": camera00..04), the fly-bys round the car before the start.
var flybys: Array[CanFile] = []
## The rest of the road network the lap meets (shortcuts, side streets, the other ways at
## a junction): per segment its slices (Array of VRoad), for the walls to leave them open
## and fence them in themselves.
var side_roads: Array = []
## Where the lap's walls stand, [left, right] per slice (TrackPath.wall_left/wall_right):
## past the verges, where the slices' own wall distances are their lanes' edges.
var fences: Array[PackedFloat32Array] = []
var _spare: Array[Vector2i] = []   # the segments the lap doesn't take: first, last slice


static func is_track_file(path: String) -> bool:
	return path.get_extension().to_lower() == "crp" and FileAccess.file_exists(path)


static func load_file(path: String, _night := false) -> Nfs5Track:
	var t := Nfs5Track.new()
	t.name = "pu_" + path.get_file().get_basename().to_lower()
	t.vroad_walls = true
	var crp := Crp.load_file(path)
	if crp.error != "":
		t.error = crp.error
		return t
	if not crp.track:
		t.error = "not a track"
		return t
	var fsh := Fsh.load_file(path.get_basename() + ".fsh")
	if fsh == null:
		t.error = "missing texture archive"
		return t
	t.images = fsh.images
	_solid_water(fsh)
	var simd := _read_simd(crp)
	if simd.is_empty():
		t.error = "no virtual road"
		return t
	var order := t._route(crp, simd)
	t._add_vroad(simd, order)
	t._add_side_roads(simd)
	t._read_geometry(crp, fsh, simd)
	var grid := t._level_grid()
	t._fit_vroad(grid, t.vroad, t.closed)
	t.fences = t._open_walls(grid, t.vroad, t.closed)
	# Nothing keeps to a side road's lanes: its walls go straight out to the fences.
	for road: Array in t.side_roads:
		t._fit_vroad(grid, road, false)
		var fence := t._open_walls(grid, road, false)
		for k in road.size():
			road[k].left_wall = fence[0][k]
			road[k].right_wall = fence[1][k]
	t._read_flybys(crp)
	return t


## "CmAn": a name (12 bytes), then floats, a key step (s) at 36 and the key count at 40,
## then 52-byte keys from 44: a rotation (4 floats), the camera's position about the car
## (3; the game's car space, front towards -Z) and 6 more. Only the positions are used:
## the race's fly-by looks at the car.
func _read_flybys(crp: Crp) -> void:
	var d := crp.data
	for e in crp.misc_of("CmAn"):
		var n := d.decode_s32(e.offset + 40)
		if n < 2 or 44 + n * 52 > e.length:
			continue
		var c := CanFile.new()
		for k in n:
			var p := e.offset + 44 + k * 52 + 16
			c.keys.append({"pos": Vector3(d.decode_float(p), d.decode_float(p + 4), -d.decode_float(p + 8)),
				"rot": Quaternion.IDENTITY})
		flybys.append(c)


## The virtual road's slices, in file order: {pos, up, fwd, right, lanes_l, lanes_r,
## left, right_w, lane_l, lane_r} in Godot space.
static func _read_simd(crp: Crp) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var e: Crp.Entry = null
	for m in crp.misc_of("SimD"):
		e = m
	if e == null:
		return out
	var d := crp.data
	for i in e.count:
		var p := e.offset + i * SIMD_SIZE
		if p + SIMD_SIZE > d.size():
			break
		out.append({
			"pos": _v(d, p + 4), "up": _v(d, p + 16), "fwd": _v(d, p + 28), "right": _v(d, p + 40),
			"lanes_l": d.decode_u32(p + 56), "lanes_r": d.decode_u32(p + 60),
			"left": d.decode_float(p + 64), "right_w": d.decode_float(p + 68),
			"lane_l": d.decode_float(p + 72), "lane_r": d.decode_float(p + 76),
		})
	return out


static func _v(d: PackedByteArray, p: int) -> Vector3:
	return Vector3(-d.decode_float(p), d.decode_float(p + 4), d.decode_float(p + 8))


## The slices of the lap in order: segment 0, then at each segment's end the segment
## starting nearest it (within JUNCTION_REACH), until the lap is back at segment 0 or the
## road ends. A point-to-point run is cut to its start and finish lines (either way round)
## and RUN_OFF slices beyond them; `sprint` gets those lines.
func _route(crp: Crp, simd: Array[Dictionary]) -> PackedInt32Array:
	var segs: Array[Vector2i] = []   # first, last slice
	var simt: Array[Crp.Entry] = crp.misc_of("SimT")
	var at := 0
	if not simt.is_empty():
		for k in simt[0].count:
			var n := crp.data.decode_u32(simt[0].offset + k * 4)
			if n > 0 and at + n <= simd.size():
				segs.append(Vector2i(at, at + n - 1))
				at += n
	if segs.is_empty():
		segs.append(Vector2i(0, simd.size() - 1))
	var used := [0]
	closed = false
	var cur := 0
	while true:
		var end: Vector3 = simd[segs[cur].y].pos
		var best := -1
		var best_d := JUNCTION_REACH
		for j in segs.size():
			if j in used and j != 0:
				continue
			var dd := end.distance_to(simd[segs[j].x].pos)
			if dd < best_d:
				best_d = dd
				best = j
		if best < 0:
			break
		if best == 0:
			closed = true
			break
		used.append(best)
		cur = best
	for j in segs.size():
		if not j in used:
			_spare.append(segs[j])
	var order := PackedInt32Array()
	for s in used:
		for i in range(segs[s].x, segs[s].y + 1):
			order.append(i)
	if closed:
		return order
	# Start and finish lines, each way.
	var base := crp_base(crp)
	var lines := PackedInt32Array()
	for which in ["fstart", "bstart"]:
		var trig := _triggers(base + "_%s.scn" % which)
		var start := -1
		var finish := -1
		for tr: Dictionary in trig:
			var n := _nearest(simd, order, tr.pos)
			if tr.type == 2:
				start = n
			elif tr.type == 1:
				finish = n
		lines.append_array([start, finish])
	if lines[0] < 0 or lines[1] < 0:
		lines = PackedInt32Array([mini(RUN_OFF, order.size() - 1), maxi(order.size() - 1 - RUN_OFF, 0), -1, -1])
	if lines[2] < 0 or lines[3] < 0:
		lines[2] = lines[1]
		lines[3] = lines[0]
	var lo := maxi(mini(mini(lines[0], lines[1]), mini(lines[2], lines[3])) - RUN_OFF, 0)
	var hi := mini(maxi(maxi(lines[0], lines[1]), maxi(lines[2], lines[3])) + RUN_OFF, order.size() - 1)
	for k in 4:
		lines[k] -= lo
	sprint = lines
	return order.slice(lo, hi + 1)


## The path of the .crp without its extension ("…/Track/alps").
static func crp_base(crp: Crp) -> String:
	return crp.path.get_basename()


## The TRIGGER_ELEMENTs of a .scn file: [{type, pos}].
static func _triggers(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f := DataPath.find_ci(path.get_base_dir(), path.get_file())
	if f == "":
		return out
	var lines := FileAccess.get_file_as_string(f).split("\n")
	for i in lines.size():
		if not lines[i].begins_with("TRIGGER_ELEMENT") or i + 3 >= lines.size():
			continue
		var p := lines[i + 1].split_floats(" ", false)
		var params := lines[i + 3].split_floats(" ", false)
		if p.size() >= 3 and params.size() >= 1:
			out.append({"type": int(params[0]), "pos": Vector3(-p[0], p[1], p[2])})
	return out


static func _nearest(simd: Array[Dictionary], order: PackedInt32Array, p: Vector3) -> int:
	var best := 0
	var best_d := INF
	for k in order.size():
		var dd: float = simd[order[k]].pos.distance_squared_to(p)
		if dd < best_d:
			best_d = dd
			best = k
	return best


func _add_vroad(simd: Array[Dictionary], order: PackedInt32Array) -> void:
	for i in order:
		vroad.append(_slice(simd[i]))


static func _slice(s: Dictionary) -> Nfs3Track.VRoad:
	var vr := Nfs3Track.VRoad.new()
	vr.pos = s.pos
	vr.normal = s.up
	vr.forward = s.fwd
	vr.right = s.right
	vr.left_wall = s.left
	vr.right_wall = s.right_w
	vr.lanes_left = clampi(s.lanes_l, 0, 8)
	vr.lanes_right = clampi(s.lanes_r, 0, 8)
	vr.lane_w_left = s.lane_l
	vr.lane_w_right = s.lane_r
	return vr


## The segments the lap doesn't take that meet it, or meet one that does, an end within
## JUNCTION_REACH of it: they're side_roads.
func _add_side_roads(simd: Array[Dictionary]) -> void:
	var near: Array[Vector3] = []   # the slices of the lap and of the side roads kept so far
	for vr in vroad:
		near.append(vr.pos)
	var left := _spare.duplicate()
	var grew := true
	while grew:
		grew = false
		for seg: Vector2i in left.duplicate():
			var ends := [simd[seg.x].pos, simd[seg.y].pos]
			var meets := false
			for q in near:
				if q.distance_to(ends[0]) < JUNCTION_REACH or q.distance_to(ends[1]) < JUNCTION_REACH:
					meets = true
					break
			if not meets:
				continue
			var road := []
			for i in range(seg.x, seg.y + 1):
				road.append(_slice(simd[i]))
				near.append(simd[i].pos)
			side_roads.append(road)
			left.erase(seg)
			grew = true


## Every article's triangles at full detail (level 0), sorted into its chunk by the slice
## its name starts with ("CNK0016L", "RD1136C", "OBJ0480R") where that's near it, or else
## the nearest slice.
## Corners are turned to wind the same way once X is mirrored.
func _read_geometry(crp: Crp, fsh: Fsh, simd: Array[Dictionary]) -> void:
	var layer := {}   # fsh entry name -> images index
	for i in fsh.names.size():
		layer[fsh.names[i]] = i
	var tex_of := {}  # material -> images index (-1: none)
	for e in crp.misc_of("mt"):
		tex_of[e.index] = layer.get(crp.data.slice(e.offset + 40, e.offset + 44).get_string_from_ascii(), -1) \
			if e.length >= 44 else -1
	var n_chunks := (simd.size() + SLICES_PER_CHUNK - 1) / SLICES_PER_CHUNK
	for c in n_chunks:
		var pieces := []
		for k in 3:
			var pc := Piece.new()
			pc.kind = k
			pieces.append(pc)
		var mid: int = mini(c * SLICES_PER_CHUNK + SLICES_PER_CHUNK / 2, simd.size() - 1)
		chunks.append({"center": simd[mid].pos, "pieces": pieces})
	for k in 3:
		var pc := Piece.new()
		pc.kind = k
		backdrop.append(pc)
	# The road's textures: a ground article's parts in them are road too. The set pieces
	# (tunnel mouths, junctions, ramps, "…_SECONDARY") carry their stretch of road so.
	var road_tex := {}
	for art in crp.articles:
		var base := crp.sub(art, "Base")
		if base == null or crp.data.decode_u32(base.offset) & (BASE_ROAD | BASE_SMACKABLE) != BASE_ROAD:
			continue
		for k in 256:
			var pe := crp.sub(art, "pr", k)
			if pe == null:
				break
			road_tex[tex_of.get(crp.data.decode_s16(pe.offset + 4), -1)] = true
	road_tex.erase(-1)
	var numbered := RegEx.create_from_string("^[A-Z]+?(\\d{4})")
	for art in crp.articles:
		var base := crp.sub(art, "Base")
		var vt := crp.sub(art, "vt")
		if base == null or vt == null:
			continue
		var flags := crp.data.decode_u32(base.offset)
		if flags & BASE_SMACKABLE:
			continue
		var kind := Kind.SCENERY
		if flags & BASE_GROUND:
			kind = Kind.ROAD if flags & BASE_ROAD else Kind.GROUND
		var verts := crp.vec3s(vt)
		var uvs := crp.uvs(crp.sub(art, "uv"))
		var cols := crp.colours(crp.sub(art, "df"))
		var box := AABB(verts[0], Vector3.ZERO) if verts.size() > 0 else AABB()
		for v in verts:
			box = box.expand(v)
		# Numbered by the slice their chunk starts at, but not every article of a side road is
		# numbered as the virtual road's slices go: one far from its slice goes by the nearest.
		var m := numbered.search(art.name)
		var slice := int(m.get_string(1)) if m else -1
		if slice < 0 or slice >= simd.size() or simd[slice].pos.distance_to(box.get_center()) > NAMED_REACH + box.size.length() * 0.5:
			slice = _nearest_slice(simd, box.get_center())
		var chunk: int = slice / SLICES_PER_CHUNK
		var reach: float = box.get_center().distance_to(simd[slice].pos) + box.size.length() * 0.5
		var into: Piece = backdrop[kind] if kind != Kind.ROAD and reach > BACKDROP_REACH \
			else chunks[chunk].pieces[kind]
		for k in 256:
			var pe := crp.sub(art, "pr", k)
			if pe == null:
				break
			var p := crp.part(pe)
			var tex: int = tex_of.get(p.material, -1)
			if tex < 0:
				continue
			var dest := into
			if kind == Kind.GROUND and road_tex.has(tex) and into != backdrop[kind]:
				dest = chunks[chunk].pieces[Kind.ROAD]
			var vi: PackedInt32Array = p.vertex
			var ui: PackedInt32Array = p.uv
			var ci: PackedInt32Array = p.colour
			for t3 in range(0, vi.size() - 2, 3):
				if vi[t3] >= verts.size() or vi[t3 + 1] >= verts.size() or vi[t3 + 2] >= verts.size():
					continue
				for c in [0, 2, 1]:
					dest.pos.append(verts[vi[t3 + c]])
					var u: int = ui[t3 + c] if ui.size() > t3 + c else -1
					dest.uv.append(uvs[u] if u >= 0 and u < uvs.size() else Vector2.ZERO)
					var col: int = ci[t3 + c] if ci.size() > t3 + c else -1
					dest.colour.append(cols[col] if col >= 0 and col < cols.size() else Color(0.5, 0.5, 0.5))
				dest.tex.append(tex)


## Puts each virtual road slice down on the road under it. Mostly it is, but through the set
## pieces (junctions, ramps, tunnel mouths, courtyards) the slices run flat or off by metres
## while the road climbs over and dips under them, and the walls, the grid, resets and the
## AI's view of the road all hang off the slices. The surface is followed along the lap:
## each slice expects the road where the last one found it (as far off its own height),
## and takes the top level surface within FIT_TRACK of that at its lane centres. The first,
## and one where that finds nothing (the slices jump from one segment to the next), goes
## by the nearest road within FIT_REACH.
func _fit_vroad(grid: Dictionary, road: Array, loop: bool) -> void:
	var off := NAN
	var offs := PackedFloat32Array()
	for vr: Nfs3Track.VRoad in road:
		var lanes := PackedFloat32Array([0.0])
		if vr.lanes_left > 0:
			lanes.append(-0.5 * vr.lanes_left * vr.lane_w_left)
		if vr.lanes_right > 0:
			lanes.append(0.5 * vr.lanes_right * vr.lane_w_right)
		var found := PackedFloat32Array()
		# Where the slices jump (from one segment to the next) the road is lost from where
		# it was: start again from the nearest road itself.
		for track in [true, false] if not is_nan(off) else [false]:
			var want := off if track else 0.0
			var reach := FIT_TRACK if track else FIT_REACH
			for lat in lanes:
				var p := vr.pos + vr.right * lat
				# Following, the top one within reach (the collision is two-sided: a deck's
				# underside is under it); starting again, the nearest (an overpass is further).
				var best := INF
				for e: Array in grid.get(Vector2i(floori(p.x / FIT_CELL), floori(p.z / FIT_CELL)), []):
					var pc: Piece = e[0]
					var i: int = e[1]
					if not track and pc.kind != Kind.ROAD:
						continue
					var hit = Geometry3D.ray_intersects_triangle(Vector3(p.x, p.y + want + reach, p.z), Vector3.DOWN,
						pc.pos[i], pc.pos[i + 1], pc.pos[i + 2])
					if hit == null or hit.y - p.y < want - reach:
						continue
					var dy: float = hit.y - p.y
					if best == INF or (dy > best if track else absf(dy) < absf(best)):
						best = dy
				if best != INF:
					found.append(best)
			if not found.is_empty():
				break
		if not found.is_empty():
			found.sort()
			off = (found[(found.size() - 1) / 2] + found[found.size() / 2]) * 0.5
		offs.append(0.0 if is_nan(off) else off)
	# A deck of two layers (a ramp's top and its underside) can be picked a slice apart:
	# each slice goes by the middle of its neighbours'.
	var n := road.size()
	for k in n:
		var near := PackedFloat32Array()
		for j in range(k - FIT_SPAN, k + FIT_SPAN + 1):
			if loop or (j >= 0 and j < n):
				near.append(offs[posmod(j, n)])
		near.sort()
		var dy := near[near.size() / 2]
		if absf(dy) > FIT_MIN:
			road[k].pos.y += dy


## The level triangles of the road and the ground (the backdrop's too) by XZ cell
## (FIT_CELL): [piece, first corner index] each, for _fit_vroad and _open_walls.
func _level_grid() -> Dictionary:
	var grid := {}
	# The big stretches of terrain (the backdrop's ground) run up to the verges too.
	for c in chunks + [{"pieces": backdrop}]:
		for pc: Piece in [c.pieces[Kind.ROAD], c.pieces[Kind.GROUND]]:
			for i in range(0, pc.pos.size(), 3):
				var n := (pc.pos[i + 1] - pc.pos[i]).cross(pc.pos[i + 2] - pc.pos[i])
				if absf(n.normalized().y) < FIT_LEVEL:
					continue
				var box := AABB(pc.pos[i], Vector3.ZERO).expand(pc.pos[i + 1]).expand(pc.pos[i + 2])
				for x in range(floori(box.position.x / FIT_CELL), floori(box.end.x / FIT_CELL) + 1):
					for z in range(floori(box.position.z / FIT_CELL), floori(box.end.z / FIT_CELL) + 1):
						grid.get_or_add(Vector2i(x, z), []).append([pc, i])
	return grid


## The top level surface's height at `p` (x, z) between `lo` and `hi`, or NAN.
static func _surface_at(grid: Dictionary, p: Vector3, lo: float, hi: float) -> float:
	var best := NAN
	for e: Array in grid.get(Vector2i(floori(p.x / FIT_CELL), floori(p.z / FIT_CELL)), []):
		var pc: Piece = e[0]
		var i: int = e[1]
		var hit = Geometry3D.ray_intersects_triangle(Vector3(p.x, hi, p.z), Vector3.DOWN,
			pc.pos[i], pc.pos[i + 1], pc.pos[i + 2])
		if hit != null and hit.y >= lo and (is_nan(best) or hit.y > best):
			best = hit.y
	return best


## Where each slice's walls stand, [left, right]: the slices' own wall distances are their
## lanes' outer edges (the road, for the AI and the grid), and walls there would stand on the
## white line, with the verge, the pavement or the hard shoulder behind them. Each goes out over
## the ground beyond, EDGE_STEP at a time while it carries on (up a bank no steeper than
## EDGE_RISE, down one no steeper than EDGE_DROP, and from EDGE_DOWN under the slice's
## plane to EDGE_UP over it, where the wall hangs from), to EDGE_REACH at most, halfway to
## another stretch of the road, and inside a bend short of where its slices' walls cross
## (_bend_reach). A bank too steep to climb stops the car itself, and where the ground
## stops at a wall, a building or a barrier, those are solid. A slice
## goes by the least of its neighbours' (EDGE_SPAN each way), so a gap between two
## buildings doesn't pocket out.
func _open_walls(grid: Dictionary, road: Array, loop: bool) -> Array[PackedFloat32Array]:
	var n := road.size()
	# Along the road (m) to each slice, and its slices by XZ cell, for _nearer_other.
	var arc := PackedFloat32Array()
	arc.resize(n)
	for k in range(1, n):
		arc[k] = arc[k - 1] + road[k].pos.distance_to(road[k - 1].pos)
	var length: float = arc[n - 1] + (road[0].pos.distance_to(road[n - 1].pos) if loop else 0.0)
	var cells := {}
	for k in n:
		cells.get_or_add(_edge_cell(road[k].pos), []).append(k)
	var out := [PackedFloat32Array(), PackedFloat32Array()]
	for k in n:
		var vr: Nfs3Track.VRoad = road[k]
		var reach := _bend_reach(road, k, loop)
		for side in 2:
			var sg := 1.0 if side == 1 else -1.0
			var edge: float = vr.right_wall if side == 1 else vr.left_wall
			var d := edge
			var at := vr.pos + vr.right * d * sg
			# The ground at the lane edge: a banked road can be off the slice's tilt there.
			var h := _surface_at(grid, at, at.y - EDGE_DOWN, at.y + EDGE_DOWN)
			while not is_nan(h) and d < minf(edge + EDGE_REACH, reach[side]):
				at = vr.pos + vr.right * (d + EDGE_STEP) * sg
				var nh := _surface_at(grid, at, h - EDGE_DROP, h + EDGE_RISE)
				# The wall hangs off the slice (Nfs3TrackBuilder.make_walls): no further than
				# it still reaches the ground from.
				if is_nan(nh) or nh - at.y > EDGE_UP or at.y - nh > EDGE_DOWN:
					break
				if _nearer_other(road, cells, arc, length, loop, k, Vector3(at.x, nh, at.z), d + EDGE_STEP):
					break
				h = nh
				d += EDGE_STEP
			out[side].append(d)
	var walls: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
	for side in 2:
		walls[side].resize(n)
		for k in n:
			var least := INF
			for j in range(k - EDGE_SPAN, k + EDGE_SPAN + 1):
				if loop or (j >= 0 and j < n):
					least = minf(least, out[side][posmod(j, n)])
			var road_edge: float = road[k].right_wall if side == 1 else road[k].left_wall
			walls[side][k] = maxf(road_edge, least)
	return walls


static func _edge_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / EDGE_OTHER), floori(p.z / EDGE_OTHER))


## How far [left, right] a wall of slice `k` may go: on the inside of a bend, no further
## than EDGE_BEND of its radius, where the walls of the slices round it would cross.
static func _bend_reach(road: Array, k: int, loop: bool) -> Array:
	var n := road.size()
	var a := k - EDGE_BEND_SPAN
	var b := k + EDGE_BEND_SPAN
	if not loop:
		a = maxi(a, 0)
		b = mini(b, n - 1)
	var fa: Vector3 = road[posmod(a, n)].forward
	var fb: Vector3 = road[posmod(b, n)].forward
	var turn := fa.angle_to(fb)
	var out := [INF, INF]
	if b <= a or turn < 0.01:
		return out
	var span := 0.0
	for j in range(a, b):
		span += road[posmod(j + 1, n)].pos.distance_to(road[posmod(j, n)].pos)
	# Turning towards the right: its inside is the right.
	var inside := 1 if (fb - fa).dot(road[k].right) > 0.0 else 0
	out[inside] = EDGE_BEND * span / turn
	return out


## Whether `p`, `d` out from slice `k`, is as near to another stretch of the road (a slice
## EDGE_OTHER along it or further) as to its own: beside that slice, and no further across.
static func _nearer_other(road: Array, cells: Dictionary, arc: PackedFloat32Array, length: float,
		loop: bool, k: int, p: Vector3, d: float) -> bool:
	var c := _edge_cell(p)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for j: int in cells.get(c + Vector2i(dx, dz), []):
				var along := absf(arc[j] - arc[k])
				if loop:
					along = minf(along, length - along)
				if along < EDGE_OTHER:
					continue
				var vr: Nfs3Track.VRoad = road[j]
				var o := p - vr.pos
				if absf(o.dot(vr.forward)) <= EDGE_BESIDE and absf(o.y) < EDGE_UP \
						and absf(o.dot(vr.right)) <= d:
					return true
	return false


## The sea's layers ("wtr" textures, alpha 95 at most) are blended over what the game draws
## under them; here nothing is, so they're made opaque: the sea's surface.
static func _solid_water(fsh: Fsh) -> void:
	for i in fsh.names.size():
		if not fsh.names[i].begins_with("wtr"):
			continue
		var im: Image = fsh.images[i]
		im.convert(Image.FORMAT_RGBA8)
		var d := im.get_data()
		var most := 0
		for k in range(3, d.size(), 4):
			most = maxi(most, d[k])
		if most >= 128:
			continue
		for k in range(3, d.size(), 4):
			d[k] = 255
		im.set_data(im.get_width(), im.get_height(), im.has_mipmaps(), Image.FORMAT_RGBA8, d)


static func _nearest_slice(simd: Array[Dictionary], p: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in simd.size():
		var dd: float = simd[i].pos.distance_squared_to(p)
		if dd < best_d:
			best_d = dd
			best = i
	return best


func mirror_world() -> void:
	super.mirror_world()
	for group in [backdrop] + chunks.map(func(c: Dictionary) -> Array: return c.pieces):
		for pc: Piece in group:
			for i in range(0, pc.pos.size(), 3):
				var a := pc.pos[i + 1]
				pc.pos[i + 1] = Vector3(-pc.pos[i + 2].x, pc.pos[i + 2].y, pc.pos[i + 2].z)
				pc.pos[i + 2] = Vector3(-a.x, a.y, a.z)
				pc.pos[i] = Vector3(-pc.pos[i].x, pc.pos[i].y, pc.pos[i].z)
				var uv := pc.uv[i + 1]
				pc.uv[i + 1] = pc.uv[i + 2]
				pc.uv[i + 2] = uv
				var col := pc.colour[i + 1]
				pc.colour[i + 1] = pc.colour[i + 2]
				pc.colour[i + 2] = col
	for c in chunks:
		c.center = Vector3(-c.center.x, c.center.y, c.center.z)
	for road: Array in side_roads:
		for vr: Nfs3Track.VRoad in road:
			mirror_vroad(vr)
	if fences.size() == 2:
		var left := fences[0]
		fences[0] = fences[1]
		fences[1] = left


## The virtual road's slices along the lap (Godot space) for the menu's map.
static func peek_outline(path: String) -> PackedVector3Array:
	var t := Nfs5Track.new()
	var crp := Crp.load_file(path)
	var out := PackedVector3Array()
	if crp.error != "":
		return out
	var simd := _read_simd(crp)
	if simd.is_empty():
		return out
	var order := t._route(crp, simd)
	for k in range(0, order.size(), SLICES_PER_CHUNK):
		out.append(simd[order[k]].pos)
	return out
