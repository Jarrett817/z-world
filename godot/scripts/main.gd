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
const CREW_ORDER := ["lin_wan", "chen_mo", "ye_lan", "tang_tang", "ivory"]

var rv: CharacterBody3D
var rv_model: Node3D
var cam: Camera3D
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var env: Environment
var hud: CanvasLayer
var terrain: MeshInstance3D
var rain: CPUParticles3D
var headlight: SpotLight3D

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
var terrain_front := 0.0
var trauma := 0.0
var hit_cd := 0.0
var bite_cd := 0.0
var last_z := 0.0
var cam_pos: Vector3
var weather := "clear"
var weather_timer := 45.0
var view_mode := 0   # 0 追尾 / 1 驾驶舱 / 2 车内
var _c_down := false
var survivors_data := {}
var crew_members: Array = []
var crew_figures: Array = []
var crew_font: SystemFont
var _crew_t := 0.0

func _ready() -> void:
	_load_survivors()
	_build_sky()
	_build_terrain()
	_build_rv()
	_build_camera()
	_build_weather()
	_build_hud()
	_spawn_initial_scenery()
	hud.set_weather(weather)
	last_z = rv.global_position.z
	terrain_front = rv.global_position.z + 100.0

func _physics_process(delta: float) -> void:
	_update_time(delta)
	_update_sun()
	if game_over:
		if Input.is_physical_key_pressed(KEY_R):
			get_tree().reload_current_scene()
		return
	_update_resources(delta)
	_update_weather(delta)
	_update_zombies(delta)
	_update_frontier()
	_recycle_world()
	hit_cd = maxf(0.0, hit_cd - delta)
	bite_cd = maxf(0.0, bite_cd - delta)

func _load_survivors() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/survivors.json"))
	if parsed is Dictionary:
		survivors_data = parsed

# ---------- 相机（追尾 / 驾驶舱 / 车内） ----------
func _process(delta: float) -> void:
	if rv == null:
		return
	var pressed := Input.is_physical_key_pressed(KEY_C)
	if pressed and not _c_down:
		view_mode = (view_mode + 1) % 3
	_c_down = pressed
	# 车内视角隐藏整车外壳，避免 GLB 车体从内部遮挡视野
	rv_model.visible = view_mode == 0
	if view_mode == 1:
		cam.global_position = rv.to_global(Vector3(-0.55, 1.2, -1.9))
		cam.look_at(rv.to_global(Vector3(-0.55, 0.9, -30.0)))
		cam.fov = 72.0
	elif view_mode == 2:
		cam.global_position = rv.to_global(Vector3(-0.55, 1.5, -2.6))
		cam.look_at(rv.to_global(Vector3(0.35, 0.85, 2.6)))
		cam.fov = 78.0
		_animate_crew(delta)
	else:
		var target := rv.global_position + Vector3(0, 3.5, 11.0)
		cam_pos = cam_pos.lerp(target, 1.0 - exp(-5.0 * delta))
		cam.global_position = cam_pos
		var shake := trauma * trauma
		cam.global_position += Vector3(
			randf_range(-1, 1) * 0.5 * shake,
			randf_range(-1, 1) * 0.4 * shake,
			0)
		cam.look_at(rv.global_position + Vector3(0, 1.3, -12.0))
		cam.fov = 58.0 + (rv.speed_kmh / MAX_KMH) * 12.0
	trauma = maxf(0.0, trauma - delta * 1.4)

func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)

# ---------- 数值 ----------
func _update_resources(delta: float) -> void:
	var z := rv.global_position.z
	dist_km += (last_z - z) / 1440.0
	last_z = z
	# 燃料（陈默·驾驶：油耗 -25%）
	if rv.speed_kmh > 1.0:
		var burn: float = rv.speed_kmh * delta * 0.0022
		if _has_passive("chen_mo"):
			burn *= 0.75
		fuel = maxf(0.0, fuel - burn)
	rv.engine_dead = fuel <= 0.0
	# 队友修车（林晚·急救：额外 +0.35/s）
	if rv.speed_kmh > 5.0 and durability < 100.0:
		var repair := crew * 0.12
		if _has_passive("lin_wan"):
			repair += 0.35
		durability = minf(100.0, durability + repair * delta)
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
	sky_mat.sky_top_color = Color(0.2, 0.27, 0.35)
	sky_mat.sky_horizon_color = Color(0.44, 0.47, 0.5)
	sky_mat.ground_bottom_color = Color(0.1, 0.09, 0.085)
	sky_mat.ground_horizon_color = Color(0.3, 0.29, 0.27)
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
	env.fog_light_color = Color(0.52, 0.55, 0.58)
	env.fog_density = 0.0036
	env.fog_sky_affect = 0.35
	env.glow_enabled = true
	env.glow_intensity = 0.4
	self.env = env
	get_viewport().world_3d.environment = env
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 1.35
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
		sun.light_color = Color(0.5, 0.58, 0.8)
		sky_mat.sky_top_color = Color(0.04, 0.05, 0.1)
		sky_mat.sky_horizon_color = Color(0.1, 0.11, 0.16)
	else:
		var p := clampf(1.0 - absf(deg + 60.0) / 70.0, 0.0, 1.0)
		sun.light_energy = 0.25 + p * 1.2
		sun.light_color = Color(1.0, 0.95, 0.88).lerp(Color(1.0, 0.55, 0.32), 1.0 - p)
		sky_mat.sky_top_color = Color(0.2, 0.27, 0.35).lerp(Color(0.4, 0.26, 0.21), 1.0 - p)
		sky_mat.sky_horizon_color = Color(0.44, 0.47, 0.5).lerp(Color(0.85, 0.46, 0.28), 1.0 - p)
	# 天气调制：雾=白茫茫能见度低，雨=阴沉
	match weather:
		"fog":
			sky_mat.sky_top_color = sky_mat.sky_top_color.lerp(Color(0.5, 0.52, 0.53), 0.55)
			sky_mat.sky_horizon_color = sky_mat.sky_horizon_color.lerp(Color(0.66, 0.67, 0.67), 0.65)
			env.fog_density = 0.013
			env.fog_light_color = Color(0.62, 0.63, 0.63)
			sun.light_energy *= 0.65
		"rain":
			sky_mat.sky_top_color = sky_mat.sky_top_color.lerp(Color(0.13, 0.16, 0.2), 0.6)
			sky_mat.sky_horizon_color = sky_mat.sky_horizon_color.lerp(Color(0.3, 0.33, 0.36), 0.6)
			env.fog_density = 0.006
			env.fog_light_color = Color(0.4, 0.43, 0.46)
			sun.light_energy *= 0.55
		_:
			env.fog_density = 0.0036
			env.fog_light_color = Color(0.52, 0.55, 0.58)
	# 夜间/雾天自动开灯
	var dark := deg > -15.0 or deg < -165.0
	headlight.light_energy = 11.0 if dark or weather == "fog" else (2.6 if weather == "rain" else 0.0)
	if dark:
		# 夜色：雾色压暗，改用月光色环境光保证剪影可辨
		env.fog_light_color = Color(0.07, 0.09, 0.13)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.22, 0.27, 0.38)
		env.ambient_light_energy = 1.6
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 1.0

# ---------- 地形（无限重建） ----------
func _build_terrain() -> void:
	terrain = MeshInstance3D.new()
	terrain.set_script(TERRAIN_SCRIPT)
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.rebuild(100.0)

func _recycle_world() -> void:
	var rvz := rv.global_position.z
	# 地形重建（前方余量不足时，从车后 100m 起向前铺 380m）
	# 覆盖区间 [terrain_front-SPAN, terrain_front]，可视前沿接近覆盖末端时才重建
	if rvz - VIEW_AHEAD < terrain_front - terrain.SPAN + 60.0:
		terrain_front = rvz + 100.0
		terrain.rebuild(terrain_front)
	# 路肩景物回收
	for p in props:
		if not is_instance_valid(p):
			continue
		if p.global_position.z > rvz + 30.0:
			var nz: float = p.global_position.z - 700.0
			if p.has_meta("on_road"):
				p.global_position = Vector3(road_x(nz) + randf_range(-5.5, 5.5), ground_y(nz) + 0.012, nz)
			else:
				var side := 1.0 if randf() > 0.5 else -1.0
				p.global_position = Vector3(
					road_x(nz) + side * (ROAD_HALF + 3.0 + randf() * 26.0),
					ground_y(nz) + float(p.get_meta("y_off", 0.0)),
					nz)
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
	rv_model = RV_SCENE.instantiate()
	rv_model.rotation.y = PI   # GLB 车头朝 +Z，翻转对齐行进方向 -Z
	rv.add_child(rv_model)
	rv.position = Vector3(0, GROUND_Y + RV_MODEL_FOOT, 0)
	headlight = SpotLight3D.new()
	headlight.light_color = Color(1.0, 0.93, 0.78)
	headlight.light_energy = 0.0
	headlight.spot_range = 90.0
	headlight.spot_angle = 46.0
	headlight.spot_attenuation = 0.9
	headlight.position = Vector3(0, 2.1, -4.4)
	headlight.rotation_degrees = Vector3(-11, 0, 0)
	rv.add_child(headlight)
	_build_interior()
	_build_crew()
	add_child(rv)

## 驾驶舱 + 生活舱共用的程序化内饰
func _build_interior() -> void:
	var shell := _mat(Color(0.18, 0.17, 0.15))
	var pad := _mat(Color(0.26, 0.22, 0.19))
	var seat := _mat(Color(0.32, 0.25, 0.2))
	var wood := _mat(Color(0.4, 0.3, 0.2))
	var steel := _mat(Color(0.33, 0.34, 0.36))
	# 地板 / 顶棚 / 后墙
	_interior_box(Vector3(2.7, 0.1, 7.4), Vector3(0, -0.45, -0.75), shell)
	_interior_box(Vector3(2.7, 0.1, 7.4), Vector3(0, 2.2, -0.75), shell)
	_interior_box(Vector3(2.62, 2.6, 0.1), Vector3(0, 0.95, 2.82), shell)
	# 侧窗台（腰线以下）与 A 柱，保留侧窗视野
	for sx in [-1.3, 1.3]:
		_interior_box(Vector3(0.08, 1.1, 7.3), Vector3(sx, 0.3, -0.75), shell)
		_interior_box(Vector3(0.12, 2.6, 0.14), Vector3(sx, 1.0, -4.15), shell)
	# 驾驶舱：仪表台 / 台面 / 挡风上沿 / 后视镜
	_interior_box(Vector3(2.6, 0.55, 0.7), Vector3(0, 0.28, -3.72), shell)
	_interior_box(Vector3(2.55, 0.06, 0.75), Vector3(0, 0.575, -3.7), pad)
	_interior_box(Vector3(2.6, 0.14, 0.16), Vector3(0, 2.03, -4.2), shell)
	_interior_box(Vector3(0.34, 0.08, 0.09), Vector3(0, 1.94, -4.02), pad)
	for sx in [-0.55, 0.55]:
		_interior_box(Vector3(0.52, 0.14, 0.55), Vector3(sx, 0.05, -1.5), seat)
		_interior_box(Vector3(0.52, 0.66, 0.14), Vector3(sx, 0.38, -1.16), seat)
	# 生活舱：灶台（左）/ 货架（右）/ 餐桌 / 后铺
	_interior_box(Vector3(0.55, 0.85, 2.4), Vector3(-1.0, 0.03, -0.1), shell)
	_interior_box(Vector3(0.6, 0.05, 2.45), Vector3(-1.0, 0.47, -0.1), steel)
	_interior_box(Vector3(0.3, 0.16, 0.3), Vector3(-1.0, 0.57, -0.5), steel)
	_interior_box(Vector3(0.3, 1.3, 1.6), Vector3(1.12, 0.25, 0.4), shell)
	for sy in [-0.05, 0.4, 0.85]:
		_interior_box(Vector3(0.34, 0.05, 1.5), Vector3(1.12, sy, 0.4), wood)
	_interior_box(Vector3(0.7, 0.07, 0.6), Vector3(0.25, 0.32, 1.75), wood)
	for lx in [0.05, 0.45]:
		for lz in [1.53, 1.97]:
			_interior_box(Vector3(0.06, 0.72, 0.06), Vector3(lx, -0.04, lz), shell)
	_interior_box(Vector3(2.3, 0.45, 0.55), Vector3(0, 0.02, 2.5), shell)
	_interior_box(Vector3(2.2, 0.12, 0.5), Vector3(0, 0.3, 2.5), pad)
	# 方向盘：竖直面朝驾驶者，略向后倾
	var wheel := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.18
	tor.outer_radius = 0.245
	wheel.mesh = tor
	wheel.material_override = pad
	wheel.position = Vector3(-0.55, 0.78, -3.2)
	wheel.rotation.x = -PI * 0.5 + 0.28
	rv.add_child(wheel)
	# 仪表遮光罩 + 暖色仪表光条
	_interior_box(Vector3(0.62, 0.16, 0.12), Vector3(-0.55, 0.7, -3.5), shell)
	var gauge := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.34, 0.03, 0.02)
	gauge.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.9, 0.55, 0.2)
	gmat.emission_enabled = true
	gmat.emission = Color(1.0, 0.55, 0.18)
	gmat.emission_energy_multiplier = 1.0
	gauge.material_override = gmat
	gauge.position = Vector3(-0.55, 0.72, -3.43)
	rv.add_child(gauge)
	# 舱内暖色小灯：夜间/雾天也能看清仪表台与舱内
	var cab_light := OmniLight3D.new()
	cab_light.light_color = Color(1.0, 0.82, 0.6)
	cab_light.light_energy = 3.0
	cab_light.omni_range = 8.0
	cab_light.position = Vector3(0, 1.85, 0.4)
	rv.add_child(cab_light)

## 车内视角的队友：各自在灶台/货架/餐桌/后铺忙碌
func _build_crew() -> void:
	crew_font = SystemFont.new()
	crew_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "sans-serif"])
	var stations := [
		[Vector3(-0.55, -0.4, -0.1), PI * 0.5],
		[Vector3(0.55, -0.4, 0.4), -PI * 0.5],
		[Vector3(0.15, -0.4, 2.05), 0.0],
		[Vector3(-0.85, -0.4, 2.05), -PI * 0.5],
	]
	for i in stations.size():
		var fig := _make_crew_figure(i)
		fig.position = stations[i][0]
		fig.rotation.y = stations[i][1]
		rv.add_child(fig)
		crew_figures.append(fig)
	_sync_crew()

func _make_crew_figure(idx: int) -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	root.add_child(body)
	var skin := _mat(Color(0.82, 0.68, 0.55))
	var pants := _mat(Color(0.17, 0.18, 0.2))
	var hair := _mat(Color(0.12, 0.1, 0.09))
	var jackets := [Color(0.38, 0.3, 0.22), Color(0.28, 0.32, 0.34), Color(0.35, 0.24, 0.24), Color(0.25, 0.28, 0.22)]
	var jacket := _mat(jackets[idx % jackets.size()])
	for sx in [-0.11, 0.11]:
		_crew_box(body, Vector3(0.17, 0.86, 0.2), Vector3(sx, 0.43, 0), pants)
	_crew_box(body, Vector3(0.5, 0.62, 0.28), Vector3(0, 1.2, 0), jacket)
	var arms := []
	for sx in [-0.31, 0.31]:
		var pivot := Node3D.new()
		pivot.position = Vector3(sx, 1.44, 0)
		body.add_child(pivot)
		_crew_box(pivot, Vector3(0.13, 0.56, 0.15), Vector3(0, -0.28, 0), jacket)
		arms.append(pivot)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.155
	sph.height = 0.34
	head.mesh = sph
	head.material_override = skin
	head.position.y = 1.66
	body.add_child(head)
	var cap := MeshInstance3D.new()
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 0.165
	cap_mesh.height = 0.3
	cap_mesh.is_hemisphere = true
	cap.mesh = cap_mesh
	cap.material_override = hair
	cap.position = Vector3(0, 1.72, 0.01)
	body.add_child(cap)
	# 头顶名牌：名字 · 专长
	var lb := Label3D.new()
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.font = crew_font
	lb.font_size = 30
	lb.pixel_size = 0.0025
	lb.outline_size = 8
	lb.modulate = Color(1.0, 0.86, 0.66)
	lb.position = Vector3(0, 2.2, 0)
	root.add_child(lb)
	root.set_meta("body", body)
	root.set_meta("arms", arms)
	root.set_meta("label", lb)
	return root

func _sync_crew() -> void:
	for i in crew_figures.size():
		var f: Node3D = crew_figures[i]
		f.visible = i < crew_members.size()
		if f.visible:
			var m: Dictionary = crew_members[i]
			(f.get_meta("label") as Label3D).text = "%s · %s" % [m.get("name", ""), m.get("skill", "")]

func _animate_crew(delta: float) -> void:
	_crew_t += delta
	for i in crew_figures.size():
		var f: Node3D = crew_figures[i]
		if not f.visible:
			continue
		var body: Node3D = f.get_meta("body")
		body.position.y = absf(sin(_crew_t * 2.6 + i * 1.3)) * 0.02
		body.rotation.z = sin(_crew_t * 1.7 + i) * 0.03
		var arms: Array = f.get_meta("arms")
		arms[0].rotation.x = sin(_crew_t * 3.2 + i) * 0.6 - 0.3
		arms[1].rotation.x = sin(_crew_t * 3.2 + i + 2.1) * 0.6 - 0.3

func _crew_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)

func _interior_box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	rv.add_child(mi)

func _build_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.1
	cam.far = 900.0
	cam_pos = Vector3(0, 4.4, 14.5)
	cam.position = cam_pos
	add_child(cam)
	cam.make_current()

# ---------- 天气 ----------
func _build_weather() -> void:
	rain = CPUParticles3D.new()
	rain.amount = 700
	rain.lifetime = 1.3
	rain.preprocess = 0.4
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(34, 4, 46)
	rain.direction = Vector3(0.18, -1, 0)
	rain.spread = 5.0
	rain.gravity = Vector3(0, -26, 0)
	rain.initial_velocity_min = 24.0
	rain.initial_velocity_max = 32.0
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.5)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.62, 0.68, 0.75, 0.55)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = m
	rain.mesh = q
	rain.emitting = false
	rain.visible = false
	add_child(rain)

func _update_weather(delta: float) -> void:
	rain.global_position = rv.global_position + Vector3(0, 9.0, -14.0)
	weather_timer -= delta
	if weather_timer > 0.0:
		return
	weather_timer = randf_range(50.0, 90.0)
	var roll := randf()
	weather = "rain" if roll < 0.32 else ("fog" if roll < 0.55 else "clear")
	rain.emitting = weather == "rain"
	rain.visible = weather == "rain"
	match weather:
		"rain": hud.toast("下起了冷雨，路面湿滑")
		"fog": hud.toast("浓雾弥漫，能见度骤降")
		_: hud.toast("云开了，路况转好")
	hud.set_weather(weather)

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
		zombie_timer = clampf(2.6 - difficulty * 0.8, 0.8, 2.6)
		_spawn_zombie()
	zombies = zombies.filter(func(z):
		if not is_instance_valid(z):
			return false
		if z.should_free:
			z.queue_free()
			return false
		return true)

func _spawn_zombie() -> void:
	# 成批生成在车前 50-160m，形成远处尸群的视觉压迫
	var rvz := rv.global_position.z
	var count := randi_range(1, 3)
	var base_z := rvz - 50.0 - randf() * 110.0
	for i in count:
		var body := RigidBody3D.new()
		body.set_script(ZOMBIE_SCRIPT)
		body.name = "Zombie"
		var zz := base_z - i * randf_range(2.5, 7.0)
		var lane := (randf() - 0.5) * 13.0
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
	# 全局冷却：同一时刻只允许一只丧尸生效，避免多只叠加秒杀
	if game_over or bite_cd > 0.0:
		return
	bite_cd = 1.2
	var bite := 1.0 + minf(dist_km / 2.0, 3.0)
	if _has_passive("tang_tang"):
		bite *= 0.6
	durability = maxf(0.0, durability - bite)
	add_trauma(0.12)
	hud.update_stats(self)

# ---------- 前方内容生成 ----------
func _update_frontier() -> void:
	var rvz := rv.global_position.z
	while obs_z > rvz - VIEW_AHEAD:
		_spawn_obstacle(obs_z)
		obs_z -= randf_range(32.0, 68.0)
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
	var hx := 1.0
	if roll < 0.35:
		scene = WCAR_SCENE
		half = Vector3(2.8, 1.75, 4.05)
		center = Vector3(0, 1.43, 0)
		hx = 2.8
	elif roll < 0.6:
		scene = BARRIERS_SCENE
		half = Vector3(3.0, 1.2, 1.8)
		center = Vector3(0, 1.1, 0)
		hx = 3.0
	elif roll < 0.8:
		scene = WTRUCK_SCENE
		scale_f = 0.28
		half = Vector3(3.3, 2.0, 5.0)
		center = Vector3(0, 1.6, 0)
		hard = true
		hx = 3.3
	else:
		scene = BARRICADE_SCENE
		scale_f = 0.55
		half = Vector3(5.7, 0.95, 0.35)
		center = Vector3(0, 0.95, 0)
		hard = true
		hx = 5.7
	# 只占单侧车道，且保证另一侧至少留 4.8 宽通道（房车宽 3.8）
	var side := 1.0 if randf() > 0.5 else -1.0
	var x_off := side * (hx - 2.2 + randf() * 2.2)
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
	body.position = Vector3(road_x(z) + x_off, ground_y(z), z)
	body.rotation.y = randf_range(-0.25, 0.25) if not hard else 0.0
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
func on_obstacle_hit(hard: bool, speed_kmh: float, obstacle: Node3D = null) -> void:
	# 低速贴靠不计伤害，避免卡在障碍旁被反复结算
	if hit_cd > 0.0 or speed_kmh < 12.0:
		return
	hit_cd = 0.8 if hard else 0.45
	if hard:
		durability = maxf(0.0, durability - (8.0 + speed_kmh * 0.06))
		rv.speed_kmh *= 0.2
		add_trauma(0.8)
		hud.toast("撞上硬障碍！车况受损")
		# 硬障碍不消失，但把车横向推开一点，避免卡死
		if obstacle != null:
			var side := signf(rv.global_position.x - obstacle.global_position.x)
			rv.global_position.x += side * 1.2
	else:
		durability = maxf(0.0, durability - (3.0 + speed_kmh * 0.03))
		rv.speed_kmh *= 0.6
		add_trauma(0.4)
		hud.toast("撞飞路障")
		if obstacle != null:
			obstacle.queue_free()
	hud.update_stats(self)

func on_zombie_run_over() -> void:
	if hit_cd > 0.0 or rv.speed_kmh < 10.0:
		return
	hit_cd = 0.25
	var dmg := 1.2 if _has_passive("tang_tang") else 2.0
	durability = maxf(0.0, durability - dmg)
	add_trauma(0.25)

func on_pickup(kind: String) -> void:
	if game_over:
		return
	var mult := 1.5 if _has_passive("ye_lan") else 1.0
	match kind:
		"fuel":
			var g := 25.0 * mult
			fuel = minf(100.0, fuel + g)
			hud.toast("+%d 燃料" % int(g))
		"food":
			var g := 8.0 * mult
			food += g
			hud.toast("+%d 食物" % int(g))
		"repair":
			var g := 15.0 * mult
			durability = minf(100.0, durability + g)
			hud.toast("+%d 车况" % int(g))
	hud.update_stats(self)

func try_recruit(survivor: Node3D) -> void:
	if game_over or not is_instance_valid(survivor):
		return
	# 苏薇·谈判：招募食物消耗 3 → 2
	var cost := 2.0 if _has_passive("ivory") else 3.0
	if food < cost:
		hud.toast("食物不足，无法招募幸存者")
		return
	food -= cost
	crew += 1
	survivor.queue_free()
	var member := _next_crew_member()
	if not member.is_empty():
		crew_members.append(member)
		hud.set_crew(crew_members)
		hud.toast("%s（%s）加入队伍 · 分食 -%d" % [member.get("name", ""), member.get("skill", ""), int(cost)])
	else:
		hud.toast("幸存者上车！队伍 %d 人（分食 -%d）" % [crew, int(cost)])
	_sync_crew()
	hud.update_stats(self)

## 队友专长是否已在车上
func _has_passive(id: String) -> bool:
	for m in crew_members:
		if m.get("id", "") == id:
			return true
	return false

func _next_crew_member() -> Dictionary:
	for id in CREW_ORDER:
		var d: Dictionary = survivors_data.get(id, {})
		if d.is_empty():
			continue
		var taken := false
		for m in crew_members:
			if m.get("id", "") == id:
				taken = true
				break
		if not taken:
			return d
	return {}

# ---------- 初始景物 ----------
func _spawn_initial_scenery() -> void:
	for i in range(80):
		var zz := -650.0 + randf() * 710.0
		props.append(_make_scenery(zz))
	# 路面裂缝污渍
	for i in range(26):
		var zz := -650.0 + randf() * 710.0
		var q := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(randf_range(1.8, 5.0), randf_range(3.0, 9.0))
		q.mesh = pm
		q.rotation.x = -PI * 0.5
		q.position = Vector3(road_x(zz) + randf_range(-5.5, 5.5), ground_y(zz) + 0.012, zz)
		q.material_override = _mat(Color(0.06, 0.055, 0.05))
		q.set_meta("on_road", true)
		add_child(q)
		props.append(q)
	# 路肩碎石与杂草
	for i in range(50):
		var zz := -650.0 + randf() * 710.0
		var side := 1.0 if randf() > 0.5 else -1.0
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(0.25, 0.9), randf_range(0.12, 0.45), randf_range(0.25, 0.9))
		mi.mesh = bm
		mi.rotation.y = randf() * TAU
		mi.position = Vector3(
			road_x(zz) + side * randf_range(ROAD_HALF + 0.4, ROAD_HALF + 10.0),
			ground_y(zz) + bm.size.y * 0.4,
			zz)
		mi.material_override = _mat(Color(0.24, 0.22, 0.18))
		mi.set_meta("y_off", bm.size.y * 0.4)
		add_child(mi)
		props.append(mi)

func _make_scenery(z: float) -> Node3D:
	var root := Node3D.new()
	var side := 1.0 if randf() > 0.5 else -1.0
	root.position = Vector3(
		road_x(z) + side * (ROAD_HALF + 3.0 + randf() * 26.0),
		ground_y(z),
		z)
	var roll := randf()
	if roll < 0.4:
		# 枯树：树干 + 歪斜枯枝
		var trunk := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.1
		tm.bottom_radius = 0.3
		tm.height = randf_range(3.5, 6.5)
		trunk.mesh = tm
		trunk.position.y = tm.height * 0.5
		trunk.material_override = _mat(Color(0.16, 0.13, 0.1))
		root.add_child(trunk)
		for k in randi_range(2, 4):
			var br := MeshInstance3D.new()
			var bm := CylinderMesh.new()
			bm.top_radius = 0.03
			bm.bottom_radius = 0.09
			bm.height = randf_range(1.2, 2.4)
			br.mesh = bm
			br.position.y = tm.height * randf_range(0.55, 0.95)
			br.rotation = Vector3(randf_range(-0.9, 0.9), randf() * TAU, randf_range(-0.9, 0.9))
			br.material_override = _mat(Color(0.14, 0.11, 0.09))
			root.add_child(br)
	elif roll < 0.58:
		# 废弃电线杆
		var pole := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.1
		pm.bottom_radius = 0.16
		pm.height = randf_range(7.0, 9.0)
		pole.mesh = pm
		pole.position.y = pm.height * 0.5
		pole.material_override = _mat(Color(0.25, 0.24, 0.22))
		root.add_child(pole)
		var cross := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(2.6, 0.14, 0.14)
		cross.mesh = cm
		cross.position.y = pm.height * 0.88
		cross.material_override = _mat(Color(0.22, 0.21, 0.19))
		root.add_child(cross)
	elif roll < 0.72:
		# 远处废墟楼剪影
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(5.0, 10.0), randf_range(6.0, 14.0), randf_range(5.0, 10.0))
		b.mesh = bm
		b.position.y = bm.size.y * 0.5
		b.material_override = _mat(Color(0.19, 0.2, 0.22))
		root.add_child(b)
		root.position.x = road_x(z) + side * randf_range(45.0, 90.0)
	elif roll < 0.9:
		# 混凝土残块
		var c := MeshInstance3D.new()
		var cm2 := BoxMesh.new()
		cm2.size = Vector3(randf_range(1.2, 3.0), randf_range(0.4, 1.2), randf_range(1.2, 3.0))
		c.mesh = cm2
		c.position = Vector3(randf_range(-1, 1), cm2.size.y * 0.5, randf_range(-1, 1))
		c.rotation.y = randf() * TAU
		c.material_override = _mat(Color(0.3, 0.29, 0.27))
		root.add_child(c)
	else:
		# 锈蚀油桶
		var d := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = 0.32
		dm.bottom_radius = 0.32
		dm.height = 0.9
		d.mesh = dm
		d.position.y = 0.45
		d.material_override = _mat(Color(0.42, 0.25, 0.12))
		root.add_child(d)
	add_child(root)
	return root

func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	return m

# ---------- 地形函数（全场景共享） ----------
func road_x(z: float) -> float:
	return sin(z * 0.035) * 3.5 + sin(z * 0.1 + 1.5) * 1.6

func ground_y(z: float) -> float:
	return GROUND_Y + sin(z * 0.06) * 0.08 + sin(z * 0.13 + 2.1) * 0.05 + sin(z * 0.031 + 5.0) * 0.04
