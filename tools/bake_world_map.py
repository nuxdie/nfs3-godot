#!/usr/bin/env python3
"""Bakes data/world_map.png for the track picker's map from Natural Earth (world-atlas topojson):
red = land (antialiased), green = country borders. Miller projection, lon -180..180 across the
width, lat MAX_LAT at the top; TrackMapWorld.project() must match.
  curl -LO https://cdn.jsdelivr.net/npm/world-atlas@2/land-50m.json
  curl -LO https://cdn.jsdelivr.net/npm/world-atlas@2/countries-50m.json
  tools/bake_world_map.py land-50m.json countries-50m.json data/world_map.png"""
import json, math, sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter

W, H = 4096, 2048
SS = 2                      # supersampling
MAX_LAT, MIN_LAT = 84.0, -60.0


def miller(lat):
    return 1.25 * math.log(math.tan(math.pi / 4 + 0.4 * math.radians(lat)))


TOP = miller(MAX_LAT)
SCALE = W / (2 * math.pi)   # px per radian, both axes
assert abs((TOP - miller(MIN_LAT)) * SCALE - H) < H * 0.06, (TOP - miller(MIN_LAT)) * SCALE


def proj(lon, lat, s=1):
    lat = max(min(lat, 89.0), -89.0)
    return ((math.radians(lon) + math.pi) * SCALE * s, (TOP - miller(lat)) * SCALE * s)


def arcs_of(topo):
    t = topo.get("transform")
    out = []
    for arc in topo["arcs"]:
        x = y = 0
        pts = []
        for p in arc:
            if t:
                x += p[0]; y += p[1]
                pts.append((x * t["scale"][0] + t["translate"][0], y * t["scale"][1] + t["translate"][1]))
            else:
                pts.append(tuple(p))
        out.append(pts)
    return out


def ring(arcs, idx):
    pts = []
    for i in idx:
        a = arcs[i] if i >= 0 else arcs[~i][::-1]
        pts.extend(a if not pts else a[1:])
    return pts


def polys(geom):
    if geom["type"] == "Polygon":
        return [geom["arcs"]]
    if geom["type"] == "MultiPolygon":
        return geom["arcs"]
    if geom["type"] == "GeometryCollection":
        return [p for g in geom["geometries"] for p in polys(g)]
    return []


def unwrap(pts):
    out = [pts[0]]
    for lon, lat in pts[1:]:
        while lon - out[-1][0] > 180:
            lon -= 360
        while lon - out[-1][0] < -180:
            lon += 360
        out.append((lon, lat))
    return out


def split_dateline(pts):
    """Rings crossing the antimeridian (Russia's, Fiji's) as runs that don't jump across."""
    runs, cur = [], [pts[0]]
    for a, b in zip(pts, pts[1:]):
        if abs(b[0] - a[0]) > 180:
            runs.append(cur); cur = []
        cur.append(b)
    runs.append(cur)
    return runs


def main(land_path, countries_path, out_path):
    land = json.load(open(land_path))
    la = arcs_of(land)
    mask = Image.new("L", (W * SS, H * SS), 0)
    d = ImageDraw.Draw(mask)
    for obj in land["objects"].values():
        for poly in polys(obj):
            for k, r in enumerate(poly):
                # Unwrapped across the dateline (Russia's ring), drawn again a world over each way.
                pts = unwrap(ring(la, r))
                for shift in (-360, 0, 360):
                    xy = [proj(lon + shift, lat, SS) for lon, lat in pts]
                    d.polygon(xy, fill=255 if k == 0 else 0)
    mask = mask.resize((W, H), Image.LANCZOS)

    cty = json.load(open(countries_path))
    ca = arcs_of(cty)
    borders = Image.new("L", (W, H), 0)
    bd = ImageDraw.Draw(borders)
    # Arcs shared by two countries are borders (coast arcs belong to one).
    use = {}
    for obj in cty["objects"].values():
        for poly in polys(obj):
            for r in poly:
                for i in r:
                    k = i if i >= 0 else ~i
                    use[k] = use.get(k, 0) + 1
    for k, n in use.items():
        if n < 2:
            continue
        for run in split_dateline(ca[k]):
            if len(run) > 1:
                bd.line([proj(lon, lat) for lon, lat in run], fill=255, width=1)
    # Islands' coasts can come out as shared arcs: keep the borders that run inland.
    borders = ImageChops.multiply(borders, mask.point(lambda v: 255 if v > 250 else 0).filter(ImageFilter.MinFilter(5)))
    img = Image.merge("RGB", (mask, borders, Image.new("L", (W, H), 0)))
    img.save(out_path, optimize=True)
    print(out_path, img.size)


if __name__ == "__main__":
    main(*sys.argv[1:4])
