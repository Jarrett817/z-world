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
}
## 统一视觉高度（米）：小道具按真实比例放大到路边醒目尺寸
const MODEL_HEIGHT := 0.95

var kind := "fuel"
var _t := 0.0
var _base_y := 0.0

func _ready() -> void:
	_t = randf() * TAU
	_base_y = position.y
	var model: Node3D = MODELS[kind].instantiate()
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
	area.collision_mask = 2  # 房车独占碰撞层2
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.4, 2.8, 3.4)
	cs.shape = shape
	cs.position.y = 1.0
	area.add_child(cs)
	area.body_entered.connect(_on_body)
	add_child(area)

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
	if body == get_parent().rv:
		get_parent().on_pickup(kind)
		queue_free()
