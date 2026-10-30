extends Node
## 任务管理器：JSON 驱动的章节目标追踪（res://data/quests.json）。
## 目标类型：dist（里程 km）/ crew（队伍人数）。进度满足即自动推进并 toast。
## 完成状态/已触发提示入存档；瞬时战斗状态不跟踪。

var main: Node
var quests: Array = []          # [{id,name,desc,kind,goals:[{type,target,text}],done:bool,goal_i:int}]

func setup(node: Node) -> void:
	main = node
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/quests.json"))
	if parsed is Dictionary:
		for kind in ["main", "side"]:
			for q in parsed.get(kind, []):
				var qd: Dictionary = q.duplicate(true)
				qd["kind"] = kind
				qd["done"] = false
				qd["goal_i"] = 0
				quests.append(qd)

func _process(_delta: float) -> void:
	if main.game_over or main.story_active:
		return
	var any_changed := false
	for q in quests:
		if q["done"] or float(q.get("at", 0.0)) > main.dist_km:
			continue
		var goals: Array = q["goals"]
		var gi: int = q["goal_i"]
		var q_changed := false
		while gi < goals.size() and _goal_met(goals[gi]):
			gi += 1
			q_changed = true
			if gi >= goals.size():
				q["done"] = true
				q["goal_i"] = gi
				main.hud.toast("任务完成：%s" % q["name"])
				break
		q["goal_i"] = gi
		# 里程碑目标推进（非任务完成）时提示新目标
		if q_changed and not q["done"]:
			main.hud.toast("新目标：%s" % String(goals[gi].get("text", "")))
		any_changed = any_changed or q_changed
	if any_changed:
		main.hud.refresh_quests()

func _goal_met(g: Dictionary) -> bool:
	match String(g.get("type", "")):
		"dist":
			return main.dist_km >= float(g.get("target", 0.0))
		"crew":
			return main.crew_members.size() >= int(g.get("target", 0))
	return false

## 当前应在追踪条显示的任务目标（每个未完成任务的当前目标）
func active_goals() -> Array:
	var out: Array = []
	for q in quests:
		if q["done"] or float(q.get("at", 0.0)) > main.dist_km:
			continue
		var goals: Array = q["goals"]
		var gi: int = q["goal_i"]
		if gi < goals.size():
			out.append({"name": q["name"], "kind": q["kind"], "text": String(goals[gi].get("text", "")),
				"done_i": gi, "total": goals.size()})
	return out

## 日志面板用：全部任务及其目标完成情况
func all_quests() -> Array:
	return quests

# ---------- 存档 ----------
func save_state() -> Dictionary:
	var st := {}
	for q in quests:
		st[q["id"]] = {"done": q["done"], "goal_i": q["goal_i"]}
	return st

func load_state(st: Dictionary) -> void:
	for q in quests:
		if st.has(q["id"]):
			q["done"] = bool(st[q["id"]].get("done", false))
			q["goal_i"] = int(st[q["id"]].get("goal_i", 0))
