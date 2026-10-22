class_name CharLively
extends Node
## 角色「活感」组件：周期眨眼 + 常态微表情 + 说话嘴动 + 闲置动作插播。
## 由 CharUtil.instantiate 自动挂载；表情基用 GLB 自带 morph target（Fcl_* 全套）。

const EYE_CLOSE := "Fcl_EYE_Close"
const MTH_A := "Fcl_MTH_A"
const BLINK_TIME := 0.12
const DEFAULT_EXPR := {"Fcl_ALL_Joy": 0.10}
const IDLE_VARIANTS: Array[StringName] = [&"idle_look", &"idle_stretch"]
const SIT_VARIANTS: Array[StringName] = [&"sit_talk"]

var _face: MeshInstance3D
var _eye_idx := -1
var _mth_idx := -1
var _anim: AnimationPlayer
var _base := &"idle"
var _variants: Array[StringName] = []
var _t := 0.0
var _next_blink := 0.0
var _blink_left := 0.0
var _talk_left := 0.0
var _next_variant := 0.0
var _expr: Dictionary = {}

func _init(expr: Dictionary = {}, base_anim: String = "idle") -> void:
	_expr = expr if not expr.is_empty() else DEFAULT_EXPR
	_base = StringName(base_anim)

func _ready() -> void:
	var root := get_parent()
	_face = _find_face(root)
	if _face != null:
		_eye_idx = _face.find_blend_shape_by_name(EYE_CLOSE)
		_mth_idx = _face.find_blend_shape_by_name(MTH_A)
		_apply_expression()
	_anim = root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim != null:
		var pool := SIT_VARIANTS if _base == &"sit" else IDLE_VARIANTS
		for v in pool:
			if _anim.has_animation(v):
				_anim.get_animation(v).loop_mode = Animation.LOOP_NONE
				_variants.append(v)
		if not _variants.is_empty():
			_anim.animation_finished.connect(_on_variant_done)
	_next_blink = randf_range(1.0, 3.0)
	_next_variant = randf_range(6.0, 12.0)

## 说话嘴动：气泡展示期间嘴部张合
func talk(dur: float) -> void:
	_talk_left = dur

func _process(delta: float) -> void:
	_t += delta
	if _face != null and _eye_idx >= 0:
		if _blink_left > 0.0:
			_blink_left = maxf(_blink_left - delta, 0.0)
			_face.set_blend_shape_value(_eye_idx, sin((1.0 - _blink_left / BLINK_TIME) * PI))
		elif _t >= _next_blink:
			_blink_left = BLINK_TIME
			_next_blink = _t + randf_range(2.2, 4.8)
	if _face != null and _mth_idx >= 0 and _talk_left > 0.0:
		_talk_left = maxf(_talk_left - delta, 0.0)
		_face.set_blend_shape_value(_mth_idx, absf(sin(_t * 13.0)) * 0.75 * minf(_talk_left, 1.0))
	if not _variants.is_empty() and _anim != null and _t >= _next_variant:
		_next_variant = _t + randf_range(8.0, 16.0)
		_anim.play(_variants[randi() % _variants.size()], 0.3)

func _on_variant_done(_name: StringName) -> void:
	_anim.play(_base, 0.3)

func _apply_expression() -> void:
	for k in _expr:
		var idx := _face.find_blend_shape_by_name(String(k))
		if idx >= 0:
			_face.set_blend_shape_value(idx, float(_expr[k]))

static func _find_face(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and n.get_blend_shape_count() > 0:
		return n
	for c in n.get_children():
		var r := _find_face(c)
		if r != null:
			return r
	return null
