extends RigidBody3D
## 丧尸：追车 AI（朝房车走）、贴身啃咬扣耐久、被撞飞物理接管、高速碾压播放 Death。

const WALK := &"Walk"
const ATTACK := &"Attack"
const DEATH := &"Death"
const BITE_RANGE := 4.4
const BITE_INTERVAL := 0.8

var main_node: Node3D
var rv: Node3D
var speed := 2.0
var flung_t := 0.0
var bite_t := 0.0
var dead := false
var death_t := 0.0
var should_free := false
var anim: AnimationPlayer

func setup(main: Node3D) -> void:
	main_node = main
	rv = main.rv
	speed = randf_range(4.2, 6.6) * (1.0 + clampf(main.dist_km * 0.05, 0.0, 0.5))
	mass = 70.0
	linear_damp = 1.2
	_remove_rig_controls(self)
	_vary_materials(self)
	anim = _find_anim_player(self)
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

## 删除 GLB 误导出的 Blender 控制器圆环（近立方体小 mesh），否则头顶悬浮两个粉色环
func _remove_rig_controls(node: Node) -> void:
	for c in node.get_children():
		if c is MeshInstance3D:
			var s: Vector3 = (c as MeshInstance3D).get_aabb().size
			if s.x > 0.5 and s.x < 2.0 and s.y > 0.5 and s.y < 2.0 and s.z > 0.5 and s.z < 2.0:
				c.queue_free()
				continue
		_remove_rig_controls(c)

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

func _ai(delta: float) -> void:
	if main_node.game_over:
		linear_velocity = Vector3(0, linear_velocity.y, 0)
		return
	var to_rv := rv.global_position - global_position
	var d_xz := Vector2(to_rv.x, to_rv.z).length()
	if d_xz > BITE_RANGE:
		var dir := Vector3(to_rv.x, 0.0, to_rv.z).normalized()
		linear_velocity = Vector3(dir.x * speed, linear_velocity.y, dir.z * speed)
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 6.0)
		_play(WALK)
		if anim != null:
			anim.speed_scale = clampf(speed * 0.45, 1.3, 2.6)
	else:
		# 贴身啃咬
		linear_velocity = Vector3(0, linear_velocity.y, 0)
		if anim != null:
			anim.speed_scale = 1.0
		bite_t += delta
		if bite_t >= BITE_INTERVAL:
			bite_t = 0.0
			main_node.zombie_bite()
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
		_play_once(DEATH)

func _play(anim_name: StringName) -> void:
	if anim != null and anim_name in anim.get_animation_list() and anim.current_animation != String(anim_name):
		anim.play(anim_name)

func _play_once(anim_name: StringName) -> void:
	if anim != null and anim_name in anim.get_animation_list():
		anim.play(anim_name)

func _stop_anim() -> void:
	if anim != null:
		anim.stop()
