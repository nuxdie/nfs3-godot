class_name Nfs6Driver
## Hot Pursuit 2's people in the cars: Actors/Driver (at the racers' wheels) and
## Actors/Copdriver, each a skinned EAGL model (Model1/model.o, textured from tex1.fsh) and a
## bank of animations (animbank.o). Read once per install and kept (`get_actor`); `pose`
## poses one and `skin` gives its mesh in that pose. HP2's space, as the model's (Y up, the
## front -Z, the driver's side -X): Nfs6Car turns it round.
##
## model.o (see Eagl):
##   __Skeleton:::Root: +8 the bone count, then from +0x10 a record of 0x70 per bone: its
##     scale (f32 x3, +0), rotation (quaternion x y z w, +0x10) and translation (+0x20), its
##     parent's frame, in the bind pose; and its inverse bind matrix (+0x30, 4x4, rows: the
##     axes then the translation). The parents aren't stored: each bone's is the one its bind
##     pose hangs from (_parents). A bone's scale is its own, not its children's (theirs
##     hang from its unscaled frame).
##   __Bone:::Root.<name>: the bone's index.
##   __RenderMethod:::*: per piece of the mesh, +0x24 its geoprim's data buffer, +0x58 its
##     weights: a vertex's word at +12 (Eagl.geoprim's "blend") picks a weight record of 16
##     bytes, three f32 weights and a zero, each weight's low byte the bone it is for.
## animbank.o:
##   __AnimationBank:::Animation1: +4 the clip count, +12 the clips, +16 their names, in pairs
##     "<name>_q" (rotations) and "<name>_t" (translations). A clip: +8 (frames << 16 | parts),
##     its parts from +12, each's kind its first word's low half:
##   kind 0x0B, the rotations sampled: +4 the samples (a word: 8 << 16 | channels; then per
##     channel three f32, offset, step, base; then a byte per channel per frame, frame by
##     frame); +10 a u16 per bone, (its first channel * 3 + 4). A channel's value is
##     base + offset + step * byte, a bone's four channels its quaternion (normalised: the
##     samples aren't quite unit).
##   kind 0x14: vectors held still (the translations, 3 floats): +4 0 (or a list of the bones
##     it holds, not read), +16 a u16 (count << 8 | 3), a u16, then a u16 per vector (its
##     place, 8 + bone * 12), then the vectors (_read_still). Bones not in one keep their bind
##     pose's translation (and kind 0x15's moving ones aren't read).

## The clips: t090902 the hard turn (its steering wheel well round), the rest sitting at it
## and looking about.
const STEER_CLIP := "t090902"
const REST_CLIP := "t090903"
## His own steering wheel (the model's, which the clips put his hands on): its rim's radius
## about the SteeringWheel bone, in that bone's XY plane, its Z the column (toward the dash).
const OWN_RIM := 0.155
## The bones left out of the mesh in the car (its own wheel is the car's), and those taken
## away for the in-car view, from the eye's seat.
const OWN_WHEEL := ["SteeringColumn", "SteeringWheel"]
const HEAD := ["Neck", "Head", "HeadEND"]
## His arms: upper arm, forearm, hand.
const ARMS := [["LeftHumerus", "LeftRadiusUlna", "LeftMetacarpals"],
	["RightHumerus", "RightRadiusUlna", "RightMetacarpals"]]

var names := PackedStringArray()
var parents := PackedInt32Array()
var rest_scale := PackedVector3Array()
var rest_rot: Array[Quaternion] = []
var rest_pos := PackedVector3Array()
var inv_bind: Array[Transform3D] = []
## The mesh, a triangle list in HP2's space, and per vertex three bones and their weights.
var pos := PackedVector3Array()
var normal := PackedVector3Array()
var uv := PackedVector2Array()
var indices := PackedInt32Array()
var bones := PackedInt32Array()
var weights := PackedFloat32Array()
var texture: Texture2D
## name -> {"frames": n, "rot": [frame][bone] Quaternion (bones the clip leaves out: their
## bind pose's), "pos": per bone its translation (the clip's still ones, else the bind pose's)}
var clips := {}
var error := ""

static var _actors := {}


## The actor `who` ("Driver", "Copdriver") of the install at `hp2_root`, or null.
static func get_actor(hp2_root: String, who: String) -> Nfs6Driver:
	var key := hp2_root + "|" + who
	if not _actors.has(key):
		var a := Nfs6Driver.new()
		a._load(DataPath.find_ci(DataPath.find_ci(hp2_root, "Actors"), who))
		_actors[key] = a if a.error == "" else null
	return _actors[key]


func bone(name: String) -> int:
	return names.find(name)


func _load(dir: String) -> void:
	if dir == "":
		error = "no actor"
		return
	var model := Eagl.parse(FileAccess.get_file_as_bytes(DataPath.find_ci(DataPath.find_ci(dir, "Model1"), "model.o")))
	if model.error != "" or not model.symbols.has("__Skeleton:::Root"):
		error = "model.o: " + (model.error if model.error != "" else "no skeleton")
		return
	_read_skeleton(model)
	_read_mesh(model)
	if pos.is_empty():
		error = "model.o: no mesh"
		return
	var fsh := Fsh.from_bytes(FileAccess.get_file_as_bytes(DataPath.find_ci(DataPath.find_ci(dir, "Model1"), "tex1.fsh")))
	if fsh and not fsh.images.is_empty():
		var img := fsh.images[0].duplicate() as Image
		if img.is_compressed():
			img.decompress()
		img.generate_mipmaps()
		texture = ImageTexture.create_from_image(img)
	var bank := Eagl.parse(FileAccess.get_file_as_bytes(DataPath.find_ci(dir, "animbank.o")))
	if bank.error == "":
		_read_clips(bank)


# ---------------------------------------------------------------- skeleton

func _read_skeleton(m: Eagl) -> void:
	var sk: int = m.symbols["__Skeleton:::Root"]
	var n := m.u32(sk + 8)
	names.resize(n)
	for s: String in m.symbols:
		if s.begins_with("__Bone:::Root."):
			var i := m.u32(m.symbols[s])
			if i < n:
				names[i] = s.get_slice(".", s.get_slice_count(".") - 1)
	for k in n:
		var r := sk + 0x10 + k * 0x70
		rest_scale.append(_vec(m, r))
		rest_rot.append(Quaternion(m.data.decode_float(r + 0x10), m.data.decode_float(r + 0x14),
			m.data.decode_float(r + 0x18), m.data.decode_float(r + 0x1C)).normalized())
		rest_pos.append(_vec(m, r + 0x20))
		var a := r + 0x30
		inv_bind.append(Transform3D(Basis(_vec(m, a), _vec(m, a + 16), _vec(m, a + 32)), _vec(m, a + 48)))
	_parents()


static func _vec(m: Eagl, at: int) -> Vector3:
	return Vector3(m.data.decode_float(at), m.data.decode_float(at + 4), m.data.decode_float(at + 8))


## Each bone's parent: the earlier bone whose bind frame, with the bone's own translation from
## it, lands where the bone's bind frame is.
func _parents() -> void:
	var bind: Array[Transform3D] = []
	for t in inv_bind:
		bind.append(t.affine_inverse())
	parents.resize(names.size())
	parents[0] = -1
	for i in range(1, names.size()):
		var best := INF
		for p in i:
			var d := (bind[p] * Transform3D(Basis(rest_rot[i]), rest_pos[i])).origin.distance_to(bind[i].origin)
			if d < best:
				best = d
				parents[i] = p


# ---------------------------------------------------------------- mesh

func _read_mesh(m: Eagl) -> void:
	for s: String in m.symbols:
		if not s.begins_with("__RenderMethod:::"):
			continue
		var rm: int = m.symbols[s]
		var g := m.geoprim(m.u32(rm + 0x24))
		var wt := m.u32(rm + 0x58)
		if g.is_empty() or not g.has("blend") or wt == 0:
			continue
		var base := pos.size()
		pos.append_array(g.pos)
		normal.append_array(g.normal)
		uv.append_array(g.uv)
		for b: int in g.blend:
			for j in 3:
				var w := m.u32(wt + b * 16 + j * 4)
				bones.append(w & 0xFF)
				weights.append(m.data.decode_float(wt + b * 16 + j * 4) if w != 0 else 0.0)
		for i: int in g.indices:
			indices.append(base + i)
	# (The low byte the bone's: a weight's own last bits, cleared.)
	for i in weights.size():
		if weights[i] != 0.0:
			var b := PackedByteArray()
			b.resize(4)
			b.encode_float(0, weights[i])
			b[0] = 0
			weights[i] = b.decode_float(0)


# ---------------------------------------------------------------- clips

func _read_clips(b: Eagl) -> void:
	if not b.symbols.has("__AnimationBank:::Animation1"):
		return
	var bank: int = b.symbols["__AnimationBank:::Animation1"]
	var n := b.u32(bank + 4)
	var list := b.u32(bank + 12)
	var name_list := b.u32(bank + 16)
	var rots := {}
	var still := {}
	for i in n:
		var clip := b.u32(list + i * 4)
		var cname := b.c_string(b.u32(name_list + i * 4))
		var frames := b.u32(clip + 8) >> 16
		for k in b.u32(clip + 8) & 0xFFFF:
			var part := b.u32(clip + 12 + k * 4)
			match b.u32(part) & 0xFFFF:
				0x0B:
					rots[cname.trim_suffix("_q")] = _read_rotations(b, part, frames)
				0x14:
					still[cname.trim_suffix("_t")] = _read_still(b, part)
	for c: String in rots:
		clips[c] = {"frames": (rots[c] as Array).size(), "rot": rots[c], "pos": still.get(c, rest_pos)}


func _read_rotations(b: Eagl, part: int, frames: int) -> Array:
	var at := b.u32(part + 4)
	var nch := b.u32(at) & 0xFFFF
	var rows := at + 4
	var samples := rows + nch * 12
	if frames < 1 or samples + nch * frames > b.data.size():
		return []
	var first := PackedInt32Array()   # per bone, its first channel
	for k in mini(nch / 4, names.size()):
		first.append((b.data.decode_u16(part + 10 + k * 2) - 4) / 3)
	# (The last frame's samples are all zero: not a frame.)
	var out := []
	for f in frames - 1:
		var q: Array[Quaternion] = rest_rot.duplicate()
		for k in first.size():
			var v := PackedFloat32Array()
			v.resize(4)
			for c in 4:
				var ch := first[k] + c
				var row := rows + ch * 12
				v[c] = b.data.decode_float(row + 8) + b.data.decode_float(row) \
					+ b.data.decode_float(row + 4) * b.data[samples + f * nch + ch]
			var qq := Quaternion(v[0], v[1], v[2], v[3])
			if qq.length_squared() > 0.01:
				q[k] = qq.normalized()
		out.append(q)
	return out


## A clip's translations: the bind pose's, with those a part of still vectors holds.
func _read_still(b: Eagl, part: int) -> PackedVector3Array:
	var out := rest_pos.duplicate()
	var desc := b.data.decode_u16(part + 0x10)
	var count := desc >> 8
	if b.u32(part + 4) != 0 or desc & 0xFF != 3:
		return out
	var data := part + 0x14 + count * 2
	var first := b.data.decode_u16(part + 0x14)
	for k in count:
		var bone_i := (b.data.decode_u16(part + 0x14 + k * 2) - 8) / 12
		if bone_i >= 0 and bone_i < out.size():
			out[bone_i] = _vec(b, data + b.data.decode_u16(part + 0x14 + k * 2) - first)
	return out


# ---------------------------------------------------------------- posing

## Each bone's frame (its own scale left out), HP2's space, with the bones' rotations `rot`
## and translations `at` (a clip's), the whole placed by `place`.
func pose(rot: Array, at: PackedVector3Array, place := Transform3D.IDENTITY) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for i in names.size():
		var local := Transform3D(Basis(rot[i] as Quaternion), at[i])
		if parents[i] < 0:
			local = place * local
		out.append(local if parents[i] < 0 else out[parents[i]] * local)
	return out


## The mesh's positions and normals in the pose `frames` (pose()'s), skinned.
func skin(frames: Array[Transform3D]) -> Array:
	var m: Array[Transform3D] = []
	for i in names.size():
		m.append(frames[i] * Transform3D(Basis.from_scale(rest_scale[i]), Vector3.ZERO) * inv_bind[i])
	var p := PackedVector3Array()
	var nn := PackedVector3Array()
	p.resize(pos.size())
	nn.resize(pos.size())
	for v in pos.size():
		var a := Vector3.ZERO
		var n := Vector3.ZERO
		for j in 3:
			var w := weights[v * 3 + j]
			if w == 0.0:
				continue
			var t := m[bones[v * 3 + j]]
			a += t * pos[v] * w
			n += t.basis * normal[v] * w
		p[v] = a
		nn[v] = n.normalized()
	return [p, nn]


# ---------------------------------------------------------------- in the car

## His bones seated at a steering wheel: REST_CLIP's first frame, his root at `seat`, and his
## hands holding `wheel` (a frame: its middle, Z its column toward the dash, Y up its face;
## the rim `rim` across) turned `turn` (radians about its column) where they hold his own
## wheel, as far round it, the arms reaching there. HP2's space.
func seated(seat: Vector3, wheel: Transform3D, rim: float, turn: float) -> Array[Transform3D]:
	var rest: Dictionary = clips.get(REST_CLIP, clips.values()[0])
	var steer: Dictionary = clips.get(STEER_CLIP, rest)
	var rot: Array = (rest.rot[0] as Array).duplicate()
	var at: PackedVector3Array = (rest.pos as PackedVector3Array).duplicate()
	# (Only STEER_CLIP puts his wheel in front of him; unturned.)
	var col := bone("SteeringColumn")
	var own := bone("SteeringWheel")
	if col >= 0 and own >= 0:
		at[col] = steer.pos[col]
		at[own] = steer.pos[own]
		rot[own] = Quaternion.IDENTITY
	at[0] = seat
	var f := pose(rot, at)
	if own < 0:
		return f
	var held := wheel * Transform3D(Basis(Vector3.BACK, turn), Vector3.ZERO)
	var to_own := wheel_frame(f[own].origin, f[own].basis.z.normalized()).affine_inverse()
	for arm: Array in ARMS:
		var hand := bone(arm[2])
		if hand < 0:
			continue
		var grip := to_own * f[hand]
		grip.origin = Vector3(grip.origin.x * rim / OWN_RIM, grip.origin.y * rim / OWN_RIM, grip.origin.z)
		f = _reach(rot, at, bone(arm[0]), bone(arm[1]), hand, held * grip)
	return f


## A steering wheel's frame: at its middle `mid`, Z its column `axis` (toward the dash), Y the
## way up its face.
static func wheel_frame(mid: Vector3, axis: Vector3) -> Transform3D:
	var x := Vector3.UP.cross(axis).normalized()
	return Transform3D(Basis(x, axis.cross(x), axis), mid)


## The arm `upper`-`lower`-`hand` bent to put the hand at `goal` (as near as it reaches), the
## elbow out the way it was; `rot` takes the new rotations. The bones' frames.
func _reach(rot: Array, at: PackedVector3Array, upper: int, lower: int, hand: int, goal: Transform3D) -> Array[Transform3D]:
	var f := pose(rot, at)
	var s := f[upper].origin
	var e := f[lower].origin
	var a := s.distance_to(e)
	var b := e.distance_to(f[hand].origin)
	var to := goal.origin - s
	var d := clampf(to.length(), absf(a - b) + 0.001, a + b - 0.001)
	var u := to.normalized()
	var out := (e - s) - u * (e - s).dot(u)
	out = out.normalized() if out.length_squared() > 1e-8 else Vector3.DOWN
	var x := (a * a - b * b + d * d) / (2.0 * d)
	var elbow := s + u * x + out * sqrt(maxf(a * a - x * x, 0.0))
	rot[upper] = _turned(f, upper, e - s, elbow - s)
	f = pose(rot, at)
	rot[lower] = _turned(f, lower, f[hand].origin - f[lower].origin, s + u * d - f[lower].origin)
	f = pose(rot, at)
	rot[hand] = (f[lower].basis.inverse() * goal.basis).get_rotation_quaternion()
	return pose(rot, at)


## Bone `i`'s rotation (its parent's frame) turned so its `from` (world) points along `to`.
func _turned(f: Array[Transform3D], i: int, from: Vector3, to: Vector3) -> Quaternion:
	var q := Quaternion(from.normalized(), to.normalized())
	return (f[parents[i]].basis.inverse() * Basis(q) * f[i].basis).get_rotation_quaternion()


## The mesh for the car: seated()'s pose at each of `turns`, his own wheel left out. A
## triangle list: {"pos": [per turn PackedVector3Array], "normal": [per turn], "uv",
## "head": PackedByteArray (1 where the vertex is his head's)}. HP2's space.
func seated_mesh(seat: Vector3, wheel: Transform3D, rim: float, turns: PackedFloat32Array) -> Dictionary:
	var drop := {}
	for n: String in OWN_WHEEL:
		drop[bone(n)] = true
	var head := {}
	for n: String in HEAD:
		head[bone(n)] = true
	var keep := PackedInt32Array()
	for t in range(0, indices.size() - 2, 3):
		var out := false
		for k in 3:
			out = out or drop.has(_main_bone(indices[t + k]))
		if not out:
			keep.append_array([indices[t], indices[t + 1], indices[t + 2]])
	var poses := []
	var normals := []
	for turn in turns:
		var sk := skin(seated(seat, wheel, rim, turn))
		var p := PackedVector3Array()
		var n := PackedVector3Array()
		for i in keep:
			p.append(sk[0][i])
			n.append(sk[1][i])
		poses.append(p)
		normals.append(n)
	var tuv := PackedVector2Array()
	var th := PackedByteArray()
	for i in keep:
		tuv.append(uv[i])
		th.append(1 if head.has(_main_bone(i)) else 0)
	return {"pos": poses, "normal": normals, "uv": tuv, "head": th}


func _main_bone(v: int) -> int:
	var best := 0
	for j in range(1, 3):
		if weights[v * 3 + j] > weights[v * 3 + best]:
			best = j
	return bones[v * 3 + best]
