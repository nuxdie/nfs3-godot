class_name TrafficRules
## High Stakes' rules for its traffic (from the PSX release's AI: aispeeds, ailife, aih_traf,
## ai and aitune), in metres and seconds.

## Speed limits by stretch of road, per High Stakes track (its Tracks folder): [last slice,
## m/s] in slice order (AISpeeds_TrackSpeeds; the PC tracks have the same slices). Real
## limits of each country: 35/50/65 mph in the US, 50/100 km/h in Germany and France,
## 50/70 mph in England. Tracks not listed have none.
const LEGAL_SPEEDS := {
	"snowy": [[INF, 28.887]],
	"coastal": [[50, 15.555], [196, 28.887], [293, 28.887], [332, 15.555], [390, 28.887],
		[624, 28.887], [665, 15.555], [1026, 28.887], [INF, 15.555]],
	"france": [[7, 22.219], [236, 13.887], [INF, 22.219]],
	"park": [[INF, 22.219]],
	"hills": [[369, 31.109], [674, 22.219], [INF, 31.109]],
	"germany": [[26, 13.887], [327, 27.777], [393, 13.887], [627, 27.777], [INF, 13.887]],
	"uk": [[29, 22.219], [429, 31.109], [617, 31.109], [655, 22.219], [823, 31.109], [INF, 22.219]],
}
## Where no limit is known: the open-road one (65 mph).
const DEFAULT_LEGAL := 28.887
## Tracks whose traffic keeps left (AITune_trackInfo's driveSide: Durham Road, Celtic Ruins).
const DRIVE_LEFT := ["hills", "uk"]

## Traffic cruises at this share of the limit (AISpeeds_CalcTrafficTopSpeed)...
const LEGAL_SHARE := 0.75
## ...times one of these, drawn for each car each time it comes back into play
## (AISpeeds_SetTrafficSpeedRandomFactor), taking at most MAX_CUT off...
const SPEED_FACTORS := [1.0, 0.9, 0.8, 0.7]
const MAX_CUT := 13.4
## ...and never under MIN_SPEED (32 km/h).
const MIN_SPEED := 8.9

## A cruiser with its siren on within this far along the road makes traffic give way
## (AIHigh_Traffic::CopCheck): one stopped across the road (a roadblock) makes it pull over
## and wait; one on the move, it pulls over (70%), stops where it is (10%), or carries on (20%).
const COP_REACT := 75.0
const COP_STOPPED := 2.0

## Traffic further than LIVE from every racer is taken out of play and brought back in
## front of or behind one of them (AILife): here further out than the original's 216 m
## and 28-35 slices, as this draws the road much further ahead than the PlayStation.
const LIVE := 380.0
const SPAWN_MIN := 280.0
const SPAWN_MAX := 340.0
## A racer this fast gets the traffic in front of it, where it's heading (AILife_RCPickSliceAndDirection).
const FAST := 30.0

## Oncoming traffic honks now and then while a racer can see it (AI_HandleTrafficHonking:
## 5 in 1000 each AI tick), per second here.
const HONK_RATE := 0.15


## The speed limit (m/s) at each of `n` nodes of track `track_id` (a Game track id), in
## the track's own slice order; empty where the original has no table for it.
static func legal_speeds(track_id: String, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if not Game.is_hs_track(track_id):
		return out
	var table: Array = LEGAL_SPEEDS.get(track_id.trim_prefix(Game.HS_PREFIX).to_lower(), [])
	if table.is_empty():
		return out
	out.resize(n)
	var k := 0
	for i in n:
		while i > table[k][0]:
			k += 1
		out[i] = table[k][1]
	return out


## +1 where traffic keeps right, -1 where it keeps left; `mirrored` (the track's mirrored
## layout, whose lanes swap sides with the road) the other way.
static func drive_side(track_id: String, mirrored := false) -> int:
	var side := -1 if Game.is_hs_track(track_id) and track_id.trim_prefix(Game.HS_PREFIX).to_lower() in DRIVE_LEFT else 1
	return -side if mirrored else side


## How fast traffic coming the other way may go (m/s) when the racer it's in play for does
## `racer_speed`: the faster the racer, the slower it comes (AISpeeds_CalculateOncomingCarSpeed),
## so a head-on is something the player can react to.
static func oncoming_speed(racer_speed: float) -> float:
	var v := absf(racer_speed)
	if v < 13.33:
		return 22.22
	if v < 26.67:
		return 13.33
	return MIN_SPEED


## A car's cruising speed (m/s) under the limit `legal`, with its speed factor, coming
## the other way to a racer doing `oncoming_racer_speed` if that isn't NAN
## (AISpeeds_CalcTrafficTopSpeed, AISpeeds_RandomizeTrafficSpeed).
static func cruise(legal: float, factor: float, oncoming_racer_speed := NAN) -> float:
	var v := legal * LEGAL_SHARE
	if not is_nan(oncoming_racer_speed):
		v = minf(v, oncoming_speed(oncoming_racer_speed))
	return maxf(maxf(v * factor, v - MAX_CUT), MIN_SPEED)
