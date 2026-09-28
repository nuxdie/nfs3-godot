extends Node
## Renders every track's menu postcard and saves copies to shots/ for a look:
## godot --path . -- --postcards [track ...]

var _p: TrackPostcards
var _left: Array[String] = []


func _ready() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var ids: Array = args.filter(func(a: String) -> bool: return not a.begins_with("--"))
	if ids.is_empty():
		ids = Game.tracks
	_p = TrackPostcards.new()
	add_child(_p)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	for id: String in ids:
		DirAccess.remove_absolute(TrackPostcards._file(id, false))
		DirAccess.remove_absolute(TrackPostcards._file(id, true))
		_p.request(id)
		_left.append(id)
	_p.rendered.connect(_on_rendered)


func _on_rendered(id: String) -> void:
	for night in [false, true]:
		var img := Image.load_from_file(TrackPostcards._file(id, night))
		img.save_png("shots/postcard_%s_%s.png" % [id, "night" if night else "day"])
	print("postcard ", id)
	_left.erase(id)
	if _left.is_empty():
		get_tree().quit()
