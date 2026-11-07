extends Node3D
## 车内/车顶宠物摆件：无 AI、无碰撞、不进消耗回收组。
## 安静待着的同时偶尔摆尾/转头/抖耳/舔爪，小鸡在笼内小步踱步啄米，动作随机低频。
## 几何与 toon 材质风格对齐 animal.gd，由 main 摆放在宠物角与车顶鸡笼。

## 外观参数与 animal.gd 同物种保持一致（尺寸单位：米）
const SPECIES := {
	"dog": {"color": Color(0.72, 0.5, 0.3), "belly": Color(0.82, 0.68, 0.5), "ear": "floppy"},
	"cat": {"color": Color(0.62, 0.62, 0.66), "belly": Color(0.8, 0.78, 0.75), "ear": "pointy"},
	"rabbit": {"color": Color(0.85, 0.78, 0.7), "belly": Color(0.95, 0.92, 0.88), "ear": "long"},
	"chick": {"color": Color(0.96, 0.82, 0.36), "belly": Color(0.99, 0.9, 0.6), "ear": "none"},
}

# 小鸡踱步半径（笼内三只各守站位，不越界相撞）
const CHICK_WALK_RADIUS := 0.22

var _model: Node3D
var _head: Node3D
var _tail: Node3D
var _ears: Array = []
var _species := "cat"
var _t := 0.0
var _act := ""          # 当前动作；空串为纯呼吸空闲
var _act_t := 0.0
var _act_dur := 1.0
var _next_act := 4.0
var _act_seed := 0      # 动作内随机选择（哪只耳朵/朝哪看）
var _origin := Vector3.ZERO
var _walk_dir := Vector3.ZERO

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
	_next_act = randf_range(2.0, 6.0)
	_origin = position

func _process(delta: float) -> void:
	_t += delta
	if _model == null:
		return
	# 呼吸：整体 1.5% 的极轻微缩放，肉眼只觉安静起伏
	var b := 1.0 + sin(_t * 2.2) * 0.015
	_model.scale = Vector3(1.0, b, 1.0)
	if _act == "":
		_next_act -= delta
		if _next_act <= 0.0:
			_start_act()
	else:
		_act_t += delta
		_drive_act()
		if _act_t >= _act_dur:
			_end_act()

## 随机挑一个符合物种的小动作，包络 sin 曲线保证起势/收势都平滑归零
func _start_act() -> void:
	var pool: Array
	match _species:
		"dog":
			pool = ["look", "wag", "ear", "lick"]
		"cat":
			pool = ["look", "wag", "ear", "lick"]
		"rabbit":
			pool = ["look", "ear", "sniff"]
		_:
			pool = ["peck", "walk", "look"]
	_act = String(pool[randi() % pool.size()])
	_act_t = 0.0
	_act_seed = randi()
	match _act:
		"wag":
			_act_dur = randf_range(1.2, 2.2)
		"walk":
			_act_dur = randf_range(2.5, 4.0)
			var ang := randf() * TAU
			_walk_dir = Vector3(cos(ang), 0.0, sin(ang))
		"lick", "peck":
			_act_dur = randf_range(1.0, 1.6)
		"ear":
			_act_dur = 0.7
		_:
			_act_dur = randf_range(2.0, 3.2)

func _end_act() -> void:
	_act = ""
	_next_act = randf_range(3.5, 9.0)
	# 归零由包络终点保证，这里兜底防浮点残差
	if _head != null:
		_head.rotation = Vector3.ZERO
	if _tail != null:
		_tail.rotation = Vector3.ZERO
	for ear in _ears:
		ear.rotation.x = 0.0
	if _species == "chick":
		_model.position.y = 0.0

func _drive_act() -> void:
	var p := clampf(_act_t / _act_dur, 0.0, 1.0)
	var env := sin(PI * p)
	match _act:
		"look":
			# 左右张望，偶尔低一下头
			_head.rotation.y = sin(_act_t * 1.4) * 0.55 * env
			_head.rotation.x = (0.18 if _act_seed % 2 == 0 else 0.0) * env
		"wag":
			if _species == "rabbit":
				_tail.rotation.z = sin(_act_t * 5.0) * 0.25 * env
			else:
				var freq := 9.0 if _species == "dog" else 4.0
				var amp := 0.7 if _species == "dog" else 0.35
				_tail.rotation.y = sin(_act_t * freq) * amp * env
		"ear":
			if not _ears.is_empty():
				var ear: Node3D = _ears[_act_seed % _ears.size()]
				ear.rotation.x = -0.45 * absf(sin(_act_t * 16.0)) * env
		"lick":
			# 低头舔前爪，快速点动
			_head.rotation.x = 0.85 * absf(sin(_act_t * 9.0)) * env
		"sniff":
			# 兔子鼻尖微动嗅闻
			_head.rotation.x = (0.22 + 0.12 * sin(_act_t * 6.0)) * env
		"peck":
			# 小鸡啄米：头部快速下点
			_head.rotation.x = 0.95 * absf(sin(_act_t * 11.0)) * env
		"walk":
			# 沿随机方向走一个往返，身体轻微起伏，朝向平滑跟进
			var dist := CHICK_WALK_RADIUS * sin(PI * p)
			position = _origin + _walk_dir * dist
			if p < 0.5:
				rotation.y = lerp_angle(rotation.y, atan2(_walk_dir.x, _walk_dir.z), 0.12)
			else:
				rotation.y = lerp_angle(rotation.y, atan2(-_walk_dir.x, -_walk_dir.z), 0.12)
			_model.position.y = absf(sin(_act_t * 10.0)) * 0.03 * env

func _assemble(species: String) -> void:
	_species = species
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
	# 头部 pivot 架在颈根：头/吻/眼鼻/耳全挂其下，转头时整体一起转
	var head_r := 0.15 * s
	_head = Node3D.new()
	_head.position = Vector3(0, 0.5 * s, 0.17 * s)
	_model.add_child(_head)
	var head := _sphere(head_r, fur)
	_head.add_child(head)
	# 吻部
	var snout := _box(Vector3(head_r * 0.9, head_r * 0.7, head_r * 0.7), belly_mat)
	snout.position = Vector3(0, -0.04 * s, 0.13 * s)
	_head.add_child(snout)
	# 眼鼻
	for sx in [-1.0, 1.0]:
		var eye := _sphere(head_r * 0.16, dark)
		eye.position = Vector3(sx * head_r * 0.55, 0.03 * s, 0.12 * s)
		_head.add_child(eye)
	var nose := _sphere(head_r * 0.18, dark)
	nose.position = Vector3(0, -0.04 * s, 0.17 * s)
	_head.add_child(nose)
	# 耳朵按物种区分，各自包 pivot 支持抖耳
	var ear_type: String = spec["ear"]
	for sx in [-1.0, 1.0]:
		var ear_size := Vector3(0.06 * s, 0.12 * s, 0.05 * s)
		var ear_pos := Vector3(sx * 0.08 * s, 0.12 * s, -0.03 * s)
		var ear_tilt := 0.0
		match ear_type:
			"pointy":
				ear_size = Vector3(0.06 * s, 0.13 * s, 0.05 * s)
				ear_pos = Vector3(sx * 0.08 * s, 0.14 * s, -0.03 * s)
			"long":
				ear_size = Vector3(0.05 * s, 0.26 * s, 0.04 * s)
				ear_pos = Vector3(sx * 0.07 * s, 0.2 * s, -0.04 * s)
				ear_tilt = -0.2
			_:
				# 狗耷拉耳贴头侧
				ear_size = Vector3(0.04 * s, 0.14 * s, 0.08 * s)
				ear_pos = Vector3(sx * head_r * 0.95, -0.02 * s, -0.01 * s)
		var ear_pivot := Node3D.new()
		ear_pivot.position = ear_pos
		_head.add_child(ear_pivot)
		var ear := _box(ear_size, fur)
		ear.rotation.x = ear_tilt
		ear_pivot.add_child(ear)
		_ears.append(ear_pivot)
	# 尾巴：根部 pivot 驱动摆动；猫竖尾、兔短绒球、狗后伸上翘
	_tail = Node3D.new()
	_tail.position = Vector3(0, 0.34 * s, -0.24 * s)
	_model.add_child(_tail)
	if species == "rabbit":
		var tail := _sphere(0.07 * s, belly_mat)
		tail.position = Vector3(0, -0.14 * s, -0.02 * s)
		_tail.add_child(tail)
	else:
		var tail := _box(Vector3(0.06 * s, 0.18 * s, 0.06 * s), fur)
		tail.rotation.x = -0.5 if species == "dog" else 0.3
		_tail.add_child(tail)

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
	# 头部 pivot：啄米时整体下点
	_head = Node3D.new()
	_head.position = Vector3(0, 0.3, 0.05)
	_model.add_child(_head)
	var head := _sphere(0.075, down)
	_head.add_child(head)
	# 三角喙（小锥）
	var beak := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.028
	cm.height = 0.06
	beak.mesh = cm
	beak.material_override = orange
	beak.rotation.x = PI * 0.5
	beak.position = Vector3(0, -0.01, 0.08)
	_head.add_child(beak)
	# 眼睛
	for sx in [-1.0, 1.0]:
		var eye := _sphere(0.012, dark)
		eye.position = Vector3(sx * 0.032, 0.02, 0.06)
		_head.add_child(eye)
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
