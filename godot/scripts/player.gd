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
const FPS_GUN_POS := Vector3(0.24, -0.22, 0.5)   # 第一人称视模型枪位（眼部挂点本地，+Z 朝准星）
const FPS_EYE := 1.62        # 站立眼高
const FPS_EYE_CROUCH := 1.05 # 下蹲眼高

enum Mode { ON_FOOT, SUNROOF }

var main_node: Node   # duck-typed：调用 main/hud 上动态解析的方法
var mode: int = Mode.ON_FOOT
var aim_yaw := 0.0
var aim_pitch := -0.32   # 高位俯视默认下压枪口，准星落在地面战场
var fire_cd := 0.0
var reload_t := 0.0
var hp := 100.0
var model_root: Node3D
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

var _r_down := false
var _recoil := 0.0
var fps := false             # 第一人称视角（V / HUD 视角按钮）
var fps_rig: Node3D          # 第一人称时的枪挂点（挂在自身，不随 model_root 隐藏）
var touch_move := Vector2.ZERO   # HUD 虚拟摇杆输入（-1..1），与键盘并存
var _airborne := false           # 跳跃滞空中（落地才恢复贴地）
var _crouching := false
var _space_down := false
var _c_down := false

func setup(main: Node, m: int) -> void:
	main_node = main
	mode = m

func _ready() -> void:
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
	for a in ["aim", "walk", "run", "crouch"]:
		_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_anim.get_animation("jump").loop_mode = Animation.LOOP_NONE
	add_child(model_root)
	# 武器数据
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/guns.json"))
	_guns = parsed["guns"]
	_gun_order = parsed["order"]
	for id in _gun_order:
		_ammo_map[id] = int(_guns[id]["mag_size"])
	# 枪挂点：位置按 aim 动作双手实测对位；grip 点对齐到这里
	gun = Node3D.new()
	gun.position = GUN_POS
	model_root.add_child(gun)
	fps_rig = Node3D.new()
	add_child(fps_rig)
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
	main_node.hud.set_combat_active(true, ammo(), hp)
	_equip_current()

func _exit() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cam.current = false
	_firing = false
	if fps:
		toggle_fps()
	main_node.hud.set_combat_active(false, ammo(), hp)

## 第一/第三人称切换：FPS 隐藏身体，枪移到眼部挂点当视模型
func toggle_fps() -> void:
	fps = not fps
	if fps:
		gun.reparent(fps_rig)
		gun.position = FPS_GUN_POS
	else:
		gun.reparent(model_root)
		gun.position = GUN_POS
	gun.rotation = Vector3.ZERO
	model_root.visible = not fps
	main_node.hud.toast("第一人称" if fps else "第三人称")

func _unhandled_input(event: InputEvent) -> void:
	var pitch_hi := 1.35 if fps else 0.35   # FPS 允许抬头看天
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		aim_yaw -= event.relative.x * MOUSE_SENS
		aim_pitch = clampf(aim_pitch - event.relative.y * MOUSE_SENS, -1.35, pitch_hi)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_firing = event.pressed
		if event.pressed:
			_try_fire()
	elif event is InputEventScreenDrag:
		# 触屏右半屏拖动瞄准（摇杆区事件已被 HUD 消费，到不了这里）
		aim_yaw -= event.relative.x * MOUSE_SENS * 1.6
		aim_pitch = clampf(aim_pitch - event.relative.y * MOUSE_SENS * 1.6, -1.35, pitch_hi)
	elif event is InputEventKey and event.pressed and not event.echo:
		# 数字键 1-4 直选武器
		if event.keycode >= KEY_1 and event.keycode <= KEY_4:
			switch_gun(int(event.keycode - KEY_1))
		elif event.keycode == KEY_V:
			toggle_fps()

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
	if mode == Mode.ON_FOOT:
		_move_foot(delta)
	else:
		velocity = Vector3.ZERO
		move_and_slide()
	_aim_and_camera(delta)

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
	if dir.length() > 0.01:
		dir = dir.normalized()
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	velocity.y -= GRAVITY * delta
	move_and_slide()
	var ground: float = main_node.ground_height(position.x, position.z)
	if _airborne:
		# 滞空：仅下落段才检测落地（起跳帧 y 还在地面，直接判会瞬间落地）
		if velocity.y <= 0.0 and position.y <= ground:
			position.y = ground
			velocity.y = 0.0
			_airborne = false
	else:
		# 贴地：跟随地形
		position.y = ground
		velocity.y = 0.0
	# 下蹲时手臂随骨骼链下沉，枪挂点同步下放（FPS 枪位由 _aim_and_camera 管理）
	if not fps:
		gun.position.y = lerpf(gun.position.y, 0.99 if _crouching else GUN_POS.y, delta * 10.0)
	# 模型朝瞄准方向（GLB 正面朝 +Z，瞄准基准是 -Z，故补 180°）
	model_root.rotation.y = aim_yaw + PI
	# 动画优先级：跳跃 > 下蹲 > 走/跑 > 端枪戒备（变化才播，0.15s 融合）
	var want := "aim"
	if dir.length() > 0.01:
		want = "run" if sprinting else "walk"
	if _crouching:
		want = "crouch"
	if _airborne:
		want = "jump"
	if want != _cur_anim:
		_cur_anim = want
		_anim.play(want, 0.15)

func _aim_and_camera(delta: float) -> void:
	# 身体随瞄准转身（GLB 正面朝 +Z，瞄准基准是 -Z，故补 180°）
	model_root.rotation.y = aim_yaw + PI
	var cam_basis := Basis(Vector3.UP, aim_yaw)
	var right := cam_basis.x
	var back := cam_basis.z   # 瞄准基准 -Z，+Z 即玩家身后
	if fps:
		# 第一人称：相机贴眼位，枪挂点随视线同步（下蹲降眼高）
		var eye_h := FPS_EYE_CROUCH if _crouching else FPS_EYE
		cam.global_position = global_position + Vector3(0, eye_h, 0) + back * 0.05
		fps_rig.position = Vector3(0, eye_h, 0)
		fps_rig.rotation.y = aim_yaw + PI
	else:
		# MOBA 式斜背后高位俯视：玩家居画面下方，准星指向远处战场，宏观感知敌我态势
		cam.global_position = global_position + Vector3(0, 3.6, 0) + back * 4.5
	var look_dir := (cam_basis * Vector3(0, 0, -1)).rotated(right, aim_pitch)
	cam.look_at(cam.global_position + look_dir * 10.0, Vector3.UP)
	_recoil = maxf(0.0, _recoil - delta * 6.0)
	# 枪身随俯仰角指向瞄点，开火瞬间后坐上抬
	gun.rotation.x = -aim_pitch - _recoil * 0.22
	main_node.hud.set_combat_aim(look_dir, cam.global_position)

func _try_fire() -> void:
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
	main_node.spawn_bullet(muzzle_ws, dir, float(cfg["bullet_speed"]), exclude)
	# 枪声惊动周围尸群
	main_node.alert_gunshot(muzzle_ws)
	main_node.spawn_muzzle_flash(muzzle_ws)
	main_node.hud.set_combat_ammo(ammo(), int(reload_t > 0.0))

func _finish_reload() -> void:
	var mag := int(_cfg()["mag_size"])
	if ammo() == mag:
		return
	_ammo_map[_gun_order[_gun_idx]] = mag
	main_node.hud.set_combat_ammo(ammo(), 0)

func take_damage(amount: float) -> void:
	hp = maxf(0.0, hp - amount)
	main_node.add_trauma(0.35)
	main_node.hud.set_combat_hp(hp)
	if hp <= 0.0:
		main_node.on_player_dead()
