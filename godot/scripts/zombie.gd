extends RigidBody3D
## 丧尸 AI：各处踱步游荡（WANDER/IDLE），听到声音才进入狂暴冲锋（CHASE）。
## 声源：引擎声随车速扩大感知半径（main 每物理帧推送），枪声全向大半径（on_hear_gunshot）。
## 目标：玩家下车后优先追玩家，否则追房车；贴身啃咬；被撞飞物理接管；高速碾压播放 Death。

const WALK := &"Walk"
const ATTACK := &"Attack"
const DEATH := &"Death"
const BITE_RANGE := 4.4
const BITE_INTERVAL := 0.8
const WANDER_SPEED := 0.9
const CHASE_SPEED_BASE := 5.2

enum St { WANDER, IDLE, CHASE }

var main_node: Node3D
var rv: Node3D
var hunt_target: Node3D   # 锁定猎杀目标（如逃命的幸存者）；null 时按玩家→房车优先级
var speed := 2.0
var state: int = St.WANDER
var state_t := 0.0
var wander_target := Vector3.ZERO
var flung_t := 0.0
var bite_t := 0.0
var dead := false
var death_t := 0.0
var should_free := false
var growl_t := 0.0
var anim: AnimationPlayer

func setup(main: Node3D) -> void:
	main_node = main
	rv = main.rv
	speed = CHASE_SPEED_BASE + randf_range(-0.8, 1.4) * (1.0 + clampf(main.dist_km * 0.05, 0.0, 0.5))
	mass = 70.0
	linear_damp = 1.2
	# 锁死物理旋转：否则胶囊体受地面/碰撞扭矩会整体乱转，朝向只由 AI 脚本控制
	lock_rotation = true
	angular_velocity = Vector3.ZERO
	_vary_materials(self)
	anim = _find_anim_player(self)
	state = St.WANDER if randf() < 0.7 else St.IDLE
	state_t = randf_range(1.5, 5.0)
	_pick_wander_target()
	if anim == null:
		return
	var names := anim.get_animation_list()
	if WALK in names:
		anim.get_animation(WALK).loop_mode = Animation.LOOP_LINEAR
		anim.play(WALK)
		# 随机起步相位，避免尸群动作同步
		anim.seek(randf() * anim.get_animation(WALK).length, true)
	if ATTACK in names:
		anim.get_animation(ATTACK).loop_mode = Animation.LOOP_NONE
	if DEATH in names:
		anim.get_animation(DEATH).loop_mode = Animation.LOOP_NONE
	_apply_anim_rate()

## 复制材质并随机染色，让尸群出现不同腐烂程度/尸变阶段的色差
func _vary_materials(node: Node) -> void:
	# 四档色调：新鲜尸变（泛青）/ 普通腐绿 / 严重溃烂（泛黄）/ 干瘪发黑
	var tints: Array[Color] = [
		Color(0.72, 0.78, 0.82),
		Color(0.82, 0.86, 0.72),
		Color(0.86, 0.78, 0.62),
		Color(0.68, 0.66, 0.62),
	]
	var tint: Color = tints.pick_random()
	var brightness := randf_range(0.85, 1.05)
	for c in node.get_children():
		if c is MeshInstance3D:
			_tint_mesh(c as MeshInstance3D, tint * brightness)
		_vary_materials(c)

func _tint_mesh(mi: MeshInstance3D, tint: Color) -> void:
	if mi.mesh == null:
		return
	for si in mi.mesh.get_surface_count():
		var src: Material = mi.mesh.surface_get_material(si)
		if src == null or not (src is StandardMaterial3D):
			continue
		var m: StandardMaterial3D = src.duplicate() as StandardMaterial3D
		m.albedo_color = m.albedo_color * tint
		mi.set_surface_override_material(si, m)

func _find_anim_player(node: Node) -> AnimationPlayer:
	for c in node.get_children():
		if c is AnimationPlayer:
			return c
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null

func _physics_process(delta: float) -> void:
	if main_node == null or rv == null:
		return
	if dead:
		death_t -= delta
		if death_t <= 0.0:
			should_free = true
		return
	# 掉出世界 / 被甩到车后视野外 → 回收
	if global_position.y < -8.0 or global_position.z > rv.global_position.z + 40.0:
		should_free = true
		return
	if flung_t > 0.0:
		flung_t -= delta
		return
	_ai(delta)

# ---------- 声音感知 ----------

## 枪声：全向大半径，听到立即狂暴
func on_hear_gunshot(pos: Vector3) -> void:
	if state == St.CHASE:
		return
	if global_position.distance_to(pos) < 85.0:
		_enter_chase()

## 引擎声：房车每物理帧推送，半径随车速；停车时只有贴脸才惊动
func on_engine_noise(pos: Vector3, radius: float) -> void:
	if state == St.CHASE:
		return
	if global_position.distance_to(pos) < radius:
		_enter_chase()

func _enter_chase() -> void:
	state = St.CHASE
	bite_t = 0.0

## 是否正在狂暴冲锋（供音乐/氛围状态判定）
func is_hunting() -> bool:
	return state == St.CHASE and not dead

# ---------- 状态机 ----------

func _ai(delta: float) -> void:
	if main_node.game_over:
		linear_velocity = Vector3(0, linear_velocity.y, 0)
		return
	state_t -= delta
	match state:
		St.IDLE:
			linear_velocity = Vector3(0, linear_velocity.y, 0)
			if anim != null:
				anim.speed_scale = 1.0
			if state_t <= 0.0:
				state = St.WANDER
				state_t = randf_range(3.0, 8.0)
				_pick_wander_target()
		St.WANDER:
			_wander(delta)
		St.CHASE:
			_chase(delta)

## 踱步：朝附近随机点慢走，到点或超时就停下发呆
func _wander(delta: float) -> void:
	var to := wander_target - global_position
	to.y = 0.0
	if to.length() < 1.5 or state_t <= 0.0:
		state = St.IDLE
		state_t = randf_range(1.5, 5.0)
		linear_velocity = Vector3(0, linear_velocity.y, 0)
		return
	var dir := to.normalized()
	linear_velocity = Vector3(dir.x * WANDER_SPEED, linear_velocity.y, dir.z * WANDER_SPEED)
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 4.0)
	if anim != null:
		anim.speed_scale = 0.7

func _pick_wander_target() -> void:
	# 只在自己当前位置周围踱步，不主动朝路/车靠拢
	var ang := randf() * TAU
	var r := randf_range(3.0, 14.0)
	wander_target = global_position + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
	wander_target.y = global_position.y

## 狂暴冲锋：玩家下车优先追玩家，否则追房车，贴身啃咬
func _chase(delta: float) -> void:
	# 追击嘶吼：随机间隔，3D 方位衰减
	growl_t -= delta
	if growl_t <= 0.0:
		growl_t = randf_range(4.0, 9.0)
		main_node.sfx.play3d("zombie_growl", global_position, 1.0, 0.15)
	var target_pos: Vector3 = rv.global_position
	var player: Node3D = main_node.get_player_body()
	var hunt: Node3D = hunt_target if is_instance_valid(hunt_target) else null
	if hunt != null:
		target_pos = hunt.global_position
	elif is_instance_valid(player):
		target_pos = player.global_position
	var to_t := target_pos - global_position
	var d_xz := Vector2(to_t.x, to_t.z).length()
	if d_xz > BITE_RANGE:
		var dir := Vector3(to_t.x, 0.0, to_t.z).normalized()
		linear_velocity = Vector3(dir.x * speed, linear_velocity.y, dir.z * speed)
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 8.0)
		_play(WALK)
		if anim != null:
			anim.speed_scale = clampf(speed * 0.45, 1.4, 2.8)
	else:
		# 贴身啃咬：猎杀目标有自卫钩子则交给它（幸存者反杀），玩家由 main 结算，否则啃车
		linear_velocity = Vector3(0, linear_velocity.y, 0)
		if anim != null:
			anim.speed_scale = 1.0
		bite_t += delta
		if bite_t >= BITE_INTERVAL:
			bite_t = 0.0
			if hunt != null and hunt.has_method("on_bitten"):
				hunt.on_bitten(self)
			elif is_instance_valid(player):
				main_node.on_player_bitten()
			else:
				main_node.zombie_bite()
			main_node.sfx.play3d("zombie_bite", global_position, 1.0, 0.1)
			_play_once(ATTACK)

func on_hit_by_rv(speed_kmh: float, _normal: Vector3) -> void:
	if dead:
		return
	var dir := global_position - rv.global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.BACK
	var v := 5.0 + speed_kmh * 0.16
	apply_central_impulse((dir + Vector3.UP * 0.55).normalized() * mass * v)
	flung_t = 1.3
	_stop_anim()
	if speed_kmh > 45.0:
		dead = true
		death_t = 1.5
		main_node.sfx.play3d("zombie_die", global_position, 1.1, 0.12)
		_play_once(DEATH)

## 被玩家武器击中：低速车辆撞不死的枪下亡魂
func on_shot() -> void:
	if dead:
		return
	dead = true
	death_t = 1.5
	linear_velocity = Vector3(0, linear_velocity.y, 0)
	main_node.sfx.play3d("zombie_die", global_position, 1.0, 0.12)
	_play_once(DEATH)

func _apply_anim_rate() -> void:
	if anim != null:
		anim.speed_scale = 1.0

func _play(anim_name: StringName) -> void:
	if anim != null and anim_name in anim.get_animation_list() and anim.current_animation != String(anim_name):
		anim.play(anim_name)

func _play_once(anim_name: StringName) -> void:
	if anim != null and anim_name in anim.get_animation_list():
		anim.play(anim_name)

func _stop_anim() -> void:
	if anim != null:
		anim.stop()
