class_name DutyMotion
extends Node
## 车内岗位程序化微动：做饭看锅搅拌 / 收拾转身蹲起，叠加在骨骼动画之上消除「死站着」。
## 作用于 Char 根节点（不在骨骼链上，不与 AnimationPlayer 冲突），随机相位错开多角色节奏。

var _char: Node3D
var _duty: String
var _t := 0.0
var _phase := 0.0
var _base_y := 0.0
var _skel: Skeleton3D
var _bones: Dictionary = {}

func _init(duty: String, char_node: Node3D) -> void:
	_duty = duty
	_char = char_node

func _ready() -> void:
	_phase = randf() * TAU
	_base_y = _char.position.y
	var skels := _char.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		_skel = skels[0]
		for bone_name in ["J_Bip_L_UpperArm", "J_Bip_L_LowerArm", "J_Bip_L_Hand", "J_Bip_R_UpperArm", "J_Bip_R_LowerArm", "J_Bip_R_Hand"]:
			_bones[bone_name] = _skel.find_bone(bone_name)
		# 动画每帧重写骨骼，必须在 pose_updated 后叠加岗位动作
		_skel.pose_updated.connect(_on_pose_updated)

func _process(delta: float) -> void:
	_t += delta
	match _duty:
		"cook":
			_char.rotation.x = 0.06 + sin(_t * 1.9 + _phase) * 0.025
			_char.position.y = _base_y
		"tidy":
			# 伸手取物后转身码放，低速蹲起配合够取低层货架
			_char.rotation.y = sin(_t * 0.8 + _phase) * 0.25
			var c := maxf(0.0, sin(_t * 0.42 + _phase))
			_char.position.y = _base_y - c * c * 0.07
			_char.rotation.x = c * c * 0.10

func _on_pose_updated() -> void:
	if _skel == null:
		return
	var poses: Array = []
	match _duty:
		"cook":
			# 左手扶锅，右手前臂与手腕持续画圈搅拌
			var stir := _t * 4.2 + _phase
			poses = [
				[_bones["J_Bip_L_UpperArm"], Vector3(-0.55, 0.0, 0.08)],
				[_bones["J_Bip_L_LowerArm"], Vector3(-0.80, 0.0, 0.0)],
				[_bones["J_Bip_R_UpperArm"], Vector3(-0.62 + sin(stir) * 0.10, 0.0, cos(stir) * 0.12)],
				[_bones["J_Bip_R_LowerArm"], Vector3(-0.78 + sin(stir) * 0.18, 0.0, 0.0)],
				[_bones["J_Bip_R_Hand"], Vector3(0.0, sin(stir) * 0.45, cos(stir) * 0.20)],
			]
		"tidy":
			# 双臂同步前伸—收回—转向，形成清楚的拿取与放置循环
			var reach := 0.5 + 0.5 * sin(_t * 1.5 + _phase)
			for side in ["L", "R"]:
				poses.append([_bones["J_Bip_%s_UpperArm" % side], Vector3(-0.38 - reach * 0.52, 0.0, 0.0)])
				poses.append([_bones["J_Bip_%s_LowerArm" % side], Vector3(-0.45 - reach * 0.42, 0.0, 0.0)])
				poses.append([_bones["J_Bip_%s_Hand" % side], Vector3(0.0, 0.0, sin(_t * 1.5 + _phase) * 0.18)])
	for p in poses:
		var bone: int = p[0]
		var animated := _skel.get_bone_pose_rotation(bone)
		_skel.set_bone_pose_rotation(bone, animated * Quaternion.from_euler(p[1]))
