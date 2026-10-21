extends Node3D
## 路边幸存者：VRM 女性角色 GLB（CharUtil 选基底，循环 idle）+ 橙色求救光柱，车辆驶入范围即招募。

var _beam: MeshInstance3D
var crew_id := ""

## main.gd 在 add_child 前调用：指定本幸存者对应的队友 id
func setup(cid: String) -> void:
	crew_id = cid

func _ready() -> void:
	var made := CharUtil.instantiate(crew_id, "idle")
	add_child(made["node"])

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
	_beam.rotate_y(delta * 0.6)

func _on_body(body: Node3D) -> void:
	if body == get_parent().rv:
		get_parent().try_recruit(self)
