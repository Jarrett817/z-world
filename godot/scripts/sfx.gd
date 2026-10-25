class_name Sfx
extends Node
## 音效中心：外部 CC0/CC-BY 素材统一播放（署名见 data/credits.json）。2D 池（UI/枪声/拾取）+ 3D 池（丧尸方位衰减）+ 引擎循环。

const DIR := "res://assets/sfx/"
const KEYS := ["gunshot", "reload", "zombie_die", "zombie_growl", "zombie_bite", "run_over", "pickup", "story_open", "engine"]
const POOL_2D := 8
const POOL_3D := 6

var _streams: Dictionary = {}
var _pool2d: Array[AudioStreamPlayer] = []
var _i2d := 0
var _pool3d: Array[AudioStreamPlayer3D] = []
var _i3d := 0
var _engine: AudioStreamPlayer

func _ready() -> void:
	for k in KEYS:
		_streams[k] = load(DIR + k + ".wav")
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool2d.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 55.0
		p.unit_size = 7.0
		add_child(p)
		_pool3d.append(p)
	# 引擎循环：WAV 首尾已交叉淡化为无缝接缝，LOOP_FORWARD 无咔哒
	var eng: AudioStreamWAV = _streams["engine"]
	eng.loop_mode = AudioStreamWAV.LOOP_FORWARD
	eng.loop_begin = 0
	eng.loop_end = eng.get_data().size() / 2
	_engine = AudioStreamPlayer.new()
	_engine.stream = eng
	add_child(_engine)

## 2D 播放：pitch 基准 + var_ 随机浮动，避免重复感
func play(key: String, pitch := 1.0, var_ := 0.07, vol := 0.0) -> void:
	var p := _pool2d[_i2d]
	_i2d = (_i2d + 1) % POOL_2D
	p.stream = _streams[key]
	p.pitch_scale = pitch * (1.0 + randf_range(-var_, var_))
	p.volume_db = vol
	p.play()

## 3D 播放：按世界坐标衰减（Sfx 父链无 3D 变换，global 即世界坐标）
func play3d(key: String, pos: Vector3, pitch := 1.0, var_ := 0.07, vol := 0.0) -> void:
	var p := _pool3d[_i3d]
	_i3d = (_i3d + 1) % POOL_3D
	p.stream = _streams[key]
	p.global_position = pos
	p.pitch_scale = pitch * (1.0 + randf_range(-var_, var_))
	p.volume_db = vol
	p.play()

## 引擎音随车速：speed01 = speed_kmh / 极速
func set_engine(speed01: float) -> void:
	if speed01 <= 0.02:
		if _engine.playing:
			_engine.stop()
		return
	if not _engine.playing:
		_engine.play()
	_engine.pitch_scale = 0.75 + speed01 * 0.85
	_engine.volume_db = -21.0 + speed01 * 11.0
