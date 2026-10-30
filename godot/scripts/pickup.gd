extends Node3D
## 可拾取物资：地面物资模型 + 微光，房车靠近自动拾取。
## kind 由 main 在 add_child 前设置：fuel / food / repair。

const MODELS := {
	"fuel": preload("res://assets/props/pickup_fuel.glb"),
	"food": preload("res://assets/props/pickup_food.glb"),
	"repair": preload("res://assets/props/pickup_repair.glb"),
}
## 三类物资的微光与识别色
const COLORS := {
	"fuel": Color(1.0, 0.45, 0.12),
	"food": Color(0.75, 0.6, 0.3),
	"repair": Color(0.55, 0.75, 0.85),
	"ammo": Color(0.85, 0.72, 0.3),
}
## 统一视觉高度（米）：小道具按真实比例放大到路边醒目尺寸
const MODEL_HEIGHT := 0.95

var kind := "fuel"
## true=镇内搜刮箱：玩家步行可拾取（mask 含玩家层1）；false=路面箱：仅房车吸
var walkable := false
## 奖励倍率（镇内箱比路面丰厚）
var boost := 1.0
var _t := 0.0
var _base_y := 0.0

func _ready() -> void:
	_t = randf() * TAU
	_base_y = position.y
	var model: Node3D
	if kind == "ammo":
		# 弹药箱无现成 GLB：代码生成军绿铁箱 + 箱顶两排黄铜子弹
		model = _build_ammo_crate()
	else:
		model = MODELS[kind].instantiate()
		# glb 原点在底面，按包围盒高度等比放大到 MODEL_HEIGHT
		var _aabb := _node_aabb(model)
		var s := MODEL_HEIGHT / maxf(_aabb.size.y, 0.001)
		model.scale = Vector3(s, s, s)
	add_child(model)
	var col: Color = COLORS[kind]
	var light := OmniLight3D.new()
	light.light_color = col
	light.omni_range = 4.2
	light.light_energy = 0.7
	light.position.y = 0.7
	add_child(light)
	var area := Area3D.new()
	area.collision_mask = 3 if walkable else 2  # 层1=玩家 层2=房车
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.4, 2.8, 3.4)
	cs.shape = shape
	cs.position.y = 1.0
	area.add_child(cs)
	area.body_entered.connect(_on_body)
	add_child(area)

## 弹药箱：军绿铁箱（箱盖略浅、棱边深色包角）+ 箱顶两排黄铜子弹，总高对齐 MODEL_HEIGHT
func _build_ammo_crate() -> Node3D:
	var root := Node3D.new()
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color(0.31, 0.34, 0.2)
	olive.roughness = 0.7
	var lid_mat := StandardMaterial3D.new()
	lid_mat.albedo_color = Color(0.38, 0.41, 0.25)
	lid_mat.roughness = 0.7
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.83, 0.66, 0.28)
	brass.metallic = 0.7
	brass.roughness = 0.35
	var s := MODEL_HEIGHT / 0.62   # 造型高 0.62（箱 0.5 + 弹 0.12），放大到统一拾取高度
	root.scale = Vector3(s, s, s)
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.mesh.size = Vector3(0.62, 0.5, 0.42)
	box.position.y = 0.25
	box.material_override = olive
	root.add_child(box)
	var lid := MeshInstance3D.new()
	lid.mesh = BoxMesh.new()
	lid.mesh.size = Vector3(0.66, 0.06, 0.46)
	lid.position.y = 0.52
	lid.material_override = lid_mat
	root.add_child(lid)
	# 两排子弹（小圆柱 + 尖头锥）
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.018
	body_mesh.bottom_radius = 0.018
	body_mesh.height = 0.09
	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = 0.018
	tip_mesh.height = 0.035
	for rz in [-0.07, 0.07]:
		for i in 9:
			var rx := -0.24 + i * 0.06
			var rd := MeshInstance3D.new()
			rd.mesh = body_mesh
			rd.material_override = brass
			rd.position = Vector3(rx, 0.595, rz)
			root.add_child(rd)
			var tip := MeshInstance3D.new()
			tip.mesh = tip_mesh
			tip.material_override = brass
			tip.position = Vector3(rx, 0.657, rz)
			root.add_child(tip)
	return root

func _node_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (mi as MeshInstance3D).get_aabb()
		# 叠加节点自身变换，得到相对 glb 根的包围盒
		box = mi.transform * box
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out

func _process(delta: float) -> void:
	_t += delta
	position.y = _base_y + sin(_t * 2.2) * 0.08
	rotate_y(delta * 0.6)

func _on_body(body: Node3D) -> void:
	var m := get_parent()
	if body == m.rv or (walkable and body == m.get_player_body()):
		m.on_pickup(kind, boost)
		queue_free()
