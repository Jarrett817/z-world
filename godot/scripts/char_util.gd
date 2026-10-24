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
	return roles.get(cid, "role1")

## 程序化步枪：钢木材质，机匣/枪管/握把/枪托四件；挂点与枪口由调用者按 aim 动作对位
static func build_gun() -> Node3D:
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
