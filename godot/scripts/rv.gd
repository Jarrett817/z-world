extends CharacterBody3D
## 房车驾驶：WASD/方向键 + HUD 触摸按钮（touch_* 字段）。
## 车头朝 -Z，速度以 km/h 表达，换算 0.4 单位/秒（1440 单位 = 1 km）。

const ACCEL := 55.0
const BRAKE := 120.0
const DRAG := 10.0
const KMH_TO_UNITS := 0.4

var speed_kmh := 0.0
var engine_dead := false
var parked := false
var combat_in := false   # 下车/天窗战斗中：忽略驾驶按键（惯性滑行）
var touch_gas := false
var touch_brake := false
var touch_steer := 0.0   # -1 右 / +1 左
var main_node: Node3D
var _wheels: Array[Node3D] = []   # 车轴轮一体网格（滚动动画）

func _ready() -> void:
	main_node = get_parent()
	# 独占碰撞层 2：被撞飞的丧尸清掉 mask 第 2 位后不再挡车，消除碾压顿帧
	collision_layer = 2
	# 收集车轮：横贯车宽、贴底、截面近圆的圆柱网格（车轴+双轮一体件）
	for mi in main_node.rv_model.find_children("*", "MeshInstance3D", true, false):
		var aabb: AABB = mi.get_aabb()
		if aabb.size.x > 1.8 and absf(aabb.size.y - aabb.size.z) < 0.15 and aabb.size.y < 1.2 and mi.position.y < -0.5:
			_wheels.append(mi)

func _physics_process(delta: float) -> void:
	_spin_wheels(delta)
	# 坡度姿态：前后 5m 地面高差算俯仰（车头朝 -Z，前方更高即上坡抬车头）
	var slope := atan2(main_node.ground_height(position.x, position.z - 2.5) - main_node.ground_height(position.x, position.z + 2.5), 5.0)
	# 剧情对话期间：世界冻结，强制刹停并贴地（忽略一切驾驶输入）
	if main_node.story_active:
		speed_kmh = maxf(speed_kmh - BRAKE * delta, 0.0)
		velocity = -global_transform.basis.z * (speed_kmh * KMH_TO_UNITS)
		move_and_slide()
		position.y = main_node.ground_height(position.x, position.z) + main_node.RV_MODEL_FOOT
		rotation.x = lerpf(rotation.x, slope, delta * 3.0)
		rotation.z = lerpf(rotation.z, 0.0, delta * 4.0)
		return
	if parked or combat_in or main_node.rv_walk_active:
		if parked:
			# 驻车 = 绝对锚定：不调 move_and_slide（重叠的残骸会把车持续顶开），只贴地
			speed_kmh = 0.0
			velocity = Vector3.ZERO
		else:
			if combat_in:
				# 天窗射击：无驾驶输入，惯性滑行
				speed_kmh = maxf(speed_kmh - DRAG * delta, 0.0)
			elif speed_kmh > 1.0 and absf(position.x - main_node.road_x(position.z)) < main_node.ROAD_HALF + 3.0:
				# 车内行走·队友代驾：定速巡航，公路上自动跟弯（同驾驶回正逻辑）
				var d: float = 0.6
				var bx: float = main_node.road_x(position.z + d) - main_node.road_x(position.z - d)
				rotation.y = lerp_angle(rotation.y, atan2(bx, 2.0 * d), delta * 1.2)
			velocity = -global_transform.basis.z * (speed_kmh * KMH_TO_UNITS)
			move_and_slide()
		position.y = main_node.ground_height(position.x, position.z) + main_node.RV_MODEL_FOOT
		rotation.x = lerpf(rotation.x, slope, delta * 3.0)
		rotation.z = lerpf(rotation.z, 0.0, delta * 4.0)
		return
	var gas := touch_gas or Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
	var brake: bool = touch_brake or main_node._park_brake or Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
	var steer_in := clampf(touch_steer + _key_steer(), -1.0, 1.0)

	if not engine_dead and gas:
		var grip := 0.78 if main_node.weather == "rain" else 1.0
		speed_kmh = minf(speed_kmh + ACCEL * grip * delta, main_node.MAX_KMH)
	elif brake:
		var braking := 0.85 if main_node.weather == "rain" else 1.0
		speed_kmh = maxf(speed_kmh - BRAKE * braking * delta, 0.0)
	else:
		speed_kmh = maxf(speed_kmh - DRAG * delta, 0.0)

	velocity = -global_transform.basis.z * (speed_kmh * KMH_TO_UNITS)
	if absf(speed_kmh) > 1.0:
		# 高速转向迟滞：速度越快打舵越缓，避免掉头打转
		var ratio: float = speed_kmh / main_node.MAX_KMH
		rotation.y += steer_in * delta * 1.5 * (1.0 - 0.55 * ratio)
		if absf(steer_in) < 0.05 and absf(position.x - main_node.road_x(position.z)) < main_node.ROAD_HALF + 3.0:
			# 松手自动回正：对齐道路切线（仅在公路上时生效，野地里不抢方向盘）
			var d: float = 0.6
			var bx: float = main_node.road_x(position.z + d) - main_node.road_x(position.z - d)
			# 行进方向是 -Z：目标朝向 = atan2(bx, +2d)，否则会掉头往后开
			var target := atan2(bx, 2.0 * d)
			rotation.y = lerp_angle(rotation.y, target, delta * 1.2 * (1.0 - 0.5 * ratio))
	move_and_slide()
	_report_collisions()

	# 贴地：直接跟随地形高度函数，避免起伏穿模
	position.y = main_node.ground_height(position.x, position.z) + main_node.RV_MODEL_FOOT

	# 姿态小动效：加速前倾 + 转向侧倾（叠加地形坡度）
	var pitch := -0.05 if (gas and not engine_dead) else 0.0
	rotation.x = lerpf(rotation.x, pitch + slope, delta * 3.0)
	rotation.z = lerpf(rotation.z, steer_in * 0.035 * (speed_kmh / main_node.MAX_KMH), delta * 4.0)

## 车轮滚动：ω=v/r（半径 0.378），绕本地 X 轴正转即前进滚动
func _spin_wheels(delta: float) -> void:
	if speed_kmh < 0.05:
		return
	var w := speed_kmh * KMH_TO_UNITS / 0.378 * delta
	for wheel in _wheels:
		wheel.rotate_x(w)

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
			# 动量衰减：房车 ~4 吨 vs 丧尸 70kg，单个几乎无感，尸群累积才拖慢
			speed_kmh *= 4000.0 / 4070.0
			main_node.on_zombie_run_over()
		elif other.is_in_group("obstacle_hard"):
			main_node.on_obstacle_hit(true, speed_kmh, other)
		elif other.is_in_group("obstacle_soft"):
			# 已撞飞的解冻残骸：推着走不当墙，避免房车被自己的战利品卡死
			if other is RigidBody3D and not other.freeze:
				other.apply_central_impulse(-global_transform.basis.z * speed_kmh * KMH_TO_UNITS * other.mass * 0.4)
			main_node.on_obstacle_hit(false, speed_kmh, other)
