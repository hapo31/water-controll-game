class_name DebugHUD
extends CanvasLayer

signal water_reset_requested
signal terrain_reset_requested
signal weather_requested(weather: int)
signal toggle_requested
signal step_requested
signal home_requested
signal tool_requested(mode: int)

var status: Label
var numbers: Label
var cell_info: Label
var toggle_button: Button
var fps_label: Label
var weather_select: OptionButton
var fps_update_elapsed := 0.0

func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(298, 0)
	add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.13, 0.14, 0.97)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	var title := _label(box, "治水の神", 26)
	title.add_theme_color_override("font_color", Color(0.79, 0.91, 0.75))
	_label(box, "水の実験室  /  256 × 256", 15)
	_label(box, "山の支流 → 合流湖 → 蛇行 → 海", 14)
	box.add_child(HSeparator.new())
	_button(box, "水の状態を初期化", func(): water_reset_requested.emit()).tooltip_text = "地形を残し、水量と水の計測値を起動時の状態に戻します。"
	_button(box, "地形を初期化", func(): terrain_reset_requested.emit()).tooltip_text = "地形・水・計測値・時間を起動時に戻します。天候は豪雨、再生は停止状態になります。"
	var weather_row := HBoxContainer.new()
	weather_row.add_theme_constant_override("separation", 12)
	box.add_child(weather_row)
	_label(weather_row, "雨の強さ", 14)
	weather_select = OptionButton.new()
	weather_select.add_item("晴れ", RainExperiment.Weather.SUNNY)
	weather_select.add_item("通常", RainExperiment.Weather.NORMAL)
	weather_select.add_item("豪雨", RainExperiment.Weather.HEAVY)
	weather_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weather_select.custom_minimum_size.y = 32
	weather_select.focus_mode = Control.FOCUS_NONE
	weather_select.tooltip_text = "天候だけを切り替えます。地形と水はそのまま残ります。"
	weather_select.item_selected.connect(func(index: int): weather_requested.emit(weather_select.get_item_id(index)))
	weather_row.add_child(weather_select)
	toggle_button = _button(box, "開始 / 停止 [Space]", func(): toggle_requested.emit())
	_button(box, "1刻み（停止中）", func(): step_requested.emit())
	_button(box, "視点を戻す", func(): home_requested.emit())
	var tools := OptionButton.new()
	tools.add_item("選択 / 観察", 0)
	tools.add_item("盛土 +0.5（長押し可）", 1)
	tools.add_item("掘削 -0.5（長押し可）", 2)
	tools.set_item_tooltip(1, "停止中に左クリックを押し続けると連続盛土。ドラッグで対象のマスを変更。")
	tools.set_item_tooltip(2, "停止中に左クリックを押し続けると連続掘削。ドラッグで対象のマスを変更。")
	tools.item_selected.connect(func(index: int): tool_requested.emit(index))
	box.add_child(tools)
	box.add_child(HSeparator.new())
	status = _label(box, "", 16)
	fps_label = _label(box, "FPS           --", 14)
	numbers = _label(box, "", 14)
	box.add_child(HSeparator.new())
	cell_info = _label(box, "左クリックでセル情報を表示", 14)
	box.add_child(HSeparator.new())
	_label(box, "右/中ドラッグ：移動 · ホイール：拡縮\n天候変更で地形・水は保持\n晴れでも流入・排水は継続", 13)
	_label(box, "数値はゲーム内単位 / 実験用操作", 12)

func _process(delta: float) -> void:
	fps_update_elapsed += delta
	if fps_update_elapsed >= 0.25:
		fps_update_elapsed = 0.0
		fps_label.text = "FPS           %d" % Engine.get_frames_per_second()

func _label(parent: Node, value: String, size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label

func _button(parent: Node, value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 32
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func update_state(experiment: RainExperiment, selected: int) -> void:
	var grid := experiment.grid

	weather_select.select(experiment.weather)
	status.text = "%s  /  %s\n%s  /  %.2f秒" % [experiment.weather_label(),
		"実行中" if experiment.running else "一時停止", experiment.phase_label(), experiment.elapsed]
	toggle_button.text = "停止 [Space]" if experiment.running else "開始 / 続行 [Space]"
	numbers.text = "陸域の水量    %.2f\n浸水セル      %d / 経験 %d\n収支誤差      %.8f\n流入設定      %.2f /秒\n海への排水    %.2f /秒\n累計 雨/流入  %.1f / %.1f\n累計 排水/蒸発 %.1f / %.1f\n水計算        %.1f ms /刻み" % [
		experiment.summary.water, experiment.summary.inundated_now, experiment.summary.inundated_peak,
		experiment.summary.balance_error, FixedMap.INFLOW_PER_CELL * grid.source_cells.size(),
		experiment.summary.drain_rate, experiment.summary.rain, experiment.summary.inflow,
		experiment.summary.drained, experiment.summary.evaporated, experiment.step_ms]
	if selected >= 0:
		var kind := "河道" if grid.river[selected] == 1 else "陸地"
		if grid.source_cells.has(selected):
			kind = "流入 +%.1f/秒" % FixedMap.INFLOW_PER_CELL
		elif grid.sea[selected]:
			kind = "海（排水 / 編集不可）"
		elif grid.lake[selected]:
			kind = "湖"
		cell_info.text = "セル (%d, %d)  %s\n標高 %.3f   水深 %.3f\n水面高 %.3f   最大水深 %.3f" % [
			selected % grid.width, selected / grid.width, kind,
			grid.elevation[selected], grid.visible_depth(selected), grid.surface(selected), grid.visible_depth(selected) if grid.sea[selected] else grid.peak_depth[selected]]
	else:
		cell_info.text = "左クリックでセル情報を表示\n標高・水深・水面高を比較"
