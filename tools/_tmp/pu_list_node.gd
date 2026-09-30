extends Node
func _ready() -> void:
	Game.scan_data()
	for c in Game.cars:
		if c.id.begins_with("pu_"):
			var rec: Dictionary = Game._pu_cars[c.path]
			print("%s %s %d" % [c.id, rec.model, rec.style])
	get_tree().quit()
