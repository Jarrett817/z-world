class_name CharUtil
extends RefCounted
## 精细 VRM 角色实例化：按队友 id 选择 roles_glb 下的 GLB（自带 idle/sit 动画与多材质）。

const ROLE_SCENES := {
	"hero": "res://assets/roles_glb/hero.glb",
	"role1": "res://assets/roles_glb/role1.glb",
	"role2": "res://assets/roles_glb/role2.glb",
}

static var _scene_cache: Dictionary = {}

## 返回 {"node": 角色根 Node3D, "anim": AnimationPlayer}；anim_name 不存在时保持静息。
## expr 为 morph 常态表情参数（如 {"Fcl_ALL_Joy": 0.15}），自动挂 CharLively 活感组件。
static func instantiate(cid: String, anim_name := "idle", expr: Dictionary = {}) -> Dictionary:
	var packed: PackedScene = _get_scene(cid)
	var char: Node3D = packed.instantiate()
	var anim: AnimationPlayer = char.find_child("AnimationPlayer", true, false)
	if anim != null and anim_name != "" and anim.has_animation(anim_name):
		# idle/sit 必须循环，否则播完停在末帧，人物变成静止人偶
		anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		anim.play(anim_name)
	char.add_child(CharLively.new(expr, anim_name))
	return {"node": char, "anim": anim}

## 队员 id → 角色基底：写实 role1 / 洋装 role2 按人设分配，未知名回退 role1。
static func _get_scene(cid: String) -> PackedScene:
	var key := _role_key(cid)
	if not _scene_cache.has(key):
		_scene_cache[key] = load(ROLE_SCENES[key])
	return _scene_cache[key]

static func _role_key(cid: String) -> String:
	if ROLE_SCENES.has(cid):
		return cid
	# role1 写实：医生/司机/教练；role2 洋装：记者/外贸跟单（优雅都市人设）
	var roles := {"lin_wan": "role1", "shen_man": "role1", "tang_tang": "role1", "ye_lan": "role2", "ivory": "role2"}
	return roles.get(cid, "role1")
