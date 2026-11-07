extends Node3D
## 路边待救助小动物：温顺无害，在路肩有限范围内踱步/发呆，头顶粉色心形标识远距可见。
## 房车（或下车玩家）进入触发区即被救上车：跑向房车后消失，由 main.rescue_animal 结算士气收益。
## 全程序化网格（项目无动物 GLB），不参与战斗、不可中弹、不与任何实体物理互撞。

enum St { WANDER, IDLE, BOARD }

## 三种小动物的外观与体型参数（尺寸单位：米）
const SPECIES := {
	"dog": {"color": Color(0.72, 0.5, 0.3), "belly": Color(0.82, 0.68, 0.5), "body": Vector3(0.34, 0.34, 0.62), "leg": 0.3, "head": 0.2, "ear": "floppy"},
	"cat": {"color": Color(0.62, 0.62, 0.66), "belly": Color(0.8, 0.78, 0.75), "body": Vector3(0.26, 0.26, 0.46), "leg": 0.24, "head": 0.16, "ear": "pointy"},
	"rabbit": {"color": Color(0.85, 0.78, 0.7), "belly": Color(0.95, 0.92, 0.88), "body": Vector3(0.24, 0.26, 0.36), "leg": 0.18, "head": 0.15, "ear": "long"},
}
const WALK_SPEED := 1.6
const WANDER_RADIUS := 4.0
const RECYCLE_BEHIND := 40.0

var species := "dog"
var _main: Node3D
var _state: int = St.IDLE
var _state_t := 0.0
var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _t := 0.0
var _base_y := 0.0
var _heart: MeshInstance3D
var _model: Node3D

## main 在 add_child 前调用：指定物种
func setup(sp: String) -> void:
	species = sp

func _ready() -> void:
	_main = get_parent()
	add_to_group("consumable")
	add_to_group("animal")
	_home = position
	_base_y = position.y
	_state_t = randf_range(0.5, 2.0)
	_build_body()
	_build_marker()
	# 触发区：层1玩家 + 层2房车；动物在路肩外 2~8m，横向加宽确保房车经过即可扫到
	var area := Area3D.new()
	area.collision_mask = 3
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(11.0, 2.6, 6.0)
	cs.shape = shape
	cs.position.y = 0.8
	area.add_child(cs)
	area.body_entered.connect(_on_body)
	add_child(area)

func _build_body() -> void:
	var spec: Dictionary = SPECIES[species]
	_model = Node3D.new()
	add_child(_model)
	var fur := _mat(spec["color"])
	var belly_mat := _mat(spec["belly"])
	var dark := _mat(Color(0.12, 0.1, 0.09))
	var body_size: Vector3 = spec["body"]
	var leg_h: float = spec["leg"]
	var head_r: float = spec["head"]
	var body_y := leg_h + body_size.y * 0.5
	# 躯干
	var torso := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = body_size
	torso.mesh = bm
	torso.position.y = body_y
	torso.material_override = fur
	_model.add_child(torso)
	# 腹部浅色块
	var belly := MeshInstance3D.new()
	var blm := BoxMesh.new()
	blm.size = Vector3(body_size.x * 0.7, body_size.y * 0.5, 0.04)
	belly.mesh = blm
	belly.position = Vector3(0, body_y - body_size.y * 0.12, body_size.z * 0.5 + 0.005)
	belly.material_override = belly_mat
	_model.add_child(belly)
	# 四条腿
	var lx := body_size.x * 0.32
	var lz := body_size.z * 0.34
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.09, leg_h, 0.09)
			leg.mesh = lm
			leg.position = Vector3(sx * lx, leg_h * 0.5, sz * lz)
			leg.material_override = fur
			_model.add_child(leg)
	# 头（朝 +Z）
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = head_r
	hm.height = head_r * 2.0
	head.mesh = hm
	var head_z := body_size.z * 0.5 + head_r * 0.55
	head.position = Vector3(0, body_y + body_size.y * 0.25, head_z)
	head.material_override = fur
	_model.add_child(head)
	# 吻部
	var snout := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(head_r * 0.9, head_r * 0.7, head_r * 0.8)
	snout.mesh = sm
	snout.position = Vector3(0, body_y + body_size.y * 0.12, head_z + head_r * 0.75)
	snout.material_override = belly_mat
	_model.add_child(snout)
	# 眼睛 + 鼻子
	for sx in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = head_r * 0.16
		em.height = head_r * 0.32
		eye.mesh = em
		eye.position = Vector3(sx * head_r * 0.55, body_y + body_size.y * 0.38, head_z + head_r * 0.72)
		eye.material_override = dark
		_model.add_child(eye)
	var nose := MeshInstance3D.new()
	var nm := SphereMesh.new()
	nm.radius = head_r * 0.2
	nm.height = head_r * 0.4
	nose.mesh = nm
	nose.position = Vector3(0, body_y + body_size.y * 0.14, head_z + head_r * 1.15)
	nose.material_override = dark
	_model.add_child(nose)
	# 耳朵按物种区分
	var ear_type: String = spec["ear"]
	var ear_base_y := body_y + body_size.y * 0.25 + head_r * 0.8
	for sx in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var em2 := BoxMesh.new()
		match ear_type:
			"pointy":
				em2.size = Vector3(head_r * 0.4, head_r * 0.7, head_r * 0.3)
				ear.position = Vector3(sx * head_r * 0.5, ear_base_y + head_r * 0.2, head_z - head_r * 0.1)
				ear.rotation.x = -0.15
			"long":
				em2.size = Vector3(head_r * 0.35, head_r * 1.7, head_r * 0.22)
				ear.position = Vector3(sx * head_r * 0.45, ear_base_y + head_r * 0.7, head_z - head_r * 0.15)
				ear.rotation.x = -0.25
			_:
				# 狗的耷拉耳：贴在头侧下垂
				em2.size = Vector3(head_r * 0.25, head_r * 0.9, head_r * 0.5)
				ear.position = Vector3(sx * head_r * 0.85, ear_base_y - head_r * 0.25, head_z)
		ear.mesh = em2
		ear.material_override = fur
		_model.add_child(ear)
	# 尾巴（朝 -Z 上翘）
	var tail := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.07, 0.07, body_size.z * 0.5)
	tail.mesh = tm
	tail.position = Vector3(0, body_y + body_size.y * 0.2, -body_size.z * 0.5 - body_size.z * 0.18)
	tail.rotation.x = -0.7
	tail.material_override = fur
	_model.add_child(tail)
	# 兔子后腿更粗壮（前短后长的蹲姿观感）
	if species == "rabbit":
		for sx in [-1.0, 1.0]:
			var hind := MeshInstance3D.new()
			var hm2 := BoxMesh.new()
			hm2.size = Vector3(0.12, leg_h * 0.7, 0.22)
			hind.mesh = hm2
			hind.position = Vector3(sx * lx, leg_h * 0.35, -lz)
			hind.material_override = fur
			_model.add_child(hind)

## 头顶粉色心形：两个小球 + 倒锥拼合，缓慢旋转 + 上下浮动
func _build_marker() -> void:
	_heart = MeshInstance3D.new()
	var pink := StandardMaterial3D.new()
	pink.albedo_color = Color(1.0, 0.45, 0.6)
	pink.emission_enabled = true
	pink.emission = Color(1.0, 0.35, 0.5)
	pink.emission_energy_multiplier = 1.6
	pink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for sx in [-1.0, 1.0]:
		var lobe := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.18
		lobe.mesh = sm
		lobe.position.x = sx * 0.085
		lobe.position.y = 0.05
		lobe.material_override = pink
		_heart.add_child(lobe)
	var tip := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.13
	cm.bottom_radius = 0.0
	cm.height = 0.22
	tip.mesh = cm
	tip.position.y = -0.08
	tip.rotation.z = PI
	tip.material_override = pink
	_heart.add_child(tip)
	_heart.position.y = 1.25
	add_child(_heart)
	# 夜间也能看到的柔和粉光
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.55, 0.65)
	glow.omni_range = 3.2
	glow.light_energy = 0.6
	glow.position.y = 0.9
	add_child(glow)

func _process(delta: float) -> void:
	if _main == null or _main.game_over:
		return
	_t += delta
	_heart.rotation.y += delta * 1.5
	_heart.position.y = 1.25 + sin(_t * 2.5) * 0.08
	match _state:
		St.WANDER:
			_do_wander(delta)
		St.IDLE:
			_state_t -= delta
			_model.position.y = sin(_t * 3.0) * 0.015
			if _state_t <= 0.0:
				_pick_wander()
		St.BOARD:
			_do_board(delta)
	# 被甩到车后 → 交由 main 的 consumable 统一回收（双保险：这里先兜底）
	if global_position.z > _main.rv.global_position.z + RECYCLE_BEHIND:
		queue_free()

func _do_wander(delta: float) -> void:
	var to := _target - position
	to.y = 0.0
	if to.length() < 0.25:
		_state = St.IDLE
		_state_t = randf_range(1.2, 3.5)
		return
	var dir := to.normalized()
	position.x += dir.x * WALK_SPEED * delta
	position.z += dir.z * WALK_SPEED * delta
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 8.0)
	# 兔子一跳一跳，其余小幅踱步起伏
	var bob_freq := 9.0 if species == "rabbit" else 5.0
	_model.position.y = absf(sin(_t * bob_freq)) * (0.09 if species == "rabbit" else 0.035)
	_state_t -= delta
	if _state_t <= 0.0:
		_state = St.IDLE
		_state_t = randf_range(1.0, 3.0)

func _pick_wander() -> void:
	var ang := randf() * TAU
	var r := randf() * WANDER_RADIUS
	_target = _home + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
	_state = St.WANDER
	_state_t = randf_range(2.5, 5.0)

## 被救助：收起心形，跑向房车，贴近即消失（收益在触发瞬间已由 main 结算）
func _do_board(delta: float) -> void:
	var door: Vector3 = _main.rv.global_position
	var flat := Vector2(position.x - door.x, position.z - door.z).length()
	if flat < 1.6 or flat > 45.0:
		queue_free()
		return
	var dir := (door - position)
	dir.y = 0.0
	dir = dir.normalized()
	position.x += dir.x * WALK_SPEED * 1.8 * delta
	position.z += dir.z * WALK_SPEED * 1.8 * delta
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 10.0)
	_model.position.y = absf(sin(_t * 8.0)) * 0.06

func _on_body(body: Node3D) -> void:
	if _state == St.BOARD:
		return
	if body == _main.rv or body == _main.get_player_body():
		_state = St.BOARD
		_heart.visible = false
		_main.rescue_animal(species)

func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	return m
