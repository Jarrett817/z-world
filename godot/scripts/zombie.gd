extends RigidBody3D
## 丧尸 AI：各处踱步游荡（WANDER/IDLE），听到声音才进入狂暴冲锋（CHASE）。
## 声源：引擎声随车速扩大感知半径（main 每物理帧推送），枪声全向大半径（on_hear_gunshot）。
## 目标：玩家下车后优先追玩家，否则追房车；贴身啃咬；被撞飞物理接管；高速碾压播放 Death。

const WALK := &"Walk"
const ATTACK := &"Attack"
const DEATH := &"Death"
const BITE_RANGE := 4.4
const RV_BITE_RANGE := 1.25
const BITE_INTERVAL := 0.8
const WANDER_SPEED := 0.9
const CHASE_SPEED_BASE := 5.2
const FAR_AI_DISTANCE := 45.0
const FAR_AI_INTERVAL := 0.1
const SHADOW_DISTANCE := 30.0
const ANIM_DISTANCE := 70.0
const RENDER_DISTANCE := 100.0
const RVO_DISTANCE := 26.0        # 仅近身丧尸参与 RVO 局部避让，远处游荡丧尸关闭以降尸群开销
const GROUND_SNAP_TOL := 0.35     # 活体离地超过该高度则拉回地形面（修浮空）
const HEADSHOT_Y := 1.05          # 命中点高于碰撞原点该值即爆头（胶囊上半球=头颈，一击必杀）
const FLASH_TIME := 0.14          # 受击红闪时长
const HP_BAR_HEIGHT := 2.35       # 头顶血条离地高度
const ROOF_SAFE_DY := 2.2         # 玩家高出丧尸该米数时处于车顶/够不到的位置，免疫啃咬
const PLAYER_SUNROOF := 1         # player.Mode.SUNROOF 枚举值（避免跨脚本类型依赖）

enum St { WANDER, IDLE, CHASE }

var main_node: Node3D
var rv: Node3D
var hunt_target: Node3D   # 锁定猎杀目标（如逃命的幸存者）；null 时按玩家→房车优先级
var speed := 2.0
var state: int = St.WANDER
var state_t := 0.0
var wander_target := Vector3.ZERO
var flung_t := 0.0
var stagger_t := 0.0  # 中弹硬直：短暂定身，读得出命中感
var hp := 2.0         # 身体血量；爆头一击必杀，身体按枪械 dmg 扣血
var max_hp := 2.0     # 血量上限（血条比例用，setup 时与 hp 同步）
var bite_t := 0.0
var dead := false
var death_t := 0.0
var should_free := false
var growl_t := 0.0
var anim: AnimationPlayer
var _agent: NavigationAgent3D
var _ai_accum := 0.0
var _meshes: Array[MeshInstance3D] = []
var _shadows_on := true
var _flash_t := 0.0                       # 受击红闪剩余时间
var _flash_mats: Array[StandardMaterial3D] = []  # 各网格当前的红闪材质（还原用）
var _origin_mats: Array[Material] = []    # 与 _flash_mats 对应的原始材质
var _flash_slots: Array = []              # 与 _flash_mats 平行的 [MeshInstance3D, surface_index] 还原位置
var _hp_bar: Sprite3D                     # 头顶世界空间血条（仅受损后出现）
var _hp_bar_bg: Sprite3D
var _hp_bar_w := 0.9

func setup(main: Node3D) -> void:
	main_node = main
	rv = main.rv
	speed = CHASE_SPEED_BASE + randf_range(-0.8, 1.4) * (1.0 + clampf(main.dist_km * 0.05, 0.0, 0.5))
	hp = 2.0 + clampf(main.dist_km / 150.0, 0.0, 2.0)  # 后期更耐打：150km 后 3、300km 后 4
	max_hp = hp
	mass = 70.0
	linear_damp = 1.2
	# layer=层3(丧尸独占)：房车不再与丧尸物理互撞（碾压由房车触发区接管），子弹射线仍正常命中
	collision_layer = 4
	# mask=层1(地面/障碍/玩家)+层2(房车)：平时能贴身围车；被撞飞/击毙后清第2位不再蹭车
	collision_mask = 3
	# 锁死物理旋转：否则胶囊体受地面/碰撞扭矩会整体乱转，朝向只由 AI 脚本控制
	lock_rotation = true
	angular_velocity = Vector3.ZERO
	_agent = NavigationAgent3D.new()
	_agent.radius = 0.5
	_agent.max_speed = 8.0
	_agent.avoidance_enabled = true
	_agent.velocity_computed.connect(_on_velocity_computed)
	add_child(_agent)
	_vary_materials(self)
	anim = _find_anim_player(self)
	state = St.WANDER if randf() < 0.7 else St.IDLE
	_agent.avoidance_enabled = state != St.IDLE
	_ai_accum = randf_range(0.0, FAR_AI_INTERVAL)
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
			var mi := c as MeshInstance3D
			_tint_mesh(mi, tint * brightness)
			mi.visibility_range_end = RENDER_DISTANCE
			_meshes.append(mi)
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
	_update_hit_flash(delta)
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
		if flung_t <= 0.0:
			var local := rv.to_local(global_position)
			if absf(local.x) < 2.35 and absf(local.z) < 5.45:
				global_position = rv.to_global(_rv_escape(local))
			set_collision_mask_value(2, true)  # 先脱离重叠再恢复车身碰撞，避免把丧尸弹入地下或留在车厢
		return
	if stagger_t > 0.0:
		stagger_t -= delta
		_agent.velocity = Vector3.ZERO
		linear_velocity = Vector3(0, linear_velocity.y, 0)
		return
	# 地面贴合：活体（非撞飞/硬直）若因地形重建等原因离地或陷入，拉回地形高度
	var gy: float = main_node.ground_height(global_position.x, global_position.z)
	if absf(global_position.y - gy) > GROUND_SNAP_TOL:
		global_position.y = gy
	var rv_dist_sq := global_position.distance_squared_to(rv.global_position)
	var shadows_on := rv_dist_sq < SHADOW_DISTANCE * SHADOW_DISTANCE
	if shadows_on != _shadows_on:
		_shadows_on = shadows_on
		for mi in _meshes:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows_on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if anim != null:
		var should_animate := rv_dist_sq < ANIM_DISTANCE * ANIM_DISTANCE
		if anim.active != should_animate:
			anim.active = should_animate
	# RVO 性能门控：只有近身的冲锋丧尸才参与局部避让计算，远处游荡者关闭，减少尸群导航开销
	var want_rvo := state == St.CHASE and rv_dist_sq < RVO_DISTANCE * RVO_DISTANCE
	if _agent.avoidance_enabled != want_rvo:
		_agent.avoidance_enabled = want_rvo
	_ai_accum += delta
	if rv_dist_sq > FAR_AI_DISTANCE * FAR_AI_DISTANCE and _ai_accum < FAR_AI_INTERVAL:
		return
	var ai_delta := _ai_accum
	_ai_accum = 0.0
	_ai(ai_delta)

## 原生 RVO 避让只接管追逐/游荡的水平速度；撞飞、硬直和死亡仍由刚体物理接管
func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if dead or flung_t > 0.0 or stagger_t > 0.0 or main_node.game_over:
		return
	linear_velocity.x = safe_velocity.x
	linear_velocity.z = safe_velocity.z

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
		_agent.velocity = Vector3.ZERO
		linear_velocity = Vector3(0, linear_velocity.y, 0)
		return
	state_t -= delta
	match state:
		St.IDLE:
			_agent.velocity = Vector3.ZERO
			linear_velocity = Vector3(0, linear_velocity.y, 0)
			if anim != null:
				anim.speed_scale = 1.0
			if state_t <= 0.0:
				state = St.WANDER
				_agent.avoidance_enabled = true
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
		_agent.avoidance_enabled = false
		state_t = randf_range(1.5, 5.0)
		_agent.velocity = Vector3.ZERO
		linear_velocity = Vector3(0, linear_velocity.y, 0)
		return
	var dir := to.normalized()
	_agent.velocity = dir * WANDER_SPEED
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 4.0)
	if anim != null:
		anim.speed_scale = 0.7

func _pick_wander_target() -> void:
	# 只在自己当前位置周围踱步，不主动朝路/车靠拢
	var ang := randf() * TAU
	var r := randf_range(3.0, 14.0)
	wander_target = global_position + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
	wander_target.y = global_position.y
	_agent.target_position = wander_target

## 与车壳重叠时沿最近侧面撤到车外；居中固定向正侧脱离，避免 signf(0) 原地停留
func _rv_escape(local: Vector3) -> Vector3:
	var gap_x := 2.35 - absf(local.x)
	var gap_z := 5.45 - absf(local.z)
	if gap_x < gap_z:
		local.x = (1.0 if local.x >= 0.0 else -1.0) * 2.35
	else:
		local.z = (1.0 if local.z >= 0.0 else -1.0) * 5.45
	return local

## 狂暴冲锋：玩家下车优先追玩家，否则追房车，贴身啃咬
func _chase(delta: float) -> void:
	# 追击嘶吼：随机间隔，3D 方位衰减
	growl_t -= delta
	if growl_t <= 0.0:
		growl_t = randf_range(4.0, 9.0)
		main_node.sfx.play3d("zombie_growl", global_position, 1.0, 0.15)
	var target_pos: Vector3 = rv.global_position
	# 车内行走玩家不是可啃咬目标：追车外壳，不能穿过车厢追人
	var player: Node3D = null if main_node.rv_walk_active else main_node.get_player_body()
	if is_instance_valid(player) and int(player.get("mode")) == PLAYER_SUNROOF \
			and player.global_position.y - global_position.y > ROOF_SAFE_DY:
		# 玩家在车顶天窗守卫位、垂直高差超出丧尸可达范围：够不到，改为围车
		player = null
	var hunt: Node3D = hunt_target if is_instance_valid(hunt_target) else null
	if hunt != null:
		target_pos = hunt.global_position
	elif is_instance_valid(player):
		target_pos = player.global_position
	var bite_range := BITE_RANGE
	if hunt == null and not is_instance_valid(player):
		# 房车是 3.8×10m 长方体：重叠时先强制退出车壳，正常追击仍只贴外表面
		var local := rv.to_local(global_position)
		if absf(local.x) < 2.35 and absf(local.z) < 5.45:
			target_pos = rv.to_global(_rv_escape(local))
			bite_range = 0.0
		else:
			var surface := Vector2(clampf(local.x, -1.95, 1.95), clampf(local.z, -5.05, 5.05))
			target_pos = rv.to_global(Vector3(surface.x, 0.0, surface.y))
			bite_range = RV_BITE_RANGE
	var to_t := target_pos - global_position
	var d_xz := Vector2(to_t.x, to_t.z).length()
	if d_xz > bite_range:
		var dir := Vector3(to_t.x, 0.0, to_t.z).normalized()
		_agent.velocity = dir * speed
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 8.0)
		_play(WALK)
		if anim != null:
			anim.speed_scale = clampf(speed * 0.45, 1.4, 2.8)
	else:
		# 贴身啃咬：猎杀目标有自卫钩子则交给它（幸存者反杀），玩家由 main 结算，否则啃车
		_agent.velocity = Vector3.ZERO
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
	set_collision_mask_value(2, false)  # 撞飞后不再与房车碰撞，避免尸体挡车顿帧
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

## 被玩家武器击中：爆头一击必杀；身体命中扣血并触发红闪/血条/伤害数字/硬直
func on_shot(dmg: float, headshot: bool, dir: Vector3) -> bool:
	if dead:
		return true
	if headshot:
		hp = 0.0
		_spawn_damage_number(0.0, true)
		return _die()
	hp -= dmg
	_trigger_flash()
	_spawn_damage_number(dmg, false)
	if hp > 0.0:
		_update_hp_bar()
		stagger_t = 0.32
		var push := Vector3(dir.x, 0.0, dir.z)
		if push.length() > 0.01:
			apply_central_impulse(push.normalized() * mass * 0.9)
		return false
	return _die()

## 死亡公共路径：尸体不挡车、停 AI、播死亡音效与动画，返回 true 供调用方做击杀反馈
func _die() -> bool:
	set_collision_mask_value(2, false)
	dead = true
	death_t = 1.5
	_agent.velocity = Vector3.ZERO
	linear_velocity = Vector3(0, linear_velocity.y, 0)
	if _hp_bar != null:
		_hp_bar.visible = false
		_hp_bar_bg.visible = false
	main_node.sfx.play3d("zombie_die", global_position, 1.0, 0.12)
	_play_once(DEATH)
	return true

# ---------- 命中反馈 ----------

## 受击红闪：各网格材质临时换为自发光红色，FLASH_TIME 后由 _update_hit_flash 还原
func _trigger_flash() -> void:
	_flash_t = FLASH_TIME
	if not _flash_mats.is_empty():
		return
	for mi in _meshes:
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var src: Material = mi.get_surface_override_material(si)
			if src == null or not (src is StandardMaterial3D):
				continue
			_origin_mats.append(src)
			var fm: StandardMaterial3D = (src as StandardMaterial3D).duplicate()
			fm.albedo_color = Color(1.0, 0.15, 0.12)
			fm.emission_enabled = true
			fm.emission = Color(1.0, 0.08, 0.05)
			fm.emission_energy_multiplier = 1.6
			mi.set_surface_override_material(si, fm)
			_flash_mats.append(fm)
			_flash_slots.append([mi, si])

func _update_hit_flash(delta: float) -> void:
	if _flash_t <= 0.0 or _flash_mats.is_empty():
		return
	_flash_t -= delta
	if _flash_t > 0.0:
		return
	# 倒计时结束：按记录的 (网格, 表面) 配对还原原始材质
	for i in _flash_slots.size():
		var slot: Array = _flash_slots[i]
		(slot[0] as MeshInstance3D).set_surface_override_material(int(slot[1]), _origin_mats[i])
	_flash_mats.clear()
	_origin_mats.clear()
	_flash_slots.clear()

## 头顶血条：受损后才懒构建，Sprite3D 自带 billboard 始终面向相机
func _build_hp_bar() -> void:
	var tex := _white_texture()
	_hp_bar_bg = Sprite3D.new()
	_hp_bar_bg.texture = tex
	_hp_bar_bg.modulate = Color(0.12, 0.05, 0.05, 0.92)
	_hp_bar_bg.pixel_size = 0.02
	_hp_bar_bg.scale = Vector3(_hp_bar_w + 0.08, 0.16, 1.0)
	_hp_bar_bg.no_depth_test = true
	_hp_bar_bg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_bar_bg.visible = false
	add_child(_hp_bar_bg)
	_hp_bar = Sprite3D.new()
	_hp_bar.texture = tex
	_hp_bar.modulate = Color(0.25, 0.9, 0.3)
	_hp_bar.pixel_size = 0.02
	_hp_bar.scale = Vector3(_hp_bar_w, 0.1, 1.0)
	_hp_bar.no_depth_test = true
	_hp_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_bar.visible = false
	add_child(_hp_bar)

func _update_hp_bar() -> void:
	if _hp_bar == null:
		_build_hp_bar()
	var ratio: float = clampf(hp / max_hp, 0.0, 1.0)
	_hp_bar.visible = true
	_hp_bar_bg.visible = true
	_hp_bar_bg.position.y = HP_BAR_HEIGHT
	# 前景左对齐缩窄：中心随宽度左移，保持左端固定
	_hp_bar.scale.x = _hp_bar_w * ratio
	_hp_bar.position = Vector3(-_hp_bar_w * (1.0 - ratio) * 0.5, HP_BAR_HEIGHT, 0.0)
	_hp_bar.modulate = Color(0.25, 0.9, 0.3) if ratio > 0.5 else (Color(1.0, 0.75, 0.2) if ratio > 0.25 else Color(1.0, 0.25, 0.2))

## 伤害数字：挂到 main 下（尸体 queue_free 不影响飘字），上浮淡出后自动释放
func _spawn_damage_number(amount: float, headshot: bool) -> void:
	var label := Label3D.new()
	label.text = "爆头!" if headshot else str(int(round(amount)))
	label.font_size = 48
	label.pixel_size = 0.006
	label.outline_size = 10
	label.modulate = Color(1.0, 0.3, 0.25) if headshot else Color(1.0, 0.95, 0.7)
	label.outline_modulate = Color(0.05, 0.02, 0.02)
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = global_position + Vector3(randf_range(-0.2, 0.2), HP_BAR_HEIGHT + 0.25, randf_range(-0.2, 0.2))
	main_node.add_child(label)
	var tw := main_node.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y + 0.9, 0.7)
	tw.tween_property(label, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(label.queue_free)

## 1×1 白纹理（血条底图，靠 modulate 染色 + scale 成条）
func _white_texture() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	return ImageTexture.create_from_image(img)

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
