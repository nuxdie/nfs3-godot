class_name Nfs3Horizon
## Parses an NFS3 track's horizon file (trkNNN/3trNN.hrz, "n" suffix for night, "w" for
## weather): C-commented comma-separated integers giving fog, the gradient-shaded sky and
## earth bands around the track, clouds, and the track's ambient light. Also gathers the
## images the sky is drawn with: the horizon panorama (the first 8 tiles of the track's
## texture archive) and the clouds and sun/moon from trkNNN/sky.fsh.

const PANORAMA_TILES := 8

var fog_color := Color.WHITE
var fog_density := 0.0          # percent 0-100
var fog_on_pixmap := 0.0        # percent 0-100 the horizon pixmap fades toward the fog colour
var cloud_type := 0             # 0 none, 1 additive, 2 blended
var cloud_bright := 0.0         # 0-1, the brightest cloud
var cloud_variance := 0.0       # 0-1, how much darker the thinnest cloud is
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

var panorama: Image              # PANORAMA_TILES tiles side by side, or null
var clouds: Image
var sun: Image                   # the sun by day, the moon (or an aurora) at night


## Loads the day or night horizon for the track folder `dir`; null when it's missing or
## too short to be a horizon file. `track_images` are the track's decoded texture archive.
static func load_dir(dir: String, night: bool, track_images: Array[Image] = []) -> Nfs3Horizon:
	var short := dir.get_file().to_lower().replace("trk0", "3tr")  # trk001 -> 3tr01
	var path := DataPath.find_ci(dir, short + ("n" if night else "") + ".hrz")
	if path == "":
		return null
	var h := from_text(FileAccess.get_file_as_string(path))
	if h == null:
		return null
	if h.has_pixmap and track_images.size() >= PANORAMA_TILES:
		h.panorama = _stitch(track_images.slice(0, PANORAMA_TILES))
	var fsh := Fsh.load_file(DataPath.find_ci(dir, "sky.fsh"))
	if fsh:
		h.clouds = fsh.by_name.get("CLDN" if night else "CLDD")
		h.sun = fsh.by_name.get("SUNN" if night else "SUND")
	return h


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
	# fog clouds, lightning x2, visual height, cloud dome offset x2
	h.cloud_type = v[p]
	h.cloud_bright = clampf(v[p + 7] / 255.0, 0.0, 1.0)
	h.cloud_variance = clampf(v[p + 8] / 255.0, 0.0, h.cloud_bright)
	# p + 9: nimbus effect, p + 10/11: wind speed/direction, p + 12: black horizon
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
	p += 15 + 8  # weather parameters
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
