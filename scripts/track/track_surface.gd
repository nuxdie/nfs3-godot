class_name TrackSurface
## What a wheel is standing on, from the NFS3 track's per-polygon surface codes (the low
## nibble of the road poly flags). The builder tags each collision shape with a surface
## and texture per triangle; a wheel's ray hit (collider, shape, face_index) looks it up.
##   paved: 1 asphalt, 10 road edge, 4 concrete, 7/12 wooden bridge planks
##   loose: 2/3/5/13 grass, dirt and sand verges, 11 leaves, 14 off-road terrain, 15 snow
## Loose ground throws dust in the colour of its texture, which covers sand, grass and snow
## without a table per track. Needs face_index in ray results, which Jolt only fills in
## with physics/jolt_physics_3d/queries/enable_ray_cast_face_index (set in project.godot).

const UNKNOWN := 255
const LOOSE := [2, 3, 5, 11, 13, 14, 15]

## How the tyres get on with each surface: [grip factor, drag (1/s: deceleration per m/s of
## speed, for the whole car), roughness (m: height of the bumps the wheels ride over)].
## Paved is the reference; anything missing from the table (untagged scenery, bridges)
## counts as paved. Off the road the car slides more, bogs down and shakes.
const PAVED := [1.0, 0.0, 0.0]
const FEEL := {
	10: [0.97, 0.0, 0.006],    # road edge: rumble strip
	7: [0.95, 0.0, 0.004], 12: [0.95, 0.0, 0.004],   # bridge planks
	5: [0.72, 0.045, 0.022],    # gravel / dirt verge
	13: [0.66, 0.08, 0.02],    # sand
	2: [0.68, 0.065, 0.018], 3: [0.68, 0.065, 0.018],   # grass verges
	11: [0.8, 0.03, 0.01],     # leaves
	14: [0.6, 0.09, 0.03],     # off-road terrain
	15: [0.55, 0.06, 0.015],    # snow
}

static var _colours := {}   # body instance id * 4096 + texture -> dust Color


static func tag(cs: CollisionShape3D, surfaces: PackedByteArray, textures: PackedInt32Array) -> void:
	cs.set_meta("surface", surfaces)
	cs.set_meta("texture", textures)


## Track textures (Nfs3Track.images) for the dust colour of `body`'s shapes.
static func set_images(body: CollisionObject3D, images: Array[Image]) -> void:
	body.set_meta("surface_images", images)


## Surface code under a ray hit; UNKNOWN on untagged ground.
static func code(collider: Object, shape: int, face: int) -> int:
	var body := collider as CollisionObject3D
	if body == null or face < 0:
		return UNKNOWN
	var cs := body.shape_owner_get_owner(body.shape_find_owner(shape)) as CollisionShape3D
	if cs == null or not cs.has_meta("surface"):
		return UNKNOWN
	var surfaces: PackedByteArray = cs.get_meta("surface")
	return surfaces[face] if face < surfaces.size() else UNKNOWN


## [grip, drag, roughness] for a surface code (see FEEL).
static func feel(surface: int) -> Array:
	return FEEL.get(surface, PAVED)


## Dust colour for the ground under a ray hit, alpha 1; alpha 0 on paved or untagged ground.
static func dust(collider: Object, shape: int, face: int) -> Color:
	var body := collider as CollisionObject3D
	if body == null or not body.has_meta("surface_images"):
		return Color(0, 0, 0, 0)
	if code(collider, shape, face) not in LOOSE:
		return Color(0, 0, 0, 0)
	var cs := body.shape_owner_get_owner(body.shape_find_owner(shape)) as CollisionShape3D
	var tex: int = cs.get_meta("texture")[face]
	var images: Array[Image] = body.get_meta("surface_images")
	var key := body.get_instance_id() * 4096 + tex
	if not _colours.has(key):
		_colours[key] = _average(images[tex]) if tex >= 0 and tex < images.size() else Color(0.6, 0.5, 0.4)
	return _colours[key]


static func _average(img: Image) -> Color:
	var small := img.duplicate() as Image
	if small.is_compressed():
		small.decompress()
	small.convert(Image.FORMAT_RGBA8)
	small.resize(4, 4, Image.INTERPOLATE_LANCZOS)
	var sum := Color(0, 0, 0, 0)
	for y in 4:
		for x in 4:
			sum += small.get_pixel(x, y)
	sum /= 16.0
	# Pulled towards a light dusty beige: dust off grass reads as dirt, not green smoke, and
	# a cloud lighter than the ground it comes off stands out against it.
	var c := sum.lerp(Color(0.8, 0.74, 0.62), 0.45)
	c.a = 1.0
	return c
