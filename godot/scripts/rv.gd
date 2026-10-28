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
	# 独占碰撞层 2 + 仅撞层1（地面/障碍）：丧尸在层3 不参与物理碰撞，碾压由触发区接管，消除顿帧
	collision_layer = 2
	collision_mask = 1
	# 碾压触发区：覆盖车头与车身，进区的丧尸直接撞飞
	var kill := Area3D.new()
	kill.collision_layer = 0
	kill.collision_mask = 4
	var kshape := CollisionShape3D.new()
	var kbox := BoxShape3D.new()
	kbox.size = Vector3(2.6, 2.0, 5.4)
	kshape.shape = kbox
	kshape.position = Vector3(0.0, 1.0, -0.6)
	kill.add_child(kshape)
	kill.body_entered.connect(_on_zombie_area)
	add_child(kill)
	# 收集车轮：横贯车宽、贴底、截面近圆的圆柱网格（车轴+双轮一体件）
	for mi in main_node.rv_model.find_children("*", "MeshInstance3D", true, false):
		var aabb: AABB = mi.get_aabb()
		if aabb.size.x > 1.8 and absf(aabb.size.y - aabb.size.z) < 0.15 and aabb.size.y < 1.2 and mi.position.y < -0.5:
			_wheels.append(mi)
			_add_hub_marker(mi)

## 轮毂盖+偏心螺栓：轮面胎纹均匀时纯旋转视觉不可读，加可见标记让滚动看得出来
func _add_hub_marker(axle: MeshInstance3D) -> void:
	var hub_mat := StandardMaterial3D.new()
	hub_mat.albedo_color = Color(0.58, 0.58, 0.62)
	hub_mat.metallic = 0.6
	hub_mat.roughness = 0.4
	var bolt_mat := StandardMaterial3D.new()
	bolt_mat.albedo_color = Color(0.16, 0.16, 0.18)
	for side in [-1.0, 1.0]:
		var hub := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.26
		hm.bottom_radius = 0.26
		hm.height = 0.04
		hm.radial_segments = 12
		hub.mesh = hm
		hub.rotation.z = PI * 0.5   # 圆柱默认 Y 轴，转到 X 轴贴轮端面
		hub.position = Vector3(side * 1.13, 0.0, 0.0)
		hub.material_override = hub_mat
		axle.add_child(hub)
		# 偏心螺栓：轮轴转动时它绕轴公转，滚动最直接的视觉锚点
		var bolt := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.11, 0.11)
		bolt.mesh = bm
		bolt.position = Vector3(side * 1.16, 0.14, 0.0)
		bolt.material_override = bolt_mat
		axle.add_child(bolt)

func _physics_process(delta: float) -> void:
	_spin_wheels(delta)
	# 坡度姿态：前后 5m 地面高差算俯仰（车头朝 -Z，前方更高即上坡抬车头）
	var slope := atan2(main_node.ground_height(position.x, position.z - 2.5) - main_node.ground_height(position.x, position.z + 2.5), 5.0)
	# 剧情对话期间：世界冻结，强制刹停并贴地（忽略一切驾驶输入）
	if main_node.story_active:
		speed_kmh = maxf(speed_kmh - BRAKE * delta, 0.0)
		# 水平化速度：y 分量由贴地逻辑接管，带坡度会被 move_and_slide 当碰撞损耗（爬坡难的根因）
		var fwd0 := -global_transform.basis.z
		fwd0.y = 0.0
		velocity = fwd0.normalized() * (speed_kmh * KMH_TO_UNITS)
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
			var fwd1 := -global_transform.basis.z
			fwd1.y = 0.0
			velocity = fwd1.normalized() * (speed_kmh * KMH_TO_UNITS)
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
		# 爬坡动力补偿：坡度越陡油门加成越大，陡坡不再爬不动
		var climb := 1.0 + maxf(slope, 0.0) * 2.2
		speed_kmh = minf(speed_kmh + ACCEL * grip * climb * delta, main_node.MAX_KMH)
	elif brake:
		var braking := 0.85 if main_node.weather == "rain" else 1.0
		speed_kmh = maxf(speed_kmh - BRAKE * braking * delta, 0.0)
	else:
		speed_kmh = maxf(speed_kmh - DRAG * delta, 0.0)

	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	velocity = fwd.normalized() * (speed_kmh * KMH_TO_UNITS)
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

## 碾压：触发区内的丧尸直接撞飞（车速 >8 才触发，停车时丧尸仍可围车）；动量按质量比衰减
func _on_zombie_area(body: Node) -> void:
	if speed_kmh <= 8.0 or parked:
		return
	if body is RigidBody3D and body.has_method("on_hit_by_rv") and not body.dead:
		body.on_hit_by_rv(speed_kmh, Vector3.UP)
		# 动量衰减：房车 ~4 吨 vs 丧尸 70kg，单个几乎无感，尸群累积才拖慢
		speed_kmh *= 4000.0 / 4070.0
		main_node.on_zombie_run_over()

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
		if other.is_in_group("obstacle_hard"):
			main_node.on_obstacle_hit(true, speed_kmh, other)
		elif other.is_in_group("obstacle_soft"):
			# 已撞飞的解冻残骸：推着走不当墙，避免房车被自己的战利品卡死
			if other is RigidBody3D and not other.freeze:
				other.apply_central_impulse(-global_transform.basis.z * speed_kmh * KMH_TO_UNITS * other.mass * 0.4)
			main_node.on_obstacle_hit(false, speed_kmh, other)
