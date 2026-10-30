class_name CharUtil
extends RefCounted
## 精细 VRM 角色实例化：按队友 id 选择 roles_glb 下的 GLB（自带 idle/sit 动画与多材质）。

const ROLE_SCENES := {
	"hero": "res://assets/roles_glb/hero.glb",
	"role1": "res://assets/roles_glb/role1.glb",
	"role2": "res://assets/roles_glb/role2.glb",
}
const AK_SCENE := preload("res://assets/guns/ak.glb")

static var _scene_cache: Dictionary = {}

## 返回 {"node": 角色根 Node3D, "anim": AnimationPlayer}；anim_name 不存在时保持静息。
## expr 为 morph 常态表情参数（如 {"Fcl_ALL_Joy": 0.15}），自动挂 CharLively 活感组件；lively=false 跳过（战斗态自管动画）。
static func instantiate(cid: String, anim_name := "idle", expr: Dictionary = {}, lively := true) -> Dictionary:
	var packed: PackedScene = _get_scene(cid)
	var char: Node3D = packed.instantiate()
	var anim: AnimationPlayer = char.find_child("AnimationPlayer", true, false)
	if anim != null and anim_name != "" and anim.has_animation(anim_name):
		# idle/sit 必须循环，否则播完停在末帧，人物变成静止人偶
		anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		anim.play(anim_name)
	if lively:
		char.add_child(CharLively.new(expr, anim_name))
	return {"node": char, "anim": anim}

## 队员 id → 角色基底：写实 role1 / 洋装 role2 按人设分配，未知名回退 role1。
static func _get_scene(cid: String) -> PackedScene:
	var key := _role_key(cid)
	if not _scene_cache.has(key):
		var packed: PackedScene = load(ROLE_SCENES[key])
		# GLB 材质缺 metallicFactor（glTF 默认 1.0），皮肤变全金属反射环境泛灰蓝；实例化一次修正共享材质
		var probe := packed.instantiate()
		_fix_materials(probe)
		probe.free()
		_scene_cache[key] = packed
	return _scene_cache[key]

static func _fix_materials(root: Node) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m is StandardMaterial3D:
				(m as StandardMaterial3D).metallic = 0.0
	for c in root.get_children():
		_fix_materials(c)

static func _role_key(cid: String) -> String:
	if ROLE_SCENES.has(cid):
		return cid
	# role1 写实：医生/司机/教练；role2 洋装：记者/外贸跟单（优雅都市人设）
	var roles := {"lin_wan": "role1", "shen_man": "role1", "tang_tang": "role1", "ye_lan": "role2", "ivory": "role2"}
	if roles.has(cid):
		return roles[cid]
	# 泛型幸存者 gen<序号>：两基底按序号奇偶轮换，车厢里外观有区分
	if cid.begins_with("gen"):
		return "role2" if int(cid.trim_prefix("gen")) % 2 == 1 else "role1"
	return "role1"

## 队友步枪：AKM GLB（guns.json ak 同源 0.066 缩放；GLB 枪口朝 -Z，绕 Y 转 180° 对齐枪手 +Z 瞄准向；grip 对齐原程序化枪握把位）
static func build_gun() -> Node3D:
	var g := Node3D.new()
	var wm: Node3D = AK_SCENE.instantiate()
	wm.scale = Vector3.ONE * 0.066
	wm.rotation_degrees = Vector3(0, 180, 0)
	wm.position = Vector3(0, -0.041, 0.166)
	g.add_child(wm)
	return g
