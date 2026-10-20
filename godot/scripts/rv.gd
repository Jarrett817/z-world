extends CharacterBody3D
## 房车驾驶：WASD/方向键 + HUD 触摸按钮（touch_* 字段）。
## 车头朝 -Z，速度以 km/h 表达，换算 0.4 单位/秒（1440 单位 = 1 km）。

const ACCEL := 55.0
const BRAKE := 120.0
const DRAG := 10.0
const KMH_TO_UNITS := 0.4

var speed_kmh := 0.0
var engine_dead := false
var touch_gas := false
var touch_brake := false
var touch_steer := 0.0   # -1 右 / +1 左
var main_node: Node3D

func _ready() -> void:
	main_node = get_parent()

func _physics_process(delta: float) -> void:
	var gas := touch_gas or Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
	var brake := touch_brake or Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
	var steer_in := clampf(touch_steer + _key_steer(), -1.0, 1.0)

	if not engine_dead and gas:
		speed_kmh = minf(speed_kmh + ACCEL * delta, main_node.MAX_KMH)
	elif brake:
		speed_kmh = maxf(speed_kmh - BRAKE * delta, 0.0)
	else:
		speed_kmh = maxf(speed_kmh - DRAG * delta, 0.0)

	velocity = -global_transform.basis.z * (speed_kmh * KMH_TO_UNITS)
	if absf(speed_kmh) > 1.0:
		rotation.y += steer_in * delta * (0.8 + speed_kmh / main_node.MAX_KMH * 0.9)
	move_and_slide()
	_report_collisions()

	# 贴地：直接跟随地形高度函数，避免起伏穿模
	position.y = main_node.ground_y(position.z) + main_node.RV_MODEL_FOOT

	# 姿态小动效：加速前倾 + 转向侧倾
	var pitch := -0.05 if (gas and not engine_dead) else 0.0
	rotation.x = lerpf(rotation.x, pitch, delta * 3.0)
	rotation.z = lerpf(rotation.z, steer_in * 0.035 * (speed_kmh / main_node.MAX_KMH), delta * 4.0)

func _key_steer() -> float:
	var s := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		s += 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		s -= 1.0
	return s

func _report_collisions() -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other: Object = col.get_collider()
		if other == null:
			continue
		if other is RigidBody3D and other.has_method("on_hit_by_rv"):
			other.on_hit_by_rv(speed_kmh, col.get_normal())
			main_node.on_zombie_run_over()
		elif other is StaticBody3D and other.is_in_group("obstacle_hard"):
			main_node.on_obstacle_hit(true, speed_kmh)
		elif other is StaticBody3D and other.is_in_group("obstacle_soft"):
			main_node.on_obstacle_hit(false, speed_kmh)
