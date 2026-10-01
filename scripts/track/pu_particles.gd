class_name PuParticles
## Porsche Unleashed's particle effects on its tracks: at each emitter (Nfs5Track.emitters:
## waterfall spray, river rapids, fountains, chimney and factory smoke, steam vents), the
## system its tag picks from GameData/Render/particle.ini, drawn with particle.fsh's sprites.
##
## A system there: numparticles; emit.x and emit.z the area (m) it starts in, across the
## emitter's X and Z, emit.y how fast it leaves along its Y (m a tick); randemit a random
## speed (m a tick) on each axis; weight how hard it falls (up when negative: steam);
## lifetime (ticks); startsize and endsize (m); color.0-3 (ARGB) over its life, numstates
## of them; matid the sprite (particle.fsh's entry name, as a big-endian word); blendmode
## 1 and 2 added on, 0 blended; randrotation how fast (degrees a second, either way) it spins.

## The game's ticks a second the systems count in (its animations key every other tick).
const TICKS_PER_SECOND := 30.0
## Downward acceleration (m/s^2) for a weight of 1.
const GRAVITY := 4.0
## How far off (m) the effects are drawn.
const DRAW_DISTANCE := 500.0

static var _systems := {}       # pu_root -> {tag -> system Dictionary}
static var _sprites := {}       # pu_root -> {name -> ImageTexture}


## The emitters of `t` as particle nodes under a new node, or null when there are none (or
## no particle.ini).
static func build(t: Nfs5Track, pu_root: String) -> Node3D:
	if t.emitters.is_empty() or pu_root == "":
		return null
	var systems := _load_systems(pu_root)
	if systems.is_empty():
		return null
	var root := Node3D.new()
	root.name = "Particles"
	var mats := {}   # [sprite, blend] -> material
	for em: Dictionary in t.emitters:
		var sys: Dictionary = systems.get(em.tag, {})
		if sys.is_empty() or int(sys.get("inUse", 1)) == 0:
			continue
		var p := _particles(sys, _sprite(pu_root, sys), mats)
		if p == null:
			continue
		var x: Vector3 = em.x.normalized()
		var y: Vector3 = em.y.normalized()
		if x.is_zero_approx() or y.is_zero_approx():
			continue
		p.transform = Transform3D(Basis(x, y, x.cross(y)).orthonormalized(), em.pos)
		p.name = "%s_%d" % [em.tag.validate_node_name(), root.get_child_count()]
		root.add_child(p)
	return root if root.get_child_count() > 0 else null


static func _particles(sys: Dictionary, sprite: Texture2D, mats: Dictionary) -> GPUParticles3D:
	var n := int(sys.get("numparticles", 0))
	var life := float(sys.get("lifetime", 0)) / TICKS_PER_SECOND
	if n <= 0 or life <= 0.0:
		return null
	var p := GPUParticles3D.new()
	p.amount = n
	p.lifetime = life
	p.preprocess = life   # already going when the race starts
	p.local_coords = false
	p.visibility_range_end = DRAW_DISTANCE
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	var area := Vector3(float(sys.get("emit.x", 0)), 0.0, float(sys.get("emit.z", 0)))
	if area.length() > 0.01:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = area * 0.5
	var speed := float(sys.get("emit.y", 0)) * TICKS_PER_SECOND
	var rnd := Vector3(float(sys.get("randemit.x", 0)), float(sys.get("randemit.y", 0)),
		float(sys.get("randemit.z", 0))) * TICKS_PER_SECOND
	pm.direction = Vector3.UP
	pm.initial_velocity_min = maxf(speed - rnd.y, 0.0)
	pm.initial_velocity_max = speed + rnd.y
	var across := maxf(rnd.x, rnd.z)
	pm.spread = rad_to_deg(atan2(across, maxf(speed, 0.01))) if across > 0.0 else 0.0
	pm.gravity = Vector3.DOWN * float(sys.get("weight", 0)) * GRAVITY
	var size_a := float(sys.get("startsize", 1))
	var size_b := float(sys.get("endsize", 1))
	var big := maxf(maxf(size_a, size_b), 0.01)
	pm.scale_min = big
	pm.scale_max = big
	var curve := Curve.new()
	curve.add_point(Vector2(0, size_a / big))
	curve.add_point(Vector2(1, size_b / big))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var spin := float(sys.get("randrotation", 0))
	pm.angular_velocity_min = -spin
	pm.angular_velocity_max = spin
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	var states := clampi(int(sys.get("numstates", 2)), 1, 4)
	var grad := Gradient.new()
	grad.remove_point(1)
	grad.set_offset(0, 0.0)
	grad.set_color(0, _argb(int(sys.get("color.0", -1))))
	for k in range(1, states):
		grad.add_point(float(k) / (states - 1), _argb(int(sys.get("color.%d" % k, -1))))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var blend := int(sys.get("blendmode", 0))
	var key := [sprite, blend]
	if not mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = sprite
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if blend != 0 else BaseMaterial3D.BLEND_MODE_MIX
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mats[key] = m
	var quad := QuadMesh.new()
	quad.material = mats[key]
	p.draw_pass_1 = quad
	# How far its particles can get, for culling: up to their speed (and fall) over a life.
	var reach := (speed + rnd.length()) * life + absf(pm.gravity.y) * life * life * 0.5 + big + area.length()
	p.visibility_aabb = AABB(Vector3.ONE * -reach, Vector3.ONE * reach * 2.0)
	return p


static func _argb(v: int) -> Color:
	v &= 0xFFFFFFFF
	return Color8((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF, (v >> 24) & 0xFF)


static func _load_systems(pu_root: String) -> Dictionary:
	if _systems.has(pu_root):
		return _systems[pu_root]
	var out := {}
	var path := DataPath.find_ci(pu_root, "Render/particle.ini")
	var text := FileAccess.get_file_as_string(path) if path != "" else ""
	var cur := {}
	for line in text.split("\n"):
		line = line.strip_edges()
		if line.begins_with("[system#"):
			cur = {}
			continue
		var eq := line.find("=")
		if eq < 0:
			continue
		var k := line.substr(0, eq)
		var val := line.substr(eq + 1)
		cur[k] = val
		if k == "tag":
			out[_fourcc(int(val), false)] = cur
	_systems[pu_root] = out
	return out


## A word as its 4 characters: little-endian (the tags, "RPD1") or big-endian (matid, "WFAL").
static func _fourcc(v: int, big_endian: bool) -> String:
	var s := ""
	for i in 4:
		var b := (v >> ((3 - i if big_endian else i) * 8)) & 0xFF
		s += char(b)
	return s


static func _sprite(pu_root: String, sys: Dictionary) -> Texture2D:
	if not _sprites.has(pu_root):
		var tex := {}
		var path := DataPath.find_ci(pu_root, "Render/particle.fsh")
		var fsh := Fsh.load_file(path) if path != "" else null
		if fsh != null:
			for i in mini(fsh.names.size(), fsh.images.size()):
				tex[fsh.names[i]] = ImageTexture.create_from_image(fsh.images[i])
		_sprites[pu_root] = tex
	return _sprites[pu_root].get(_fourcc(int(sys.get("matid", 0)), true))
