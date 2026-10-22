extends Node3D
## 路边幸存者：从野地逃命（run）跑向路缘，据枪（aim）反击追兵，被贴身则应急反杀；
## 车辆驶入范围即招募。橙色求救光柱远距可见。

enum St { FLEE, STAND, KITE }

const RUN_SPEED := 4.8
const FIRE_RANGE := 16.0
const FIRE_CD := 1.3
const KITE_RANGE := 3.0   # 丧尸贴身则沿路缘向房车驶来方向风筝

var crew_id := ""
var _main: Node3D
var _beam: MeshInstance3D
var _anim: AnimationPlayer
var _muzzle: Node3D
var _state: int = St.FLEE
var _curb_x := 0.0
var _kite_z := 0.0
var _fire_cd := 0.0

## main.gd 在 add_child 前调用：指定本幸存者对应的队友 id
func setup(cid: String) -> void:
	crew_id = cid

func _ready() -> void:
	_main = get_parent()
	# 战斗态自管 run/aim，关掉活感插播（CharLively 会周期性插播闲置动作打断据枪）
	var made := CharUtil.instantiate(crew_id, "run", {}, false)
	add_child(made["node"])
	_anim = made["anim"]
	if _anim != null:
		for a in ["run", "aim"]:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	# 自带武器：与玩家同款步枪，挂点按 aim 动作对位
	var gun := CharUtil.build_gun()
	gun.position = Vector3(-0.12, 1.30, 0.33)
	made["node"].add_child(gun)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.04, 0.72)
	gun.add_child(_muzzle)
	# 逃命目标：本侧路缘
	var side := signf(position.x - _main.road_x(position.z))
	if side == 0.0:
		side = 1.0
	_curb_x = _main.road_x(position.z) + side * (_main.ROAD_HALF - 0.5)

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
	area.collision_mask = 2  # 房车独占碰撞层2
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
	if _main.game_over:
		return
	_fire_cd -= delta
	match _state:
		St.FLEE:
			_move_toward(Vector3(_curb_x, 0.0, position.z), delta)
			if absf(position.x - _curb_x) < 0.3:
				_state = St.STAND
				_play("aim")
		St.KITE:
			_move_toward(Vector3(_curb_x, 0.0, _kite_z), delta)
			if absf(position.z - _kite_z) < 0.4:
				_state = St.STAND
				_play("aim")
		St.STAND:
			var z := _nearest_zombie(FIRE_RANGE)
			if z != null:
				_face(z.global_position, delta)
				if _fire_cd <= 0.0:
					_fire_at(z)
				if global_position.distance_to(z.global_position) < KITE_RANGE:
					# 贴太近了：收起枪沿路缘向房车方向跑一段再回身据枪
					_state = St.KITE
					_kite_z = position.z + 7.0
					_play("run")
			else:
				# 无威胁时面向公路，朝驶来的房车示意
				rotation.y = lerp_angle(rotation.y, 0.0, delta * 3.0)

## 丧尸贴身啃咬钩子：应急反杀（幸存者都是见过世面的狠角色，本轮不设死亡）
func on_bitten(z: Node3D) -> void:
	_face(z.global_position, 1.0)
	_fire_at(z)

func _fire_at(z: Node3D) -> void:
	_fire_cd = FIRE_CD
	var from := _muzzle.global_position
	var dir := (z.global_position + Vector3(0, 1.1, 0) - from).normalized()
	_main.spawn_bullet(from, dir, 600.0, [])
	_main.spawn_muzzle_flash(from)
	_main.sfx.play3d("gunshot", global_position, 0.9, 0.08)

func _move_toward(target: Vector3, delta: float) -> void:
	var to := target - position
	to.y = 0.0
	var step: float = RUN_SPEED * delta
	if to.length() > step:
		var dir := to.normalized()
		position += dir * step
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 10.0)
	else:
		position.x = target.x
		position.z = target.z
	position.y = _main.ground_height(position.x, position.z)

func _face(target: Vector3, delta: float) -> void:
	var to := target - global_position
	if Vector2(to.x, to.z).length() < 0.05:
		return
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), delta * 8.0)

func _nearest_zombie(max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for z in _main.zombies:
		if is_instance_valid(z) and not z.dead:
			var d := global_position.distance_to(z.global_position)
			if d < best_d:
				best_d = d
				best = z
	return best

func _play(anim_name: String) -> void:
	if _anim != null and _anim.has_animation(anim_name) and _anim.current_animation != anim_name:
		_anim.play(anim_name, 0.15)

func _on_body(body: Node3D) -> void:
	if body == _main.rv:
		_main.try_recruit(self)
