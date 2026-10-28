extends Node
## 剧情事件管理器：车载电台突发事件。
## JSON 驱动（res://data/events.json）：里程里程碑（at）+ 加权随机（weight）+ 事件链（next/goto）。
## 事件打开期间冻结主循环（main.story_active）。

var main: Node
var events: Dictionary = {}
var fired: Array = []
var active := false
var rng := RandomNumberGenerator.new()
var _random_in := 55.0
var _intro_delay := 2.5

func setup(node: Node) -> void:
	main = node
	rng.randomize()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/events.json"))
	if parsed is Dictionary:
		events = parsed

func _ready() -> void:
	# --nostory：截帧验收等调试场景不弹任何剧情
	if OS.get_cmdline_user_args().has("--nostory"):
		set_process(false)
		return
	# 开局序章：给玩家两秒看清场景后电台亮起（兼容仅记录过 intro_2 的旧存档）
	get_tree().create_timer(_intro_delay).timeout.connect(func() -> void:
		if not fired.has("intro") and not fired.has("intro_2"):
			_open("intro"))

func _process(delta: float) -> void:
	if active or events.is_empty() or main.game_over or main.rv_walk_active:
		return
	# 里程碑事件：到里程且角色门控满足（错过后招到人仍可补触发）
	for id in events:
		var ev: Dictionary = events[id]
		if ev.has("at") and not fired.has(id) and main.dist_km >= float(ev["at"]):
			if _req_ok(ev.get("requires", "")):
				_open(id)
				return
	# 随机事件：行驶或驻车中，按冷却时间投骰
	_random_in -= delta
	if _random_in <= 0.0:
		_random_in = rng.randf_range(70.0, 120.0)
		var id := _weighted_random_id()
		if id != "":
			_open(id)

## 加权抽取一个满足角色门控的随机事件
func _weighted_random_id() -> String:
	var pool: Array = []
	var total := 0.0
	for id in events:
		var ev: Dictionary = events[id]
		if ev.has("weight") and not fired.has(id) and _req_ok(ev.get("requires", "")):
			var w: float = ev["weight"]
			pool.append({"id": id, "w": w})
			total += w
	if pool.is_empty():
		return ""
	var roll := rng.randf() * total
	for item in pool:
		roll -= item.w
		if roll <= 0.0:
			return item.id
	return pool[-1].id

func _req_ok(req_id: String) -> bool:
	return req_id == "" or main._has_passive(req_id)

func _open(id: String) -> void:
	if not events.has(id):
		return
	var ev: Dictionary = events[id]
	active = true
	main.story_active = true
	# 战斗态鼠标被锁定，弹窗必须放出光标才能点选项
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# JSON 外层 key 才是事件 id，注入副本传给 HUD
	var evv: Dictionary = ev.duplicate()
	evv["id"] = id
	main.set_facilities_ui(false)
	main.sfx.play("story_open", 1.0, 0.03, -4.0)
	main.hud.show_story(evv)

## HUD 选项按钮回调
func choose(idx: int) -> void:
	if not active:
		return
	var ev: Dictionary = events[main.hud.story_event_id]
	var opts: Array = ev.get("options", [])
	if idx < 0 or idx >= opts.size():
		return
	var opt: Dictionary = opts[idx]
	# 分支事件链：goto 优先（无即时结算）
	if opt.has("goto"):
		fired.append(main.hud.story_event_id)
		main.hud.hide_story()
		_open(String(opt["goto"]))
		return
	# 概率型选项：60% 好结果
	if opt.has("roll"):
		var branch_key := "ok" if rng.randf() < 0.6 else "bad"
		var branch: Dictionary = opt["roll"][branch_key]
		_apply(branch.get("fx", {}))
		if branch.has("toast"):
			main.hud.toast(String(branch["toast"]))
		# 分支结算后跳转叙事节点（如垂死抢修成功续命）
		if branch.has("goto"):
			fired.append(main.hud.story_event_id)
			main.hud.hide_story()
			_open(String(branch["goto"]))
			return
	else:
		_apply(opt.get("fx", {}))
		if opt.has("toast"):
			main.hud.toast(String(opt["toast"]))
	# 顺序下一节
	if opt.has("next"):
		fired.append(main.hud.story_event_id)
		main.hud.hide_story()
		_open(String(opt["next"]))
		return
	# 事件结束
	fired.append(main.hud.story_event_id)
	main.hud.hide_story()
	active = false
	main.story_active = false
	# 战斗态恢复鼠标锁定（_enter 时 CAPTURED）
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if main.combat_active else Input.MOUSE_MODE_VISIBLE
	main.set_facilities_ui(true)
	main.hud.update_stats(main)
	# 终局选项：驶入方舟（win）/ 叙事性死亡（lose）
	if opt.get("win", false):
		main._do_win()
	elif opt.get("lose", false):
		main._do_game_over()

func _apply(fx: Dictionary) -> void:
	if fx.has("dur"):
		main.durability = clampf(main.durability + float(fx["dur"]), 0.0, 100.0)
	if fx.has("fuel"):
		main.fuel = clampf(main.fuel + float(fx["fuel"]), 0.0, 100.0)
	if fx.has("food"):
		main.food = maxf(0.0, main.food + float(fx["food"]))
	if fx.has("morale"):
		main.morale = clampf(main.morale + float(fx["morale"]), 0.0, 100.0)

## 选项前置条件是否满足（队友/士气/人数/医疗/战力不足时按钮置灰）
func option_available(opt: Dictionary) -> bool:
	if opt.has("requires") and not _req_ok(String(opt["requires"])):
		return false
	if opt.has("requires_morale") and main.morale < float(opt["requires_morale"]):
		return false
	if opt.has("requires_crew") and main.crew_members.size() < int(opt["requires_crew"]):
		return false
	if opt.has("requires_med") and _crew_stat("med") < int(opt["requires_med"]):
		return false
	if opt.has("requires_atk") and _crew_stat("atk") < int(opt["requires_atk"]):
		return false
	return true

func _crew_stat(key: String) -> int:
	var total := 0
	for m in main.crew_members:
		total += int(m.get(key, 0))
	return total
