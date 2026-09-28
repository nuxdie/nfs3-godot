# NFS3 Revival (Godot 4)

A *Need for Speed III: Hot Pursuit*-style arcade racer for Godot 4.7. All game
code is original GDScript; it loads **tracks and cars from your own NFS3
install at runtime** (nothing from the game is copied into this project). With
no game data present it falls back to a procedural circuit and stand-in cars,
so the project always runs.

## Run

```bash
godot --path /home/n/NFSHS-revive/nfs3-godot          # play
godot -e --path /home/n/NFSHS-revive/nfs3-godot       # open in the editor
```

(`/home/n/OpenSkyRPG/3d-rpg-game-v4/godot` is a Godot 4.7.2 binary on this machine.)

## Game data

The first folder that contains `gamedata/tracks` wins:

1. `NFS3_DATA` environment variable
2. `../OpenNFS/resources/NFS_3` (the lowercased copy next to this project)
3. `./nfs3_data`
4. The Lutris install under `~/Games/need-for-speed-iii-hot-pursuit/...`

File lookups are case-insensitive, so a raw Windows install works too.
What's read:

| File | Used for |
|---|---|
| `tracks/trkNNN/trNN.frd` | Track geometry, per-vertex baked lighting, scenery, animated objects and textures (fire), drivable-surface flags (invisible walls follow their edge) |
| `tracks/trkNNN/trNN.col` | Virtual road (AI line, lap progress, respawns), global scenery |
| `tracks/trkNNN/trNN0.qfs` | Track textures (RefPack-compressed FSH); the first 8 are the horizon panorama |
| `tracks/trkNNN/3trNN.hrz`, `3trNNn.hrz`, `3trNNw.hrz`, `3trNNnw.hrz` | Sky gradient, horizon/cloud placement, fog colour/density and fog regions, ambient light, lightning, rain/snow and its on/off cycle (day / night, clear / weather) |
| `tracks/trkNNN/sky.fsh` | Cloud layer and sun/moon sprites (clear and weather) |
| `render/pc/weather.fsh` | Raindrop and snowflake sprites |
| `carmodel/*/car.viv` → `car.fce`, `car00.tga` | Car mesh, wheels, skin, paint colours |
| `car.viv` → `carp.txt` | All of the driving model: engine, automatic gearbox, drive split (AWD), brakes and ABS, pedal and steering ramps, turning circle, grip and its front/rear balance, load transfer, downforce and spoiler, slide assists, tyres, body roll; the AI's bend speeds; drag fitted to the original acceleration table (see `Car._load_spec`) |
| `car.viv` → `fedata.eng` | Car names for the menu |
| `carmodel/traffic/pursuit/*` | Police cars |
| `carmodel/traffic/NNNN` | Traffic |

## Modes

- **Single Race** – up to 7 AI opponents, 1–8 laps.
- **Hot Pursuit** – one rival plus police: three cruisers parked on the verge
  and one on patrol. Speed past one (> ~120 km/h) and it gives chase with
  lights and siren – after you or the rival, whoever it saw. The first cop on a
  car rams it (or spins it out from alongside); the second overtakes and
  blocks. Stop with a cop on you and you're busted: two tickets, the third is
  an arrest (a busted rival just loses a few seconds). The heat rises every 20 s
  of chase: backup units join from behind, heat 2 brings roadblocks and heat 3
  lays a spike strip across the gap (flat tyres: half the grip and top speed
  for 14 s, or until a reset). Get > 380 m away to evade; cops then drive back to their post.
- **Time Trial** – just you and the clock.
- **Free Roam** – no laps, traffic and a couple of cops (same pursuit rules,
  but tickets never end the session).

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Accelerate / brake-reverse | ↑ / ↓ (W / S) | RT / LT |
| Steer | ← → (A D) | Left stick |
| Handbrake | Space | B |
| Camera (chase / far / bumper) | C | Y |
| Look back | B | LB |
| Reset car to road | R | Back |
| Toggle rear-view mirror | M | |
| Pause | Esc / P | Start |

## Layout

```
scripts/io/        file formats: qfs.gd (RefPack), fsh.gd, viv.gd, nfs3_track.gd, nfs3_car.gd,
                   nfs3_horizon.gd (.hrz sky/fog), data_path.gd (case-insensitive lookups)
scripts/track/     nfs3_track_builder.gd (meshes, Texture2DArray, collision, walls),
                   procedural_track.gd (the no-data circuit's layout: lap, heights, tunnel, bridges,
                   and the roads off it: town streets, farm lanes, forest roads, the campground's
                   road, a lookout, gravel shortcuts across two big bends),
                   proc_ground.gd (its road and side roads, cuttings and banks, terrain, mountains,
                   water, tunnel, bridges), proc_scenery.gd (its town, farms, forest, rails, lamps),
                   proc_places.gd (its named places - the town's shops, hotel, church and water
                   tower, gas station, diner, farms, campground, lookout, motel - and the signs and
                   billboards that name them and point to them with real distances),
                   proc_signs.gd (traffic signs: speed limits, warnings, stop signs, street names,
                   route shields, guide signs, mile markers, barricades) painted into one atlas by
                   sign_art.gd,
                   track_path.gd (virtual road), keyframe_mover.gd
scripts/vehicle/   car.gd (raycast suspension, tyre friction circle, auto gearbox),
                   player_controller.gd, ai_controller.gd (racer / traffic / cop), procedural_car.gd,
                   car_damage.gd (dents and wear from crashes; NFS3 had none, Settings → Car damage)
scripts/race/      race.gd (spawning, laps, positions, pursuit rules), spike_strip.gd, chase_camera.gd,
                   track_world.gd (the track plus its sun, sky, fog and ambient for the conditions),
                   weather.gd (fog regions, rain/snow, lightning and thunder, wet/snowy grip),
                   rain_cover.gd (top-down height map: no rain under bridges or in tunnels),
                   reflections.gd (wet road sheen, lamp streaks and High-quality mirror; the
                   reflection probe on the player's car)
scripts/ui/        main_menu.gd (showroom front end), track_postcards.gd (renders each track by day and
                   night in the background for the menu backdrop, cached in user://postcards), hud.gd (tach, map, mirror, pause, results),
                   ui_kit.gd (palette, fonts, slanted shapes, key hints), selector_row.gd,
                   action_list.gd (pause/results menus), track_map.gd, car_stats.gd
fonts/             Barlow / Barlow Condensed (SIL Open Font License, see fonts/OFL.txt)
scripts/audio/     car_audio.gd (synthesised engine, tyre squeal, siren)
shaders/           track.gdshader (unshaded, vertex-lit like the original; wet road), track_additive.gdshader
                   (glows, fire, light shafts), car.gdshader (paint mask), precipitation.gdshader
                   (rain/snow wrapped around the camera on the GPU), proc_road.gdshader and
                   proc_ground.gdshader (the procedural track's asphalt and land)
tools/autotest.gd  scripted run for testing: godot --path . -- --autotest <trk000|procedural|menu> [mode] [car] [--duration=S]
                   (add --settings with menu to photograph the settings panel)
                   (--night / --weather set the conditions, --tag=NAME prefixes the screenshots)
                   (--classic drops the body sway and progressive grip, --no-traffic empties the road)
tools/track_shots.gd photograph a track's road at points round the lap (fractions 0..1), with
                   draw-call and triangle counts: godot --path . -- --trackshots <track> [0.25 ...]
                   (--night / --weather; --up= --back= --ahead= --side= --lookside= aim the eye;
                   --tag=NAME; --hazards lists solid scenery inside the procedural track's walls)
tools/postcards.gd re-render the menu's track pictures and copy them to shots/:
                   godot --path . -- --postcards [track ...]
tools/car_shots.gd contact sheet of every traffic car, cruiser or player car, front and rear, saved to shots/:
                   godot --path . -- --carshots [traffic|cops|cars] [id ...] [--track=trk000 [--night]]
                   (--big / --low / --yaw=DEG / --wire for close inspection)
tools/car_calib.gd flat-out drag test of every car against the original game's acceleration table:
                   godot --headless --path . -s tools/car_calib.gd [-- name-filter]
```

## Not done yet

- Original sounds/music (`.bnk`) – audio is synthesised instead.
- Lane-marking textures that live in `render/pc/sfx.fsh` are skipped.
- Mirrored/reverse tracks, split-screen.
- The Knockout/tournament structure and car unlocks.
- The car body collides as a box; FCE dummies (light positions) are unused.
- Scenery collision is guessed from the textures (the track files carry no collision flag):
  opaque objects (buildings, walls, poles) are solid, sign-sized ones are knocked over, and
  cut-out foliage and glows are passable except for a solid trunk or post where the
  billboard's texture touches the ground (trees, cacti, lamp posts). Cut-out fence and
  railing panels standing on the road surface are knocked over like signs (solid when
  longer than 10 m); those along its edge are left to the invisible walls. The AI steers around
  cars only, so it can snag on a tree or sign that stands on the drivable surface.
