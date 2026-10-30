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
var cam: Camera3D
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

func setup(main: Node, m: int) -> void:
	main_node = main
	mode = m

func _ready() -> void:
	# 车内由本地坐标移动，不对外参与碰撞，避免房车把车内玩家当障碍推挤
	collision_layer = 0 if mode == Mode.RV_WALK else 1
	# 胶囊碰撞：与丧尸同款尺寸
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
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
	main_node.hud.set_combat_gun(cfg["name"], ammo(), int(cfg["mag_size"]))
	main_node.hud.set_combat_grenades(_grenades)

## 切换武器（数字键直选 / HUD 按钮循环）
func switch_gun(idx: int) -> void:
	if idx == _gun_idx or idx < 0 or idx >= _gun_order.size():
		return
	_gun_idx = idx
	reload_t = 0.0
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
		cam.fov = 80.0   # 车内广角：狭长空间显大
		main_node.hud.set_rv_walk_active(true)
	else:
		main_node.hud.set_combat_active(true, ammo(), hp)
	_equip_current()

func _exit() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cam.current = false
	cam.fov = 68.0
	_firing = false
	if fps:
		toggle_fps()
	if mode == Mode.RV_WALK:
		main_node.hud.set_rv_walk_active(false)
	else:
		main_node.hud.set_combat_active(false, ammo(), hp)

## 第一/第三人称切换：FPS 全身可见，仅 Head 骨缩零隐头/发防挡视线（车内行走强制 FPS，禁切回；force 供进入时强制开）
func toggle_fps(force := false) -> void:
	if mode == Mode.RV_WALK and not force:
		return
	fps = not fps
	if not fps and _head_bone >= 0:
		_skel.set_bone_pose_scale(_head_bone, Vector3.ONE)
	if mode == Mode.SUNROOF:
		for mesh in _body_meshes:
			mesh.visible = not fps
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
	# 全自动：按住左键持续开火
	if _firing and bool(_cfg()["auto"]):
		_try_fire()
	# G/T 撤离由 main 统一处理（同时负责开关）；R：换弹
	var rk := Input.is_physical_key_pressed(KEY_R)
	if rk and not _r_down:
		reload()
	_r_down = rk
	var sk := Input.is_physical_key_pressed(KEY_SPACE)
	if sk and not _space_down:
		jump()
	_space_down = sk
	var ck := Input.is_physical_key_pressed(KEY_C)
	if ck and not _c_down:
		toggle_crouch()
	_c_down = ck
	if mode == Mode.RV_WALK:
		_move_rv(delta)
	elif mode == Mode.ON_FOOT:
		_move_foot(delta)
	else:
		_move_speed = 0.0
		velocity = Vector3.ZERO
		move_and_slide()
		if _cur_anim != "prone":
			_cur_anim = "prone"
			_anim.play("prone", 0.15)
	_update_sway(delta)
	_aim_and_camera(delta)

## 车内行走：玩家挂在 rv 下，本地空间直接挪动（无物理）；地板顶 y=-0.4，车头 -Z
func _move_rv(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input.x += 1.0
	input += touch_move
	var yaw_basis := Basis(Vector3.UP, aim_yaw)
	var dir := yaw_basis * Vector3(input.x, 0, input.y)
	_move_speed = WALK_SPEED * 0.55 if dir.length() > 0.01 else 0.0
	if dir.length() > 0.01:
		position += dir.normalized() * WALK_SPEED * 0.55 * delta
	# 活动范围：仪表台后到尾壁前（内饰实测尾壁 z=3.07），两侧舱壁内
	position.x = clampf(position.x, -1.06 * main_node.INTERIOR_SCALE.x, 1.06 * main_node.INTERIOR_SCALE.x)
	position.z = clampf(position.z, -2.72 * main_node.INTERIOR_SCALE.z, 2.68 * main_node.INTERIOR_SCALE.z)
	position.y = -0.4
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
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input.x += 1.0
	# 触屏摇杆输入叠加，推满自动奔跑（下蹲时强制慢走）
	input += touch_move
	var sprinting := (Input.is_physical_key_pressed(KEY_SHIFT) or touch_move.length() > 0.85) and not _crouching
	var spd := RUN_SPEED if sprinting else WALK_SPEED
	if _crouching:
		spd *= CROUCH_MUL
	var yaw_basis := Basis(Vector3.UP, aim_yaw)
	var dir := yaw_basis * Vector3(input.x, 0, input.y)
	_move_speed = spd if dir.length() > 0.01 else 0.0
	if dir.length() > 0.01:
		dir = dir.normalized()
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	velocity.y -= GRAVITY * delta
	move_and_slide()
	var ground: float = main_node.ground_height(position.x, position.z)
	if _airborne:
		# 滞空：仅下落段才检测落地（起跳帧 y 还在地面，直接判会瞬间落地）；落到地形或实体（残骸/障碍/车体）上都算
		if velocity.y <= 0.0 and (position.y <= ground or is_on_floor()):
			if not is_on_floor():
				position.y = ground
			velocity.y = 0.0
			_airborne = false
	else:
		# 贴地：跟随地形；被实体托住（站上残骸/障碍）时不拉回地面
		if not (is_on_floor() and position.y > ground + 0.05):
			position.y = ground
		velocity.y = 0.0
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

## 统一写枪挂点姿态：后坐衰减 + sway 叠加 + 蹲姿下放
func _apply_gun(delta: float) -> void:
	_recoil = maxf(0.0, _recoil - delta * 6.0)
	gun.rotation.x = -aim_pitch - _recoil * 0.22 + _look_sway.y
	gun.rotation.y = _look_sway.x
	gun.rotation.z = _bob_roll + _look_sway.x * 0.3 + _breath_roll
	var base_pos := GUN_POS_PRONE if mode == Mode.SUNROOF else GUN_POS
	gun.position.x = base_pos.x + _bob_x + _look_sway.x * 0.35
	gun.position.z = base_pos.z
	var base_y := base_pos.y
	if mode == Mode.ON_FOOT and _crouching:
		base_y = 0.99
	var target_y := base_y + _bob_y + _breath_y
	if mode == Mode.ON_FOOT:
		gun.position.y = lerpf(gun.position.y, target_y, delta * 10.0)
	else:
		gun.position.y = target_y

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
		# MOBA 式斜背后高位俯视：玩家居画面下方，准星指向远处战场，宏观感知敌我态势
		# 车顶卧姿：相机降到贴近车顶跟拍
		cam.global_position = global_position + (Vector3(0, 2.2, 0) + back * 3.6 if mode == Mode.SUNROOF else Vector3(0, 3.6, 0) + back * 4.5)
		# 坡地防穿：身后是上坡时 3.6m 高可能埋进土里，抬到地面以上
		cam.global_position.y = maxf(cam.global_position.y, main_node.ground_height(cam.global_position.x, cam.global_position.z) + 0.35)
	var look_dir := (cam_basis * Vector3(0, 0, -1)).rotated(right, aim_pitch)
	cam.look_at(cam.global_position + look_dir * 10.0, Vector3.UP)
	# 枪身随俯仰角指向瞄点，开火瞬间后坐上抬；sway/蹲姿下放统一在 _apply_gun
	_apply_gun(delta)
	main_node.hud.set_combat_aim(look_dir, cam.global_position)

func _try_fire() -> void:
	if mode == Mode.RV_WALK:
		main_node.hud.toast("车内无法开枪，Q 回驾驶座后下车作战")
		fire_cd = 0.8
		return
	if fire_cd > 0.0:
		return
	var cfg := _cfg()
	var mag := int(cfg["mag_size"])
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

func take_damage(amount: float) -> void:
	hp = maxf(0.0, hp - amount)
	main_node.add_trauma(0.35)
	main_node.hud.set_combat_hp(hp)
	if hp <= 0.0:
		main_node.on_player_dead()
