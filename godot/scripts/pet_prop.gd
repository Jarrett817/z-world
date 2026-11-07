extends Node3D
## 车内/车顶静态宠物摆件：无 AI、无碰撞、不进消耗回收组，只做极轻微呼吸起伏。
## 几何与 toon 材质风格对齐 animal.gd，但为安静趴姿/站姿，由 main 摆放在宠物角与车顶鸡笼。

## 外观参数与 animal.gd 同物种保持一致（尺寸单位：米）
const SPECIES := {
	"dog": {"color": Color(0.72, 0.5, 0.3), "belly": Color(0.82, 0.68, 0.5), "ear": "floppy"},
	"cat": {"color": Color(0.62, 0.62, 0.66), "belly": Color(0.8, 0.78, 0.75), "ear": "pointy"},
	"rabbit": {"color": Color(0.85, 0.78, 0.7), "belly": Color(0.95, 0.92, 0.88), "ear": "long"},
	"chick": {"color": Color(0.96, 0.82, 0.36), "belly": Color(0.99, 0.9, 0.6), "ear": "none"},
}

var _model: Node3D
var _t := 0.0

## main 调用：在 parent 下生成一只 species 宠物，pos 为脚底位置、yaw 为朝向（车头 -Z 时用 PI）
static func build(parent: Node3D, species: String, pos: Vector3, yaw: float) -> Node3D:
	var pet := Node3D.new()
	pet.set_script(preload("res://scripts/pet_prop.gd"))
	pet.name = "Pet_%s" % species
	pet.position = pos
	pet.rotation.y = yaw
	parent.add_child(pet)
	pet._assemble(species)
	return pet

func _ready() -> void:
	_t = randf() * TAU

func _process(delta: float) -> void:
	_t += delta
	if _model != null:
		# 呼吸：整体 1.5% 的极轻微缩放，肉眼只觉安静起伏
		var b := 1.0 + sin(_t * 2.2) * 0.015
		_model.scale = Vector3(1.0, b, 1.0)

func _assemble(species: String) -> void:
	var spec: Dictionary = SPECIES.get(species, SPECIES["cat"])
	_model = Node3D.new()
	add_child(_model)
	if species == "chick":
		_build_chick(spec)
	else:
		_build_mammal(species)

## 猫狗兔：安静坐姿，臀部落地、前腿撑直，朝 +Z
func _build_mammal(species: String) -> void:
	var spec: Dictionary = SPECIES[species]
	var fur := _mat(spec["color"])
	var belly_mat := _mat(spec["belly"])
	var dark := _mat(Color(0.12, 0.1, 0.09))
	var s := 0.72 if species == "rabbit" else 1.0   # 兔子略小一圈
	var body := _box(Vector3(0.3 * s, 0.34 * s, 0.4 * s), fur)
	body.position = Vector3(0, 0.26 * s, 0.02 * s)
	_model.add_child(body)
	# 圆臀
	var rump := _sphere(0.2 * s, fur)
	rump.position = Vector3(0, 0.24 * s, -0.16 * s)
	_model.add_child(rump)
	# 胸前浅色块
	var belly := _box(Vector3(0.2 * s, 0.2 * s, 0.03), belly_mat)
	belly.position = Vector3(0, 0.24 * s, 0.23 * s)
	_model.add_child(belly)
	# 两只前腿垂直撑地
	for sx in [-1.0, 1.0]:
		var leg := _box(Vector3(0.07 * s, 0.2 * s, 0.08 * s), fur)
		leg.position = Vector3(sx * 0.08 * s, 0.1 * s, 0.18 * s)
		_model.add_child(leg)
	# 头
	var head_r := 0.15 * s
	var head := _sphere(head_r, fur)
	head.position = Vector3(0, 0.5 * s, 0.17 * s)
	_model.add_child(head)
	# 吻部
	var snout := _box(Vector3(head_r * 0.9, head_r * 0.7, head_r * 0.7), belly_mat)
	snout.position = Vector3(0, 0.46 * s, 0.3 * s)
	_model.add_child(snout)
	# 眼鼻
	for sx in [-1.0, 1.0]:
		var eye := _sphere(head_r * 0.16, dark)
		eye.position = Vector3(sx * head_r * 0.55, 0.53 * s, 0.29 * s)
		_model.add_child(eye)
	var nose := _sphere(head_r * 0.18, dark)
	nose.position = Vector3(0, 0.46 * s, 0.34 * s)
	_model.add_child(nose)
	# 耳朵按物种区分
	var ear_type: String = spec["ear"]
	for sx in [-1.0, 1.0]:
		var ear_size := Vector3(0.06 * s, 0.12 * s, 0.05 * s)
		var ear_pos := Vector3(sx * 0.08 * s, 0.62 * s, 0.14 * s)
		var ear_tilt := 0.0
		match ear_type:
			"pointy":
				ear_size = Vector3(0.06 * s, 0.13 * s, 0.05 * s)
				ear_pos = Vector3(sx * 0.08 * s, 0.64 * s, 0.14 * s)
			"long":
				ear_size = Vector3(0.05 * s, 0.26 * s, 0.04 * s)
				ear_pos = Vector3(sx * 0.07 * s, 0.7 * s, 0.13 * s)
				ear_tilt = -0.2
			_:
				# 狗耷拉耳贴头侧
				ear_size = Vector3(0.04 * s, 0.14 * s, 0.08 * s)
				ear_pos = Vector3(sx * head_r * 0.95, 0.48 * s, 0.16 * s)
		var ear := _box(ear_size, fur)
		ear.position = ear_pos
		ear.rotation.x = ear_tilt
		_model.add_child(ear)
	# 尾巴：猫竖尾、兔短绒球、狗后伸上翘
	var tail := _box(Vector3(0.06 * s, 0.18 * s, 0.06 * s), fur)
	if species == "rabbit":
		tail = _sphere(0.07 * s, belly_mat)
		tail.position = Vector3(0, 0.2 * s, -0.26 * s)
	else:
		tail.position = Vector3(0, 0.34 * s, -0.24 * s)
		tail.rotation.x = -0.5 if species == "dog" else 0.3
	_model.add_child(tail)

## 小鸡：圆身球 + 小翅 + 三角喙 + 细腿，站在笼底板上
func _build_chick(spec: Dictionary) -> void:
	var down := _mat(spec["color"])
	var belly_mat := _mat(spec["belly"])
	var orange := _mat(Color(0.92, 0.5, 0.16))
	var dark := _mat(Color(0.12, 0.1, 0.09))
	var body := _sphere(0.11, down)
	body.position = Vector3(0, 0.16, 0)
	body.scale = Vector3(1.0, 1.12, 1.0)
	_model.add_child(body)
	var head := _sphere(0.075, down)
	head.position = Vector3(0, 0.3, 0.05)
	_model.add_child(head)
	# 三角喙（小锥）
	var beak := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.028
	cm.height = 0.06
	beak.mesh = cm
	beak.material_override = orange
	beak.rotation.x = PI * 0.5
	beak.position = Vector3(0, 0.29, 0.13)
	_model.add_child(beak)
	# 眼睛
	for sx in [-1.0, 1.0]:
		var eye := _sphere(0.012, dark)
		eye.position = Vector3(sx * 0.032, 0.32, 0.11)
		_model.add_child(eye)
	# 小翅膀贴两侧
	for sx in [-1.0, 1.0]:
		var wing := _sphere(0.05, belly_mat)
		wing.scale = Vector3(0.45, 1.0, 0.8)
		wing.position = Vector3(sx * 0.095, 0.16, 0.0)
		_model.add_child(wing)
	# 两条细腿
	for sx in [-1.0, 1.0]:
		var leg := _box(Vector3(0.02, 0.08, 0.02), orange)
		leg.position = Vector3(sx * 0.04, 0.04, 0)
		_model.add_child(leg)
		var foot := _box(Vector3(0.04, 0.015, 0.06), orange)
		foot.position = Vector3(sx * 0.04, 0.008, 0.02)
		_model.add_child(foot)

func _box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	return mi

func _sphere(r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.material_override = mat
	return mi

func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	return m
