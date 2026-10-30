extends CharacterBody3D
## 房车驾驶：WASD/方向键 + HUD 左侧摇杆（touch_* 字段）。
## 车头朝 -Z，速度以 km/h 表达，换算 0.4 单位/秒（1440 单位 = 1 km）。

const ACCEL := 55.0
const BRAKE := 120.0
const DRAG := 10.0
const REVERSE_MAX_KMH := 45.0
const WATER_MAX_KMH := 26.0   # 水上最高速（水陆两栖，水面慢驶）
const WATER_ACCEL := 26.0     # 水上推进加速度
const WATER_DRAG := 34.0      # 水上水阻
const KMH_TO_UNITS := 0.4
const CREW_CRUISE_KMH := 60.0   # 队友代驾的默认巡航速度；接管时保留更高的当前车速

var speed_kmh := 0.0
var reversing := false
var engine_dead := false
var parked := false
var combat_in := false   # 下车/天窗战斗中：忽略驾驶按键（惯性滑行）
var touch_throttle := 0.0   # -1 倒退 / +1 前进
var touch_steer := 0.0      # -1 右 / +1 左
var in_water := false       # 当前是否浮在水面
var _water_f := 0.0         # 浮水混合 0=陆地 1=水面（岸边平滑）
var _support_y := 0.0       # 本帧车身贴靠高度（地面或水面）
var main_node: Node3D
var _wheels: Array[Node3D] = []   # 车轴轮一体网格（滚动动画）
var _crew_cruise_kmh := 0.0

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
	if not main_node.rv_walk_active:
		_crew_cruise_kmh = 0.0
	var grip := 1.0
	var braking := 1.0
	match main_node.weather:
		"rain":
			grip = 0.78
			braking = 0.85
		"heavy_rain":
			grip = 0.62
			braking = 0.68
		"snow":
			grip = 0.55
			braking = 0.6
	# 坡度姿态：前后 5m 地面高差算俯仰（车头朝 -Z，前方更高即上坡抬车头）
	var slope := atan2(main_node.ground_height(position.x, position.z - 2.5) - main_node.ground_height(position.x, position.z + 2.5), 5.0)
	_update_water(delta)
	# 剧情对话期间：世界冻结，强制刹停并贴地（忽略一切驾驶输入）
	if main_node.story_active:
		speed_kmh = maxf(speed_kmh - BRAKE * delta, 0.0)
		# 水平化速度：y 分量由贴地逻辑接管，带坡度会被 move_and_slide 当碰撞损耗（爬坡难的根因）
		var fwd0 := -global_transform.basis.z
		fwd0.y = 0.0
		var drive_dir := -1.0 if reversing else 1.0
		velocity = fwd0.normalized() * (speed_kmh * KMH_TO_UNITS * drive_dir)
		move_and_slide()
		position.y = _support_y
		_align_to_terrain(_water_f)
		main_node.rv_model.rotation.x = lerpf(main_node.rv_model.rotation.x, 0.0, delta * 3.0)
		main_node.rv_model.rotation.z = lerpf(main_node.rv_model.rotation.z, 0.0, delta * 4.0)
		return
	if parked or combat_in or main_node.rv_walk_active:
		if parked:
			# 驻车 = 绝对锚定：不调 move_and_slide（重叠的残骸会把车持续顶开），只贴地
			speed_kmh = 0.0
			reversing = false
			velocity = Vector3.ZERO
		else:
			if combat_in:
				# 天窗射击：无驾驶输入，惯性滑行（水上水阻更大）
				speed_kmh = maxf(speed_kmh - lerpf(DRAG, WATER_DRAG, _water_f) * delta, 0.0)
			else:
				# 车内行走·队友代驾：接管当前车速，静止时自动起步；剧情结束继续巡航
				reversing = false
				if _crew_cruise_kmh <= 0.0:
					_crew_cruise_kmh = maxf(speed_kmh, CREW_CRUISE_KMH)
				if main_node._park_brake:
					speed_kmh = maxf(speed_kmh - BRAKE * braking * delta, 0.0)
				elif engine_dead:
					speed_kmh = maxf(speed_kmh - lerpf(DRAG, WATER_DRAG, _water_f) * delta, 0.0)
				elif speed_kmh < _crew_cruise_kmh:
					var climb := 1.0 + maxf(slope, 0.0) * 2.2
					var accel := lerpf(ACCEL * grip * climb, WATER_ACCEL, _water_f)
					speed_kmh = minf(speed_kmh + accel * delta, _crew_cruise_kmh)
				else:
					speed_kmh = maxf(speed_kmh - lerpf(DRAG, WATER_DRAG, _water_f) * delta, _crew_cruise_kmh)
				if speed_kmh > 1.0 and absf(position.x - main_node.road_x(position.z)) < main_node.ROAD_HALF + 3.0:
					var d: float = 0.6
					var bx: float = main_node.road_x(position.z + d) - main_node.road_x(position.z - d)
					rotation.y = lerp_angle(rotation.y, atan2(bx, 2.0 * d), delta * 1.2)
			var fwd1 := -global_transform.basis.z
			fwd1.y = 0.0
			var drive_dir := -1.0 if reversing else 1.0
			velocity = fwd1.normalized() * (speed_kmh * KMH_TO_UNITS * drive_dir)
			move_and_slide()
			if not combat_in:
				_report_collisions()
				if is_on_wall():
					speed_kmh = minf(speed_kmh, maxf(0.0, get_real_velocity().dot(fwd1 * drive_dir) / KMH_TO_UNITS))
		position.y = _support_y
		_align_to_terrain(_water_f)
		main_node.rv_model.rotation.x = lerpf(main_node.rv_model.rotation.x, 0.0, delta * 3.0)
		main_node.rv_model.rotation.z = lerpf(main_node.rv_model.rotation.z, 0.0, delta * 4.0)
		return
	var throttle := clampf(touch_throttle + _key_throttle(), -1.0, 1.0)
	var steer_in := clampf(touch_steer + _key_steer(), -1.0, 1.0)
	if main_node._park_brake:
		speed_kmh = maxf(speed_kmh - BRAKE * braking * delta, 0.0)
		if speed_kmh <= 0.05:
			reversing = false
	elif not engine_dead and absf(throttle) > 0.05:
		var want_reverse := throttle < 0.0
		if want_reverse != reversing:
			speed_kmh = maxf(speed_kmh - BRAKE * braking * absf(throttle) * delta, 0.0)
			if speed_kmh <= 0.05:
				reversing = want_reverse
		else:
			# 沿当前运动方向爬坡补偿；倒退时坡向取反；水上不做爬坡补偿
			var slope_along := -slope if reversing else slope
			var climb := 1.0 + maxf(slope_along, 0.0) * 2.2
			var max_speed: float = REVERSE_MAX_KMH if reversing else lerpf(main_node.MAX_KMH, WATER_MAX_KMH, _water_f)
			var accel := ACCEL * grip * climb
			if _water_f > 0.0:
				accel = WATER_ACCEL
			speed_kmh = minf(speed_kmh + accel * absf(throttle) * delta, max_speed)
	else:
		speed_kmh = maxf(speed_kmh - lerpf(DRAG, WATER_DRAG, _water_f) * delta, 0.0)
		if speed_kmh <= 0.05:
			reversing = false

	var drive_dir := -1.0 if reversing else 1.0
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	velocity = fwd.normalized() * (speed_kmh * KMH_TO_UNITS * drive_dir)
	if speed_kmh > 1.0:
		# 高速转向迟滞：速度越快打舵越缓，倒退时按实际行进方向反向打舵；水上舵效减半
		var ratio: float = speed_kmh / main_node.MAX_KMH
		rotation.y += steer_in * drive_dir * delta * lerpf(1.5, 0.8, _water_f) * (1.0 - 0.55 * ratio)
		if not reversing and _water_f < 0.3 and absf(steer_in) < 0.05 and absf(position.x - main_node.road_x(position.z)) < main_node.ROAD_HALF + 3.0:
			# 松手自动回正：对齐道路切线（仅在公路前进时生效，野地里/水上不抢方向盘）
			var d: float = 0.6
			var bx: float = main_node.road_x(position.z + d) - main_node.road_x(position.z - d)
			# 行进方向是 -Z：目标朝向 = atan2(bx, +2d)，否则会掉头往后开
			var target := atan2(bx, 2.0 * d)
			rotation.y = lerp_angle(rotation.y, target, delta * 1.2 * (1.0 - 0.5 * ratio))
	move_and_slide()
	_report_collisions()
	if is_on_wall():
		# 顶住障碍时采用实际位移速度，避免表显/耗油/车轮仍按油门目标速度运行
		speed_kmh = minf(speed_kmh, maxf(0.0, get_real_velocity().dot(fwd * drive_dir) / KMH_TO_UNITS))

	# 贴靠：陆地跟随地形高度，入水后平滑抬到水面（岸边不跳变）
	position.y = _support_y

	# 物理车身只贴合地形坡度；水面上保持水平。加速俯仰/转向侧倾仅作用于外壳
	var gas_forward := throttle > 0.05 and not reversing
	var pitch := -0.05 if (gas_forward and not engine_dead and _water_f < 0.3) else 0.0
	_align_to_terrain(_water_f)
	main_node.rv_model.rotation.x = lerpf(main_node.rv_model.rotation.x, pitch, delta * 3.0)
	main_node.rv_model.rotation.z = lerpf(main_node.rv_model.rotation.z, steer_in * drive_dir * 0.035 * (speed_kmh / main_node.MAX_KMH), delta * 4.0)

## 浮水状态：水面高于地形（车会落进水里）时浮起，_water_f 在岸边平滑过渡
func _update_water(delta: float) -> void:
	var x: float = position.x
	var z: float = position.z
	var ground_h: float = main_node.ground_height(x, z)
	var water_h: float = main_node.water_surface_height(x, z)
	var target := 0.0
	if not is_inf(water_h) and water_h > ground_h + 0.05:
		target = 1.0
	in_water = target > 0.5
	# 岸边/入水平滑：高度跟随与浮水混合同步，避免 2m 岸沿突变导致的跳车
	_water_f = lerpf(_water_f, target, delta * 3.0)
	var support_h := ground_h
	if not is_inf(water_h):
		support_h = lerpf(ground_h, water_h, _water_f)
	elif _water_f < 0.02:
		_water_f = 0.0
	_support_y = support_h + main_node.RV_MODEL_FOOT

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
	if reversing:
		w = -w
	for wheel in _wheels:
		wheel.rotate_x(w)

func _key_throttle() -> float:
	var t := 0.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		t += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		t -= 1.0
	return t

func _key_steer() -> float:
	var s := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		s += 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		s -= 1.0
	return s

## 物理车身贴合局部地形平面：主路外的横坡也必须由俯仰和侧倾共同承担；water_f>0 时向水平姿态混合（船体水面平稳）
func _align_to_terrain(water_f := 0.0) -> void:
	var yaw_basis := Basis(Vector3.UP, rotation.y)
	var forward := -yaw_basis.z
	var right := yaw_basis.x
	var front_h: float = main_node.ground_height(position.x + forward.x * 2.5, position.z + forward.z * 2.5)
	var back_h: float = main_node.ground_height(position.x - forward.x * 2.5, position.z - forward.z * 2.5)
	var right_h: float = main_node.ground_height(position.x + right.x * 1.6, position.z + right.z * 1.6)
	var left_h: float = main_node.ground_height(position.x - right.x * 1.6, position.z - right.z * 1.6)
	var gradient := forward * ((front_h - back_h) / 5.0) + right * ((right_h - left_h) / 3.2)
	var up := (Vector3.UP - gradient).normalized()
	var back := -(forward - up * forward.dot(up)).normalized()
	var side := up.cross(back).normalized()
	basis = Basis(side, up, back).orthonormalized()
	if water_f > 0.0:
		basis = basis.slerp(Basis(Vector3.UP, rotation.y), clampf(water_f, 0.0, 1.0)).orthonormalized()

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
				var drive_dir := -1.0 if reversing else 1.0
				other.apply_central_impulse(-global_transform.basis.z * drive_dir * speed_kmh * KMH_TO_UNITS * other.mass * 0.4)
			main_node.on_obstacle_hit(false, speed_kmh, other)
