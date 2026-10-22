extends Node3D
## 末世：我要当救世主 —— Godot 版主场景（全代码构建，零编辑器依赖）
## 线性驾驶生存：无限公路、丧尸围攻、障碍撞击、物资收集、幸存者招募、昼夜循环。

const RV_SCENE := preload("res://assets/rv/gs_001.glb")
const ZMB_SCENE := preload("res://assets/props/zmb_stand.glb")
const ZMB_SCENE_G := preload("res://assets/props/zmb_stand_g.glb")
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
const STORY_SCRIPT := preload("res://scripts/story.gd")
const PLAYER_SCRIPT := preload("res://scripts/player.gd")

const GROUND_Y := -1.56
const KMH_FACTOR := 250.0   # 世界米 → 里程公里（1440 旧值，调快后一局实际驾驶 ~15 分钟走完序章的 680km 目标）
const GOAL_KM := 680.0      # 方舟集结点里程，抵达触发终章
const ROAD_HALF := 7.0
const MAX_KMH := 140.0
const VIEW_AHEAD := 260.0
const VIEW_BEHIND := 40.0
const RV_MODEL_FOOT := 1.557   # GLB 轮底到模型原点的距离
const CREW_ORDER := ["lin_wan", "shen_man", "ye_lan", "tang_tang", "ivory"]

# 场景音乐（六种处境各一首，交叉淡入淡出切换）
const MUSIC_TRACKS := {
	"drive": "res://assets/music/Daylight Drive.mp3",
	"combat": "res://assets/music/Gunfire at Dawn.mp3",
	"camp": "res://assets/music/Embers Tonight.mp3",
	"story": "res://assets/music/The Long Quiet.mp3",
	"danger": "res://assets/music/They Are Coming.mp3",
	"death": "res://assets/music/Last Light Fades.mp3",
}
const MUSIC_VOLUME := -10.0

var rv: CharacterBody3D
var rv_model: Node3D
var interior: Node3D
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
var morale := 70.0
var parts := 3.0
var crew := 0
var story_active := false
var dist_km := 0.0
var day := 1
var hour := 9.0
var game_over := false
var won := false
var dying := false
var story: Node

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
var lamp_mat: StandardMaterial3D
var lamp_z := -30.0
var lamp_side := 1.0
var view_mode := 0   # 0 追尾 / 1 驾驶舱 / 2 车内
var _c_down := false
var combat_active := false
var _g_down := false
var _t_down := false
var parked := false
var _f_down := false
var _e_down := false
var facilities_visible := false
var facilities_data := {}
var facility_levels := {}   # 设施 id → 当前等级（0 起）
var _starving := false
var _low_morale_warned := false
var ark_spawned := false
var survivors_data := {}
var crew_members: Array = []
var crew_figures: Array = []
var crew_font: SystemFont

var music_a: AudioStreamPlayer
var music_b: AudioStreamPlayer
var music_key := ""
var music_tween: Tween
var sfx: Sfx

var banter_t := 9.0
var banter_busy := false

func _ready() -> void:
	_load_survivors()
	_load_facilities()
	_build_sky()
	_build_terrain()
	_build_rv()
	_build_camera()
	_build_weather()
	_build_hud()
	_build_music()
	sfx = Sfx.new()
	add_child(sfx)
	_spawn_initial_scenery()
	hud.set_weather(weather)
	# 车载电台剧情管理器
	story = Node.new()
	story.set_script(STORY_SCRIPT)
	add_child(story)
	story.setup(self)
	hud.story_node = story
	last_z = rv.global_position.z
	terrain_front = rv.global_position.z + 100.0

func _physics_process(delta: float) -> void:
	_update_time(delta)
	_update_sun()
	if game_over:
		if Input.is_physical_key_pressed(KEY_R):
			get_tree().reload_current_scene()
		return
	# 剧情对话框打开：冻结世界逻辑（时间/太阳继续走，车由 rv.gd 自动刹停）
	if story_active:
		return
	_update_resources(delta)
	_update_weather(delta)
	_update_zombies(delta)
	_update_frontier()
	_recycle_world()
	# 终点前 8km 方舟营地进入视野
	if not ark_spawned and dist_km >= GOAL_KM - 8.0:
		ark_spawned = true
		_spawn_ark_camp()
	hit_cd = maxf(0.0, hit_cd - delta)
	bite_cd = maxf(0.0, bite_cd - delta)

func _load_survivors() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/survivors.json"))
	if parsed is Dictionary:
		survivors_data = parsed

func _load_facilities() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/facilities.json"))
	if parsed is Dictionary:
		facilities_data = parsed
		for f in parsed.get("facilities", []):
			facility_levels[f.get("id", "")] = 0

## 储物架等级决定燃料上限
func fuel_cap() -> float:
	for f in facilities_data.get("facilities", []):
		if f.get("id", "") == "storage":
			var caps: Array = f.get("fuel_cap", [100.0])
			return float(caps[facility_levels["storage"]])
	return 100.0

## 设施定义
func _facility(id: String) -> Dictionary:
	for f in facilities_data.get("facilities", []):
		if f.get("id", "") == id:
			return f
	return {}

# ---------- 音乐 ----------
func _build_music() -> void:
	music_a = AudioStreamPlayer.new()
	music_b = AudioStreamPlayer.new()
	music_a.volume_db = -60.0
	music_b.volume_db = -60.0
	add_child(music_a)
	add_child(music_b)

## 双播放器交叉淡入淡出切换场景音乐
func play_music(key: String) -> void:
	if key == music_key or not MUSIC_TRACKS.has(key):
		return
	var stream: AudioStream = load(MUSIC_TRACKS[key])
	if stream == null:
		return
	stream.loop = key != "death"
	music_key = key
	var old_p := music_a if music_a.playing else music_b
	var new_p := music_b if old_p == music_a else music_a
	if music_tween != null and music_tween.is_valid():
		music_tween.kill()
	new_p.stream = stream
	new_p.volume_db = -45.0
	new_p.play()
	music_tween = create_tween()
	music_tween.set_parallel(true)
	music_tween.tween_property(new_p, "volume_db", MUSIC_VOLUME, 1.0)
	music_tween.tween_property(old_p, "volume_db", -60.0, 1.0)
	music_tween.set_parallel(false)
	music_tween.tween_callback(old_p.stop)

## 退出时释放音轨引用，避免根部残留资源
func _exit_tree() -> void:
	music_a.stream = null
	music_b.stream = null

## 优先级：结局 > 剧情 > 战斗 > 丧尸逼近 > 驻车 > 行驶
func _update_music() -> void:
	if game_over:
		play_music("story" if won else "death")
		return
	if story_active:
		play_music("story")
		return
	if combat_active:
		play_music("combat")
		return
	if _zombies_hunting():
		play_music("danger")
		return
	play_music("camp" if parked else "drive")

## 附近是否有丧尸进入冲锋状态
func _zombies_hunting() -> bool:
	for z in zombies:
		if is_instance_valid(z) and z.is_hunting():
			if z.global_position.distance_to(rv.global_position) < 55.0:
				return true
	return false

# ---------- 相机（追尾 / 驾驶舱 / 车内） ----------
func _process(delta: float) -> void:
	if rv == null:
		return
	_update_music()
	sfx.set_engine(clampf(rv.speed_kmh / 55.0, 0.0, 1.0))
	# G：驻车时下车战斗 / 战斗中回到驾驶座（player.gd 内部也处理结束）
	var gk := Input.is_physical_key_pressed(KEY_G)
	if gk and not _g_down and not game_over and not story_active:
		if combat_active:
			end_combat()
		elif parked:
			start_combat(0)
	_g_down = gk
	# T：天窗射击（行驶中也可探身开火，身体固定车顶）
	var tk := Input.is_physical_key_pressed(KEY_T)
	if tk and not _t_down and not game_over and not story_active:
		if combat_active:
			end_combat()
		else:
			start_combat(1)
	_t_down = tk
	if combat_active:
		_sync_player_to_rv(delta)
		trauma = maxf(0.0, trauma - delta * 1.4)
		return
	var pressed := Input.is_physical_key_pressed(KEY_C)
	if pressed and not _c_down:
		view_mode = (view_mode + 1) % 3
	_c_down = pressed
	# 驻车休整（F 开关）
	var f := Input.is_physical_key_pressed(KEY_F)
	if f and not _f_down and not game_over:
		_toggle_park()
	_f_down = f
	# 驻车时 E 开关房车设施面板
	var e := Input.is_physical_key_pressed(KEY_E)
	if e and not _e_down and parked and not game_over:
		set_facilities_ui(not facilities_visible)
	_e_down = e
	# 追尾视角只看 GLB 车壳；车内/驾驶舱视角隐藏车壳、显示程序化内饰与队友
	rv_model.visible = view_mode == 0
	interior.visible = view_mode != 0
	for i in crew_figures.size():
		crew_figures[i].visible = view_mode == 2 and i < crew_members.size()
	_update_banter(delta)
	if view_mode == 1:
		cam.global_position = rv.to_global(Vector3(-0.55, 1.2, -1.9))
		cam.look_at(rv.to_global(Vector3(-0.55, 0.9, -30.0)))
		cam.fov = 72.0
	elif view_mode == 2:
		# 后铺上方俯拍：餐桌当前景，灶台/货架队友为中景，副驾在车头；后移+抬视线+宽 fov 保证后舱两人完整入镜
		cam.global_position = rv.to_global(Vector3(0.0, 1.66, 2.6))
		cam.look_at(rv.to_global(Vector3(0.0, 1.12, -1.0)))
		cam.fov = 72.0
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

## 驻车休整：全员检修，消耗食物，时间快进；再按 F 出发
func _toggle_park() -> void:
	if not parked:
		if rv.speed_kmh > 6.0:
			hud.toast("车速降到 6 km/h 以下才能驻车")
			return
		parked = true
		rv.parked = true
		rv.speed_kmh = 0.0
		view_mode = 2
		_starving = false
		hud.set_drive_buttons_visible(false)
		set_facilities_ui(true)
		hud.toast("驻车休整 · E 设施操作，F 出发")
	else:
		parked = false
		rv.parked = false
		view_mode = 0
		hud.set_drive_buttons_visible(true)
		set_facilities_ui(false)
		hud.toast("出发")

## 设施面板开关（剧情对话时强制隐藏，避免遮挡与误点）
func set_facilities_ui(v: bool) -> void:
	facilities_visible = v and parked and not story_active
	hud.set_facilities_visible(facilities_visible)

## 推进若干小时（与驻车同倍率无关：直接结算干活花掉的时间）
func _advance_hours(h: float) -> void:
	hour += h
	while hour >= 24.0:
		hour -= 24.0
		day += 1

## HUD：执行设施主动动作（做饭 / 深度检修）
func facility_action(id: String) -> void:
	if not parked or game_over:
		return
	var f := _facility(id)
	var act: Dictionary = f.get("action", {})
	if act.is_empty():
		return
	var lv := int(facility_levels.get(id, 0))
	var need_food := float(act.get("food", 0))
	var need_parts := float(act.get("parts", 0))
	if food < need_food:
		hud.toast("食物不足")
		return
	if parts < need_parts:
		hud.toast("零件不足")
		return
	food -= need_food
	parts -= need_parts
	_advance_hours(float(act.get("hours", 0)))
	if act.has("fx_morale"):
		var gains: Array = act["fx_morale"]
		morale = minf(100.0, morale + float(gains[lv]))
		hud.toast("热饭下肚，士气 +%d" % int(gains[lv]))
	if act.has("fx_dur"):
		var reps: Array = act["fx_dur"]
		durability = minf(100.0, durability + float(reps[lv]))
		hud.toast("深度检修完成，车况 +%d" % int(reps[lv]))
	hud.update_stats(self)
	hud.refresh_facilities()

## HUD：升级设施（消耗零件）
func facility_upgrade(id: String) -> void:
	if not parked or game_over:
		return
	var f := _facility(id)
	var up: Dictionary = f.get("upgrade", {})
	if up.is_empty():
		return
	var lv := int(facility_levels.get(id, 0))
	if lv >= int(f.get("max_level", 1)) - 1:
		return
	var costs: Array = up.get("parts", [])
	var cost := float(costs[lv])
	if parts < cost:
		hud.toast("零件不足（需要 %d）" % int(cost))
		return
	parts -= cost
	facility_levels[id] = lv + 1
	hud.toast("%s 已升级" % String(f.get("name", "")))
	hud.update_stats(self)
	hud.refresh_facilities()

# ---------- 数值 ----------
## 士气系数：50 为中轴，高士气增益、低士气惩罚（0.8 ~ 1.2）
func morale_factor() -> float:
	return clampf(1.0 + (morale - 50.0) / 250.0, 0.8, 1.2)

func _update_resources(delta: float) -> void:
	var z := rv.global_position.z
	dist_km += (last_z - z) / KMH_FACTOR
	last_z = z
	if parked:
		# 驻车休整：全员检修（2.5 倍速度），持续消耗食物；吃饱时士气回升
		if food > 0.0:
			food = maxf(0.0, food - delta * 0.1)
			_starving = false
			# 驻车闲聊只缓慢回暖；想要快速恢复士气，得用灶台做热饭
			morale = minf(100.0, morale + delta * 0.3)
			if durability < 100.0:
				var rate := crew * 0.12
				if _has_passive("lin_wan"):
					rate += 0.35
				durability = minf(100.0, durability + rate * 2.5 * morale_factor() * delta)
		else:
			morale = maxf(0.0, morale - delta * 0.8)
			if not _starving:
				_starving = true
				hud.toast("食物耗尽，检修停摆")
	else:
		# 行驶中的精神消耗：缓慢但持续，事件与驻车是主要士气来源
		if rv.speed_kmh > 1.0:
			morale = maxf(0.0, morale - delta * 0.05)
		# 燃料（沈蔓·驾驶：油耗 -25%；高士气开车更稳更省）
		if rv.speed_kmh > 1.0:
			var burn: float = rv.speed_kmh * delta * 0.0022
			if _has_passive("shen_man"):
				burn *= 0.75
			burn *= 2.0 - morale_factor()
			fuel = maxf(0.0, fuel - burn)
		rv.engine_dead = fuel <= 0.0
		# 队友修车（林晚·急救：额外 +0.35/s；士气影响干劲）
		if rv.speed_kmh > 5.0 and durability < 100.0:
			var repair := crew * 0.12
			if _has_passive("lin_wan"):
				repair += 0.35
			durability = minf(100.0, durability + repair * morale_factor() * delta)
	# 低士气一次性警告（士气回升到 40 以上后可再次触发）
	if morale < 25.0 and not _low_morale_warned:
		_low_morale_warned = true
		hud.toast("士气低落：队伍沉默寡言，操作开始走形")
	elif morale >= 40.0:
		_low_morale_warned = false
	hud.update_stats(self)
	if durability > 0.0:
		dying = false
	elif not dying:
		# 垂死选择：车辆损毁前先进入剧情（抢修可续命），而非立刻结算
		dying = true
		add_trauma(1.0)
		story._open("deathbed")

func _do_game_over() -> void:
	game_over = true
	rv.engine_dead = true
	trauma = 1.0
	hud.show_game_over(self)

## 抵达 680km 方舟集结点：通关
func _do_win() -> void:
	game_over = true
	won = true
	rv.engine_dead = true
	hud.show_victory(self)

# ---------- 昼夜 ----------
func _build_sky() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.27, 0.5, 0.82)
	sky_mat.sky_horizon_color = Color(0.62, 0.78, 0.92)
	sky_mat.ground_bottom_color = Color(0.16, 0.22, 0.12)
	sky_mat.ground_horizon_color = Color(0.55, 0.66, 0.52)
	sky_mat.sun_angle_max = 45.0
	sky_mat.sun_curve = 0.13
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.25
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.68, 0.78, 0.88)
	environment.fog_density = 0.0011
	environment.fog_sky_affect = 0.25
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_bloom = 0.12
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.08
	self.env = environment
	get_viewport().world_3d.environment = environment
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.light_energy = 1.75
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	sun.rotation_degrees = Vector3(-42, 24, 0)
	add_child(sun)
	# 路灯灯头共享材质：夜间开自发光，靠 glow 发亮，不用真实光源
	lamp_mat = StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(0.25, 0.22, 0.18)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.72, 0.38)
	lamp_mat.emission_energy_multiplier = 0.0

func _update_time(delta: float) -> void:
	hour += delta * (0.4 if parked else 0.05)
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
		sun.light_energy = 0.5 + p * 1.4
		sun.light_color = Color(1.0, 0.98, 0.92).lerp(Color(1.0, 0.72, 0.5), 1.0 - p)
		# 明媚末日：正午饱和蓝天，晨昏只在近日落处留一抹暖橙
		sky_mat.sky_top_color = Color(0.27, 0.5, 0.82).lerp(Color(0.42, 0.34, 0.32), (1.0 - p) * 0.6)
		sky_mat.sky_horizon_color = Color(0.62, 0.78, 0.92).lerp(Color(0.92, 0.58, 0.36), (1.0 - p) * 0.7)
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
			env.fog_density = 0.0011
			env.fog_light_color = Color(0.68, 0.78, 0.88)
	# 夜间/雾天自动开灯
	var dark := deg > -15.0 or deg < -165.0
	headlight.light_energy = 11.0 if dark or weather == "fog" else (2.6 if weather == "rain" else 0.0)
	lamp_mat.emission_energy_multiplier = 3.2 if dark else (1.2 if weather != "clear" else 0.0)
	if dark:
		# 夜色：雾色压暗，改用月光色环境光保证剪影可辨
		env.fog_light_color = Color(0.07, 0.09, 0.13)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.22, 0.27, 0.38)
		env.ambient_light_energy = 1.6
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 1.25

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

## 驾驶舱 + 生活舱共用的程序化内饰（仅车内/驾驶舱视角可见）
func _build_interior() -> void:
	interior = Node3D.new()
	interior.name = "Interior"
	rv.add_child(interior)
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
		# 温室上沿压条 + 纵向窗框，把开放式侧壁读作一排车窗
		_interior_box(Vector3(0.09, 0.16, 7.3), Vector3(sx, 2.02, -0.75), shell)
		for wz in [-3.3, -1.9, -0.5, 0.9, 2.3]:
			_interior_box(Vector3(0.09, 1.17, 0.09), Vector3(sx, 1.44, wz), shell)
	# 侧窗玻璃：低饱和灰蓝薄雾，让车厢有封闭感
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.45, 0.55, 0.62, 0.16)
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	for sx in [-1.3, 1.3]:
		var g := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(7.0, 1.06)
		g.mesh = q
		g.material_override = glass
		g.position = Vector3(sx, 1.4, -0.75)
		g.rotation.y = PI * 0.5
		interior.add_child(g)
	# 驾驶舱：仪表台 / 台面 / 挡风上沿 / 后视镜
	_interior_box(Vector3(2.6, 0.55, 0.7), Vector3(0, 0.28, -3.72), shell)
	_interior_box(Vector3(2.55, 0.06, 0.75), Vector3(0, 0.575, -3.7), pad)
	_interior_box(Vector3(2.6, 0.14, 0.16), Vector3(0, 2.03, -4.2), shell)
	_interior_box(Vector3(0.34, 0.08, 0.09), Vector3(0, 1.94, -4.02), pad)
	for sx in [-0.55, 0.55]:
		_interior_box(Vector3(0.52, 0.16, 0.55), Vector3(sx, -0.08, -1.5), seat)
		_interior_box(Vector3(0.52, 0.55, 0.14), Vector3(sx, 0.27, -1.16), seat)
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
	# 方向盘：圆环 + 三辐 + 转向柱，竖直面朝驾驶者略向后倾
	var wheel_pivot := Node3D.new()
	wheel_pivot.position = Vector3(-0.55, 0.78, -3.2)
	wheel_pivot.rotation.x = -PI * 0.5 + 0.28
	interior.add_child(wheel_pivot)
	var wheel := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.18
	tor.outer_radius = 0.245
	wheel.mesh = tor
	wheel.material_override = pad
	wheel_pivot.add_child(wheel)
	for k in 3:
		var spoke := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.035, 0.19, 0.025)
		spoke.mesh = sm
		spoke.material_override = pad
		spoke.position = Vector3(0, 0.095, 0)
		spoke.rotation.z = k * TAU / 3.0
		wheel_pivot.add_child(spoke)
	var hub := MeshInstance3D.new()
	var hm2 := CylinderMesh.new()
	hm2.top_radius = 0.06
	hm2.bottom_radius = 0.06
	hm2.height = 0.05
	hub.mesh = hm2
	hub.rotation.x = PI * 0.5
	hub.material_override = steel
	wheel_pivot.add_child(hub)
	_interior_box(Vector3(0.06, 0.06, 0.6), Vector3(-0.55, 0.62, -2.95), steel)
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
	interior.add_child(gauge)
	# 舱内暖色小灯：夜间/雾天也能看清仪表台与舱内
	var cab_light := OmniLight3D.new()
	cab_light.light_color = Color(1.0, 0.82, 0.6)
	cab_light.light_energy = 3.0
	cab_light.omni_range = 8.0
	cab_light.position = Vector3(0, 1.85, 0.4)
	interior.add_child(cab_light)
	# 生活舱杂物：灶台锅具 / 吊柜 / 货架货物 / 餐桌餐具 / 床铺卧具 / 窗帘
	var cloth := _mat(Color(0.32, 0.18, 0.15))
	var bedding := _mat(Color(0.3, 0.31, 0.3))
	var crate_mat := _mat(Color(0.34, 0.26, 0.17))
	var can_mat := _mat(Color(0.38, 0.39, 0.4))
	var food_mat := _mat(Color(0.45, 0.34, 0.16))
	# 灶台：汤锅 / 煎锅 / 水龙头 / 墙上吊柜
	_interior_cyl(Vector3(-1.0, 0.6, -1.05), 0.16, 0.2, steel)
	_interior_cyl(Vector3(-1.0, 0.72, -1.05), 0.15, 0.04, pad)
	_interior_cyl(Vector3(-1.0, 0.52, 0.55), 0.19, 0.05, steel)
	_interior_box(Vector3(0.05, 0.04, 0.22), Vector3(-0.98, 0.52, 0.78), steel)
	_interior_cyl(Vector3(-0.88, 0.56, -0.18), 0.018, 0.14, steel)
	_interior_box(Vector3(0.03, 0.03, 0.12), Vector3(-0.88, 0.62, -0.23), steel)
	_interior_box(Vector3(0.28, 0.5, 1.8), Vector3(-1.16, 1.55, -0.1), wood)
	# 货架三层货物：木箱 / 罐头 / 粮袋 / 瓶子
	_interior_box(Vector3(0.26, 0.2, 0.34), Vector3(1.12, 0.12, -0.2), crate_mat)
	_interior_box(Vector3(0.28, 0.24, 0.3), Vector3(1.12, 0.57, 0.35), crate_mat)
	_interior_cyl(Vector3(1.05, 0.09, 0.55), 0.07, 0.16, can_mat)
	_interior_cyl(Vector3(1.19, 0.09, 0.55), 0.07, 0.16, can_mat)
	_interior_cyl(Vector3(1.06, 0.54, -0.1), 0.07, 0.16, can_mat)
	_interior_box(Vector3(0.24, 0.2, 0.22), Vector3(1.12, 1.0, 0.0), food_mat)
	_interior_cyl(Vector3(1.06, 0.99, 0.82), 0.035, 0.2, can_mat)
	_interior_cyl(Vector3(1.15, 0.99, 0.85), 0.035, 0.2, can_mat)
	# 餐桌：餐盘 / 水杯 / 酒瓶
	_interior_cyl(Vector3(0.1, 0.37, 1.7), 0.12, 0.02, pad)
	_interior_cyl(Vector3(0.42, 0.4, 1.62), 0.04, 0.09, steel)
	_interior_cyl(Vector3(0.38, 0.46, 1.9), 0.035, 0.2, can_mat)
	# 后铺：枕头 / 毯子 / 衣物卷
	_interior_box(Vector3(0.55, 0.12, 0.3), Vector3(-0.7, 0.44, 2.28), bedding)
	_interior_box(Vector3(1.7, 0.08, 0.9), Vector3(0.1, 0.42, 2.62), cloth)
	var roll := _interior_cyl(Vector3(0.85, 0.48, 2.28), 0.09, 0.5, cloth)
	roll.rotation.z = PI * 0.5
	# 窗帘（弱化大片裸玻璃的生硬）
	_interior_box(Vector3(0.03, 1.0, 0.5), Vector3(-1.27, 1.42, -0.4), cloth)
	_interior_box(Vector3(0.03, 1.0, 0.5), Vector3(-1.27, 1.42, 2.5), cloth)

## 车内视角的队友：副驾坐姿、其余站姿，各自在灶台/货架/餐桌/后铺忙碌
func _build_crew() -> void:
	crew_font = SystemFont.new()
	crew_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "sans-serif"])
	# [本地坐标, 朝向, 是否坐姿]；GLB 正面朝 +Z，副驾朝车头(-Z)故转 180°
	# 地板顶面 y=-0.4：所有站位 root 均落地板；坐姿髋部下沉约 0.44，落在坐垫顶(y=0.0)上
	var stations := [
		[Vector3(0.55, -0.4, -1.45), PI, true],          # 副驾（坐姿朝车头，首位队友）
		[Vector3(-0.55, -0.4, -0.1), -PI * 0.5, false],  # 灶台前，朝 -X
		[Vector3(0.55, -0.4, 0.4), PI * 0.5, false],     # 货架前，朝 +X
		[Vector3(-0.55, -0.4, 1.15), PI * 0.5, false],    # 餐桌靠车头侧，左，朝桌/右
		[Vector3(0.55, -0.4, 1.15), -PI * 0.5, false],    # 餐桌靠车头侧，右，隔桌相望
	]
	for st in stations:
		var fig := Node3D.new()
		var lb := Label3D.new()
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.font = crew_font
		lb.font_size = 26
		lb.pixel_size = 0.0016
		lb.outline_size = 10
		lb.no_depth_test = false
		lb.modulate = Color(1.0, 0.93, 0.84)
		lb.position = Vector3(0, 1.72, 0)
		fig.add_child(lb)
		fig.position = st[0]
		fig.rotation.y = st[1]
		fig.set_meta("label", lb)
		fig.set_meta("seated", st[2])
		fig.visible = false
		rv.add_child(fig)
		crew_figures.append(fig)
	_sync_crew()

## 队员加入/刷新时：按 id 实例化对应 VRM 基底（播 sit/idle）并更新名牌
func _sync_crew() -> void:
	for i in crew_figures.size():
		var f: Node3D = crew_figures[i]
		var lb: Label3D = f.get_meta("label")
		var old: Node = f.get_node_or_null("Char")
		if i < crew_members.size():
			var m: Dictionary = crew_members[i]
			lb.text = "%s · %s" % [m.get("name", ""), m.get("skill", "")]
			var anim_name := "sit" if f.get_meta("seated") else "idle"
			var made := CharUtil.instantiate(String(m.get("id", "")), anim_name, m.get("expression", {}))
			var char: Node3D = made["node"]
			char.name = "Char"
			if old:
				old.queue_free()
			f.add_child(char)
		else:
			lb.text = ""
			if old:
				old.queue_free()

# ---------- 队友互动 ----------
## 车内视角下，队友之间隔一阵子搭一句话，听的人转头看向说的人
func _update_banter(delta: float) -> void:
	if banter_busy or story_active or game_over or combat_active:
		return
	if view_mode != 2 or crew_members.size() < 2:
		return
	banter_t -= delta
	if banter_t <= 0.0:
		_start_banter()

func _start_banter() -> void:
	banter_t = randf_range(14.0, 24.0)
	var n := mini(crew_members.size(), crew_figures.size())
	if n < 2:
		return
	var a := randi() % n
	var b := (a + 1 + randi() % (n - 1)) % n
	var lines: Array = crew_members[a].get("banter", [])
	if lines.is_empty():
		return
	var fa: Node3D = crew_figures[a]
	var fb: Node3D = crew_figures[b]
	var bubble: Label3D = fa.get_meta("bubble", null)
	if bubble == null:
		bubble = Label3D.new()
		bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bubble.font = crew_font
		bubble.font_size = 22
		bubble.pixel_size = 0.0016
		bubble.outline_size = 9
		bubble.modulate = Color(1.0, 0.96, 0.9)
		bubble.position = Vector3(0, 1.28, 0.24)
		bubble.visible = false
		fa.add_child(bubble)
		fa.set_meta("bubble", bubble)
	bubble.text = String(lines[randi() % lines.size()])
	bubble.visible = true
	banter_busy = true
	# 说话者嘴动 + 表情，听者转向说话者，说完转回原位
	var la := fa.find_child("CharLively", true, false) as CharLively
	if la != null:
		la.talk(4.5)
	var back := fb.rotation.y
	var dir := fa.position - fb.position
	fb.rotation.y = atan2(dir.x, dir.z)
	var tw := create_tween()
	tw.tween_interval(4.5)
	tw.tween_callback(func() -> void:
		bubble.visible = false
		fb.rotation.y = back
		banter_busy = false
	)

func _interior_box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	interior.add_child(mi)

## 内饰小圆柱（锅/罐/杯/瓶）：pos 为世界中心，radius/height 定尺寸，轴朝 Y
func _interior_cyl(pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	interior.add_child(mi)
	return mi

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
	# 明媚基调：晴天占大头，恶劣天气只是偶发
	weather = "rain" if roll < 0.15 else ("fog" if roll < 0.30 else "clear")
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
	# 最后 1.5km 进入方舟防区，不再刷怪
	if dist_km >= GOAL_KM - 1.5:
		zombie_timer = 2.0
		return
	if zombie_timer <= 0.0 and zombies.size() < 34:
		var difficulty: float = clampf(dist_km * 0.8 + (rv.speed_kmh / MAX_KMH) * 1.5, 0.0, 2.8)
		zombie_timer = clampf(2.2 - difficulty * 0.6, 0.7, 2.2)
		_spawn_zombie()
	# 引擎声推送：半径随车速；怠速停车只有贴脸才惊动游荡尸群
	var engine_radius: float = lerpf(6.0, 34.0, clampf(rv.speed_kmh / MAX_KMH, 0.0, 1.0))
	for z in zombies:
		if is_instance_valid(z):
			z.on_engine_noise(rv.global_position, engine_radius)
	zombies = zombies.filter(func(z):
		if not is_instance_valid(z):
			return false
		if z.should_free:
			z.queue_free()
			return false
		return true)

func _spawn_zombie() -> void:
	# 成批生成在车前各处：路面、路肩、远处野地都有踱步的丧尸，靠声音才被惊动
	var rvz := rv.global_position.z
	var count := randi_range(1, 4)
	var base_z := rvz - 20.0 - randf() * 150.0
	for i in count:
		var body := RigidBody3D.new()
		body.set_script(ZOMBIE_SCRIPT)
		body.name = "Zombie"
		var zz := base_z - i * randf_range(3.0, 10.0)
		# 45% 在道路附近，55% 散布到两侧野地（最远约 60m）
		var off: float
		if randf() < 0.45:
			off = (randf() - 0.5) * 13.0
		else:
			var side2 := 1.0 if randf() > 0.5 else -1.0
			off = side2 * randf_range(ROAD_HALF + 3.0, 60.0)
		body.position = Vector3(road_x(zz) + off, GROUND_Y + 0.5, zz)
		var col := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35
		cap.height = 1.4
		col.shape = cap
		col.position.y = 0.7
		body.add_child(col)
		var model: Node3D = (ZMB_SCENE_G if randf() < 0.4 else ZMB_SCENE).instantiate()
		model.scale = Vector3.ONE * randf_range(0.058, 0.072)
		body.add_child(model)
		add_child(body)
		body.setup(self)
		zombies.append(body)

## 玩家下车后的角色实体（战斗系统启用；在车内时为 null，丧尸追车）
var player_body: Node3D = null

func get_player_body() -> Node3D:
	return player_body if is_instance_valid(player_body) else null

## 枪声/爆炸：全向惊动周围游荡丧尸进入狂暴
func alert_gunshot(pos: Vector3) -> void:
	for z in zombies:
		if is_instance_valid(z):
			z.on_hear_gunshot(pos)

## 玩家被啃咬（下车战斗时）：全局冷却，转发伤害给玩家
func on_player_bitten() -> void:
	if game_over or bite_cd > 0.0:
		return
	bite_cd = 1.2
	add_trauma(0.2)
	var p := get_player_body()
	if p != null:
		# 唐糖·教练：身手矫健，受伤减轻 40%；士气越低越容易乱
		var dmg := 8.0 * (2.0 - morale_factor())
		if _has_passive("tang_tang"):
			dmg *= 0.6
		p.take_damage(dmg)
	hud.toast("被丧尸抓伤了！快回车里")

# ---------- 下车 / 天窗战斗 ----------
## mode：0 下车（仅驻车），1 天窗探出（行驶中可用）
func start_combat(m: int) -> void:
	if combat_active or game_over or story_active:
		return
	if m == 0 and not parked:
		hud.toast("先按 F 驻车才能下车")
		return
	var p := CharacterBody3D.new()
	p.set_script(PLAYER_SCRIPT)
	if m == 0:
		# 左车门旁落地
		p.position = rv.global_position + rv.global_transform.basis.x * 2.4 + Vector3(0, -RV_MODEL_FOOT, 0.0)
		p.position.y = ground_y(p.position.z)
	else:
		# 车顶天窗：脚踩车顶（碰撞顶约 +2.35）
		p.position = rv.global_position + Vector3(0, 2.35, 0.2)
	p.setup(self, m)
	add_child(p)
	player_body = p
	combat_active = true
	rv.combat_in = true
	p.aim_yaw = rv.rotation.y
	p.aim_pitch = 0.0
	# 第三人称战斗：强制显示车壳、隐藏内饰与队友，退出时由视图模式恢复
	rv_model.visible = true
	interior.visible = false
	for f in crew_figures:
		f.visible = false
	p._enter()
	hud.toast("天窗射击：鼠标瞄准 · 左键开火 · G/T 返回" if m == 1 else "下车战斗：WASD 移动 · 鼠标瞄准 · 左键开火 · G 返回车内")

func end_combat() -> void:
	if not combat_active:
		return
	var p := get_player_body()
	if p != null:
		p._exit()
		p.queue_free()
	player_body = null
	combat_active = false
	rv.combat_in = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cam.make_current()
	# 恢复当前视图模式下的车壳/内饰/队友显隐
	rv_model.visible = view_mode == 0
	interior.visible = view_mode != 0
	for i in crew_figures.size():
		crew_figures[i].visible = view_mode == 2 and i < crew_members.size()

## 天窗模式：玩家身体每帧锚在行驶中的车顶
func _sync_player_to_rv(_delta: float) -> void:
	var p := get_player_body()
	if p == null or p.mode != 1:
		return
	p.position = rv.global_position + Vector3(0, 2.35, 0.2)
	p.velocity = Vector3.ZERO

func on_zombie_shot() -> void:
	hud.flash_hit_marker()

func on_player_dead() -> void:
	end_combat()
	_do_game_over()

## 枪口火光 + 弹道曳光：自发光短寿命节点
func spawn_muzzle_flash(muzzle_ws: Vector3, hit_point: Vector3) -> void:
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.78, 0.42)
	flash.light_energy = 6.0
	flash.omni_range = 9.0
	flash.position = muzzle_ws
	add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.09)
	tw.tween_callback(flash.queue_free)
	var tracer := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var dirv := hit_point - muzzle_ws
	var dist := maxf(dirv.length(), 0.01)
	bm.size = Vector3(0.025, 0.025, dist)
	tracer.mesh = bm
	tracer.material_override = _emis_mat(Color(1.0, 0.85, 0.5), 3.0)
	add_child(tracer)
	tracer.global_position = (muzzle_ws + hit_point) * 0.5
	tracer.look_at(hit_point, Vector3.UP)
	tracer.rotate_y(PI)
	var tw2 := create_tween()
	tw2.tween_interval(0.06)
	tw2.tween_callback(tracer.queue_free)

func zombie_bite() -> void:
	# 全局冷却：同一时刻只允许一只丧尸生效，避免多只叠加秒杀
	if game_over or bite_cd > 0.0:
		return
	bite_cd = 1.2
	var bite := 1.0 + minf(dist_km / 2.0, 3.0)
	if _has_passive("tang_tang"):
		bite *= 0.6
	# 低士气时反应迟钝，咬伤更重；高士气时配合更默契
	bite *= 2.0 - morale_factor()
	durability = maxf(0.0, durability - bite)
	add_trauma(0.12)
	hud.update_stats(self)

# ---------- 前方内容生成 ----------
func _update_frontier() -> void:
	var rvz := rv.global_position.z
	# 方舟防区（最后约 1km）保持道路通畅，不刷障碍/物资/幸存者
	var safe_z := rvz - (GOAL_KM - dist_km) * KMH_FACTOR + 250.0
	while obs_z > rvz - VIEW_AHEAD:
		if obs_z < safe_z:
			obs_z = safe_z - 1.0
			break
		_spawn_obstacle(obs_z)
		obs_z -= randf_range(32.0, 68.0)
	while pick_z > rvz - VIEW_AHEAD:
		if pick_z < safe_z:
			pick_z = safe_z - 1.0
			break
		_spawn_pickup(pick_z)
		pick_z -= randf_range(30.0, 70.0)
	while surv_z > rvz - VIEW_AHEAD:
		if surv_z < safe_z:
			surv_z = safe_z - 1.0
			break
		_spawn_survivor(surv_z)
		surv_z -= randf_range(250.0, 450.0)
	while lamp_z > rvz - VIEW_AHEAD:
		if lamp_z < safe_z:
			lamp_z = safe_z - 1.0
			break
		_spawn_lamp(lamp_z)
		lamp_z -= 55.0
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
	# 路边人形按招募顺序对应下一名队友，外观与人设一致
	var upcoming := _next_crew_member()
	if not upcoming.is_empty():
		s.setup(upcoming.get("id", ""))
	var side := 1.0 if randf() > 0.5 else -1.0
	s.position = Vector3(road_x(z) + side * randf_range(5.5, 8.0), ground_y(z), z)
	add_child(s)

## 路灯：杆 + 朝路面的悬臂 + 自发光灯头，每 55m 交替两侧
func _spawn_lamp(z: float) -> void:
	lamp_side = -lamp_side
	var root := Node3D.new()
	root.add_to_group("consumable")
	root.position = Vector3(road_x(z) + lamp_side * (ROAD_HALF + 1.4), ground_y(z), z)
	var dark := _mat(Color(0.16, 0.15, 0.14))
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.07
	pm.bottom_radius = 0.11
	pm.height = 5.2
	pole.mesh = pm
	pole.position.y = 2.6
	pole.material_override = dark
	root.add_child(pole)
	var arm := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(1.7, 0.09, 0.09)
	arm.mesh = am
	arm.position = Vector3(-lamp_side * 0.85, 5.08, 0)
	arm.material_override = dark
	root.add_child(arm)
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.52, 0.12, 0.24)
	head.mesh = hm
	head.position = Vector3(-lamp_side * 1.62, 5.02, 0)
	head.material_override = lamp_mat
	root.add_child(head)
	add_child(root)

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
	sfx.play("run_over")

func on_pickup(kind: String) -> void:
	if game_over:
		return
	var mult := 1.5 if _has_passive("ye_lan") else 1.0
	match kind:
		"fuel":
			var g := 25.0 * mult
			fuel = minf(fuel_cap(), fuel + g)
			hud.toast("+%d 燃料" % int(g))
		"food":
			var g := 8.0 * mult
			food += g
			hud.toast("+%d 食物" % int(g))
		"repair":
			var g := 15.0 * mult
			durability = minf(100.0, durability + g)
			# 修理箱拆出可用零件（叶澜·搜刮：物资整体 +50%）
			var pg := 2.0 * mult
			parts += pg
			hud.toast("+%d 车况 · +%d 零件" % [int(g), int(pg)])
	sfx.play("pickup")
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
	for i in range(100):
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
	# 路肩青草丛：两片交叉草叶，双面不剔除，随世界回收
	var grass_mat := _mat(Color(0.2, 0.34, 0.13))
	grass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 野花：三色小贴片散布草丛间
	var flower_mats := [_mat(Color(0.9, 0.36, 0.42)), _mat(Color(0.95, 0.82, 0.25)), _mat(Color(0.55, 0.5, 0.92))]
	for fm in flower_mats:
		fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in range(70):
		var zz := -650.0 + randf() * 710.0
		var side := 1.0 if randf() > 0.5 else -1.0
		var gq := QuadMesh.new()
		var gh := randf_range(0.35, 0.8)
		gq.size = Vector2(randf_range(0.18, 0.34), gh)
		var blades := Node3D.new()
		blades.position = Vector3(
			road_x(zz) + side * randf_range(ROAD_HALF + 0.3, ROAD_HALF + 13.0),
			ground_y(zz),
			zz)
		var g := MeshInstance3D.new()
		g.mesh = gq
		g.material_override = grass_mat
		g.position.y = gh * 0.5
		g.rotation.y = randf() * PI
		blades.add_child(g)
		var g2 := MeshInstance3D.new()
		g2.mesh = gq
		g2.material_override = grass_mat
		g2.position.y = gh * 0.5
		g2.rotation.y = PI * 0.5
		blades.add_child(g2)
		add_child(blades)
		props.append(blades)
	# 野花：细茎 + 花冠小十字贴片
	var stem_mat := _mat(Color(0.16, 0.3, 0.12))
	for i in range(60):
		var zz := -650.0 + randf() * 710.0
		var side := 1.0 if randf() > 0.5 else -1.0
		var flower := Node3D.new()
		flower.position = Vector3(
			road_x(zz) + side * randf_range(ROAD_HALF + 1.0, ROAD_HALF + 22.0),
			ground_y(zz),
			zz)
		var fh := randf_range(0.28, 0.55)
		var stem_mi := MeshInstance3D.new()
		var stem_bm := BoxMesh.new()
		stem_bm.size = Vector3(0.03, fh, 0.03)
		stem_mi.mesh = stem_bm
		stem_mi.material_override = stem_mat
		stem_mi.position.y = fh * 0.5
		flower.add_child(stem_mi)
		var fq := QuadMesh.new()
		fq.size = Vector2(0.16, 0.16)
		var head := MeshInstance3D.new()
		head.mesh = fq
		head.material_override = flower_mats[i % flower_mats.size()]
		head.position.y = fh + 0.05
		head.rotation.y = randf() * PI
		flower.add_child(head)
		var head2 := MeshInstance3D.new()
		head2.mesh = fq
		head2.material_override = flower_mats[i % flower_mats.size()]
		head2.position.y = fh + 0.05
		head2.rotation.y = PI * 0.5
		flower.add_child(head2)
		add_child(flower)
		props.append(flower)

# ---------- 方舟集结点（终点营地） ----------
## 车接近 680km 终点时一次性生成：钢制大门、哨塔、围墙、帐篷、灯海、人群
## 大门锚定 680km 对应世界坐标：营地在 672km 时生成（灯海先进入视野），680km 时大门恰在车前 40m
func _spawn_ark_camp() -> void:
	var remain_world := (GOAL_KM - dist_km) * KMH_FACTOR
	var gate_z := rv.global_position.z - remain_world + 40.0
	var gy := ground_y(gate_z)
	var camp := Node3D.new()
	camp.name = "ArkCamp"
	camp.position = Vector3(0.0, 0.0, gate_z)
	add_child(camp)
	var rng := RandomNumberGenerator.new()
	rng.seed = 680

	var steel := _mat(Color(0.32, 0.33, 0.34))
	steel.metallic = 0.6
	steel.roughness = 0.45
	var dark_steel := _mat(Color(0.2, 0.2, 0.21))
	dark_steel.metallic = 0.5
	var concrete := _mat(Color(0.42, 0.4, 0.36))
	var canvas_olive := _mat(Color(0.27, 0.3, 0.22))
	var canvas_sand := _mat(Color(0.36, 0.32, 0.24))

	# 硬化空地（大门内侧）
	var pad_mi := MeshInstance3D.new()
	var padm := PlaneMesh.new()
	padm.size = Vector2(90.0, 120.0)
	pad_mi.mesh = padm
	pad_mi.rotation.x = -PI * 0.5
	pad_mi.position = Vector3(0.0, ground_y(gate_z - 60.0) + 0.02, -60.0)
	pad_mi.material_override = _mat(Color(0.22, 0.21, 0.19))
	camp.add_child(pad_mi)

	# 发光材质（灯光）
	var warm_glow := _emis_mat(Color(1.0, 0.78, 0.42), 2.2)

	# 门柱（2）
	for sx in [-6.0, 6.0]:
		var post := MeshInstance3D.new()
		var pm2 := BoxMesh.new()
		pm2.size = Vector3(1.6, 8.0, 1.6)
		post.mesh = pm2
		post.position = Vector3(sx, gy + 4.0, 0.0)
		post.material_override = concrete
		camp.add_child(post)
		var cap := MeshInstance3D.new()
		var capm := BoxMesh.new()
		capm.size = Vector3(2.2, 0.6, 2.2)
		cap.mesh = capm
		cap.position = Vector3(sx, gy + 8.3, 0.0)
		cap.material_override = dark_steel
		camp.add_child(cap)
		# 柱顶灯
		var lamp := MeshInstance3D.new()
		lamp.mesh = SphereMesh.new()
		lamp.mesh.radius = 0.35
		lamp.mesh.height = 0.7
		lamp.position = Vector3(sx, gy + 8.7, 0.0)
		lamp.material_override = warm_glow
		camp.add_child(lamp)
		var pl := OmniLight3D.new()
		pl.light_color = Color(1.0, 0.8, 0.5)
		pl.light_energy = 3.0
		pl.omni_range = 22.0
		pl.position = lamp.position
		camp.add_child(pl)

	# 钢制大门两扇（向外侧敞开）
	for sx in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(sx * 5.2, gy, 0.0)
		pivot.rotation.y = sx * 1.15
		camp.add_child(pivot)
		var leaf := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(4.4, 5.6, 0.28)
		leaf.mesh = lm
		leaf.position.x = sx * 2.2
		leaf.position.y = 2.8
		leaf.material_override = steel
		pivot.add_child(leaf)
		for by in [-1.6, 0.0, 1.6]:
			var bar := MeshInstance3D.new()
			var bm2 := BoxMesh.new()
			bm2.size = Vector3(4.2, 0.18, 0.4)
			bar.mesh = bm2
			bar.position = Vector3(sx * 2.2, 2.8 + by, 0.05)
			bar.material_override = dark_steel
			pivot.add_child(bar)

	# 横梁 + 方舟标识牌
	var beam := MeshInstance3D.new()
	var beamm := BoxMesh.new()
	beamm.size = Vector3(15.0, 1.4, 1.0)
	beam.mesh = beamm
	beam.position = Vector3(0.0, gy + 8.6, 0.0)
	beam.material_override = steel
	camp.add_child(beam)
	var sign := Label3D.new()
	sign.text = "方舟集结点"
	sign.font_size = 96
	sign.pixel_size = 0.009
	sign.outline_size = 12
	sign.outline_modulate = Color(0.1, 0.06, 0.02)
	sign.modulate = Color(1.0, 0.82, 0.45)
	sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sign.position = Vector3(0.0, gy + 8.6, 0.55)
	camp.add_child(sign)

	# 围墙：集装箱墙向两侧延伸
	for k in range(7):
		var ox := 11.0 + k * 7.2
		for sx in [-1.0, 1.0]:
			var box := MeshInstance3D.new()
			var bxm := BoxMesh.new()
			bxm.size = Vector3(7.0, 3.0, 2.8)
			box.mesh = bxm
			var ccol := Color(0.28, 0.3, 0.26) if k % 2 == 0 else Color(0.24, 0.26, 0.28)
			box.material_override = _mat(ccol)
			box.position = Vector3(sx * ox, gy + 1.5, (2.0 if k % 2 == 0 else -2.0))
			camp.add_child(box)

	# 哨塔（2 座）
	for sx in [-14.0, 14.0]:
		var tg := Node3D.new()
		tg.position = Vector3(sx, gy, -4.0)
		camp.add_child(tg)
		for lx in [-1.0, 1.0]:
			for lz in [-1.0, 1.0]:
				var leg := MeshInstance3D.new()
				var legm := BoxMesh.new()
				legm.size = Vector3(0.22, 7.0, 0.22)
				leg.mesh = legm
				leg.position = Vector3(lx, 3.5, lz)
				leg.material_override = dark_steel
				tg.add_child(leg)
		var deck := MeshInstance3D.new()
		var dm := BoxMesh.new()
		dm.size = Vector3(3.0, 0.3, 3.0)
		deck.mesh = dm
		deck.position.y = 7.1
		deck.material_override = steel
		tg.add_child(deck)
		var hut := MeshInstance3D.new()
		var htm := BoxMesh.new()
		htm.size = Vector3(2.6, 1.8, 2.6)
		hut.mesh = htm
		hut.position.y = 8.15
		hut.material_override = canvas_olive
		tg.add_child(hut)
		var tlamp := MeshInstance3D.new()
		tlamp.mesh = SphereMesh.new()
		tlamp.mesh.radius = 0.3
		tlamp.mesh.height = 0.6
		tlamp.position = Vector3(0.0, 9.3, 0.0)
		tlamp.material_override = warm_glow
		tg.add_child(tlamp)
		var tl := SpotLight3D.new()
		tl.light_color = Color(1.0, 0.82, 0.55)
		tl.light_energy = 4.0
		tl.spot_range = 40.0
		tl.spot_angle = 40.0
		tl.position = Vector3(0.0, 9.0, 0.0)
		tl.rotation_degrees = Vector3(-25, -sx * 26.0, 0)
		tg.add_child(tl)
		# 探照灯循环扫视；两塔起摆方向相反形成错相
		var sweep_to: float = sx * 26.0
		var stw := camp.create_tween().set_loops()
		stw.tween_property(tl, "rotation_degrees:y", sweep_to, 5.2).set_trans(Tween.TRANS_SINE)
		stw.tween_property(tl, "rotation_degrees:y", -sx * 26.0, 5.2).set_trans(Tween.TRANS_SINE)

	# 帐篷群（两列排布）：底箱 + 双人字斜面顶
	for i in range(12):
		var col_i := i % 2
		var row_i := i / 2
		var tz := -24.0 - row_i * 9.0
		var t := Node3D.new()
		t.position = Vector3(-9.0 + col_i * 18.0, ground_y(gate_z + tz), tz)
		camp.add_child(t)
		var tmat: StandardMaterial3D = canvas_olive if i % 2 == 0 else canvas_sand
		var body := MeshInstance3D.new()
		var bodym := BoxMesh.new()
		bodym.size = Vector3(3.6, 1.5, 4.4)
		body.mesh = bodym
		body.position.y = 0.75
		body.material_override = tmat
		t.add_child(body)
		for rs in [-1.0, 1.0]:
			var roof := MeshInstance3D.new()
			var rm := BoxMesh.new()
			rm.size = Vector3(2.25, 0.12, 4.7)
			roof.mesh = rm
			roof.position = Vector3(rs * 0.95, 1.95, 0.0)
			roof.rotation.z = rs * -0.62
			roof.material_override = tmat
			t.add_child(roof)
		# 帐篷前暖光
		var tl2 := OmniLight3D.new()
		tl2.light_color = Color(1.0, 0.72, 0.4)
		tl2.light_energy = 1.1
		tl2.omni_range = 7.0
		tl2.position = Vector3(0.0, 1.4, 2.8)
		t.add_child(tl2)

	# 灯海：大门两侧纵深散布的暖光点
	for i in range(46):
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var lx := side * rng.randf_range(10.0, 46.0)
		var lz := -rng.randf_range(6.0, 115.0)
		var bulb := MeshInstance3D.new()
		bulb.mesh = SphereMesh.new()
		bulb.mesh.radius = 0.22
		bulb.mesh.height = 0.44
		bulb.position = Vector3(lx, ground_y(gate_z + lz) + rng.randf_range(1.6, 3.2), lz)
		bulb.material_override = warm_glow
		camp.add_child(bulb)

	# 人群：大门两侧聚集欢呼的人影（躯干+头+双臂挥动）
	var coat_cols: Array[Color] = [
		Color(0.2, 0.24, 0.18), Color(0.28, 0.2, 0.15), Color(0.16, 0.2, 0.26),
		Color(0.3, 0.26, 0.16), Color(0.24, 0.15, 0.17), Color(0.18, 0.18, 0.18)
	]
	for i in range(22):
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var p := Node3D.new()
		p.position = Vector3(side * rng.randf_range(7.5, 13.0), gy, rng.randf_range(-6.0, 10.0))
		p.rotation.y = -side * PI / 2.0 + rng.randf_range(-0.4, 0.4)
		camp.add_child(p)
		var coat := _mat(coat_cols[randi() % coat_cols.size()])
		var torso := MeshInstance3D.new()
		var tm2 := CapsuleMesh.new()
		tm2.radius = 0.26
		tm2.height = 1.15
		torso.mesh = tm2
		torso.position.y = 0.86
		torso.material_override = coat
		p.add_child(torso)
		var head := MeshInstance3D.new()
		var hm2 := SphereMesh.new()
		hm2.radius = 0.18
		hm2.height = 0.36
		head.mesh = hm2
		head.position.y = 1.62
		head.material_override = _mat(Color(0.62, 0.5, 0.4))
		p.add_child(head)
		var arms: Array[Node3D] = []
		for hsx in [-1.0, 1.0]:
			var arm_node := Node3D.new()
			arm_node.position = Vector3(hsx * 0.3, 1.3, 0.0)
			arm_node.rotation.x = -1.9
			arm_node.rotation.z = hsx * 0.3
			p.add_child(arm_node)
			var arm := MeshInstance3D.new()
			var am2 := CapsuleMesh.new()
			am2.radius = 0.08
			am2.height = 0.7
			arm.mesh = am2
			arm.position.y = -0.32
			arm.material_override = coat
			arm_node.add_child(arm)
			arms.append(arm_node)
		# 挥手 + 身体起伏（各人节奏错相）
		var period := rng.randf_range(0.5, 0.9)
		var wave := camp.create_tween().set_loops()
		wave.tween_property(arms[0], "rotation:x", -2.5, period).set_trans(Tween.TRANS_SINE)
		wave.tween_property(arms[0], "rotation:x", -1.5, period).set_trans(Tween.TRANS_SINE)
		var wave2 := camp.create_tween().set_loops()
		wave2.tween_property(arms[1], "rotation:x", -1.4, period * 1.3).set_trans(Tween.TRANS_SINE)
		wave2.tween_property(arms[1], "rotation:x", -2.4, period * 1.3).set_trans(Tween.TRANS_SINE)
		var bounce := camp.create_tween().set_loops()
		bounce.tween_property(p, "position:y", gy + 0.18, period).set_trans(Tween.TRANS_SINE)
		bounce.tween_property(p, "position:y", gy, period).set_trans(Tween.TRANS_SINE)

	# 篝火（大门内侧正中）
	var fire := MeshInstance3D.new()
	fire.mesh = CylinderMesh.new()
	fire.mesh.top_radius = 0.5
	fire.mesh.bottom_radius = 0.6
	fire.mesh.height = 0.5
	fire.position = Vector3(0.0, ground_y(gate_z - 14.0) + 0.25, -14.0)
	fire.material_override = _emis_mat(Color(1.0, 0.5, 0.15), 3.0)
	camp.add_child(fire)
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.55, 0.2)
	fl.light_energy = 2.4
	fl.omni_range = 14.0
	fl.position = fire.position + Vector3(0.0, 1.2, 0.0)
	camp.add_child(fl)
	# 篝火明暗跳动
	var flicker := camp.create_tween().set_loops()
	flicker.tween_property(fl, "light_energy", 3.4, 0.16)
	flicker.tween_property(fl, "light_energy", 2.0, 0.22)

	# 篝火炊烟：灰色半透明贴片粒子，缓慢上飘并横向漂移
	var smoke := CPUParticles3D.new()
	smoke.amount = 64
	smoke.lifetime = 4.6
	smoke.lifetime_randomness = 0.5
	smoke.preprocess = 2.0
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.45
	smoke.position = fire.position + Vector3(0.0, 0.7, 0.0)
	smoke.direction = Vector3(0.3, 1.0, 0.0)
	smoke.spread = 22.0
	smoke.gravity = Vector3(1.1, 0.25, 0.0)
	smoke.initial_velocity_min = 0.5
	smoke.initial_velocity_max = 0.9
	smoke.scale_amount_min = 0.9
	smoke.scale_amount_max = 1.6
	var alpha_ramp := Gradient.new()
	alpha_ramp.add_point(0.0, Color(0.55, 0.53, 0.5, 0.0))
	alpha_ramp.add_point(0.28, Color(0.55, 0.53, 0.5, 0.13))
	alpha_ramp.add_point(1.0, Color(0.55, 0.53, 0.5, 0.0))
	smoke.color_ramp = alpha_ramp
	var sq := QuadMesh.new()
	sq.size = Vector2(0.5, 0.5)
	var soft := Gradient.new()
	soft.add_point(0.0, Color(1, 1, 1, 1))
	soft.add_point(0.55, Color(1, 1, 1, 0.65))
	soft.add_point(1.0, Color(1, 1, 1, 0))
	var soft_tex := GradientTexture2D.new()
	soft_tex.gradient = soft
	soft_tex.width = 64
	soft_tex.height = 64
	soft_tex.fill = GradientTexture2D.FILL_RADIAL
	soft_tex.fill_from = Vector2(0.5, 0.5)
	soft_tex.fill_to = Vector2(0.854, 0.854)
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_texture = soft_tex
	sm.albedo_color = Color(0.55, 0.53, 0.5)
	sm.vertex_color_use_as_albedo = true
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.billboard_keep_scale = true
	sq.material = sm
	smoke.mesh = sq
	camp.add_child(smoke)

	# 门柱顶飘扬的方舟旗：横杆 + 软旗片，tween 循环缩放 x 模拟风摆
	for sx in [-1.0, 1.0]:
		var fp := Node3D.new()
		fp.position = Vector3(sx * 6.0, gy + 9.4, 0.0)
		camp.add_child(fp)
		var yard := MeshInstance3D.new()
		var ym := BoxMesh.new()
		ym.size = Vector3(2.2, 0.1, 0.1)
		yard.mesh = ym
		yard.position.x = sx * 1.0
		yard.material_override = dark_steel
		fp.add_child(yard)
		var flag := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(1.8, 1.0, 0.04)
		flag.mesh = fm
		# 旗片绕门柱那一侧摆动：原点平移到旗杆端后缩放
		flag.position = Vector3(sx * 2.0, -0.05, 0.0)
		flag.scale.x = 1.0
		flag.material_override = _mat(Color(0.62, 0.18, 0.14))
		fp.add_child(flag)
		var flag_swing := camp.create_tween().set_loops()
		flag_swing.tween_property(flag, "scale:x", 0.86, 0.9).set_trans(Tween.TRANS_SINE)
		flag_swing.tween_property(flag, "scale:x", 1.0, 0.9).set_trans(Tween.TRANS_SINE)

	# 营地停车场：几辆废弃/驻扎车辆残骸，硬化空地两侧
	var wreck_cols: Array[Color] = [
		Color(0.3, 0.32, 0.28), Color(0.24, 0.26, 0.3), Color(0.34, 0.26, 0.2),
	]
	for i in range(5):
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var w := _make_wreck(wreck_cols[i % wreck_cols.size()], rng, i)
		w.position = Vector3(side * rng.randf_range(22.0, 34.0), ground_y(gate_z - 30.0 - i * 14.0), -30.0 - i * 14.0)
		w.rotation.y = side * rng.randf_range(-0.3, 0.35)
		camp.add_child(w)

	# 围墙巡逻哨兵：两人沿营地纵深往返走动
	for gi in range(2):
		var guard := Node3D.new()
		var gside: float = -1.0 if gi == 0 else 1.0
		guard.position = Vector3(gside * 13.0, gy, -6.0)
		guard.rotation.y = -gside * PI / 2.0
		camp.add_child(guard)
		var gcoat := _mat(Color(0.18, 0.22, 0.16))
		var gtorso := MeshInstance3D.new()
		var gtm := CapsuleMesh.new()
		gtm.radius = 0.24
		gtm.height = 1.1
		gtorso.mesh = gtm
		gtorso.position.y = 0.86
		gtorso.material_override = gcoat
		guard.add_child(gtorso)
		var ghead := MeshInstance3D.new()
		var ghm := SphereMesh.new()
		ghm.radius = 0.17
		ghm.height = 0.34
		ghead.mesh = ghm
		ghead.position.y = 1.6
		ghead.material_override = _mat(Color(0.6, 0.48, 0.38))
		guard.add_child(ghead)
		# 头盔
		var helm := MeshInstance3D.new()
		var helm_m := SphereMesh.new()
		helm_m.radius = 0.19
		helm_m.height = 0.26
		helm.mesh = helm_m
		helm.position.y = 1.66
		helm.material_override = dark_steel
		guard.add_child(helm)
		# 巡逻：沿 z 走到营地深处再返回，到位转身
		var far_z := -90.0 - gi * 18.0
		var patrol := camp.create_tween().set_loops()
		patrol.tween_property(guard, "position:z", far_z, 18.0).set_trans(Tween.TRANS_LINEAR)
		patrol.tween_property(guard, "rotation:y", gside * PI / 2.0, 0.6)
		patrol.tween_property(guard, "position:z", -6.0, 18.0).set_trans(Tween.TRANS_LINEAR)
		patrol.tween_property(guard, "rotation:y", -gside * PI / 2.0, 0.6)
		# 走动时身体轻微起伏
		var gstep := camp.create_tween().set_loops()
		gstep.tween_property(guard, "position:y", gy + 0.07, 0.34).set_trans(Tween.TRANS_SINE)
		gstep.tween_property(guard, "position:y", gy, 0.34).set_trans(Tween.TRANS_SINE)

## 程序化废弃/驻扎车辆残骸：锈蚀车身 + 驾驶舱 + 歪斜车轮，随机破损
func _make_wreck(col: Color, rng: RandomNumberGenerator, seed_i: int) -> Node3D:
	var w := Node3D.new()
	var body_mat := _mat(col)
	var body := MeshInstance3D.new()
	var bm3 := BoxMesh.new()
	bm3.size = Vector3(2.0, 0.9, 4.2)
	body.mesh = bm3
	body.position.y = 0.85
	body.material_override = body_mat
	w.add_child(body)
	var cab := MeshInstance3D.new()
	var cm3 := BoxMesh.new()
	cm3.size = Vector3(1.9, 0.85, 1.8)
	cab.mesh = cm3
	cab.position = Vector3(0.0, 1.5, -0.9)
	cab.material_override = body_mat
	w.add_child(cab)
	# 破碎挡风玻璃（暗色）
	var glass := MeshInstance3D.new()
	var glm := BoxMesh.new()
	glm.size = Vector3(1.5, 0.5, 0.06)
	glass.mesh = glm
	glass.position = Vector3(0.0, 1.55, -1.84)
	glass.material_override = _mat(Color(0.12, 0.14, 0.15))
	w.add_child(glass)
	# 四个歪斜车轮
	var wheel_mat := _mat(Color(0.08, 0.08, 0.08))
	for wx in [-1.05, 1.05]:
		for wz in [-1.4, 1.4]:
			var wheel := MeshInstance3D.new()
			var wm := CylinderMesh.new()
			wm.top_radius = 0.42
			wm.bottom_radius = 0.42
			wm.height = 0.3
			wheel.mesh = wm
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(wx, 0.42, wz)
			wheel.rotation.y = rng.randf_range(-0.3, 0.3)
			wheel.material_override = wheel_mat
			w.add_child(wheel)
	# 随机一辆侧倾/陷胎，显破败
	if seed_i % 2 == 0:
		w.rotation.z = rng.randf_range(-0.06, 0.06)
		w.position.y = -0.15
	return w

func _make_scenery(z: float) -> Node3D:
	var root := Node3D.new()
	var side := 1.0 if randf() > 0.5 else -1.0
	root.position = Vector3(
		road_x(z) + side * (ROAD_HALF + 3.0 + randf() * 26.0),
		ground_y(z),
		z)
	var roll := randf()
	if roll < 0.06:
		# 枯树：树干 + 歪斜枯枝（少量点缀，提醒这是末世）
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
	elif roll < 0.30:
		# 阔叶绿树：树干 + 三团鲜绿叶冠，末世里草木照样疯长
		var tree := _make_broadleaf()
		root.add_child(tree)
	elif roll < 0.44:
		# 常青松树：矮干 + 三层锥形树冠
		var pine := _make_pine()
		root.add_child(pine)
	elif roll < 0.56:
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
	elif roll < 0.70:
		# 废墟楼：近处矮楼 + 远处玻璃幕墙高楼天际线
		var far := randf() < 0.55
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		if far:
			bm.size = Vector3(randf_range(9.0, 18.0), randf_range(28.0, 72.0), randf_range(9.0, 16.0))
		else:
			bm.size = Vector3(randf_range(5.0, 10.0), randf_range(6.0, 14.0), randf_range(5.0, 10.0))
		b.mesh = bm
		b.position.y = bm.size.y * 0.5
		if far:
			# 玻璃幕墙：低粗糙、微蓝、反射天光，晴天里明亮挺拔
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.52, 0.66, 0.78)
			glass.metallic = 0.35
			glass.roughness = 0.22
			b.material_override = glass
		else:
			b.material_override = _mat(Color(0.3, 0.3, 0.31))
		root.add_child(b)
		# 楼顶破损女儿墙/天线，强化废墟感
		if far and randf() < 0.5:
			var antenna := MeshInstance3D.new()
			var am2 := CylinderMesh.new()
			am2.top_radius = 0.05
			am2.bottom_radius = 0.08
			am2.height = randf_range(3.0, 8.0)
			antenna.mesh = am2
			antenna.position = Vector3(randf_range(-bm.size.x * 0.3, bm.size.x * 0.3), bm.size.y + am2.height * 0.5, 0)
			antenna.material_override = _mat(Color(0.25, 0.25, 0.26))
			root.add_child(antenna)
		root.position.x = road_x(z) + side * (randf_range(105.0, 190.0) if far else randf_range(45.0, 90.0))
	elif roll < 0.82:
		# 路边广告牌：双腿 + 锈蚀面板
		for px in [-1.1, 1.1]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.14, 3.2, 0.14)
			leg.mesh = lm
			leg.position = Vector3(px, 1.6, 0)
			leg.material_override = _mat(Color(0.2, 0.19, 0.17))
			root.add_child(leg)
		var panel := MeshInstance3D.new()
		var plm := BoxMesh.new()
		plm.size = Vector3(3.4, 1.9, 0.12)
		panel.mesh = plm
		panel.position.y = 3.8
		panel.rotation.y = randf_range(-0.15, 0.15)
		panel.material_override = _mat(Color(0.36, 0.3, 0.24))
		root.add_child(panel)
		root.position.x = road_x(z) + side * randf_range(ROAD_HALF + 4.0, ROAD_HALF + 9.0)
	elif roll < 0.90:
		# 茂盛灌木：两团鲜绿球丛，部分顶端点缀花色
		var shrub_col := Color(0.17, 0.34, 0.13).lerp(Color(0.3, 0.42, 0.16), randf())
		for n in randi_range(2, 3):
			var tu := MeshInstance3D.new()
			var tum := CylinderMesh.new()
			tum.top_radius = randf_range(0.35, 0.6)
			tum.bottom_radius = randf_range(0.45, 0.8)
			tum.height = randf_range(0.7, 1.3)
			tum.radial_segments = 6
			tu.mesh = tum
			tu.position = Vector3(randf_range(-0.7, 0.7), tum.height * 0.5, randf_range(-0.7, 0.7))
			tu.rotation.y = randf() * TAU
			tu.material_override = _mat(shrub_col)
			root.add_child(tu)
	elif roll < 0.96:
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

## 程序化常青松树：短干 + 三层锥形树冠（自下而上收窄），灰绿做旧，整体随机缩放
func _make_pine() -> Node3D:
	var p := Node3D.new()
	var trunk_h := randf_range(1.0, 1.7)
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.11
	tm.bottom_radius = 0.22
	tm.height = trunk_h
	trunk.mesh = tm
	trunk.position.y = trunk_h * 0.5
	trunk.material_override = _mat(Color(0.17, 0.13, 0.09))
	p.add_child(trunk)
	var col := Color(0.13, 0.3, 0.12).lerp(Color(0.26, 0.4, 0.17), randf())
	var tiers := [
		Vector2(1.9, 2.0), # (底半径, 层高)
		Vector2(1.45, 1.8),
		Vector2(0.95, 1.6),
	]
	var y := trunk_h
	for t in tiers:
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = t.x
		cm.height = t.y
		cone.mesh = cm
		cone.position.y = y + t.y * 0.5 - 0.35
		cone.material_override = _mat(col)
		p.add_child(cone)
		y += t.y - 0.55
	p.scale = Vector3.ONE * randf_range(0.8, 1.25)
	p.rotation.y = randf() * TAU
	return p

## 程序化阔叶树：树干 + 三团高低错落的鲜绿叶冠（低多边形球体），整体随机缩放
func _make_broadleaf() -> Node3D:
	var t := Node3D.new()
	var trunk_h := randf_range(2.6, 4.2)
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.12
	tm.bottom_radius = 0.3
	tm.height = trunk_h
	trunk.mesh = tm
	trunk.position.y = trunk_h * 0.5
	trunk.material_override = _mat(Color(0.26, 0.19, 0.12))
	t.add_child(trunk)
	var leaf_col := Color(0.16, 0.38, 0.12).lerp(Color(0.34, 0.52, 0.18), randf())
	var blobs := [
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.9, -0.5, 0.4),
		Vector3(-0.8, -0.7, -0.3),
	]
	for off in blobs:
		var crown := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = randf_range(1.2, 1.7)
		sm.height = sm.radius * randf_range(1.5, 1.9)
		sm.radial_segments = 7
		sm.rings = 5
		crown.mesh = sm
		crown.position = Vector3(off.x, trunk_h + 1.0 + off.y, off.z)
		crown.material_override = _mat(leaf_col.lerp(Color(0.4, 0.55, 0.2), randf() * 0.25))
		t.add_child(crown)
	t.scale = Vector3.ONE * randf_range(0.85, 1.3)
	t.rotation.y = randf() * TAU
	return t

func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	return m

## 自发光材质（营灯/篝火）
func _emis_mat(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.roughness = 0.6
	return m

# ---------- 地形函数（全场景共享） ----------
func road_x(z: float) -> float:
	return sin(z * 0.035) * 3.5 + sin(z * 0.1 + 1.5) * 1.6

func ground_y(z: float) -> float:
	return GROUND_Y + sin(z * 0.06) * 0.08 + sin(z * 0.13 + 2.1) * 0.05 + sin(z * 0.031 + 5.0) * 0.04
