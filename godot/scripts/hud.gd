extends CanvasLayer
## HUD：状态面板 + 车速表 + 触摸驾驶按钮 + toast + 结算界面。
## 末世暖调：篝火橙 #e8862e / 面板 #2a2320 / 主文字 #e8ded2 / 次文字 #8a7d6d。

const ACCENT := Color("e8862e")
const TEXT_MAIN := Color("e8ded2")
const TEXT_DIM := Color("8a7d6d")
const BAR_W := 168.0

var rv: Node
var speed_label: Label
var res_label: Label
var info_label: Label
var weather_label: Label
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
var _tab_down := false
var _toast_tween: Tween

# 电台剧情对话框
var story_node: Node
var story_root: Panel
var story_portrait: TextureRect
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
	var panel := _panel(Vector2(12, 12), Vector2(276, 164))
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
	var hint := _label("W/A/S/D 驾驶 · C 切换视角 · F 驻车休整 · Tab 队伍 · 光柱 = 幸存者", 14, TEXT_DIM)
	hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint.offset_left = -560
	hint.offset_right = -14
	hint.offset_top = 14
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(hint)

	# 天气
	weather_label = _label("天气 晴", 15, TEXT_DIM)
	weather_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	weather_label.offset_left = -200
	weather_label.offset_right = -14
	weather_label.offset_top = 38
	weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(weather_label)

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

	# 触摸驾驶按钮
	_touch_button(root, "油门", Control.PRESET_BOTTOM_RIGHT, Rect2(-176, -118, 156, 98), "gas")
	_touch_button(root, "刹车", Control.PRESET_BOTTOM_RIGHT, Rect2(-352, -118, 156, 98), "brake")
	_touch_button(root, "左", Control.PRESET_BOTTOM_LEFT, Rect2(20, -118, 130, 98), "left")
	_touch_button(root, "右", Control.PRESET_BOTTOM_LEFT, Rect2(170, -118, 130, 98), "right")
	_touch_button(root, "视角", Control.PRESET_BOTTOM_RIGHT, Rect2(-176, -222, 78, 56), "view")
	_touch_button(root, "驻车", Control.PRESET_BOTTOM_RIGHT, Rect2(-90, -222, 78, 56), "park")

	# 队伍面板（Tab 开关）
	crew_panel = _panel(Vector2.ZERO, Vector2.ZERO)
	crew_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	crew_panel.offset_left = -342
	crew_panel.offset_top = 70
	crew_panel.offset_right = -14
	crew_panel.offset_bottom = 470
	crew_panel.visible = false
	root.add_child(crew_panel)
	crew_rows = VBoxContainer.new()
	crew_rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	crew_rows.offset_left = 12
	crew_rows.offset_top = 12
	crew_rows.offset_right = -12
	crew_rows.offset_bottom = -12
	crew_rows.add_theme_constant_override("separation", 10)
	crew_panel.add_child(crew_rows)

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
	var retry := _label("按 R 重新出发", 24, TEXT_MAIN)
	retry.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(retry)
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
	var vretry := _label("按 R 重新出发", 24, TEXT_MAIN)
	vretry.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vvb.add_child(vretry)
	root.add_child(victory_root)

	_build_story(root)

## 电台剧情对话框：底部通栏，左侧立绘 + 说话人名，右侧打字机正文与选项
func _build_story(root: Control) -> void:
	story_root = Panel.new()
	# 底部宽锚点（anchor 顶/底均为 1）：offset 相对屏幕底边
	story_root.anchor_left = 0.0
	story_root.anchor_right = 1.0
	story_root.anchor_top = 1.0
	story_root.anchor_bottom = 1.0
	story_root.offset_left = 140
	story_root.offset_right = -140
	story_root.offset_top = -360
	story_root.offset_bottom = -26
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

	story_portrait = TextureRect.new()
	story_portrait.custom_minimum_size = Vector2(150, 150)
	story_portrait.position = Vector2(26, 20)
	story_portrait.size = Vector2(150, 150)
	story_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	story_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	story_portrait.clip_contents = true
	story_portrait.visible = false
	story_root.add_child(story_portrait)

	story_speaker = _label("", 22, ACCENT, Vector2(196, 18))
	story_root.add_child(story_speaker)
	story_text = _label("", 19, TEXT_MAIN, Vector2(196, 52))
	story_text.size = Vector2(720, 128)
	story_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_root.add_child(story_text)

	story_options = VBoxContainer.new()
	story_options.position = Vector2(196, 188)
	story_options.size = Vector2(760, 138)
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
	speed_label.text = "%d km/h" % int(rv.speed_kmh)
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
	story_speaker.text = String(ev.get("speaker", ""))
	for c in story_options.get_children():
		c.queue_free()
	# 立绘
	var pic := String(ev.get("portrait", ""))
	if pic != "":
		var path := "res://assets/portraits/" + pic
		if ResourceLoader.exists(path):
			story_portrait.texture = load(path)
			story_portrait.visible = true
	else:
		story_portrait.visible = false
	story_root.visible = true

## 正文显示完毕后生成选项按钮（条件不足置灰）
func _show_options() -> void:
	for c in story_options.get_children():
		c.queue_free()
	var ev: Dictionary = story_node.events.get(story_event_id, {})
	var opts: Array = ev.get("options", [])
	# 选项过多时（如终章 7 个分支结局）面板自适应加高
	var panel_h: float = maxf(334.0, 208.0 + opts.size() * 49.0)
	story_root.offset_top = -(panel_h + 26.0)
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

func set_crew(members: Array) -> void:
	for c in crew_rows.get_children():
		c.queue_free()
	if members.is_empty():
		crew_rows.add_child(_label("车上还没有同伴", 15, TEXT_DIM))
		return
	crew_panel.offset_bottom = 70.0 + 24.0 + members.size() * 72.0
	for m in members:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(64, 64)
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
	fuel_fill.size.x = (BAR_W - 4.0) * main.fuel / 100.0
	var mr: float = main.morale / 100.0
	morale_fill.size.x = (BAR_W - 4.0) * mr
	morale_fill.color = Color(0.75, 0.3, 0.2).lerp(Color(0.91, 0.53, 0.18), mr)
	res_label.text = "食物 %d · 队伍 %d 人" % [int(main.food), main.crew]
	var h := int(main.hour)
	var m := int((main.hour - h) * 60.0)
	info_label.text = "里程 %.1f km · 第 %d 天 %02d:%02d%s" % [main.dist_km, main.day, h, m, " · 驻车中" if main.parked else ""]

func set_weather(w: String) -> void:
	weather_label.text = "天气 " + {"clear": "晴", "rain": "雨", "fog": "雾"}.get(w, "晴")

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

func _touch_button(parent: Control, text: String, preset: int, rect: Rect2, action: String) -> void:
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

func _on_btn_down(action: String) -> void:
	match action:
		"gas": rv.touch_gas = true
		"brake": rv.touch_brake = true
		"left": rv.touch_steer = 1.0
		"right": rv.touch_steer = -1.0
		"view":
			if rv.main_node != null:
				rv.main_node.view_mode = (rv.main_node.view_mode + 1) % 3
		"park":
			if rv.main_node != null:
				rv.main_node._toggle_park()

func _on_btn_up(action: String) -> void:
	match action:
		"gas": rv.touch_gas = false
		"brake": rv.touch_brake = false
		"left": if rv.touch_steer > 0.0: rv.touch_steer = 0.0
		"right": if rv.touch_steer < 0.0: rv.touch_steer = 0.0
