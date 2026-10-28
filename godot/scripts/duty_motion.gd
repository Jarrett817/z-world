class_name DutyMotion
extends Node
## 车内岗位程序化微动：做饭看锅搅拌 / 收拾转身蹲起，叠加在骨骼动画之上消除「死站着」。
## 作用于 Char 根节点（不在骨骼链上，不与 AnimationPlayer 冲突），随机相位错开多角色节奏。

var _char: Node3D
var _duty: String
var _t := 0.0
var _phase := 0.0
var _base_y := 0.0

func _init(duty: String, char_node: Node3D) -> void:
	_duty = duty
	_char = char_node

func _ready() -> void:
	_phase = randf() * TAU
	_base_y = _char.position.y

func _process(delta: float) -> void:
	_t += delta
	match _duty:
		"cook":
			# 看锅+搅拌：身体前倾小幅起伏，手下落的快速微颤（灶台蒸汽配合）
			_char.rotation.x = 0.07 + sin(_t * 1.9 + _phase) * 0.04
			_char.position.y = _base_y + sin(_t * 3.8 + _phase) * 0.008
		"tidy":
			# 拿取整理：慢速左右转身 + 周期蹲起（平方让低处停留更久，像真的在码货）
			_char.rotation.y = sin(_t * 0.8 + _phase) * 0.25
			var c := maxf(0.0, sin(_t * 0.42 + _phase))
			_char.position.y = _base_y - c * c * 0.10
			_char.rotation.x = c * c * 0.14
