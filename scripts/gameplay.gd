extends Node2D

@onready var view: GameWorldView = $WorldView
@onready var camera: Camera2D = $Camera2D
@onready var hud: GameHUD = $GameHUD
@onready var rain: RainEffect = $RainLayer/RainParticles
@onready var audio: GameAudio = $GameAudio
var session: GameSession
var saves := SaveStore.new()
var saved_data := {}
var generator: TerrainGenerator
var generation_thread := Thread.new()
var simulation_thread := Thread.new()
var accumulator := 0.0
var tool_mode := 0
var modal_open := false
var skipping := false
var autosave_seconds := 0.0
var last_phase := -1
var screen := "title"
var pointer := Vector2.ZERO
var pointer_inside := true
var display_development: DevelopmentSystem
var save_path := SaveStore.PATH
var published_rate := 0
var published_raining := false
var published_heavy := false
var published_mountain_rain := false
const SKIP_BATCH_TICKS := 16

func _ready() -> void:
	hud.new_requested.connect(_new_game)
	hud.continue_requested.connect(_continue_game)
	hud.toggle_requested.connect(_toggle)
	hud.speed_requested.connect(_cycle_speed)
	hud.skip_requested.connect(_request_skip)
	hud.skip_confirmed.connect(_confirm_skip)
	hud.save_requested.connect(_manual_save)
	hud.title_requested.connect(_return_title)
	hud.home_requested.connect(_home)
	hud.next_requested.connect(_next_turn)
	hud.transition_dismissed.connect(_dismiss_transition)
	hud.tool_requested.connect(_set_tool)
	hud.sound_requested.connect(func(value: bool): audio.set_muted(value); _update_weather())
	hud.modal_changed.connect(func(value: bool): modal_open = value; accumulator = 0.0)
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(_close_game)
	get_viewport().size_changed.connect(_home)
	get_viewport().mouse_exited.connect(func(): pointer_inside = false; view.set_hovered(-1))
	get_viewport().mouse_entered.connect(func(): pointer_inside = true)
	_show_title()

func _show_title() -> void:
	screen = "title"
	view.hide()
	rain.reset_weather()
	audio.set_rain(false, false)
	saved_data = saves.read(save_path)
	hud.show_title(not saved_data.is_empty(), saves.error_message)

func _new_game(seed_text: String) -> void:
	var trimmed := seed_text.strip_edges()
	if not trimmed.is_empty() and (not trimmed.is_valid_int() or trimmed.to_int() < 0 or trimmed.to_int() > 2147483647):
		hud.title_note.text = "地形シードは0から2147483647の整数にしてください。"
		audio.play_cue("error")
		return
	var terrain_seed := trimmed.to_int() if not trimmed.is_empty() else int(randi() & 0x7fffffff)
	audio.play_cue("confirm")
	screen = "generating"
	view.hide()
	generator = TerrainGenerator.new(terrain_seed)
	hud.show_loading(0.0, "地形を作っています。")
	generation_thread.start(generator.generate)

func _continue_game() -> void:
	if saved_data.is_empty():
		return
	audio.play_cue("confirm")
	_attach_session(GameSession.from_data(saved_data))

func _attach_session(value: GameSession) -> void:
	session = value
	screen = "game"
	accumulator = 0.0
	autosave_seconds = 0.0
	last_phase = -1
	display_development = DevelopmentSystem.new(session.grid.water.size())
	view.grid = GridState.new(session.grid.width, session.grid.height)
	view.grid.river = session.grid.river
	view.grid.sea = session.grid.sea
	view.grid.source_cells = session.grid.source_cells
	view.development = display_development
	view.selected = -1
	view.show()
	hud.show_game()
	_set_tool(0)
	_refresh()
	_home()
	_handle_phase()
	_save(false)

func _finish_batch(wait: bool = false) -> bool:
	if not simulation_thread.is_started():
		return false
	if simulation_thread.is_alive() and not wait:
		return false
	simulation_thread.wait_to_finish()
	return true

func _process(delta: float) -> void:
	if screen == "generating":
		var status := generator.status()
		hud.show_loading(status.progress, status.stage)
		if not generation_thread.is_alive():
			var state: GridState = generation_thread.wait_to_finish()
			_attach_session(GameSession.new(state, generator.terrain_seed, int(randi() & 0x7fffffff)))
		return
	if screen != "game":
		return
	if not skipping and not modal_open and published_rate > 0:
		# Include frames spent waiting for the worker in the real-time clock.
		accumulator = minf(accumulator + delta * published_rate, 2.0)
	if skipping and not modal_open:
		_update_camera(delta)
		_update_hover()
	var changed := _finish_batch()
	# No reads of live gameplay state while the worker is writing it.
	# WorldView uses a separate published snapshot, including house records.
	if simulation_thread.is_started():
		return
	if changed:
		if skipping and session.phase != GameSession.Phase.PREPARE:
			skipping = false
		_refresh()
		_handle_phase()
	if skipping:
		if session.phase != GameSession.Phase.PREPARE:
			skipping = false
			_refresh()
			_handle_phase()
		else:
			simulation_thread.start(session.advance_ticks.bind(SKIP_BATCH_TICKS))
		return
	if modal_open:
		_update_weather()
		return
	_update_camera(delta)
	_update_hover()
	if session.can_advance():
		var ticks := mini(32, floori(accumulator / WaterSimulator.FIXED_DT))
		if ticks > 0:
			accumulator -= ticks * WaterSimulator.FIXED_DT
			simulation_thread.start(session.advance_ticks.bind(ticks))
	autosave_seconds += delta
	if autosave_seconds >= 20.0:
		_finish_batch(true)
		_refresh()
		_save(false)
		autosave_seconds = 0.0

func _refresh() -> void:
	published_rate = (session.speed if session.phase == GameSession.Phase.PREPARE else 4) if session.can_advance() else 0
	published_raining = session.phase == GameSession.Phase.RAIN
	published_heavy = session.weather >= 2
	published_mountain_rain = session.weather % 2 == 0
	for key in ["elevation", "water", "peak_depth", "flow", "discharge", "origin_mask"]:
		view.grid.set(key, session.grid.get(key))
	display_development.houses.assign(session.development.houses.duplicate(true))
	display_development.eligible = session.development.eligible
	view.boundary_rate = GameUnits.flow_cm3(session.inflow_rate() / 3.0)
	view.invalidate_state()
	view.update_highlights()
	hud.update_state(session, view.selected, skipping)
	_update_weather()

func _handle_phase() -> void:
	if skipping and session.phase == GameSession.Phase.PREPARE:
		return
	if last_phase != session.phase:
		last_phase = session.phase
		var loss: bool = session.phase == GameSession.Phase.GAME_OVER or (session.phase == GameSession.Phase.REPORT and session.last_report.get("lost_houses", 0) > 0)
		audio.play_cue("loss" if loss else "phase")
		_save(false)
	if session.transition_pending and hud.modal_kind != "transition":
		hud.show_transition(session)
		if session.notification.contains("移住し") or session.notification.contains("家族"):
			audio.play_cue("arrival")
	elif session.phase in [GameSession.Phase.REPORT, GameSession.Phase.GAME_OVER] and hud.modal_kind != "report":
		hud.show_report(session)
	_update_weather()

func _update_weather() -> void:
	if session == null or screen != "game":
		return
	var raining := published_raining
	var active := raining and not modal_open and published_rate > 0
	rain.update_weather(raining, active, published_heavy)
	if raining and published_mountain_rain:
		# Mountain weather occupies the upper part of the map, never the whole screen.
		var north := view.get_global_transform_with_canvas() * view.project(32, 2, 6.0)
		rain.position = north + Vector2(0, -80)
		rain.emission_rect_extents = Vector2(400 * camera.zoom.x, 70 * camera.zoom.x)
		rain.lifetime = 0.18
		rain.initial_velocity_min = 280.0
		rain.initial_velocity_max = 350.0
	else:
		rain.lifetime = 0.55
		rain.initial_velocity_min = 520.0
		rain.initial_velocity_max = 700.0
		rain._fit_viewport()
	audio.set_rain(active, published_heavy)

func _dismiss_transition() -> void:
	_finish_batch(true)
	session.dismiss_transition()
	accumulator = 0.0
	audio.play_cue("confirm")
	_refresh()

func _next_turn() -> void:
	_finish_batch(true)
	session.next_turn()
	accumulator = 0.0
	_refresh()
	_handle_phase()

func _toggle() -> void:
	if screen != "game" or modal_open or skipping:
		return
	_finish_batch(true)
	if session.phase != GameSession.Phase.PREPARE:
		return
	session.paused = not session.paused
	accumulator = 0.0
	audio.play_cue("confirm")
	_refresh()

func _cycle_speed() -> void:
	if screen != "game" or modal_open or skipping:
		return
	_finish_batch(true)
	if session.phase == GameSession.Phase.PREPARE:
		session.speed = 2 if session.speed == 1 else 4 if session.speed == 2 else 1
		audio.play_cue("confirm")
		_refresh()

func _set_tool(mode: int) -> void:
	tool_mode = mode
	hud.set_tool(mode)
	audio.play_cue("confirm")

func _request_skip() -> void:
	if screen != "game" or modal_open or skipping:
		return
	_finish_batch(true)
	if session.phase == GameSession.Phase.PREPARE:
		hud.show_skip(session)
		audio.play_cue("confirm")

func _confirm_skip() -> void:
	_finish_batch(true)
	if session.phase != GameSession.Phase.PREPARE or session.transition_pending or skipping:
		return
	skipping = true
	session.paused = false
	accumulator = 0.0
	hud.show_game()
	_refresh()
	audio.play_cue("confirm")

func _save(show_message: bool) -> bool:
	if session == null:
		return true
	var success := saves.write(session, save_path)
	if show_message or not success:
		hud.toast("保存しました。" if success else saves.error_message)
	return success

func _manual_save() -> void:
	_finish_batch(true)
	_refresh()
	_save(true)
	audio.play_cue("confirm")

func _return_title() -> void:
	_finish_batch(true)
	if not _save(true):
		return
	skipping = false
	hud.close_modal()
	_show_title()

func _close_game() -> void:
	_finish_batch(true)
	if generation_thread.is_started():
		generator.cancel()
		generation_thread.wait_to_finish()
	if _save(false):
		get_tree().quit()

func _exit_tree() -> void:
	_finish_batch(true)
	if generation_thread.is_started():
		generator.cancel()
		generation_thread.wait_to_finish()

func _home() -> void:
	if session == null or screen != "game":
		return
	var viewport := get_viewport_rect().size
	var map_size := Vector2((session.grid.width + session.grid.height) * WorldView.HALF_W,
		(session.grid.width + session.grid.height) * WorldView.HALF_H + 100.0)
	var zoom_level := maxf(0.15, minf((viewport.x - 350.0) / map_size.x, (viewport.y - 225.0) / map_size.y))
	camera.zoom = Vector2.ONE * zoom_level
	camera.position = Vector2(-150.0 / zoom_level, 330.0)
	camera.force_update_scroll()
	view.queue_redraw()

func _update_camera(delta: float) -> void:
	var direction := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if direction != Vector2.ZERO:
		camera.position += direction.normalized() * 420.0 * delta / camera.zoom.x
		camera.force_update_scroll()
		view.queue_redraw()

func _update_hover() -> void:
	if not pointer_inside or get_viewport().gui_get_hovered_control() != null:
		view.set_hovered(-1)
		return
	view.set_hovered(_cell_at(pointer))

func _cell_at(point: Vector2) -> int:
	camera.force_update_scroll()
	return view.pick(view.get_global_transform_with_canvas().affine_inverse() * point)

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		pointer = event.position
	if event is InputEventKey and event.pressed and not event.echo and screen == "game" and not modal_open:
		if event.keycode == KEY_SPACE:
			_toggle()
		elif event.keycode == KEY_TAB:
			_cycle_speed()
		elif event.keycode == KEY_F5:
			_manual_save()
		elif event.keycode == KEY_HOME:
			_home()
		elif event.keycode == KEY_ESCAPE:
			hud.hide_popup()
		elif event.keycode in [KEY_1, KEY_2, KEY_3] and not skipping:
			_set_tool(event.keycode - KEY_1)

func _unhandled_input(event: InputEvent) -> void:
	if screen != "game" or modal_open:
		return
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		camera.position -= event.relative / camera.zoom
		view.queue_redraw()
		_update_weather()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var zoom_factor := 1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
			camera.zoom = Vector2.ONE * clampf(camera.zoom.x * zoom_factor, 0.15, 3.0)
			view.queue_redraw()
			_update_weather()
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if skipping:
				return
			_finish_batch(true)
			var cell := _cell_at(event.position)
			if cell < 0:
				return
			view.selected = cell
			if event.button_index == MOUSE_BUTTON_RIGHT:
				hud.show_popup(session, cell, event.position)
				audio.play_cue("confirm")
			else:
				hud.hide_popup()
				if tool_mode > 0:
					if session.edit_terrain(cell, 1 if tool_mode == 1 else -1):
						audio.play_cue("earth")
					else:
						hud.toast("地形は治水中に変えられます。神力を10使います。")
						audio.play_cue("error")
				else:
					audio.play_cue("confirm")
			_refresh()
