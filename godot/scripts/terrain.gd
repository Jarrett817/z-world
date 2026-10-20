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
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _band(start_z, -600.0, 600.0, -0.3, false))
	# 1/2 两侧路肩土带
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _band(start_z, -ROAD_HALF - 16.0, -ROAD_HALF, -0.05, false))
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _band(start_z, ROAD_HALF, ROAD_HALF + 16.0, -0.05, false))
	# 3 柏油路面
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _band(start_z, -ROAD_HALF, ROAD_HALF, 0.0, false))
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

## 生成一条沿路弯曲的条带（x0/x1 为相对路中心的横向范围）
func _band(start_z: float, x0: float, x1: float, y_off: float, dashed: bool) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
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
		var a := Vector3(cxa + x0, ya, za)
		var b := Vector3(cxa + x1, ya, za)
		var c := Vector3(cxb + x1, yb, zb)
		var d := Vector3(cxb + x0, yb, zb)
		var base := verts.size()
		verts.append(a); verts.append(b); verts.append(c); verts.append(d)
		for k in 4:
			normals.append(Vector3.UP)
		indices.append(base); indices.append(base + 2); indices.append(base + 1)
		indices.append(base); indices.append(base + 3); indices.append(base + 2)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = indices
	return arr

func _mat(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m
