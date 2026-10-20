extends MeshInstance3D
## 无限地形：rebuild(start_z) 从 start_z 向前（-Z）重建 SPAN 长度条带。
## 多 surface：柏油路面 / 两侧路肩 / 边缘实线 / 中央黄虚线。

const SPAN := 900.0
const GROUND_Y := -1.56
const ROAD_HALF := 7.0
const SEG_LEN := 2.0
const DASH_PERIOD := 7.0
const DASH_LEN := 3.0

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
	# 0 超宽大地（远景地面，消除两侧露天空的空洞感）
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _band(start_z, -600.0, 600.0, -0.3, false, 8))
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
	if _mats.is_empty():
		_mats = [
			_mat(Color(0.17, 0.155, 0.135), 1.0),
			_mat(Color(0.21, 0.18, 0.15), 1.0),
			_mat(Color(0.21, 0.18, 0.15), 1.0),
			_mat(Color(0.115, 0.11, 0.105), 0.98),
			_mat(Color(0.5, 0.48, 0.43), 0.9),
			_mat(Color(0.5, 0.48, 0.43), 0.9),
			_mat(Color(0.58, 0.44, 0.17), 0.9),
		]
	for i in _mats.size():
		am.surface_set_material(i, _mats[i])
	return am

## 生成一条沿路弯曲的条带（x0/x1 为相对路中心的横向范围，nx 为横向细分数）
## 顶点叠加确定性多频噪声色，做出柏油/泥地旧化斑驳，避免纯色塑料感
func _band(start_z: float, x0: float, x1: float, y_off: float, dashed: bool, nx := 1) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var steps := int(SPAN / SEG_LEN)
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
		for j in nx + 1:
			var t := float(j) / nx
			var xx: float = lerpf(x0, x1, t)
			verts.append(Vector3(cxa + xx, ya, za))
			normals.append(Vector3.UP)
			colors.append(_mottle(cxa + xx, za))
		for j in nx + 1:
			var t := float(j) / nx
			var xx: float = lerpf(x0, x1, t)
			verts.append(Vector3(cxb + xx, yb, zb))
			normals.append(Vector3.UP)
			colors.append(_mottle(cxb + xx, zb))
		for j in nx:
			var a := row_a + j
			var b := row_a + j + 1
			var c := row_a + (nx + 1) + j + 1
			var d := row_a + (nx + 1) + j
			indices.append(a); indices.append(c); indices.append(b)
			indices.append(a); indices.append(d); indices.append(c)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices
	return arr

## 确定性多频噪声：0.78~1.12 灰度调制，重建时同位置颜色不变
func _mottle(x: float, z: float) -> Color:
	var n := sin(x * 0.91 + z * 0.37) * 0.5 + sin(x * 2.3 - z * 1.7) * 0.3 + sin(z * 4.7 + x * 0.4) * 0.2
	var v: float = clampf(0.95 + n * 0.09, 0.78, 1.12)
	return Color(v, v, v)

func _mat(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	return m
