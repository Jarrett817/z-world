extends MeshInstance3D
## 无限地形：rebuild(start_z) 从 start_z 向前（-Z）重建 SPAN 长度条带。
## 多 surface：大地 / 路肩 / 柏油路面 / 车道线 / 波形护栏 / 双层远景山脊。

const SPAN := 900.0
const GROUND_Y := -1.56
const ROAD_HALF := 7.0
const SEG_LEN := 2.0
const DASH_PERIOD := 7.0
const DASH_LEN := 3.0
const RAIL_OFFSET := 8.9
const RAIL_SEG := 4.0

var _main: Node3D
var _mats: Array[StandardMaterial3D] = []

func _ready() -> void:
	# 一次性平面碰撞（车与丧尸共用，rebuild 不重建）
	var col := StaticBody3D.new()
	var shape := WorldBoundaryShape3D.new()
	shape.plane = Plane(Vector3.UP, GROUND_Y)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	col.add_child(cs)
	add_child(col)

func rebuild(start_z: float) -> void:
	_main = get_parent()
	mesh = _make_mesh(start_z)

func _make_mesh(start_z: float) -> ArrayMesh:
	var am := ArrayMesh.new()
	# 0 超宽大地（含 24m 走廊平坦过渡断点；按景观段做山坡隆起/海床下沉）
	var gxs := PackedFloat32Array([-600.0, -380.0, -220.0, -130.0, -80.0, -50.0, -34.0, -20.0, 20.0, 34.0, 50.0, 80.0, 130.0, 220.0, 380.0, 600.0])
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _band(start_z, 0.0, 0.0, -0.3, false, 1, gxs))
	# 1/2 两侧路肩土带
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _band(start_z, -ROAD_HALF - 16.0, -ROAD_HALF, -0.05, false, 2))
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _band(start_z, ROAD_HALF, ROAD_HALF + 16.0, -0.05, false, 2))
	# 3 柏油路面
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _band(start_z, -ROAD_HALF, ROAD_HALF, 0.0, false, 3))
	# 4/5 边缘实线（发旧白）
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _band(start_z, -ROAD_HALF + 0.35, -ROAD_HALF + 0.65, 0.02, false))
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _band(start_z, ROAD_HALF - 0.65, ROAD_HALF - 0.35, 0.02, false))
	# 6 中央黄虚线
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _band(start_z, -0.12, 0.12, 0.02, true))
	# 7/8 公路波形护栏（双横梁 + 立柱，沿弯路逐段挤出）
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _rail(start_z, -1.0))
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _rail(start_z, 1.0))
	# 9/10 近层青山剪影（草木覆盖，大气透视偏青，双面）
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _ridge(start_z, -150.0))
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _ridge(start_z, 150.0))
	# 11/12 远层青山（更矮更淡，拉出纵深）
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _ridge(start_z, -380.0, 280.0, 0.6))
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _ridge(start_z, 380.0, 280.0, 0.6))
	# 13/14 路边河湖：顺弯路展开的条带水面，随重建位置固定（明媚风光）
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _water(start_z, -1.0))
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _water(start_z, 1.0))
	if _mats.is_empty():
		var rail_mat := _mat(Color(0.42, 0.43, 0.44), 0.55)
		rail_mat.metallic = 0.35
		var ridge_mat := _mat(Color(0.23, 0.34, 0.22), 1.0)
		ridge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var ridge_far_mat := _mat(Color(0.42, 0.55, 0.45), 1.0)
		ridge_far_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var water_mat := StandardMaterial3D.new()
		water_mat.albedo_color = Color(0.16, 0.36, 0.46)
		water_mat.roughness = 0.12
		water_mat.metallic = 0.25
		water_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats = [
			_mat(Color(0.24, 0.33, 0.16), 1.0),
			_mat(Color(0.31, 0.34, 0.20), 1.0),
			_mat(Color(0.31, 0.34, 0.20), 1.0),
			_mat(Color(0.115, 0.11, 0.105), 0.98),
			_mat(Color(0.5, 0.48, 0.43), 0.9),
			_mat(Color(0.5, 0.48, 0.43), 0.9),
			_mat(Color(0.58, 0.44, 0.17), 0.9),
			rail_mat,
			rail_mat,
			ridge_mat,
			ridge_mat,
			ridge_far_mat,
			ridge_far_mat,
			water_mat,
			water_mat,
		]
	for i in _mats.size():
		am.surface_set_material(i, _mats[i])
	return am

## 生成一条沿路弯曲的条带（x0/x1 为相对路中心的横向范围，nx 为横向细分数）
## 顶点叠加确定性多频噪声色，做出柏油/泥地旧化斑驳，避免纯色塑料感
## xs 非空时改用给定 x 断点（大地带用），顶点叠加 side_elev 地势（山坡/海床）
func _band(start_z: float, x0: float, x1: float, y_off: float, dashed: bool, nx := 1, xs := PackedFloat32Array()) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var steps := int(SPAN / SEG_LEN)
	var use_xs := xs.size() >= 2
	var enx := xs.size() - 1 if use_xs else nx
	for i in steps:
		if dashed and fmod(i * SEG_LEN, DASH_PERIOD) > DASH_LEN:
			continue
		var za := start_z - i * SEG_LEN
		var zb := start_z - (i + 1) * SEG_LEN
		var cxa: float = _main.road_x(za)
		var cxb: float = _main.road_x(zb)
		var ya: float = _main.ground_y(za) + y_off
		var yb: float = _main.ground_y(zb) + y_off
		var row_a: int = verts.size()
		for j in enx + 1:
			var xx: float = xs[j] if use_xs else lerpf(x0, x1, float(j) / nx)
			var sy: float = _main.side_elev(za, absf(xx)) if use_xs else 0.0
			verts.append(Vector3(cxa + xx, ya + sy, za))
			normals.append(Vector3.UP)
			colors.append(_mottle(cxa + xx, za))
		for j in enx + 1:
			var xx: float = xs[j] if use_xs else lerpf(x0, x1, float(j) / nx)
			var sy: float = _main.side_elev(zb, absf(xx)) if use_xs else 0.0
			verts.append(Vector3(cxb + xx, yb + sy, zb))
			normals.append(Vector3.UP)
			colors.append(_mottle(cxb + xx, zb))
		for j in enx:
			var a := row_a + j
			var b := row_a + j + 1
			var c := row_a + (enx + 1) + j + 1
			var d := row_a + (enx + 1) + j
			indices.append(a); indices.append(c); indices.append(b)
			indices.append(a); indices.append(d); indices.append(c)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices
	return arr

## 确定性多频噪声：0.78~1.12 亮度调制并带轻微绿相漂移，重建时同位置颜色不变
func _mottle(x: float, z: float) -> Color:
	var n := sin(x * 0.91 + z * 0.37) * 0.5 + sin(x * 2.3 - z * 1.7) * 0.3 + sin(z * 4.7 + x * 0.4) * 0.2
	var v: float = clampf(0.95 + n * 0.09, 0.78, 1.12)
	# 枯草/裸土斑块：低频噪声把部分草地带向黄绿，避免整片塑料绿
	var dry: float = sin(x * 0.05 + z * 0.031) * 0.5 + sin(x * 0.013 - z * 0.017) * 0.5
	return Color(v * (1.0 + dry * 0.05), v, v * (1.0 - dry * 0.07))

## 路边河湖：沿 z 的确定性包络让水面一段段出现/消失，宽度平滑收缩到零
## 按景观段增强：海岸段右侧常在大海、湖泊段两侧大湖，宽度随段权重渐变
func _water(start_z: float, side: float) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var steps := int(SPAN / SEG_LEN)
	var nx := 6
	var rows: Array[PackedInt32Array] = []
	for i in steps + 1:
		var zz: float = start_z - i * SEG_LEN
		var cx: float = _main.road_x(zz)
		var gy: float = _main.ground_y(zz)
		# 沿 z 周期出现的河湖段，左右岸错相；0~1 包络控制水面半宽
		var phase := zz * 0.0062 + (2.1 if side > 0.0 else 0.0)
		var env: float = clampf(sin(phase) * 2.2 - 0.55, 0.0, 1.0)
		var center := side * 150.0
		var half := 30.0 * env
		var sink := 0.22 * env
		var zw: float = _main.zone_weight(zz)
		match _main.zone_at(zz):
			"coast":
				if side > 0.0:
					center = 150.0
					half = maxf(half, 120.0 * zw)
					sink = maxf(sink, 1.5 * zw)
			"lake":
				center = side * 95.0
				half = maxf(half, 55.0 * zw)
				sink = maxf(sink, 0.8 * zw)
		var row: int = verts.size()
		var row_idx := PackedInt32Array()
		for j in nx + 1:
			var t := float(j) / nx
			# 岸边与地面齐平、中心下沉的碟形；half→0 时整条与地面齐平即隐形
			var xx: float = center + lerpf(-half, half, t)
			var y := gy - sin(t * PI) * sink
			verts.append(Vector3(cx + xx, y, zz))
			normals.append(Vector3.UP)
			colors.append(Color(1, 1, 1))
			row_idx.append(row + j)
		rows.append(row_idx)
	for i in steps:
		var a: PackedInt32Array = rows[i]
		var b: PackedInt32Array = rows[i + 1]
		for j in nx:
			indices.append(a[j]); indices.append(b[j + 1]); indices.append(a[j + 1])
			indices.append(a[j]); indices.append(b[j]); indices.append(b[j + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices
	return arr

## 公路波形护栏：每 RAIL_SEG 一段横梁（矩形截面挤出）+ 段首立柱，沿路随弯平移
func _rail(start_z: float, side: float) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var steps := int(SPAN / RAIL_SEG)
	for i in steps:
		var za := start_z - i * RAIL_SEG
		var zb := za - RAIL_SEG
		# 每 15 段留一处缺口（损毁护栏，末世感），立柱照旧
		var broken := fmod(float(i) + (1.0 if side > 0.0 else 7.0), 15.0) == 0.0
		var xa: float = _main.road_x(za) + side * RAIL_OFFSET
		var xb: float = _main.road_x(zb) + side * RAIL_OFFSET
		if not broken:
			_extrude_box(verts, normals, indices,
				Vector3(xa, _main.ground_y(za) + 0.72, za),
				Vector3(xb, _main.ground_y(zb) + 0.72, zb), 0.24, 0.3)
		# 立柱 0.12 宽 × 0.85 高，立于段首
		_extrude_box(verts, normals, indices,
			Vector3(xa, _main.ground_y(za) + 0.425, za + 0.15),
			Vector3(xa, _main.ground_y(za) + 0.425, za - 0.15), 0.12, 0.85)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = indices
	return arr

## 矩形截面沿 a→b（主要沿 Z）挤出盒子，宽为 X、高为 Y；6 面各自独立顶点+正确法线
func _extrude_box(verts: PackedVector3Array, normals: PackedVector3Array,
		indices: PackedInt32Array, a: Vector3, b: Vector3, half_x: float, height: float) -> void:
	var hy := height * 0.5
	# 局部角点：0-3 为 a 端（逆时针，朝 -Z 看），4-7 为 b 端
	var ca := [
		Vector3(-half_x, -hy, 0.0), Vector3(half_x, -hy, 0.0),
		Vector3(half_x, hy, 0.0), Vector3(-half_x, hy, 0.0),
	]
	var p: Array[Vector3] = []
	for c in ca:
		p.append(a + c)
	for c in ca:
		p.append(b + c)
	# 每面：4 角点索引（从面外看顺时针）+ 面法线
	var faces := [
		[[0, 1, 2, 3], Vector3.BACK],
		[[4, 7, 6, 5], Vector3.FORWARD],
		[[1, 2, 6, 5], Vector3.RIGHT],
		[[0, 4, 7, 3], Vector3.LEFT],
		[[2, 3, 7, 6], Vector3.UP],
		[[0, 1, 5, 4], Vector3.DOWN],
	]
	for f in faces:
		var base := verts.size()
		for idx in f[0]:
			verts.append(p[idx])
			normals.append(f[1])
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

## 山脊竖起伏带：内端埋入地平线、外端为起伏峰顶，宽度与峰高按层传入，双面材质配雾做纵深
func _ridge(start_z: float, side_x: float, width: float = 200.0, h_scale: float = 1.0) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var steps := int(SPAN / SEG_LEN)
	var x0 := side_x
	var x1 := side_x + (signf(side_x) * width)
	var face_n := Vector3(signf(side_x) * -1.0, 0.0, 0.0)
	for i in steps + 1:
		var zz: float = start_z - i * SEG_LEN
		var cx: float = _main.road_x(zz)
		var gy: float = _main.ground_y(zz)
		var h: float = (24.0 + sin(zz * 0.0041 + side_x) * 16.0
			+ sin(zz * 0.0013 + 3.0) * 26.0 + sin(zz * 0.011) * 5.0) * h_scale
		var xa: float = cx + x0
		var xb: float = cx + x1
		verts.append(Vector3(xa, gy - 3.0, zz)); normals.append(face_n)
		verts.append(Vector3(xb, gy + maxf(h, 8.0), zz)); normals.append(face_n)
	for i in steps:
		var r := i * 2
		indices.append(r); indices.append(r + 1); indices.append(r + 3)
		indices.append(r); indices.append(r + 3); indices.append(r + 2)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = indices
	return arr

func _mat(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	return m
