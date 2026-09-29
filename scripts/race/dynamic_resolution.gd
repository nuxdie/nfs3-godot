class_name DynamicResolution
extends Node
## Holds 60 fps on a GPU that can't draw every stretch of a track at the quality preset's
## resolution: the 3D view (not the HUD) drops a step where frames are being missed while
## the GPU is busy, and climbs back towards the preset's scale once it has been keeping up
## for a while. A step up that brings misses straight back is undone, and the next try waits
## longer. Changes are spaced out, as each one reallocates the view's buffers.
##
## The GPU time the renderer measures doesn't see presenting the frame, and an iGPU clocked
## down under vsync reads slow, so misses (not the measured time alone) decide.

const MISS_MS := 20.0        # a frame this long missed the 60 fps vsync
const MISSES := 3            # ...this many of them within WINDOW calls for a step down
const WINDOW := 1.0          # s
const GPU_BUSY := 7.0        # ms measured: below this, misses are the CPU's and resolution won't help
const GPU_OVER := 13.5       # ms measured: this far over, step down without waiting for misses
const GPU_ROOM := 10.5       # ms measured: a step up needs the GPU under this
const STEP := 0.05
const MIN_SCALE := 0.5
const SETTLE := 1.0          # s after a change before judging the new scale
const RAISE_WAIT := 4.0      # s without misses before a step up; doubles after one fails
const RAISE_WAIT_MAX := 32.0

var _vp: Viewport
var _max := 1.0
var _gpu := 0.0              # smoothed ms
var _extra: Array[Viewport] = []
var _misses: Array[float] = []   # times of recent misses
var _t := 0.0                # clock
var _changed_t := -INF
var _clean_t := 0.0          # s since the last miss
var _raised_t := -INF
var _raise_wait := RAISE_WAIT


func _ready() -> void:
	_vp = get_viewport()
	_max = _vp.scaling_3d_scale
	# Start where the last race settled rather than finding it again over the first seconds.
	if Game.render_scale > 0.0 and Game.render_scale_quality == Game.quality:
		_vp.scaling_3d_scale = clampf(Game.render_scale, MIN_SCALE, _max)
	RenderingServer.viewport_set_measure_render_time(_vp.get_viewport_rid(), true)


func _exit_tree() -> void:
	Game.render_scale = _vp.scaling_3d_scale
	Game.render_scale_quality = Game.quality
	# The menu's views and the next race's preset start from the preset's own scale.
	_vp.scaling_3d_scale = _max


## Counts `vp`'s drawing (the mirror) in the GPU's time too.
func watch(vp: Viewport) -> void:
	_extra.append(vp)
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)


func _process(dt: float) -> void:
	if get_tree().paused:
		return
	_t += dt
	var ms := RenderingServer.viewport_get_measured_render_time_gpu(_vp.get_viewport_rid())
	for v in _extra:
		if is_instance_valid(v):
			ms += RenderingServer.viewport_get_measured_render_time_gpu(v.get_viewport_rid())
	if ms > 0.0:
		_gpu = lerpf(_gpu, ms, 1.0 - exp(-dt * 4.0))
	# Frame time from the real clock: the frame delta Godot hands out is smoothed.
	if dt * 1000.0 > MISS_MS:
		_misses.append(_t)
		_clean_t = 0.0
	else:
		_clean_t += dt
	while not _misses.is_empty() and _misses[0] < _t - WINDOW:
		_misses.pop_front()
	if _t - _changed_t < SETTLE:
		return
	var s := _vp.scaling_3d_scale
	var missing := _misses.size() >= MISSES and _gpu > GPU_BUSY
	if (missing or _gpu > GPU_OVER) and s > MIN_SCALE + 0.001:
		if _t - _raised_t < SETTLE + WINDOW * 2.0:
			# The last step up was too much: wait longer before the next try.
			_raise_wait = minf(_raise_wait * 2.0, RAISE_WAIT_MAX)
		_change_scale(maxf(s - STEP, MIN_SCALE))
	elif _clean_t > _raise_wait and _gpu < GPU_ROOM and s < _max - 0.001:
		_change_scale(minf(s + STEP, _max))
		_raised_t = _t
	elif _clean_t > RAISE_WAIT_MAX:
		# Kept up at this scale for a good while: the next step up may try sooner again.
		_raise_wait = RAISE_WAIT


func _change_scale(s: float) -> void:
	_vp.scaling_3d_scale = s
	_changed_t = _t
	_misses.clear()
	_clean_t = 0.0
