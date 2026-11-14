extends CharacterBody3D
## 沈蔓下车战斗：第三人称肩后视角，鼠标瞄准，左键射击。
## 车顶天窗模式：身体固定在 RV 顶部，只能转身开火（行车中也能用）。
## W/A/S/D 地面移动，Shift 奔跑，Space 跳跃，C 下蹲，R 换弹，1-4 换枪，G 回到驾驶座结束模式。
## 武器数据驱动（res://data/guns.json）：模型/缩放/朝向/射速/弹匣/后坐全在 JSON。

const WALK_SPEED := 4.2
const RUN_SPEED := 6.8
const MOUSE_SENS := 0.0026
const RAY_DIST := 90.0
const GRAVITY := 18.0
const JUMP_VEL := 7.2
const CROUCH_MUL := 0.45
const GUN_POS := Vector3(-0.12, 1.30, 0.33)   # 枪挂点基准（下蹲时随手下放）
const GUN_POS_PRONE := Vector3(-0.3043, 0.1447, 0.4909)   # 免费卧姿第 0 帧右手 grip 关节实测位置
const FPS_EYE := 1.62        # 站立眼高
const FPS_EYE_CROUCH := 1.05 # 下蹲眼高
const FPS_EYE_PRONE := 0.56  # 与站立视角一致：相机高于 M4 枪线约 0.16m
const FPS_ARMS_SCENE := preload("res://assets/roles_glb/fps_arms.glb")

enum Mode { ON_FOOT, SUNROOF, RV_WALK }

var main_node: Node   # duck-typed：调用 main/hud 上动态解析的方法
var mode: int = Mode.ON_FOOT
var aim_yaw := 0.0
var aim_pitch := -0.32   # 高位俯视默认下压枪口，准星落在地面战场
var fire_cd := 0.0
var reload_t := 0.0
var hp := 100.0
var model_root: Node3D
var _body_meshes: Array[MeshInstance3D] = []
var muzzle: Node3D
var gun: Node3D          # 当前枪的挂点（grip 对齐点），俯仰/后坐作用在它身上
var _fps_arms: Node3D    # 从 hero 抽取的手部精模，跟随枪挂点运动后坐/换弹
var _fps_sleeves: Array[MeshInstance3D] = []
var _fps_support: Node3D
var _fps_support_pos := Vector3.ZERO
var _fps_left_hand := -1
var _fps_finger_pose: Dictionary = {}
var cam: Camera3D
var _camera_arm: SpringArm3D
var _anim: AnimationPlayer
var _cur_anim := ""

## 武器系统：JSON 数据 + 每枪独立余弹
var _guns: Dictionary = {}       # id -> 配置
var _gun_order: Array = []
var _gun_idx := 0
var _ammo_map: Dictionary = {}   # id -> 余弹
var _firing := false             # 左键按住（全自动连发用）
var _grenade_cfg: Dictionary = {}  # guns.json "grenade" 节
var _grenades := 0               # 剩余手雷数

var _r_down := false
var _recoil := 0.0
var fps := false             # 第一人称视角（V / HUD 视角按钮）
var _skel: Skeleton3D        # hero 骨架（FPS 时缩 Head 骨隐头）
var _head_bone := -1
var touch_move := Vector2.ZERO   # HUD 虚拟摇杆输入（-1..1），与键盘并存
var _airborne := false           # 跳跃滞空中（落地才恢复贴地）
var _crouching := false
var _space_down := false
var _c_down := false

## 持枪晃动（sway）：呼吸 + 步伐 bob + 视角惯性滞后，参数见 guns.json "sway" 节
var _sway_cfg: Dictionary = {}
var _sway_t := 0.0
var _look_sway := Vector2.ZERO
var _prev_yaw := 0.0
var _prev_pitch := 0.0
var _bob_phase := 0.0
var _bob_amp := 0.0
var _bob_x := 0.0
var _bob_y := 0.0
var _bob_roll := 0.0
var _breath_y := 0.0
var _breath_roll := 0.0
var _move_speed := 0.0

## 瞄准与动作表现（参数见 guns.json ads/anim 节）：右键 ADS、开火上抬、换弹/换枪程序动画、抛壳
var _ads_cfg: Dictionary = {}
var _anim_cfg: Dictionary = {}
var _ads := false
var _ads_t := 0.0        # 0..1 ADS 过渡
var _kick := 0.0         # 开火累积上抬（弧度），指数回正
var _fire_shake := 0.0   # 开火瞬间镜头轻抖
var _switch_t := 0.0     # 换枪动作剩余时间
var _reload_p := 0.0     # 换弹进度 0..1，sin 包络驱动枪身下沉
var _eject_t := 0.0
var _shells: Array = []
var _shell_mat: StandardMaterial3D

func setup(main: Node, m: int) -> void:
	main_node = main
	mode = m

func _ready() -> void:
	# 车内/车顶玩家不参与房车碰撞，避免房车把自己的玩家胶囊当障碍；车内只检测独立内饰层
	collision_layer = 1 if mode == Mode.ON_FOOT else 0
	collision_mask = main_node.INTERIOR_COLLISION_LAYER if mode == Mode.RV_WALK else 1
	floor_snap_length = 0.5
	if mode == Mode.RV_WALK:
		# 玩家已作为房车子节点随父节点移动，不能再叠加移动平台速度
		platform_floor_layers = 0
	# 车内胶囊略收窄，保证中央过道可通行；车外与丧尸同款尺寸
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.24 if mode == Mode.RV_WALK else 0.35
	cap.height = 1.5
	col.shape = cap
	col.position.y = 0.75
	add_child(col)
	# 主角 GLB（脚底 y=0，真实米数 scale=1）；战斗态自管 aim/walk/run，关掉活感插播
	var made := CharUtil.instantiate("hero", "aim", {}, false)
	model_root = made["node"]
	_anim = made["anim"]
	for a in ["aim", "walk", "run", "crouch", "prone"]:
		_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_anim.get_animation("jump").loop_mode = Animation.LOOP_NONE
	add_child(model_root)
	# 第三人称保留完整服装；车顶第一人称再统一隐藏自身网格，避免低机位穿模
	for mesh in model_root.find_children("*", "MeshInstance3D", true, false):
		_body_meshes.append(mesh)
	# 武器数据
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/guns.json"))
	_guns = parsed["guns"]
	_gun_order = parsed["order"]
	_sway_cfg = parsed.get("sway", {})
	_ads_cfg = parsed.get("ads", {})
	_anim_cfg = parsed.get("anim", {})
	_grenade_cfg = parsed.get("grenade", {})
	_grenades = int(_grenade_cfg.get("count", 0))
	for id in _gun_order:
		_ammo_map[id] = int(_guns[id]["mag_size"])
	# 枪挂点：位置按 aim 动作双手实测对位；grip 点对齐到这里
	gun = Node3D.new()
	gun.position = GUN_POS
	model_root.add_child(gun)
	# FPS 全身：记录 Head 骨，第一人称时缩零隐藏头/发（身体与持枪手臂保持可见）
	var skels := model_root.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		_skel = skels[0]
		_head_bone = _skel.find_bone("J_Bip_C_Head")
		_skel.pose_updated.connect(_on_pose_updated)
	_equip_current()
	cam = Camera3D.new()
	cam.fov = 68.0
	cam.current = false
	add_child(cam)
	# 下车第三人称使用原生伸缩臂；相机仍由玩家脚本控制，车内/车顶专用机位不受影响
	_camera_arm = SpringArm3D.new()
	_camera_arm.spring_length = 4.5
	_camera_arm.margin = 0.2
	_camera_arm.collision_mask = 1
	_camera_arm.add_excluded_object(get_rid())
	var arm_shape := SphereShape3D.new()
	arm_shape.radius = 0.2
	_camera_arm.shape = arm_shape
	add_child(_camera_arm)

## 当前枪配置
func _cfg() -> Dictionary:
	return _guns[_gun_order[_gun_idx]]

func ammo() -> int:
	return _ammo_map[_gun_order[_gun_idx]]

## 装备当前枪：清旧模型，按 JSON 实例化 GLB（grip 对齐挂点、muzzle 定位）
func _equip_current() -> void:
	for c in gun.get_children():
		c.queue_free()
	var cfg := _cfg()
	var packed: PackedScene = load(cfg["model"])
	var wm: Node3D = packed.instantiate()
	var sc: float = cfg["scale"]
	wm.scale = Vector3.ONE * sc
	var rd: Array = cfg["rot_deg"]
	wm.rotation_degrees = Vector3(rd[0], rd[1], rd[2])
	var grip: Array = cfg["grip"]
	wm.position = -Vector3(grip[0], grip[1], grip[2]) * sc
	gun.add_child(wm)
	muzzle = Node3D.new()
	var mz: Array = cfg["muzzle"]
	muzzle.position = Vector3(mz[0], mz[1], mz[2])
	wm.add_child(muzzle)
	# 去掉模型自带的 GPS/弹药箱/弹链等外挂杂物，只保留枪体与瞄具
	for p in ["gps", "bullets", "belt"]:
		var part := wm.find_child(p, true, false)
		if part is Node3D:
			part.visible = false
	# 手臂与枪共用挂点：原 aim 右手位置是 GUN_POS，平移回来后坐/换弹时双手不离开枪
	_fps_arms = FPS_ARMS_SCENE.instantiate() as Node3D
	_fps_arms.position = -GUN_POS
	_fps_arms.visible = fps and mode != Mode.SUNROOF
	gun.add_child(_fps_arms)
	CharUtil._fix_materials(_fps_arms)
	for arm_mesh in _fps_arms.find_children("*", "MeshInstance3D", true, false):
		for surface in arm_mesh.mesh.get_surface_count():
			var arm_mat := arm_mesh.get_active_material(surface) as StandardMaterial3D
			if arm_mat != null:
				arm_mat.emission_enabled = false
				if arm_mesh.name == "Body":
					arm_mat.albedo_color = Color(0.78, 0.62, 0.52)
	var arms_anim := _fps_arms.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if arms_anim != null:
		arms_anim.get_animation("aim").loop_mode = Animation.LOOP_LINEAR
		arms_anim.play("aim")
		arms_anim.advance(0.0)
	# 右手保留原生握把位置，左手对齐护木；换弹时托枪手再独立下伸
	_fps_support = Node3D.new()
	var support_pos: Array = cfg["fps_support"]
	_fps_support_pos = Vector3(support_pos[0], support_pos[1], support_pos[2])
	_fps_support.position = _fps_support_pos
	gun.add_child(_fps_support)
	var arms_skel := _fps_arms.find_child("Skeleton3D", true, false) as Skeleton3D
	# 复用 drive 相对 aim 的指骨屈曲方向，小幅加强握持，避免近景张开手掌
	_fps_finger_pose.clear()
	var drive_pose: Dictionary = {}
	arms_anim.play("drive")
	arms_anim.advance(0.0)
	for side in ["L", "R"]:
		for finger in ["Index", "Middle", "Ring", "Little", "Thumb"]:
			for joint in [1, 2, 3]:
				var bone := arms_skel.find_bone("J_Bip_%s_%s%d" % [side, finger, joint])
				drive_pose[bone] = arms_skel.get_bone_pose_rotation(bone)
	arms_anim.play("aim")
	arms_anim.advance(0.0)
	for bone in drive_pose:
		var aim_rot := arms_skel.get_bone_pose_rotation(bone)
		var delta: Quaternion = aim_rot.inverse() * drive_pose[bone]
		_fps_finger_pose[bone] = (aim_rot * delta * Quaternion().slerp(delta, 0.6)).normalized()
	arms_skel.force_update_all_bone_transforms()
	_fps_left_hand = arms_skel.find_bone("J_Bip_L_Hand")
	var hand_basis := (arms_skel.global_transform * arms_skel.get_bone_global_pose(_fps_left_hand)).basis
	_fps_support.basis = gun.global_transform.basis.inverse() * hand_basis
	_fps_sleeves.clear()
	var sleeve_mat := StandardMaterial3D.new()
	sleeve_mat.albedo_color = Color(0.12, 0.15, 0.16)
	sleeve_mat.roughness = 0.92
	for i in 2:
		var sleeve := MeshInstance3D.new()
		var sm := CapsuleMesh.new()
		sm.radius = 0.042
		sm.height = 0.24
		sm.radial_segments = 16
		sm.rings = 6
		sleeve.mesh = sm
		sleeve.material_override = sleeve_mat
		arms_skel.add_child(sleeve)
		_fps_sleeves.append(sleeve)
	arms_skel.pose_updated.connect(_update_fps_sleeves)
	_update_fps_sleeves()
	main_node.hud.set_combat_gun(cfg["name"], ammo(), int(cfg["mag_size"]))
	main_node.hud.set_combat_grenades(_grenades)

func _update_fps_sleeves() -> void:
	if _fps_sleeves.size() != 2:
		return
	var skel := _fps_sleeves[0].get_parent() as Skeleton3D
	for bone in _fps_finger_pose:
		skel.set_bone_pose_rotation(bone, _fps_finger_pose[bone])
	for i in 2:
		var side := "L" if i == 0 else "R"
		var elbow := skel.get_bone_global_pose(skel.find_bone("J_Bip_%s_LowerArm" % side)).origin
		var wrist := skel.get_bone_global_pose(skel.find_bone("J_Bip_%s_Hand" % side)).origin
		var dir := (wrist - elbow).normalized()
		var start := elbow - dir * 0.10
		var end := wrist + dir * 0.035
		var sleeve := _fps_sleeves[i]
		sleeve.position = (start + end) * 0.5
		sleeve.quaternion = Quaternion(Vector3.UP, dir)
		sleeve.scale = Vector3(1.0, start.distance_to(end) / 0.24, 1.0)

## 切换武器（数字键直选 / HUD 按钮循环）
func switch_gun(idx: int) -> void:
	if idx == _gun_idx or idx < 0 or idx >= _gun_order.size():
		return
	_gun_idx = idx
	reload_t = 0.0
	_switch_t = float(_anim_cfg.get("switch_time", 0.16))
	_equip_current()
	main_node.sfx.play("reload", 1.3)
	main_node.hud.toast(_cfg()["name"])

func switch_gun_next() -> void:
	switch_gun((_gun_idx + 1) % _gun_order.size())

func _enter() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_crouching = false
	_airborne = false
	cam.current = true
	if mode == Mode.RV_WALK:
		cam.fov = 86.0   # 车内广角：狭长空间显大
		main_node.hud.set_rv_walk_active(true)
	else:
		main_node.hud.set_combat_active(true, ammo(), hp)
	_equip_current()

func _exit() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cam.current = false
	cam.fov = 68.0
	_firing = false
	_ads = false
	_ads_t = 0.0
	_kick = 0.0
	_fire_shake = 0.0
	if fps:
		toggle_fps()
	if mode == Mode.RV_WALK:
		main_node.hud.set_rv_walk_active(false)
	else:
		main_node.hud.set_combat_active(false, ammo(), hp)

## 第一/第三人称切换：FPS 显示独立的真实手臂网格，原全身隐藏防躯干穿镜头
func toggle_fps(force := false) -> void:
	if mode == Mode.RV_WALK and not force:
		return
	fps = not fps
	if not fps and _head_bone >= 0:
		_skel.set_bone_pose_scale(_head_bone, Vector3.ONE)
	for mesh in _body_meshes:
		mesh.visible = not fps
	if _fps_arms != null:
		_fps_arms.visible = fps and mode != Mode.SUNROOF
	main_node.hud.toast("第一人称" if fps else "第三人称")

## FPS 期间每帧把 Head 骨缩零（动画每帧重写 pose，须在 pose_updated 后覆盖）
func _on_pose_updated() -> void:
	if fps and _head_bone >= 0:
		_skel.set_bone_pose_scale(_head_bone, Vector3.ZERO)

func _unhandled_input(event: InputEvent) -> void:
	var pitch_hi := 1.35 if fps else 0.35   # FPS 允许抬头看天
	var pitch_lo := -0.55 if mode == Mode.SUNROOF else -1.35   # 车顶卧姿压低枪口有下限，防穿车顶
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		aim_yaw -= event.relative.x * MOUSE_SENS
		aim_pitch = clampf(aim_pitch - event.relative.y * MOUSE_SENS, pitch_lo, pitch_hi)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_firing = event.pressed
		if event.pressed:
			_try_fire()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		set_ads(event.pressed)
	elif event is InputEventScreenDrag:
		# 触屏右半屏拖动瞄准（摇杆区事件已被 HUD 消费，到不了这里）
		aim_yaw -= event.relative.x * MOUSE_SENS * 1.6
		aim_pitch = clampf(aim_pitch - event.relative.y * MOUSE_SENS * 1.6, pitch_lo, pitch_hi)
	elif event is InputEventKey and event.pressed and not event.echo:
		# 数字键 1-4 直选武器
		if event.keycode >= KEY_1 and event.keycode <= KEY_4:
			switch_gun(int(event.keycode - KEY_1))
		elif event.keycode == KEY_V:
			toggle_fps()
		elif event.keycode == KEY_X:
			throw_grenade()

## HUD 开火按钮：按下开火（半自动单发、全自动按住连发），松开停火
func press_fire() -> void:
	_firing = true
	_try_fire()

func release_fire() -> void:
	_firing = false

## HUD 换弹按钮（R 键路径复用）
func reload() -> void:
	if ammo() < int(_cfg()["mag_size"]) and reload_t == 0.0:
		reload_t = float(_cfg()["reload_time"])
		main_node.sfx.play("reload", 1.05)
		main_node.hud.toast("换弹中……")

func _physics_process(delta: float) -> void:
	if main_node == null or main_node.game_over:
		return
	fire_cd = maxf(0.0, fire_cd - delta)
	reload_t = maxf(0.0, reload_t - delta)
	if reload_t == 0.0 and ammo() == 0 and fire_cd == 0.0:
		_finish_reload()
	# 动作表现：ADS 过渡、后坐回正、换枪计时、换弹包络、抛壳飞行
	_switch_t = maxf(0.0, _switch_t - delta)
	_ads_t = move_toward(_ads_t, 1.0 if _ads else 0.0, delta / maxf(0.01, float(_ads_cfg.get("in" if _ads else "out", 0.15))))
	_kick = lerpf(_kick, 0.0, clampf(delta * float(_anim_cfg.get("kick_recover", 7.0)), 0.0, 1.0))
	_fire_shake = maxf(0.0, _fire_shake - delta * 4.5)
	_reload_p = (1.0 - reload_t / maxf(0.01, float(_cfg()["reload_time"]))) if reload_t > 0.0 else 0.0
	_eject_t = maxf(0.0, _eject_t - delta)
	_update_shells(delta)
	# 全自动：按住左键持续开火
	if _firing and bool(_cfg()["auto"]):
		_try_fire()
	# G/T 撤离由 main 统一处理（同时负责开关）；R：换弹
	var rk := _key_down(KEY_R)
	if rk and not _r_down:
		reload()
	_r_down = rk
	var sk := _key_down(KEY_SPACE)
	if sk and not _space_down:
		jump()
	_space_down = sk
	var ck := _key_down(KEY_C)
	if ck and not _c_down:
		toggle_crouch()
	_c_down = ck
	if mode == Mode.RV_WALK:
		_move_rv(delta)
		main_node.hud.set_rv_walk_fire_enabled(_near_rv_port())
	elif mode == Mode.ON_FOOT:
		_move_foot(delta)
	else:
		# 房车先完成物理移动，再在同一物理帧锚定车顶并更新相机，避免渲染帧二次改位置
		position = main_node.rv.to_global(main_node.ROOF_ACCESS_POS)
		_move_speed = 0.0
		velocity = Vector3.ZERO
		move_and_slide()
		if _cur_anim != "prone":
			_cur_anim = "prone"
			_anim.play("prone", 0.15)
	_update_sway(delta)
	_aim_and_camera(delta)

## 物理键位 + 逻辑键位双通道：远程串流注入的键事件通常只带逻辑键码
static func _key_down(k: int) -> bool:
	return Input.is_physical_key_pressed(k) or Input.is_key_pressed(k)

## 右键 ADS：收窄视野、枪身向中线靠、晃动与移速衰减；车内行走禁用
func set_ads(v: bool) -> void:
	if mode == Mode.RV_WALK:
		return
	_ads = v

## 车内行走：输入在 rv 本地空间解算，转换成世界速度后由物理引擎碰撞；地板顶 y=-0.4，车头 -Z
func _move_rv(delta: float) -> void:
	var input := Vector2.ZERO
	if _key_down(KEY_W) or _key_down(KEY_UP):
		input.y -= 1.0
	if _key_down(KEY_S) or _key_down(KEY_DOWN):
		input.y += 1.0
	if _key_down(KEY_A) or _key_down(KEY_LEFT):
		input.x -= 1.0
	if _key_down(KEY_D) or _key_down(KEY_RIGHT):
		input.x += 1.0
	input += touch_move
	var yaw_basis := Basis(Vector3.UP, aim_yaw)
	var dir := yaw_basis * Vector3(input.x, 0, input.y)
	_move_speed = WALK_SPEED * 0.55 if dir.length() > 0.01 else 0.0
	var local_velocity := dir.normalized() * _move_speed if dir.length() > 0.01 else Vector3.ZERO
	var world_velocity: Vector3 = main_node.rv.global_transform.basis * local_velocity
	velocity.x = world_velocity.x
	velocity.z = world_velocity.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	# 车内行走恒第一人称：锁端枪姿势，避免手臂摆动脱离枪挂点
	if _cur_anim != "aim":
		_cur_anim = "aim"
		_anim.play("aim", 0.15)

## 跳跃（Space / HUD 跳跃按钮）：滞空期间禁用下蹲
func jump() -> void:
	if mode != Mode.ON_FOOT or _airborne:
		return
	_crouching = false
	_airborne = true
	velocity.y = JUMP_VEL

## 下蹲切换（C / HUD 下蹲按钮）
func toggle_crouch() -> void:
	if mode != Mode.ON_FOOT or _airborne:
		return
	_crouching = not _crouching

func _move_foot(delta: float) -> void:
	var input := Vector2.ZERO
	if _key_down(KEY_W) or _key_down(KEY_UP):
		input.y -= 1.0
	if _key_down(KEY_S) or _key_down(KEY_DOWN):
		input.y += 1.0
	if _key_down(KEY_A) or _key_down(KEY_LEFT):
		input.x -= 1.0
	if _key_down(KEY_D) or _key_down(KEY_RIGHT):
		input.x += 1.0
	# 触屏摇杆输入叠加，推满自动奔跑（下蹲时强制慢走；ADS 禁冲刺）
	input += touch_move
	var sprinting := (_key_down(KEY_SHIFT) or touch_move.length() > 0.85) and not _crouching and _ads_t < 0.5
	var spd := RUN_SPEED if sprinting else WALK_SPEED
	if _crouching:
		spd *= CROUCH_MUL
	spd *= lerpf(1.0, float(_ads_cfg.get("move_mul", 0.62)), _ads_t)
	var yaw_basis := Basis(Vector3.UP, aim_yaw)
	var dir := yaw_basis * Vector3(input.x, 0, input.y)
	_move_speed = spd if dir.length() > 0.01 else 0.0
	if dir.length() > 0.01:
		dir = dir.normalized()
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	if is_on_floor() and not _airborne:
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	# 落地完全由 CharacterBody3D 碰撞判定；走离实体边缘时保留重力自然下落
	if _airborne and is_on_floor():
		velocity.y = 0.0
		_airborne = false
	# 下蹲时枪挂点下放在 _apply_gun 统一处理
	# 模型朝瞄准方向（GLB 正面朝 +Z，瞄准基准是 -Z，故补 180°）
	model_root.rotation.y = aim_yaw + PI
	# 动画优先级：跳跃 > 下蹲 > 走/跑 > 端枪戒备（变化才播，0.15s 融合）；第一人称锁端枪避免手离枪
	var want := "aim"
	if not fps:
		if dir.length() > 0.01:
			want = "run" if sprinting else "walk"
		if _crouching:
			want = "crouch"
		if _airborne:
			want = "jump"
	if want != _cur_anim:
		_cur_anim = want
		_anim.play(want, 0.15)

## 持枪晃动解算：呼吸（双频正弦）+ 步伐 bob（Lissajous）+ 视角惯性滞后
func _update_sway(delta: float) -> void:
	_sway_t += delta
	# 步伐幅度按移动速度渐变（起跑快淡入、停下慢淡出）
	var target_amp := clampf(_move_speed / WALK_SPEED, 0.0, 1.0)
	_bob_amp = lerpf(_bob_amp, target_amp, delta * (5.0 if target_amp > _bob_amp else 3.0))
	var freq := 1.55 + 0.85 * clampf(_move_speed / RUN_SPEED, 0.0, 1.0)
	_bob_phase += delta * TAU * freq
	_bob_x = cos(_bob_phase) * float(_sway_cfg.get("bob_x", 0.0075)) * _bob_amp
	_bob_y = sin(_bob_phase * 2.0) * float(_sway_cfg.get("bob_y", 0.006)) * _bob_amp
	_bob_roll = cos(_bob_phase) * float(_sway_cfg.get("bob_roll", 0.008)) * _bob_amp
	# 呼吸：移动时减弱 70%，原地端枪时最明显
	var br := (sin(_sway_t * 1.35) * 0.6 + sin(_sway_t * 2.13 + 1.7) * 0.4) * (1.0 - _bob_amp * 0.7)
	_breath_y = br * float(_sway_cfg.get("breath_y", 0.004))
	_breath_roll = br * float(_sway_cfg.get("breath_roll", 0.0015))
	# 视角惯性：枪滞后于视线，转头/抬枪时枪口先甩后收
	var dyaw := aim_yaw - _prev_yaw
	var dpitch := aim_pitch - _prev_pitch
	_prev_yaw = aim_yaw
	_prev_pitch = aim_pitch
	_look_sway.x = clampf(_look_sway.x - dyaw * float(_sway_cfg.get("look_yaw", 0.9)), -float(_sway_cfg.get("look_max_x", 0.07)), float(_sway_cfg.get("look_max_x", 0.07)))
	_look_sway.y = clampf(_look_sway.y + dpitch * float(_sway_cfg.get("look_pitch", 0.7)), -float(_sway_cfg.get("look_max_y", 0.05)), float(_sway_cfg.get("look_max_y", 0.05)))
	_look_sway = _look_sway.lerp(Vector2.ZERO, delta * float(_sway_cfg.get("look_recover", 8.0)))
	# ADS 时晃动整体收敛，瞄准更稳
	var sway_mul := lerpf(1.0, float(_ads_cfg.get("sway_scale", 0.28)), _ads_t)
	_bob_x *= sway_mul
	_bob_y *= sway_mul
	_bob_roll *= sway_mul
	_breath_y *= sway_mul
	_breath_roll *= sway_mul
	_look_sway *= sway_mul

## 统一写枪挂点姿态：后坐 + 开火上抬 + sway + ADS 靠中 + 换弹/换枪/跑动程序动画
func _apply_gun(delta: float) -> void:
	_recoil = maxf(0.0, _recoil - delta * 6.0)
	var view_pitch := aim_pitch + _kick
	var base_pos: Vector3 = GUN_POS_PRONE if mode == Mode.SUNROOF else GUN_POS
	if mode == Mode.ON_FOOT and _ads_t > 0.0:
		var ap: Array = _ads_cfg.get("pos", [-0.10, 1.24, 0.24])
		base_pos = base_pos.lerp(Vector3(ap[0], ap[1], ap[2]), _ads_t)
	# 第一人称把枪前移：让枪托越过镜头，画面里不再出现一大块枪托底板；ADS 时保持原校准距离
	if fps and mode != Mode.SUNROOF:
		base_pos.z += 0.30 * (1.0 - _ads_t)
	# 换弹单峰包络下沉；换枪起手重压后抬回；跑动低持侧倾
	var reload_env := sin(PI * _reload_p) if _reload_p > 0.0 else 0.0
	if _fps_support != null:
		_fps_support.position = _fps_support_pos + Vector3(-0.02, -0.15, 0.07) * reload_env
	var switch_env := 0.0
	var switch_time := float(_anim_cfg.get("switch_time", 0.16))
	if _switch_t > 0.0 and switch_time > 0.0:
		switch_env = _switch_t / switch_time
	var run_env := 0.0
	if mode == Mode.ON_FOOT:
		run_env = clampf((_move_speed - WALK_SPEED * 1.05) / maxf(0.01, RUN_SPEED - WALK_SPEED * 1.05), 0.0, 1.0) * (1.0 - _ads_t)
	var dip := reload_env * float(_anim_cfg.get("reload_dip", 0.16)) + switch_env * 0.22 + run_env * float(_anim_cfg.get("run_drop", 0.10))
	gun.rotation.x = -view_pitch - _recoil * 0.22 + _look_sway.y + run_env * 0.25
	gun.rotation.y = _look_sway.x
	gun.rotation.z = _bob_roll + _look_sway.x * 0.3 + _breath_roll + reload_env * float(_anim_cfg.get("reload_roll", 0.55)) + run_env * float(_anim_cfg.get("run_tilt", 0.30))
	gun.position.x = base_pos.x + _bob_x + _look_sway.x * 0.35
	gun.position.z = base_pos.z - _recoil * 0.03
	var base_y := base_pos.y
	if mode == Mode.ON_FOOT and _crouching:
		base_y = minf(base_y, 0.99)
	var target_y := base_y + _bob_y + _breath_y - dip
	if mode == Mode.ON_FOOT:
		gun.position.y = lerpf(gun.position.y, target_y, delta * 10.0)
	else:
		gun.position.y = target_y
	_align_fps_support()

## 左手只有手部网格，直接对齐护木；程序袖口连接原生肘点与修正后的腕点。
func _align_fps_support() -> void:
	if not _fps_arms.visible:
		return
	var skel := _fps_sleeves[0].get_parent() as Skeleton3D
	var pose := skel.global_transform.affine_inverse() * _fps_support.global_transform
	skel.set_bone_global_pose_override(_fps_left_hand, pose, 1.0, true)

## 抛壳：轻量弹壳按抛物线飞出，落地即消失（不用刚体，避免每发创建物理体）
func _eject_shell() -> void:
	if not bool(_anim_cfg.get("eject", true)) or _eject_t > 0.0:
		return
	_eject_t = 0.09
	if _shell_mat == null:
		_shell_mat = StandardMaterial3D.new()
		_shell_mat.albedo_color = Color(0.72, 0.52, 0.2)
		_shell_mat.metallic = 0.35
		_shell_mat.roughness = 0.5
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.007, 0.007, 0.022)
	mi.mesh = bm
	mi.material_override = _shell_mat
	main_node.add_child(mi)
	var right := global_transform.basis.x
	var back := global_transform.basis.z
	mi.global_position = muzzle.global_position + right * 0.12 + Vector3.UP * -0.02 + back * -0.1
	_shells.append({
		"node": mi,
		"vel": right * randf_range(1.6, 2.4) + Vector3.UP * randf_range(1.2, 1.8) + back * randf_range(0.4, 0.9),
		"t": 0.0,
	})

func _update_shells(delta: float) -> void:
	for i in range(_shells.size() - 1, -1, -1):
		var s: Dictionary = _shells[i]
		var node: MeshInstance3D = s["node"]
		var vel: Vector3 = s["vel"]
		s["t"] = float(s["t"]) + delta
		vel.y -= 9.8 * delta
		s["vel"] = vel
		node.global_position += vel * delta
		node.rotate_x(delta * 9.0)
		var gy: float = main_node.ground_height(node.global_position.x, node.global_position.z)
		if node.global_position.y <= gy + 0.02 or float(s["t"]) > 1.6:
			node.queue_free()
			_shells.remove_at(i)

func _aim_and_camera(delta: float) -> void:
	# 身体随瞄准转身（GLB 正面朝 +Z，瞄准基准是 -Z，故补 180°）
	model_root.rotation.y = aim_yaw + PI
	model_root.rotation.x = 0.0
	model_root.position.y = 0.0
	if mode == Mode.RV_WALK:
		# 车内：aim_yaw 是 rv 本地朝向，相机直接用本地变换（车转弯不甩视角）
		var eye := Vector3(0, FPS_EYE, 0)
		cam.transform = Transform3D(Basis(Vector3.UP, aim_yaw) * Basis(Vector3.RIGHT, aim_pitch), eye)
		_apply_gun(delta)
		return
	var view_pitch := aim_pitch + _kick
	var cam_basis := Basis(Vector3.UP, aim_yaw)
	var right := cam_basis.x
	var back := cam_basis.z   # 瞄准基准 -Z，+Z 即玩家身后
	if fps:
		# 第一人称：相机贴眼位（下蹲降眼高；车顶卧姿眼位移到前伸的头部），全身可见仅头骨缩零
		var eye_h := FPS_EYE_CROUCH if _crouching else FPS_EYE
		var eye_back := 0.05
		if mode == Mode.SUNROOF:
			eye_h = FPS_EYE_PRONE
			eye_back = -0.30   # 与站立视角保持相同的枪后距离
		cam.global_position = global_position + Vector3(0, eye_h, 0) + back * eye_back
	else:
		if mode == Mode.ON_FOOT:
			# 原生形状扫掠同时处理墙体与身后上坡，命中后自动缩短肩后距离
			_camera_arm.global_transform = Transform3D(cam_basis, global_position + Vector3(0, 3.6, 0))
			cam.global_position = _camera_arm.global_position + back * _camera_arm.get_hit_length()
		else:
			# 车顶卧姿：保留贴近车顶的专用跟拍机位
			cam.global_position = global_position + Vector3(0, 2.2, 0) + back * 3.6
			cam.global_position.y = maxf(cam.global_position.y, main_node.ground_height(cam.global_position.x, cam.global_position.z) + 0.35)
	var look_dir := (cam_basis * Vector3(0, 0, -1)).rotated(right, view_pitch)
	cam.look_at(cam.global_position + look_dir * 10.0, Vector3.UP)
	# ADS 收窄视野；开火瞬间小幅镜头抖动（旋转偏移，不影响瞄准基准）
	cam.fov = lerpf(68.0, float(_ads_cfg.get("fov", 52.0)), _ads_t)
	if _fire_shake > 0.001:
		cam.rotate_object_local(Vector3.RIGHT, randf_range(-1.0, 1.0) * _fire_shake * 0.4)
		cam.rotate_object_local(Vector3.FORWARD, randf_range(-1.0, 1.0) * _fire_shake * 0.35)
	# 受击/爆炸 trauma 抖动（main 在战斗态持续衰减），平方曲线让轻伤不晃、重伤明显
	var shake: float = main_node.trauma * main_node.trauma
	if shake > 0.0001:
		cam.global_position += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * 0.03 * shake
		cam.rotate_object_local(Vector3.FORWARD, randf_range(-1.0, 1.0) * 0.035 * shake)
	# 准星扩散：移动晃动与后坐放大，ADS 收拢
	var spread := 1.0 + (_bob_amp * 0.22 + _recoil * 0.22) * (1.0 - _ads_t * 0.6)
	main_node.hud.set_crosshair_spread(spread * lerpf(1.0, 0.7, _ads_t))
	# 枪身随俯仰角指向瞄点，开火瞬间后坐上抬；sway/蹲姿下放统一在 _apply_gun
	_apply_gun(delta)
	main_node.hud.set_combat_aim(look_dir, cam.global_position)

func _near_rv_port() -> bool:
	for p in main_node.RV_PORT_POINTS:
		if position.distance_squared_to(p) <= main_node.RV_PORT_RANGE * main_node.RV_PORT_RANGE:
			return true
	return false

func _try_fire() -> void:
	if mode == Mode.RV_WALK and not _near_rv_port():
		main_node.hud.toast("靠近窗射孔或尾射孔开枪")
		fire_cd = 0.8
		return
	if fire_cd > 0.0 or _switch_t > 0.0:
		return
	var cfg := _cfg()
	if ammo() == 0:
		if reload_t == 0.0:
			reload_t = float(cfg["reload_time"])
			main_node.sfx.play("reload")
			main_node.hud.toast("弹匣空了，换弹……")
		return
	if reload_t > 0.0:
		return
	_ammo_map[_gun_order[_gun_idx]] -= 1
	fire_cd = float(cfg["fire_interval"])
	_recoil = float(cfg["recoil"])
	# 开火上抬累积 + 镜头轻抖 + 抛壳
	_kick = minf(_kick + float(_anim_cfg.get("kick_pitch", 0.018)), float(_anim_cfg.get("kick_max", 0.10)))
	_fire_shake = float(_anim_cfg.get("fire_shake", 0.06))
	_eject_shell()
	main_node.sfx.play("gunshot", 1.0, 0.05, 2.0)
	# 准星收敛弹道：先求相机中心射线目标点，实弹从枪口朝该点飞（排除自身与房车）
	var exclude := [self.get_rid(), main_node.rv.get_rid()]
	var aim_from := cam.global_position
	var aim_dir := -cam.global_transform.basis.z
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(aim_from, aim_from + aim_dir * RAY_DIST)
	q.collide_with_areas = false
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	var target: Vector3 = hit["position"] if hit else aim_from + aim_dir * RAY_DIST
	var muzzle_ws := muzzle.global_position
	var dir := (target - muzzle_ws).normalized()
	# 相机在身后：俯角大时目标点可能落在枪口后方，导致弹道反向，直接沿瞄准方向打
	if dir.dot(aim_dir) < 0.5:
		dir = aim_dir
	main_node.spawn_bullet(muzzle_ws, dir, float(cfg["bullet_speed"]), exclude, float(cfg.get("damage", 1)))
	# 枪声惊动周围尸群
	main_node.alert_gunshot(muzzle_ws)
	main_node.spawn_muzzle_flash(muzzle_ws)
	main_node.hud.set_combat_ammo(ammo(), int(reload_t > 0.0), int(main_node.ammo_reserve))

## X：投掷手雷（抛物线 + 引信爆炸，AOE 杀伤；HUD 余量拼在枪名行尾）
func throw_grenade() -> void:
	if mode == Mode.RV_WALK:
		main_node.hud.toast("车内无法投掷，Q 回驾驶座后下车作战")
		return
	if _grenades <= 0:
		main_node.hud.toast("手雷用完了")
		return
	_grenades -= 1
	# 出手点取枪口，方向沿瞄准、略抬抛角
	var from := muzzle.global_position
	var dir := (-cam.global_transform.basis.z + Vector3.UP * 0.18).normalized()
	main_node.throw_grenade(from, dir, _grenade_cfg)
	main_node.sfx.play("reload", 1.6)   # 拔销脆响
	main_node.hud.set_combat_grenades(_grenades)
	main_node.hud.toast("手雷投出！剩余 %d" % _grenades)

func _finish_reload() -> void:
	var mag := int(_cfg()["mag_size"])
	if ammo() == mag:
		return
	# 从共享备弹领取：有多少装多少，备弹 0 则保持空仓停火
	var take := mini(mag - ammo(), int(main_node.ammo_reserve))
	main_node.ammo_reserve -= float(take)
	_ammo_map[_gun_order[_gun_idx]] = ammo() + take
	main_node.hud.set_combat_ammo(ammo(), 0, int(main_node.ammo_reserve))
	if take <= 0:
		main_node.hud.toast("备弹打光了，回营地复装或搜刮弹药箱")

func take_damage(amount: float, from := Vector3.ZERO) -> void:
	hp = maxf(0.0, hp - amount)
	main_node.add_trauma(0.35)
	main_node.hud.set_combat_hp(hp)
	main_node.hud.flash_damage(amount, from, aim_yaw, global_position)
	if hp <= 0.0:
		main_node.on_player_dead()
