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
var crew_panel: Panel
var crew_rows: VBoxContainer
var crew_visible := false
var _tab_down := false
var _toast_tween: Tween

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
	var panel := _panel(Vector2(12, 12), Vector2(276, 134))
	root.add_child(panel)
	panel.add_child(_label("车况", 15, TEXT_DIM, Vector2(14, 10)))
	dur_fill = _add_bar(panel, Vector2(58, 13))
	panel.add_child(_label("燃料", 15, TEXT_DIM, Vector2(14, 36)))
	fuel_fill = _add_bar(panel, Vector2(58, 39))
	res_label = _label("食物 0 · 队伍 0 人", 15, TEXT_MAIN, Vector2(14, 66))
	panel.add_child(res_label)
	info_label = _label("里程 0.0 km · 第 1 天 09:00", 15, TEXT_DIM, Vector2(14, 94))
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

func _process(_delta: float) -> void:
	var tab := Input.is_physical_key_pressed(KEY_TAB)
	if tab and not _tab_down:
		crew_visible = not crew_visible
		crew_panel.visible = crew_visible
	_tab_down = tab
	if rv == null:
		return
	speed_label.text = "%d km/h" % int(rv.speed_kmh)

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
