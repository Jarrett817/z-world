extends CharacterBody3D
## 房车驾驶：WASD/方向键 + HUD 左侧摇杆（touch_* 字段）。
## 车头朝 -Z，速度以 km/h 表达，换算 0.4 单位/秒（1440 单位 = 1 km）。

const ACCEL := 55.0
const BRAKE := 120.0
const DRAG := 10.0
const REVERSE_MAX_KMH := 30.0
const WATER_MAX_KMH := 26.0   # 水上最高速（水陆两栖，水面慢驶）
const WATER_ACCEL := 26.0     # 水上推进加速度
const WATER_DRAG := 34.0      # 水上水阻
const KMH_TO_UNITS := 0.4
const CREW_CRUISE_KMH := 60.0   # 队友代驾的默认巡航速度；接管时保留更高的当前车速
const GRAVITY := 18.0

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
var _ground_normal := Vector3.UP
var main_node: Node3D
var _wheels: Array[Node3D] = []   # 车轴轮一体网格（滚动动画）
var _crew_cruise_kmh := 0.0
var _crew_avoid := 0.0   # 绕障方向：+1 右 / -1 左；越过障碍后自动回正
var _crew_avoid_pass_z := 0.0
var _crew_reverse_t := 0.0
var _crew_stuck_t := 0.0

func _ready() -> void:
	main_node = get_parent()
	# 独占碰撞层 2 + 仅撞层1（地面/障碍）：丧尸在层3 不参与物理碰撞，碾压由触发区接管，消除顿帧
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.8
	floor_max_angle = deg_to_rad(55.0)
	floor_constant_speed = true
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
	if not main_node.crew_driving:
		_crew_cruise_kmh = 0.0
		_crew_avoid = 0.0
		_crew_avoid_pass_z = 0.0
		_crew_reverse_t = 0.0
		_crew_stuck_t = 0.0
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
	# 原生地面法线提供爬坡补偿，不再从高度函数手算车身支撑
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var slope := -asin(clampf(forward.dot(get_floor_normal()), -1.0, 1.0)) if is_on_floor() else 0.0
	_update_water(delta)
	# 剧情对话期间：世界冻结，强制刹停并贴地（忽略一切驾驶输入）
	if main_node.story_active:
		speed_kmh = maxf(speed_kmh - BRAKE * delta, 0.0)
		# 水平化速度：y 分量由贴地逻辑接管，带坡度会被 move_and_slide 当碰撞损耗（爬坡难的根因）
		var fwd0 := -global_transform.basis.z
		fwd0.y = 0.0
		var drive_dir := -1.0 if reversing else 1.0
		var drive_velocity := fwd0.normalized() * (speed_kmh * KMH_TO_UNITS * drive_dir)
		velocity.x = drive_velocity.x
		velocity.z = drive_velocity.z
		_move_with_support(delta)
		_update_water(0.0)   # 移动后用新位置重算浮水状态，姿态与支撑保持同帧
		_align_to_terrain(_water_f)
		main_node.rv_model.rotation.x = lerpf(main_node.rv_model.rotation.x, 0.0, delta * 3.0)
		main_node.rv_model.rotation.z = lerpf(main_node.rv_model.rotation.z, 0.0, delta * 4.0)
		return
	if parked or combat_in or main_node.crew_driving:
		if parked:
			# 驻车只锁水平驾驶，垂直支撑仍由物理碰撞处理
			speed_kmh = 0.0
			reversing = false
			velocity.x = 0.0
			velocity.z = 0.0
			_move_with_support(delta)
		else:
			if combat_in and not main_node.crew_driving:
				# 无代驾的天窗射击：忽略驾驶输入，惯性滑行
				speed_kmh = maxf(speed_kmh - lerpf(DRAG, WATER_DRAG, _water_f) * delta, 0.0)
			else:
				# 队友独立代驾：前视车体扫掠发现障碍后提前减速，选择有完整净空的一侧绕行
				if _crew_cruise_kmh <= 0.0:
					_crew_cruise_kmh = maxf(speed_kmh, CREW_CRUISE_KMH)
				var target_pos := Vector3.ZERO
				var best_dist := 85.0
				for group in ["pickup", "survivor"]:
					for node in get_tree().get_nodes_in_group(group):
						var local: Vector3 = to_local((node as Node3D).global_position)
						if local.z > -3.0 or local.z < -85.0 or absf(local.x) > 24.0:
							continue
						var dist := Vector2(local.x, local.z).length()
						if dist < best_dist:
							best_dist = dist
							target_pos = (node as Node3D).global_position
				var has_target := best_dist < 85.0
				var target_yaw := rotation.y
				if has_target:
					var to_target := target_pos - global_position
					target_yaw = atan2(-to_target.x, -to_target.z)
				else:
					# 没有拾取目标时始终回到前方公路，绕障后也不会沿野地一直直行
					var road_z := position.z - 20.0
					var to_road := Vector3(main_node.road_x(road_z), position.y, road_z) - global_position
					target_yaw = atan2(-to_road.x, -to_road.z)
				var desired_speed := _crew_cruise_kmh
				if has_target and best_dist < 35.0:
					desired_speed = minf(desired_speed, 35.0)
				var center_hit := _crew_obstacle_ahead(0.0)
				if center_hit > 0.0:
					var right_hit := _crew_obstacle_ahead(4.6)
					var left_hit := _crew_obstacle_ahead(-4.6)
					if right_hit <= 0.0 or left_hit <= 0.0:
						if _crew_avoid == 0.0 or (_crew_avoid > 0.0 and right_hit > 0.0) or (_crew_avoid < 0.0 and left_hit > 0.0):
							if _crew_avoid == 0.0:
								_crew_avoid_pass_z = position.z - center_hit - 12.0
							_crew_avoid = 1.0 if right_hit <= 0.0 else -1.0
					else:
						_crew_avoid = 0.0
					desired_speed = minf(desired_speed, clampf((center_hit - 7.0) * 2.0, 0.0, 30.0))
				elif absf(_crew_avoid) > 0.0 and position.z < _crew_avoid_pass_z:
					# 以整车越过障碍为回正条件，而不是车头刚偏开就结束绕行
					_crew_avoid = 0.0
				if absf(_crew_avoid) > 0.0:
					# 整车越过障碍前都保持低速，正前方暂时变空也不能提前加速
					desired_speed = clampf(desired_speed, 8.0, 20.0)
				reversing = _crew_reverse_t > 0.0
				if reversing:
					_crew_reverse_t = maxf(_crew_reverse_t - delta, 0.0)
					desired_speed = 14.0
					target_yaw += _crew_avoid * 0.35
				elif absf(_crew_avoid) > 0.0:
					# 近距路障用更近的换道目标获得足够转向角，远距离保持平顺；本地 +X 为右侧
					var lane_ahead := clampf(center_hit * 0.65, 7.0, 18.0) if center_hit > 0.0 else 7.0
					var lane_z := position.z - lane_ahead
					var to_lane := Vector3(main_node.road_x(lane_z) + _crew_avoid * 4.8, position.y, lane_z) - global_position
					target_yaw = atan2(-to_lane.x, -to_lane.z)
				if speed_kmh > 1.0 or reversing:
					rotation.y = lerp_angle(rotation.y, target_yaw, minf(delta * (3.0 if reversing else 2.4), 1.0))
				if absf(angle_difference(rotation.y, target_yaw)) > 0.45:
					desired_speed = minf(desired_speed, 25.0)
				if main_node._park_brake:
					speed_kmh = maxf(speed_kmh - BRAKE * braking * delta, 0.0)
				elif engine_dead:
					speed_kmh = maxf(speed_kmh - lerpf(DRAG, WATER_DRAG, _water_f) * delta, 0.0)
				elif reversing or speed_kmh > desired_speed:
					speed_kmh = maxf(speed_kmh - BRAKE * braking * delta, desired_speed)
				elif speed_kmh < desired_speed:
					var climb := 1.0 + maxf(slope, 0.0) * 0.5
					var accel := lerpf(ACCEL * grip * climb, WATER_ACCEL, _water_f)
					speed_kmh = minf(speed_kmh + accel * delta, desired_speed)
				# 低速已经贴住障碍时先倒出空间，再沿上次选定的空侧绕行，杜绝反复顶墙
				if center_hit > 0.0 and center_hit <= 7.0 and speed_kmh < 2.0 and not reversing and not engine_dead:
					_crew_stuck_t += delta
					if _crew_stuck_t > 0.35:
						_crew_reverse_t = 1.1
						_crew_stuck_t = 0.0
				else:
					_crew_stuck_t = 0.0
			var fwd1 := -global_transform.basis.z
			fwd1.y = 0.0
			var drive_dir := -1.0 if reversing else 1.0
			var drive_velocity := fwd1.normalized() * (speed_kmh * KMH_TO_UNITS * drive_dir)
			velocity.x = drive_velocity.x
			velocity.z = drive_velocity.z
			_move_with_support(delta)
			if not combat_in:
				_report_collisions()
				if is_on_wall():
					speed_kmh = minf(speed_kmh, maxf(0.0, get_real_velocity().dot(fwd1 * drive_dir) / KMH_TO_UNITS))
		_update_water(0.0)
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
			var climb := 1.0 + maxf(slope_along, 0.0) * 0.5
			var max_speed: float = REVERSE_MAX_KMH if reversing else lerpf(main_node.MAX_KMH, WATER_MAX_KMH, _water_f)
			var accel := ACCEL * (0.58 if reversing else 1.0) * grip * climb
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
	var drive_velocity := fwd.normalized() * (speed_kmh * KMH_TO_UNITS * drive_dir)
	velocity.x = drive_velocity.x
	velocity.z = drive_velocity.z
	if speed_kmh > 1.0:
		# 高速转向迟滞：速度越快打舵越缓，倒退时按实际行进方向反向打舵；水上舵效减半
		var ratio: float = speed_kmh / main_node.MAX_KMH
		var steer_rate := lerpf(1.5, 0.8, _water_f) * (1.0 - 0.55 * ratio)
		if reversing:
			steer_rate *= 0.55
		rotation.y += steer_in * drive_dir * delta * steer_rate
		if not reversing and _water_f < 0.3 and absf(steer_in) < 0.05 and absf(position.x - main_node.road_x(position.z)) < main_node.ROAD_HALF + 3.0:
			# 松手自动回正：对齐道路切线（仅在公路前进时生效，野地里/水上不抢方向盘）
			var d: float = 0.6
			var bx: float = main_node.road_x(position.z + d) - main_node.road_x(position.z - d)
			# 行进方向是 -Z：目标朝向 = atan2(bx, +2d)，否则会掉头往后开
			var target := atan2(bx, 2.0 * d)
			rotation.y = lerp_angle(rotation.y, target, delta * 1.2 * (1.0 - 0.5 * ratio))
	_move_with_support(delta)
	_report_collisions()
	if is_on_wall():
		# 顶住障碍时采用实际位移速度，避免表显/耗油/车轮仍按油门目标速度运行
		speed_kmh = minf(speed_kmh, maxf(0.0, get_real_velocity().dot(fwd * drive_dir) / KMH_TO_UNITS))

	# 移动后更新浮水混合，姿态与物理支撑保持同帧
	_update_water(0.0)

	# 物理车身只贴合地形坡度；水面上保持水平。加速俯仰/转向侧倾仅作用于外壳
	var gas_forward := throttle > 0.05 and not reversing
	var pitch := -0.05 if (gas_forward and not engine_dead and _water_f < 0.3) else 0.0
	_align_to_terrain(_water_f)
	main_node.rv_model.rotation.x = lerpf(main_node.rv_model.rotation.x, pitch, delta * 3.0)
	main_node.rv_model.rotation.z = lerpf(main_node.rv_model.rotation.z, steer_in * drive_dir * 0.035 * (speed_kmh / main_node.MAX_KMH), delta * 4.0)

## 水平驾驶速度由各状态机给出；陆地交给原生地面碰撞，水面用限速浮力速度逼近支撑高度
func _move_with_support(delta: float) -> void:
	if _water_f > 0.01 and not is_inf(main_node.water_surface_height(position.x, position.z)):
		velocity.y = clampf((_support_y - position.y) * 8.0, -6.0, 6.0)
	elif is_on_floor():
		# 微小向下速度维持坡面接触，避免零速驻车时地面状态逐帧丢失
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

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
	_support_y = support_h + main_node.RV_MODEL_FOOT * main_node.RV_SCALE

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

## 物理键位（防键盘布局差异）+ 逻辑键位（远程串流工具注入的键事件通常只带逻辑键码）双通道检测
static func _key_down(k: int) -> bool:
	return Input.is_physical_key_pressed(k) or Input.is_key_pressed(k)

func _key_throttle() -> float:
	var t := 0.0
	if _key_down(KEY_W) or _key_down(KEY_UP):
		t += 1.0
	if _key_down(KEY_S) or _key_down(KEY_DOWN):
		t -= 1.0
	return t

func _key_steer() -> float:
	var s := 0.0
	if _key_down(KEY_A) or _key_down(KEY_LEFT):
		s += 1.0
	if _key_down(KEY_D) or _key_down(KEY_RIGHT):
		s -= 1.0
	return s

## 物理车身贴合原生地面法线；水面向水平姿态混合，外壳加速俯仰/转向侧倾仍独立表现
func _align_to_terrain(water_f := 0.0) -> void:
	var yaw_basis := Basis(Vector3.UP, rotation.y)
	var forward := -yaw_basis.z
	if is_on_floor():
		_ground_normal = get_floor_normal()
	# 短暂失去地板接触时延续坡面姿态，避免大型碰撞盒反复转平又贴坡而弹跳
	var up := _ground_normal.slerp(Vector3.UP, clampf(water_f, 0.0, 1.0)).normalized()
	var back := -(forward - up * forward.dot(up)).normalized()
	var side := up.cross(back).normalized()
	basis = Basis(side, up, back).orthonormalized()

## 代驾前视：用整车碰撞盒扫描旁侧通道；返回最近扫描点距离，0 表示可走
func _crew_obstacle_ahead(side_offset: float) -> float:
	var space := get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.9, 3.9, 6.0)
	for distance in [7.0, 13.0, 19.0, 25.0, 31.0, 37.0, 43.0]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = global_transform * Transform3D(Basis.IDENTITY, Vector3(side_offset, 0.75, -distance))
		query.collision_mask = 1
		query.exclude = [get_rid()]
		for hit in space.intersect_shape(query, 4):
			var collider: Object = hit.get("collider")
			if collider != null and (collider.is_in_group("obstacle_hard") or collider.is_in_group("obstacle_soft")):
				return distance
	return 0.0

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
