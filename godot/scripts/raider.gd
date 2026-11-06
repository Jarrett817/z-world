extends RigidBody3D
## 邪恶人类掠夺者：路边小队袭击房车。两态状态机——
## ADVANCE 沿路面逼近到交战距离，ENGAGE 保持距离周期性据枪点射。
## 与丧尸同碰撞层（层3），复用子弹鸭子接口 on_shot；被击毙掉落物资。
## 不发射敌方实体子弹：开火用枪口火光+枪声+概率命中结算，避免新增敌我碰撞复杂度。

enum St { ADVANCE, ENGAGE }

const HP_BASE := 5.0            # 略耐打于丧尸（后期随里程成长到 7）
const MOVE_SPEED := 5.8         # 比丧尸冲锋略快，拉得出突袭压力
const ENGAGE_RANGE := 18.0      # 交战保持距离（米）
const FIRE_INTERVAL_MIN := 1.6  # 点射间隔
const FIRE_INTERVAL_MAX := 2.6
const HIT_CHANCE := 0.55        # 每发命中房车的概率（其余只听枪响）
const RV_DMG := 2.2             # 单发房车耐久伤害（main 侧全局冷却再限流）
const FAR_AI_DISTANCE := 45.0
const FAR_AI_INTERVAL := 0.1
const RECYCLE_BEHIND := 40.0    # 被甩到车后这么多米即回收

var main_node: Node3D
var rv: Node3D
var hp := HP_BASE
var state: int = St.ADVANCE
var dead := false
var death_t := 0.0
var should_free := false
var stagger_t := 0.0
var fire_cd := 0.0
var _agent: NavigationAgent3D
var _anim: AnimationPlayer
var _muzzle: Node3D
var _ai_accum := 0.0
var _cur_anim := ""

## main 在 add_child 前调用：注入主场景与角色外观 id（hero/role1/role2）
func setup(main: Node3D, role_id: String) -> void:
	main_node = main
	rv = main.rv
	hp = HP_BASE + clampf(main.dist_km / 200.0, 0.0, 2.0)
	mass = 75.0
	linear_damp = 1.2
	# 同丧尸：layer=层3 让子弹射线命中；mask=层1地面/障碍+层2房车，可贴身围车
	collision_layer = 4
	collision_mask = 3
	lock_rotation = true
	angular_velocity = Vector3.ZERO
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.5
	col.shape = cap
	col.position.y = 0.75
	add_child(col)
	_agent = NavigationAgent3D.new()
	_agent.radius = 0.45
	_agent.max_speed = MOVE_SPEED
	_agent.avoidance_enabled = true
	_agent.velocity_computed.connect(_on_velocity_computed)
	add_child(_agent)
	# 复用队友角色 GLB（战斗态自管动画，关掉活感插播）
	var made := CharUtil.instantiate(role_id, "run", {}, false)
	var figure: Node3D = made["node"]
	add_child(figure)
	_anim = made["anim"]
	if _anim != null:
		for a in ["run", "walk", "aim"]:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	# 自带步枪，挂点与队友/幸存者一致
	var gun := CharUtil.build_gun()
	gun.position = Vector3(-0.12, 1.30, 0.33)
	figure.add_child(gun)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.04, 0.72)
	gun.add_child(_muzzle)
	_tint_hostile(figure)
	fire_cd = randf_range(FIRE_INTERVAL_MIN, FIRE_INTERVAL_MAX)

## 服装压暗偏暖、去饱和：与明媚风景和正常队友拉开敌对观感，但不丑化脸部
func _tint_hostile(root: Node) -> void:
	var tint := Color(0.62, 0.52, 0.48)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var src: Material = m.mesh.surface_get_material(si)
			if src == null or not (src is StandardMaterial3D):
				continue
			var mat: StandardMaterial3D = (src as StandardMaterial3D).duplicate()
			mat.albedo_color = mat.albedo_color * tint
			m.set_surface_override_material(si, mat)

func _physics_process(delta: float) -> void:
	if main_node == null or rv == null:
		return
	if dead:
		death_t -= delta
		if death_t <= 0.0:
			should_free = true
		return
	# 掉出世界 / 被甩到车后视野外 → 回收
	if global_position.y < -8.0 or global_position.z > rv.global_position.z + RECYCLE_BEHIND:
		should_free = true
		return
	if stagger_t > 0.0:
		stagger_t -= delta
		_agent.velocity = Vector3.ZERO
		linear_velocity = Vector3(0, linear_velocity.y, 0)
		return
	# 远处降频省 AI，与丧尸同一套节流
	var rv_dist_sq := global_position.distance_squared_to(rv.global_position)
	_ai_accum += delta
	if rv_dist_sq > FAR_AI_DISTANCE * FAR_AI_DISTANCE and _ai_accum < FAR_AI_INTERVAL:
		return
	var ai_delta := _ai_accum
	_ai_accum = 0.0
	_ai(ai_delta)

## RVO 避让只接管水平速度；垂直仍由刚体重力/地面支撑
func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if dead or stagger_t > 0.0 or main_node.game_over:
		return
	linear_velocity.x = safe_velocity.x
	linear_velocity.z = safe_velocity.z

func _ai(delta: float) -> void:
	if main_node.game_over:
		_agent.velocity = Vector3.ZERO
		linear_velocity = Vector3(0, linear_velocity.y, 0)
		return
	var to_rv := rv.global_position - global_position
	var d_xz := Vector2(to_rv.x, to_rv.z).length()
	if state == St.ADVANCE and d_xz <= ENGAGE_RANGE:
		state = St.ENGAGE
	# 面向房车（+Z 朝向约定：atan2(x,z)）
	var dir := Vector3(to_rv.x, 0.0, to_rv.z)
	if dir.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 8.0)
	if state == St.ADVANCE:
		var ndir := dir.normalized()
		_agent.velocity = Vector3(ndir.x, 0.0, ndir.z) * MOVE_SPEED
		_play("run")
		return
	# ENGAGE：原地据枪点射；房车冲出射程则回身追击
	_agent.velocity = Vector3.ZERO
	linear_velocity = Vector3(0, linear_velocity.y, 0)
	_play("aim")
	if d_xz > ENGAGE_RANGE + 2.0:
		state = St.ADVANCE
		return
	fire_cd -= delta
	if fire_cd <= 0.0:
		fire_cd = randf_range(FIRE_INTERVAL_MIN, FIRE_INTERVAL_MAX)
		_fire()

## 点射：枪口火光+枪声做反馈，命中概率结算房车伤害（main 全局冷却防多人群殴秒杀）
func _fire() -> void:
	var muzzle_ws: Vector3 = _muzzle.global_position if _muzzle != null else global_position + Vector3(0, 1.4, 0)
	main_node.spawn_muzzle_flash(muzzle_ws)
	main_node.sfx.play3d("gunshot", global_position, 0.9, 0.1)
	if randf() < HIT_CHANCE:
		main_node.raider_hit_rv(RV_DMG, global_position)

## 子弹命中鸭子接口（与丧尸同名，main._bullet_impact 直接复用）：爆头 ×2，返回是否击杀
func on_shot(dmg: float, headshot: bool, shot_dir: Vector3) -> bool:
	if dead:
		return true
	hp -= dmg * (2.0 if headshot else 1.0)
	if hp > 0.0:
		stagger_t = 0.3
		var push := Vector3(shot_dir.x, 0.0, shot_dir.z)
		if push.length() > 0.01:
			apply_central_impulse(push.normalized() * mass * 0.9)
		return false
	_die()
	return true

func _die() -> void:
	dead = true
	death_t = 1.2
	set_collision_mask_value(2, false)  # 尸体不挡车
	_agent.velocity = Vector3.ZERO
	linear_velocity = Vector3(0, linear_velocity.y, 0)
	if _anim != null:
		_anim.stop()
	main_node.sfx.play3d("zombie_thud", global_position, 1.0, 0.1)
	# 倒地：绕侧轴倾倒，随后由回收逻辑移除
	var tween := create_tween()
	tween.tween_property(self, "rotation:x", -PI * 0.5, 0.35)
	main_node.spawn_raider_loot(global_position)

func _play(anim_name: String) -> void:
	if anim_name == _cur_anim:
		return
	if _anim != null and _anim.has_animation(anim_name):
		_cur_anim = anim_name
		_anim.play(anim_name, 0.15)
