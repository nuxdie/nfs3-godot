class_name TrackPostcards
extends Node
## Renders a still of each track, by day and by night, for the menu backdrop and keeps them
## in user://postcards. One track at a time: built on a worker thread, then photographed in
## an off-screen viewport, so the menu keeps running while the missing ones fill in.

signal rendered(id: String)

const VERSION := 2              # bump to re-render everyone's after a change to the look
const SIZE := Vector2i(1280, 720)   # rendered at...
const SAVED := Vector2i(640, 360)   # ...and kept at, softened: it's a backdrop
const DIR := "user://postcards"
const EYE_HEIGHT := 7.0         # m above the road
const EYE_OFFSET := 0.0         # of the half-width towards the right verge
const LOOK_AHEAD := 140.0        # m along the road to the point the camera looks at
const BEHIND_START := 60.0      # m back from the start line

var _queue: Array[String] = []
var _task := -1
var _world: TrackWorld
var _current := ""              # the track being built or photographed
var _cache := {}                # file path -> Texture2D


## The picture for `id`, or null if it hasn't been rendered yet (then it's queued).
func get_postcard(id: String, night: bool) -> Texture2D:
	var file := _file(id, night)
	if _cache.has(file):
		return _cache[file]
	if FileAccess.file_exists(file):
		var img := Image.load_from_file(file)
		if img:
			_cache[file] = ImageTexture.create_from_image(img)
			return _cache[file]
	request(id, true)
	return null


## Queues `id` for rendering unless it's done or queued already; `first` puts it at the front.
func request(id: String, first := false) -> void:
	if DisplayServer.get_name() == "headless" or FileAccess.file_exists(_file(id, false)):
		return
	if id == _current:
		return
	_queue.erase(id)
	if first:
		_queue.push_front(id)
	else:
		_queue.push_back(id)


## Softened a little, like a shallow depth of field, so the showroom car and the text
## over it stand out.
static func _soften(img: Image) -> void:
	img.resize(SIZE.x / 4, SIZE.y / 4, Image.INTERPOLATE_BILINEAR)
	img.resize(SAVED.x, SAVED.y, Image.INTERPOLATE_CUBIC)


static func _file(id: String, night: bool) -> String:
	return "%s/%s_%s_v%d.webp" % [DIR, id, "night" if night else "day", VERSION]


func _process(_dt: float) -> void:
	if _task < 0 and _world == null and not _queue.is_empty():
		var id: String = _queue.pop_front()
		_current = id
		_task = WorkerThreadPool.add_task(func() -> void:
			var w := TrackWorld.load_track(id)
			# A picture needs no collision: registering it all would hitch the menu.
			for c in w.root.find_children("*", "CollisionShape3D", true, false):
				c.free()
			_world = w)
	elif _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_shoot()


func _shoot() -> void:
	var w := _world
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	vp.add_child(w.root)
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.far = 2500.0
	vp.add_child(cam)
	cam.global_transform = pose(w.path)
	var shots: Array[Image] = []
	for night in [false, true]:
		w.light(vp, night, false)
		# A few frames for the shadows and sky to settle (and the shaders to compile).
		for k in 4:
			await RenderingServer.frame_post_draw
		shots.append(vp.get_texture().get_image())
	vp.queue_free()
	# Softening and encoding take a couple of hundred ms: off the main thread.
	DirAccess.make_dir_recursive_absolute(DIR)
	var task := WorkerThreadPool.add_task(func() -> void:
		for k in shots.size():
			_soften(shots[k])
			shots[k].save_webp(_file(w.id, k == 1), true, 0.85))
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	for k in shots.size():
		_cache[_file(w.id, k == 1)] = ImageTexture.create_from_image(shots[k])
	_world = null
	_current = ""
	rendered.emit(w.id)


## Above the road a little back from the start line, looking up it.
static func pose(path: TrackPath) -> Transform3D:
	var n := path.size()
	var i := n - 1
	var back := 0.0
	while back < BEHIND_START and i > n / 2:
		back += path.points[path.idx(i)].distance_to(path.points[path.idx(i - 1)])
		i -= 1
	var ahead := i
	var along := 0.0
	while along < LOOK_AHEAD:
		along += path.points[path.idx(ahead)].distance_to(path.points[path.idx(ahead + 1)])
		ahead += 1
	i = path.idx(i)
	var up := path.ups[i] if path.ups.size() > i else Vector3.UP
	var eye := path.points[i] + path.rights[i] * path.right_width[i] * EYE_OFFSET + up * EYE_HEIGHT
	var target := path.points[path.idx(ahead)] + Vector3.UP * 3.0
	return Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
