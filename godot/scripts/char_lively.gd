class_name CharLively
extends Node
## 角色「活感」组件：周期眨眼 + 常态微表情 + 说话嘴动 + 闲置动作插播。
## 由 CharUtil.instantiate 自动挂载；表情基用 GLB 自带 morph target（Fcl_* 全套）。

const EYE_CLOSE := "Fcl_EYE_Close"
const MTH_A := "Fcl_MTH_A"
const BLINK_TIME := 0.12
const DEFAULT_EXPR := {"Fcl_ALL_Joy": 0.10}
# idle_stretch（伸懒腰双臂上举 2.8s）在车内狭小空间持续举手很怪，只保留转头的 idle_look
const IDLE_VARIANTS: Array[StringName] = [&"idle_look"]
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
var _in_combat := false   # 战斗据枪态：屏蔽闲置插播，shoot 结束回 aim
var _hold := &""          # 一次性动作结束后要回到的动作（变体回 _base，shoot 回 aim）

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
		# 仅 idle/sit 插播小动作；aim（射击孔射手）等姿势被 idle_look 打断会很怪
		var pool: Array[StringName] = []
		if _base == &"sit":
			pool = SIT_VARIANTS
		elif _base == &"idle":
			pool = IDLE_VARIANTS
		for v in pool:
			if _anim.has_animation(v):
				_anim.get_animation(v).loop_mode = Animation.LOOP_NONE
				_variants.append(v)
		if not _variants.is_empty():
			_anim.animation_finished.connect(_on_one_shot_done)
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
	if not _variants.is_empty() and _anim != null and not _in_combat and _t >= _next_variant:
		_next_variant = _t + randf_range(8.0, 16.0)
		_hold = _base
		_anim.play(_variants[randi() % _variants.size()], 0.3)

## 战斗动作：shoot 一次性、结束回 aim；reload 一次性、结束停在末帧等逻辑切回；aim 据枪循环
func play_combat(anim: StringName) -> void:
	if _anim == null or not _anim.has_animation(anim):
		return
	_in_combat = true
	# shoot/reload 是一次性动作：导入默认若被识别成循环会导致 animation_finished 不触发，显式压成 LOOP_NONE
	if anim == &"shoot" or anim == &"reload":
		_anim.get_animation(anim).loop_mode = Animation.LOOP_NONE
	match anim:
		&"shoot":
			if _anim.current_animation == &"reload" or (_anim.current_animation == &"shoot" and _anim.is_playing()):
				return
			_hold = &"aim"
			if not _anim.is_connected("animation_finished", _on_one_shot_done):
				_anim.animation_finished.connect(_on_one_shot_done)
			_anim.play(&"shoot", 0.1)
		&"reload":
			if _anim.current_animation != &"reload":
				_hold = &""
				_anim.play(&"reload", 0.2)
		&"aim":
			if _anim.current_animation != &"aim":
				_anim.play(&"aim", 0.25)

## 收枪结束战斗：恢复闲置插播并回基础姿态
func end_combat() -> void:
	_in_combat = false
	_hold = &""

func _on_one_shot_done(name: StringName) -> void:
	if _hold != &"":
		var back := _hold
		_hold = &""
		_anim.play(back, 0.3)

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
