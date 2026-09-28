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
| `tracks/trkNNN/trNN.frd` | Track geometry, per-vertex baked lighting, scenery, animated objects |
| `tracks/trkNNN/trNN.col` | Virtual road (AI line, lap progress, invisible walls), global scenery |
| `tracks/trkNNN/trNN0.qfs` | Track textures (RefPack-compressed FSH); the first 8 are the horizon panorama |
| `tracks/trkNNN/3trNN.hrz`, `3trNNn.hrz` | Sky gradient, horizon/cloud placement, fog colour/density, ambient light (day / night) |
| `tracks/trkNNN/sky.fsh` | Cloud layer and sun/moon sprites |
| `carmodel/*/car.viv` → `car.fce`, `car00.tga` | Car mesh, wheels, skin, paint colours |
| `car.viv` → `carp.txt` | Mass, torque curve, gearing, final drive, redline, top speed, braking |
| `car.viv` → `fedata.eng` | Car names for the menu |
| `carmodel/traffic/pursuit/*` | Police cars |
| `carmodel/traffic/NNNN` | Traffic |

## Modes

- **Single Race** – up to 7 AI opponents, 1–8 laps.
- **Hot Pursuit** – one rival plus police. Speed past a parked cruiser
  (> ~120 km/h) and it gives chase with lights and siren. Stop with a cop on
  you and you're busted: two tickets, the third is an arrest. Long chases call
  in a roadblock. Get > 380 m away to evade.
- **Time Trial** – just you and the clock.
- **Free Roam** – no laps, traffic and a couple of patrol cars.

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
                   procedural_track.gd, track_path.gd (virtual road), keyframe_mover.gd
scripts/vehicle/   car.gd (raycast suspension, tyre friction circle, auto gearbox),
                   player_controller.gd, ai_controller.gd (racer / traffic / cop), procedural_car.gd
scripts/race/      race.gd (spawning, laps, positions, pursuit rules), chase_camera.gd
scripts/ui/        main_menu.gd (showroom front end), hud.gd (tach, map, mirror, pause, results),
                   ui_kit.gd (palette, fonts, slanted shapes, key hints), selector_row.gd,
                   action_list.gd (pause/results menus), track_map.gd, car_stats.gd
fonts/             Barlow / Barlow Condensed (SIL Open Font License, see fonts/OFL.txt)
scripts/audio/     car_audio.gd (synthesised engine, tyre squeal, siren)
shaders/           track.gdshader (unshaded, vertex-lit like the original), track_additive.gdshader
                   (glows, fire, light shafts), car.gdshader (paint mask)
tools/autotest.gd  scripted run for testing: godot --path . -- --autotest <trk000|procedural|menu> [mode] [car]
                   (add --settings with menu to photograph the settings panel)
```

## Not done yet

- Original sounds/music (`.bnk`) – audio is synthesised instead.
- Lane-marking textures that live in `render/pc/sfx.fsh` are skipped.
- Night, weather, mirrored/reverse tracks, damage, split-screen.
- The Knockout/tournament structure and car unlocks.
- The car body collides as a box; FCE dummies (light positions) are unused.
- Scenery collision is guessed from the textures (the track files carry no collision flag):
  opaque objects (buildings, walls, poles) are solid, sign-sized ones are knocked over, and
  cut-out foliage and glows are passable.
