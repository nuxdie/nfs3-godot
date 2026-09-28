class_name SpikeStrip
extends Area3D
## A police stinger laid across part of the road. Any car but a cop's that drives over it
## gets flat tyres (see Car.puncture).

signal punctured(car: Car)

var length := 6.0


func _init(len_m := 6.0) -> void:
	length = len_m


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2   # cars
	monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Taller than it looks, so a car skimming over at speed still registers.
	box.size = Vector3(length, 0.8, 0.9)
	shape.shape = box
	shape.position.y = 0.3
	add_child(shape)
	body_entered.connect(_on_body_entered)

	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(length, 0.04, 0.3)
	base.mesh = bm
	base.position.y = 0.02
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.13)
	mat.metallic = 0.6
	mat.roughness = 0.5
	base.material_override = mat
	add_child(base)

	# Two rows of spikes, sharing one mesh through a MultiMesh.
	var spike := PrismMesh.new()
	spike.size = Vector3(0.07, 0.12, 0.07)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.75, 0.75, 0.78)
	steel.metallic = 0.9
	steel.roughness = 0.3
	spike.material = steel
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = spike
	var per_row := int(length / 0.2)
	mm.instance_count = per_row * 2
	for k in mm.instance_count:
		var x := -length * 0.5 + 0.1 + (k % per_row) * 0.2 + (0.1 if k >= per_row else 0.0)
		var z := -0.08 if k < per_row else 0.08
		mm.set_instance_transform(k, Transform3D(Basis(), Vector3(minf(x, length * 0.5 - 0.05), 0.1, z)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _on_body_entered(body: Node3D) -> void:
	var c := body as Car
	if c == null or c.is_cop or c.tyres_flat():
		return
	c.puncture()
	punctured.emit(c)
