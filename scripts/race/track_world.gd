class_name TrackWorld
extends RefCounted
## A track and its sky: the geometry, then a sun, sky, fog and ambient light for the time
## of day and weather (the track's own .hrz where there is one). Shared by the race and the
## menu's track postcards.

var id := ""
var root: Node3D               # the track's meshes and collision
var path: TrackPath
var track: Nfs3Track           # null for the procedural track (or a failed load)
var track_mat: ShaderMaterial  # NFS3 track only: takes the night tint and headlight cones
var horizon: Nfs3Horizon       # set by light(); null without one
var env: Environment
var sun: DirectionalLight3D
var mirrored := false          # laid out mirrored: the sun and the horizon's panorama go with it

var _nodes: Array[Node] = []   # what light() added, so it can be lit again


## Loads and builds the track (with `night`, its night version where it has one), laid out
## by `layout` (Game.LAYOUTS: forward, reverse, mirrored, mirrored reverse). Doesn't touch
## the scene tree, so it can run on a worker thread.
static func load_track(track_id: String, night := false, layout := 0) -> TrackWorld:
	var w := TrackWorld.new()
	w.id = track_id
	w.root = Node3D.new()
	w.root.name = "Track"
	w.mirrored = Game.layout_mirrored(layout) and Game.track_dir(track_id) != ""
	if Game.track_dir(track_id) != "":
		var t := Nfs3Track.load_dir(Game.track_dir(track_id), night)
		if t.error == "" and Game.layout_mirrored(layout):
			var remake := Game.hs_remake(track_id)
			if remake != "":
				t.borrow_mirror_images(Fsh.load_file(Game.find_ci(Game.track_dir(remake), "tr0.qfs")))
			t.mirror_world()
		if t.error == "" and t.vroad.size() > 10:
			if t is Nfs6Track:
				w.path = Nfs6TrackBuilder.build(t, w.root)
			else:
				w.path = Nfs5TrackBuilder.build(t, w.root) if t is Nfs5Track else Nfs3TrackBuilder.build(t, w.root)
			w.track_mat = w.root.get_meta("track_material")
			w.track = t
		else:
			push_warning("Track load failed (%s), using procedural track" % t.error)
	if w.path == null:
		w.path = ProceduralTrack.build(w.root)
	else:
		w.path.legal_speed = TrafficRules.legal_speeds(track_id, w.path.size())
	if Game.layout_reversed(layout):
		w.path.reverse()
	return w


## Adds the sun and sky under `parent` for these conditions, replacing an earlier call's.
## With `vp`, the quality preset is applied to it and the sun; otherwise the sun keeps
## full shadows.
func light(parent: Node, night: bool, weather: bool, vp: Viewport = null) -> void:
	for n in _nodes:
		n.queue_free()
	_nodes.clear()
	horizon = null
	if track:
		horizon = Nfs3Horizon.load_dir(Game.track_dir(id), night, weather, track.images)
	if track_mat:
		track_mat.set_shader_parameter("night_tint", Vector3.ONE)
		track_mat.set_shader_parameter("shadow_strength", 0.6)

	var we := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.28, 0.48, 0.82)
	sm.sky_horizon_color = Color(0.72, 0.8, 0.9)
	sm.ground_horizon_color = Color(0.72, 0.8, 0.9)
	sm.ground_bottom_color = Color(0.35, 0.4, 0.35)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.72, 0.8, 0.9)
	e.fog_density = 0.0016
	e.fog_sky_affect = 0.0
	we.environment = e
	env = e
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35 if mirrored else -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 120.0
	_nodes = [we, sun]
	# High Stakes' lamp and beacon glows, from the same .ini as the sky (night and weather
	# ones have their own colours).
	var glows: Node3D = TrackGlows.build(track, horizon.glows) if track and horizon else null
	if glows:
		_nodes.append(glows)
	for n in _nodes:
		parent.add_child(n)
	if vp:
		Game.apply_quality(vp, sun)
	# The procedural track's street-lamp light pools only show at night.
	for n: Node3D in root.get_meta("night_only", []):
		n.visible = night
	# ...and its windows light up.
	for m: ShaderMaterial in root.get_meta("night_materials", []):
		m.set_shader_parameter("night", 1.0 if night else 0.0)
	if night:
		_make_night(e, sm)
	if weather and not horizon:
		_make_overcast(e, sm, night)
	if horizon:
		_apply_horizon(horizon, e, sky, night, weather)


## Dark sky and fog (NFS3's night horizons use near-black fog), a faint moon and a cool
## ambient so unlit cars still read; the NFS3 track's baked light is dimmed to match.
func _make_night(e: Environment, sm: ProceduralSkyMaterial) -> void:
	sm.sky_top_color = Color(0.01, 0.015, 0.04)
	sm.sky_horizon_color = Color(0.05, 0.06, 0.1)
	sm.ground_horizon_color = sm.sky_horizon_color
	sm.ground_bottom_color = Color(0.01, 0.01, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.1, 0.12, 0.2)
	e.ambient_light_energy = 1.0
	e.fog_light_color = Color(0.03, 0.035, 0.06)
	e.fog_density = 0.003
	sun.light_color = Color(0.6, 0.7, 1.0)
	sun.light_energy = 0.12
	sun.shadow_enabled = false
	if track_mat:
		track_mat.set_shader_parameter("night_tint", Vector3(0.16, 0.18, 0.28))
		# Only a faint contact shadow under moonlight.
		track_mat.set_shader_parameter("shadow_strength", 0.35)


## Grey sky, thicker fog and weak sun for rain where the track has no weather horizon.
func _make_overcast(e: Environment, sm: ProceduralSkyMaterial, night: bool) -> void:
	var grey := Color(0.45, 0.48, 0.52) if not night else Color(0.03, 0.035, 0.05)
	sm.sky_top_color = grey.darkened(0.3)
	sm.sky_horizon_color = grey
	sm.ground_horizon_color = grey
	e.fog_light_color = grey
	e.fog_density *= 2.5
	sun.light_energy *= 0.4
	sun.shadow_enabled = false
	if track_mat and not night:
		track_mat.set_shader_parameter("shadow_strength", 0.45)


## The track's own sky, fog and ambient light from its .hrz file, replacing the generic
## ones set up above.
func _apply_horizon(h: Nfs3Horizon, e: Environment, sky: Sky, night: bool, weather: bool) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/horizon_sky.gdshader")
	mat.set_shader_parameter("sky_top", h.sky_top)
	mat.set_shader_parameter("sky_sun", h.sky_sun)
	mat.set_shader_parameter("sky_away", h.sky_away)
	mat.set_shader_parameter("earth_top", h.earth_top)
	mat.set_shader_parameter("earth_base", h.earth_base)
	# Band edges as the sine of their elevation from the car at the horizon radius.
	for k in [["horizon", h.band_mid], ["top", h.band_top], ["bottom", h.band_base]]:
		mat.set_shader_parameter(k[0], sin(atan2(k[1], h.radius)))
	# A directional light shines along -Z. The sprite sits no higher than 25 degrees so it
	# shows in the chase view; the light itself stays high for the shading.
	var to_sun := sun.transform.basis.z
	var flat := Vector2(to_sun.x, to_sun.z).normalized()
	var el := minf(asin(to_sun.y), deg_to_rad(25.0))
	mat.set_shader_parameter("sun_dir", Vector3(flat.x * cos(el), sin(el), flat.y * cos(el)))
	if h.sun:
		mat.set_shader_parameter("sun_tex", ImageTexture.create_from_image(h.sun))
		mat.set_shader_parameter("sun_size", 0.1 * h.sun.get_width() / 64.0)
		mat.set_shader_parameter("has_sun", true)
	if h.clouds and h.cloud_type > 0:
		var ct := ImageTexture.create_from_image(_with_mipmaps(h.clouds))
		mat.set_shader_parameter("cloud_tex", ct)
		mat.set_shader_parameter("cloud_type", h.cloud_type)
		mat.set_shader_parameter("cloud_bright", h.cloud_bright)
		mat.set_shader_parameter("cloud_variance", h.cloud_variance)
	var tint := Vector3(0.12 + 0.88 * h.ambient.r, 0.12 + 0.88 * h.ambient.g, 0.12 + 0.88 * h.ambient.b)
	mat.set_shader_parameter("tint", tint)
	if h.panorama:
		mat.set_shader_parameter("panorama", ImageTexture.create_from_image(h.panorama))
		mat.set_shader_parameter("has_panorama", true)
		mat.set_shader_parameter("mirror", h.mirror)
		mat.set_shader_parameter("flip", mirrored)
		mat.set_shader_parameter("pano_rotation", deg_to_rad(h.rotation))
		mat.set_shader_parameter("pano_top", sin(atan2(h.pixmap_top, h.radius)))
		mat.set_shader_parameter("pano_bottom", sin(atan2(h.pixmap_bottom, h.radius)))
		mat.set_shader_parameter("fog_color", h.fog_color)
		mat.set_shader_parameter("pano_fog", h.fog_on_pixmap / 100.0 * 0.5)
	sky.sky_material = mat
	e.fog_light_color = h.fog_color
	e.fog_density = Weather.fog_density(h.fog_density)
	# The ambient percentages scale the track's baked light (and the sky's layers above); a
	# floor keeps night tracks readable (5/10/15 % lands close to the old hand-tuned tint).
	if track_mat:
		# High Stakes' night versions have the night baked in, lamp pools and all: only a touch
		# more darkness on top, or the pools go out.
		track_mat.set_shader_parameter("night_tint", Vector3(0.75, 0.75, 0.8) if night and track.night_version else tint)
	if night:
		e.ambient_light_color = Color(tint.x, tint.y, tint.z) * 0.7
	elif weather:
		# Overcast: the sun barely gets through and casts no shadows.
		sun.light_energy *= 0.45
		sun.shadow_enabled = false
		if track_mat:
			track_mat.set_shader_parameter("shadow_strength", 0.45)


static func _with_mipmaps(img: Image) -> Image:
	var m := img.duplicate() as Image
	if m.is_compressed():
		m.decompress()
	m.generate_mipmaps()
	return m
