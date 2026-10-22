extends CharacterBody3D
## 沈蔓下车战斗：第三人称肩后视角，鼠标瞄准，左键射击。
## 车顶天窗模式：身体固定在 RV 顶部，只能转身开火（行车中也能用）。
## W/A/S/D 地面移动，Shift 奔跑，R 换弹，G 回到驾驶座结束模式。

const WALK_SPEED := 4.2
const RUN_SPEED := 6.8
const MOUSE_SENS := 0.0026
const FIRE_INTERVAL := 0.16
const MAG_SIZE := 12
const RELOAD_TIME := 1.4
const RAY_DIST := 90.0
const GRAVITY := 18.0

enum Mode { ON_FOOT, SUNROOF }

var main_node: Node   # duck-typed：调用 main/hud 上动态解析的方法
var mode: int = Mode.ON_FOOT
var aim_yaw := 0.0
var aim_pitch := 0.0
var fire_cd := 0.0
var reload_t := 0.0
var ammo := MAG_SIZE
var hp := 100.0
var model_root: Node3D
var muzzle: Node3D
var gun: Node3D
var cam: Camera3D

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
	# 主角 VRM（脚底 y=0，真实米数 scale=1）
	var made := CharUtil.instantiate("hero", "idle")
	model_root = made["node"]
	add_child(model_root)
	# 程序化步枪：枪托/机匣/枪管 + 枪口节点
	gun = _build_gun()
	gun.position = Vector3(0.28, 1.15, 0.28)
	model_root.add_child(gun)
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0.04, 0.72)
	gun.add_child(muzzle)
	cam = Camera3D.new()
	cam.fov = 68.0
	cam.current = false
	add_child(cam)

func _build_gun() -> Node3D:
	var g := Node3D.new()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.12, 0.12, 0.13)
	steel.metallic = 0.6
	steel.roughness = 0.4
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.28, 0.19, 0.11)
	wood.roughness = 0.9
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.1, 0.55)
	body.mesh = bm
	body.material_override = steel
	body.position.z = 0.05
	g.add_child(body)
	var barrel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.022
	cyl.bottom_radius = 0.022
	cyl.height = 0.42
	barrel.mesh = cyl
	barrel.rotation.x = PI * 0.5
	barrel.position = Vector3(0, 0.03, 0.5)
	barrel.material_override = steel
	g.add_child(barrel)
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.06, 0.16, 0.08)
	grip.mesh = gm
	grip.position = Vector3(0, -0.12, -0.02)
	grip.rotation.x = -0.3
	grip.material_override = wood
	g.add_child(grip)
	var stock := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.06, 0.11, 0.22)
	stock.mesh = sm
	stock.position = Vector3(0, -0.02, -0.32)
	stock.material_override = wood
	g.add_child(stock)
	return g

func _enter() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	cam.current = true
	main_node.hud.set_combat_active(true, ammo, hp)

func _exit() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cam.current = false
	main_node.hud.set_combat_active(false, ammo, hp)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		aim_yaw -= event.relative.x * MOUSE_SENS
		aim_pitch = clampf(aim_pitch - event.relative.y * MOUSE_SENS, -1.1, 0.6)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_fire()

func _physics_process(delta: float) -> void:
	if main_node == null or main_node.game_over:
		return
	fire_cd = maxf(0.0, fire_cd - delta)
	reload_t = maxf(0.0, reload_t - delta)
	if reload_t == 0.0 and ammo == 0 and fire_cd == 0.0:
		_finish_reload()
	# G/T 撤离由 main 统一处理（同时负责开关）；R：换弹
	var rk := Input.is_physical_key_pressed(KEY_R)
	if rk and not _r_down and ammo < MAG_SIZE and reload_t == 0.0:
		reload_t = RELOAD_TIME
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

func _aim_and_camera(delta: float) -> void:
	# 身体随瞄准转身（GLB 正面朝 +Z，瞄准基准是 -Z，故补 180°）
	model_root.rotation.y = aim_yaw + PI
	var cam_basis := Basis(Vector3.UP, aim_yaw)
	var right := cam_basis.x
	var back := -cam_basis.z
	cam.global_position = global_position + Vector3(0, 1.62, 0) + right * 0.55 + back * 3.2
	var look_dir := (cam_basis * Vector3(0, 0, -1)).rotated(right, aim_pitch)
	cam.look_at(cam.global_position + look_dir, Vector3.UP)
	_recoil = maxf(0.0, _recoil - delta * 6.0)
	# 枪身随俯仰角指向瞄点，开火瞬间后坐上抬
	gun.rotation.x = -aim_pitch - _recoil * 0.22
	main_node.hud.set_combat_aim(look_dir, cam.global_position)

func _try_fire() -> void:
	if fire_cd > 0.0:
		return
	if ammo == 0:
		if reload_t == 0.0:
			reload_t = RELOAD_TIME
			main_node.sfx.play("reload")
			main_node.hud.toast("弹匣空了，换弹……")
		return
	if reload_t > 0.0:
		return
	ammo -= 1
	fire_cd = FIRE_INTERVAL
	_recoil = 1.0
	main_node.sfx.play("gunshot", 1.0, 0.05, 2.0)
	# 射线命中：从屏幕准星（相机中心）发射
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var to := from + dir * RAY_DIST
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	# 天窗模式枪口穿出车顶：排除玩家自身与房车碰撞，否则只会打到车顶
	q.exclude = [self.get_rid(), main_node.rv.get_rid()]
	var hit := space.intersect_ray(q)
	var muzzle_ws := muzzle.global_position
	if hit:
		var col: Object = hit.collider
		if col is RigidBody3D and col.has_method("on_shot"):
			col.on_shot()
			main_node.on_zombie_shot()
	# 枪声惊动周围尸群
	main_node.alert_gunshot(muzzle_ws)
	main_node.spawn_muzzle_flash(muzzle_ws, from + dir * (hit.position.distance_to(from) if hit else RAY_DIST))
	main_node.hud.set_combat_ammo(ammo, int(reload_t > 0.0))

func _finish_reload() -> void:
	if ammo == MAG_SIZE:
		return
	ammo = MAG_SIZE
	main_node.hud.set_combat_ammo(ammo, 0)

func take_damage(amount: float) -> void:
	hp = maxf(0.0, hp - amount)
	main_node.add_trauma(0.35)
	main_node.hud.set_combat_hp(hp)
	if hp <= 0.0:
		main_node.on_player_dead()
