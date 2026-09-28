class_name Nfs3Horizon
## Parses an NFS3 track's horizon file (trkNNN/3trNN.hrz, "n" suffix for night, "w" for
## weather): C-commented comma-separated integers giving fog, the gradient-shaded sky and
## earth bands around the track, clouds, lightning, rain or snow and the track's ambient
## light. Also gathers the images the sky is drawn with: the horizon panorama (the first 8
## tiles of the track's texture archive) and the clouds and sun/moon from trkNNN/sky.fsh.

const PANORAMA_TILES := 8
enum Precip { NONE, RAIN, SNOW }

var fog_color := Color.WHITE
var fog_density := 0.0          # percent 0-100
var fog_on_pixmap := 0.0        # percent 0-100 the horizon pixmap fades toward the fog colour
## Stretches of track with their own fog, each {slices: [before, centre, after] (virtual
## road nodes), colors: [3 Color], densities: [3 percent]}: the fog blends from the base
## to the first, the apex and the last colour and density along the stretch.
var fog_regions: Array[Dictionary] = []
var lightning_chance := 0       # percent chance of a strike per `lightning_ticks`; 0 none
var lightning_ticks := 0
var cloud_type := 0             # 0 none, 1 additive, 2 blended
var cloud_bright := 0.0         # 0-1, the brightest cloud
var cloud_variance := 0.0       # 0-1, how much darker the thinnest cloud is
var wind_mph := 0                # moves the clouds (and here the rain)
var wind_dir := 0                # degrees
var mirror := false             # the panorama covers 180 degrees and repeats mirrored
var radius := 1500.0            # horizon cylinder radius (NFS3 units)
var rotation := 0.0             # degrees
var has_pixmap := false
## Heights in NFS3 units, relative to the camera: the gradient's earth base, sky/earth
## midpoint and sky top, and the panorama's top and bottom edges.
var band_base := -750.0
var band_mid := -15.0
var band_top := 500.0
var pixmap_top := 210.0
var pixmap_bottom := -150.0
var earth_top := Color.GRAY
var earth_base := Color.GRAY
var sky_top := Color.SKY_BLUE
var sky_sun := Color.WHITE       # sky base colour toward the sun
var sky_away := Color.WHITE      # sky base colour opposite the sun
var ambient := Color.WHITE       # 0-1 per channel
## Weather files only: rain or snow, optionally just on the stretch from `precip_start` to
## `precip_end` (virtual road nodes, wrapping; equal means everywhere) fading in and out over
## `precip_fade` nodes, and cycling on, fading off, off and fading on (game ticks each; all
## zero means it never lets up).
var precip := Precip.NONE
var precip_start := 0
var precip_end := 0
var precip_fade := 0
var precip_cycle := PackedInt32Array([0, 0, 0, 0])

var panorama: Image              # PANORAMA_TILES tiles side by side, or null
var clouds: Image
var sun: Image                   # the sun by day, the moon (or an aurora) at night


## Loads the day or night, clear or weather horizon for the track folder `dir`; null when
## it's missing or too short to be a horizon file. `track_images` are the track's decoded
## texture archive.
static func load_dir(dir: String, night: bool, weather := false, track_images: Array[Image] = []) -> Nfs3Horizon:
	var short := dir.get_file().to_lower().replace("trk0", "3tr")  # trk001 -> 3tr01
	var path := DataPath.find_ci(dir, short + ("n" if night else "") + ("w" if weather else "") + ".hrz")
	if path == "":
		return null
	var h := from_text(FileAccess.get_file_as_string(path))
	if h == null:
		return null
	if h.has_pixmap and track_images.size() >= PANORAMA_TILES:
		h.panorama = _stitch(track_images.slice(0, PANORAMA_TILES))
	var fsh := Fsh.load_file(DataPath.find_ci(dir, "sky.fsh"))
	if fsh:
		# Cloud and sun/moon sprites: CLDD/CLDN/CLWD/CLWN, SUND/SUNN/SUNW/SNNW.
		h.clouds = fsh.by_name.get(("CLWN" if weather else "CLDN") if night else ("CLWD" if weather else "CLDD"))
		h.sun = fsh.by_name.get(("SNNW" if weather else "SUNN") if night else ("SUNW" if weather else "SUND"))
	return h


## Just the kind of weather the track folder `dir` has, without loading its sky images.
static func peek_precip(dir: String) -> Precip:
	var short := dir.get_file().to_lower().replace("trk0", "3tr")
	var path := DataPath.find_ci(dir, short + "w.hrz")
	var h := from_text(FileAccess.get_file_as_string(path)) if path != "" else null
	return h.precip if h else Precip.NONE


static func from_text(text: String) -> Nfs3Horizon:
	var body := RegEx.create_from_string("(?s)/\\*.*?\\*/").sub(text, " ", true)
	var v := PackedInt32Array()
	for m in RegEx.create_from_string("-?\\d+").search_all(body):
		v.append(int(m.get_string()))
	# 5 fog values, the region count, 15 per dynamic fog region, then 48 fixed fields.
	if v.size() < 6:
		return null
	var p := 6 + 15 * maxi(v[5], 0)
	if v.size() < p + 48:
		return null
	var h := Nfs3Horizon.new()
	h.fog_color = _rgb(v, 0)
	h.fog_density = v[3]
	h.fog_on_pixmap = v[4]
	for r in maxi(v[5], 0):
		var q := 6 + 15 * r
		h.fog_regions.append({
			"colors": [_rgb(v, q), _rgb(v, q + 4), _rgb(v, q + 8)],
			"densities": [v[q + 3], v[q + 7], v[q + 11]],
			"slices": [v[q + 12], v[q + 13], v[q + 14]],
		})
	# cloud type, fog clouds, lightning x2, visual height, cloud dome offset x2
	h.cloud_type = v[p]
	h.lightning_chance = maxi(v[p + 2], 0)
	h.lightning_ticks = maxi(v[p + 3], 0)
	h.cloud_bright = clampf(v[p + 7] / 255.0, 0.0, 1.0)
	h.cloud_variance = clampf(v[p + 8] / 255.0, 0.0, h.cloud_bright)
	# p + 9: nimbus effect, p + 12: black horizon
	h.wind_mph = v[p + 10]
	h.wind_dir = v[p + 11]
	h.mirror = v[p + 13] != 0
	p += 14
	h.radius = maxf(v[p], 100.0)
	h.rotation = v[p + 1]
	h.has_pixmap = v[p + 2] != 0
	var base := float(v[p + 3])
	h.band_base = base
	h.band_top = base + v[p + 4]
	h.band_mid = base + v[p + 5]
	h.pixmap_top = base + v[p + 6]
	h.pixmap_bottom = base + v[p + 7]
	p += 8
	h.earth_top = _rgb(v, p)
	h.earth_base = _rgb(v, p + 3)
	h.sky_top = _rgb(v, p + 6)
	h.sky_sun = _rgb(v, p + 9)
	h.sky_away = _rgb(v, p + 12)
	p += 15
	# The weather block is in every file; clear-weather files just don't get to use it.
	h.precip = clampi(v[p], 0, Precip.SNOW) as Precip
	h.precip_start = v[p + 1]
	h.precip_end = v[p + 2]
	h.precip_fade = maxi(v[p + 3], 0)
	h.precip_cycle = PackedInt32Array([v[p + 4], v[p + 5], v[p + 6], v[p + 7]])
	p += 8
	if v.size() >= p + 3:
		h.ambient = Color(v[p] / 100.0, v[p + 1] / 100.0, v[p + 2] / 100.0)
	return h


static func _rgb(v: PackedInt32Array, i: int) -> Color:
	return Color8(clampi(v[i], 0, 255), clampi(v[i + 1], 0, 255), clampi(v[i + 2], 0, 255))


## The panorama tiles side by side, each scaled to the first tile's size.
static func _stitch(tiles: Array[Image]) -> Image:
	var w := tiles[0].get_width()
	var ht := tiles[0].get_height()
	var out := Image.create_empty(w * tiles.size(), ht, false, Image.FORMAT_RGBA8)
	for i in tiles.size():
		var t: Image = tiles[i].duplicate()
		if t.is_compressed():
			t.decompress()
		t.convert(Image.FORMAT_RGBA8)
		if t.get_size() != Vector2i(w, ht):
			t.resize(w, ht)
		out.blit_rect(t, Rect2i(0, 0, w, ht), Vector2i(i * w, 0))
	return out
