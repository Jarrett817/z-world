extends Node3D
## 下车协同作战的队友：跟随玩家（背后扇形站位），自动索敌据枪射击，贴身应急反杀。
## 仅 ground 下车模式生成，回车即回收；本轮队友不设死亡（与幸存者同理）。

const FOLLOW_SPEED := 7.2    # 略快于玩家跑速，保证跟上
const FIRE_RANGE := 16.0
const FIRE_CD := 1.3

# 背后扇形站位偏移（x 横向 / z 玩家背后距离），按 slot 取
const SLOTS := [
	Vector2(-1.8, 2.2), Vector2(1.8, 2.2), Vector2(-3.0, 3.8),
	Vector2(3.0, 3.8), Vector2(0.0, 3.0),
]

var crew_id := ""
var _slot := 0
var _main: Node3D
var _player: Node3D
var _anim: AnimationPlayer
var _muzzle: Node3D
var _fire_cd := 0.0
var _cur_anim := ""

## main.gd 在 add_child 前调用：指定队友 id 与站位序号
func setup(cid: String, slot: int) -> void:
	crew_id = cid
	_slot = clampi(slot, 0, SLOTS.size() - 1)

func _ready() -> void:
	_main = get_parent()
	_player = _main.get_player_body()
	# 战斗态自管 run/walk/aim，关掉活感插播（CharLively 会周期性打断据枪）
	var made := CharUtil.instantiate(crew_id, "run", {}, false)
	add_child(made["node"])
	_anim = made["anim"]
	if _anim != null:
		for a in ["run", "walk", "aim"]:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	# 自带武器：与玩家同款步枪，挂点按 aim 动作对位
	var gun := CharUtil.build_gun()
	gun.position = Vector3(-0.12, 1.30, 0.33)
	made["node"].add_child(gun)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.04, 0.72)
	gun.add_child(_muzzle)

func _process(delta: float) -> void:
	if _main.game_over:
		return
	_fire_cd -= delta
	if not is_instance_valid(_player):
		_player = _main.get_player_body()
		if _player == null:
			return
	# 索敌：射程内最近丧尸优先据枪射击
	var z := _nearest_zombie(FIRE_RANGE)
	if z != null:
		_face(z.global_position, delta)
		if _fire_cd <= 0.0:
			_fire_at(z)
		_play("aim")
		return
	# 无威胁：回到玩家背后扇形站位
	var off: Vector2 = SLOTS[_slot]
	var anchor: Vector3 = _player.global_position \
		+ Basis(Vector3.UP, _player.aim_yaw) * Vector3(off.x, 0.0, off.y)
	var to := anchor - global_position
	to.y = 0.0
	if to.length() > 0.5:
		var spd: float = FOLLOW_SPEED if to.length() > 4.0 else 3.2
		var dir := to.normalized()
		global_position += dir * minf(spd * delta, to.length())
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 10.0)
		_play("run" if to.length() > 4.0 else "walk")
	else:
		# 就位后面向玩家瞄准方向戒备
		rotation.y = lerp_angle(rotation.y, _player.aim_yaw + PI, delta * 4.0)
		_play("aim")
	global_position.y = _main.ground_y(global_position.z)

## 丧尸贴身啃咬钩子：应急反杀
func on_bitten(z: Node3D) -> void:
	_face(z.global_position, 1.0)
	_fire_at(z)

func _fire_at(z: Node3D) -> void:
	_fire_cd = FIRE_CD
	_main.spawn_muzzle_flash(_muzzle.global_position, z.global_position + Vector3(0, 1.1, 0))
	_main.sfx.play3d("gunshot", global_position, 0.9, 0.08)
	z.on_shot()

func _face(target: Vector3, delta: float) -> void:
	var to := target - global_position
	if Vector2(to.x, to.z).length() < 0.05:
		return
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), delta * 8.0)

func _nearest_zombie(max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for z in _main.zombies:
		if is_instance_valid(z) and not z.dead:
			var d := global_position.distance_to(z.global_position)
			if d < best_d:
				best_d = d
				best = z
	return best

func _play(anim_name: String) -> void:
	if anim_name == _cur_anim:
		return
	if _anim != null and _anim.has_animation(anim_name):
		_cur_anim = anim_name
		_anim.play(anim_name, 0.15)
