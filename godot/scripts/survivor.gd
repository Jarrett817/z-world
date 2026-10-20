extends Node3D
## 路边幸存者：简易人形（躯干/四肢/背包/头发）+ 微弱橙色光柱，房车靠近自动触发招募。

var _t := 0.0
var _body: Node3D
var _beam: MeshInstance3D

func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	var skin := _mat(Color(0.82, 0.68, 0.55))
	var jacket := _mat(Color(0.3, 0.32, 0.26))
	var pants := _mat(Color(0.17, 0.18, 0.2))
	var hair := _mat(Color(0.12, 0.1, 0.09))

	# 双腿
	for sx in [-0.11, 0.11]:
		_add_box(_body, Vector3(0.17, 0.86, 0.2), Vector3(sx, 0.43, 0), pants)
	# 躯干
	_add_box(_body, Vector3(0.5, 0.62, 0.28), Vector3(0, 1.2, 0), jacket)
	# 双臂
	for sx in [-0.31, 0.31]:
		_add_box(_body, Vector3(0.13, 0.56, 0.15), Vector3(sx, 1.14, 0.02), jacket)
	# 背包
	_add_box(_body, Vector3(0.34, 0.42, 0.18), Vector3(0, 1.2, 0.22), _mat(Color(0.22, 0.2, 0.16)))
	# 头 + 头发
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.155
	sph.height = 0.34
	head.mesh = sph
	head.material_override = skin
	head.position.y = 1.66
	_body.add_child(head)
	var cap := MeshInstance3D.new()
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 0.165
	cap_mesh.height = 0.3
	cap_mesh.is_hemisphere = true
	cap.mesh = cap_mesh
	cap.material_override = hair
	cap.position = Vector3(0, 1.72, 0.01)
	_body.add_child(cap)

	# 微弱求救光柱（暗夜远距离可见，但不刺眼）
	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.32
	cyl.height = 4.5
	_beam.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(1.0, 0.55, 0.15, 0.1)
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam.material_override = bm
	_beam.position.y = 2.25
	add_child(_beam)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.omni_range = 6.0
	light.light_energy = 0.7
	light.position.y = 1.4
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
	# 原地张望：轻微重心摆动
	_body.rotation.z = sin(_t * 1.6) * 0.04
	_body.rotation.y = sin(_t * 0.7) * 0.25
	_beam.rotate_y(delta * 0.6)

func _on_body(body: Node3D) -> void:
	if body == get_parent().rv:
		get_parent().try_recruit(self)

func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)

func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	return m
