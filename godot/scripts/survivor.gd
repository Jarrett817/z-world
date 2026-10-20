extends Node3D
## 路边幸存者：按招募顺序对应下一名队友的精细程序化人形（外套/发型/随身配件）+ 挥臂求救动画与橙色光柱。

var _body: Node3D
var _beam: MeshInstance3D
var crew_id := ""

## main.gd 在 add_child 前调用：指定本幸存者对应的队友 id
func setup(cid: String) -> void:
	crew_id = cid

func _ready() -> void:
	# 人设配色（id 见 data/survivors.json）
	var coat := Color(0.3, 0.32, 0.26)
	var shirt := Color(0.45, 0.4, 0.35)
	var pants_c := Color(0.17, 0.18, 0.2)
	var hair_c := Color(0.12, 0.1, 0.09)
	var skin := Color(0.82, 0.68, 0.55)
	var pack_c := Color(0.22, 0.2, 0.16)
	var height := 1.0
	var wave_side := 1.0 # 1=右臂挥，-1=左臂挥
	match crew_id:
		"lin_wan": # 林晚：白大褂 + 红十字医药箱 + 齐肩发
			coat = Color(0.87, 0.86, 0.83)
			shirt = Color(0.2, 0.3, 0.42)
			pants_c = Color(0.25, 0.27, 0.32)
			hair_c = Color(0.2, 0.15, 0.12)
		"chen_mo": # 陈默：深蓝工装 + 腰包，体型偏高
			coat = Color(0.18, 0.24, 0.32)
			shirt = Color(0.5, 0.46, 0.4)
			height = 1.05
		"ye_lan": # 叶澜：卡其风衣 + 胸前相机 + 盘发
			coat = Color(0.45, 0.4, 0.3)
			shirt = Color(0.75, 0.7, 0.6)
			pants_c = Color(0.22, 0.2, 0.17)
		"tang_tang": # 唐棠：黑色运动外套 + 红内搭 + 红绷带拳 + 高马尾
			coat = Color(0.12, 0.12, 0.14)
			shirt = Color(0.7, 0.12, 0.12)
			pants_c = Color(0.14, 0.14, 0.16)
			height = 1.05
		"ivory": # 苏薇：米白西装 + 长发 + 手提包，左手挥手
			coat = Color(0.82, 0.78, 0.72)
			shirt = Color(0.3, 0.28, 0.3)
			pants_c = Color(0.28, 0.26, 0.28)
			wave_side = -1.0
	_build({
		"coat": coat, "shirt": shirt, "pants": pants_c, "hair": hair_c,
		"skin": skin, "pack": pack_c, "height": height, "wave": wave_side
	})

	# 微弱求救光柱（暗夜远距离可见，但不刺眼）
	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.32
	cyl.height = 4.5
	_beam.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(1.0, 0.55, 0.15, 0.1)
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam.material_override = bm
	_beam.position.y = 2.25
	add_child(_beam)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.omni_range = 6.0
	light.light_energy = 0.7
	light.position.y = 1.4
	add_child(light)

	var area := Area3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.0, 3.0, 4.0)
	cs.shape = shape
	cs.position.y = 1.2
	area.add_child(cs)
	area.body_entered.connect(_on_body)
	add_child(area)

func _build(look: Dictionary) -> void:
	var coat_c: Color = look["coat"]
	var shirt_c: Color = look["shirt"]
	var pants_col: Color = look["pants"]
	var hair_col: Color = look["hair"]
	var skin_c: Color = look["skin"]
	var pack_col: Color = look["pack"]
	var height_s: float = look["height"]
	var wave_side: float = look["wave"]

	_body = Node3D.new()
	_body.scale = Vector3(1.0, height_s, 1.0)
	add_child(_body)
	var m_skin := _mat(skin_c)
	var m_coat := _mat(coat_c)
	var m_shirt := _mat(shirt_c)
	var m_pants := _mat(pants_col)
	var m_hair := _mat(hair_col)
	var m_shoes := _mat(Color(0.08, 0.08, 0.09))

	# 双腿 + 鞋
	for sx in [-1.0, 1.0]:
		var side: float = sx
		_add_box(_body, Vector3(0.16, 0.78, 0.18), Vector3(side * 0.11, 0.46, 0), m_pants)
		_add_box(_body, Vector3(0.17, 0.12, 0.28), Vector3(side * 0.11, 0.06, 0.03), m_shoes)
	# 躯干（外套）+ 胸前内搭
	_add_box(_body, Vector3(0.48, 0.62, 0.26), Vector3(0, 1.18, 0), m_coat)
	_add_box(_body, Vector3(0.2, 0.42, 0.03), Vector3(0, 1.16, 0.138), m_shirt)
	# 腰带
	_add_box(_body, Vector3(0.49, 0.06, 0.27), Vector3(0, 0.88, 0), m_shoes)
	# 脖子
	_add_cyl(_body, 0.06, 0.12, Vector3(0, 1.52, 0), m_skin)

	# 随身物：医药箱 / 腰包 / 相机 / 手提包 / 背包
	match crew_id:
		"lin_wan":
			var kit := _add_box(_body, Vector3(0.3, 0.22, 0.16), Vector3(0, 1.16, 0.22), _mat(Color(0.75, 0.14, 0.11)))
			_add_box(kit, Vector3(0.05, 0.15, 0.02), Vector3(0, 0, 0.085), _mat(Color(0.9, 0.9, 0.88)))
			_add_box(kit, Vector3(0.15, 0.05, 0.02), Vector3(0, 0, 0.086), _mat(Color(0.9, 0.9, 0.88)))
		"chen_mo":
			_add_box(_body, Vector3(0.26, 0.13, 0.15), Vector3(0, 0.8, 0.16), _mat(Color(0.15, 0.14, 0.12)))
			_add_box(_body, Vector3(0.32, 0.4, 0.16), Vector3(0, 1.2, -0.2), _mat(pack_col))
		"ye_lan":
			var cam := _add_box(_body, Vector3(0.15, 0.11, 0.09), Vector3(0, 1.42, 0.17), _mat(Color(0.07, 0.07, 0.08)))
			var lens := _add_cyl(cam, 0.035, 0.08, Vector3(0, 0, 0.08), _mat(Color(0.04, 0.04, 0.05)))
			lens.rotation.x = deg_to_rad(90.0)
			_add_box(_body, Vector3(0.32, 0.4, 0.16), Vector3(0, 1.2, -0.2), _mat(pack_col))
		"tang_tang":
			_add_box(_body, Vector3(0.32, 0.4, 0.16), Vector3(0, 1.2, -0.2), _mat(pack_col))
		"ivory":
			pass # 手提包挂在下垂的右手，见下
		_:
			_add_box(_body, Vector3(0.32, 0.4, 0.16), Vector3(0, 1.2, -0.2), _mat(pack_col))

	# 双肩双臂（pivot 在肩，可旋转）
	var arms: Array[Node3D] = []
	for sx in [-1.0, 1.0]:
		var side: float = sx
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.29, 1.42, 0)
		_body.add_child(arm)
		var am := MeshInstance3D.new()
		var ac := CapsuleMesh.new()
		ac.radius = 0.075
		ac.height = 0.54
		am.mesh = ac
		am.position.y = -0.25
		am.material_override = m_coat
		arm.add_child(am)
		var hand_mat := m_skin
		if crew_id == "tang_tang":
			hand_mat = _mat(Color(0.7, 0.1, 0.09)) # 红色缠手绷带
		var hand := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = 0.085
		hs.height = 0.17
		hand.mesh = hs
		hand.position.y = -0.55
		hand.material_override = hand_mat
		arm.add_child(hand)
		if crew_id == "ivory" and side > 0.0:
			_add_box(arm, Vector3(0.15, 0.2, 0.09), Vector3(0.02, -0.72, 0.03), _mat(Color(0.25, 0.18, 0.12)))
		arms.append(arm)

	# 头部 pivot（张望动画）
	var head_pivot := Node3D.new()
	head_pivot.position.y = 1.53
	_body.add_child(head_pivot)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.155
	sph.height = 0.34
	head.mesh = sph
	head.position.y = 0.16
	head.material_override = m_skin
	head_pivot.add_child(head)
	# 眼睛
	for sx in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.022
		em.height = 0.044
		eye.mesh = em
		eye.position = Vector3(sx * 0.055, 0.19, 0.138)
		eye.material_override = _mat(Color(0.05, 0.04, 0.035))
		head_pivot.add_child(eye)
	# 头发：半球盖贴头顶 + 后脑发，发型按人设追加
	var cap := MeshInstance3D.new()
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 0.156
	cap_mesh.height = 0.22
	cap_mesh.is_hemisphere = true
	cap.mesh = cap_mesh
	cap.position = Vector3(0, 0.19, 0)
	cap.material_override = m_hair
	head_pivot.add_child(cap)
	_add_box(head_pivot, Vector3(0.22, 0.12, 0.1), Vector3(0, 0.07, -0.09), m_hair)
	match crew_id:
		"lin_wan": # 齐肩黑发
			_add_box(head_pivot, Vector3(0.24, 0.24, 0.09), Vector3(0, -0.04, -0.1), m_hair)
		"ye_lan": # 盘发顶髻
			var bun := MeshInstance3D.new()
			var bm2 := SphereMesh.new()
			bm2.radius = 0.06
			bm2.height = 0.12
			bun.mesh = bm2
			bun.position = Vector3(0, 0.33, -0.01)
			bun.material_override = m_hair
			head_pivot.add_child(bun)
		"tang_tang": # 高马尾
			var tail := MeshInstance3D.new()
			var tmc := CapsuleMesh.new()
			tmc.radius = 0.045
			tmc.height = 0.3
			tail.mesh = tmc
			tail.position = Vector3(0, 0.12, -0.2)
			tail.rotation.x = deg_to_rad(70.0)
			tail.material_override = m_hair
			head_pivot.add_child(tail)
		"ivory": # 长发垂肩
			_add_box(head_pivot, Vector3(0.3, 0.3, 0.1), Vector3(0, -0.05, -0.11), m_hair)

	# 待机动画：挥臂求救 / 呼吸 / 重心摆动 / 张望
	var wave_arm: Node3D = arms[0] if wave_side < 0.0 else arms[1]
	wave_arm.rotation.x = -2.4
	var tw_wave := create_tween().set_loops()
	tw_wave.tween_property(wave_arm, "rotation:z", wave_side * 0.5, 0.5).set_trans(Tween.TRANS_SINE)
	tw_wave.tween_property(wave_arm, "rotation:z", wave_side * 0.12, 0.5).set_trans(Tween.TRANS_SINE)
	var tw_breath := create_tween().set_loops()
	tw_breath.tween_property(_body, "scale", Vector3(1.0, height_s * 1.006, 1.0), 2.6).set_trans(Tween.TRANS_SINE)
	tw_breath.tween_property(_body, "scale", Vector3.ONE * Vector3(1.0, height_s, 1.0), 2.6).set_trans(Tween.TRANS_SINE)
	var tw_sway := create_tween().set_loops()
	tw_sway.tween_property(_body, "rotation:z", 0.035, 3.1).set_trans(Tween.TRANS_SINE)
	tw_sway.tween_property(_body, "rotation:z", -0.035, 3.1).set_trans(Tween.TRANS_SINE)
	var tw_look := create_tween().set_loops()
	tw_look.tween_property(head_pivot, "rotation:y", 0.35, 2.2).set_trans(Tween.TRANS_SINE)
	tw_look.tween_property(head_pivot, "rotation:y", -0.35, 4.4).set_trans(Tween.TRANS_SINE)
	tw_look.tween_property(head_pivot, "rotation:y", 0.0, 2.2).set_trans(Tween.TRANS_SINE)

func _process(delta: float) -> void:
	_beam.rotate_y(delta * 0.6)

func _on_body(body: Node3D) -> void:
	if body == get_parent().rv:
		get_parent().try_recruit(self)

func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _add_cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	return m
