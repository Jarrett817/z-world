extends Node3D
## 可拾取物资：浮动旋转方块 + 同色光源，房车靠近自动拾取。
## kind 由 main 在 add_child 前设置：fuel / food / repair。

const COLORS := {
	"fuel": Color(1.0, 0.55, 0.15),
	"food": Color(0.4, 0.85, 0.35),
	"repair": Color(0.35, 0.7, 1.0),
}

var kind := "fuel"
var _t := 0.0
var _base_y := 0.0

func _ready() -> void:
	_t = randf() * TAU
	_base_y = position.y + 1.1
	var col: Color = COLORS[kind]
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 0.8, 0.8)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.7
	mi.material_override = mat
	mi.position.y = 1.1
	add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = col
	light.omni_range = 7.0
	light.light_energy = 1.4
	light.position.y = 1.2
	add_child(light)
	var area := Area3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.4, 2.8, 3.4)
	cs.shape = shape
	cs.position.y = 1.2
	area.add_child(cs)
	area.body_entered.connect(_on_body)
	add_child(area)

func _process(delta: float) -> void:
	_t += delta
	position.y = _base_y + sin(_t * 2.2) * 0.12
	rotate_y(delta * 1.6)

func _on_body(body: Node3D) -> void:
	if body == get_parent().rv:
		get_parent().on_pickup(kind)
		queue_free()
