extends Node3D
## 路边幸存者：简易人形 + 橙色求救光柱，房车靠近自动触发招募（食物消耗在 main 判定）。

var _t := 0.0
var _beam: MeshInstance3D

func _ready() -> void:
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.28
	cap.height = 1.25
	body.mesh = cap
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.42, 0.3)
	m.roughness = 1.0
	body.material_override = m
	body.position.y = 0.85
	add_child(body)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.2
	sph.height = 0.4
	head.mesh = sph
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.85, 0.72, 0.6)
	hm.roughness = 0.9
	head.material_override = hm
	head.position.y = 1.72
	add_child(head)
	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.55
	cyl.height = 9.0
	_beam.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(1.0, 0.55, 0.15, 0.3)
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam.material_override = bm
	_beam.position.y = 4.5
	add_child(_beam)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.omni_range = 8.0
	light.light_energy = 1.2
	light.position.y = 1.5
	add_child(light)
	var area := Area3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.0, 3.0, 4.0)
	cs.shape = shape
	cs.position.y = 1.2
	area.add_child(cs)
	area.body_entered.connect(_on_body)
	add_child(area)

func _process(delta: float) -> void:
	_t += delta
	_beam.rotate_y(delta * 0.8)
	_beam.scale = Vector3.ONE * (1.0 + sin(_t * 3.0) * 0.08)

func _on_body(body: Node3D) -> void:
	if body == get_parent().rv:
		get_parent().try_recruit(self)
