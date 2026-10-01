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

## High Stakes only: the glows drawn at the track's light sources (see TrackGlows), from
## the .ini's [track glows]: 32 of {color (with alpha), blink (-1: steady; else off while
## bit `blink` of the game tick plus `phase` is set), phase, size, on and off (ticks lit and
## dark in turn; 0 when it doesn't cycle)}.
var glows: Array[Dictionary] = []

var panorama: Image              # PANORAMA_TILES tiles side by side, or null
var clouds: Image
var sun: Image                   # the sun by day, the moon (or an aurora) at night


## Loads the day or night, clear or weather horizon for the track folder `dir`; null when
## it's missing or too short to be a horizon file. `track_images` are the track's decoded
## texture archive.
static func load_dir(dir: String, night: bool, weather := false, track_images: Array[Image] = []) -> Nfs3Horizon:
	if Nfs6Track.is_track_dir(dir):
		return _load_hp2(dir)
	if Nfs5Track.is_track_file(dir):
		return _load_pu(dir, night)
	if Nfs4Track.is_track_dir(dir):
		return _load_hs(dir, night, weather)
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
	if Nfs4Track.is_track_dir(dir):
		var ini := DataPath.find_ci(dir, "trw.ini")
		var hs := from_ini(FileAccess.get_file_as_string(ini)) if ini != "" else null
		return hs.precip if hs else Precip.NONE
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


## A Hot Pursuit 2 level's horizon: its area's tr.ini, in High Stakes' keys. Its sky is a
## dome (Nfs6Track.sky, drawn by Nfs6TrackBuilder), so there's no panorama.
static func _load_hp2(level_dir: String) -> Nfs3Horizon:
	var path := DataPath.find_ci(level_dir.get_base_dir(), "tr.ini")
	var h := from_ini(FileAccess.get_file_as_string(path)) if path != "" else null
	if h:
		h.has_pixmap = false
	return h


## A High Stakes track's horizon: tr.ini (trn night, trw weather, trnw both) holds the same
## settings as NFS3's .hrz, as named keys; its sky.qfs holds the panorama (HDC0-7 by day,
## HNC at night, HDW/HNW in weather) as well as the clouds and sun.
static func _load_hs(dir: String, night: bool, weather: bool) -> Nfs3Horizon:
	var path := DataPath.find_ci(dir, "tr" + ("n" if night else "") + ("w" if weather else "") + ".ini")
	if path == "":
		return null
	var h := from_ini(FileAccess.get_file_as_string(path))
	if h == null:
		return null
	var fsh := Fsh.load_file(DataPath.find_ci(dir, "sky.qfs"))
	if fsh:
		var prefix := "H" + ("N" if night else "D") + ("W" if weather else "C")
		var tiles: Array[Image] = []
		for i in PANORAMA_TILES:
			if fsh.by_name.has(prefix + str(i)):
				tiles.append(fsh.by_name[prefix + str(i)])
		if h.has_pixmap and tiles.size() == PANORAMA_TILES:
			h.panorama = _stitch(tiles)
		h.clouds = fsh.by_name.get(("CLWN" if weather else "CLDN") if night else ("CLWD" if weather else "CLDD"))
		h.sun = fsh.by_name.get(("SNNW" if weather else "SUNN") if night else ("SUNW" if weather else "SUND"),
			fsh.by_name.get("SUNN" if night else "SUND"))
	return h


## Parses a High Stakes horizon .ini (see _load_hs); null when it has no [strip] section.
static func from_ini(text: String) -> Nfs3Horizon:
	var sec := {}
	var cur := {}
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("["):
			cur = {}
			sec[line.trim_prefix("[").trim_suffix("]").to_lower()] = cur
		elif "=" in line:
			cur[line.get_slice("=", 0).strip_edges()] = line.substr(line.find("=") + 1).strip_edges()
	if not sec.has("strip"):
		return null
	var s: Dictionary = sec.strip
	var c: Dictionary = sec.get("clouds", {})
	var f: Dictionary = sec.get("fog", {})
	var w: Dictionary = sec.get("weather", {})
	var l: Dictionary = sec.get("light", {})
	var lt: Dictionary = sec.get("lightning", {})
	var h := Nfs3Horizon.new()
	var num := func(d: Dictionary, key: String, fallback := 0.0) -> float:
		return float(d[key]) if d.has(key) else fallback
	var col := func(d: Dictionary, key: String, fallback := Color.GRAY) -> Color:
		var m := RegEx.create_from_string("(-?\\d+)\\D+(-?\\d+)\\D+(-?\\d+)").search(d.get(key, ""))
		if m == null:
			return fallback
		return Color8(clampi(int(m.get_string(1)), 0, 255), clampi(int(m.get_string(2)), 0, 255),
			clampi(int(m.get_string(3)), 0, 255))
	h.fog_color = col.call(f, "fogColor", Color.WHITE)
	h.fog_density = num.call(f, "fogDensity")
	h.fog_on_pixmap = num.call(f, "fogHorizon") * 100.0
	for r in int(num.call(f, "fogNumRegions")):
		var fr: Dictionary = sec.get("fog region %d" % r, {})
		if fr.is_empty():
			continue
		h.fog_regions.append({
			"colors": [col.call(fr, "s_color"), col.call(fr, "c_color"), col.call(fr, "e_color")],
			"densities": [num.call(fr, "s_density"), num.call(fr, "c_density"), num.call(fr, "e_density")],
			"slices": [int(num.call(fr, "startSlice")), int(num.call(fr, "centerSlice")), int(num.call(fr, "endSlice"))],
		})
	h.cloud_type = int(num.call(c, "cloudType"))
	h.cloud_bright = clampf(num.call(c, "cloudBright") / 255.0, 0.0, 1.0)
	h.cloud_variance = clampf(num.call(c, "cloudVariance") / 255.0, 0.0, h.cloud_bright)
	h.wind_mph = int(num.call(c, "windSpeed"))
	h.wind_dir = int(num.call(c, "windDir"))
	h.lightning_chance = maxi(int(num.call(lt, "lightningChance")), 0)
	h.lightning_ticks = maxi(int(num.call(lt, "lightningOffTicks")), 0)
	h.mirror = num.call(s, "hrzMirror") != 0.0
	h.radius = maxf(num.call(s, "hrzfRadius", 1500.0), 100.0)
	h.rotation = num.call(s, "hrzAngle") * 360.0   # a fraction of a turn
	h.has_pixmap = num.call(s, "hrzHasPMX") != 0.0
	var base: float = num.call(s, "hrzBottomYOff", -1200.0)
	h.band_base = base
	h.band_top = base + num.call(s, "hrzGouraudHeight", 1800.0)
	h.band_mid = base + num.call(s, "hrzGouraudMiddle", 1200.0)
	h.pixmap_top = base + num.call(s, "hrzPmxTop", 1350.0)
	h.pixmap_bottom = base + num.call(s, "hrzPmxBottom", 1150.0)
	h.earth_top = col.call(s, "hrzEarthTopColor")
	h.earth_base = col.call(s, "hrzEarthBotColor")
	h.sky_top = col.call(s, "hrzSkyTopColor", Color.SKY_BLUE)
	h.sky_sun = col.call(s, "hrzSunColor", Color.WHITE)
	h.sky_away = col.call(s, "hrzOppositeSunColor", Color.WHITE)
	h.precip = clampi(int(num.call(w, "type")), 0, Precip.SNOW) as Precip
	h.precip_start = int(num.call(w, "startSlice"))
	h.precip_end = int(num.call(w, "endSlice"))
	h.precip_fade = maxi(int(num.call(w, "fade")), 0)
	h.precip_cycle = PackedInt32Array([int(num.call(w, "stayTimeOn")), int(num.call(w, "fadeTimeOff")),
		int(num.call(w, "stayTimeOff")), int(num.call(w, "fadeTimeOn"))])
	# glowN=[alpha,r,g,b], blinks, shift, phase, size, (on s, off s), T<race-start light>
	var g: Dictionary = sec.get("track glows", {})
	var nums := RegEx.create_from_string("-?\\d+(\\.\\d+)?")
	for i in 32:
		var v: Array[float] = []
		for m in nums.search_all(g.get("glow%d" % i, "")):
			v.append(float(m.get_string()))
		if v.size() < 8:
			h.glows.append({})
			continue
		while v.size() < 10:   # many leave out the cycle (and T): 0
			v.append(0.0)
		h.glows.append({
			"color": Color8(clampi(int(v[1]), 0, 255), clampi(int(v[2]), 0, 255), clampi(int(v[3]), 0, 255),
				clampi(int(v[0]), 0, 255)),
			"blink": int(v[5]) if v[4] != 0.0 else -1,
			"phase": int(v[6]),
			"size": v[7],
			# The seconds are counted in the game's 64 ticks a second.
			"on": int(v[8]) * 64 if v[8] > 0.0 and v[9] > 0.0 else 0,
			"off": int(v[9]) * 64 if v[8] > 0.0 and v[9] > 0.0 else 0,
		})
	if h.glows.all(func(x: Dictionary) -> bool: return x.is_empty()):
		h.glows.clear()
	if l.has("AmbientRed"):
		h.ambient = Color(num.call(l, "AmbientRed") / 100.0, num.call(l, "AmbientGreen") / 100.0,
			num.call(l, "AmbientBlue") / 100.0)
	return h


static func _rgb(v: PackedInt32Array, i: int) -> Color:
	return Color8(clampi(v[i], 0, 255), clampi(v[i + 1], 0, 255), clampi(v[i + 2], 0, 255))


## The panorama tiles side by side, each scaled to the first tile's size.
## A Porsche Unleashed track's sky, Track/Sky/<name>.fsh (default.fsh without one): its
## "horz" image holds the horizon panorama as two 256 x 128 halves, one above the other,
## clear over the sky. Its sky tiles ("st1a" the sky, "sc1a" its cloud layer) are the time
## of day (sunset over Côte d'Azur and Auvergne, dusk in Monte Carlo); its dome (the .bin,
## not read) shades them, so their colours are taken most of the way from a plain day sky,
## no darker than a dusk. The game has no night: at night the same sky goes dark, and
## the ambient light with it (the baked colours are the day's).
static func _load_pu(crp_path: String, night := false) -> Nfs3Horizon:
	var sky_dir := DataPath.find_ci(crp_path.get_base_dir(), "Sky")
	var name := crp_path.get_file().get_basename().to_lower()
	var fsh := Fsh.load_file(DataPath.find_ci(sky_dir, name + ".fsh"))
	if fsh == null:
		fsh = Fsh.load_file(DataPath.find_ci(sky_dir, "default.fsh"))
	if fsh == null or not fsh.by_name.has("horz"):
		return null
	var h := Nfs3Horizon.new()
	var horz: Image = fsh.by_name.horz.duplicate()
	horz.convert(Image.FORMAT_RGBA8)
	var half := horz.get_height() / 2
	h.panorama = _stitch([horz.get_region(Rect2i(0, 0, horz.get_width(), half)),
		horz.get_region(Rect2i(0, half, horz.get_width(), half))])
	h.has_pixmap = true
	h.pixmap_top = 190.0
	h.pixmap_bottom = -25.0
	var top := _tile_colour(fsh.by_name.get("st1a"), Color(0.28, 0.48, 0.82))
	var low := _tile_colour(fsh.by_name.get("sc1a"), Color(0.72, 0.8, 0.9))
	h.sky_top = top
	h.sky_sun = low
	h.sky_away = low.lerp(top, 0.3)
	h.fog_color = low
	h.fog_density = 8.0
	h.fog_on_pixmap = 30.0
	h.earth_top = low.darkened(0.3)
	h.earth_base = low.darkened(0.5)
	h.ambient = Color.WHITE
	if night:
		h.sky_top = Color(0.02, 0.03, 0.07)
		h.sky_sun = Color(0.07, 0.08, 0.14)
		h.sky_away = Color(0.05, 0.06, 0.1)
		h.fog_color = Color(0.05, 0.06, 0.09)
		h.earth_top = Color(0.03, 0.03, 0.04)
		h.earth_base = Color(0.02, 0.02, 0.03)
		h.ambient = Color(0.22, 0.24, 0.32)
	return h


## A sky tile's average colour, 60% over `day` (the plain sky's), at least 35% bright.
static func _tile_colour(img: Variant, day: Color) -> Color:
	if img == null:
		return day
	var im: Image = (img as Image).duplicate()
	im.convert(Image.FORMAT_RGBA8)
	im.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	var c := day.lerp(im.get_pixel(0, 0), 0.6)
	c.a = 1.0
	return c.lightened(0.35 - c.get_luminance()) if c.get_luminance() < 0.35 else c


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
