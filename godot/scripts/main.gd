extends Node3D
## 末世：我要当救世主 —— Godot 版主场景（全代码构建，零编辑器依赖）
## 线性驾驶生存：无限公路、丧尸围攻、障碍撞击、物资收集、幸存者招募、昼夜循环。

const RV_SCENE := preload("res://assets/rv/gs_001.glb")
const ZMB_SCENE := preload("res://assets/props/zmb_stand.glb")
const WCAR_SCENE := preload("res://assets/props/wcar.glb")
const WTRUCK_SCENE := preload("res://assets/props/wtruck.glb")
const BARRIERS_SCENE := preload("res://assets/props/barriers.glb")
const BARRICADE_SCENE := preload("res://assets/props/barricade.glb")
const RV_SCRIPT := preload("res://scripts/rv.gd")
const TERRAIN_SCRIPT := preload("res://scripts/terrain.gd")
const ZOMBIE_SCRIPT := preload("res://scripts/zombie.gd")
const HUD_SCRIPT := preload("res://scripts/hud.gd")
const PICKUP_SCRIPT := preload("res://scripts/pickup.gd")
const SURVIVOR_SCRIPT := preload("res://scripts/survivor.gd")

const GROUND_Y := -1.56
const ROAD_HALF := 7.0
const MAX_KMH := 140.0
const VIEW_AHEAD := 260.0
const VIEW_BEHIND := 40.0
const RV_MODEL_FOOT := 1.557   # GLB 轮底到模型原点的距离

var rv: CharacterBody3D
var cam: Camera3D
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var hud: CanvasLayer
var terrain: MeshInstance3D

# ---- 游戏状态 ----
var durability := 100.0
var fuel := 60.0
var food := 10.0
var crew := 0
var dist_km := 0.0
var day := 1
var hour := 9.0
var game_over := false

var zombies: Array = []
var props: Array = []
var zombie_timer := 2.0
var obs_z := -30.0
var pick_z := -20.0
var surv_z := -180.0
var terrain_rear := 0.0
var trauma := 0.0
var hit_cd := 0.0
var last_z := 0.0
var cam_pos: Vector3

func _ready() -> void:
	_build_sky()
	_build_terrain()
	_build_rv()
	_build_camera()
	_build_hud()
	_spawn_initial_scenery()
	last_z = rv.global_position.z
	terrain_rear = rv.global_position.z - 100.0

func _physics_process(delta: float) -> void:
	_update_time(delta)
	_update_sun()
	if game_over:
		if Input.is_physical_key_pressed(KEY_R):
			get_tree().reload_current_scene()
		return
	_update_resources(delta)
	_update_zombies(delta)
	_update_frontier()
	_recycle_world()
	hit_cd = maxf(0.0, hit_cd - delta)

# ---------- 相机（追尾 + 震屏） ----------
func _process(delta: float) -> void:
	if rv == null:
		return
	var target := rv.global_position + Vector3(0, 4.4, 14.5)
	cam_pos = cam_pos.lerp(target, 1.0 - exp(-5.0 * delta))
	cam.global_position = cam_pos
	var shake := trauma * trauma
	cam.global_position += Vector3(
		randf_range(-1, 1) * 0.5 * shake,
		randf_range(-1, 1) * 0.4 * shake,
		0)
	cam.look_at(rv.global_position + Vector3(0, 1.6, -10.0))
	cam.fov = 55.0 + (rv.speed_kmh / MAX_KMH) * 14.0
	trauma = maxf(0.0, trauma - delta * 1.4)

func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)

# ---------- 数值 ----------
func _update_resources(delta: float) -> void:
	var z := rv.global_position.z
	dist_km += (last_z - z) / 1440.0
	last_z = z
	# 燃料
	if rv.speed_kmh > 1.0:
		fuel = maxf(0.0, fuel - rv.speed_kmh * delta * 0.018)
	rv.engine_dead = fuel <= 0.0
	# 队友修车
	if rv.speed_kmh > 5.0 and durability < 100.0:
		durability = minf(100.0, durability + crew * 0.12 * delta)
	hud.update_stats(self)
	if durability <= 0.0:
		_do_game_over()

func _do_game_over() -> void:
	game_over = true
	rv.engine_dead = true
	trauma = 1.0
	hud.show_game_over(self)

# ---------- 昼夜 ----------
func _build_sky() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.78)
	sky_mat.sky_horizon_color = Color(0.82, 0.72, 0.58)
	sky_mat.ground_bottom_color = Color(0.24, 0.22, 0.18)
	sky_mat.ground_horizon_color = Color(0.72, 0.62, 0.48)
	sky_mat.sun_angle_max = 40.0
	sky_mat.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.68, 0.58)
	env.fog_density = 0.003
	env.fog_sky_affect = 0.4
	env.glow_enabled = true
	env.glow_intensity = 0.4
	get_viewport().world_3d.environment = env
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.92, 0.82)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	sun.rotation_degrees = Vector3(-42, 24, 0)
	add_child(sun)

func _update_time(delta: float) -> void:
	hour += delta * 0.05
	if hour >= 24.0:
		hour -= 24.0
		day += 1

func _update_sun() -> void:
	var deg := -100.0 + (hour / 24.0) * 160.0
	sun.rotation_degrees = Vector3(deg, 24, 0)
	if deg > -15.0 or deg < -165.0:
		sun.light_energy = 0.15
		sun.light_color = Color(0.55, 0.62, 0.85)
		sky_mat.sky_top_color = Color(0.05, 0.06, 0.12)
		sky_mat.sky_horizon_color = Color(0.12, 0.13, 0.2)
	else:
		var p := clampf(1.0 - absf(deg + 60.0) / 70.0, 0.0, 1.0)
		sun.light_energy = 0.2 + p * 1.5
		sun.light_color = Color(1.0, 0.92, 0.82).lerp(Color(1.0, 0.5, 0.28), 1.0 - p)
		sky_mat.sky_top_color = Color(0.35, 0.55, 0.78).lerp(Color(0.55, 0.35, 0.25), 1.0 - p)
		sky_mat.sky_horizon_color = Color(0.82, 0.72, 0.58).lerp(Color(1.0, 0.55, 0.32), 1.0 - p)

# ---------- 地形（无限重建） ----------
func _build_terrain() -> void:
	terrain = MeshInstance3D.new()
	terrain.set_script(TERRAIN_SCRIPT)
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.rebuild(-100.0)

func _recycle_world() -> void:
	var rvz := rv.global_position.z
	# 地形重建（后方余量不足时）
	if rvz - VIEW_BEHIND < terrain_rear:
		terrain_rear = rvz - 100.0
		terrain.rebuild(terrain_rear)
	# 路肩景物回收
	for p in props:
		if not is_instance_valid(p):
			continue
		if p.global_position.z > rvz + 30.0:
			p.global_position.z -= 330.0
			var side := 1.0 if randf() > 0.5 else -1.0
			p.global_position.x = road_x(p.global_position.z) + side * (ROAD_HALF + 1.5 + randf() * 20.0)
	props = props.filter(func(p): return is_instance_valid(p))

# ---------- 房车 ----------
func _build_rv() -> void:
	rv = CharacterBody3D.new()
	rv.name = "RV"
	rv.set_script(RV_SCRIPT)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.8, 3.9, 10.0)
	col.shape = box
	col.position = Vector3(0, 0.4, 0)
	rv.add_child(col)
	var model := RV_SCENE.instantiate()
	rv.add_child(model)
	rv.position = Vector3(0, GROUND_Y + RV_MODEL_FOOT, 0)
	add_child(rv)

func _build_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.1
	cam.far = 600.0
	cam_pos = Vector3(0, 4.4, 14.5)
	cam.position = cam_pos
	add_child(cam)
	cam.make_current()

# ---------- HUD ----------
func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.set_script(HUD_SCRIPT)
	hud.name = "HUD"
	add_child(hud)
	hud.build(rv)

# ---------- 丧尸 ----------
func _update_zombies(delta: float) -> void:
	zombie_timer -= delta
	if zombie_timer <= 0.0 and zombies.size() < 22:
		var difficulty: float = clampf(dist_km * 0.8 + (rv.speed_kmh / MAX_KMH) * 1.5, 0.0, 2.8)
		zombie_timer = clampf(4.0 - difficulty, 1.2, 4.0)
		_spawn_zombie()
	zombies = zombies.filter(func(z): return is_instance_valid(z) and not z.should_free)

func _spawn_zombie() -> void:
	var body := RigidBody3D.new()
	body.set_script(ZOMBIE_SCRIPT)
	body.name = "Zombie"
	var rvz := rv.global_position.z
	var zz := rvz - 30.0 - randf() * 50.0
	var lane := (randf() - 0.5) * 8.0
	body.position = Vector3(road_x(zz) + lane, GROUND_Y + 0.5, zz)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.4
	col.shape = cap
	col.position.y = 0.7
	body.add_child(col)
	var model := ZMB_SCENE.instantiate()
	model.scale = Vector3.ONE * 0.065
	body.add_child(model)
	add_child(body)
	body.setup(self)
	zombies.append(body)

func zombie_bite() -> void:
	if game_over:
		return
	var bite := 1.0 + minf(dist_km / 2.0, 3.0)
	durability = maxf(0.0, durability - bite)
	hud.update_stats(self)

# ---------- 前方内容生成 ----------
func _update_frontier() -> void:
	var rvz := rv.global_position.z
	while obs_z > rvz - VIEW_AHEAD:
		_spawn_obstacle(obs_z)
		obs_z -= randf_range(18.0, 40.0)
	while pick_z > rvz - VIEW_AHEAD:
		_spawn_pickup(pick_z)
		pick_z -= randf_range(30.0, 70.0)
	while surv_z > rvz - VIEW_AHEAD:
		_spawn_survivor(surv_z)
		surv_z -= randf_range(250.0, 450.0)
	# 清理身后
	for s in get_children():
		if s.is_in_group("consumable") and s.global_position.z > rvz + 40.0:
			s.queue_free()

func _spawn_obstacle(z: float) -> void:
	var roll := randf()
	var scene: PackedScene
	var scale_f := 1.0
	var half := Vector3.ONE
	var center := Vector3.ZERO
	var hard := false
	var x_off := 0.0
	if roll < 0.35:
		scene = WCAR_SCENE
		half = Vector3(2.8, 1.75, 4.05)
		center = Vector3(0, 1.43, 0)
		x_off = randf_range(-4.5, 4.5)
	elif roll < 0.6:
		scene = BARRIERS_SCENE
		half = Vector3(3.0, 1.2, 1.8)
		center = Vector3(0, 1.1, 0)
		x_off = randf_range(-4.0, 4.0)
	elif roll < 0.8:
		scene = WTRUCK_SCENE
		scale_f = 0.28
		half = Vector3(3.3, 2.0, 5.0)
		center = Vector3(0, 1.6, 0)
		hard = true
		x_off = randf_range(-3.0, 3.0)
	else:
		scene = BARRICADE_SCENE
		scale_f = 0.55
		half = Vector3(5.7, 0.95, 0.35)
		center = Vector3(0, 0.95, 0)
		hard = true
		x_off = randf_range(-2.0, 2.0)
	var body := StaticBody3D.new()
	body.add_to_group("consumable")
	body.add_to_group("obstacle_hard" if hard else "obstacle_soft")
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = half * 2.0
	col.shape = box
	col.position = center
	body.add_child(col)
	var model := scene.instantiate()
	model.scale = Vector3.ONE * scale_f
	body.add_child(model)
	var zz := z
	body.position = Vector3(road_x(zz) + x_off, ground_y(zz), zz)
	body.rotation.y = randf_range(-0.3, 0.3) if not hard else 0.0
	add_child(body)

func _spawn_pickup(z: float) -> void:
	var p := Node3D.new()
	p.set_script(PICKUP_SCRIPT)
	p.add_to_group("consumable")
	p.add_to_group("pickup")
	var roll := randf()
	if roll < 0.45:
		p.kind = "fuel"
	elif roll < 0.8:
		p.kind = "food"
	else:
		p.kind = "repair"
	p.position = Vector3(road_x(z) + randf_range(-4.0, 4.0), ground_y(z), z)
	add_child(p)

func _spawn_survivor(z: float) -> void:
	var s := Node3D.new()
	s.set_script(SURVIVOR_SCRIPT)
	s.add_to_group("consumable")
	s.add_to_group("survivor")
	var side := 1.0 if randf() > 0.5 else -1.0
	s.position = Vector3(road_x(z) + side * randf_range(5.5, 8.0), ground_y(z), z)
	add_child(s)

# ---------- 撞击处理（rv.gd 回调） ----------
func on_obstacle_hit(hard: bool, speed_kmh: float) -> void:
	if hit_cd > 0.0:
		return
	hit_cd = 0.5
	if hard:
		durability = maxf(0.0, durability - (15.0 + speed_kmh * 0.15))
		rv.speed_kmh *= 0.15
		add_trauma(0.8)
		hud.toast("撞上硬障碍！车况大幅受损")
	else:
		durability = maxf(0.0, durability - (6.0 + speed_kmh * 0.08))
		rv.speed_kmh *= 0.55
		add_trauma(0.4)
		hud.toast("撞飞路障")
	hud.update_stats(self)

func on_zombie_run_over() -> void:
	if hit_cd > 0.0:
		return
	hit_cd = 0.25
	durability = maxf(0.0, durability - 2.0)
	add_trauma(0.25)

func on_pickup(kind: String) -> void:
	match kind:
		"fuel":
			fuel = minf(100.0, fuel + 25.0)
			hud.toast("+25 燃料")
		"food":
			food += 8.0
			hud.toast("+8 食物")
		"repair":
			durability = minf(100.0, durability + 15.0)
			hud.toast("+15 车况")
	hud.update_stats(self)

func try_recruit(survivor: Node3D) -> void:
	if food < 3.0:
		hud.toast("食物不足，无法招募幸存者")
		return
	food -= 3.0
	crew += 1
	survivor.queue_free()
	hud.toast("幸存者上车！队伍 %d 人（分食 -3）" % crew)
	hud.update_stats(self)

# ---------- 初始景物 ----------
func _spawn_initial_scenery() -> void:
	for i in range(46):
		var side := 1.0 if randf() > 0.5 else -1.0
		var x := side * (ROAD_HALF + 1.5 + randf() * 20.0)
		var zz := -260.0 + randf() * 300.0
		var mesh: Mesh
		var h := 0.5
		var roll := randf()
		if roll < 0.3:
			var bm := BoxMesh.new()
			bm.size = Vector3(randf_range(1.5, 3.5), randf_range(0.6, 1.8), randf_range(1.5, 3.5))
			mesh = bm
			h = bm.size.y * 0.5
		elif roll < 0.5:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.45
			cm.bottom_radius = 0.45
			cm.height = 1.1
			mesh = cm
			h = 0.55
		elif roll < 0.7:
			var cm2 := CylinderMesh.new()
			cm2.top_radius = 0.08
			cm2.bottom_radius = 0.12
			cm2.height = 4.2
			mesh = cm2
			h = 2.1
		else:
			var bm2 := BoxMesh.new()
			bm2.size = Vector3(randf_range(0.4, 0.8), 0.5, 0.4)
			mesh = bm2
			h = 0.25
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.roughness = 1.0
		mat.albedo_color = Color(0.35 + randf() * 0.2, 0.3 + randf() * 0.15, 0.22 + randf() * 0.12)
		mi.material_override = mat
		mi.position = Vector3(x, ground_y(zz) + h, zz)
		add_child(mi)
		props.append(mi)

# ---------- 地形函数（全场景共享） ----------
func road_x(z: float) -> float:
	return sin(z * 0.035) * 3.5 + sin(z * 0.1 + 1.5) * 1.6

func ground_y(z: float) -> float:
	return GROUND_Y + sin(z * 0.06) * 0.08 + sin(z * 0.13 + 2.1) * 0.05 + sin(z * 0.031 + 5.0) * 0.04
