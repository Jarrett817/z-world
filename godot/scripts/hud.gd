extends CanvasLayer
## HUD：状态面板 + 车速表 + 驾驶摇杆 + toast + 结算界面。
## 末世暖调：篝火橙 #e8862e / 面板 #2a2320 / 主文字 #e8ded2 / 次文字 #8a7d6d。

const ACCENT := Color("e8862e")
const TEXT_MAIN := Color("e8ded2")
const TEXT_DIM := Color("8a7d6d")
const BAR_W := 240.0
const RESOLUTIONS: Array = [[1280, 720], [1600, 900], [1920, 1080], [2560, 1440]]

## 虚拟摇杆：手游战斗移动输入，输出 -1..1 向量（推满自动奔跑由 player 判定）
class Joystick:
	extends Control
	var knob := Vector2.ZERO
	var _active := false
	signal moved(v: Vector2)

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 62.0, Color(0, 0, 0, 0.28))
		draw_arc(c, 62.0, 0.0, TAU, 48, Color(0.91, 0.53, 0.18, 0.85), 3.0)
		draw_circle(c + knob * 36.0, 26.0, Color(0.91, 0.53, 0.18, 0.75))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventScreenTouch:
			_active = e.pressed
			if _active:
				_update(e.position)
			else:
				knob = Vector2.ZERO
				moved.emit(knob)
				queue_redraw()
		elif e is InputEventScreenDrag and _active:
			_update(e.position)

	func release() -> void:
		if not _active and knob == Vector2.ZERO:
			return
		_active = false
		knob = Vector2.ZERO
		moved.emit(knob)
		queue_redraw()

	func _update(p: Vector2) -> void:
		var v := (p - size * 0.5) / 38.0
		if v.length() > 1.0:
			v = v.normalized()
		knob = v
		moved.emit(knob)
		queue_redraw()

var rv: Node
var speed_label: Label
var res_label: Label
var info_label: Label
var weather_label: Label
var journey_label: Label
var dur_fill: ColorRect
var fuel_fill: ColorRect
var toast_label: Label
var over_root: ColorRect
var over_stats: Label
var victory_root: ColorRect
var victory_stats: Label
var crew_panel: Panel
var crew_rows: VBoxContainer
var crew_visible := false
var facilities_root: Panel
var facilities_rows: VBoxContainer
var facilities_title: Label
var credits_root: Panel
var credits_rows: VBoxContainer
var pause_root: ColorRect
var settings_root: ColorRect
var _setting_sliders: Dictionary = {}         # key -> HSlider
var _setting_value_labels: Dictionary = {}   # key -> 百分比 Label
var _fullscreen_btn: Button
var _res_opt: OptionButton
var drive_joystick: Control
var drive_misc_buttons: Array[Button] = []   # 视角/驻车/天窗/下车/车内（战斗时连同驾驶摇杆一起收起）
var combat_fire_buttons: Array[Button] = []   # 车内行走时要藏起来的开火类按钮
var combat_stance_buttons: Array[Button] = [] # 跳跃/下蹲：车顶卧姿时隐藏
var combat_joystick: Control
var _tab_down := false
var _toast_tween: Tween

# 下车/天窗战斗层
var combat_root: Control
var crosshair: Label
var combat_hint: Label
var ammo_label: Label
var gun_label: Label
var _cur_gun_name := ""
var _grenade_count := 0
var _cur_mag: int = 12
var combat_hp_fill: ColorRect
var combat_hp_label: Label
var _hit_tween: Tween

# 电台剧情对话框
var story_node: Node
var story_root: Panel
var story_pic: TextureRect
var story_speaker: Label
var story_text: Label
var story_options: VBoxContainer
var story_event_id := ""
var _full_text := ""
var _shown := 0
var _type_t := 0.0
var _skip_down := false
var morale_fill: ColorRect

func build(rv_node: Node) -> void:
	rv = rv_node
	# Esc 暂停菜单需要暂停期间仍能响应点击
	process_mode = Node.PROCESS_MODE_ALWAYS
	var theme := Theme.new()
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "sans-serif"])
	theme.default_font = f
	theme.default_font_size = 16

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	add_child(root)

	# 左上状态面板
	var panel := _panel(Vector2(12, 12), Vector2(348, 164))
	root.add_child(panel)
	panel.add_child(_label("车况", 15, TEXT_DIM, Vector2(14, 10)))
	dur_fill = _add_bar(panel, Vector2(58, 13))
	panel.add_child(_label("燃料", 15, TEXT_DIM, Vector2(14, 36)))
	fuel_fill = _add_bar(panel, Vector2(58, 39))
	panel.add_child(_label("士气", 15, TEXT_DIM, Vector2(14, 62)))
	morale_fill = _add_bar(panel, Vector2(58, 65))
	res_label = _label("食物 0 · 队伍 0 人", 15, TEXT_MAIN, Vector2(14, 92))
	panel.add_child(res_label)
	info_label = _label("里程 0.0 km · 第 1 天 09:00", 15, TEXT_DIM, Vector2(14, 120))
	panel.add_child(info_label)

	# 右上操作提示
	var hint := _label("W/A/S/D 驾驶 · C 换视角 · F 驻车 · G 下车战斗 · T 天窗 · Q 点按车内/接管 · E 设施 · V 射击视角 · Tab 队伍 · Esc 菜单", 14, TEXT_DIM)
	hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint.offset_left = -958
	hint.offset_right = -308
	hint.offset_top = 14
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(hint)

	# 天气
	weather_label = _label("天气 晴", 15, TEXT_DIM)
	weather_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	weather_label.offset_left = -200
	weather_label.offset_right = -14
	weather_label.offset_top = 50
	weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(weather_label)

	# 顶部旅程条：前方地点 + 距离（在操作提示下一行，避免重叠）
	journey_label = _label("", 15, TEXT_DIM)
	journey_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	journey_label.offset_left = -400
	journey_label.offset_right = 400
	journey_label.offset_top = 38
	journey_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(journey_label)

	# 车速表
	speed_label = _label("0 km/h", 40, TEXT_MAIN)
	speed_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	speed_label.offset_left = -120
	speed_label.offset_right = 120
	speed_label.offset_top = -88
	speed_label.offset_bottom = -30
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(speed_label)

	# toast 提示
	toast_label = _label("", 20, ACCENT)
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.offset_left = -320
	toast_label.offset_right = 320
	toast_label.offset_top = 60
	toast_label.offset_bottom = 96
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.modulate.a = 0.0
	root.add_child(toast_label)

	# 左侧驾驶摇杆：前推前进，后拉先刹停再倒车，左右转向
	drive_joystick = Joystick.new()
	drive_joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	drive_joystick.offset_left = 36
	drive_joystick.offset_top = -206
	drive_joystick.offset_right = 186
	drive_joystick.offset_bottom = -56
	drive_joystick.moved.connect(func(v: Vector2) -> void:
		rv.touch_throttle = -v.y
		rv.touch_steer = -v.x)
	root.add_child(drive_joystick)
	drive_misc_buttons.append(_touch_button(root, "视角", Control.PRESET_BOTTOM_RIGHT, Rect2(-176, -222, 78, 56), "view"))
	drive_misc_buttons.append(_touch_button(root, "驻车", Control.PRESET_BOTTOM_RIGHT, Rect2(-90, -222, 78, 56), "park"))
	drive_misc_buttons.append(_touch_button(root, "天窗", Control.PRESET_BOTTOM_RIGHT, Rect2(-176, -284, 78, 56), "sunroof"))
	drive_misc_buttons.append(_touch_button(root, "下车", Control.PRESET_BOTTOM_RIGHT, Rect2(-90, -284, 78, 56), "exitveh"))
	drive_misc_buttons.append(_touch_button(root, "点按·车内", Control.PRESET_BOTTOM_RIGHT, Rect2(-176, -346, 78, 56), "rvwalk"))
	# 右上：署名 / 队伍 / 设施（手游触屏替代 Tab/E 快捷键）
	_touch_button(root, "署名", Control.PRESET_TOP_RIGHT, Rect2(-292, 14, 88, 46), "credits")
	_touch_button(root, "队伍", Control.PRESET_TOP_RIGHT, Rect2(-196, 14, 88, 46), "crew")
	_touch_button(root, "设施", Control.PRESET_TOP_RIGHT, Rect2(-100, 14, 88, 46), "fac")

	# 队伍面板（Tab 开关）
	crew_panel = _panel(Vector2.ZERO, Vector2.ZERO)
	crew_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	crew_panel.offset_left = -342
	crew_panel.offset_top = 70
	crew_panel.offset_right = -14
	crew_panel.offset_bottom = 470
	crew_panel.visible = false
	root.add_child(crew_panel)
	# 成员多时滚动：面板高度封顶，列表包 ScrollContainer
	var crew_scroll := ScrollContainer.new()
	crew_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	crew_scroll.offset_left = 12
	crew_scroll.offset_top = 12
	crew_scroll.offset_right = -12
	crew_scroll.offset_bottom = -12
	crew_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	crew_panel.add_child(crew_scroll)
	crew_rows = VBoxContainer.new()
	crew_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crew_rows.add_theme_constant_override("separation", 10)
	crew_scroll.add_child(crew_rows)

	# 房车设施面板（驻车时 E 开关，底部居中）
	facilities_root = Panel.new()
	facilities_root.anchor_left = 0.5
	facilities_root.anchor_right = 0.5
	facilities_root.anchor_top = 1.0
	facilities_root.anchor_bottom = 1.0
	facilities_root.offset_left = -306
	facilities_root.offset_right = 306
	facilities_root.offset_top = -372
	facilities_root.offset_bottom = -28
	facilities_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.105, 0.085, 0.07, 0.96)
	fsb.set_border_width_all(2)
	fsb.border_color = Color(0.91, 0.53, 0.18, 0.75)
	fsb.set_corner_radius_all(12)
	fsb.content_margin_left = 16
	fsb.content_margin_right = 16
	fsb.content_margin_top = 12
	fsb.content_margin_bottom = 12
	facilities_root.add_theme_stylebox_override("panel", fsb)
	facilities_root.visible = false
	root.add_child(facilities_root)
	var fac_margin := MarginContainer.new()
	fac_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	fac_margin.add_theme_constant_override("margin_left", 16)
	fac_margin.add_theme_constant_override("margin_right", 16)
	fac_margin.add_theme_constant_override("margin_top", 12)
	fac_margin.add_theme_constant_override("margin_bottom", 12)
	fac_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	facilities_root.add_child(fac_margin)
	var fac_vbox := VBoxContainer.new()
	fac_vbox.add_theme_constant_override("separation", 8)
	fac_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fac_margin.add_child(fac_vbox)
	# 标题行：标题 + 显式收起按钮（手机端无 E 键，必须有点击入口）
	var fac_title_row := HBoxContainer.new()
	fac_title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fac_vbox.add_child(fac_title_row)
	facilities_title = _label("", 18, ACCENT, Vector2.ZERO)
	facilities_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facilities_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fac_title_row.add_child(facilities_title)
	var fac_close := _facility_button("收起", true)
	fac_close.pressed.connect(func() -> void: rv.main_node.set_facilities_ui(false))
	fac_title_row.add_child(fac_close)
	facilities_rows = VBoxContainer.new()
	facilities_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	facilities_rows.add_theme_constant_override("separation", 6)
	facilities_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fac_vbox.add_child(facilities_rows)

	# 素材署名面板（居中，右上「署名」按钮开关）
	credits_root = Panel.new()
	credits_root.set_anchors_preset(Control.PRESET_CENTER)
	credits_root.offset_left = -320
	credits_root.offset_top = -290
	credits_root.offset_right = 320
	credits_root.offset_bottom = 290
	credits_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var crsb := StyleBoxFlat.new()
	crsb.bg_color = Color(0.105, 0.085, 0.07, 0.97)
	crsb.set_border_width_all(2)
	crsb.border_color = Color(0.91, 0.53, 0.18, 0.75)
	crsb.set_corner_radius_all(12)
	credits_root.add_theme_stylebox_override("panel", crsb)
	credits_root.visible = false
	root.add_child(credits_root)
	var cr_margin := MarginContainer.new()
	cr_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr_margin.add_theme_constant_override("margin_left", 20)
	cr_margin.add_theme_constant_override("margin_right", 20)
	cr_margin.add_theme_constant_override("margin_top", 14)
	cr_margin.add_theme_constant_override("margin_bottom", 14)
	credits_root.add_child(cr_margin)
	var cr_vbox := VBoxContainer.new()
	cr_vbox.add_theme_constant_override("separation", 8)
	cr_margin.add_child(cr_vbox)
	var cr_title := _label("素材署名", 20, ACCENT, Vector2.ZERO)
	cr_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cr_vbox.add_child(cr_title)
	var cr_scroll := ScrollContainer.new()
	cr_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cr_vbox.add_child(cr_scroll)
	credits_rows = VBoxContainer.new()
	credits_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credits_rows.add_theme_constant_override("separation", 5)
	cr_scroll.add_child(credits_rows)
	var cr_close := Button.new()
	cr_close.text = "关闭"
	cr_close.custom_minimum_size = Vector2(160, 44)
	cr_close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cr_close.add_theme_font_size_override("font_size", 20)
	cr_close.pressed.connect(func() -> void: set_credits_visible(false))
	cr_vbox.add_child(cr_close)

	# 结算遮罩（隐藏）
	over_root = ColorRect.new()
	over_root.color = Color(0.05, 0.03, 0.02, 0.85)
	over_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_root.mouse_filter = Control.MOUSE_FILTER_STOP
	over_root.visible = false
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over_root.add_child(cc)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	cc.add_child(vb)
	var title := _label("车辆损毁", 46, ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := _label("尸群围攻下，房车抛锚了……", 20, TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	over_stats = _label("", 22, TEXT_MAIN)
	over_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(over_stats)
	var retry := Button.new()
	retry.text = "重新出发"
	retry.custom_minimum_size = Vector2(260, 64)
	retry.add_theme_font_size_override("font_size", 26)
	retry.pressed.connect(func() -> void: get_tree().reload_current_scene())
	vb.add_child(retry)
	var over_new := Button.new()
	over_new.text = "从头开始"
	over_new.custom_minimum_size = Vector2(260, 48)
	over_new.add_theme_font_size_override("font_size", 20)
	over_new.pressed.connect(func() -> void: rv.main_node.new_game())
	vb.add_child(over_new)
	root.add_child(over_root)

	# 通关遮罩（隐藏）：暖金色调
	victory_root = ColorRect.new()
	victory_root.color = Color(0.08, 0.05, 0.01, 0.88)
	victory_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	victory_root.mouse_filter = Control.MOUSE_FILTER_STOP
	victory_root.visible = false
	var vcc := CenterContainer.new()
	vcc.set_anchors_preset(Control.PRESET_FULL_RECT)
	vcc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	victory_root.add_child(vcc)
	var vvb := VBoxContainer.new()
	vvb.alignment = BoxContainer.ALIGNMENT_CENTER
	vvb.add_theme_constant_override("separation", 14)
	vcc.add_child(vvb)
	var vtitle := _label("抵达方舟", 46, Color("f0c060"))
	vtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vvb.add_child(vtitle)
	var vsub := _label("钢制大门在身后合拢，680 公里的狂奔终于结束", 20, TEXT_DIM)
	vsub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vvb.add_child(vsub)
	victory_stats = _label("", 22, TEXT_MAIN)
	victory_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vvb.add_child(victory_stats)
	var vretry := Button.new()
	vretry.text = "再来一局"
	vretry.custom_minimum_size = Vector2(260, 64)
	vretry.add_theme_font_size_override("font_size", 26)
	vretry.pressed.connect(func() -> void: rv.main_node.new_game())
	vvb.add_child(vretry)
	root.add_child(victory_root)

	# 暂停菜单（Esc）：继续 / 保存并退出 / 从头开始
	pause_root = ColorRect.new()
	pause_root.color = Color(0.05, 0.03, 0.02, 0.82)
	pause_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_root.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_root.visible = false
	var pcc := CenterContainer.new()
	pcc.set_anchors_preset(Control.PRESET_FULL_RECT)
	pcc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_root.add_child(pcc)
	var pvb := VBoxContainer.new()
	pvb.alignment = BoxContainer.ALIGNMENT_CENTER
	pvb.add_theme_constant_override("separation", 14)
	pcc.add_child(pvb)
	var ptitle := _label("暂停", 46, ACCENT)
	ptitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pvb.add_child(ptitle)
	var presume := Button.new()
	presume.text = "继续游戏"
	presume.custom_minimum_size = Vector2(260, 60)
	presume.add_theme_font_size_override("font_size", 26)
	presume.pressed.connect(func() -> void: set_pause_visible(false))
	pvb.add_child(presume)
	var pset := Button.new()
	pset.text = "设置"
	pset.custom_minimum_size = Vector2(260, 48)
	pset.add_theme_font_size_override("font_size", 20)
	pset.pressed.connect(func() -> void:
		pause_root.visible = false
		set_settings_visible(true))
	pvb.add_child(pset)
	var psave := Button.new()
	psave.text = "保存并退出"
	psave.custom_minimum_size = Vector2(260, 48)
	psave.add_theme_font_size_override("font_size", 20)
	psave.pressed.connect(func() -> void:
		rv.main_node.save_game()
		get_tree().quit())
	pvb.add_child(psave)
	var pnew := Button.new()
	pnew.text = "从头开始"
	pnew.custom_minimum_size = Vector2(260, 48)
	pnew.add_theme_font_size_override("font_size", 20)
	pnew.pressed.connect(func() -> void: rv.main_node.new_game())
	pvb.add_child(pnew)
	root.add_child(pause_root)

	# 设置面板（暂停菜单 → 设置）：三档音量 + 显示模式 + 分辨率
	settings_root = ColorRect.new()
	settings_root.color = Color(0.05, 0.03, 0.02, 0.9)
	settings_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_root.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_root.visible = false
	var stcc := CenterContainer.new()
	stcc.set_anchors_preset(Control.PRESET_FULL_RECT)
	stcc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_root.add_child(stcc)
	var sp := Panel.new()
	sp.custom_minimum_size = Vector2(600, 470)
	var spsb := StyleBoxFlat.new()
	spsb.bg_color = Color(0.105, 0.085, 0.07, 0.97)
	spsb.set_border_width_all(2)
	spsb.border_color = Color(0.91, 0.53, 0.18, 0.75)
	spsb.set_corner_radius_all(12)
	sp.add_theme_stylebox_override("panel", spsb)
	stcc.add_child(sp)
	var sm := MarginContainer.new()
	sm.set_anchors_preset(Control.PRESET_FULL_RECT)
	sm.add_theme_constant_override("margin_left", 32)
	sm.add_theme_constant_override("margin_right", 32)
	sm.add_theme_constant_override("margin_top", 20)
	sm.add_theme_constant_override("margin_bottom", 20)
	sp.add_child(sm)
	var svb := VBoxContainer.new()
	svb.add_theme_constant_override("separation", 16)
	sm.add_child(svb)
	var stitle := _label("设置", 34, ACCENT)
	stitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	svb.add_child(stitle)
	_add_setting_slider(svb, "master", "总音量")
	_add_setting_slider(svb, "music", "音乐")
	_add_setting_slider(svb, "sfx", "音效")
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 12)
	svb.add_child(drow)
	var dl := _label("显示", 19, TEXT_MAIN, Vector2.ZERO)
	dl.custom_minimum_size.x = 96
	dl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drow.add_child(dl)
	_fullscreen_btn = Button.new()
	_fullscreen_btn.custom_minimum_size = Vector2(200, 42)
	_fullscreen_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fullscreen_btn.add_theme_font_size_override("font_size", 19)
	_fullscreen_btn.pressed.connect(_on_fullscreen_toggle)
	drow.add_child(_fullscreen_btn)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 12)
	svb.add_child(rrow)
	var rl := _label("分辨率", 19, TEXT_MAIN, Vector2.ZERO)
	rl.custom_minimum_size.x = 96
	rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rrow.add_child(rl)
	_res_opt = OptionButton.new()
	_res_opt.custom_minimum_size = Vector2(200, 42)
	_res_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_res_opt.add_theme_font_size_override("font_size", 18)
	for r in RESOLUTIONS:
		_res_opt.add_item("%d × %d" % [r[0], r[1]])
	_res_opt.item_selected.connect(_on_res_selected)
	rrow.add_child(_res_opt)
	var sback := Button.new()
	sback.text = "返回"
	sback.custom_minimum_size = Vector2(200, 48)
	sback.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sback.add_theme_font_size_override("font_size", 20)
	sback.pressed.connect(func() -> void: set_settings_visible(false))
	svb.add_child(sback)
	root.add_child(settings_root)

	_build_combat(root)
	_build_story(root)

# ---------- 下车 / 天窗战斗层 ----------
func _build_combat(root: Control) -> void:
	combat_root = Control.new()
	combat_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	combat_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combat_root.visible = false
	root.add_child(combat_root)
	# 屏幕中心准星
	crosshair = _label("+", 34, TEXT_MAIN)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -16
	crosshair.offset_right = 16
	crosshair.offset_top = -24
	crosshair.offset_bottom = 8
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.pivot_offset = Vector2(16, 16)  # 击杀放大时绕中心缩放
	combat_root.add_child(crosshair)
	# 常驻操作提示（准星下方）：手雷等按键不再只靠入场 toast 一闪而过
	combat_hint = _label("左键 开火 · R 换弹 · X 手雷 · 1-4 换枪 · C 下蹲 · V 视角 · G 上车", 14, TEXT_DIM)
	combat_hint.set_anchors_preset(Control.PRESET_CENTER)
	combat_hint.offset_left = -220
	combat_hint.offset_right = 220
	combat_hint.offset_top = 26
	combat_hint.offset_bottom = 50
	combat_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combat_root.add_child(combat_hint)
	# 右下：弹匣 + 枪名（左侧按钮列上方，避免与跳跃/下蹲按钮重叠）
	ammo_label = _label("12/12", 30, ACCENT)
	ammo_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_label.offset_left = -364
	ammo_label.offset_right = -190
	ammo_label.offset_top = -262
	ammo_label.offset_bottom = -214
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	combat_root.add_child(ammo_label)
	gun_label = _label("", 16, TEXT_DIM)
	gun_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	gun_label.offset_left = -364
	gun_label.offset_right = -190
	gun_label.offset_top = -292
	gun_label.offset_bottom = -266
	gun_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	combat_root.add_child(gun_label)
	# 触屏战斗按钮组：开火（大）/ 跳跃 / 换弹 / 换枪 / 下蹲 / 上车撤离
	combat_fire_buttons.append(_touch_button(combat_root, "开火", Control.PRESET_BOTTOM_RIGHT, Rect2(-170, -140, 146, 116), "fire"))
	var jump_btn := _touch_button(combat_root, "跳跃", Control.PRESET_BOTTOM_RIGHT, Rect2(-170, -262, 146, 62), "jump")
	combat_fire_buttons.append(jump_btn)
	combat_stance_buttons.append(jump_btn)
	combat_fire_buttons.append(_touch_button(combat_root, "换弹", Control.PRESET_BOTTOM_RIGHT, Rect2(-336, -204, 150, 54), "reload"))
	combat_fire_buttons.append(_touch_button(combat_root, "换枪", Control.PRESET_BOTTOM_RIGHT, Rect2(-336, -140, 150, 54), "swapgun"))
	var crouch_btn := _touch_button(combat_root, "下蹲", Control.PRESET_BOTTOM_RIGHT, Rect2(-336, -76, 150, 54), "crouch")
	combat_fire_buttons.append(crouch_btn)
	combat_stance_buttons.append(crouch_btn)
	_touch_button(combat_root, "上车", Control.PRESET_TOP_RIGHT, Rect2(-170, 64, 146, 54), "exitcombat")
	combat_fire_buttons.append(_touch_button(combat_root, "视角", Control.PRESET_TOP_RIGHT, Rect2(-170, 128, 146, 54), "fps"))
	combat_fire_buttons.append(_touch_button(combat_root, "手雷", Control.PRESET_TOP_RIGHT, Rect2(-170, 192, 146, 54), "grenade"))
	# 左下：虚拟摇杆（手游移动）
	var js := Joystick.new()
	combat_joystick = js
	js.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	js.offset_left = 36
	js.offset_top = -206
	js.offset_right = 186
	js.offset_bottom = -56
	js.moved.connect(func(v: Vector2) -> void:
		var p: Node3D = rv.main_node.get_player_body()
		if p != null:
			p.touch_move = v)
	combat_root.add_child(js)
	# 生命条（摇杆上方，避免遮挡）
	var hp_title := _label("生命", 15, TEXT_DIM, Vector2(24, -258))
	hp_title.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	combat_root.add_child(hp_title)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.55)
	hp_bg.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hp_bg.offset_left = 70
	hp_bg.offset_top = -252
	hp_bg.offset_right = 280
	hp_bg.offset_bottom = -228
	combat_root.add_child(hp_bg)
	combat_hp_fill = ColorRect.new()
	combat_hp_fill.color = Color(0.55, 0.8, 0.45)
	combat_hp_fill.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	combat_hp_fill.offset_left = 72
	combat_hp_fill.offset_top = -250
	combat_hp_fill.offset_right = 278
	combat_hp_fill.offset_bottom = -230
	combat_root.add_child(combat_hp_fill)
	combat_hp_label = _label("100", 14, TEXT_MAIN, Vector2(286, -256))
	combat_hp_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	combat_root.add_child(combat_hp_label)

func set_combat_active(active: bool, ammo: int, hp: float) -> void:
	combat_root.visible = active
	# 战斗时收起整个驾驶面板；结束按驻车状态恢复
	drive_joystick.visible = not active and not _is_parked()
	if active:
		drive_joystick.release()
	for b in drive_misc_buttons:
		b.visible = not active
	if active:
		var roof: bool = rv.main_node.get_player_body().mode == 1
		for b in combat_stance_buttons:
			b.visible = not roof
		combat_joystick.visible = not roof
		combat_hint.text = "左键 开火 · R 换弹 · X 手雷 · 1-4 换枪 · V 视角 · G 上车" if roof else "左键 开火 · R 换弹 · X 手雷 · 1-4 换枪 · C 下蹲 · V 视角 · G 上车"
		set_combat_ammo(ammo, 0)
		set_combat_hp(hp)

func _is_parked() -> bool:
	return rv != null and rv.main_node != null and rv.main_node.parked

## 车内行走：复用战斗 HUD 底板，但只留摇杆与「上车」撤离（无法开枪/跳跃/换枪）
func set_rv_walk_active(v: bool) -> void:
	combat_root.visible = v
	if v:
		combat_joystick.visible = true
	for b in combat_fire_buttons:
		b.visible = not v
	ammo_label.visible = not v
	gun_label.visible = not v
	combat_hint.visible = not v

## 瞄准数据（相机已直接朝向，准星居中即可；保留接口）
func set_combat_aim(_dir: Vector3, _pos: Vector3) -> void:
	pass

func set_combat_ammo(ammo: int, reloading: int) -> void:
	if reloading != 0:
		ammo_label.text = "换弹中……"
	else:
		ammo_label.text = "%d/%d" % [ammo, _cur_mag]

## 切枪：刷新枪名与弹匣上限
func set_combat_gun(gun_name: String, ammo: int, mag: int) -> void:
	_cur_mag = mag
	_cur_gun_name = gun_name
	gun_label.text = _cur_gun_name + (" · 手雷×%d" % _grenade_count if _grenade_count > 0 else "")
	set_combat_ammo(ammo, 0)

## 手雷余量：拼在枪名行尾
func set_combat_grenades(n: int) -> void:
	_grenade_count = n
	gun_label.text = _cur_gun_name + (" · 手雷×%d" % _grenade_count if _grenade_count > 0 else "")

func set_combat_hp(hp: float) -> void:
	var ratio := clampf(hp / 100.0, 0.0, 1.0)
	combat_hp_fill.size.x = 206.0 * ratio
	combat_hp_fill.offset_right = 72.0 + 206.0 * ratio
	combat_hp_fill.color = Color(0.75, 0.3, 0.2).lerp(Color(0.55, 0.8, 0.45), ratio)
	combat_hp_label.text = "%d" % int(round(hp))

## 命中丧尸：准星闪橙；击杀闪红放大，爆头击杀更醒目
func flash_hit_marker(killed := true, headshot := false) -> void:
	if killed:
		crosshair.modulate = Color(1.0, 0.25, 0.15) if headshot else Color(1.0, 0.45, 0.2)
		crosshair.scale = Vector2(1.35, 1.35)
	else:
		crosshair.modulate = ACCENT
		crosshair.scale = Vector2(1.15, 1.15)
	if _hit_tween != null:
		_hit_tween.kill()
	_hit_tween = create_tween()
	_hit_tween.set_parallel(true)
	_hit_tween.tween_interval(0.08)
	_hit_tween.tween_property(crosshair, "modulate", TEXT_MAIN, 0.18).set_delay(0.08)
	_hit_tween.tween_property(crosshair, "scale", Vector2.ONE, 0.18).set_delay(0.08)

## 电台剧情对话框：底部通栏，左侧立绘 + 说话人名，右侧打字机正文与选项
func _build_story(root: Control) -> void:
	story_root = Panel.new()
	# 对话框居中偏下：940 宽水平居中，底边距屏 40（anchor 顶/底均为 1，offset 相对屏幕底边）
	story_root.anchor_left = 0.5
	story_root.anchor_right = 0.5
	story_root.anchor_top = 1.0
	story_root.anchor_bottom = 1.0
	story_root.offset_left = -470
	story_root.offset_right = 470
	story_root.offset_top = -360
	story_root.offset_bottom = -40
	story_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.105, 0.085, 0.07, 0.96)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.91, 0.53, 0.18, 0.75)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 20
	sb.content_margin_bottom = 18
	story_root.add_theme_stylebox_override("panel", sb)
	story_root.visible = false
	root.add_child(story_root)

	# 对话框内左侧立绘（3:4 竖幅缩略，与队伍头像同风格）
	story_pic = TextureRect.new()
	story_pic.position = Vector2(20, 18)
	story_pic.size = Vector2(150, 200)
	story_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	story_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	story_pic.clip_contents = true
	story_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_pic.visible = false
	story_root.add_child(story_pic)

	story_speaker = _label("", 22, ACCENT, Vector2(26, 18))
	story_root.add_child(story_speaker)
	story_text = _label("", 19, TEXT_MAIN, Vector2(26, 52))
	story_text.size = Vector2(888, 128)
	story_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_root.add_child(story_text)

	story_options = VBoxContainer.new()
	story_options.position = Vector2(26, 188)
	story_options.size = Vector2(888, 138)
	story_options.add_theme_constant_override("separation", 8)
	story_options.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_root.add_child(story_options)

	var hint := _label("点击选项继续", 13, TEXT_DIM)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.offset_left = -150
	hint.offset_top = -30
	hint.offset_right = -22
	hint.offset_bottom = -6
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	story_root.add_child(hint)
	story_root.gui_input.connect(_on_story_gui_input)

## 打字机效果：正文逐字显示，显示完再放出选项按钮
func _process(delta: float) -> void:
	var tab := Input.is_physical_key_pressed(KEY_TAB)
	if tab and not _tab_down:
		crew_visible = not crew_visible
		crew_panel.visible = crew_visible
	_tab_down = tab
	if rv == null:
		return
	speed_label.text = ("R · %d km/h" if rv.reversing else "%d km/h") % int(rv.speed_kmh)
	# 空格/回车：打字机直接出全文
	var skip := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_ENTER)
	if story_root.visible and story_root.is_inside_tree() and _shown < _full_text.length():
		if skip and not _skip_down:
			_shown = _full_text.length()
			story_text.text = _full_text
			_show_options()
		else:
			_type_t += delta
			# 中文按整字推进
			while _type_t >= 0.02 and _shown < _full_text.length():
				_type_t -= 0.02
				_shown += 1
			story_text.text = _full_text.substr(0, _shown)
			if _shown >= _full_text.length():
				_show_options()
	_skip_down = skip

## 点击对话框空白处：打字机直接出全文
func _on_story_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if _shown < _full_text.length():
			_shown = _full_text.length()
			story_text.text = _full_text
			_show_options()

func show_story(ev: Dictionary) -> void:
	story_event_id = String(ev.get("id", ""))
	_full_text = String(ev.get("text", ""))
	_shown = 0
	_type_t = 0.0
	story_text.text = ""
	# 剧情面板会盖住驾驶摇杆吞掉松手事件：清零触摸输入，防止油门/转向卡死
	drive_joystick.release()
	rv.touch_throttle = 0.0
	rv.touch_steer = 0.0
	story_speaker.text = String(ev.get("speaker", ""))
	for c in story_options.get_children():
		c.queue_free()
	# 对话框内嵌立绘：有立绘时正文/选项右移让位
	var pic := String(ev.get("portrait", ""))
	var path := "res://assets/portraits/" + pic
	var has_pic := pic != "" and ResourceLoader.exists(path)
	story_pic.visible = has_pic
	if has_pic:
		story_pic.texture = load(path)
	var tx := 190.0 if has_pic else 26.0
	var tw := 724.0 if has_pic else 888.0
	story_speaker.position.x = tx
	story_text.position.x = tx
	story_text.size.x = tw
	story_options.position.x = tx
	story_options.size.x = tw
	story_root.visible = true

## 正文显示完毕后生成选项按钮（条件不足置灰）
func _show_options() -> void:
	for c in story_options.get_children():
		c.queue_free()
	var ev: Dictionary = story_node.events.get(story_event_id, {})
	var opts: Array = ev.get("options", [])
	# 选项过多时（如终章 7 个分支结局）面板自适应加高
	var panel_h: float = maxf(334.0, 208.0 + opts.size() * 49.0)
	story_root.offset_top = -(panel_h + 40.0)
	story_options.size.y = panel_h - 208.0
	for i in opts.size():
		var b := Button.new()
		b.text = "  " + String(opts[i].get("t", "")) + "  "
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 18)
		var usable: bool = story_node.option_available(opts[i])
		if not usable:
			b.text += "（条件不足）"
			b.disabled = true
			b.modulate = Color(0.62, 0.58, 0.54)
		var sbn := StyleBoxFlat.new()
		sbn.bg_color = Color(0.17, 0.14, 0.12, 0.9)
		sbn.set_border_width_all(1)
		sbn.border_color = Color(0.91, 0.53, 0.18, 0.5 if usable else 0.18)
		sbn.set_corner_radius_all(8)
		sbn.content_margin_left = 12
		sbn.content_margin_top = 8
		sbn.content_margin_bottom = 8
		b.add_theme_stylebox_override("normal", sbn)
		b.add_theme_stylebox_override("hover", sbn)
		b.add_theme_color_override("font_color", TEXT_MAIN if usable else TEXT_DIM)
		b.pressed.connect(story_node.choose.bind(i))
		story_options.add_child(b)

func hide_story() -> void:
	story_root.visible = false

# ---------- 暂停菜单 ----------
## Esc 开关暂停菜单（HUD 常驻处理：暂停时本体收不到输入，HUD 才能关）
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if settings_root.visible:
		set_settings_visible(false)
	elif pause_root.visible:
		set_pause_visible(false)
	elif rv.main_node != null and not rv.main_node.story_active and not rv.main_node.game_over:
		set_pause_visible(true)
	get_viewport().set_input_as_handled()

func set_pause_visible(v: bool) -> void:
	pause_root.visible = v
	get_tree().paused = v
	if v:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif rv.main_node != null and rv.main_node.combat_active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ---------- 设置面板 ----------
func set_settings_visible(v: bool) -> void:
	settings_root.visible = v
	if v:
		_sync_settings_ui()
	else:
		rv.main_node.save_settings()
		if get_tree().paused:
			pause_root.visible = true

## 即时生效的音量滑条（值域 0-100，写入 0..1 到 main.settings）
func _add_setting_slider(parent: VBoxContainer, key: String, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var l := _label(text, 19, TEXT_MAIN, Vector2.ZERO)
	l.custom_minimum_size.x = 96
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	var s := HSlider.new()
	s.max_value = 100.0
	s.step = 1.0
	s.custom_minimum_size.y = 26
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.26, 0.22, 0.18, 0.95)
	track.set_corner_radius_all(4)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	s.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.91, 0.53, 0.18, 0.85)
	fill.set_corner_radius_all(4)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	row.add_child(s)
	var vl := _label("100%", 17, TEXT_DIM, Vector2.ZERO)
	vl.custom_minimum_size.x = 56
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(vl)
	_setting_sliders[key] = s
	_setting_value_labels[key] = vl
	s.value_changed.connect(func(v: float) -> void:
		vl.text = "%d%%" % int(v)
		rv.main_node.apply_setting(key, v / 100.0))

func _sync_settings_ui() -> void:
	var st: Dictionary = rv.main_node.settings
	for key in _setting_sliders:
		var pct := float(st[key]) * 100.0
		_setting_sliders[key].set_value_no_signal(pct)
		_setting_value_labels[key].text = "%d%%" % int(pct)
	var fs := bool(st["fullscreen"])
	_fullscreen_btn.text = "全屏" if fs else "窗口"
	_res_opt.disabled = fs
	_res_opt.select(maxi(RESOLUTIONS.find([int(st["res_w"]), int(st["res_h"])]), 0))

func _on_fullscreen_toggle() -> void:
	var on := not bool(rv.main_node.settings["fullscreen"])
	rv.main_node.apply_setting("fullscreen", on)
	_fullscreen_btn.text = "全屏" if on else "窗口"
	_res_opt.disabled = on

func _on_res_selected(i: int) -> void:
	rv.main_node.apply_setting("res_w", int(RESOLUTIONS[i][0]))
	rv.main_node.apply_setting("res_h", int(RESOLUTIONS[i][1]))

# ---------- 素材署名面板 ----------
func set_credits_visible(v: bool) -> void:
	credits_root.visible = v
	if v:
		_refresh_credits()

func _refresh_credits() -> void:
	for c in credits_rows.get_children():
		c.queue_free()
	var data: Dictionary = rv.main_node.credits_data
	_credit_header("CC-BY 许可素材（依许可要求署名）")
	for it in data.get("cc_by", []):
		_credit_line("· %s\n  %s · %s" % [it.get("asset", ""), it.get("author", ""), it.get("license", "")])
	var pend: Array = data.get("pending", [])
	if not pend.is_empty():
		_credit_header("来源信息待补")
		for it in pend:
			_credit_line("· %s\n  %s" % [it.get("asset", ""), it.get("note", "")])
	_credit_header("CC0 公共领域素材（致谢）")
	for it in data.get("cc0", []):
		_credit_line("· %s\n  %s" % [it.get("asset", ""), it.get("author", "")])

func _credit_header(text: String) -> void:
	var l := _label(text, 17, ACCENT, Vector2.ZERO)
	l.custom_minimum_size.y = 30
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	credits_rows.add_child(l)

func _credit_line(text: String) -> void:
	var l := _label(text, 15, TEXT_MAIN, Vector2.ZERO)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 560
	credits_rows.add_child(l)

# ---------- 房车设施面板 ----------
func set_facilities_visible(v: bool) -> void:
	facilities_root.visible = v
	if v:
		_refresh_facilities()

## 驻车时隐藏驾驶摇杆，避免与设施面板重叠
func set_drive_buttons_visible(v: bool) -> void:
	drive_joystick.visible = v
	if not v:
		drive_joystick.release()
		rv.touch_throttle = 0.0
		rv.touch_steer = 0.0

func refresh_facilities() -> void:
	if facilities_root.visible:
		_refresh_facilities()

func _refresh_facilities() -> void:
	for c in facilities_rows.get_children():
		c.queue_free()
	var main: Node = rv.main_node
	facilities_title.text = "房车设施 · 零件 %d" % int(main.parts)
	for f in main.facilities_data.get("facilities", []):
		var id := String(f.get("id", ""))
		var lv := int(main.facility_levels.get(id, 0))
		var max_lv := int(f.get("max_level", 1))
		var act: Dictionary = f.get("action", {})
		# 卡片底
		var card := PanelContainer.new()
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(0.15, 0.12, 0.1, 0.85)
		csb.set_border_width_all(1)
		csb.border_color = Color(0.91, 0.53, 0.18, 0.28)
		csb.set_corner_radius_all(8)
		csb.content_margin_left = 12
		csb.content_margin_right = 12
		csb.content_margin_top = 8
		csb.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", csb)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(col)
		# 第一行：名称 · 等级点 · 描述 · 按钮们
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 10)
		var dots := ""
		for i in max_lv:
			dots += "●" if i <= lv else "○"
		var head := _label("%s %s" % [String(f.get("name", "")), dots], 16, ACCENT)
		head.custom_minimum_size = Vector2(128, 0)
		top.add_child(head)
		var desc_lab := _label(String(f.get("desc", "")), 14, TEXT_DIM)
		desc_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		top.add_child(desc_lab)
		if not act.is_empty():
			var can: bool = main.food >= float(act.get("food", 0)) and main.parts >= float(act.get("parts", 0))
			var b := _facility_button(String(act.get("label", "使用")), can)
			b.custom_minimum_size = Vector2(104, 0)
			b.pressed.connect(main.facility_action.bind(id))
			top.add_child(b)
		if lv < max_lv - 1:
			var costs: Array = f.get("upgrade", {}).get("parts", [])
			var cost := int(costs[lv])
			var ub := _facility_button("%s ·%d件" % [String(f.get("upgrade", {}).get("label", "升级")), cost], main.parts >= cost)
			ub.custom_minimum_size = Vector2(118, 0)
			ub.pressed.connect(main.facility_upgrade.bind(id))
			top.add_child(ub)
		else:
			var max_lab := _label("已满级", 13, TEXT_DIM)
			max_lab.custom_minimum_size = Vector2(64, 0)
			max_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			max_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			top.add_child(max_lab)
		col.add_child(top)
		# 第二行：动作明细 / 燃料上限
		if not act.is_empty():
			col.add_child(_label(_action_detail(main, act, lv), 13, TEXT_MAIN))
		elif f.has("fuel_cap"):
			var caps: Array = f["fuel_cap"]
			col.add_child(_label("当前燃料上限 %d" % int(caps[lv]), 13, TEXT_MAIN))
		facilities_rows.add_child(card)

## 拼接动作当前收益描述
func _action_detail(main: Node, act: Dictionary, lv: int) -> String:
	var cost_parts := []
	if float(act.get("food", 0)) > 0:
		cost_parts.append("食物 -%d" % int(act["food"]))
	if float(act.get("parts", 0)) > 0:
		cost_parts.append("零件 -%d" % int(act["parts"]))
	cost_parts.append("%d 小时" % int(act.get("hours", 0)))
	var s := " · ".join(cost_parts)
	if act.has("fx_morale"):
		s += "  →  士气 +%d" % int((act["fx_morale"] as Array)[lv])
	if act.has("fx_dur"):
		s += "  →  车况 +%d" % int((act["fx_dur"] as Array)[lv])
	return s

func _facility_button(text: String, enabled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.add_theme_font_size_override("font_size", 14)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.17, 0.14, 0.12, 0.92)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.91, 0.53, 0.18, 0.55 if enabled else 0.18)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("disabled", sb)
	b.add_theme_color_override("font_color", TEXT_MAIN if enabled else TEXT_DIM)
	b.modulate = Color(1, 1, 1, 1 if enabled else 0.7)
	return b

func set_crew(members: Array) -> void:
	for c in crew_rows.get_children():
		c.queue_free()
	if members.is_empty():
		crew_rows.add_child(_label("车上还没有同伴", 15, TEXT_DIM))
		return
	# 每行 72 头像 + 10 间距；内容高超 540 后固定面板高度，滚动查看
	crew_panel.offset_bottom = 70.0 + 24.0 + minf(members.size() * 82.0, 540.0)
	for m in members:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(56, 72)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.clip_contents = true
		var path := "res://assets/portraits/" + String(m.get("avatar", "")).get_file()
		if ResourceLoader.exists(path):
			pic.texture = load(path)
		row.add_child(pic)
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 2)
		box.add_child(_label(String(m.get("name", "")), 18, TEXT_MAIN))
		box.add_child(_label("%s · %s" % [String(m.get("skill", "")), String(m.get("passive", "工作中"))], 14, ACCENT))
		row.add_child(box)
		crew_rows.add_child(row)

func update_stats(main: Node3D) -> void:
	var ratio: float = main.durability / 100.0
	dur_fill.size.x = (BAR_W - 4.0) * ratio
	dur_fill.color = Color(0.75, 0.3, 0.2).lerp(Color(0.55, 0.8, 0.45), ratio)
	fuel_fill.size.x = (BAR_W - 4.0) * main.fuel / main.fuel_cap()
	var mr: float = main.morale / 100.0
	morale_fill.size.x = (BAR_W - 4.0) * mr
	morale_fill.color = Color(0.75, 0.3, 0.2).lerp(Color(0.91, 0.53, 0.18), mr)
	res_label.text = "食物 %d · 零件 %d · 燃料 %.0f/%.0f · 队伍 %d 人" % [int(main.food), int(main.parts), main.fuel, main.fuel_cap(), main.crew]
	var h := int(main.hour)
	var m := int((main.hour - h) * 60.0)
	info_label.text = "里程 %.1f km · 第 %d 天 %02d:%02d%s" % [main.dist_km, main.day, h, m, " · 驻车中" if main.parked else ""]
	if main.crew_driving and not main.parked:
		info_label.text += "\n%s 代驾中 · 定速巡航 · Q 接管" % main.crew_members[0].get("name", "")
	var legs := PackedStringArray()
	for pl in main.next_places(3):
		legs.append("%s %.0fkm" % [pl[0], pl[1]])
	journey_label.text = " → ".join(legs)

func set_weather(w: String) -> void:
	weather_label.text = "天气 " + {"clear": "晴", "rain": "雨", "heavy_rain": "大雨", "snow": "大雪", "fog": "雾"}.get(w, "晴")

func toast(msg: String) -> void:
	toast_label.text = msg
	if _toast_tween != null:
		_toast_tween.kill()
	toast_label.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.4)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.6)

func show_game_over(main: Node3D) -> void:
	over_stats.text = "存活 %d 天 · 里程 %.1f km · 队伍 %d 人" % [main.day, main.dist_km, main.crew]
	over_root.visible = true

func show_victory(main: Node3D) -> void:
	victory_stats.text = "用时 %d 天 · 里程 %.1f km · 队伍 %d 人 · 最终士气 %.0f" % [main.day, main.dist_km, main.crew, main.morale]
	victory_root.visible = true

# ---------- 控件工厂 ----------
func _panel(pos: Vector2, size: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.165, 0.137, 0.125, 0.78)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.91, 0.53, 0.18, 0.45)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	p.add_theme_stylebox_override("panel", sb)
	return p

func _label(text: String, size: int, col: Color, pos := Vector2.ZERO) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l

func _add_bar(panel: Control, pos: Vector2) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.5)
	bg.position = pos
	bg.size = Vector2(BAR_W, 16)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bg)
	var fill := ColorRect.new()
	fill.color = Color(0.55, 0.8, 0.45)
	fill.position = pos + Vector2(2, 2)
	fill.size = Vector2(BAR_W - 4, 12)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(fill)
	return fill

func _touch_button(parent: Control, text: String, preset: int, rect: Rect2, action: String) -> Button:
	var b := Button.new()
	b.text = text
	b.set_anchors_preset(preset)
	b.offset_left = rect.position.x
	b.offset_top = rect.position.y
	b.offset_right = rect.end.x
	b.offset_bottom = rect.end.y
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.165, 0.137, 0.125, 0.6)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.91, 0.53, 0.18, 0.55)
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	b.add_theme_stylebox_override("normal", sb)
	var sbp: StyleBoxFlat = sb.duplicate()
	sbp.bg_color = Color(0.91, 0.53, 0.18, 0.35)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", TEXT_MAIN)
	b.button_down.connect(_on_btn_down.bind(action))
	b.button_up.connect(_on_btn_up.bind(action))
	parent.add_child(b)
	return b

func _on_btn_down(action: String) -> void:
	match action:
		"view":
			if rv.main_node != null:
				rv.main_node.view_mode = (rv.main_node.view_mode + 1) % 3
				toast(["车外视角", "驾驶位视角 · 第一人称", "车厢视角 · 按住右键环顾"][rv.main_node.view_mode])
		"park":
			if rv.main_node != null:
				rv.main_node._toggle_park()
		"swapgun":
			if rv.main_node != null and rv.main_node.get_player_body() != null:
				rv.main_node.get_player_body().switch_gun_next()
		"fire":
			if rv.main_node != null and rv.main_node.get_player_body() != null:
				rv.main_node.get_player_body().press_fire()
		"reload":
			if rv.main_node != null and rv.main_node.get_player_body() != null:
				rv.main_node.get_player_body().reload()
		"grenade":
			if rv.main_node != null and rv.main_node.get_player_body() != null:
				rv.main_node.get_player_body().throw_grenade()
		"jump":
			if rv.main_node != null and rv.main_node.get_player_body() != null:
				rv.main_node.get_player_body().jump()
		"crouch":
			if rv.main_node != null and rv.main_node.get_player_body() != null:
				rv.main_node.get_player_body().toggle_crouch()
		"fps":
			if rv.main_node != null and rv.main_node.get_player_body() != null:
				rv.main_node.get_player_body().toggle_fps()
		"exitcombat":
			if rv.main_node != null:
				if rv.main_node.rv_walk_active:
					rv.main_node.end_rv_walk()
				else:
					rv.main_node.end_combat()
		"rvwalk":
			if rv.main_node != null:
				if rv.main_node.rv_walk_active:
					if rv.main_node.parked:
						toast("驻车休整中 · 按驻车键出发")
					else:
						rv.main_node.end_rv_walk()
				else:
					rv.main_node.start_rv_walk()
		"sunroof":
			if rv.main_node != null:
				if rv.main_node.combat_active:
					rv.main_node.end_combat()
				else:
					rv.main_node.start_combat(1)
		"exitveh":
			if rv.main_node != null and rv.main_node.parked and not rv.main_node.combat_active:
				rv.main_node.start_combat(0)
		"crew":
			crew_visible = not crew_visible
			crew_panel.visible = crew_visible
		"credits":
			set_credits_visible(not credits_root.visible)
		"fac":
			if rv.main_node != null and rv.main_node.parked:
				rv.main_node.set_facilities_ui(not rv.main_node.facilities_visible)

func _on_btn_up(action: String) -> void:
	match action:
		"fire":
			if rv.main_node != null and rv.main_node.get_player_body() != null:
				rv.main_node.get_player_body().release_fire()
