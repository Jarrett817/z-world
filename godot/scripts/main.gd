extends Node3D
## 末世：我要当救世主 —— Godot 版主场景（全代码构建，零编辑器依赖）
## 线性驾驶生存：无限公路、丧尸围攻、障碍撞击、物资收集、幸存者招募、昼夜循环。

const RV_SCENE := preload("res://assets/rv/gs_001.glb")
const RV_INTERIOR_SCENE := preload("res://assets/rv_interior.glb")
const ZMB_SCENE := preload("res://assets/props/zmb_stand.glb")
const ZMB_SCENE_G := preload("res://assets/props/zmb_stand_g.glb")
const ZMB_SCENE_R := preload("res://assets/props/zmb_ripper.glb")
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
const MATE_SCRIPT := preload("res://scripts/mate.gd")
const BUILDING_SCENE := preload("res://assets/props/scene_models/building/scene.gltf")
const TREE_SCENE := preload("res://assets/props/scene_models/tree/scene.gltf")
const JUNK_SCENE := preload("res://assets/props/scene_models/container/scene.gltf")

const GROUND_Y := -1.56
const KMH_FACTOR := 250.0   # 世界米 → 里程公里（1440 旧值，调快后一局实际驾驶 ~15 分钟走完序章的 680km 目标）
const GOAL_KM := 680.0      # 方舟集结点里程，抵达触发终章
const ROAD_HALF := 7.0
const MAX_KMH := 140.0
const VIEW_AHEAD := 260.0
const VIEW_BEHIND := 40.0
const RV_MODEL_FOOT := 1.557   # GLB 轮底到模型原点的距离
const RV_ROOF_Y := 2.077       # 实测 gs_001.glb 主车壳(Object_16)顶面局部高度，天窗站立用
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
var _fv_yaw := 0.0     # 车内自由视角：右键拖动环顾的偏航/俯仰偏移
var _fv_pitch := 0.0
var combat_active := false
var rv_walk_active := false   # 车内行走中（驻车起身 / 队友代驾巡航）
var _q_down := false
var _zones: Array = []        # 景观段循环（data/terrain_zones.json）
var _zones_total := 0.0
var _wrecks: Array = []       # 撞飞后待落地冻结的障碍残骸
var scenery_z := -20.0
var sign_z := -50.0 * KMH_FACTOR   # 里程碑路牌：首块在 50km 处
var _detour_z := -JUNCTION_EVERY   # 可探索支路扫描游标（对齐 -n*JUNCTION_EVERY 岔路网格）
var pole_z := -40.0                # 电线杆生成前沿
var _pole_prev: Array = []         # 上一根电线杆两侧挂线点（世界坐标）
var _world_seed := 1               # 确定性世界种子（data/world.json）
var _places: Array = []            # 沿途地点（km 升序，data/world.json）
var _detours: Array = []           # 可探索支路 POI 类型表（data/world.json）
var _hamlet_cfg: Dictionary = {}   # 小聚落填充配置（data/world.json hamlets）
var _hamlet_km := 0.0              # 下一个小聚落里程（0=未初始化/已结束）
var _place_idx := 0                # 下一个待生成地点
var _place_sign_idx := 0           # 下一个待出预告牌的地点（预告牌在地点前 1.5km）
var _g_down := false
var _t_down := false
var parked := false
var _park_brake := false  # 驻车自动刹车中：F 超速时按下即重刹，停稳自动完成驻车
var _f_down := false
var _e_down := false
var facilities_visible := false
var facilities_data := {}
var credits_data := {}
var facility_levels := {}   # 设施 id → 当前等级（0 起）
var _starving := false
var _low_morale_warned := false
var ark_spawned := false
var survivors_data := {}
var crew_members: Array = []
var crew_figures: Array = []
var driver_figure: Node3D   # 主角驾驶位模型（坐姿 + 双手 IK 握方向盘）
var crew_font: SystemFont

var music_a: AudioStreamPlayer
var music_b: AudioStreamPlayer
var music_key := ""
var music_tween: Tween
var sfx: Sfx

var banter_t := 9.0
var banter_busy := false

var _shot_at := -1.0  # --shot=路径 命令行截帧：启动后计时保存并退出
var _shot_path := ""
var _shot_t := 0.0
var _shot_walk := false  # --shotrvwalk：截帧前先进车内行走
var _shot_combat := false  # --shotcombat：截帧前先进下车战斗
var _shot_fps := false     # --fps：配合 --shotcombat 切第一人称截帧
var _shot_credits := false  # --shotcredits：截帧前先打开署名面板
var _shot_cab := false      # --shotcab：截帧前切车内视角看驾驶座
var _shot_cab_cam := false  # --shotcab：截帧专用近距离侧拍驾驶座相机
var _shot_seat := false     # --shotseat：截帧前切车内视角看副驾队友
var _shot_seat_cam := false # --shotseat：截帧专用近距离侧拍副驾相机
var _jump_km := 0.0         # --jump=KM：直达指定里程（配合 --shot 截帧验收）
var _debug_crew := 0        # --crew=N：调试直接补 N 名队友（配合截帧验收座位角色）
var _dump := false          # --dump：截帧时刻打印房车周边节点并退出（验收定位异常物）

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.trim_prefix("--shot=")
			_shot_at = 3.0
		elif a == "--shotrvwalk":
			_shot_walk = true
		elif a == "--shotcombat":
			_shot_combat = true
		elif a == "--fps":
			_shot_fps = true
		elif a == "--shotcredits":
			_shot_credits = true
		elif a == "--shotcab":
			_shot_cab = true
		elif a == "--shotseat":
			_shot_seat = true
		elif a.begins_with("--jump="):
			_jump_km = float(a.trim_prefix("--jump="))
		elif a.begins_with("--crew="):
			_debug_crew = int(a.trim_prefix("--crew="))
		elif a == "--dump":
			_dump = true
			_shot_at = 3.0
	_load_survivors()
	_load_facilities()
	_load_zones()
	_load_world()
	_load_credits()
	_build_sky()
	_build_terrain()
	_build_rv()
	_build_driver()
	_build_camera()
	_build_weather()
	_build_hud()
	_build_music()
	# --crew=N 调试补员：配合截帧验收座位角色
	if _debug_crew > 0:
		for i in _debug_crew:
			var m := _next_crew_member()
			if m.is_empty():
				break
			crew_members.append(m)
			crew += 1
		_sync_crew()
		hud.set_crew(crew_members)
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
	# --jump 直达：同步里程与房车位置，跳过已走过的生成游标，避免一帧补刷全程
	if _jump_km > 0.0:
		var rvz0 := rv.global_position.z
		rv.global_position.z = rvz0 - (_jump_km - dist_km) * KMH_FACTOR
		dist_km = _jump_km
		last_z = rv.global_position.z
		terrain_front = rv.global_position.z + 100.0
		terrain.rebuild(terrain_front)   # jump 后原条带留在原地，必须按新位置重建
		obs_z = rv.global_position.z - 30.0
		pick_z = rv.global_position.z - 20.0
		surv_z = rv.global_position.z - 180.0
		lamp_z = rv.global_position.z - 30.0
		scenery_z = rv.global_position.z - 20.0
		pole_z = rv.global_position.z - 40.0
		_pole_prev.clear()
		# 支路游标对齐 -n*JUNCTION_EVERY 绝对网格（与 terrain 支路条带同源，不可随 rvz 偏移）
		_detour_z = -float(maxi(int(ceil(-(rv.global_position.z - 30.0) / JUNCTION_EVERY)), 1)) * JUNCTION_EVERY
		while _place_idx < _places.size() and float(_places[_place_idx].get("km", 0.0)) <= _jump_km:
			_place_idx += 1
		while _place_sign_idx < _places.size() and float(_places[_place_sign_idx].get("km", 0.0)) - 1.5 <= _jump_km:
			_place_sign_idx += 1
		# 小聚落游标同步（带 180m 预告牌提前量，跳过牌身位已在身后的点）
		while _hamlet_km > 0.0 and _hamlet_km - DETOUR_SIGN_LEAD / KMH_FACTOR <= _jump_km:
			_hamlet_km = _next_hamlet_km(_hamlet_km)

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
	_update_bullets(delta)
	# 驻车自动刹车：停稳即完成驻车（复用正常驻车路径）
	if _park_brake and rv.speed_kmh <= 0.5:
		_park_brake = false
		_toggle_park()
	_update_frontier()
	_recycle_world()
	# 终点前 8km 方舟营地进入视野
	if not ark_spawned and dist_km >= GOAL_KM - 8.0:
		ark_spawned = true
		_spawn_ark_camp()
	hit_cd = maxf(0.0, hit_cd - delta)
	bite_cd = maxf(0.0, bite_cd - delta)
	# 撞飞的残骸落到当地地面后冻结留作路障（平面碰撞只有最低海拔，高海拔段会沉穿）
	for i in range(_wrecks.size() - 1, -1, -1):
		var w = _wrecks[i]
		if not is_instance_valid(w):
			_wrecks.remove_at(i)
		elif w.global_position.y <= ground_height(w.global_position.x, w.global_position.z) + 0.35:
			w.freeze = true
			_wrecks.remove_at(i)

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

func _load_credits() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/credits.json"))
	if parsed is Dictionary:
		credits_data = parsed

func _load_zones() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/terrain_zones.json"))
	if parsed is Dictionary:
		_zones = parsed.get("zones", [])
		for zn in _zones:
			_zones_total += float(zn.get("len", 400.0))

func _load_world() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	if parsed is Dictionary:
		_world_seed = int(parsed.get("world_seed", 1))
		_places = parsed.get("places", [])
		_detours = parsed.get("detours", [])
		_hamlet_cfg = parsed.get("hamlets", {})
		if not _hamlet_cfg.is_empty():
			var kr: Array = _hamlet_cfg.get("km_range", [3.0, 5.0])
			_hamlet_km = lerpf(float(kr[0]), float(kr[1]), _jh(31))

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
	if _shot_at > 0.0:
		_shot_t += delta
		if _shot_t >= _shot_at:
			_shot_at = -1.0
			if _dump:
				_dump_nodes()
				get_tree().quit()
				return
			if story != null and story.active:
				story.active = false
				story_active = false
				hud.hide_story()
			if _shot_walk and not rv_walk_active:
				# --shotrvwalk：先驻车再起身车内行走，稳定 1.5s 后截帧
				_shot_walk = false
				parked = true
				rv.parked = true
				rv.speed_kmh = 0.0
				set_facilities_ui(false)
				start_rv_walk()
				_shot_at = 1.5
				_shot_t = 0.0
				return
			if _shot_combat and not combat_active:
				# --shotcombat：先驻车再下车战斗，稳定 1.5s 后截帧
				_shot_combat = false
				parked = true
				rv.parked = true
				rv.speed_kmh = 0.0
				set_facilities_ui(false)
				start_combat(0)
				if _shot_fps:
					get_player_body().toggle_fps()
				_shot_at = 1.5
				_shot_t = 0.0
				return
			if _shot_credits:
				# --shotcredits：打开署名面板，稳定 1.5s 后截帧
				_shot_credits = false
				hud.set_credits_visible(true)
				_shot_at = 1.5
				_shot_t = 0.0
				return
			if _shot_cab:
				# --shotcab：切车内视角看驾驶座，稳定 1.5s 后截帧
				_shot_cab = false
				view_mode = 2
				_shot_cab_cam = true
				_shot_at = 1.5
				_shot_t = 0.0
				return
			if _shot_seat:
				# --shotseat：切车内视角看副驾队友，稳定 1.5s 后截帧
				_shot_seat = false
				view_mode = 2
				_shot_seat_cam = true
				_shot_at = 1.5
				_shot_t = 0.0
				return
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_shot_path)
			get_tree().quit()
			return
	if rv == null:
		return
	_update_music()
	sfx.set_engine(clampf(rv.speed_kmh / 55.0, 0.0, 1.0))
	# G：驻车时下车战斗 / 战斗中回到驾驶座（player.gd 内部也处理结束）
	var gk := Input.is_physical_key_pressed(KEY_G)
	if gk and not _g_down and not game_over and not story_active:
		if combat_active:
			end_combat()
		elif rv_walk_active:
			end_rv_walk()
		elif parked:
			start_combat(0)
	_g_down = gk
	# Q：车内行走（驻车起身 / 有队友时行驶中代驾巡航）；驻车行走中 Q 仅提示出发方式
	var qk := Input.is_physical_key_pressed(KEY_Q)
	if qk and not _q_down and not game_over and not story_active and not combat_active:
		if rv_walk_active:
			if parked:
				hud.toast("驻车休整中 · 按驻车键出发")
			else:
				end_rv_walk()
		else:
			start_rv_walk()
	_q_down = qk
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
	# 驻车（F）与设施（E）：车内行走时也必须响应（驻车键=出发），故在行走提前 return 之前读
	var f := Input.is_physical_key_pressed(KEY_F)
	if f and not _f_down and not game_over:
		_toggle_park()
	_f_down = f
	var e := Input.is_physical_key_pressed(KEY_E)
	if e and not _e_down and parked and not game_over:
		set_facilities_ui(not facilities_visible)
	_e_down = e
	if rv_walk_active:
		# 车内行走：相机由玩家节点接管，显隐在 start/end 里一次性设好
		return
	var pressed := Input.is_physical_key_pressed(KEY_C)
	if pressed and not _c_down:
		view_mode = (view_mode + 1) % 3
		_fv_yaw = 0.0
		_fv_pitch = 0.0
	_c_down = pressed
	# 追尾视角只看 GLB 车壳；车内/驾驶舱视角隐藏车壳、显示程序化内饰与队友
	rv_model.visible = view_mode == 0
	interior.visible = view_mode != 0
	for i in crew_figures.size():
		crew_figures[i].visible = view_mode == 2 and i < crew_members.size()
	if driver_figure != null:
		driver_figure.visible = view_mode == 2 and not combat_active
	_update_banter(delta)
	if view_mode == 1:
		cam.global_position = rv.to_global(Vector3(-0.55, 1.2, -1.9))
		cam.look_at(rv.to_global(Vector3(-0.55, 0.9, -30.0)))
		cam.fov = 72.0
	elif view_mode == 2:
		# 后铺上方俯拍：餐桌当前景，灶台/货架队友为中景，副驾在车头；后移+抬视线+宽 fov 保证后舱两人完整入镜
		cam.global_position = rv.to_global(Vector3(0.0, 1.66, 2.6))
		# 自由视角：按住右键拖动环顾舱内（默认朝车头的略俯视线为基准）
		var base_dir := Vector3(0.0, -0.148, -0.989)
		var look_dir := Basis(Vector3.UP, _fv_yaw) * Basis(Vector3.RIGHT, _fv_pitch) * base_dir
		cam.look_at(cam.global_position + rv.global_transform.basis * look_dir * 5.0, Vector3.UP)
		cam.fov = 72.0
		if _shot_cab_cam:
			# --shotcab：主驾正侧面近拍，验收坐姿穿模
			cam.global_position = rv.to_global(Vector3(0.5, 0.95, -2.85))
			cam.look_at(rv.to_global(Vector3(-0.55, 0.5, -2.85)), Vector3.UP)
			cam.fov = 55.0
		if _shot_seat_cam:
			# --shotseat：副驾正侧面近拍，验收座位队友
			cam.global_position = rv.to_global(Vector3(-0.5, 0.95, -2.85))
			cam.look_at(rv.to_global(Vector3(0.55, 0.5, -2.85)), Vector3.UP)
			cam.fov = 55.0
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

## 车内自由视角：PC 按住右键拖动 / 手机单指拖动环顾（不捕获鼠标，左键仍可点设施 UI）
func _unhandled_input(event: InputEvent) -> void:
	if view_mode != 2 or rv_walk_active:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_fv_yaw -= event.relative.x * 0.0032
		_fv_pitch = clampf(_fv_pitch - event.relative.y * 0.0032, -0.9, 0.75)
	elif event is InputEventScreenDrag:
		_fv_yaw -= event.relative.x * 0.005
		_fv_pitch = clampf(_fv_pitch - event.relative.y * 0.005, -0.9, 0.75)

## 驻车休整：按一下即可——超速时自动重刹，停稳即驻车；车内行走中按 F 回驾驶座；在驾驶座再按 F 出发
func _toggle_park() -> void:
	if story_active:
		return   # 剧情弹窗期间不响应：防止 parked 隐形翻转（start_rv_walk 会被 story 拦截）
	if _park_brake:
		return   # 自动刹车中：停稳自动完成驻车（不允许取消，连按 F 不会误退出刹车）
	if rv_walk_active:
		if not parked:
			# 代驾巡航中按驻车键 = 驻车：超速先自动刹车（停稳后经 _park_brake 闭环回本分支），低速立即停稳
			if rv.speed_kmh > 6.0:
				_park_brake = true
				hud.toast("自动刹车中，停稳即驻车")
			else:
				parked = true
				rv.parked = true
				rv.speed_kmh = 0.0
				_starving = false
				set_facilities_ui(true)
				hud.toast("已驻车 · 再按驻车键出发")
			return
		end_rv_walk()   # 驻车行走中按驻车键 = 回驾驶座保持驻车（不直接出发，防误触闪退）
		hud.toast("已回驾驶座 · 再按驻车键出发")
		return
	if not parked:
		if rv.speed_kmh > 6.0:
			_park_brake = true
			hud.toast("自动刹车中，停稳即驻车")
			return
		parked = true
		rv.parked = true
		rv.speed_kmh = 0.0
		_starving = false
		start_rv_walk()   # 主角起身，驾驶位空出（起身 toast 含走动/设施/出发提示）
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
	if act.has("fx_food"):
		var crops: Array = act["fx_food"]
		food += float(crops[lv])
		hud.toast("收获了一箱速生菜，食物 +%d" % int(crops[lv]))
	if act.has("fx_parts"):
		var scraps: Array = act["fx_parts"]
		parts += float(scraps[lv])
		hud.toast("拆出能用的零件，零件 +%d" % int(scraps[lv]))
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
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.08
	# 画质：SSAO 接触阴影 + SSIL 间接光反弹 + 微色彩校正，提升立体感与通透度
	environment.ssao_enabled = true
	environment.ssil_enabled = true
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.06
	environment.adjustment_contrast = 1.04
	self.env = environment
	get_viewport().world_3d.environment = environment
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.light_energy = 1.75
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
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
				var nx := road_x(nz) + randf_range(-5.5, 5.5)
				p.global_position = Vector3(nx, ground_height(nx, nz) + 0.012, nz)
			else:
				var side := 1.0 if randf() > 0.5 else -1.0
				# 按生成时记录的横向距离带重放：高楼永远 105m 外，不会被回收贴到路边
				var band: Vector2 = p.get_meta("x_band", Vector2(ROAD_HALF + 3.0, ROAD_HALF + 29.0))
				var nx: float = road_x(nz) + side * randf_range(band.x, band.y)
				p.global_position = Vector3(
					nx,
					ground_height(nx, nz) + float(p.get_meta("y_off", 0.0)),
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
	# 装甲裙边/后保险杠比车壳宽一圈且颜色不搭，斜上方看像穿模，直接隐藏
	for n in rv_model.find_children("*skirt*", "Node3D", true, false) + rv_model.find_children("*bumper*", "Node3D", true, false):
		n.visible = false
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

## 驾驶舱 + 生活舱共用的精模内饰（仅车内/驾驶舱视角可见）
func _build_interior() -> void:
	# 精模内饰 GLB（Blender 建模，rv 本地空间：地板顶 y=-0.4、车头 -Z）；队友站位兼容见 _build_crew
	interior = RV_INTERIOR_SCENE.instantiate()
	interior.name = "Interior"
	# GLB 里 steer_col 生成的 StaticBody 与房车碰撞盒重叠会把车头顶走：内饰纯装饰，剥掉物理体
	for n in interior.find_children("*", "CollisionObject3D", true, false):
		n.free()  # 未入树，立即删除避免延迟一帧的推挤
	rv.add_child(interior)
	# 舱内暖色小灯：夜间/雾天也能看清仪表台与舱内
	var cab_light := OmniLight3D.new()
	cab_light.light_color = Color(1.0, 0.82, 0.6)
	cab_light.light_energy = 1.5
	cab_light.omni_range = 8.0
	cab_light.position = Vector3(0, 1.85, 0.4)
	interior.add_child(cab_light)
	# 内饰 GLB 座椅建模位置距方向盘约 1.7m（建模缺陷）：双排座椅整体前移 1.27m 贴向仪表台（坐垫中心 -1.5 → -2.77）
	for sn in ["seat_c0", "seat_c1", "seat_b0", "seat_b1", "headrest0", "headrest1"]:
		var seat_mesh: Node3D = interior.find_child(sn, true, false)
		if seat_mesh != null:
			seat_mesh.position.z -= 1.27

## 车内视角的队友：副驾坐姿、其余站姿，各自在灶台/货架/餐桌/后铺忙碌
func _build_crew() -> void:
	crew_font = SystemFont.new()
	crew_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "sans-serif"])
	# [本地坐标, 朝向, 是否坐姿]；GLB 正面朝 +Z，副驾朝车头(-Z)故转 180°
	# 地板顶面 y=-0.4：所有站位 root 均落地板；坐姿髋部下沉约 0.44，落在坐垫顶(y=0.0)上
	var stations := [
		# sit 动画髋部在 root 后方约 0.324：副驾 root 需再靠前 0.33，髋才落在坐垫(z -3.04..-2.50)后 1/3 处
		[Vector3(0.55, -0.4, -3.18), PI, true],          # 副驾（坐姿朝车头，首位队友；座椅已前移贴方向盘）
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
		# 坐姿头顶(rv 本地)约 0.79，名牌 1.30 悬顶 0.5 内不穿挡风；站姿头顶约 1.6，用 1.72
		lb.position = Vector3(0, 1.30 if st[2] else 1.72, 0)
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

## 主角驾驶位：hero 坐主驾播 drive 动画（坐姿+双手握方向盘已烘焙，仅车内视角可见）
func _build_driver() -> void:
	var fig := Node3D.new()
	# 主驾坐垫后部（座椅已前移贴方向盘：坐垫 z -3.04..-2.50）；drive 动画髋部已前移 13cm 够到方向盘
	fig.position = Vector3(-0.55, -0.42, -2.85)
	fig.rotation.y = PI  # 朝车头
	var lb := Label3D.new()
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.font = crew_font
	lb.font_size = 26
	lb.pixel_size = 0.0016
	lb.outline_size = 10
	lb.no_depth_test = false
	lb.modulate = Color(1.0, 0.93, 0.84)
	lb.position = Vector3(0, 1.35, 0)
	lb.text = "我 · 驾驶中"
	fig.add_child(lb)
	var char: Node3D = CharUtil.instantiate("hero", "drive")["node"]
	char.name = "Char"
	fig.add_child(char)
	fig.visible = false
	rv.add_child(fig)
	driver_figure = fig

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
	# 刷在车前 12~90m：保持在无雾视野内，远处太散既看不见也构不成威胁
	var base_z := rvz - 12.0 - randf() * 78.0
	for i in count:
		var zz := base_z - i * randf_range(3.0, 10.0)
		# 65% 在道路附近（行驶主威胁），35% 散布到两侧野地（最远约 35m，作氛围）
		var off: float
		if randf() < 0.65:
			off = (randf() - 0.5) * 13.0
		else:
			var side2 := 1.0 if randf() > 0.5 else -1.0
			off = side2 * randf_range(ROAD_HALF + 3.0, 35.0)
		var body := _make_zombie_body()
		body.position = Vector3(road_x(zz) + off, GROUND_Y + 0.5, zz)
		add_child(body)
		body.setup(self)
		zombies.append(body)

## 创建一只丧尸实体（胶囊碰撞 + Quaternius 模型随机缩放）；位置与 AI 目标由调用者设置
func _make_zombie_body() -> RigidBody3D:
	var body := RigidBody3D.new()
	body.set_script(ZOMBIE_SCRIPT)
	body.name = "Zombie"
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.4
	col.shape = cap
	col.position.y = 0.7
	body.add_child(col)
	# 三种丧尸混编：精致写实(ripper) 30% / 蓝胖 28% / 绿瘦 42%
	var roll := randf()
	var model: Node3D = (ZMB_SCENE_R if roll < 0.3 else (ZMB_SCENE_G if roll < 0.58 else ZMB_SCENE)).instantiate()
	# Quaternius 模型按真实米数建模（站立约 2m），随机缩放保持体型差异
	model.scale = Vector3.ONE * randf_range(0.75, 0.9)
	body.add_child(model)
	return body

## 玩家下车后的角色实体（战斗系统启用；在车内时为 null，丧尸追车）
var player_body: Node3D = null
## 下车协同作战的队友实体（仅 ground 下车模式生成，回车回收）
var mates: Array = []

func get_player_body() -> Node3D:
	return player_body if is_instance_valid(player_body) else null

## 枪声/爆炸：全向惊动周围游荡丧尸进入狂暴
func alert_gunshot(pos: Vector3) -> void:
	for z in zombies:
		if is_instance_valid(z):
			z.on_hear_gunshot(pos)

## 玩家被啃咬（下车战斗时）：全局冷却，转发伤害给玩家
func on_player_bitten() -> void:
	if game_over or bite_cd > 0.0 or rv_walk_active:
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
	if combat_active or rv_walk_active or game_over or story_active:
		return
	if m == 0 and not parked:
		hud.toast("先按 F 驻车才能下车")
		return
	# 下车/探天窗前收起驻车设施面板，免得挡住战斗操作；end_combat 里按 parked 恢复
	set_facilities_ui(false)
	var p := CharacterBody3D.new()
	p.set_script(PLAYER_SCRIPT)
	if m == 0:
		# 左车门旁落地
		p.position = rv.global_position + rv.global_transform.basis.x * 2.4 + Vector3(0, -RV_MODEL_FOOT, 0.0)
		p.position.y = ground_height(p.position.x, p.position.z)
	else:
		# 车顶天窗：脚踩实测车壳顶面（to_global 含行驶俯仰，不再悬空）
		p.position = rv.to_global(Vector3(0, RV_ROOF_Y, 0.2))
	p.setup(self, m)
	add_child(p)
	player_body = p
	combat_active = true
	rv.combat_in = true
	p.aim_yaw = rv.rotation.y
	p.aim_pitch = -0.32
	# 第三人称战斗：强制显示车壳、隐藏内饰与队友，退出时由视图模式恢复
	rv_model.visible = true
	interior.visible = false
	for f in crew_figures:
		f.visible = false
	if driver_figure != null:
		driver_figure.visible = false
	p._enter()
	# 下车模式：全队队友下车协同作战（天窗模式身体探出车顶，队友留车内）
	if m == 0:
		for i in crew_members.size():
			var mate := Node3D.new()
			mate.set_script(MATE_SCRIPT)
			mate.setup(crew_members[i].get("id", ""), i)
			mate.position = p.position + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
			mate.position.y = ground_height(mate.position.x, mate.position.z)
			add_child(mate)
			mates.append(mate)
	hud.toast("天窗射击：鼠标瞄准 · 左键开火 · G/T 返回" if m == 1 else "下车战斗：WASD 移动 · 鼠标瞄准 · 左键开火 · 队友协同作战 · G 返回车内")

func end_combat() -> void:
	if not combat_active:
		return
	var p := get_player_body()
	if p != null:
		p._exit()
		p.queue_free()
	player_body = null
	for mate in mates:
		if is_instance_valid(mate):
			mate.queue_free()
	mates.clear()
	combat_active = false
	rv.combat_in = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cam.make_current()
	# 恢复当前视图模式下的车壳/内饰/队友显隐
	rv_model.visible = view_mode == 0
	interior.visible = view_mode != 0
	for i in crew_figures.size():
		crew_figures[i].visible = view_mode == 2 and i < crew_members.size()
	if driver_figure != null:
		driver_figure.visible = view_mode == 2
	# 驻车状态下恢复设施面板（start_combat 时收起了）
	if parked:
		set_facilities_ui(true)

# ---------- 车内行走 ----------
## Q/「车内」按钮：驻车起身车内转；有队友时行驶中也可（首位队友挪到主驾代驾，定速巡航）
func start_rv_walk() -> void:
	if rv_walk_active or combat_active or game_over or story_active:
		return
	if _park_brake:
		hud.toast("自动刹车中，停稳再起身")
		return
	if not parked and crew_members.is_empty():
		hud.toast("行驶中需要队友代驾才能起身走动（先招募幸存者）")
		return
	set_facilities_ui(false)
	var p := CharacterBody3D.new()
	p.set_script(PLAYER_SCRIPT)
	p.setup(self, 2)   # Mode.RV_WALK
	p.position = Vector3(0.0, -0.4, -1.2)   # 驾驶座旁起身点（rv 本地，地板顶 y=-0.4）
	rv.add_child(p)
	player_body = p
	rv_walk_active = true
	view_mode = 2
	rv_model.visible = false
	interior.visible = true
	for i in crew_figures.size():
		crew_figures[i].visible = i < crew_members.size()
	if driver_figure != null:
		driver_figure.visible = false   # 主角起身，驾驶位空出
	if not parked:
		# 队友代驾：首位队友（副驾坐姿）挪到主驾位
		crew_figures[0].position = Vector3(-0.55, -0.4, -2.85)
	p.aim_yaw = 0.0    # 面朝车头（车内 -Z）
	p.aim_pitch = 0.0
	p._enter()
	if not p.fps:
		p.toggle_fps(true)
	hud.set_drive_buttons_visible(false)
	if parked:
		# 驻车起身：出发走驻车键，不再提示回驾驶座
		if DisplayServer.is_touchscreen_available():
			hud.toast("已起身 · 左下摇杆走动 · 拖动屏幕环顾 · 设施键操作 · 驻车键出发")
		else:
			hud.toast("已起身 · WASD 走动 · 右键拖动环顾 · E 设施 · F 出发")
	elif DisplayServer.is_touchscreen_available():
		hud.toast("车内行走：左下摇杆移动 · 拖动屏幕环顾 · 车内键回驾驶座")
	else:
		hud.toast("车内行走：WASD 移动 · 鼠标环顾 · Q 回驾驶座")

func end_rv_walk() -> void:
	if not rv_walk_active:
		return
	var p := get_player_body()
	if p != null:
		p._exit()
		p.queue_free()
	player_body = null
	rv_walk_active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cam.make_current()
	if not parked and not crew_members.is_empty():
		# 代驾结束：队友挪回副驾位
		crew_figures[0].position = Vector3(0.55, -0.4, -2.85)
	# 回驾驶座：驻车回车内视角，行驶回追尾视角
	view_mode = 2 if parked else 0
	rv_model.visible = true
	interior.visible = false
	for f in crew_figures:
		f.visible = false
	if driver_figure != null:
		driver_figure.visible = false
	hud.set_drive_buttons_visible(not parked)
	if parked:
		set_facilities_ui(true)

## 天窗模式：玩家身体每帧锚在行驶中的车顶
func _sync_player_to_rv(_delta: float) -> void:
	var p := get_player_body()
	if p == null or p.mode != 1:
		return
	p.position = rv.to_global(Vector3(0, RV_ROOF_Y, 0.2))
	p.velocity = Vector3.ZERO

func on_zombie_shot(killed := true, headshot := false) -> void:
	hud.flash_hit_marker(killed, headshot)

func on_player_dead() -> void:
	end_combat()
	_do_game_over()

## 枪口火光：自发光短寿命点光
func spawn_muzzle_flash(muzzle_ws: Vector3) -> void:
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.78, 0.42)
	flash.light_energy = 6.0
	flash.omni_range = 9.0
	flash.position = muzzle_ws
	add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.09)
	tw.tween_callback(flash.queue_free)

# ---------- 实弹弹道 ----------
## 弹丸按真实弹速飞行：扫掠射线防穿透、重力下坠、曳光长亮条，命中延迟结算
var _bullets: Array = []

## 发射一发实弹（exclude：不参与的碰撞 RID，如射手自身与房车）
func spawn_bullet(from: Vector3, dir: Vector3, speed: float, exclude: Array, dmg := 1.0) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = from
	root.look_at(from + dir, Vector3.UP)
	# 曳光杆：-Z 朝飞行方向，杆身拖在弹头后方
	var trail := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var trail_len := clampf(speed * 0.0025, 0.7, 2.2)
	bm.size = Vector3(0.03, 0.03, trail_len)
	trail.mesh = bm
	trail.material_override = _emis_mat(Color(1.0, 0.85, 0.5), 4.0)
	trail.position.z = trail_len * 0.5
	root.add_child(trail)
	_bullets.append({
		"vel": dir.normalized() * speed,
		"pos": from,
		"dist": 120.0,
		"exclude": exclude,
		"dmg": dmg,
		"node": root,
	})

func _update_bullets(delta: float) -> void:
	if _bullets.is_empty():
		return
	var space := get_world_3d().direct_space_state
	for i in range(_bullets.size() - 1, -1, -1):
		var b: Dictionary = _bullets[i]
		var step: Vector3 = b["vel"] * delta
		var q := PhysicsRayQueryParameters3D.create(b["pos"], b["pos"] + step)
		q.collide_with_areas = false
		q.exclude = b["exclude"]
		var hit := space.intersect_ray(q)
		if hit:
			_bullet_impact(hit, b["dmg"], b["vel"].normalized())
			b["node"].queue_free()
			_bullets.remove_at(i)
			continue
		b["pos"] += step
		b["vel"].y -= 9.8 * delta
		b["dist"] -= step.length()
		var node: Node3D = b["node"]
		node.global_position = b["pos"]
		node.look_at(b["pos"] + b["vel"].normalized(), Vector3.UP)
		if b["dist"] <= 0.0:
			node.queue_free()
			_bullets.remove_at(i)

## 命中结算：丧尸中弹（命中点过肩算爆头 ×2）+ 命中点火花
func _bullet_impact(hit: Dictionary, dmg: float, dir: Vector3) -> void:
	var col: Object = hit["collider"]
	if col is RigidBody3D and col.has_method("on_shot"):
		var headshot: bool = hit["position"].y > col.global_position.y + 0.75
		on_zombie_shot(col.on_shot(dmg, headshot, dir), headshot)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.8, 0.45)
	flash.light_energy = 2.5
	flash.omni_range = 4.0
	flash.position = hit["position"] + Vector3(0, 0.06, 0)
	add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.08)
	tw.tween_callback(flash.queue_free)

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
		_wseed(obs_z, 1)
		_spawn_obstacle(obs_z)
		obs_z -= randf_range(32.0, 68.0)
	while pick_z > rvz - VIEW_AHEAD:
		if pick_z < safe_z:
			pick_z = safe_z - 1.0
			break
		_wseed(pick_z, 2)
		_spawn_pickup(pick_z)
		pick_z -= randf_range(30.0, 70.0)
	while surv_z > rvz - VIEW_AHEAD:
		if surv_z < safe_z:
			surv_z = safe_z - 1.0
			break
		_wseed(surv_z, 3)
		_spawn_survivor(surv_z)
		surv_z -= randf_range(250.0, 450.0)
	while lamp_z > rvz - VIEW_AHEAD:
		if lamp_z < safe_z:
			lamp_z = safe_z - 1.0
			break
		_wseed(lamp_z, 4)
		_spawn_lamp(lamp_z)
		lamp_z -= 55.0
	while scenery_z > rvz - VIEW_AHEAD:
		if scenery_z < safe_z:
			scenery_z = safe_z - 1.0
			break
		_wseed(scenery_z, 5)
		_spawn_scenery(scenery_z)
		scenery_z -= 12.0
	while sign_z > rvz - VIEW_AHEAD:
		if sign_z < safe_z:
			sign_z = safe_z - 1.0
			break
		_spawn_milepost(sign_z)
		sign_z -= 50.0 * KMH_FACTOR
	while pole_z > rvz - VIEW_AHEAD:
		if pole_z < safe_z:
			pole_z = safe_z - 1.0
			_pole_prev.clear()
			break
		_wseed(pole_z, 7)
		_spawn_pole(pole_z)
		pole_z -= 48.0
	# 可探索支路：哈希命中（与 junctions_in 同式）+ _jh(n+5000) 再筛——尽头 POI + 岔口前 180m 锈牌
	# 游标保持网格对齐：safe_z 截断时只 break 不改 _detour_z（车抵近终点后每帧一次空检查，无开销）
	while _detour_z > rvz - VIEW_AHEAD - DETOUR_SIGN_LEAD:
		if _detour_z < safe_z:
			break
		var dn := int(round(-_detour_z / JUNCTION_EVERY))
		if dn >= 1 and _jh(dn) <= 0.75 and _jh(dn + 2000) >= 0.28 and _jh(dn + 5000) < 0.35:
			_spawn_detour(dn, _detour_z)
		_detour_z -= JUNCTION_EVERY
	# 聚落预告牌：town/gas 地点前 1.5km 路右立"前方 X 出口"绿牌（高速惯例，提前减速）
	while _place_sign_idx < _places.size():
		var sp: Dictionary = _places[_place_sign_idx]
		var st := String(sp.get("type", ""))
		var sz: float = rvz - (float(sp.get("km", 0.0)) - 1.5 - dist_km) * KMH_FACTOR
		if sz <= rvz - VIEW_AHEAD:
			break
		if st == "town" or st == "gas":
			_place_sign("前方 " + String(sp.get("name", "")) + " 1.5km", sz)
		_place_sign_idx += 1
	# 沿途聚落：按 data/world.json 固定里程生成
	while _place_idx < _places.size():
		var p: Dictionary = _places[_place_idx]
		var pz: float = rvz - (float(p.get("km", 0.0)) - dist_km) * KMH_FACTOR
		if pz <= rvz - VIEW_AHEAD:
			break
		_spawn_place(p, pz)
		_place_idx += 1
	# 小聚落填充：每 3-5km 一处（确定性），避开剧情地点 ±2.5km 与终点区
	while _hamlet_km > 0.0 and _hamlet_km < 664.0:
		var hz: float = rvz - (_hamlet_km - dist_km) * KMH_FACTOR
		if hz <= rvz - VIEW_AHEAD:
			break
		if not _hamlet_near_place(_hamlet_km):
			_spawn_hamlet(hz)
		_hamlet_km = _next_hamlet_km(_hamlet_km)
	# 清理身后
	for s in get_children():
		if s.is_in_group("consumable") and s.global_position.z > rvz + 40.0:
			s.queue_free()

## 按世界坐标派生种子：同一路段无论何时经过，生成结果完全一致（与调用顺序无关）
func _wseed(z: float, salt: int) -> void:
	seed(_world_seed + int(z * 16.0) + salt * 7919)

## --dump 调试：打印房车周边节点（name/位置），headless 跑 --jump=KM --dump 定位异常物
func _dump_nodes() -> void:
	# 只列 main 直接子节点（生成物都挂在 main 下），避免递归遍历 GLB 子树卡死
	var rp: Vector3 = rv.global_position
	for n in get_children():
		var n3 := n as Node3D
		if n3 == null:
			continue
		if n3 == terrain:
			# 地形逐 surface 打 AABB（全局），定位异常高几何
			for si in terrain.mesh.get_surface_count():
				var vs: PackedVector3Array = terrain.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
				var mn := Vector3(INF, INF, INF)
				var mx := Vector3(-INF, -INF, -INF)
				for v in vs:
					mn = mn.min(v)
					mx = mx.max(v)
				printt("TERR surf", si, "size", (mx - mn).round(), "min", mn.round(), "max", mx.round())
			continue
		var gp: Vector3 = n3.global_position
		if absf(gp.x - rp.x) < 800.0 and absf(gp.z - rp.z) < 900.0:
			var wa: AABB = n3.global_transform * _merged_aabb(n3)
			if wa.size.y > 8.0:
				var src: String = n3.scene_file_path
				var kids: Array = n3.get_children()
				var k0: String = "(leaf)"
				if not kids.is_empty():
					k0 = "%s/%s" % [(kids[0] as Node).name, (kids[0] as Node).get_class()]
				printt("TALL", n3.name, n3.get_class(), "pos", gp.round(), "size", wa.size.round(), "top_y", snappedf(wa.position.y + wa.size.y, 0.1), "src", src, "k0", k0, "grp", n3.get_groups())
				# 打印子树各部件的网格与局部坐标，识别生成器结构
				if wa.size.y > 30.0:
					for c in n3.get_children():
						var mi := c as MeshInstance3D
						if mi != null and mi.mesh != null:
							printt("  PART", mi.name, mi.mesh.get_class(), "lpos", mi.position.round(), "maabb", mi.get_aabb().size.round())

## 前方最近的 n 个地点：[[名字, 剩余 km], …]，HUD 旅程条用
func next_places(n: int) -> Array:
	var out: Array = []
	for p in _places:
		var remain: float = float(p.get("km", 0.0)) - dist_km
		if remain > -0.2:
			out.append([String(p.get("name", "")), maxf(remain, 0.0)])
			if out.size() >= n:
				break
	return out

## 沿途聚落（data/world.json）：按类型生成 + 路口立高速名牌
func _spawn_place(p: Dictionary, z: float) -> void:
	_wseed(z, 8)
	match String(p.get("type", "")):
		"town":
			_town(z, _place_junction(p))
		"gas":
			_gas_station(z, _place_junction(p))
		"camp":
			_camp(z)
		"landmark":
			_landmark_rock(z)
	# 到达牌立支路对侧，避免遮挡岔口
	var pj := _place_junction(p)
	_place_sign(String(p.get("name", "")), z, -float(pj["side"]) if not pj.is_empty() else 1.0)

## 小镇：支路（_place_junction）斜出主路，楼群沿支路后半段两侧排开，车可一路开进镇中心
func _town(z: float, pj: Dictionary) -> void:
	var side := float(pj["side"])
	var dir := Vector3(side * sin(pj["ang"]), 0, -cos(pj["ang"])).normalized()
	var perp := Vector3(-dir.z, 0, dir.x)
	var org := Vector3(road_x(z) + side * (ROAD_HALF - 0.8), 0, z)
	var len := float(pj["len"])
	var n := 4 + randi() % 3
	for i in range(n):
		var sd := 1.0 if i % 2 == 0 else -1.0
		var bp: Vector3 = org + dir * (len * randf_range(0.5, 1.1)) + perp * (sd * randf_range(16.0, 24.0))
		# 废墟楼体宽（半宽可达 15m）：距主路 25m 内翻到支路另一侧，仍压路则舍弃
		if absf(bp.x - road_x(bp.z)) < 25.0:
			bp = org + dir * (len * randf_range(0.5, 1.1)) + perp * (-sd * randf_range(16.0, 24.0))
		if absf(bp.x - road_x(bp.z)) < 25.0:
			continue
		_place_scenery(BUILDING_SCENE, bp.x, bp.z, randf_range(8.0, 13.0))
	for i in range(2):
		var jp: Vector3 = org + dir * (len * randf_range(0.9, 1.15)) + perp * (_side() * randf_range(5.5, 8.0))
		_place_scenery(JUNK_SCENE, jp.x, jp.z, randf_range(2.4, 3.2))
	# 镇内探索：楼间搜刮箱 + 丧尸巡逻
	_loot_and_zombies(org + dir * (len * 0.75), 15.0, 2 + randi() % 2, 3 + randi() % 4)

## 聚落可探索内容：c 个搜刮箱（walkable 步行可拾取，×2.5 奖励）+ zn 只丧尸，散布 center 半径 r 内
func _loot_and_zombies(center: Vector3, r: float, c: int, zn: int) -> void:
	for i in range(c):
		var kp: Vector3 = center + Vector3(randf_range(-r, r), 0, randf_range(-r, r))
		_loot_box(kp.x, kp.z)
	for i in range(zn):
		var zp: Vector3 = center + Vector3(randf_range(-r, r), 0, randf_range(-r, r))
		var zb := _make_zombie_body()
		zb.position = Vector3(zp.x, ground_height(zp.x, zp.z) + 0.5, zp.z)
		add_child(zb)
		zb.setup(self)
		zombies.append(zb)

## 单个搜刮箱（聚落门口等精准点位用；随机 roll 物资类型）
func _loot_box(x: float, z: float) -> void:
	var p := Node3D.new()
	p.set_script(PICKUP_SCRIPT)
	p.add_to_group("consumable")
	p.add_to_group("pickup")
	var roll := randf()
	p.kind = "fuel" if roll < 0.35 else ("food" if roll < 0.7 else "repair")
	p.walkable = true
	p.boost = 2.5
	p.position = Vector3(x, ground_height(x, z), z)
	add_child(p)

## 下一个小聚落里程：km_range 内确定性随机步进
func _next_hamlet_km(km: float) -> float:
	var kr: Array = _hamlet_cfg.get("km_range", [3.0, 5.0])
	return km + lerpf(float(kr[0]), float(kr[1]), _jh(int(km * 16.0) + 43))

## 是否与剧情地点太近（±avoid_place_km 内避让）
func _hamlet_near_place(km: float) -> bool:
	var avoid := float(_hamlet_cfg.get("avoid_place_km", 2.5))
	for p in _places:
		if absf(float(p.get("km", 0.0)) - km) < avoid:
			return true
	return false

## 小聚落分派：按景观带选镇/村/景区，立预告牌（确定性）
func _spawn_hamlet(z: float) -> void:
	_wseed(z, 11)
	var zone := zone_at(z)
	if zone == "city":
		return  # 城区楼群已密，不再叠小镇
	var kind := "town"
	var roll := randf()
	if zone == "lake" or zone == "coast" or zone == "mountain":
		kind = "scenic" if roll < 0.55 else "town"
	elif zone == "plain":
		kind = "village" if roll < 0.5 else "town"
	else:  # forest / hills
		kind = "scenic" if roll < 0.2 else ("village" if roll < 0.55 else "town")
	var pool: Array = _hamlet_cfg.get("names_" + kind, [])
	if pool.is_empty():
		return
	var hname := String(pool[randi() % pool.size()])
	var side := _side()
	if kind == "town":
		_hamlet_town(z)
	elif kind == "village":
		_hamlet_village(z, side)
	else:
		_hamlet_scenic(z, side)
	# 预告牌：镇/村蓝底、景区棕底，立来车方向前 180m 同侧路肩
	var scol := Color(0.55, 0.38, 0.18) if kind == "scenic" else Color(0.16, 0.32, 0.6)
	_place_detour_sign(hname, z + DETOUR_SIGN_LEAD, side, scol)

## 小镇：跨路两侧各 4-5 栋临街楼，一栋带店铺招牌 + 门口搜刮箱
func _hamlet_town(z: float) -> void:
	for sd in [-1.0, 1.0]:
		var n := 4 + randi() % 2
		var shop_i := randi() % n
		for i in range(n):
			var bz := z - 50.0 + i * randf_range(22.0, 28.0) + randf_range(-4.0, 4.0)
			var bx: float = road_x(bz) + sd * randf_range(22.0, 27.0)
			_place_scenery(BUILDING_SCENE, bx, bz, randf_range(7.0, 12.0))
			if i == shop_i:
				var shops: Array = _hamlet_cfg.get("shops", ["便利店"])
				_shop_sign(bx, bz, sd, String(shops[randi() % shops.size()]))
				_loot_box(bx - sd * 4.5, bz + randf_range(-2.0, 2.0))
	_loot_and_zombies(Vector3(road_x(z), 0, z), 18.0, 0, 2 + randi() % 3)

## 村庄：side 侧 2-3 栋农舍 + 两块农田，丧尸 1-2
func _hamlet_village(z: float, side: float) -> void:
	var n := 2 + randi() % 2
	for i in range(n):
		var hx := road_x(z) + side * randf_range(24.0, 40.0)
		var hz := z + randf_range(-28.0, 28.0)
		_make_farmhouse(hx, hz, side)
		if i == 0:
			_loot_box(hx - side * 3.4, hz + randf_range(-1.5, 1.5))
	_make_farmland(road_x(z) + side * randf_range(24.0, 34.0), z + randf_range(-16.0, 16.0), randf_range(14.0, 20.0), randf_range(10.0, 14.0))
	_make_farmland(road_x(z) - side * randf_range(28.0, 45.0), z + randf_range(-22.0, 22.0), randf_range(18.0, 26.0), randf_range(12.0, 16.0))
	_loot_and_zombies(Vector3(road_x(z) + side * 28.0, 0, z), 16.0, 0, 1 + randi() % 2)

## 景区：停车场 + 售票亭（亭后有箱） + 观景台，沿景侧一字排开
func _hamlet_scenic(z: float, side: float) -> void:
	_make_parking_lot(road_x(z) + side * 16.0, z, side)
	_make_ticket_booth(road_x(z - 9.0) + side * randf_range(20.0, 24.0), z - 9.0, side)
	_make_viewpoint(road_x(z + 4.0) + side * randf_range(36.0, 44.0), z + 4.0, side)
	_loot_and_zombies(Vector3(road_x(z) + side * 22.0, 0, z), 14.0, 0, randi() % 3)

## 白墙红瓦农舍，正面朝路
func _make_farmhouse(x: float, z: float, side: float) -> void:
	var root := Node3D.new()
	root.add_to_group("consumable")
	root.position = Vector3(x, ground_height(x, z), z)
	root.rotation.y = -side * PI * 0.5
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(5.0, 3.2, 4.2)
	body.mesh = bm
	body.position = Vector3(0, 1.6, 0)
	body.material_override = _mat(Color(0.88, 0.86, 0.8))
	root.add_child(body)
	var roof := MeshInstance3D.new()
	var rm := PrismMesh.new()
	rm.size = Vector3(5.6, 1.6, 4.8)
	roof.mesh = rm
	roof.position = Vector3(0, 4.0, 0)
	roof.material_override = _mat(Color(0.62, 0.25, 0.18))
	root.add_child(roof)
	var door := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(1.0, 2.1, 0.08)
	door.mesh = dm
	door.position = Vector3(0, 1.05, 2.12)
	door.material_override = _mat(Color(0.3, 0.2, 0.12))
	root.add_child(door)
	_solid_box(root, Vector3(5.0, 3.2, 4.2), Vector3(0, 1.6, 0))
	add_child(root)

## 农田：土色底 + 绿色田垄（纯视觉）
func _make_farmland(x: float, z: float, w: float, d: float) -> void:
	var root := Node3D.new()
	root.add_to_group("consumable")
	root.position = Vector3(x, ground_height(x, z) + 0.04, z)
	var soil := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(w, 0.05, d)
	soil.mesh = sm
	soil.material_override = _mat(Color(0.45, 0.34, 0.2))
	root.add_child(soil)
	var rows := int(d / 1.6)
	for i in range(rows):
		var ridge := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(w - 1.0, 0.14, 0.5)
		ridge.mesh = rm
		ridge.position = Vector3(0, 0.1, -d * 0.5 + 0.8 + i * 1.6)
		ridge.material_override = _mat(Color(0.38, 0.52, 0.22))
		root.add_child(ridge)
	add_child(root)

## 景区停车场：沥青面 + 车位线 + 废弃车 1-2
func _make_parking_lot(x: float, z: float, side: float) -> void:
	var root := Node3D.new()
	root.add_to_group("consumable")
	root.position = Vector3(x, ground_height(x, z) + 0.05, z)
	var pad := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(12.0, 0.06, 10.0)
	pad.mesh = pm
	pad.material_override = _mat(Color(0.25, 0.25, 0.27))
	root.add_child(pad)
	for i in range(5):
		var line := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.12, 0.02, 4.5)
		line.mesh = lm
		line.position = Vector3(-3.6 + i * 2.4, 0.04, side * 2.5)
		line.material_override = _mat(Color(0.9, 0.9, 0.88))
		root.add_child(line)
	add_child(root)
	var ncar := 1 + randi() % 2
	for i in range(ncar):
		var cx := x - 2.4 + i * 4.8
		var cz := z + side * 2.5
		_wreck_solid(WCAR_SCENE, 1.0, Vector3(2.8, 1.75, 4.05), Vector3(0, 1.43, 0), Vector3(cx, 0, cz), side * PI * 0.5 + randf_range(-0.2, 0.2))

## 景区售票亭：米黄小屋 + 窗口 + 挑檐，亭后有搜刮箱
func _make_ticket_booth(x: float, z: float, side: float) -> void:
	var root := Node3D.new()
	root.add_to_group("consumable")
	root.position = Vector3(x, ground_height(x, z), z)
	root.rotation.y = -side * PI * 0.5
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 2.6, 2.2)
	body.mesh = bm
	body.position = Vector3(0, 1.3, 0)
	body.material_override = _mat(Color(0.82, 0.76, 0.62))
	root.add_child(body)
	var win := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(1.2, 0.9, 0.06)
	win.mesh = wm
	win.position = Vector3(0, 1.45, 1.12)
	win.material_override = _mat(Color(0.2, 0.16, 0.12))
	root.add_child(win)
	var eave := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(3.2, 0.12, 3.0)
	eave.mesh = em
	eave.position = Vector3(0, 2.75, 0)
	eave.material_override = _mat(Color(0.5, 0.28, 0.18))
	root.add_child(eave)
	_solid_box(root, Vector3(2.4, 2.6, 2.2), Vector3(0, 1.3, 0))
	add_child(root)
	_loot_box(x + side * 2.0, z - 1.6)

## 景区观景台：木平台 + 角柱 + 三边栏杆，朝景侧
func _make_viewpoint(x: float, z: float, side: float) -> void:
	var root := Node3D.new()
	root.add_to_group("consumable")
	root.position = Vector3(x, ground_height(x, z), z)
	root.rotation.y = side * PI * 0.5
	var post_mat := _mat(Color(0.42, 0.3, 0.18))
	var deck := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(4.5, 0.18, 3.4)
	deck.mesh = dm
	deck.position = Vector3(0, 0.55, 0)
	deck.material_override = post_mat
	root.add_child(deck)
	for px in [-2.1, 2.1]:
		for pz in [-1.5, 1.5]:
			var post := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.08
			pm.bottom_radius = 0.1
			pm.height = 0.55
			post.mesh = pm
			post.position = Vector3(px, 0.27, pz)
			post.material_override = post_mat
			root.add_child(post)
	# 三边栏杆（近路侧留开口）
	for sd in [-1.0, 1.0]:
		for i in range(3):
			var rp := MeshInstance3D.new()
			var rpm := CylinderMesh.new()
			rpm.top_radius = 0.05
			rpm.bottom_radius = 0.05
			rpm.height = 1.0
			rp.mesh = rpm
			rp.position = Vector3(sd * 2.2, 1.1, -1.4 + i * 1.4)
			rp.material_override = post_mat
			root.add_child(rp)
		var rail := MeshInstance3D.new()
		var rlm := BoxMesh.new()
		rlm.size = Vector3(0.08, 0.08, 3.4)
		rail.mesh = rlm
		rail.position = Vector3(sd * 2.2, 1.6, 0)
		rail.material_override = post_mat
		root.add_child(rail)
	for i in range(4):
		var fp := MeshInstance3D.new()
		var fpm := CylinderMesh.new()
		fpm.top_radius = 0.05
		fpm.bottom_radius = 0.05
		fpm.height = 1.0
		fp.mesh = fpm
		fp.position = Vector3(-2.2 + i * 1.47, 1.1, 1.65)
		fp.material_override = post_mat
		root.add_child(fp)
	var frail := MeshInstance3D.new()
	var frm := BoxMesh.new()
	frm.size = Vector3(4.5, 0.08, 0.08)
	frail.mesh = frm
	frail.position = Vector3(0, 1.6, 1.65)
	frail.material_override = post_mat
	root.add_child(frail)
	add_child(root)

## 店铺竖招：贴楼面朝来车方向
func _shop_sign(x: float, z: float, side: float, text: String) -> void:
	var lb := Label3D.new()
	lb.add_to_group("consumable")
	lb.text = text
	lb.font_size = 80
	lb.pixel_size = 0.012
	lb.outline_size = 10
	lb.outline_modulate = Color(0.08, 0.06, 0.04)
	lb.modulate = Color(1.0, 0.85, 0.4)
	lb.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lb.position = Vector3(x - side * 2.6, ground_height(x, z) + 3.6, z)
	add_child(lb)

## 加油站：雨棚 + 双油泵 + 价格立牌（支路末端，正对来车方向）
func _gas_station(z: float, pj: Dictionary) -> void:
	var root := Node3D.new()
	root.add_to_group("consumable")
	var side := float(pj["side"])
	var dir := Vector3(side * sin(pj["ang"]), 0, -cos(pj["ang"])).normalized()
	var end: Vector3 = Vector3(road_x(z) + side * (ROAD_HALF - 0.8), 0, z) + dir * (float(pj["len"]) + 7.0)
	root.position = Vector3(end.x, ground_height(end.x, end.z), end.z)
	root.rotation.y = atan2(-dir.x, -dir.z)
	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(13.0, 0.35, 8.0)
	roof.mesh = rm
	roof.position.y = 5.4
	roof.material_override = _mat(Color(0.88, 0.88, 0.85))
	root.add_child(roof)
	for dx in [-5.0, 5.0]:
		for dz in [-3.0, 3.0]:
			var post := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.12
			pm.bottom_radius = 0.14
			pm.height = 5.4
			post.mesh = pm
			post.position = Vector3(dx, 2.7, dz)
			post.material_override = _mat(Color(0.75, 0.76, 0.74))
			root.add_child(post)
	for dx in [-2.2, 2.2]:
		var pump := MeshInstance3D.new()
		var km := BoxMesh.new()
		km.size = Vector3(0.8, 1.5, 0.55)
		pump.mesh = km
		pump.position = Vector3(dx, 0.75, 0.0)
		pump.material_override = _mat(Color(0.72, 0.16, 0.12))
		root.add_child(pump)
		_solid_box(pump, km.size, Vector3.ZERO)
	# 价格立牌：白柱红顶
	var tp := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.7, 4.6, 0.4)
	tp.mesh = tm
	tp.position = Vector3(-7.6, 2.3, 3.2)
	tp.material_override = _mat(Color(0.9, 0.9, 0.86))
	root.add_child(tp)
	var th := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.9, 0.8, 0.5)
	th.mesh = hm
	th.position = Vector3(-7.6, 4.9, 3.2)
	th.material_override = _emis_mat(Color(0.85, 0.12, 0.1), 1.2)
	root.add_child(th)
	add_child(root)
	# 油站探索：雨棚周边搜刮箱 + 丧尸（下车加油有风险有回报）
	_loot_and_zombies(end, 11.0, 1 + randi() % 2, 2 + randi() % 3)

## 营地：三顶斜顶帐篷 + 石圈篝火（路左 25m 外）
func _camp(z: float) -> void:
	var root := Node3D.new()
	root.add_to_group("consumable")
	var bx: float = road_x(z) - (ROAD_HALF + 18.0)
	root.position = Vector3(bx, ground_height(bx, z), z)
	var canvas := _mat(Color(0.55, 0.5, 0.38))
	for i in range(3):
		var tent := Node3D.new()
		tent.position = Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0))
		tent.rotation.y = randf() * TAU
		for s in [-1.0, 1.0]:
			var sheet := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(3.3, 0.06, 4.4)
			sheet.mesh = sm
			sheet.position = Vector3(s * 1.14, 1.14, 0.0)
			sheet.rotation.z = -s * PI * 0.25
			sheet.material_override = canvas
			tent.add_child(sheet)
		root.add_child(tent)
	for i in range(7):
		var a := TAU * i / 7.0
		var st := MeshInstance3D.new()
		var sm2 := BoxMesh.new()
		sm2.size = Vector3(0.28, 0.2, 0.24)
		st.mesh = sm2
		st.position = Vector3(cos(a) * 0.55, 0.1, sin(a) * 0.55)
		st.rotation.y = a
		st.material_override = _mat(Color(0.4, 0.4, 0.42))
		root.add_child(st)
	var ember := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(0.5, 0.16, 0.5)
	ember.mesh = em
	ember.position.y = 0.08
	ember.material_override = _emis_mat(Color(1.0, 0.45, 0.12), 2.0)
	root.add_child(ember)
	var fire := OmniLight3D.new()
	fire.light_color = Color(1.0, 0.55, 0.25)
	fire.light_energy = 1.2
	fire.omni_range = 7.0
	fire.position.y = 0.8
	root.add_child(fire)
	add_child(root)

## 地标：鹰嘴岩式巨型岩柱（路左远眺，微倾更像风蚀）
func _landmark_rock(z: float) -> void:
	# 风蚀岩柱：基座 + 中层错叠 + 向路挑出的"喙"
	var bx: float = road_x(z) - randf_range(40.0, 52.0)
	var gy: float = ground_height(bx, z)
	var rock := Node3D.new()
	rock.position = Vector3(bx, gy, z)
	rock.rotation.y = randf() * TAU
	add_child(rock)
	rock.add_to_group("consumable")
	var layers := [
		[Vector3(randf_range(8.0, 10.0), 12.0, randf_range(7.0, 8.5)), Vector3(0, 6, 0), 0.0],
		[Vector3(randf_range(5.5, 6.5), 9.0, randf_range(5.0, 6.0)), Vector3(randf_range(-1.5, -0.8), 15.5, randf_range(-0.5, 0.5)), randf_range(-0.05, 0.05)],
		[Vector3(randf_range(4.5, 5.5), 4.0, randf_range(3.5, 4.5)), Vector3(randf_range(2.0, 3.2), 21.5, randf_range(-0.5, 0.5)), randf_range(0.04, 0.09)],
	]
	for L in layers:
		var bm := BoxMesh.new()
		bm.size = L[0]
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = _mat(Color(0.56, 0.5, 0.42).darkened(randf() * 0.12))
		mi.position = L[1]
		mi.rotation.z = L[2]
		rock.add_child(mi)
	_solid_box(rock, Vector3(9, 23, 8), Vector3(0, 11.5, 0))

## 高速绿牌：默认立路右；side=-1 立路左（town/gas 到达牌避让支路入口用）
func _place_sign(pname: String, z: float, side := 1.0) -> void:
	var root := Node3D.new()
	root.add_to_group("consumable")
	var mx: float = road_x(z) + side * (ROAD_HALF + 4.2)
	root.position = Vector3(mx, ground_height(mx, z), z)
	var bw: float = 0.62 * pname.length() + 0.8
	for dx in [-bw * 0.38, bw * 0.38]:
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.09
		pm.bottom_radius = 0.11
		pm.height = 5.2
		post.mesh = pm
		post.position = Vector3(dx, 2.6, 0.0)
		post.material_override = _mat(Color(0.42, 0.44, 0.45))
		root.add_child(post)
	var back := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(bw, 1.9, 0.07)
	back.mesh = bm
	back.position.y = 6.0
	back.material_override = _mat(Color(0.92, 0.93, 0.9))
	root.add_child(back)
	var face := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(bw - 0.16, 1.74, 0.03)
	face.mesh = fm
	face.position = Vector3(0.0, 6.0, 0.05)
	face.material_override = _mat(Color(0.02, 0.38, 0.2))
	root.add_child(face)
	var lb := Label3D.new()
	lb.text = pname
	lb.font_size = 96
	lb.pixel_size = 0.0048
	lb.outline_size = 10
	lb.outline_modulate = Color(0.02, 0.2, 0.1)
	lb.modulate = Color(0.95, 0.97, 0.95)
	lb.position = Vector3(0.0, 6.0, 0.08)
	root.add_child(lb)
	add_child(root)

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
	var body: PhysicsBody3D
	if hard:
		body = StaticBody3D.new()
	else:
		# 软障碍用冻结刚体：被撞前等同静态，命中后解冻物理撞飞，残骸留在路面
		var rb := RigidBody3D.new()
		rb.freeze = true
		rb.mass = 80.0 if scene == WCAR_SCENE else 40.0
		body = rb
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
	var ox := road_x(z) + x_off
	body.position = Vector3(ox, ground_height(ox, z), z)
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
	var px := road_x(z) + randf_range(-4.0, 4.0)
	p.position = Vector3(px, ground_height(px, z), z)
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
	# 野地逃命者：从路外野地跑向路缘（survivor.gd 自管逃命/据枪）
	var off := randf_range(ROAD_HALF + 2.5, ROAD_HALF + 9.0)
	var sx := road_x(z) + side * off
	s.position = Vector3(sx, ground_height(sx, z), z)
	add_child(s)
	# 身后追兵：外侧 8~14m 直接狂暴，锁幸存者为猎杀目标，制造追逃场面
	for i in randi_range(1, 2):
		var zz := z + randf_range(-4.0, 4.0)
		var body := _make_zombie_body()
		body.position = Vector3(road_x(zz) + side * (off + randf_range(8.0, 14.0)), GROUND_Y + 0.5, zz)
		add_child(body)
		body.setup(self)
		body.hunt_target = s
		body._enter_chase()
		zombies.append(body)

## 路灯：杆 + 朝路面的悬臂 + 自发光灯头，每 55m 交替两侧
func _spawn_lamp(z: float) -> void:
	lamp_side = -lamp_side
	var root := Node3D.new()
	root.add_to_group("consumable")
	var lx0 := road_x(z) + lamp_side * (ROAD_HALF + 1.4)
	root.position = Vector3(lx0, ground_height(lx0, z), z)
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

## 里程碑路牌：每 50km 一块绿底白字高速指示牌，路右、面向来车
func _spawn_milepost(z: float) -> void:
	# 方舟营地世界 z ≈ rvz - 剩余里程（与 safe_z 同一基准）
	var ark_z := rv.global_position.z - (GOAL_KM - dist_km) * KMH_FACTOR
	var remain_km := int(round((z - ark_z) / KMH_FACTOR))
	if remain_km <= 0:
		return
	var root := Node3D.new()
	root.add_to_group("consumable")
	var mx := road_x(z) + ROAD_HALF + 3.4
	root.position = Vector3(mx, ground_height(mx, z), z)
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.09
	pm.bottom_radius = 0.11
	pm.height = 4.4
	post.mesh = pm
	post.position.y = 2.2
	post.material_override = _mat(Color(0.42, 0.44, 0.45))
	root.add_child(post)
	var back := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.6, 1.8, 0.07)
	back.mesh = bm
	back.position.y = 5.0
	back.material_override = _mat(Color(0.92, 0.93, 0.9))
	root.add_child(back)
	var face := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(3.44, 1.64, 0.03)
	face.mesh = fm
	face.position = Vector3(0.0, 5.0, 0.05)
	face.material_override = _mat(Color(0.02, 0.38, 0.2))
	root.add_child(face)
	var lb := Label3D.new()
	lb.text = "方舟 %d km" % remain_km
	lb.font_size = 96
	lb.pixel_size = 0.0048
	lb.outline_size = 10
	lb.outline_modulate = Color(0.02, 0.2, 0.1)
	lb.modulate = Color(0.95, 0.97, 0.95)
	lb.position = Vector3(0.0, 5.0, 0.08)
	root.add_child(lb)
	add_child(root)

## 郊野电线杆：平原/森林/丘陵段路左，跨间挂垂弧电线
func _spawn_pole(z: float) -> void:
	var zone := zone_at(z)
	if zone != "plain" and zone != "forest" and zone != "hills":
		_pole_prev.clear()
		return
	var root := Node3D.new()
	root.add_to_group("consumable")
	var mx := road_x(z) - (ROAD_HALF + 4.5)
	var gy := ground_height(mx, z)
	root.position = Vector3(mx, gy, z)
	var wood := _mat(Color(0.32, 0.24, 0.16))
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.09
	pm.bottom_radius = 0.14
	pm.height = 7.2
	pole.mesh = pm
	pole.position.y = 3.6
	pole.material_override = wood
	root.add_child(pole)
	var arm := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(2.4, 0.12, 0.12)
	arm.mesh = am
	arm.position.y = 6.6
	arm.material_override = wood
	root.add_child(arm)
	# 与上一根杆跨接垂弧电线（横担两端各一根）
	var ends := [Vector3(mx - 1.1, gy + 6.55, z), Vector3(mx + 1.1, gy + 6.55, z)]
	if _pole_prev.size() == 2:
		for i in range(2):
			_wire_span(_pole_prev[i], ends[i])
	_pole_prev = ends
	add_child(root)

## 两点间 6 段下垂电线（悬链线近似，中点垂 1.1m）
func _wire_span(a: Vector3, b: Vector3) -> void:
	var dark := _mat(Color(0.08, 0.08, 0.08))
	var prev := a
	for i in range(1, 7):
		var t := float(i) / 6.0
		var p := a.lerp(b, t)
		p.y -= 4.0 * 1.1 * t * (1.0 - t)
		var seg := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.03, 0.03, prev.distance_to(p))
		seg.mesh = sm
		seg.material_override = dark
		seg.add_to_group("consumable")
		add_child(seg)
		seg.global_position = (prev + p) * 0.5
		seg.look_at(p, Vector3.UP)
		prev = p

# ---------- 撞击处理（rv.gd 回调） ----------
func on_obstacle_hit(hard: bool, speed_kmh: float, obstacle: Node3D = null) -> void:
	# 低速贴靠不计伤害，避免卡在障碍旁被反复结算
	if hit_cd > 0.0 or speed_kmh < 12.0:
		return
	# 已撞飞的软障碍残骸不再重复结算
	if not hard and obstacle != null and obstacle.has_meta("knocked"):
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
		if obstacle is RigidBody3D:
			# 解冻刚体：按车速冲量撞飞，翻滚落地后留在原地（不消失）
			obstacle.set_meta("knocked", true)
			obstacle.freeze = false
			var dir := -rv.global_transform.basis.z
			obstacle.apply_central_impulse((dir * (4.0 + speed_kmh * 0.06) + Vector3(0.0, 2.2, 0.0)) * obstacle.mass)
			obstacle.apply_torque_impulse(Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 3.0 * obstacle.mass)
			_wrecks.append(obstacle)
	hud.update_stats(self)

func on_zombie_run_over() -> void:
	if hit_cd > 0.0 or rv.speed_kmh < 10.0:
		return
	hit_cd = 0.25
	var dmg := 0.3 if _has_passive("tang_tang") else 0.5
	durability = maxf(0.0, durability - dmg)
	add_trauma(0.08)
	sfx.play("run_over")

func on_pickup(kind: String, boost := 1.0) -> void:
	if game_over:
		return
	var mult := (1.5 if _has_passive("ye_lan") else 1.0) * boost
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
	# 上车短对话：recruit_<id> 事件无 at/weight，只在此处手动触发
	if not member.is_empty():
		var ev_id := "recruit_" + String(member.get("id", ""))
		if story.events.has(ev_id):
			story._open(ev_id)

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
	# 出生区景物也走确定性：同一世界种子下布局固定
	_wseed(0.0, 9)
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
		var tx := -9.0 + col_i * 18.0
		t.position = Vector3(tx, ground_height(tx, gate_z + tz), tz)
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
		bulb.position = Vector3(lx, ground_height(lx, gate_z + lz) + rng.randf_range(1.6, 3.2), lz)
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
		var wx := side * rng.randf_range(22.0, 34.0)
		w.position = Vector3(wx, ground_height(wx, gate_z - 30.0 - i * 14.0), -30.0 - i * 14.0)
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
	# 路肩（车可开）到 21m：带碰撞/实心景物一律放 22m 外，杜绝贴路穿车
	# x_band：横向距离带写入 meta，世界回收按带重放（否则高楼会被回收贴到路边）
	var sx2 := road_x(z) + side * (ROAD_HALF + 15.0 + randf() * 22.0)
	root.position = Vector3(sx2, ground_height(sx2, z), z)
	root.set_meta("x_band", Vector2(ROAD_HALF + 15.0, ROAD_HALF + 37.0))
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
		_solid_box(root, Vector3(0.6, tm.height, 0.6), Vector3(0, tm.height * 0.5, 0))
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
		_solid_box(root, Vector3(0.6, 5.5, 0.6), Vector3(0, 2.75, 0))
	elif roll < 0.44:
		# 常青松树：矮干 + 三层锥形树冠
		var pine := _make_pine()
		root.add_child(pine)
		_solid_box(root, Vector3(0.5, 3.0, 0.5), Vector3(0, 1.5, 0))
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
		_solid_box(root, Vector3(0.35, pm.height, 0.35), Vector3(0, pm.height * 0.5, 0))
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
		_solid_box(root, bm.size, b.position)
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
		root.set_meta("x_band", Vector2(105.0, 190.0) if far else Vector2(45.0, 90.0))
		# x 移出远处后按新位置的地形高度重算 y，否则楼悬浮/埋地
		root.position.y = ground_height(root.position.x, z)
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
			_solid_box(root, Vector3(0.2, 3.2, 0.2), Vector3(px, 1.6, 0))
		var panel := MeshInstance3D.new()
		var plm := BoxMesh.new()
		plm.size = Vector3(3.4, 1.9, 0.12)
		panel.mesh = plm
		panel.position.y = 3.8
		panel.rotation.y = randf_range(-0.15, 0.15)
		panel.material_override = _mat(Color(0.36, 0.3, 0.24))
		root.add_child(panel)
		root.position.x = road_x(z) + side * randf_range(ROAD_HALF + 15.0, ROAD_HALF + 21.0)
		root.set_meta("x_band", Vector2(ROAD_HALF + 15.0, ROAD_HALF + 21.0))
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

## 给景物加实心碰撞（layer 1 默认层：房车/玩家/丧尸都会撞上），随 consumable 一并回收
func _solid_box(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	body.add_child(cs)
	parent.add_child(body)

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
	# 直弯变化：弯道段大幅摆动（视觉明显盘弯，横向 ±20m 级），直道段仍保留轻微摆动
	var w := _bend_weight(z)
	return (sin(z * 0.018) * 7.5 + sin(z * 0.045 + 1.5) * 4.0 + sin(z * 0.008 + 0.7) * 11.0) * w

func _bend_weight(z: float) -> float:
	var t := sin(z * 0.011) * 0.6 + sin(z * 0.0043 + 2.0) * 0.4
	return lerpf(0.25, 1.0, smoothstep(-0.15, 0.45, t))

func ground_y(z: float) -> float:
	return GROUND_Y + _elev_at(z) + sin(z * 0.06) * 0.08 + sin(z * 0.13 + 2.1) * 0.05 + sin(z * 0.031 + 5.0) * 0.04

## 统一地面高度(x,z)：角色/车辆/道具贴地与碰撞高度图共用的唯一基准
## 路面 d≤7 → ground_y；路肩 d≤21 → -0.05；野地 → -0.3+side_elev；21~25 缓坡过渡（车上下路肩不卡）
func ground_height(x: float, z: float) -> float:
	return ground_height_c(x, z, ground_y(z), road_x(z), zone_at(z))

## 行缓存版：批量采样（碰撞高度图重建）时传入预算的 gy/rx/zone
func ground_height_c(x: float, z: float, gy: float, rx: float, zone: String) -> float:
	var d := absf(x - rx)
	if d <= ROAD_HALF:
		return gy
	if d <= 21.0:
		return gy - 0.05
	var field := gy - 0.3 + side_elev(z, d, zone)
	if d < 25.0:
		return lerpf(gy - 0.05, field, smoothstep(0.0, 1.0, (d - 21.0) / 4.0))
	return field

# ---------- 岔路/路口（确定性生成，护栏缺口与地形条带共用） ----------
const JUNCTION_EVERY := 170.0   # 岔路间距基准（米）
const DETOUR_SIGN_LEAD := 180.0 # 支路预告锈牌提前量（米）：牌入 260m 视野时支路条带已在地形窗口内

## 岔路哈希：同 index 恒定
func _jh(n: int) -> float:
	return fposmod(sin(float(n) * 127.1) * 43758.5453, 1.0)

## 聚落专属岔路（town/gas）：由地点 km 哈希确定参数（确定性），车沿支路可驶达镇区/油站
## 返回 {km, side, ang, len}；非 town/gas 返回 {}。kind 恒 0（土路支路），ang 小=接近垂直主路
func _place_junction(p: Dictionary) -> Dictionary:
	var t := String(p.get("type", ""))
	if t != "town" and t != "gas":
		return {}
	var km := float(p.get("km", 0.0))
	var n := int(km * 10.0)
	return {
		"km": km,
		"side": 1.0 if t == "gas" else (1.0 if _jh(n + 11) < 0.5 else -1.0),
		"ang": lerpf(0.12, 0.3, _jh(n + 12)),
		"len": lerpf(45.0, 70.0, _jh(n + 13)) if t == "town" else 34.0,
	}

## 聚落岔路的世界 z（按当前里程换算，与 _update_frontier 同公式；rv 未建时返回 INF=暂不出现，
## 首个地形条带漏画的支路在前进 60m 触发 terrain rebuild 后补上，玩家不可能更早到达 1km 外岔口）
func _place_junction_z(pj: Dictionary) -> float:
	if rv == null:
		return INF
	return rv.global_position.z - (float(pj["km"]) - dist_km) * KMH_FACTOR

## 窗口 [z1, z0]（z0 > z1，向 -Z 前进）内的岔路清单：{z, side, kind, ang, len}
## kind：0 土路支路 / 1 沥青十字路口；约 25% 的位置没有岔路；末尾合并聚落专属岔路
func junctions_in(z0: float, z1: float) -> Array:
	var out: Array = []
	var n0 := int(ceil(-z0 / JUNCTION_EVERY))
	var n1 := int(floor(-z1 / JUNCTION_EVERY))
	for n in range(maxi(n0, 1), n1 + 1):
		if _jh(n) > 0.75:
			continue
		var cross := _jh(n + 2000) < 0.28
		out.append({
			"z": -n * JUNCTION_EVERY,
			"side": 1.0 if _jh(n + 1000) < 0.5 else -1.0,
			"kind": 1 if cross else 0,
			"ang": lerpf(0.5, 1.0, _jh(n + 3000)),
			"len": lerpf(60.0, 120.0, _jh(n + 4000)),
		})
	for p in _places:
		var pj := _place_junction(p)
		if pj.is_empty():
			continue
		var pz := _place_junction_z(pj)
		if pz <= z0 and pz >= z1:
			out.append({"z": pz, "side": pj["side"], "kind": 0, "ang": pj["ang"], "len": pj["len"]})
	return out

## 护栏缺口查询：z 附近 ±12m 内有岔路且在该侧（十字两侧都断；含聚落专属岔路）
func junction_gap(z: float, side: float) -> bool:
	var n := int(round(-z / JUNCTION_EVERY))
	if n >= 1 and absf(-n * JUNCTION_EVERY - z) <= 12.0 and _jh(n) <= 0.75:
		if _jh(n + 2000) < 0.28 or signf(side) == (1.0 if _jh(n + 1000) < 0.5 else -1.0):
			return true
	for p in _places:
		var pj := _place_junction(p)
		if not pj.is_empty() and absf(_place_junction_z(pj) - z) <= 12.0 and signf(side) == float(pj["side"]):
			return true
	return false

## 可探索支路：尽头兴趣点（world.json detours 表：废车场/旧营地/翻倒货车）
## org/dir/len 与 junctions_in（terrain 支路条带）同一哈希公式，POI 落在条带末端；consumable 组车后自动回收
func _spawn_detour(n: int, zj: float) -> void:
	if _detours.is_empty():
		return
	_wseed(zj, 9)
	var side := 1.0 if _jh(n + 1000) < 0.5 else -1.0
	var ang := lerpf(0.5, 1.0, _jh(n + 3000))
	var len := lerpf(60.0, 120.0, _jh(n + 4000))
	var dir := Vector3(side * sin(ang), 0, -cos(ang)).normalized()
	var org := Vector3(road_x(zj) + side * (ROAD_HALF - 0.8), 0, zj)
	var end := org + dir * (len * randf_range(0.85, 1.0))
	var d: Dictionary = _detours[randi() % _detours.size()]
	match String(d.get("id", "")):
		"wrecks":
			for i in range(2 + randi() % 2):
				var wp := end + Vector3(randf_range(-7.0, 7.0), 0, randf_range(-7.0, 7.0))
				_wreck_solid(WCAR_SCENE, 1.0, Vector3(2.8, 1.75, 4.05), Vector3(0, 1.43, 0), wp, randf() * TAU)
			_loot_and_zombies(end, 9.0, 2, 1 + randi() % 3)
		"camp":
			for i in range(2):
				var bp := end + Vector3(randf_range(-6.0, 6.0), 0, randf_range(-6.0, 6.0))
				_wreck_solid(BARRICADE_SCENE, 0.55, Vector3(5.7, 0.95, 0.35), Vector3(0, 0.95, 0), bp, randf() * TAU)
			_place_scenery(JUNK_SCENE, end.x + randf_range(-5.0, 5.0), end.z + randf_range(-5.0, 5.0), randf_range(2.4, 3.2))
			_loot_and_zombies(end, 8.0, 2, randi() % 3)
		"truck":
			# 侧翻大货车：绕长轴滚转 90°，碰撞盒高宽互换；center.y = 新半高 3.3 - 下沉 0.4
			_wreck_solid(WTRUCK_SCENE, 0.28, Vector3(2.0, 3.3, 5.0), Vector3(0, 2.9, 0), end, randf() * TAU, PI / 2.0)
			_place_scenery(JUNK_SCENE, end.x + randf_range(-6.0, 6.0), end.z + randf_range(-6.0, 6.0), randf_range(2.4, 3.2))
			_loot_and_zombies(end, 8.0, 1 + randi() % 2, randi() % 2)
	_place_detour_sign(String(d.get("name", "")), zj + DETOUR_SIGN_LEAD, side)

## 支路 POI 实心残骸：StaticBody + 碰撞盒 + 模型（撞不动，与 BARRICADE 同类）
func _wreck_solid(scene: PackedScene, scale_f: float, half: Vector3, center: Vector3, pos: Vector3, yaw: float, roll := 0.0) -> void:
	var body := StaticBody3D.new()
	body.add_to_group("consumable")
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = half * 2.0
	col.shape = box
	col.position = center
	body.add_child(col)
	var model := scene.instantiate()
	model.scale = Vector3.ONE * scale_f
	if roll != 0.0:
		# 侧翻：滚转绕原点，原 y∈[0,高] 翻成水平向，x 半宽变成垂直半高——按 center.y 抬回地面
		model.position.y = center.y
	body.add_child(model)
	body.position = Vector3(pos.x, ground_height(pos.x, pos.z), pos.z)
	body.rotation = Vector3(0.0, yaw, roll)
	add_child(body)

## 支路预告锈牌：岔口前 DETOUR_SIGN_LEAD 米立支路同侧路肩（矮单柱锈铁皮，与高速绿牌区分）
func _place_detour_sign(pname: String, z: float, side: float, face_col := Color(0.48, 0.3, 0.15)) -> void:
	var root := Node3D.new()
	root.add_to_group("consumable")
	var mx: float = road_x(z) + side * (ROAD_HALF + 3.4)
	root.position = Vector3(mx, ground_height(mx, z), z)
	var bw: float = 0.5 * pname.length() + 0.6
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.06
	pm.bottom_radius = 0.08
	pm.height = 2.4
	post.mesh = pm
	post.position = Vector3(0, 1.2, 0)
	post.material_override = _mat(Color(0.4, 0.38, 0.35))
	root.add_child(post)
	var face := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(bw, 0.85, 0.04)
	face.mesh = fm
	face.position = Vector3(0, 2.0, 0)
	face.material_override = _mat(face_col)
	root.add_child(face)
	var lb := Label3D.new()
	lb.text = pname + (" →" if side > 0.0 else " ←")
	lb.font_size = 64
	lb.pixel_size = 0.005
	lb.outline_size = 8
	lb.outline_modulate = Color(0.25, 0.14, 0.06)
	lb.modulate = Color(0.94, 0.88, 0.74)
	lb.position = Vector3(0, 2.0, 0.06)
	root.add_child(lb)
	add_child(root)

## 定位路段所属景观带（向 -Z 前进，zones 循环）
func zone_at(z: float) -> String:
	if _zones.is_empty():
		return "plain"
	var zz := fposmod(-z, _zones_total)
	var acc := 0.0
	for zn in _zones:
		acc += float(zn.get("len", 400.0))
		if zz < acc:
			return String(zn.get("type", "plain"))
	return "plain"

## 当前景观段的强度权重（段中心 1.0，首尾各 90m 淡入淡出）——供水面宽度等地物渐变
func zone_weight(z: float) -> float:
	if _zones.is_empty():
		return 0.0
	var zz := fposmod(-z, _zones_total)
	var acc := 0.0
	for zn in _zones:
		var len: float = float(zn.get("len", 400.0))
		var off := zz - acc
		if off < len:
			return minf(smoothstep(0.0, 1.0, off / 90.0), smoothstep(0.0, 1.0, (len - off) / 90.0))
		acc += len
	return 0.0

## 路段海拔：段内取段值，段首平滑过渡（坡度随高差放缓）
func _elev_at(z: float) -> float:
	if _zones.is_empty():
		return 0.0
	var zz := fposmod(-z, _zones_total)
	var acc := 0.0
	var prev_e: float = float(_zones.back().get("elev", 0.0))
	for zn in _zones:
		var e: float = float(zn.get("elev", 0.0))
		var len: float = float(zn.get("len", 400.0))
		var off := zz - acc
		if off < len:
			var trans := maxf(90.0, absf(e - prev_e) * 6.0)
			var t := smoothstep(0.0, 1.0, clampf(off / trans, 0.0, 1.0))
			return lerpf(prev_e, e, t)
		prev_e = e
		acc += len
	return 0.0

## 公路走廊外地势：山段隆起、湖海段下沉成床、丘陵缓坡（zone 可预传，批量采样免重复查段）
func side_elev(z: float, dist: float, zone := "") -> float:
	var d := maxf(dist - 24.0, 0.0)
	if zone.is_empty():
		zone = zone_at(z)
	match zone:
		"mountain":
			return d * 0.55 + sin(z * 0.02 + dist * 0.05) * d * 0.12
		"hills":
			return d * 0.18
		"lake", "coast":
			return -minf(d * 0.35, 2.5)
		_:
			return sin(z * 0.05 + dist * 0.11) * minf(d * 0.05, 1.2)

# ---------- 景观段景物生成 ----------
func _side() -> float:
	return 1.0 if randf() < 0.5 else -1.0

## 按景观段在公路两侧持续生成景物（consumable 组，过后即焚）
func _spawn_scenery(z: float) -> void:
	var zone := zone_at(z)
	var rx: float = road_x(z)
	var tree_p := 0.1
	var tree_n := 1
	match zone:
		"city":
			if randf() < 0.55:
				_place_scenery(BUILDING_SCENE, rx + _side() * randf_range(23.0, 32.0), z, randf_range(9.0, 16.0))
			if randf() < 0.25:
				_place_scenery(JUNK_SCENE, rx + _side() * randf_range(22.5, 28.0), z + randf_range(-5.0, 5.0), randf_range(2.4, 3.0))
			tree_p = 0.06
		"forest":
			tree_p = 0.9
			tree_n = 3
		"mountain":
			tree_p = 0.4
			if randf() < 0.3:
				_spawn_rock(rx + _side() * randf_range(23.0, 45.0), z + randf_range(-6.0, 6.0))
		"hills", "lake", "coast":
			tree_p = 0.22
	for i in range(tree_n):
		if randf() < tree_p:
			_place_scenery(TREE_SCENE, rx + _side() * randf_range(23.0, 65.0), z + randf_range(-6.0, 6.0), randf_range(7.0, 13.0))

## 实例化景物：按 AABB 缩放到目标高度、脚底落地（外部资产尺寸不可控）
func _place_scenery(scene: PackedScene, x: float, z: float, target_h: float) -> void:
	var node: Node3D = scene.instantiate()
	var aabb := _merged_aabb(node)
	if aabb.size.y > 0.01:
		var s := target_h / aabb.size.y
		node.scale = Vector3.ONE * s
		node.position.y = -aabb.position.y * s
	node.position = Vector3(x, ground_height(x, z) + node.position.y, z)
	node.rotation.y = randf() * TAU
	if scene == BUILDING_SCENE or scene == JUNK_SCENE:
		# 楼/集装箱：整体实心（本地坐标，随 node.scale 自动缩放）
		_solid_box(node, aabb.size, aabb.get_center())
	elif scene == TREE_SCENE:
		# 树：只挡树干，树冠可穿
		var trunk_w := maxf(0.35, aabb.size.x * 0.08)
		_solid_box(node, Vector3(trunk_w, aabb.size.y, trunk_w), Vector3(aabb.get_center().x, aabb.get_center().y, aabb.get_center().z))
	node.add_to_group("consumable")
	add_child(node)

## 递归合并子树 AABB 到 node 本地空间
func _merged_aabb(node: Node, xform := Transform3D.IDENTITY) -> AABB:
	var aabb := AABB()
	var first := true
	if node is MeshInstance3D:
		aabb = xform * node.get_aabb()
		first = false
	for c in node.get_children():
		if c is Node3D:
			var ca := _merged_aabb(c, xform * (c as Node3D).transform)
			if first:
				aabb = ca
				first = false
			else:
				aabb = aabb.merge(ca)
	return aabb

## 山段灰岩（半埋更自然）
func _spawn_rock(x: float, z: float) -> void:
	var rock := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var s := randf_range(1.2, 3.2)
	mesh.size = Vector3(s * randf_range(1.0, 1.8), s, s * randf_range(1.0, 1.8))
	rock.mesh = mesh
	rock.material_override = _mat(Color(0.52, 0.55, 0.56))
	rock.position = Vector3(x, ground_height(x, z) + mesh.size.y * 0.3, z)
	rock.rotation.y = randf() * TAU
	_solid_box(rock, mesh.size * 0.85, Vector3.ZERO)
	rock.add_to_group("consumable")
	add_child(rock)
