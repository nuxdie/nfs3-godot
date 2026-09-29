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

### Need for Speed: High Stakes tracks and cars

With a High Stakes install present its 19 tracks join the list (after NFS3's): the ten
new ones (Celtic Ruins, Landstrasse, Dolphin Cove, Kindiak Park, Route Adonf, Durham Road,
Snowy Ridge, Raceway 1–3) and its remakes of the NFS3 tracks, marked "HS". Its 28 cars
(pursuit versions included) join the car list after NFS3's, those NFS3 also has marked "HS".
On its tracks the police and traffic are its own. The first `Data`
folder that contains `tracks` and `gameart` wins:

1. `NFS4_DATA` environment variable
2. `../OpenNFS/resources/NFS_4/data`
3. `../need-for-speed-high-stakes/drive_c/Program Files (x86)/Electronic Arts/Need for Speed - High Stakes/Data`
4. The same under `~/Games`

| File | Used for |
|---|---|
| `Tracks/<name>/tr.frd` | Geometry, baked lighting, scenery, animated objects and physics props, the virtual road (it has no `.col`) |
| `Tracks/<name>/tr0.qfs` | Textures; the ids skip the `<mirrored>` copies of lettered ones (for mirrored tracks) |
| `Tracks/<name>/tr.ini`, `trn.ini`, `trw.ini`, `trnw.ini` | The same sky, fog, weather and ambient settings as NFS3's `.hrz`, as named keys |
| `Tracks/<name>/sky.qfs` | Horizon panorama (`HDC0-7` day, `HNC` night, `HDW`/`HNW` weather), clouds, sun and moon |
| `GameArt/sfx.fsh` | Lane marking sprites |
| `Cars/<id>/car.viv` → `car.fce`, `car00.tga`, `carp.txt`, `fedata.eng` | Cars, as NFS3's: FCE4 mesh (high body, mirrors, T-top, pop-up lamps, wheels), skin, driving model (its 500 rpm torque steps resampled to NFS3's 256), name |
| `Cars/traffic/pursuit/*`, `Cars/traffic/<name>` | Police cars and traffic for its tracks (the snowplow only on Snowy Ridge) |

High Stakes draws its tracks at 1/1.3 of NFS3's scale (its remakes are the NFS3 tracks
shrunk exactly 1.3 times), so they're scaled up to fit the NFS3 cars. Its polys have no
surface flags: those between the virtual road's walls, facing up, are the drivable ones.
The night versions some tracks have (`trn.frd`, `trn0.qfs`) aren't used yet: night is the
day track, darkened, as on the NFS3 tracks.

Its skins mark the paint with alpha ~224 and the interior with ~160 (NFS3: ~117 for paint);
they're converted on loading, the interior tinted with the car's first interior colour. Unlike
NFS3 it honours the TGA's top-down flag. Not used: the driver and cockpit (hidden behind the
opaque glass), the damaged-mesh tables, `dash.fce`, the busting officer (`cop.fce`) and the
helicopter.

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
- **Spectate** – a Single Race with the AI driving your car too. ←/→ (or Q/E,
  Tab, PgUp/PgDn) switch which racer the camera follows; the results come up
  once the whole field has finished.

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

## Graphics quality

Integrated GPUs and dual-core CPUs start on **Low** (Settings → Graphics), which is tuned to
hold 60 fps on a Haswell HD GT1 with a 1.4 GHz dual-core Celeron in every mode, by day or
night, rain or not, including a Hot Pursuit at heat 3. On Low:

- the 3D view renders at up to 75% resolution, and `DynamicResolution` lowers that in steps
  (to 50% at the least; the HUD stays sharp) where the GPU is missing frames, and raises it
  back once it keeps up;
- the procedural track's road, land, cars and buildings use cheaper shader variants (fewer
  texture samples, no clearcoat); its land and road are merged into a few big meshes, and
  scenery is drawn out to 60% of its usual distance, cars to 250 m;
- brake, reversing and siren lamps glow but don't light their surroundings, and the rear-view
  mirror starts off (M turns it on).

Whatever the quality, far-off traffic glides along its lane rather than being simulated,
cars out of sight skip their wheel, body and tyre effects, and AI cars held still (parked
cruisers, the grid) sleep until they're hit or drive off.

## Layout

```
scripts/io/        file formats: qfs.gd (RefPack), fsh.gd, viv.gd, nfs3_track.gd, nfs3_car.gd,
                   nfs3_horizon.gd (.hrz sky/fog, and High Stakes' .ini), nfs4_track.gd (High Stakes
                   tracks, read into nfs3_track.gd's data), data_path.gd (case-insensitive lookups)
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
                   sign_art.gd, breakables.gd (its signs, chevrons, cones, sawhorses and fence
                   panels, drawn batched until a car knocks one flying as a KnockableProp; its
                   guardrails bend as the NFS3 tracks' do, through Guardrails), parked_cars.gd
                   (real traffic cars the race parks along its streets and lots, asleep till touched),
                   track_path.gd (virtual road), keyframe_mover.gd
scripts/vehicle/   car.gd (raycast suspension, tyre friction circle, auto gearbox),
                   player_controller.gd, ai_controller.gd (racer / traffic / cop), procedural_car.gd,
                   car_damage.gd (dents and wear from crashes; NFS3 had none, Settings → Car damage)
scripts/race/      race.gd (spawning, laps, positions, pursuit rules), spike_strip.gd, chase_camera.gd,
                   track_world.gd (the track plus its sun, sky, fog and ambient for the conditions),
                   weather.gd (fog regions, rain/snow, lightning and thunder, wet/snowy grip),
                   rain_cover.gd (top-down height map: no rain under bridges or in tunnels),
                   dynamic_resolution.gd (3D resolution that gives way when the GPU misses frames),
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
                   (--ram, procedural track: drives into some knockable props and a guardrail
                   instead, printing what came loose and bent, shots/ram_*.png)
                   (--perf: frame-time report every --perfwin=S (5) seconds and at the end - fps,
                   percentiles, missed frames, physics/process/draw time, GPU time, 3D scale -
                   run without --disable-vsync to see what players get; --heat=N puts every cop
                   on the player at heat N; --opponents=N, --quality=0..2, --scale=F override;
                   --hide=cars,mm,ground,road,std,rails,precip,mirror,hud and --kill=audio,parked,
                   particles,effects,hud switch things off to see what they cost; --drawstats
                   counts the draws in view by kind)
                   (--resttest, --ghosttest, --dentbench check sleeping cruisers, far-off traffic
                   and the cost of a crash's dent)
                   (--stoplog prints where any car stops dead and what solid is around it)
tools/gdprof.py    per-function GDScript times and per-pass GPU times of a run, through the remote
                   debugger (Python, no editor needed; usage at the top of the file)
tools/track_shots.gd photograph a track's road at points round the lap (fractions 0..1), with
                   draw-call and triangle counts: godot --path . -- --trackshots <track> [0.25 ...]
                   (--night / --weather; --up= --back= --ahead= --side= --lookside= aim the eye;
                   --tag=NAME; --hazards lists solid scenery inside the procedural track's walls)
tools/postcards.gd re-render the menu's track pictures and copy them to shots/:
                   godot --path . -- --postcards [track ...]
tools/car_shots.gd contact sheet of every traffic car, cruiser or player car, front and rear, saved to shots/:
                   godot --path . -- --carshots [traffic|cops|cars|hstraffic|hscops] [id ...] [--track=trk000 [--night]]
                   (--big / --low / --yaw=DEG / --wire for close inspection)
tools/car_calib.gd flat-out drag test of every car against the original game's acceleration table:
                   godot --headless --path . -s tools/car_calib.gd [-- name-filter]
```

## Not done yet

- Original sounds/music (`.bnk`) – audio is synthesised instead.
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
