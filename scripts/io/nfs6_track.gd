class_name Nfs6Track
extends Nfs5Track
## A Need for Speed: Hot Pursuit 2 track: Tracks/<area>/Level0N, one of the three courses
## through an area (Level00-02; Level03-05 are the same three run backwards, which the
## race's reverse layout covers). Game.track_dir() gives the level folder.
##
## An area is cut into compartments, Tracks/<area>/compNN.o, which a level strings together
## as its drvpath.ini lists them (some are variants of one place: the road open one way or
## the other). A compartment's .o is EAGL geometry (Eagl: a MIPS ELF object) of render
## methods, each a vertex buffer and a triangle strip under an EAGL "microcode", with
## texture references (TARs: "0000"...) into persist.viv's track.fsh; compNN.viv holds its
## collision surface (mesh.sim). Level0N/levelg.o is the level's own scenery (barriers
## closing the roads it doesn't take, its banners) over Level0N/level.fsh, and
## persist.viv's trackg.o the area's (textures in track.fsh too).
##
## The render methods (their microcode names the vertex layout; past position and colour
## come uv sets, in the reverse order of the method's textures):
##   NamedTexture, ScrollTexture, Mirror (24 bytes): a texture.
##   NamedGouraud (16): colour only.
##   ShadowTexture (32): a texture and a shadow layer (trees' shadows, multiplied in).
##   BlendedOverlay (40): two tiling textures, the second over the first by a mask's alpha.
##   BlendedWithShadow (48): the same and a shadow layer.
## The colour is BGRA, the lighting baked in at full range.
##
## The virtual road comes from Level0N/aipaths.dat: nodes, then named paths ("AI_center13")
## of points (28 bytes: position, the road's extent left and right, the racing line in m
## left of the centre, a target speed in m/s); type 1 paths are the course, the others the
## shortcuts and alternatives. They're in the render meshes' space; mesh.sim has Z the other
## way round.

## m between the virtual road's slices (the AI's points are ~16 m apart).
const SLICE_STEP := 5.0
## mesh.sim's lookup grid (m).
const SIM_CELL := 8.0
## m a level render triangle may be off the collision surface and still be the road.
const ROAD_GAP := 0.5
## Render triangles at least this level (normal's y) can be road.
const ROAD_LEVEL := 0.6
## The chunk lookup's cells (m) and the slice buckets' (m).
const CHUNK_CELL := 16.0
const SLICE_BUCKET := 64.0
## AI path ends this close (m) join.
const PATH_JOIN := 2.0
## The racing line's and the speeds' AI path type: the course.
const PATH_MAIN := 1
## levelg.o's prop models are within this (m) of their origin; level.dat's props stand on
## the road within this (m) under their origin.
const PROP_SIZE := 30.0
const PROP_REACH := 3.0
## A compartment's footprint: the cells (m) within this (m) of its collision surface. Its
## coarse terrain mostly outside it, over another's, is left out (_foreign).
const FOOT_CELL := 16.0
const FOOT_REACH := 80.0
const FOREIGN_SHARE := 0.5
## _place_nodes looks this many nodes on for the next; _out_of_place leaves a compartment's
## triangles over the road from OVER_LOW to OVER_HIGH (m), OVER_MARGIN past its edges, where
## the course is NODE_REACH or more nodes from all of its own.
const NODE_LOOKAHEAD := 3
const NODE_REACH := 3
const COARSE_NODE_REACH := 1
## _slices_near's cells and reach (m): the reach takes in the slices either side of the
## widest road (its edges, OVER_MARGIN, a cell's half diagonal).
const NEAR_CELL := 4.0
const NEAR_REACH := 24.0
const OVER_LOW := 0.3
const OVER_HIGH := 30.0
const OVER_MARGIN := 4.0
const COARSE_EDGE := 20.0
## A point-to-point course's start line is this many slices on from the drivable road's
## start (room for the grid behind it), its finish line this many short of its end.
const GRID_ROOM := 10
const FINISH_ROOM := 20
## A stretch off the collision surface within this share of either end is behind its barricade.
const SPRINT_ENDS := 0.15
## m under a slice (from 2 m over it) its collision surface may be: in tunnels it's metres
## under the drawn road and the AI's line.
const SPRINT_REACH := 10.0
## m a triangle may be above or below the course's line (the AI's points) and be its road.
const COURSE_ROAD_GAP := 1.5
const COURSE_ROAD_REACH := 3.0
## Scenery this high (m) over the course's road, this far inside its edges, is in the way
## (_blocks_course).
const BLOCK_LOW := 0.3
const BLOCK_HIGH := 3.5
const BLOCK_MARGIN := 1.5
const BLOCK_CORE := 3.0
## A barricade's faces are steeper than this (normal's y).
const BLOCK_UPRIGHT := 0.7
## Compartments one of whose faces lie this much on the other's surface are variants of one
## place (_variants, from this many of its faces).
const VARIANT_OVERLAP := 0.6
const VARIANT_SAMPLES := 150
## Variants that each carry this many AI points of the course the other doesn't are both kept.
const VARIANT_OWN := 10
## _find_copies: the triangles sampled of a render method, the share of them within COPY_GAP
## (m) of another's for it to be a copy, the cell (m) of its lookup, and how much more of the one
## than the other (share of its triangles) must be in its compartment's own footprint to win.
const COPY_SAMPLES := 48
const COPY_SHARE := 0.6
const COPY_GAP := 1.5
const COPY_CELL := 8.0
const COPY_OWN := 0.2
## A stand-in (_find_copies) has less than STAND_IN_OWN of its triangles in its compartment's
## footprint and COPY_SHARE of them within STAND_IN_GAP (m) of another's (a rough version is
## further off the detailed one than a copy).
const STAND_IN_OWN := 0.5
const STAND_IN_GAP := 3.0
## Lanes are about this wide (m) at most.
const LANE_WIDTH := 4.0
## Microcode -> [vertex stride, uv sets].
const MICROCODES := {
	"NamedTexture": [24, 1], "ScrollTexture": [24, 1], "Mirror": [24, 1], "NamedGouraud": [16, 0],
	"ShadowTexture": [32, 2], "BlendedOverlay": [40, 3], "BlendedWithShadow": [48, 4],
	"TwoShadows": [40, 3],
}


## A Piece with HP2's extra layers: per corner the uvs of the overlay, its mask and the
## shadow, per triangle their images (index + 1; 0 for none).
class LayerPiece extends Nfs5Track.Piece:
	var uv_b := PackedVector2Array()
	var uv_m := PackedVector2Array()
	var uv_s := PackedVector2Array()
	var layers := PackedVector3Array()
	## Per triangle: 1 where its texture is a sphere map of the sky (Nfs6Track._sphere_maps).
	var sphere := PackedByteArray()


## The level's course as the AI points it was resampled from, for peek_outline.
var area := ""
var _chunk_cache := {}
var _buckets := {}
var _sim := {}   # SIM_CELL cell -> PackedVector3Array of triangle corners
var _cutout := PackedByteArray()   # per image: 1 if it has see-through texels
var _sphere := PackedByteArray()   # per image: 1 if a sphere map of the sky (_sphere_maps)
## What the loader left out and why: reason -> count (render methods), for checking.
var stats := {}
var _into: LayerPiece = null   # _add_strip's destination, when not the chunks
var _xform := Transform3D.IDENTITY   # _add_strip's placement of what it reads
## level.dat's props: per type its mesh (round its origin, a Piece of Kind.SCENERY), and the
## props standing on the course, {type, xform} each (Nfs6TrackBuilder knocks them over).
var smackable_kinds: Array[LayerPiece] = []
var smackables: Array[Dictionary] = []
var _skip := {}   # render methods _add_object leaves out (the props' own)
var _comp := -1     # the compartment being read (_out_of_place)
var _near_cache := {}   # NEAR_CELL cell -> slices near it (_slices_near)
var _variant_of := {}   # a variant left out -> the one kept (_pick_variants)
var _comp_nodes := {}   # compartment -> its drvpath.ini nodes (_place_nodes)
var _slice_node := PackedInt32Array()   # per slice, its drvpath.ini node
var _node_count := 0
var _own := {}      # the compartment being read's footprint (_footprint)
var _others := {}   # the other loaded compartments' footprints
## The sky dome (persist.viv's skyg.o, kilometres across round the origin, to be drawn
## round the camera): its triangles, their textures in sky_images (sky.fsh).
var sky := LayerPiece.new()
var sky_images: Array[Image] = []


static func is_track_dir(dir: String) -> bool:
	return dir != "" and DataPath.find_ci(dir, "aipaths.dat") != "" \
		and DataPath.find_ci(dir.get_base_dir(), "persist.viv") != ""


static func load_dir(dir: String, _night := false) -> Nfs6Track:
	var t := Nfs6Track.new()
	var area_dir := dir.get_base_dir()
	t.area = area_dir.get_file().to_lower()
	t.name = "hp2_%s_%s" % [t.area, dir.get_file().to_lower()]
	t.vroad_walls = true
	var persist := Viv.load_file(DataPath.find_ci(area_dir, "persist.viv"))
	if persist == null or not persist.files.has("track.fsh"):
		t.error = "missing persist.viv"
		return t
	var names := {}   # namespace -> {fsh name -> images index}
	names["track"] = t._add_images(Fsh.from_bytes(persist.files["track.fsh"]))
	names["level"] = t._add_images(Fsh.load_file(DataPath.find_ci(dir, "level.fsh")))
	# NamedGouraud has no texture: a white one.
	var white := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	t.images.append(white)
	t.image_names.append("")
	t._cutout.resize(t.images.size())
	for i in t.images.size():
		t._cutout[i] = int(t.images[i].detect_alpha() != Image.ALPHA_NONE)
	t._sphere = _sphere_maps(t.images)
	var route := t._course(DataPath.find_ci(dir, "aipaths.dat"))
	if route.is_empty():
		t.error = "no AI paths"
		return t
	t._add_course(route)
	var comps := _compartments(DataPath.find_ci(dir, "drvpath.ini"))
	var sims := {}   # compartment -> its mesh.sim
	for c in comps:
		var v := Viv.load_file(DataPath.find_ci(area_dir, "comp%02d.viv" % c))
		if v and v.files.has("mesh.sim"):
			sims[c] = v.files["mesh.sim"]
	comps = t._pick_variants(comps, sims, route)
	var feet := {}   # compartment -> its footprint (FOOT_CELL cells round its surface)
	var grids := {}
	for c in comps:
		if sims.has(c):
			grids[c] = _sim_grid(sims[c])
			feet[c] = _footprint(grids[c])
	for c in comps:
		if sims.has(c):
			t._add_sim(sims[c])
	t._make_chunks()
	if not t.closed:
		t._set_sprint()
	t._place_nodes(_drvpath_nodes(DataPath.find_ci(dir, "drvpath.ini")), grids)
	var objs := {}   # compartment -> its .o bytes
	for c in comps:
		var p := DataPath.find_ci(area_dir, "comp%02d.o" % c)
		if p != "":
			objs[c] = FileAccess.get_file_as_bytes(p)
	var copies := t._find_copies(objs, feet)
	for c in comps:
		if objs.has(c):
			# What lies in another's footprint and not its own is its view of the land round
			# it (a kilometre-wide sheet of terrain, the next valley), for when that
			# compartment isn't drawn: here it is, in detail.
			t._own = feet.get(c, {})
			t._others = {}
			for o in feet:
				if o != c:
					t._others.merge(feet[o])
			t._comp = c
			t._skip = copies.get(c, {})
			t._add_object(objs[c], names["track"])
	t._skip = {}
	t._comp = -1
	t._own = {}
	t._others = {}
	if persist.files.has("trackg.o"):
		t._add_object(persist.files["trackg.o"], names["track"])
	var lg := DataPath.find_ci(dir, "levelg.o")
	if lg != "":
		t._add_level(FileAccess.get_file_as_bytes(lg), names["level"], DataPath.find_ci(dir, "level.dat"))
	_sim_free(t)
	if persist.files.has("skyg.o") and persist.files.has("sky.fsh"):
		t._add_sky(persist.files["skyg.o"], Fsh.from_bytes(persist.files["sky.fsh"]))
	var grid := t._level_grid()
	t._fit_vroad(grid, t.vroad, t.closed)
	t._bank(grid)
	t.fences = t._open_walls(grid, t.vroad, t.closed)
	return t


## The sky dome: its textures go in sky_images while it's read (the images' indices are
## then sky_images'), the track's put back after.
func _add_sky(bytes: PackedByteArray, fsh: Fsh) -> void:
	if fsh == null:
		return
	var keep := images
	var keep_cut := _cutout
	var keep_sphere := _sphere
	images = fsh.images.duplicate()
	var white := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	images.append(white)
	_cutout = PackedByteArray()
	_cutout.resize(images.size())
	_sphere = PackedByteArray()
	_sphere.resize(images.size())
	var names := {}
	for i in fsh.names.size():
		names[fsh.names[i]] = i
	_add_object(bytes, names, sky)
	sky_images = images
	images = keep
	_cutout = keep_cut
	_sphere = keep_sphere
	_into = null


static func _sim_free(t: Nfs6Track) -> void:
	t._sim.clear()
	t._near_cache.clear()
	t._chunk_cache.clear()
	t._buckets.clear()


## Per image, 1 for a sphere map of the sky (the Tropics' puddles reflect one): opaque, square,
## its four corners the same sky blue, a picture inside the circle. The files don't mark them;
## the game maps them by the view.
static func _sphere_maps(imgs: Array[Image]) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(imgs.size())
	for i in imgs.size():
		var im: Image = imgs[i]
		if im.get_width() != im.get_height() or im.get_width() < 64 or im.detect_alpha() != Image.ALPHA_NONE:
			continue
		var s := im.duplicate() as Image
		s.resize(32, 32, Image.INTERPOLATE_BILINEAR)
		var cs := [s.get_pixel(1, 1), s.get_pixel(30, 1), s.get_pixel(1, 30), s.get_pixel(30, 30)]
		var spread := 0.0
		for a: Color in cs:
			for b: Color in cs:
				spread = maxf(spread, Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length())
		var c: Color = cs[0]
		var inner := 0.0
		for k in 12:
			var p := s.get_pixelv(Vector2i(16, 16) + Vector2i(Vector2(10, 0).rotated(k * 0.5)))
			inner += Vector3(p.r - c.r, p.g - c.g, p.b - c.b).length() / 12.0
		out[i] = int(spread < 0.1 and inner > 0.16 and c.b > c.r + 0.16)
	return out


func _add_images(fsh: Fsh) -> Dictionary:
	var out := {}
	if fsh == null:
		return out
	for i in fsh.names.size():
		out[fsh.names[i]] = images.size()
		images.append(fsh.images[i])
		image_names.append(fsh.names[i])
	return out


## The compartments drvpath.ini's [nodeN] sections list (compartmentId), each once.
## drvpath.ini's nodes in order: the compartments the course goes through, as it comes to
## them (a place passed twice is listed twice).
static func _drvpath_nodes(path: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	if path == "":
		return out
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var l := line.strip_edges()
		if l.to_lower().begins_with("compartmentid="):
			out.append(int(l.get_slice("=", 1)))
	return out


## The game draws the compartments round the car's node of drvpath.ini, not all of them, so
## those far along the course can stand where it is now (a hill over the road it reaches
## kilometres on). Each slice gets its node: from the node whose compartment is under the
## start line's slice, on to the next of the next few whose compartment is under it. The nodes of
## the variants left out go to the ones kept.
func _place_nodes(nodes: PackedInt32Array, grids: Dictionary) -> void:
	var n := nodes.size()
	_slice_node.resize(vroad.size())
	_slice_node.fill(-1)
	if n == 0:
		return
	for i in n:
		var c := nodes[i]
		while _variant_of.has(c) and _variant_of[c] != c:
			c = _variant_of[c]
		nodes[i] = c
		var list: PackedInt32Array = _comp_nodes.get(c, PackedInt32Array())
		list.append(i)
		_comp_nodes[c] = list
		_node_count = n
	var under := func(k: int, node: int) -> bool:
		var g: Dictionary = grids.get(nodes[posmod(node, n)], {})
		return not g.is_empty() and not is_nan(_sim_height(vroad[k].pos + Vector3.UP * 2.0, SPRINT_REACH, g))
	# From the start line (a point-to-point course's AI paths begin behind its barricade, in
	# the far end's compartment); the slices behind it take the first node.
	var first := sprint[0] if not closed and sprint.size() == 4 else 0
	var cur := 0
	for i in n:
		if under.call(first, i):
			cur = i
			break
	for k in first:
		_slice_node[k] = cur
	for k in range(first, vroad.size()):
		if not under.call(k, cur):
			for j in range(1, NODE_LOOKAHEAD + 1):
				if (closed or cur + j < n) and under.call(k, cur + j):
					cur = posmod(cur + j, n)
					break
		_slice_node[k] = cur


## Whether `p` (a triangle's middle, of compartment _comp) hangs over the course's road
## (OVER_LOW to OVER_HIGH over a slice, within its edges and OVER_MARGIN) where the course is
## at a node NODE_REACH or more from all of _comp's: drawn there only when the car is
## elsewhere.
func _out_of_place(p: Vector3) -> bool:
	if _comp < 0 or _slice_node.is_empty() or not _comp_nodes.has(_comp):
		return false
	var best := -1
	var best_d := INF
	for i in _slices_near(p):
		var dd := Vector2(vroad[i].pos.x - p.x, vroad[i].pos.z - p.z).length_squared()
		if dd < best_d:
			best_d = dd
			best = i
	if best < 0:
		return false
	var vr := vroad[best]
	var off := p - vr.pos
	if absf(off.dot(vr.forward)) > SLICE_STEP or off.y < OVER_LOW or off.y > OVER_HIGH:
		return false
	var lat := off.dot(vr.right)
	if lat < -(vr.left_wall + OVER_MARGIN) or lat > vr.right_wall + OVER_MARGIN:
		return false
	return _far_node(best)


## A coarse triangle (an edge of COARSE_EDGE or more: a sheet of rough terrain) of _comp
## over the course's road (OVER_LOW to OVER_HIGH over a slice inside it, or a little past its
## edges) anywhere but at one of _comp's own nodes (COARSE_NODE_REACH): its middle is far off,
## so _out_of_place doesn't see it, but it cuts through what's there (a tunnel's wall).
func _spans_out_of_place(a: Vector3, b: Vector3, c: Vector3) -> bool:
	if _comp < 0 or _slice_node.is_empty() or not _comp_nodes.has(_comp) \
			or maxf(maxf(a.distance_to(b), b.distance_to(c)), c.distance_to(a)) < COARSE_EDGE:
		return false
	var tri := PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)])
	var lo := Vector2(minf(minf(a.x, b.x), c.x), minf(minf(a.z, b.z), c.z))
	var hi := Vector2(maxf(maxf(a.x, b.x), c.x), maxf(maxf(a.z, b.z), c.z))
	for x in range(floori(lo.x / SLICE_BUCKET), floori(hi.x / SLICE_BUCKET) + 1):
		for z in range(floori(lo.y / SLICE_BUCKET), floori(hi.y / SLICE_BUCKET) + 1):
			for i: int in _buckets.get(Vector2i(x, z), PackedInt32Array()):
				var vr := vroad[i]
				# Across the road and past its edges (a tunnel is wider than the AI's road): a
				# sheet can cut in at the side only.
				for f: float in [-1.6, -1.3, -1.0, -0.5, 0.0, 0.5, 1.0, 1.3, 1.6]:
					var q: Vector3 = vr.pos + vr.right * (f * (vr.right_wall if f > 0.0 else vr.left_wall))
					if not Geometry2D.is_point_in_polygon(Vector2(q.x, q.z), tri):
						continue
					var hit = Geometry3D.ray_intersects_triangle(Vector3(q.x, q.y + OVER_HIGH, q.z), Vector3.DOWN, a, b, c)
					if hit != null and hit.y - q.y >= OVER_LOW and _far_node(i, COARSE_NODE_REACH):
						return true
	return false


## Whether slice `k`'s node is `reach` or more from all of _comp's.
func _far_node(k: int, reach := NODE_REACH) -> bool:
	var here := _slice_node[k]
	if here < 0:
		return false
	for nd: int in _comp_nodes[_comp]:
		var dist := absi(nd - here)
		if closed:
			dist = mini(dist, _node_count - dist)
		if dist < reach:
			return false
	return true


static func _compartments(path: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	if path == "":
		return out
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var l := line.strip_edges()
		if l.to_lower().begins_with("compartmentid="):   # (one is spelt lower case)
			var c := int(l.get_slice("=", 1))
			if not c in out:
				out.append(c)
	return out


## Some compartments are variants of one place (the same ground, other barriers: the road
## open one way or another), and a course that passes a place twice lists both, for the game
## to swap as the car comes round. Drawn together they overlap, one's verges over the other's
## road: of each such pair (most of the smaller one's collision faces, VARIANT_OVERLAP, on
## the other's surface) the one whose surface carries more of the course's AI points
## (`route`) the other's doesn't is kept, the first listed if they tie; both if each carries
## VARIANT_OWN of its own (the barricades of the one across the course's road go:
## _blocks_course).
func _pick_variants(comps: PackedInt32Array, sims: Dictionary, route: PackedFloat32Array) -> PackedInt32Array:
	var grids := {}
	for c in comps:
		if sims.has(c):
			grids[c] = _sim_grid(sims[c])
	var carries := {}   # compartment -> per AI point, 1 where its surface is under it
	var out := PackedInt32Array()
	for c in comps:
		if not grids.has(c):
			out.append(c)
			continue
		var rival := -1
		for k in out.size():
			if grids.has(out[k]) and _variants(sims[c], grids[c], sims[out[k]], grids[out[k]]):
				rival = k
				break
		if rival < 0:
			out.append(c)
			continue
		var r := out[rival]
		for x in [c, r]:
			if not carries.has(x):
				var on := PackedByteArray()
				on.resize(route.size() / 7)
				for k in on.size():
					on[k] = int(not is_nan(_sim_height(_pt(route, k) + Vector3.UP, 3.0, grids[x])))
				carries[x] = on
		var only_c := 0
		var only_r := 0
		for k in carries[c].size():
			only_c += int(carries[c][k] and not carries[r][k])
			only_r += int(carries[r][k] and not carries[c][k])
		# Each carries some of the course the other doesn't: both are needed.
		if only_c >= VARIANT_OWN and only_r >= VARIANT_OWN:
			out.append(c)
		elif only_c > only_r:
			out[rival] = c
			_variant_of[r] = c
		else:
			_variant_of[c] = r
	return out


## Whether two compartments are variants of one place: of the one with fewer faces, at least
## VARIANT_OVERLAP of a sample of its faces' middles on the other's surface.
func _variants(a: PackedByteArray, ga: Dictionary, b: PackedByteArray, gb: Dictionary) -> bool:
	if a.decode_u32(0) > b.decode_u32(0):
		return _variants(b, gb, a, ga)
	var n := mini(a.decode_u32(0), (a.size() - 8) / 64)
	if n == 0:
		return false
	var step := maxi(n / VARIANT_SAMPLES, 1)
	var hits := 0
	var tried := 0
	for i in range(0, n, step):
		var f := a.slice(8 + i * 64, 8 + i * 64 + 36).to_float32_array()
		var mid := Vector3(f[0] + f[3] + f[6], f[1] + f[4] + f[7], -(f[2] + f[5] + f[8])) / 3.0
		tried += 1
		if not is_nan(_sim_height(mid + Vector3.UP * 0.5, 1.5, gb)):
			hits += 1
	return hits >= VARIANT_OVERLAP * tried


## The AI paths: [{name, type, pts: PackedFloat32Array (7 a point)}].
static func _read_ai(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := FileAccess.get_file_as_bytes(path) if path != "" else PackedByteArray()
	if d.size() < 12:
		return out
	var o := 8 + d.decode_u32(4) * 12
	if o + 4 > d.size():
		return out
	var n := d.decode_u32(o)
	o += 4
	for i in n:
		if o + 36 > d.size():
			break
		var name := d.slice(o, o + 20).get_string_from_ascii()
		var type := d.decode_u32(o + 28)
		var count := d.decode_u32(o + 32)
		o += 36
		if o + count * 28 > d.size():
			break
		out.append({"name": name, "type": type, "pts": d.slice(o, o + count * 28).to_float32_array()})
		o += count * 28
	return out


## The course's AI points in order (7 floats each), the main paths followed end to start;
## `closed` says whether they come round to the first. A lap starts at the first main path
## in the file (the start line). A point-to-point course is the longest run of main paths
## from one no other main path leads into (some main paths come off an alternative's end).
func _course(path: String) -> PackedFloat32Array:
	var mains: Array[PackedFloat32Array] = []
	for p in _read_ai(path):
		if p.type == PATH_MAIN and p.pts.size() >= 14:
			mains.append(p.pts)
	if mains.is_empty():
		return PackedFloat32Array()
	var best := _chain(mains, 0)
	closed = best[1]
	if not closed:
		for i in mains.size():
			var s := _pt(mains[i], 0)
			var fed := false
			for j in mains.size():
				if j != i and _pt(mains[j], mains[j].size() / 7 - 1).distance_to(s) < PATH_JOIN:
					fed = true
			if not fed:
				var c := _chain(mains, i)
				if c[0].size() > best[0].size():
					best = c
	return best[0]


## [the points of the main paths from `first` on, end to start; whether they come back
## round to it (then without the last point, which is the first)].
static func _chain(mains: Array[PackedFloat32Array], first: int) -> Array:
	var out := mains[first].duplicate()
	var used := [first]
	var cur := first
	var loop := false
	while true:
		var end := _pt(mains[cur], mains[cur].size() / 7 - 1)
		var next := -1
		for j in mains.size():
			if (j not in used or j == first) and _pt(mains[j], 0).distance_to(end) < PATH_JOIN:
				next = j
				if j != first:
					break
		if next < 0:
			break
		if next == first:
			loop = true
			break
		used.append(next)
		out.append_array(mains[next].slice(7))   # its first point is the last one's end
		cur = next
	if loop:
		out = out.slice(0, out.size() - 7)
	return [out, loop]


static func _pt(pts: PackedFloat32Array, k: int) -> Vector3:
	return Vector3(pts[k * 7], pts[k * 7 + 1], pts[k * 7 + 2])


## The virtual road: the course resampled every SLICE_STEP m (Catmull-Rom through the
## points), the AI's speeds and racing line with it.
func _add_course(pts: PackedFloat32Array) -> void:
	var n := pts.size() / 7
	var arc := PackedFloat32Array([0.0])
	for k in range(1, n + (1 if closed else 0)):
		arc.append(arc[k - 1] + _pt(pts, k % n).distance_to(_pt(pts, k - 1)))
	var length := arc[arc.size() - 1]
	var count := maxi(int(length / SLICE_STEP), 4)
	var step := length / count
	var seg := 0
	var speeds := PackedFloat32Array()
	var line := PackedFloat32Array()
	var slices: Array[Dictionary] = []
	for i in count + (0 if closed else 1):
		var s := minf(i * step, length)
		while seg < arc.size() - 2 and arc[seg + 1] < s:
			seg += 1
		var span := maxf(arc[seg + 1] - arc[seg], 0.001)
		var f := clampf((s - arc[seg]) / span, 0.0, 1.0)
		var a := seg
		var b := (seg + 1) % n
		var a0 := (a - 1 + n) % n if closed or a > 0 else a
		var b1 := (b + 1) % n if closed or b + 1 < n else b
		var pos := _pt(pts, a).cubic_interpolate(_pt(pts, b), _pt(pts, a0), _pt(pts, b1), f)
		var at := func(k: int) -> float: return lerpf(pts[a * 7 + k], pts[b * 7 + k], f)
		slices.append({"pos": pos, "left": absf(at.call(3)), "right_w": absf(at.call(4))})
		line.append(-at.call(5))
		speeds.append(at.call(6))
	var m := slices.size()
	for i in m:
		var prev: Vector3 = slices[(i - 1 + m) % m if closed else maxi(i - 1, 0)].pos
		var next: Vector3 = slices[(i + 1) % m if closed else mini(i + 1, m - 1)].pos
		var fwd := (next - prev).normalized()
		var right := fwd.cross(Vector3.UP).normalized()
		var s := slices[i]
		var vr := Nfs3Track.VRoad.new()
		vr.pos = s.pos
		vr.forward = fwd
		vr.right = right
		vr.normal = right.cross(fwd).normalized()
		vr.left_wall = s.left
		vr.right_wall = s.right_w
		vr.lanes_left = clampi(ceili(s.left / LANE_WIDTH - 0.25), 1, 4)
		vr.lanes_right = clampi(ceili(s.right_w / LANE_WIDTH - 0.25), 1, 4)
		vr.lane_w_left = s.left / vr.lanes_left
		vr.lane_w_right = s.right_w / vr.lanes_right
		vroad.append(vr)
	ai_speeds = [speeds, speeds.duplicate()]
	racing_line = [line, PackedFloat32Array()]


## A point-to-point course's start and finish lines, each way: its AI paths run on past
## the ends of the drivable road, through the barricades closing it (where there's no
## collision surface) to the stretch behind (where the other way's run ends). The grid lines
## up from the first slice past the longest such gap near the start (GRID_ROOM slices on),
## the finish line FINISH_ROOM short of the longest near the end.
func _set_sprint() -> void:
	var n := vroad.size()
	var gaps: Array[Vector2i] = []   # first, last slice of each stretch off the surface
	var from := -1
	for i in n:
		var on := not is_nan(_sim_height(vroad[i].pos + Vector3.UP * 2.0, SPRINT_REACH))
		if not on and from < 0:
			from = i
		elif on and from >= 0:
			gaps.append(Vector2i(from, i - 1))
			from = -1
	if from >= 0:
		gaps.append(Vector2i(from, n - 1))
	# The longest gap near each end (other short ones are bridges' joints, a tunnel's mouth).
	var first := 0
	var last := n - 1
	var at_start := -1
	var at_end := -1
	for g in gaps:
		if g.y < n * SPRINT_ENDS and g.y - g.x >= at_start:
			at_start = g.y - g.x
			first = g.y + 1
		elif g.x > n * (1.0 - SPRINT_ENDS) and g.y - g.x > at_end:
			at_end = g.y - g.x
			last = g.x - 1
	sprint = PackedInt32Array([first + GRID_ROOM, last - FINISH_ROOM, last - GRID_ROOM, first + FINISH_ROOM])


## Leans each slice to the road's cross-fall, from the surface either side of it.
func _bank(grid: Dictionary) -> void:
	for vr in vroad:
		var flat := vr.right
		var hl := _surface_at(grid, vr.pos - flat * 3.0, vr.pos.y - 2.0, vr.pos.y + 2.0)
		var hr := _surface_at(grid, vr.pos + flat * 3.0, vr.pos.y - 2.0, vr.pos.y + 2.0)
		if is_nan(hl) or is_nan(hr):
			continue
		vr.right = (flat * 6.0 + Vector3.UP * (hr - hl)).normalized()
		vr.normal = vr.right.cross(vr.forward).normalized()


## mesh.sim: a count, a word, then 64 bytes a face: four corners (the fourth repeating the
## third on a triangle), a packed normal, then its surface. Z the other way round.
func _add_sim(d: PackedByteArray) -> void:
	var g := _sim_grid(d)
	for key in g:
		var cell: PackedVector3Array = _sim.get(key, PackedVector3Array())
		cell.append_array(g[key])
		_sim[key] = cell


static func _sim_grid(d: PackedByteArray) -> Dictionary:
	var grid := {}
	if d.size() < 8:
		return grid
	var n := d.decode_u32(0)
	for i in n:
		var o := 8 + i * 64
		if o + 64 > d.size():
			break
		var f := d.slice(o, o + 48).to_float32_array()
		var c: Array[Vector3] = []
		for k in 4:
			c.append(Vector3(f[k * 3], f[k * 3 + 1], -f[k * 3 + 2]))
		var tris := [[c[0], c[1], c[2]]]
		if not c[3].is_equal_approx(c[2]):
			tris.append([c[0], c[2], c[3]])
		for tri: Array in tris:
			var lo := Vector2(minf(minf(tri[0].x, tri[1].x), tri[2].x), minf(minf(tri[0].z, tri[1].z), tri[2].z))
			var hi := Vector2(maxf(maxf(tri[0].x, tri[1].x), tri[2].x), maxf(maxf(tri[0].z, tri[1].z), tri[2].z))
			for x in range(floori(lo.x / SIM_CELL), floori(hi.x / SIM_CELL) + 1):
				for z in range(floori(lo.y / SIM_CELL), floori(hi.y / SIM_CELL) + 1):
					var cell: PackedVector3Array = grid.get(Vector2i(x, z), PackedVector3Array())
					cell.append_array(PackedVector3Array(tri))
					grid[Vector2i(x, z)] = cell
	return grid


## Whether `p` is on the collision surface (within ROAD_GAP of it).
func _on_sim(p: Vector3) -> bool:
	var cell: PackedVector3Array = _sim.get(Vector2i(floori(p.x / SIM_CELL), floori(p.z / SIM_CELL)), PackedVector3Array())
	for i in range(0, cell.size(), 3):
		var hit = Geometry3D.ray_intersects_triangle(Vector3(p.x, p.y + ROAD_GAP, p.z), Vector3.DOWN,
			cell[i], cell[i + 1], cell[i + 2])
		if hit != null and hit.y >= p.y - ROAD_GAP:
			return true
	return false


## Whether a render method (its corners, its strip) stands across the course's road: a
## triangle of it BLOCK_LOW to BLOCK_HIGH over the collision surface within BLOCK_CORE of the
## course's middle. That's a barricade of the compartment variant that closes the road the
## other time round (_pick_variants keeps one), which the course runs through; all of it goes.
## (The roadside, palms and posts, is further out: the AI's road edges take in the verges.)
func _blocks_course(pos: PackedVector3Array, idx: PackedInt32Array) -> bool:
	for k in idx.size() - 2:
		var a := idx[k]
		var b := idx[k + 1]
		var c := idx[k + 2]
		if a == b or b == c or a == c or a >= pos.size() or b >= pos.size() or c >= pos.size():
			continue
		# Its upright faces: a deck or a strip of road lying flat over a lower surface isn't one.
		if absf((pos[b] - pos[a]).cross(pos[c] - pos[a]).normalized().y) > BLOCK_UPRIGHT:
			continue
		var p := (pos[a] + pos[b] + pos[c]) / 3.0
		var h := _sim_height(p + Vector3.UP * BLOCK_HIGH, BLOCK_HIGH + 1.0)
		if is_nan(h) or p.y - h < BLOCK_LOW or p.y - h > BLOCK_HIGH:
			continue
		var s := _course_slice(p)
		if s >= 0 and absf((p - vroad[s].pos).dot(vroad[s].right)) < BLOCK_CORE:
			return true
	return false


## Whether a triangle (its middle, its normal) is part of the course's road, for
## _find_copies to leave be: level, within its edges, within COURSE_ROAD_REACH of its line.
func _carries_road(mid: Vector3, nrm: Vector3) -> bool:
	if absf(nrm.y) < ROAD_LEVEL:
		return false
	for i in _slices_near(mid):
		var vr := vroad[i]
		var off := mid - vr.pos
		if absf(off.dot(vr.forward)) <= SLICE_STEP and absf(off.y) < COURSE_ROAD_REACH:
			var lat := off.dot(vr.right)
			if lat > -vr.left_wall and lat < vr.right_wall:
				return true
	return false


## Whether a triangle (its middle, its normal) lies flat on the course's road.
func _on_course_road(mid: Vector3, nrm: Vector3) -> bool:
	if absf(nrm.y) < ROAD_LEVEL:
		return false
	var k := _course_slice(mid)
	return k >= 0 and absf(mid.y - vroad[k].pos.y) < COURSE_ROAD_GAP


## The slices within NEAR_REACH (m, on the ground plane) of `p`'s NEAR_CELL cell, cached: the
## candidates for the nearest (most cells have none).
func _slices_near(p: Vector3) -> PackedInt32Array:
	var key := Vector2i(floori(p.x / NEAR_CELL), floori(p.z / NEAR_CELL))
	if _near_cache.has(key):
		return _near_cache[key]
	var c := Vector2((key.x + 0.5) * NEAR_CELL, (key.y + 0.5) * NEAR_CELL)
	var out := PackedInt32Array()
	var bx := floori(c.x / SLICE_BUCKET)
	var bz := floori(c.y / SLICE_BUCKET)
	for x in range(bx - 1, bx + 2):
		for z in range(bz - 1, bz + 2):
			for i: int in _buckets.get(Vector2i(x, z), PackedInt32Array()):
				if Vector2(vroad[i].pos.x, vroad[i].pos.z).distance_to(c) < NEAR_REACH:
					out.append(i)
	_near_cache[key] = out
	return out


## The course slice `p` is on, within its lanes (BLOCK_MARGIN inside its road edges), or -1.
func _course_slice(p: Vector3) -> int:
	var best := -1
	var best_d := INF
	for i in _slices_near(p):
		var dd := vroad[i].pos.distance_squared_to(p)
		if dd < best_d:
			best_d = dd
			best = i
	if best < 0:
		return -1
	var vr := vroad[best]
	var off := p - vr.pos
	if absf(off.dot(vr.forward)) > SLICE_STEP or absf(off.y) > BLOCK_HIGH + 2.0:
		return -1
	var lat := off.dot(vr.right)
	return best if lat > -(vr.left_wall - BLOCK_MARGIN) and lat < vr.right_wall - BLOCK_MARGIN else -1


## Whether a render method (its corners, its strip) is the compartment's rough view of the land
## round it: most of its area (FOREIGN_SHARE) over another loaded compartment's footprint and
## not its own, in coarse triangles (their median edge at least COARSE_EDGE): a kilometre-wide
## sheet of terrain. Buildings and rocks standing there, finer, stay.
func _foreign(pos: PackedVector3Array, idx: PackedInt32Array) -> bool:
	var total := 0.0
	var foreign := 0.0
	var edges := PackedFloat32Array()
	for k in idx.size() - 2:
		var a := idx[k]
		var b := idx[k + 1]
		var c := idx[k + 2]
		if a == b or b == c or a == c or a >= pos.size() or b >= pos.size() or c >= pos.size():
			continue
		var area := (pos[b] - pos[a]).cross(pos[c] - pos[a]).length() * 0.5
		var mid := (pos[a] + pos[b] + pos[c]) / 3.0
		var cell := Vector2i(floori(mid.x / FOOT_CELL), floori(mid.z / FOOT_CELL))
		total += area
		if _others.has(cell) and not _own.has(cell):
			foreign += area
		edges.append(maxf(maxf(pos[a].distance_to(pos[b]), pos[b].distance_to(pos[c])), pos[c].distance_to(pos[a])))
	if total <= 0.0 or edges.is_empty():
		return false
	edges.sort()
	var share := foreign / total
	var median := edges[edges.size() / 2]
	if share <= FOREIGN_SHARE or median <= COARSE_EDGE:
		return false
	# A stretch of the course's road in it (a bridge's deck, in long triangles): it stays.
	for k in idx.size() - 2:
		var a := idx[k]
		var b := idx[k + 1]
		var c := idx[k + 2]
		if a == b or b == c or a == c or a >= pos.size() or b >= pos.size() or c >= pos.size():
			continue
		if _on_course_road((pos[a] + pos[b] + pos[c]) / 3.0, (pos[b] - pos[a]).cross(pos[c] - pos[a]).normalized()):
			return false
	return true


## A chunk per SLICES_PER_CHUNK slices, and the slices bucketed for the nearest one.
func _make_chunks() -> void:
	var n := vroad.size()
	for first in range(0, n, SLICES_PER_CHUNK):
		var pieces := []
		for k in 3:
			var pc := LayerPiece.new()
			pc.kind = k
			pieces.append(pc)
		chunks.append({"center": vroad[mini(first + SLICES_PER_CHUNK / 2, n - 1)].pos, "pieces": pieces})
	for k in 3:
		var pc := LayerPiece.new()
		pc.kind = k
		backdrop.append(pc)
	for i in n:
		var p := vroad[i].pos
		var key := Vector2i(floori(p.x / SLICE_BUCKET), floori(p.z / SLICE_BUCKET))
		var b: PackedInt32Array = _buckets.get(key, PackedInt32Array())
		b.append(i)
		_buckets[key] = b


## The chunk of the slice nearest `p` (by CHUNK_CELL cell), or -1 past BACKDROP_REACH.
func _chunk_at(p: Vector3) -> int:
	var key := Vector2i(floori(p.x / CHUNK_CELL), floori(p.z / CHUNK_CELL))
	if _chunk_cache.has(key):
		return _chunk_cache[key]
	var c := Vector3((key.x + 0.5) * CHUNK_CELL, p.y, (key.y + 0.5) * CHUNK_CELL)
	var bx := floori(c.x / SLICE_BUCKET)
	var bz := floori(c.z / SLICE_BUCKET)
	var best := -1
	var best_d := BACKDROP_REACH * BACKDROP_REACH
	var rings := ceili(BACKDROP_REACH / SLICE_BUCKET) + 1
	for r in rings:
		if best >= 0 and sqrt(best_d) < (r - 1) * SLICE_BUCKET:
			break
		for x in range(bx - r, bx + r + 1):
			for z in range(bz - r, bz + r + 1):
				if maxi(absi(x - bx), absi(z - bz)) != r:
					continue
				for i: int in _buckets.get(Vector2i(x, z), PackedInt32Array()):
					var q := vroad[i].pos
					var dd := Vector2(q.x - c.x, q.z - c.z).length_squared()
					if dd < best_d:
						best_d = dd
						best = i
	var chunk := best / SLICES_PER_CHUNK if best >= 0 else -1
	_chunk_cache[key] = chunk
	return chunk


## Relocations of an ELF object's .data: offset -> the symbol's name ("" for a .data
## pointer, whose target is the value in place).
static func _relocations(d: PackedByteArray) -> Dictionary:
	var out := {}
	if d.size() < 52:
		return out
	var shoff := d.decode_u32(32)
	var shnum := d.decode_u16(48)
	var secs := []
	for i in shnum:
		var s := shoff + i * 40
		if s + 40 > d.size():
			return out
		secs.append([d.decode_u32(s + 4), d.decode_u32(s + 16), d.decode_u32(s + 20), d.decode_u32(s + 24)])
	for s: Array in secs:
		if s[0] != 9:   # SHT_REL
			continue
		var symtab: Array = secs[s[3]]
		var strtab: Array = secs[symtab[3]]
		for k in s[2] / 8:
			var q: int = s[1] + k * 8
			var sym: int = d.decode_u32(q + 4) >> 8
			var sq: int = symtab[1] + sym * 16
			var name := ""
			if d.decode_u16(sq + 14) == 0:   # undefined: an external (the microcodes)
				name = Eagl._str(d, strtab[1] + d.decode_u32(sq))
			out[d.decode_u32(q)] = name
	return out


## Prop models of levelg.o (signs, barrels, cones: modelled round their centre, small)
## are placed by level.dat: a count, then 36 bytes a prop: a rotation (quaternion, in the
## physics' space), its position (the meshes' space), a word, and its type, the props' index
## among the prop models in name order. Those standing on a loaded compartment's surface
## (within PROP_REACH under them) go in `smackables`, their meshes in `smackable_kinds`; the rest are
## other levels' or parked at the origin. The level's other models (in place already) are
## scenery.
func _add_level(bytes: PackedByteArray, tex: Dictionary, dat_path: String) -> void:
	var e := Eagl.parse(bytes)
	if e.error != "":
		return
	var rel := _relocations(bytes)
	var names: Array = e.symbols.keys().filter(func(n: String) -> bool: return n.begins_with("__Model:::"))
	names.sort()
	var kinds: Array[PackedInt32Array] = []   # per prop type, its render methods
	for n: String in names:
		var m: int = e.symbols[n]
		var lo := Vector3(e.data.decode_float(m + 0x6C), e.data.decode_float(m + 0x70), e.data.decode_float(m + 0x74))
		var hi := Vector3(e.data.decode_float(m + 0x7C), e.data.decode_float(m + 0x80), e.data.decode_float(m + 0x84))
		if (lo + hi).length() > PROP_SIZE or (hi - lo).length() > PROP_SIZE:
			continue
		var rms := PackedInt32Array()
		# Its draw list: (0xA0000000, 0, n words of entries), then (0xA000FFFF, a render
		# method + 0x30) entries. The models' lists follow on one another: the next model's
		# header ends it.
		var o := e.u32(m + 0xCC)
		if e.u32(o) == 0xA0000000:
			var end := o + 12 + e.u32(o + 8) * 4
			o += 12
			while o < end and e.u32(o) == 0xA000FFFF:
				rms.append(e.u32(o + 4) - 0x30)
				o += 8
		for rm in rms:
			_skip[rm] = true
		kinds.append(rms)
	_add_object(bytes, tex)
	_skip.clear()
	var d := FileAccess.get_file_as_bytes(dat_path) if dat_path != "" else PackedByteArray()
	if d.size() < 4:
		return
	var white := images.size() - 1
	# Each type's mesh once, round its own origin.
	for rms in kinds:
		var pc := LayerPiece.new()
		pc.kind = Kind.SCENERY
		_into = pc
		for rm in rms:
			_add_method(e, rel, rm, tex, white)
		smackable_kinds.append(pc)
	_into = null
	for i in d.decode_u32(0):
		var o := 4 + i * 36
		if o + 36 > d.size():
			break
		var f := d.slice(o, o + 28).to_float32_array()
		var type := d.decode_u32(o + 32)
		var pos := Vector3(f[4], f[5], f[6])
		if type >= kinds.size() or pos.length() < 1.0 or is_nan(_sim_height(pos, PROP_REACH)):
			continue
		if _chunk_at(pos) < 0 or smackable_kinds[type].pos.is_empty():
			continue
		# The rotation is in the physics' space (Z the other way round, as mesh.sim's): the
		# same turn in the meshes' is (-x, -y, z, w).
		var q := Quaternion(-f[0], -f[1], f[2], f[3])
		if not q.is_normalized():
			continue
		smackables.append({"type": type, "xform": Transform3D(Basis(q), pos)})


## The collision surface's (`grid`'s, or the course's) height within `reach` under `p`
## (from just over it), or NAN.
func _sim_height(p: Vector3, reach: float, grid: Variant = null) -> float:
	var g: Dictionary = grid if grid != null else _sim
	var cell: PackedVector3Array = g.get(Vector2i(floori(p.x / SIM_CELL), floori(p.z / SIM_CELL)), PackedVector3Array())
	var best := NAN
	for i in range(0, cell.size(), 3):
		var hit = Geometry3D.ray_intersects_triangle(Vector3(p.x, p.y + 0.5, p.z), Vector3.DOWN,
			cell[i], cell[i + 1], cell[i + 2])
		if hit != null and hit.y >= p.y - reach and (is_nan(best) or hit.y > best):
			best = hit.y
	return best


## The FOOT_CELL cells within FOOT_REACH of a collision surface (a _sim_grid).
static func _footprint(grid: Dictionary) -> Dictionary:
	var core := {}
	for key: Vector2i in grid:
		var cell: PackedVector3Array = grid[key]
		for i in range(0, cell.size(), 3):
			var mid := (cell[i] + cell[i + 1] + cell[i + 2]) / 3.0
			core[Vector2i(floori(mid.x / FOOT_CELL), floori(mid.z / FOOT_CELL))] = true
	var r := ceili(FOOT_REACH / FOOT_CELL)
	var out := {}
	for c: Vector2i in core:
		for x in range(-r, r + 1):
			for z in range(-r, r + 1):
				if x * x + z * z <= r * r:
					out[c + Vector2i(x, z)] = true
	return out


func _count(reason: String) -> void:
	stats[reason] = stats.get(reason, 0) + 1


## The objects drawn more than once: a compartment holds some in two versions (a rough one
## and a detailed one, in its parts and their "LOD" parts), and its neighbours hold copies of
## them to be seen from there (the Calypso Coast temple is in three). The game draws one;
## loaded together they're drawn over each other. Render methods with the same textures whose
## boxes meet are copies when most of the smaller's surface (a sample of its triangles'
## middles, COPY_SHARE of them) is within COPY_GAP of the other's: the smaller goes, unless
## the bigger lies on it too (the same thing twice) and is in different compartment's, less
## in its own compartment's footprint (`feet`) than the smaller in its. Compartment -> {render method:
## true} to leave out.
func _find_copies(objs: Dictionary, feet: Dictionary) -> Dictionary:
	var recs: Array[Dictionary] = []
	var by_key := {}
	for c in objs:
		var e := Eagl.parse(objs[c])
		if e.error != "":
			continue
		var rel := _relocations(objs[c])
		for rm in _draw_order(e):
			var g := _method_geometry(e, rel, rm)
			if g.is_empty():
				continue
			var pos: PackedVector3Array = g.pos
			var tris: PackedInt32Array = g.tris
			var box := AABB(pos[tris[0]], Vector3.ZERO)
			var mids := PackedVector3Array()
			var own := 0
			var road := false
			var step := maxi(tris.size() / 3 / COPY_SAMPLES, 1)
			for k in range(0, tris.size(), 3):
				var m := (pos[tris[k]] + pos[tris[k + 1]] + pos[tris[k + 2]]) / 3.0
				if not road:
					road = _carries_road(m, (pos[tris[k + 1]] - pos[tris[k]]).cross(pos[tris[k + 2]] - pos[tris[k]]).normalized())
				for j in 3:
					box = box.expand(pos[tris[k + j]])
				if feet.get(c, {}).has(Vector2i(floori(m.x / FOOT_CELL), floori(m.z / FOOT_CELL))):
					own += 1
				if (k / 3) % step == 0:
					mids.append(m)
			var rec := {"comp": c, "rm": rm, "pos": pos, "tris": tris, "box": box, "mids": mids,
				"n": tris.size() / 3, "own": float(own) / (tris.size() / 3), "road": road}
			recs.append(rec)
			by_key.get_or_add(g.key, []).append(rec)
	var out := {}
	# Stand-ins: what lies mostly outside its compartment's footprint (its view of the next
	# one's ground, a rough sheet of it), where the next one, loaded too, has its own (any
	# textures): COPY_SHARE of it within STAND_IN_GAP of another compartment's triangles.
	var grid := {}   # COPY_CELL cell -> [[rec, first corner index], ...] of every method
	for rec in recs:
		var pos: PackedVector3Array = rec.pos
		var tris: PackedInt32Array = rec.tris
		for k in range(0, tris.size(), 3):
			var box := AABB(pos[tris[k]], Vector3.ZERO).expand(pos[tris[k + 1]]).expand(pos[tris[k + 2]]).grow(STAND_IN_GAP)
			for x in range(floori(box.position.x / COPY_CELL), floori(box.end.x / COPY_CELL) + 1):
				for z in range(floori(box.position.z / COPY_CELL), floori(box.end.z / COPY_CELL) + 1):
					grid.get_or_add(Vector2i(x, z), []).append([rec, k])
	var by_own := recs.duplicate()
	by_own.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.own < y.own)
	for rec in by_own:
		# (A stretch of the course's road off its compartment's surface, a bridge's deck, stays.)
		if rec.own >= STAND_IN_OWN or rec.road:
			continue
		var hits := 0
		for p: Vector3 in rec.mids:
			for entry: Array in grid.get(Vector2i(floori(p.x / COPY_CELL), floori(p.z / COPY_CELL)), []):
				var o: Dictionary = entry[0]
				# (Not on another stand-in: two of them for one place far from both, the
				# temple across the bay, would take each other out.)
				if o.comp == rec.comp or o.has("dropped"):
					continue
				var k: int = entry[1]
				if _to_triangle(p, o.pos[o.tris[k]], o.pos[o.tris[k + 1]], o.pos[o.tris[k + 2]]) < STAND_IN_GAP:
					hits += 1
					break
		if hits >= COPY_SHARE * rec.mids.size():
			out.get_or_add(rec.comp, {})[rec.rm] = true
			rec.dropped = true
			_count("render methods: stand-ins")
	for key in by_key:
		var group: Array = by_key[key]
		for i in group.size():
			for j in range(i + 1, group.size()):
				var a: Dictionary = group[i]
				var b: Dictionary = group[j]
				if a.has("dropped") or b.has("dropped") or not a.box.grow(COPY_GAP).intersects(b.box):
					continue
				var small: Dictionary = a if a.n <= b.n else b
				var big: Dictionary = b if small == a else a
				if not _lies_on(small.mids, big):
					continue
				# The smaller is a copy of (part of) the bigger. Only if the bigger lies on it too
				# are they one thing twice, either of which can go: then the one at home.
				var drop: Dictionary = small
				if a.comp != b.comp and absf(a.own - b.own) > COPY_OWN:
					var away: Dictionary = a if a.own < b.own else b
					if away == small or _lies_on(big.mids, small):
						drop = away
				# (Two copies of the course's road: both stay, the same surface twice.)
				if drop.road:
					continue
				out.get_or_add(drop.comp, {})[drop.rm] = true
				drop.dropped = true
				_count("render methods: copies")
	return out


## Whether COPY_SHARE of `points` are within COPY_GAP of `rec`'s triangles.
func _lies_on(points: PackedVector3Array, rec: Dictionary) -> bool:
	if not rec.has("grid"):
		var grid := {}
		var pos: PackedVector3Array = rec.pos
		var tris: PackedInt32Array = rec.tris
		for k in range(0, tris.size(), 3):
			var box := AABB(pos[tris[k]], Vector3.ZERO).expand(pos[tris[k + 1]]).expand(pos[tris[k + 2]]).grow(COPY_GAP)
			for x in range(floori(box.position.x / COPY_CELL), floori(box.end.x / COPY_CELL) + 1):
				for z in range(floori(box.position.z / COPY_CELL), floori(box.end.z / COPY_CELL) + 1):
					grid.get_or_add(Vector2i(x, z), PackedInt32Array()).append(k)
		rec.grid = grid
	var hits := 0
	for p in points:
		var cell: PackedInt32Array = rec.grid.get(Vector2i(floori(p.x / COPY_CELL), floori(p.z / COPY_CELL)), PackedInt32Array())
		for k in cell:
			if _to_triangle(p, rec.pos[rec.tris[k]], rec.pos[rec.tris[k + 1]], rec.pos[rec.tris[k + 2]]) < COPY_GAP:
				hits += 1
				break
	return hits >= COPY_SHARE * points.size()


## The distance from `p` to triangle a b c.
static func _to_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var n := (b - a).cross(c - a)
	if n.length_squared() > 1e-8:
		n = n.normalized()
		var q := p - n * n.dot(p - a)
		var inside := (b - a).cross(q - a).dot(n) >= 0.0 and (c - b).cross(q - b).dot(n) >= 0.0 \
			and (a - c).cross(q - c).dot(n) >= 0.0
		if inside:
			return absf(n.dot(p - a))
	var d := p.distance_to(Geometry3D.get_closest_point_to_segment(p, a, b))
	d = minf(d, p.distance_to(Geometry3D.get_closest_point_to_segment(p, b, c)))
	return minf(d, p.distance_to(Geometry3D.get_closest_point_to_segment(p, c, a)))


## A render method's corners and triangles (the strip's, degenerate ones out) and its
## textures' names as a key: {pos, tris, key}, or {} when it can't be read.
static func _method_geometry(e: Eagl, rel: Dictionary, rm: int) -> Dictionary:
	var mc: String = rel.get(rm + 8, "").trim_suffix("__EAGLMicroCode")
	if not MICROCODES.has(mc):
		return {}
	var pairs: Array[Vector2i] = []
	var a := rm + 0x34
	while rel.has(a + 4) and a + 8 <= e.data.size():
		pairs.append(Vector2i(e.u32(a), e.u32(a + 4)))
		a += 8
	if pairs.size() < 3:
		return {}
	var key := mc
	for k in pairs.size() - 2:
		if e.symbol_at(pairs[k].y).begins_with("__EAGL::TAR:::"):
			key += " " + e.data.slice(pairs[k].y + 4, pairs[k].y + 8).get_string_from_ascii()
	var vb := pairs[pairs.size() - 2]
	var ib := pairs[pairs.size() - 1]
	var stride: int = MICROCODES[mc][0]
	if vb.x == 0 or vb.y + vb.x * stride > e.data.size() or ib.y + ib.x * 2 > e.data.size():
		return {}
	var w := stride / 4
	var f := e.data.slice(vb.y, vb.y + vb.x * stride).to_float32_array()
	var pos := PackedVector3Array()
	pos.resize(vb.x)
	for k in vb.x:
		pos[k] = Vector3(f[k * w], f[k * w + 1], f[k * w + 2])
	var tris := PackedInt32Array()
	for k in ib.x - 2:
		var i0 := e.data.decode_u16(ib.y + k * 2)
		var i1 := e.data.decode_u16(ib.y + k * 2 + 2)
		var i2 := e.data.decode_u16(ib.y + k * 2 + 4)
		if i0 != i1 and i1 != i2 and i0 != i2 and i0 < vb.x and i1 < vb.x and i2 < vb.x:
			tris.append_array([i0, i1, i2])
	if tris.is_empty():
		return {}
	return {"pos": pos, "tris": tris, "key": key}


## The render methods of an EAGL object's models in the order they draw them (each
## model's draw list from +0xCC: 0xA0000000/0xA0000001 entries of 3 words, 0xA000FFFF of 2
## pointing 0x30 into a render method), then any no model draws.
static func _draw_order(e: Eagl) -> PackedInt32Array:
	var out := PackedInt32Array()
	var seen := {}
	for sym: String in e.symbols:
		if not sym.begins_with("__Model:::"):
			continue
		var o := e.u32(e.symbols[sym] + 0xCC)
		for k in 100000:
			var w := e.u32(o)
			if w >> 24 != 0xA0:
				break
			if w == 0xA000FFFF:
				var rm := e.u32(o + 4) - 0x30
				if not seen.has(rm):
					seen[rm] = true
					out.append(rm)
				o += 8
			else:
				o += 12
	for sym: String in e.symbols:
		if sym.begins_with("__RenderMethod:::") and not seen.has(e.symbols[sym]):
			out.append(e.symbols[sym])
	return out


## An EAGL object's render methods into the chunks (or, with `into`, all into that one
## piece, the sky), their textures by `tex` (TAR name -> images index).
func _add_object(bytes: PackedByteArray, tex: Dictionary, into: LayerPiece = null) -> void:
	var e := Eagl.parse(bytes)
	if e.error != "":
		return
	_into = into
	var rel := _relocations(bytes)
	var white := images.size() - 1
	for rm in _draw_order(e):
		if _skip.has(rm):
			continue
		_add_method(e, rel, rm, tex, white)


## A render method: its vertices and strip, under its microcode, through _add_strip.
func _add_method(e: Eagl, rel: Dictionary, rm: int, tex: Dictionary, white: int) -> void:
	var mc: String = rel.get(rm + 8, "").trim_suffix("__EAGLMicroCode")
	if not MICROCODES.has(mc):
		_count("unknown microcode " + mc)
		return
	# Its parameters from +0x34: (count, pointer) pairs, the last two the vertices and
	# the indices; the TARs among them are its textures.
	var pairs: Array[Vector2i] = []
	var a := rm + 0x34
	while rel.has(a + 4) and a + 8 <= e.data.size():
		pairs.append(Vector2i(e.u32(a), e.u32(a + 4)))
		a += 8
	if pairs.size() < 3:
		_count("no buffers")
		return
	var tars := PackedInt32Array()
	for k in pairs.size() - 2:
		if e.symbol_at(pairs[k].y).begins_with("__EAGL::TAR:::"):
			var nm := e.data.slice(pairs[k].y + 4, pairs[k].y + 8).get_string_from_ascii()
			tars.append(tex.get(nm, -1))
			if not tex.has(nm):
				_count("missing texture " + nm)
	var vb := pairs[pairs.size() - 2]
	var ib := pairs[pairs.size() - 1]
	var stride: int = MICROCODES[mc][0]
	var uvs: int = MICROCODES[mc][1]
	if vb.y + vb.x * stride > e.data.size() or ib.y + ib.x * 2 > e.data.size():
		return
	# Images: base, overlay, mask, shadow; uv set per image (uvs in the reverse order of
	# the TARs).
	var base := white
	var over := -1
	var mask := -1
	var shadow := -1
	var uv_of := [0, 0, 0, 0]
	var nt := tars.size()
	match mc:
		"NamedGouraud":
			pass
		"ShadowTexture":
			if nt >= 2:
				base = tars[1]
				shadow = tars[0]
				uv_of = [0, 0, 0, 1]
		"BlendedOverlay":
			if nt >= 3:
				base = tars[0]
				over = tars[1]
				mask = tars[2]
				uv_of = [2, 1, 0, 0]
		"BlendedWithShadow":
			if nt >= 4:
				shadow = tars[0]
				base = tars[1]
				over = tars[2]
				mask = tars[3]
				uv_of = [2, 1, 0, 3]
		"TwoShadows":
			if nt >= 1:
				base = tars[nt - 1]
				shadow = tars[0] if nt >= 2 else -1
				uv_of = [0, 0, 0, uvs - 1]
		_:
			if nt >= 1:
				base = tars[nt - 1]
	if base < 0:
		_count("no base texture (%s)" % mc)
		return
	if over < 0 or mask < 0:
		over = -1
		mask = -1
	var layers := Vector3(over + 1, mask + 1, shadow + 1)
	_add_strip(e.data, vb, ib, stride, uvs, uv_of, base, layers, mc == "ScrollTexture")


func _add_strip(d: PackedByteArray, vb: Vector2i, ib: Vector2i, stride: int, uvs: int,
		uv_of: Array, base: int, layers: Vector3, _scrolls: bool) -> void:
	var nv := vb.x
	var w := stride / 4
	var f := d.slice(vb.y, vb.y + nv * stride).to_float32_array()
	var pos := PackedVector3Array()
	var col := PackedColorArray()
	pos.resize(nv)
	col.resize(nv)
	for k in nv:
		pos[k] = _xform * Vector3(f[k * w], f[k * w + 1], f[k * w + 2])
		var c := d.decode_u32(vb.y + k * stride + 12)
		col[k] = Color8((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF, 255)
	var uv: Array[PackedVector2Array] = []
	for j in uvs:
		var set := PackedVector2Array()
		set.resize(nv)
		for k in nv:
			set[k] = Vector2(f[k * w + 4 + j * 2], f[k * w + 5 + j * 2])
		uv.append(set)
	var empty := PackedVector2Array()
	empty.resize(nv)
	var uv_base: PackedVector2Array = uv[uv_of[0]] if uvs > 0 else empty
	var uv_b: PackedVector2Array = uv[uv_of[1]] if layers.x > 0 else empty
	var uv_m: PackedVector2Array = uv[uv_of[2]] if layers.y > 0 else empty
	var uv_s: PackedVector2Array = uv[uv_of[3]] if layers.z > 0 else empty
	var idx := PackedInt32Array()
	idx.resize(ib.x)
	for k in ib.x:
		idx[k] = d.decode_u16(ib.y + k * 2)
	if not _others.is_empty() and _foreign(pos, idx):
		_count("render methods: another compartment's ground")
		return
	if _into == null and _blocks_course(pos, idx):
		_count("render methods: across the course")
		return
	for k in ib.x - 2:
		var i0 := idx[k]
		var i1 := idx[k + 1]
		var i2 := idx[k + 2]
		if i0 == i1 or i1 == i2 or i0 == i2 or i0 >= nv or i1 >= nv or i2 >= nv:
			continue
		if k % 2 == 1:
			var t := i1
			i1 = i2
			i2 = t
		var p0 := pos[i0]
		var p1 := pos[i1]
		var p2 := pos[i2]
		var mid := (p0 + p1 + p2) / 3.0
		var nrm := (p1 - p0).cross(p2 - p0).normalized()
		var kind := Kind.GROUND
		# The road first: some of it is see-through (a steel grating bridge).
		if _into != null:
			pass
		elif absf(nrm.y) >= ROAD_LEVEL and _on_sim(mid):
			kind = Kind.ROAD
		elif _cutout[base] and layers.x == 0:
			kind = Kind.SCENERY
		# (Not the course's own road where it's off the collision surface: a bridge's joint.)
		if _into == null and kind != Kind.ROAD and not _on_course_road(mid, nrm) \
				and (_out_of_place(mid) or _spans_out_of_place(p0, p1, p2)):
			_count("triangles: another stretch's, over the road")
			continue
		var pc: LayerPiece = _into
		if pc == null:
			var chunk := _chunk_at(mid)
			pc = chunks[chunk].pieces[kind] if chunk >= 0 else backdrop[kind]
		for i in [i0, i1, i2]:
			pc.pos.append(pos[i])
			pc.colour.append(col[i])
			pc.uv.append(uv_base[i])
			pc.uv_b.append(uv_b[i])
			pc.uv_m.append(uv_m[i])
			pc.uv_s.append(uv_s[i])
		pc.tex.append(base)
		pc.scroll.append(Vector2.ZERO)
		pc.layers.append(layers)
		pc.sphere.append(_sphere[base])


func mirror_world() -> void:
	super.mirror_world()
	# super swapped each triangle's 2nd and 3rd corners' uv: the layers' with them.
	for group in [backdrop] + chunks.map(func(c: Dictionary) -> Array: return c.pieces):
		for pc: LayerPiece in group:
			pc.uv_b = _swap_corners(pc.uv_b)
			pc.uv_m = _swap_corners(pc.uv_m)
			pc.uv_s = _swap_corners(pc.uv_s)
	# The props and the sky aren't among super's pieces: a prop's mesh is mirrored about its
	# origin and its placement S M S (S the mirror), which is S M on the unmirrored mesh.
	for pc in smackable_kinds:
		_mirror_piece(pc)
	var s := Basis.from_scale(Vector3(-1, 1, 1))
	for pr in smackables:
		var x: Transform3D = pr.xform
		pr.xform = Transform3D(s * x.basis * s, Vector3(-x.origin.x, x.origin.y, x.origin.z))
	_mirror_piece(sky)


static func _mirror_piece(pc: LayerPiece) -> void:
	for i in range(0, pc.pos.size() - 2, 3):
		var a := pc.pos[i + 1]
		pc.pos[i + 1] = Vector3(-pc.pos[i + 2].x, pc.pos[i + 2].y, pc.pos[i + 2].z)
		pc.pos[i + 2] = Vector3(-a.x, a.y, a.z)
		pc.pos[i] = Vector3(-pc.pos[i].x, pc.pos[i].y, pc.pos[i].z)
		var col := pc.colour[i + 1]
		pc.colour[i + 1] = pc.colour[i + 2]
		pc.colour[i + 2] = col
	pc.uv = _swap_corners(pc.uv)
	pc.uv_b = _swap_corners(pc.uv_b)
	pc.uv_m = _swap_corners(pc.uv_m)
	pc.uv_s = _swap_corners(pc.uv_s)


static func _swap_corners(arr: PackedVector2Array) -> PackedVector2Array:
	for i in range(0, arr.size() - 2, 3):
		var u := arr[i + 1]
		arr[i + 1] = arr[i + 2]
		arr[i + 2] = u
	return arr


## The course (Godot space) for the menu's map, without loading the geometry.
static func peek_course(dir: String) -> PackedVector3Array:
	var t := Nfs6Track.new()
	var pts := t._course(DataPath.find_ci(dir, "aipaths.dat"))
	var out := PackedVector3Array()
	for k in range(0, pts.size() / 7, 2):
		out.append(_pt(pts, k))
	return out
