extends RigidBody3D
## 丧尸：追车 AI（朝房车走）、贴身啃咬扣耐久、被撞飞物理接管、高速碾压播放 Death。

const WALK := &"Walk"
const ATTACK := &"Attack"
const DEATH := &"Death"
const BITE_RANGE := 5.9
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
	speed = randf_range(1.8, 3.2)
	mass = 70.0
	linear_damp = 1.2
	anim = _find_anim_player(self)
	if anim == null:
		return
	var names := anim.get_animation_list()
	if WALK in names:
		anim.get_animation(WALK).loop_mode = Animation.LOOP_LINEAR
		anim.play(WALK)
	if ATTACK in names:
		anim.get_animation(ATTACK).loop_mode = Animation.LOOP_NONE
	if DEATH in names:
		anim.get_animation(DEATH).loop_mode = Animation.LOOP_NONE

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
	else:
		# 贴身啃咬
		linear_velocity = Vector3(0, linear_velocity.y, 0)
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
