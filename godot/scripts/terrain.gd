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
var _mats: Array[Material] = []
var _col_shape: CollisionShape3D
var _build_active := false
var _pending_mesh: ArrayMesh
var _pending_start := 0.0
var _pending_surface := 0
var _col_map := PackedFloat32Array()
var _col_row := 0
var _col_z0 := 0.0

# 碰撞高度图：x ∈ ±400m 步长 2.5，z 覆盖条带前后各留余量（与视觉地面同一高度函数）
const COL_HALF_X := 400.0
const COL_STEP := 2.5
const COL_BACK := 40.0    # 条带起点向后（+Z）覆盖
const COL_FWD := 900.0    # 向前（-Z）覆盖
const SURFACE_COUNT := 17
const COL_ROWS_PER_FRAME := 12

func _ready() -> void:
	# 静态碰撞体常驻，shape 随 rebuild 换新（真实地形高度，丧尸/车/人贴地）
	var col := StaticBody3D.new()
	_col_shape = CollisionShape3D.new()
	col.add_child(_col_shape)
	add_child(col)

func rebuild(start_z: float, immediate := false) -> void:
	_main = get_parent()
	# 开局与里程跳转没有可保留的就近地形，必须同步完成；常规行驶重建分帧执行
	if immediate or mesh == null:
		_build_active = false
		_pending_mesh = null
		_col_map = PackedFloat32Array()
		mesh = _make_mesh(start_z)
		_rebuild_collision(start_z)
		return
	_pending_start = start_z
	_pending_mesh = ArrayMesh.new()
	_pending_surface = 0
	_col_row = 0
	_col_map = PackedFloat32Array()
	_ensure_materials()
	_build_active = true

## 每帧只生成一个视觉 surface 或一段碰撞行，旧网格与旧碰撞保留到新地形完整就绪
func _process(_delta: float) -> void:
	if not _build_active:
		return
	if _pending_surface < SURFACE_COUNT:
		var index := _pending_surface
		_pending_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _surface_arrays(index, _pending_start))
		_pending_mesh.surface_set_material(index, _mats[index])
		_pending_surface += 1
		return
	var w := int(COL_HALF_X * 2.0 / COL_STEP) + 1
	var d := int((COL_BACK + COL_FWD) / COL_STEP) + 1
	if _col_map.is_empty():
		_col_map.resize(w * d)
		_col_z0 = _pending_start + COL_BACK
	var end_row := mini(_col_row + COL_ROWS_PER_FRAME, d)
	while _col_row < end_row:
		var z := _col_z0 - (d - 1 - _col_row) * COL_STEP
		var gy: float = _main.ground_y(z)
		var rx: float = _main.road_x(z)
		var zone: String = _main.zone_at(z)
		var base := _col_row * w
		for xi in w:
			var x := -COL_HALF_X + xi * COL_STEP
			_col_map[base + xi] = _main.ground_height_c(x, z, gy, rx, zone)
		_col_row += 1
	if _col_row < d:
		return
	_apply_collision(_col_map, w, d, _col_z0)
	mesh = _pending_mesh
	_pending_mesh = null
	_col_map = PackedFloat32Array()
	_build_active = false

## 碰撞高度图：行缓存 gy/rx/zone，逐点取 ground_height_c，与视觉地面严格一致
func _rebuild_collision(start_z: float) -> void:
	var w := int(COL_HALF_X * 2.0 / COL_STEP) + 1
	var d := int((COL_BACK + COL_FWD) / COL_STEP) + 1
	var map := PackedFloat32Array()
	map.resize(w * d)
	var z0 := start_z + COL_BACK
	for zi in d:
		var z := z0 - (d - 1 - zi) * COL_STEP
		var gy: float = _main.ground_y(z)
		var rx: float = _main.road_x(z)
		var zone: String = _main.zone_at(z)
		var base := zi * w
		for xi in w:
			var x := -COL_HALF_X + xi * COL_STEP
			map[base + xi] = _main.ground_height_c(x, z, gy, rx, zone)
	_apply_collision(map, w, d, z0)

func _apply_collision(map: PackedFloat32Array, w: int, d: int, z0: float) -> void:
	var hm := HeightMapShape3D.new()
	hm.map_width = w
	hm.map_depth = d
	hm.map_data = map
	_col_shape.shape = hm
	_col_shape.scale = Vector3(COL_STEP, 1.0, COL_STEP)
	_col_shape.position = Vector3(0.0, 0.0, z0 - (d - 1) * COL_STEP * 0.5)

func _make_mesh(start_z: float) -> ArrayMesh:
	_ensure_materials()
	var am := ArrayMesh.new()
	for i in SURFACE_COUNT:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _surface_arrays(i, start_z))
		am.surface_set_material(i, _mats[i])
	return am

func _surface_arrays(index: int, start_z: float) -> Array:
	match index:
		0:
			var gxs := PackedFloat32Array([-600.0, -380.0, -220.0, -180.0])
			for xi in range(-52, 53):
				gxs.append(float(xi) * COL_STEP)
			gxs.append_array(PackedFloat32Array([180.0, 220.0, 380.0, 600.0]))
			return _band(start_z, 0.0, 0.0, -0.3, false, 1, gxs)
		1:
			return _band(start_z, -ROAD_HALF - 16.0, -ROAD_HALF, -0.05, false, 2)
		2:
			return _band(start_z, ROAD_HALF, ROAD_HALF + 16.0, -0.05, false, 2)
		3:
			# 柏油必须连续；横向细分只用于车辙与修补斑块顶点色
			return _band(start_z, -ROAD_HALF, ROAD_HALF, 0.0, false, 8)
		4:
			return _band(start_z, -ROAD_HALF + 0.35, -ROAD_HALF + 0.65, 0.02, false)
		5:
			return _band(start_z, ROAD_HALF - 0.65, ROAD_HALF - 0.35, 0.02, false)
		6:
			return _band(start_z, -0.12, 0.12, 0.02, true)
		7:
			return _rail(start_z, -1.0)
		8:
			return _rail(start_z, 1.0)
		9:
			return _ridge(start_z, -150.0)
		10:
			return _ridge(start_z, 150.0)
		11:
			return _ridge(start_z, -380.0, 280.0, 0.6)
		12:
			return _ridge(start_z, 380.0, 280.0, 0.6)
		13:
			return _water(start_z, -1.0)
		14:
			return _water(start_z, 1.0)
		15:
			return _side_roads(start_z, false)
		_:
			return _side_roads(start_z, true)

func _ensure_materials() -> void:
	if not _mats.is_empty():
		return
	var rail_mat := _mat(Color(0.48, 0.55, 0.58), 0.8)
	rail_mat.metallic = 0.15
	# 远山走大气透视：近山蓝绿灰、远山淡青蓝（越远越偏天色），告别绿色塑料薄片
	var ridge_mat := _mat(Color(0.42, 0.58, 0.58), 1.0)
	ridge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ridge_far_mat := _mat(Color(0.6, 0.72, 0.83), 1.0)
	ridge_far_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 湖面/海面：片元卡通波光，双频正弦亮纹随时间漂移，近岸浅远水深，不扰动顶点避免碟形岸沿离缝
	var water_mat := ShaderMaterial.new()
	var wsh := Shader.new()
	wsh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 shallow_col : source_color = vec3(0.26, 0.55, 0.62);
uniform vec3 deep_col : source_color = vec3(0.09, 0.27, 0.38);
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 w = wpos.xz;
	float r1 = sin(w.x * 0.35 + TIME * 1.3) + sin(w.y * 0.27 - TIME * 0.9);
	float r2 = sin((w.x + w.y) * 0.12 + TIME * 0.5);
	float glint = smoothstep(1.25, 1.95, r1 + r2 * 0.8);
	float depth = smoothstep(0.2, 0.85, COLOR.r);
	vec3 base = mix(shallow_col, deep_col, depth);
	ALBEDO = base + vec3(0.35, 0.42, 0.45) * glint;
	ROUGHNESS = 0.18;
	METALLIC = 0.25;
}
"""
	water_mat.shader = wsh
	_mats = [
		_mat(Color(0.20, 0.38, 0.17), 1.0),
		_mat(Color(0.34, 0.43, 0.22), 1.0),
		_mat(Color(0.34, 0.43, 0.22), 1.0),
		_mat(Color(0.12, 0.145, 0.17), 0.95),
		_mat(Color(0.75, 0.78, 0.72), 0.9),
		_mat(Color(0.75, 0.78, 0.72), 0.9),
		_mat(Color(0.95, 0.72, 0.25), 0.9),
		rail_mat,
		rail_mat,
		ridge_mat,
		ridge_mat,
		ridge_far_mat,
		ridge_far_mat,
		water_mat,
		water_mat,
		_mat(Color(0.29, 0.235, 0.155), 1.0),
		_mat(Color(0.13, 0.125, 0.12), 0.98),
	]

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
		var za := start_z - i * SEG_LEN
		# 虚线相位使用世界坐标，流式重建后图案不跳动
		if dashed and fposmod(za, DASH_PERIOD) > DASH_LEN:
			continue
		var zb := start_z - (i + 1) * SEG_LEN
		var cxa: float = _main.road_x(za)
		var cxb: float = _main.road_x(zb)
		var gya: float = _main.ground_y(za)
		var gyb: float = _main.ground_y(zb)
		var ya: float = gya + y_off
		var yb: float = gyb + y_off
		var zone_a: String = _main.zone_at(za) if use_xs else ""
		var zone_b: String = _main.zone_at(zb) if use_xs else ""
		var row_a: int = verts.size()
		for j in enx + 1:
			var xx: float = xs[j] if use_xs else lerpf(x0, x1, float(j) / nx)
			var height: float = _main.ground_height_c(cxa + xx, za, gya, cxa, zone_a) - 0.02 if use_xs else ya
			verts.append(Vector3(cxa + xx, height, za))
			normals.append(Vector3.UP)
			colors.append(_mottle(cxa + xx, za, zone_a, use_xs))
		for j in enx + 1:
			var xx: float = xs[j] if use_xs else lerpf(x0, x1, float(j) / nx)
			var height: float = _main.ground_height_c(cxb + xx, zb, gyb, cxb, zone_b) - 0.02 if use_xs else yb
			verts.append(Vector3(cxb + xx, height, zb))
			normals.append(Vector3.UP)
			colors.append(_mottle(cxb + xx, zb, zone_b, use_xs))
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

## 低对比多频色块：保留手绘式明暗变化，不让高频脏噪声盖过卡通色板
## 公路带内保留轻量轮迹与修补斑块，重建时同位置颜色不变
## 野外大地按景观段染不同草色、叠草地斑块，并随离路距离做近鲜远淡的地面大气透视
func _mottle(x: float, z: float, zone: String = "", is_ground := false) -> Color:
	var n := sin(x * 0.91 + z * 0.37) * 0.5 + sin(x * 2.3 - z * 1.7) * 0.3 + sin(z * 4.7 + x * 0.4) * 0.2
	var v: float = clampf(0.98 + n * 0.045, 0.9, 1.06)
	var dx: float = absf(x - _main.road_x(z))
	if is_ground and dx >= ROAD_HALF:
		var zmul: Color = {
			"plain": Color(1.05, 1.0, 0.84),
			"forest": Color(0.72, 0.9, 0.68),
			"hills": Color(0.92, 1.0, 0.78),
			"mountain": Color(0.76, 0.85, 0.76),
			"lake": Color(0.97, 1.02, 0.88),
			"coast": Color(1.04, 0.96, 0.8),
			"city": Color(0.9, 0.86, 0.78),
		}.get(zone, Color(0.98, 1.0, 0.9))
		# 大块低频明暗当坡面光影，叠一层中频斑块打破塑料平涂
		var big: float = sin(x * 0.045 + z * 0.02) * 0.6 + sin(x * 0.017 - z * 0.033) * 0.4
		var mid: float = sin(x * 0.13 + z * 0.09) * 0.5 + sin(x * 0.05 - z * 0.11) * 0.5
		var c := Color(v, v, v) * zmul * (1.0 + big * 0.14 + mid * 0.045)
		var far: float = smoothstep(60.0, 240.0, dx)
		return c.lerp(Color(0.72, 0.8, 0.87), far * 0.4)
	var dry: float = sin(x * 0.05 + z * 0.031) * 0.5 + sin(x * 0.013 - z * 0.017) * 0.5
	if dx < ROAD_HALF:
		var wear: float = smoothstep(1.1, 1.7, dx) * (1.0 - smoothstep(2.6, 3.2, dx))
		v *= 1.0 - wear * 0.12
		if sin(z * 0.023 + 1.7) * sin(z * 0.11) > 0.72:
			v *= 0.94
	return Color(v * (1.0 + dry * 0.035), v, v * (1.0 - dry * 0.045))

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
					# 海面收窄贴岸（10~170m）：车载视角下清晰可见，否则 150m 外被透视压成细线融进远山
					center = 90.0
					half = maxf(half, 80.0 * zw)
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
			var sag := sin(t * PI) * sink
			var y := gy - sag
			verts.append(Vector3(cx + xx, y, zz))
			normals.append(Vector3.UP)
			# 顶点色 r 编码归一化水深（碟心最深），供水面 shader 近岸浅/远水深混色
			colors.append(Color(clampf(sag / 1.5, 0.0, 1.0), 1, 1))
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

## 岔路条带：cross=false 土路支路（斜出主路、末端收窄），cross=true 沥青十字路口
## 窗口内无对应岔路时塞地底退化三角形（add_surface 不允许空数组）
func _side_roads(start_z: float, cross: bool) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for j in _main.junctions_in(start_z, start_z - SPAN):
		if (int(j["kind"]) == 1) != cross:
			continue
		if cross:
			_cross_road(verts, normals, colors, indices, j)
		else:
			_branch_road(verts, normals, colors, indices, j)
	if verts.is_empty():
		verts.append_array([Vector3(0, -500, 0), Vector3(1, -500, 0), Vector3(0, -500, 1)])
		normals.append_array([Vector3.UP, Vector3.UP, Vector3.UP])
		colors.append_array([Color.WHITE, Color.WHITE, Color.WHITE])
		indices.append_array([0, 1, 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices
	return arr

## 土路支路：普通岔路末端收窄；探索支线经过 POI 后以平滑弯道回接下一处主路
func _branch_road(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, indices: PackedInt32Array, j: Dictionary) -> void:
	var zj: float = j["z"]
	var side: float = j["side"]
	var dir := Vector3(side * sin(j["ang"]), 0, -cos(j["ang"])).normalized()
	var org := Vector3(_main.road_x(zj) + side * (ROAD_HALF - 0.8), 0, zj)
	var seg := 3.0
	var steps := int(j["len"] / seg)
	var is_loop := bool(j.get("loop", false))
	var points: Array[Vector3] = []
	for i in steps + 1:
		points.append(org + dir * (i * seg))
	if is_loop:
		# 三次贝塞尔：出发方向沿支路，回接方向顺主路，避免 POI 后出现锐角掉头
		var p0: Vector3 = points[-1]
		var p1 := p0 + dir * 18.0
		var rejoin_z: float = j["rejoin_z"]
		var p3 := Vector3(_main.road_x(rejoin_z) + side * (ROAD_HALF - 0.8), 0, rejoin_z)
		var p2 := p3 + Vector3(0, 0, 22.0)
		var return_steps := maxi(12, int((p0.distance_to(p1) + p1.distance_to(p2) + p2.distance_to(p3)) / seg))
		for i in range(1, return_steps + 1):
			var t := float(i) / return_steps
			var u := 1.0 - t
			points.append(p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t))
	for i in points.size():
		var p: Vector3 = points[i]
		var tangent: Vector3
		if i == 0:
			tangent = points[1] - p
		elif i == points.size() - 1:
			tangent = p - points[i - 1]
		else:
			tangent = points[i + 1] - points[i - 1]
		tangent.y = 0.0
		tangent = tangent.normalized()
		var perp := Vector3(-tangent.z, 0, tangent.x)
		var t := float(i) / steps
		var half := 2.6
		if not is_loop and t >= 0.85:
			half *= maxf(0.15, (1.0 - t) / 0.15)
		var y: float = _main.ground_height(p.x, p.z) + 0.015
		var row: int = verts.size()
		verts.append(Vector3(p.x - perp.x * half, y, p.z - perp.z * half))
		verts.append(Vector3(p.x + perp.x * half, y, p.z + perp.z * half))
		normals.append_array([Vector3.UP, Vector3.UP])
		colors.append_array([_mottle(p.x, p.z), _mottle(p.x, p.z)])
		if i > 0:
			var a := row - 2
			indices.append_array([a, a + 2, a + 3, a, a + 3, a + 1])

## 沥青十字路口：垂直主路横穿 ±80m，略抬高避免与主路 z-fight
func _cross_road(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, indices: PackedInt32Array, j: Dictionary) -> void:
	var zj: float = j["z"]
	var cx: float = _main.road_x(zj)
	var half_w := 4.2
	var step := 4.0
	var steps := int(160.0 / step)
	for i in steps + 1:
		var x := cx - 80.0 + i * step
		var y: float = _main.ground_y(zj) + 0.012
		var row: int = verts.size()
		verts.append(Vector3(x, y, zj - half_w))
		verts.append(Vector3(x, y, zj + half_w))
		normals.append_array([Vector3.UP, Vector3.UP])
		colors.append_array([_mottle(x, zj), _mottle(x, zj)])
		if i > 0:
			var a := row - 2
			indices.append_array([a, a + 2, a + 3, a, a + 3, a + 1])

## 公路波形护栏：每 RAIL_SEG 一段横梁（矩形截面挤出）+ 段首立柱，沿路随弯平移
func _rail(start_z: float, side: float) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var steps := int(SPAN / RAIL_SEG)
	for i in steps:
		var za := start_z - i * RAIL_SEG
		var zb := za - RAIL_SEG
		# 每 15 段留一处缺口（损毁护栏，末世感）；岔口与回接口的横梁、立柱一起断开
		var broken: bool = fmod(float(i) + (1.0 if side > 0.0 else 7.0), 15.0) == 0.0 \
			or _main.junction_gap((za + zb) * 0.5, side)
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
		# 峰高压低：原最高 71m 会顶出屏幕上缘、被雾洗成"巨墙"；压低后波浪脊线入画才读得出山形
		var h: float = (9.0 + sin(zz * 0.0041 + side_x) * 6.0
			+ sin(zz * 0.0013 + 3.0) * 9.5 + sin(zz * 0.011) * 2.0) * h_scale
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
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	return m
