extends CharacterBody3D
## 沈蔓下车战斗：第三人称肩后视角，鼠标瞄准，左键射击。
## 车顶天窗模式：身体固定在 RV 顶部，只能转身开火（行车中也能用）。
## W/A/S/D 地面移动，Shift 奔跑，R 换弹，1-4 换枪，G 回到驾驶座结束模式。
## 武器数据驱动（res://data/guns.json）：模型/缩放/朝向/射速/弹匣/后坐全在 JSON。

const WALK_SPEED := 4.2
const RUN_SPEED := 6.8
const MOUSE_SENS := 0.0026
const RAY_DIST := 90.0
const GRAVITY := 18.0

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
	for a in ["aim", "walk", "run"]:
		_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	add_child(model_root)
	# 武器数据
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/guns.json"))
	_guns = parsed["guns"]
	_gun_order = parsed["order"]
	for id in _gun_order:
		_ammo_map[id] = int(_guns[id]["mag_size"])
	# 枪挂点：位置按 aim 动作双手实测对位；grip 点对齐到这里
	gun = Node3D.new()
	gun.position = Vector3(-0.12, 1.30, 0.33)
	model_root.add_child(gun)
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
	cam.current = true
	main_node.hud.set_combat_active(true, ammo(), hp)
	_equip_current()

func _exit() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cam.current = false
	_firing = false
	main_node.hud.set_combat_active(false, ammo(), hp)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		aim_yaw -= event.relative.x * MOUSE_SENS
		aim_pitch = clampf(aim_pitch - event.relative.y * MOUSE_SENS, -1.2, 0.35)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_firing = event.pressed
		if event.pressed:
			_try_fire()
	elif event is InputEventKey and event.pressed and not event.echo:
		# 数字键 1-4 直选武器
		if event.keycode >= KEY_1 and event.keycode <= KEY_4:
			switch_gun(int(event.keycode - KEY_1))

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
	if rk and not _r_down and ammo() < int(_cfg()["mag_size"]) and reload_t == 0.0:
		reload_t = float(_cfg()["reload_time"])
		main_node.sfx.play("reload", 1.05)
		main_node.hud.toast("换弹中……")
	_r_down = rk
	if mode == Mode.ON_FOOT:
		_move_foot(delta)
	else:
		velocity = Vector3.ZERO
		move_and_slide()
	_aim_and_camera(delta)

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
	var sprinting := Input.is_physical_key_pressed(KEY_SHIFT)
	var spd := RUN_SPEED if sprinting else WALK_SPEED
	var yaw_basis := Basis(Vector3.UP, aim_yaw)
	var dir := yaw_basis * Vector3(input.x, 0, input.y)
	if dir.length() > 0.01:
		dir = dir.normalized()
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	velocity.y -= GRAVITY * delta
	move_and_slide()
	# 贴地：跟随地形
	position.y = main_node.ground_y(position.z)
	velocity.y = 0.0
	# 模型朝瞄准方向（GLB 正面朝 +Z，瞄准基准是 -Z，故补 180°）
	model_root.rotation.y = aim_yaw + PI
	# 动画：静止端枪戒备，走动/奔跑切换（变化才播，0.15s 融合）
	var want := "aim"
	if dir.length() > 0.01:
		want = "run" if sprinting else "walk"
	if want != _cur_anim:
		_cur_anim = want
		_anim.play(want, 0.15)

func _aim_and_camera(delta: float) -> void:
	# 身体随瞄准转身（GLB 正面朝 +Z，瞄准基准是 -Z，故补 180°）
	model_root.rotation.y = aim_yaw + PI
	var cam_basis := Basis(Vector3.UP, aim_yaw)
	var right := cam_basis.x
	var back := cam_basis.z   # 瞄准基准 -Z，+Z 即玩家身后
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
