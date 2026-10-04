class_name GameHUD
extends CanvasLayer

signal new_requested(seed_text: String)
signal continue_requested
signal toggle_requested
signal speed_requested
signal skip_requested
signal skip_confirmed
signal save_requested
signal title_requested
signal home_requested
signal next_requested
signal transition_dismissed
signal tool_requested(mode: int)
signal sound_requested(muted: bool)
signal modal_changed(open: bool)
const Landscape = preload("res://scripts/ui/title_landscape.gd")
const SettlementIcon = preload("res://scripts/ui/settlement_icon.gd")
const PAPER := Color("f0e7cf")
const MUTED := Color("adc0b6")
var root_control: Control
var title_screen: Control
var game_screen: Control
var loading_screen: Control
var title_note: Label
var seed_input: LineEdit
var continue_button: Button
var loading_bar: ProgressBar
var loading_label: Label
var calendar_label: Label
var phase_label: Label
var power_label: Label
var weather_label: Label
var inlet_label: Label
var population_label: Label
var seed_label: Label
var time_bar: ProgressBar
var toggle_button: Button
var speed_button: Button
var skip_button: Button
var tool_buttons: Array[Button] = []
var inspector: Label
var eligible_icon: Control
var toast_label: Label
var modal: Control
var modal_box: VBoxContainer
var modal_kind := ""
var popup: PanelContainer
var popup_info: Label
var popup_icon: Control
var toast_remaining := 0.0
var popup_cell := -1

func _ready() -> void:
	root_control = Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", PAPER)
	theme.set_color("font_color", "Button", PAPER)
	theme.set_stylebox("normal", "Button", _style(Color("263e3d"), 7, 12))
	theme.set_stylebox("hover", "Button", _style(Color("3d5750"), 7, 12))
	theme.set_stylebox("pressed", "Button", _style(Color("5a6a50"), 7, 12))
	theme.set_stylebox("disabled", "Button", _style(Color("203132"), 7, 12))
	theme.set_color("font_disabled_color", "Button", Color("637973"))
	theme.set_stylebox("background", "ProgressBar", _style(Color("12282b"), 4, 0))
	theme.set_stylebox("fill", "ProgressBar", _style(Color("6b9c91"), 4, 0))
	root_control.theme = theme
	add_child(root_control)
	_build_title()
	_build_game()
	_build_loading()
	_build_popup()
	get_viewport().size_changed.connect(_layout)
	_layout()
	show_title(false)

func _style(color: Color, radius: int, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style

func _layer() -> Control:
	var control := Control.new()
	root_control.add_child(control)
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control

func _panel(parent: Node, width: float = 0.0) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.add_theme_stylebox_override("panel", _style(Color(0.07, 0.15, 0.16, 0.96), 12, 20))
	parent.add_child(panel)
	return panel

func _box(parent: Node, separation: int = 10) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	parent.add_child(box)
	return box

func _label(parent: Node, value: String, font_size: int = 16, color: Color = PAPER) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 42
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _build_title() -> void:
	title_screen = _layer()
	var landscape := Landscape.new()
	title_screen.add_child(landscape)
	landscape.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var centered := CenterContainer.new()
	title_screen.add_child(centered)
	centered.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := _box(_panel(centered, 540), 15)
	_label(box, "治水の神", 52)
	_label(box, "地形を変えて、水の流れを導きます。", 19, MUTED)
	box.add_child(HSeparator.new())
	_label(box, "地形シードを指定できます。", 15, MUTED)
	seed_input = LineEdit.new()
	seed_input.placeholder_text = "空欄にすると、新しい地形を作ります。"
	seed_input.max_length = 10
	seed_input.custom_minimum_size.y = 42
	box.add_child(seed_input)
	_button(box, "新しく始める", func(): new_requested.emit(seed_input.text))
	continue_button = _button(box, "続きから始める", func(): continue_requested.emit())
	title_note = _label(box, "", 14, MUTED)
	title_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(box, "最初の2ターンで、人が住む土地を整えます。", 14, MUTED)
	_label(box, "水理PoC  ·  キーボードとマウスで遊べます。", 13, Color("81988d"))

func _build_game() -> void:
	game_screen = _layer()
	var top := _panel(game_screen)
	top.name = "Top"
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_top = 14
	top.offset_right = -16
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	top.add_child(row)
	_label(row, "治水の神", 24)
	calendar_label = _label(row, "")
	calendar_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	population_label = _label(row, "")
	power_label = _label(row, "", 23, Color("e7c88a"))
	var side_scroll := ScrollContainer.new()
	side_scroll.name = "SideScroll"
	game_screen.add_child(side_scroll)
	side_scroll.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	side_scroll.offset_left = 16
	side_scroll.offset_top = 108
	side_scroll.offset_right = 306
	side_scroll.offset_bottom = -120
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var side := _panel(side_scroll, 280)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.name = "Side"
	var box := _box(side, 7)
	phase_label = _label(box, "", 22)
	time_bar = ProgressBar.new()
	time_bar.show_percentage = false
	time_bar.custom_minimum_size.y = 7
	box.add_child(time_bar)
	weather_label = _label(box, "", 14, MUTED)
	inlet_label = _label(box, "", 16, Color("91d3cb"))
	seed_label = _label(box, "", 13, MUTED)
	box.add_child(HSeparator.new())
	var icon_row := HBoxContainer.new()
	box.add_child(icon_row)
	eligible_icon = SettlementIcon.new()
	icon_row.add_child(eligible_icon)
	_label(icon_row, "マスを調べられます。", 16)
	inspector = _label(box, "右クリックで水位を調べます。", 13, MUTED)
	inspector.custom_minimum_size = Vector2(240, 120)
	inspector.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(HSeparator.new())
	_label(box, "橙色の平坦な土地に移住できます。\n10×10マスの高低差は100cm以内です。\n50cm以上の浸水で報酬を失います。\n100cm以上で住民を失います。", 13, MUTED)
	_button(box, "視点を戻す [Home]", func(): home_requested.emit())
	_button(box, "保存する [F5]", func(): save_requested.emit())
	_button(box, "保存してタイトルへ戻る", func(): title_requested.emit())
	var mute := CheckButton.new()
	mute.text = "音を消す"
	mute.focus_mode = Control.FOCUS_NONE
	mute.toggled.connect(func(value: bool): sound_requested.emit(value))
	box.add_child(mute)
	var bottom := _panel(game_screen)
	bottom.name = "Bottom"
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 16
	bottom.offset_right = -16
	bottom.offset_top = -108
	bottom.offset_bottom = -14
	var bottom_box := _box(bottom, 7)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	bottom_box.add_child(controls)
	for n in 3:
		var mode := n
		var button := _button(controls, ["調べる [1]", "盛土する [2]", "掘削する [3]"][n], func(): tool_requested.emit(mode))
		button.tooltip_text = "1回で100cm変え、周囲もなだらかに変えます。神力を10使います。" if n > 0 else "左クリックで選び、右クリックで詳しく調べます。"
		tool_buttons.append(button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(spacer)
	toggle_button = _button(controls, "停止する [Space]", func(): toggle_requested.emit())
	speed_button = _button(controls, "等速 [Tab]", func(): speed_requested.emit())
	skip_button = _button(controls, "治水を終える", func(): skip_requested.emit())
	_label(bottom_box, "左クリックで操作します。　右クリックで調べます。　中ドラッグ / WASDで移動します。　ホイールで拡縮します。", 13, MUTED)
	toast_label = _label(game_screen, "", 17, PAPER)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toast_label.offset_top = 89
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var compass := _label(game_screen, "　　　　 北\n　　　 ↗\n西 ↖　✦　↘ 東\n　　　 ↙\n　　南", 16, MUTED)
	compass.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	compass.offset_left = -164
	compass.offset_top = 108
	compass.offset_right = -24

func _build_loading() -> void:
	loading_screen = _layer()
	var shade := ColorRect.new()
	shade.color = Color("10262a")
	loading_screen.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var centered := CenterContainer.new()
	loading_screen.add_child(centered)
	centered.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := _box(_panel(centered, 580), 20)
	loading_label = _label(box, "地形を作っています。", 24)
	loading_bar = ProgressBar.new()
	loading_bar.custom_minimum_size.y = 15
	loading_bar.show_percentage = true
	box.add_child(loading_bar)
	_label(box, "水の流れを確かめています。", 15, MUTED)

func _build_popup() -> void:
	popup = _panel(root_control, 288)
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := _box(popup, 6)
	var row := HBoxContainer.new()
	box.add_child(row)
	popup_icon = SettlementIcon.new()
	row.add_child(popup_icon)
	_label(row, "マスの水位を調べます。", 17)
	popup_info = _label(box, "", 14, MUTED)
	_button(box, "閉じる", hide_popup)
	popup.hide()

func _layout() -> void:
	if popup != null and popup.visible:
		popup.position = popup.position.clamp(Vector2(8, 8), get_viewport().get_visible_rect().size - popup.size - Vector2(8, 8))

func show_title(can_continue: bool, note: String = "") -> void:
	close_modal()
	title_screen.show()
	game_screen.hide()
	loading_screen.hide()
	hide_popup()
	continue_button.disabled = not can_continue
	title_note.text = note if not note.is_empty() else ("保存したところから再開できます。" if can_continue else "まだ保存した記録がありません。")

func show_loading(progress: float, message: String) -> void:
	title_screen.hide()
	game_screen.hide()
	loading_screen.show()
	loading_bar.value = progress * 100.0
	loading_label.text = message

func show_game() -> void:
	title_screen.hide()
	loading_screen.hide()
	game_screen.show()

func set_tool(mode: int) -> void:
	for n in tool_buttons.size():
		tool_buttons[n].modulate = Color("edc68e") if n == mode else Color.WHITE

func update_state(session: GameSession, selected: int) -> void:
	calendar_label.text = session.calendar()
	population_label.text = "住民 %d人" % session.development.population()
	power_label.text = "神力 %d" % session.power
	var preparing := session.phase == GameSession.Phase.PREPARE
	var seconds := ceili(session.remaining())
	phase_label.text = "治水します。 %02d:%02d" % [seconds / 60, seconds % 60] if preparing else "雨が降っています。 %02d秒" % ceili(session.remaining() / 4.0)
	if session.phase in [GameSession.Phase.REPORT, GameSession.Phase.GAME_OVER]:
		phase_label.text = "結果を確認します。"
	time_bar.value = session.remaining() / (180.0 if preparing else 60.0) * 100.0
	weather_label.text = session.weather_label()
	inlet_label.text = "流入 %.0f cm³/s\n各流入マス %.0f cm³/s" % [GameUnits.flow_cm3(session.inflow_rate()), GameUnits.flow_cm3(session.inflow_rate() / 3.0)]
	seed_label.text = "地形シード %d" % session.terrain_seed
	toggle_button.text = "再生する [Space]" if session.paused else "停止する [Space]"
	toggle_button.disabled = not preparing
	speed_button.text = "%s [Tab]" % ("等速" if session.speed == 1 else "%d倍速" % session.speed)
	if session.phase == GameSession.Phase.RAIN:
		speed_button.text = "4倍速で進みます。"
	speed_button.disabled = not preparing
	skip_button.disabled = not preparing
	for n in range(1, 3):
		tool_buttons[n].disabled = not preparing or session.power < 10
	inspector.text = cell_text(session, selected) if selected >= 0 else "右クリックで水位を調べます。\n\n1マスは100cmです。\n盛土・掘削で神力を10使います。"
	eligible_icon.visible = selected >= 0 and session.development.eligible[selected] != 0
	if popup.visible and popup_cell >= 0:
		popup_info.text = cell_text(session, popup_cell)
		popup_icon.visible = session.development.eligible[popup_cell] != 0

func cell_text(session: GameSession, cell: int) -> String:
	var grid := session.grid
	var kind := "川筋" if grid.river[cell] else "陸地"
	if grid.source_cells.has(cell):
		kind = "流入マス"
	elif grid.sea[cell]:
		kind = "海へ排水します。"
	var house := session.development.house_at(cell)
	var text := "(%d, %d)  %s\n標高 %.0f cm\n水量（水深） %.1f cm\n流量 %.0f cm³/s\n最高水位（水深） %.1f cm\n水面高 %.1f cm" % [cell % grid.width, cell / grid.width, kind,
		grid.elevation[cell] * 100.0, grid.visible_depth(cell) * 100.0,
		GameUnits.flow_cm3(grid.discharge[cell]), grid.peak_depth[cell] * 100.0, grid.surface(cell) * 100.0]
	if session.development.eligible[cell]:
		text += "\n移住できる土地です。"
	if not house.is_empty():
		text += "\n家 %dに%d人が住んでいます。" % [house.id, house.population]
	return text

func show_popup(session: GameSession, cell: int, point: Vector2) -> void:
	popup_cell = cell
	popup_info.text = cell_text(session, cell)
	popup_icon.visible = session.development.eligible[cell] != 0
	popup.position = point + Vector2(16, 12)
	popup.show()
	popup.reset_size()
	_layout()

func hide_popup() -> void:
	popup.hide()
	popup_cell = -1

func toast(message: String) -> void:
	toast_label.text = message
	toast_remaining = 3.5

func _process(delta: float) -> void:
	if toast_remaining > 0.0:
		toast_remaining -= delta
		if toast_remaining <= 0.0:
			toast_label.text = ""

func _open_modal(kind: String, width: float = 640) -> VBoxContainer:
	close_modal()
	hide_popup()
	modal_kind = kind
	modal = ColorRect.new()
	modal.color = Color(0.01, 0.04, 0.05, 0.78)
	root_control.add_child(modal)
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var centered := CenterContainer.new()
	modal.add_child(centered)
	centered.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := _panel(centered, width)
	modal_box = _box(panel, 14)
	modal_changed.emit(true)
	panel.modulate.a = 0.0
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.3)
	return modal_box

func close_modal() -> void:
	if modal != null:
		modal.queue_free()
		modal = null
		modal_kind = ""
		modal_changed.emit(false)

func show_transition(session: GameSession) -> void:
	var box := _open_modal("transition")
	_label(box, session.calendar(), 17, MUTED)
	_label(box, "治水を始めます。" if session.phase == GameSession.Phase.PREPARE else "雨が降り始めます。", 34)
	if session.phase == GameSession.Phase.PREPARE:
		_label(box, "地形を変えて、水の流れを整えられます。", 18, MUTED)
		if session.turn < GameSession.FIRST_SETTLEMENT_TURN:
			_label(box, "春の2ターンが終わると、条件を満たした土地に人が移住します。", 15, MUTED)
		if not session.notification.is_empty():
			_label(box, session.notification, 18, Color("edc68e"))
	else:
		_label(box, session.weather_label(), 20, Color("91d3cb"))
		_label(box, "流入量が%.2f倍になります。15秒間、4倍速で進みます。" % session.weather_multiplier, 16, MUTED)
	_button(box, "進める", func(): close_modal(); transition_dismissed.emit())

func show_skip(session: GameSession) -> void:
	var box := _open_modal("skip")
	_label(box, "治水を終えますか？", 30)
	_label(box, "残り%.0f秒の水の流れを進めてから、雨を迎えます。" % session.remaining(), 17, MUTED)
	_button(box, "水の流れを進めて終える", func(): close_modal(); skip_confirmed.emit())
	_button(box, "治水を続ける", close_modal)

func show_report(session: GameSession) -> void:
	var report := session.last_report
	var ended := session.phase == GameSession.Phase.GAME_OVER
	var box := _open_modal("report", 760)
	_label(box, session.calendar(), 16, MUTED)
	_label(box, "この流域での治水が終わりました。" if ended else "水害の結果を確認します。", 30)
	if ended:
		_label(box, report.reason, 20, Color("e6a18b"))
	_label(box, "住民 %d人　失った住民 %d人\n神力 +%d　被害による減少 −%d\n神力 %d → %d" % [report.population, report.lost_people, report.reward, report.penalty, report.before, report.power], 21)
	if report.rows.is_empty():
		_label(box, "まだ人は住んでいません。土地を整えて移住を待ちます。", 16, MUTED)
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size.y = minf(300.0, 32.0 * (report.rows.size() + 1))
		box.add_child(scroll)
		var table := GridContainer.new()
		table.columns = 4
		table.add_theme_constant_override("h_separation", 24)
		table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(table)
		for value in ["家", "住民", "最高水位", "被害"]:
			_label(table, value, 15, MUTED)
		for row in report.rows:
			for value in [str(row.id), "%d人" % row.population, "%.1f cm" % row.peak_cm, row.status]:
				_label(table, value, 16)
	_label(box, "確認している間、時間は止まっています。", 15, MUTED)
	if not ended:
		_button(box, "次の治水へ進む", func(): close_modal(); next_requested.emit())
	_button(box, "保存してタイトルへ戻る", func(): title_requested.emit())
