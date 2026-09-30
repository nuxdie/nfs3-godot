# NFS Revival (Godot 4)

A *Need for Speed III: Hot Pursuit* and *Need for Speed: High Stakes*-style arcade racer
for Godot 4.7. All game code is original GDScript; it loads **tracks and cars from your
own NFS3 and/or High Stakes install at runtime** (nothing from the games is copied into
this project). With no game data present it falls back to a procedural circuit and
stand-in cars, so the project always runs.

(It was called *NFS3 Revival* before High Stakes came in. Godot keeps the save data under
the project's name, so on the first start the settings, tournament progress and track
postcards are copied over from the old `NFS3 Revival` folder.)

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
| `car.viv` → `carp.txt` | All of the driving model: engine, automatic gearbox, drive split (AWD), brakes and ABS, pedal and steering ramps, turning circle, grip on slip-angle tyres (their peak from the tyre sizes), the weight split (its "front grip bias", which High Stakes' own cars fill with their showroom weight split) and the centre of mass's height from the g transfer factor, so load moves between the tyres on the springs, downforce and the spoiler over the rear axle, slide assists, body roll; the AI's bend speeds; drag fitted to the original acceleration table (see `Car._load_spec`) |
| `car.viv` → `fedata.eng` | Car names for the menu |
| `car.viv` → `car.bnk`, `ocar.bnk` | Engine sound (on and off the throttle, pitched with rpm) of the car you drive / the cars around you, and its horn |
| `audio/sfx/gen.bnk` | Tyres sliding (tarmac, wet, gravel), body scraping, crashes, road noise, the horn of cars without their own |
| `audio/sfx/siren.bnk`, `audio/sfx/rain.bnk` | Police siren; rain on the car and thunder |
| `audio/sfx/genocar.bnk`, `otruck.bnk` | Traffic engines and horns (trucks and buses by weight) |
| `audio/speech/english/cnteng.bnk` | The countdown: "three, two, one, go" |
| `audio/speech/english/lapeng.bnk`, `vocasst.bnk` | Lap calls ("lap 3", "final lap", "best lap"), your place as it changes ("second place!", "you're in the lead!"), how far the leader is ahead at the line ("you're 3 seconds back") and where you finished |
| `audio/speech/english/copspch.bnk`, `dispNN.bnk`, `offNN{a,b,c}.bnk` | Hot pursuit: the cop's loudhailer, warnings and arrests; the police radio, officers (three voices per track) calling in, the dispatcher answering, speed reports, roadblock and spike-strip requests, losing you, arresting you. MicroTalk-coded (`ea_microtalk.gd`); which clip says what was found by transcribing them |
| `audio/sfx/fesfx.bnk` | Menu clicks |
| `audio/pc/<song>rock.mus`, `<song>tech.mus` + `.lin` | Race music: each track's song, rock or techno at random, played through as its `.lin` orders the sections, looping (the four tracks without a song borrow one) |
| `audio/pc/show1..8.mus` + `.map` | Menu music; `.map`s branch at random between sections by their percentages |
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
| `Tracks/<name>/tr0.qfs` | Textures; the ids skip the `<mirrored>` copies of lettered ones (for mirrored tracks), and those tagged `<additive>` (fire, glows, light rays) are drawn additively |
| `Tracks/<name>/tr.ini`, `trn.ini`, `trw.ini`, `trnw.ini` | The same sky, fog, weather and ambient settings as NFS3's `.hrz`, as named keys |
| `Tracks/<name>/sky.qfs` | Horizon panorama (`HDC0-7` day, `HNC` night, `HDW`/`HNW` weather), clouds, sun and moon |
| `GameArt/sfx.fsh` | Lane marking sprites |
| `Cars/<id>/car.viv` → `car.fce`, `car00.tga`, `carp.txt`, `fedata.eng` | Cars, as NFS3's: FCE4 mesh (high body, mirrors, T-top, pop-up lamps, wheels, and the driver and cockpit behind see-through windows), its damaged copy of the body (the dents), skin, driving model (its 500 rpm torque steps resampled to NFS3's 256), name |
| `car.viv` → `dash.fce`, `dash00.tga` | The in-car view: dashboard, seats, doors, steering wheel, speedo and rev needles, the dials lit at night |
| `car.viv` → `careng.bnk`, `careng.ctb`, `careng.ltb`, `ocareng.bnk` | Engine sound: up to 14 loops recorded at different rpm, faded in and out along the rev range by the tables, on and off the throttle, exhaust against engine (as the game's `AudioEng`); the simpler one for the cars around you. The shared banks under `Audio/Sfx` stand in for NFS3's when it isn't installed |
| `Audio/Speech/English/helicop.bnk` | The helicopter on the police radio: calling in, airborne, spotting you, your speed |
| `Audio/Speech/English/*.bnk` | Without NFS3: the same countdown, lap and co-driver calls and loudhailer (the banks match NFS3's line for line), and its `dispatch` / `officer1..3` radio in place of NFS3's per-track voices |
| `Audio/Music/game1..16.asf`, `menu1..4.asf` | Music for its own tracks (its NFS3 remakes play NFS3's songs when that's installed) and, without NFS3, the menus |
| `Cars/traffic/pursuit/*`, `Cars/traffic/<name>` | Police cars and traffic for its tracks (the snowplow only on Snowy Ridge) |
| `Cars/traffic/pursuit/*/car.viv` → `cop.fce`, `cop.art` | The officer who walks up to a busted car |
| `Cars/traffic/choppers/*/car.viv` → `hel.fce`, `hel00.tga` | The police helicopter |
| `car.viv` → `fedata.eng` (all of its strings) | Engine, power, 0-60 and price over the showroom car; the paints by name (the race options' Paint row); make and model for the one-make cups |
| `Tracks/<name>/trn.frd`, `trn0.qfs` | Night versions (street lamps and lit windows baked in), raced at night where a track has one |
| `Tracks/<name>/spdfa.bin`, `spdra.bin` (NFS3: `speedsf.bin`, `speedsr.bin`) | The original AI's tables: per road node a target speed (mph), and in High Stakes its racing line, which the racers drive (a quarter faster round Celtic Ruins than their own line); traffic and patrols keep to 80% of the speeds through bends |
| `Tracks/<name>/tr.frd` virtual road | Per slice, besides the walls: the traffic lanes each side of the centre line and their widths, which traffic keeps to (NFS3's `tr.col` only has the mask of paved lanes; the traffic lanes are estimated from it) |
| `Tracks/<name>/tr00.can`, `tr00a.can` (NFS3: `trNN00.can`) | The fly-by round the grid before the countdown (Settings → Intro; any key skips) |
| `Tracks/<name>/tr.cam` (NFS3: `trNN.ccm`) | Trackside cameras for the TV camera view (C) |
| `GameArt/cone`, `haybale`, `median`, `flare` `.fce`/`.art` | Round its roadblocks: cones funnelling to the gap, medians along the edges, hay bales, flares burning (lit at night) |
| `GameArt/cop0.fce` | The officer out of NFS3's cruisers, which have none |
| `GameArt/plate.fsh` | Licence plates (US or European, by the car's `:LICENSE` dummy) with a registration of their own |
| `GameArt/hud98.qfs`, `hud0.pos` | Its speedometer and the rev counter for the car's redline, where it put them (Settings → HUD → Dials: HS · top; or HS · bottom, together at the bottom centre) |
| `FeArt/slides/tN_00.qfs`, `Showcase/art/sl<car>01.qfs` | Its track slides and showroom photos in the menus |
| `Text/tierdef.cdb`, `circdef.cdb` | Its tournaments (Tournaments on the home screen): see below |

High Stakes draws its tracks at 1/1.3 of NFS3's scale (its remakes are the NFS3 tracks
shrunk exactly 1.3 times), so they're scaled up to fit the NFS3 cars. Its polys have no
surface flags: those between the virtual road's walls, facing up, are the drivable ones.
Those walls come per slice in coarse ~5 m steps that jump about: where one steps in across
ground still level with the road (a run-off's end, the Dolphin Cove gully) it's drawn in
gradually instead, so it doesn't stop the car dead in open grass. Its objects of type 2
(lamp posts, forest cards, bushes, icicles) are billboards, turned to face the camera.
Where a track has no night version, night is the day track darkened, as on the NFS3 tracks.

Its skins mark the paint with alpha ~224 and the interior with ~160 (NFS3: ~117 for paint);
they're converted on loading, the interior tinted with the car's first interior colour. Unlike
NFS3 it honours the TGA's top-down flag. Its windows are the triangles flagged `0x2E`; its body
parts (body, mirrors, T-top, cockpit, driver) are merged into one mesh and the windows into a
second. Crashes bend the body toward the damaged copy every FCE4 carries, vertex for vertex,
rather than NFS3 cars' made-up crumple. The dials' scales aren't in `dash.fce`: the speedo
needle reads to a little past the car's top speed, the rev counter to a quarter past redline.
Crashes bend a panel at a time (the triangles' flags from bit 11 up name the panel), the
damaged copy's normals coming with it.

**Upgrades** (race options, per car): level 1 suspension, 2 aero, 3 engine, cumulative, each
multiplying acceleration, braking, handling and top speed as the PlayStation version's
`ZTUNING.BIN` has them (the PC version keeps them in the program); rivals stock, as upgraded
as you or fully (Settings). **Layouts**: reverse (the lap run the other way round), mirrored
(every position flipped and each quad's corners swapped, which keeps lettering readable
without its `<mirrored>` texture copies) and both.

**Tournaments**: the 11 of `tierdef.cdb` (European Tour, High Stakes Tour, ... Tournament of
Champions) and their 32 circuits in `circdef.cdb`: races on given tracks, reversed, mirrored,
at night or in the wet; a field and laps; an entry fee and prize money per place; knockouts
(the last car out each race) and one-off races for a car. Points per race 10-8-6-5-4-3-2-1,
the prize by the final standing; winning every circuit of a tournament opens the ones it
unlocks. Money is kept in `user://career.cfg`; cars and upgrades stay free. The circuits'
race flags are read as reverse, mirror, night, weather, which order isn't certain.

Not used: the pursuit cars' alternative interiors (`:OND`, `:OLD`); `dash.fsh` (the dash skin
again, 8-bit); `GameArt/cop1-4` (skins without a mesh); `heights.sim` (one constant per track);
the second paint and driver hair colour tables (the skins carry no mask for them); the other
languages' texts; movies.

## Modes

- **Single Race** – up to 7 AI opponents, 1–8 laps.
- **Hot Pursuit** – up to seven rivals plus police: three cruisers parked on
  the verge and one on patrol (one more parked for every two rivals past the
  first). Speed past one (> ~120 km/h) and it gives chase with
  lights and siren – after you or the rival, whoever it saw. The first cop on a
  car rams it (or spins it out from alongside); the second overtakes and
  blocks. Stop with a cop on you and you're busted: two tickets, the third is
  an arrest (a busted rival just loses a few seconds). The heat rises every 20 s
  of chase: backup units join from behind, heat 2 brings roadblocks and heat 3
  lays a spike strip across the gap (flat tyres: half the grip and top speed
  for 14 s, or until a reset). Get > 380 m away to evade; cops then drive back to their post.
  With High Stakes data, its helicopter joins the chase from heat 2 (searchlight on you by
  night), and its cruisers' officers walk up to write the ticket while the cruiser waits.
- **Traffic** (every mode but Time Trial) follows High Stakes' own rules: it keeps to the
  track's lanes, on the left in England (Celtic Ruins, Durham Road); cruises at 75% of the
  local speed limit (the original's per-track limits: 35/50/65 mph, 50/100 km/h, 50/70 mph),
  each car 0–30% under that; comes the other way slower the faster you're going (down to
  32 km/h); pulls over for sirens (or stops, or now and then carries on) and waits at a
  roadblock; and is kept where the racers are, brought back 280–340 m up or down the road
  once it's left them all behind. It also keeps its distance, changes lane round a hold-up,
  honks at a head-on and, coming the other way, now and then just because.
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
| Camera (chase / far / bumper / in-car on High Stakes cars / TV) | C | Y |
| Look back | B | LB |
| Reset car to road | R | Back |
| Toggle rear-view mirror | M | |
| Hide / show the HUD | F1 | |
| Pause | Esc / P | Start |
| Fullscreen | F11 / Alt+Enter | |

### Menu

The home screen lists what there is to do: **Quick start** (the last setup, straight into
the race), the five modes, **Tournaments** (with High Stakes), Settings and Quit. A mode
then takes three steps, each with the screen to itself:

1. **Track**: every track as a postcard, searchable, by game;
2. **Car**: every car on the turntable with its ratings, searchable, by class and game, sortable;
3. **Options**: your car's paint and upgrades; the track's layout, time and weather; the
   laps, rivals and traffic (only those the mode has), with a line on what each does.

The step bar along the top shows what's picked in each step and goes back to any of them
(the mode name back to the home screen). A tournament takes two: the circuit, then the car.

Everything is clickable; the keyboard and pad do the same:

| Action | Keyboard | Gamepad |
|---|---|---|
| Move / change | ↑↓ / ←→ (or the mouse wheel over an option) | D-pad |
| Next step / start | Enter | A |
| Back a step | Esc (right click in a list) | B |
| Settings | Tab (a click in the track and car lists) | Y |
| Quit | Esc twice on the home screen | B twice |

In the track and car lists, type to search; Tab (LB / RB) steps the class or game
filter; ←→ changes the car sort (class, name, or any of the four ratings). The arrows
pick as they move; pointing at an item only previews it, and a click picks it and goes on.
In the tournaments, ↑↓ go through the circuits and ←→ through the tournaments.

Starting a race fades to its loading screen: the track's picture, what's being raced (the
mode, or the tournament and which race of the circuit), the race's facts, the map, your car,
a tip, and a bar through the loading's stages. The track is read and built on a worker
thread, so the screen keeps moving while it loads.

Settings has two pages (Q / E): **General** (graphics, sound, gameplay, the controls) and
**HUD**: the dials (this game's, or High Stakes' either side of the mirror as it had them or
at the bottom centre), and each part of the race HUD on or off (speed, standings,
police, lap, map, mirror, messages, countdown, light bar, key hints), with a sketch of the
screen showing where each one is. The pause menu has Settings too, on the HUD page, with
the race behind it changing as you go.

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
                   tracks, read into nfs3_track.gd's data), fce4.gd (High Stakes' dashboard, officer and
                   helicopter models), ea_bnk.gd (EA sound banks: PCM and EA-XA ADPCM),
                   ea_music.gd (streamed .asf / .mus music), ea_microtalk.gd (EA's speech codec),
                   data_path.gd (case-insensitive lookups)
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
                   officer.gd and helicopter.gd (High Stakes' busting officer and police helicopter),
                   track_world.gd (the track plus its sun, sky, fog and ambient for the conditions),
                   weather.gd (fog regions, rain/snow, lightning and thunder, wet/snowy grip),
                   rain_cover.gd (top-down height map: no rain under bridges or in tunnels),
                   dynamic_resolution.gd (3D resolution that gives way when the GPU misses frames),
                   reflections.gd (wet road sheen, lamp streaks and High-quality mirror; the
                   reflection probe on the player's car)
scripts/ui/        main_menu.gd (the front end: home screen, setup steps, showroom), menu_list.gd (home
                   screen list), step_bar.gd, hint_bar.gd, big_button.gd, tournament_panel.gd, loading_screen.gd,
                   track_browser.gd / car_browser.gd (on browser_base.gd:
                   search, filters, scrolling grid or list), settings_panel.gd, track_postcards.gd (renders each track by day and
                   night in the background for the menu backdrop, cached in user://postcards), hud.gd (tach, map, mirror, pause, results),
                   ui_kit.gd (palette, fonts, slanted shapes, key hints), tab_strip.gd, option_row.gd,
                   action_list.gd (pause/results menus), track_map.gd, car_stats.gd
fonts/             Barlow / Barlow Condensed (SIL Open Font License, see fonts/OFL.txt)
scripts/audio/     car_audio.gd (engine, tyres, scrapes, crashes, horn, siren: the games' banks, or
                   synthesised without them), game_sounds.gd (the shared banks),
                   music_player.gd (streams the music, owned by Game across scenes), speech.gd
                   (queued voice lines, decoded off-thread), menu_sounds.gd (menu clicks)
shaders/           track.gdshader (unshaded, vertex-lit like the original; wet road), track_additive.gdshader
                   (glows, fire, light shafts), car.gdshader (paint mask), car_glass.gdshader (High Stakes'
                   see-through windows), precipitation.gdshader
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
                   (--aistats: every racer's hit on traffic, racers, cops and walls, and the totals)
                   (--resttest, --ghosttest, --dentbench check sleeping cruisers, far-off traffic
                   and the cost of a crash's dent)
                   (--stoplog prints where any car stops dead and what solid is around it;
                   --traffictest each traffic car's lane, speed, giving way and horn every 2 s)
                   (--camera=N starts in that camera mode, 3 the in-car view, 4 TV; --surrender=S pulls
                   over S s into a chase to get busted; --rbcam watches the roadblock once one is up)
                   (--shots=S,S,... screenshot times; --seed=N the same rivals every run; --layout=N,
                   --upgrade=N, --intro, --classic-hud; --no-ai-tables / --no-ai-speeds race without
                   the original AI's racing line and speeds, to compare; menu --cars opens the car list)
tools/gdprof.py    per-function GDScript times and per-pass GPU times of a run, through the remote
                   debugger (Python, no editor needed; usage at the top of the file)
tools/track_shots.gd photograph a track's road at points round the lap (fractions 0..1), with
                   draw-call and triangle counts: godot --path . -- --trackshots <track> [0.25 ...]
                   (--night / --weather; --up= --back= --ahead= --side= --lookside= aim the eye;
                   --tag=NAME; --hazards lists solid scenery inside the procedural track's walls;
                   --clearmap=FROM-TO prints where the AI's obstacle scan finds room for a car on
                   those virtual road nodes; --eye=X,Y,Z --at=X,Y,Z [--every=S] shoots from a fixed
                   point instead, a shot per fraction given, S s apart, to watch things move)
tools/postcards.gd re-render the menu's track pictures and copy them to shots/:
                   godot --path . -- --postcards [track ...]
tools/car_shots.gd contact sheet of every traffic car, cruiser or player car, front and rear, saved to shots/:
                   godot --path . -- --carshots [traffic|cops|cars|hstraffic|hscops|heli] [id ...] [--track=trk000 [--night]]
                   (--big / --low / --yaw=DEG / --wire for close inspection; --dent crashes each car
                   first, --officer stands a High Stakes cruiser's officer beside it)
tools/car_calib.gd flat-out drag test of every car against the original game's acceleration table:
                   godot --headless --path . -s tools/car_calib.gd [-- name-filter]
tools/car_handling.gd  skidpad (lateral g, and against what the AI expects), lane change, trail
                   braking, power-on, handbrake and 100-0 braking tests of each car on a flat:
                   godot --headless --path . -- --handling [name filter ...] [--classic]
```

## Not done yet

- The radio's place names ("near the old mill": which stretch of each track they mean isn't
  known), High Stakes' speech, the car banks' one-shot patch 2, NFS3's music reacting to the
  race (its `.map`s are only used for the menu tunes, at random).
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
