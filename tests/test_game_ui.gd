extends SceneTree

var game: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): push_error("UI test timed out"); quit(1))
	call_deferred("run")

func verify(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func capture(name: String) -> void:
	await process_frame
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/game/" + name + ".png")

func press(label: String) -> void:
	for button in game.hud.find_children("*", "Button", true, false):
		if button.text == label and button.is_visible_in_tree():
			button.pressed.emit()
			return
	verify(false, "Visible button exists: " + label)

func point(x: int, y: int) -> Vector2:
	game.camera.force_update_scroll()
	var grid: GridState = game.session.grid
	return game.view.get_global_transform_with_canvas() * game.view.project(x, y, grid.surface(grid.index(x, y)))

func click(where: Vector2, button: int) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = where
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = where
	event.button_index = button
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)

func run() -> void:
	root.size = Vector2i(1360, 860)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	game.save_path = "res://work/game/ui-save.dat"
	await capture("title")
	game._new_game("invalid")
	verify(game.screen == "title" and game.hud.title_note.text.contains("整数"), "Title rejects malformed terrain seed")
	var data := SaveStore.new().read("res://work/game/generated.dat")
	verify(not data.is_empty(), "Rendered test loads model-tested generated map")
	game._attach_session(GameSession.from_data(data))
	await capture("transition")
	var before: float = game.session.elapsed
	game._process(1.0)
	verify(game.session.elapsed == before, "Phase effect freezes the simulation")
	press("進める")
	await process_frame
	game.session.paused = true
	game._refresh()
	await capture("playing")
	verify(game.hud.inlet_label.text.contains("1800000") and game.hud.inlet_label.text.contains("cm³/s"), "Total and individual inlet flows always displayed in physical units")
	var where := point(38, 30)
	click(where, MOUSE_BUTTON_RIGHT)
	verify(game.hud.popup.visible and game.hud.popup_cell >= 0, "Right click opens local cell popup")
	verify(game.hud.popup_info.text.contains("最高水位") and game.hud.popup_info.text.contains("cm³/s"), "Popup contains depth, throughput and peak water")
	await capture("inspect")
	game.hud.hide_popup()
	game._set_tool(1)
	var cell: int = game._cell_at(where)
	var height: float = game.session.grid.elevation[cell]
	var power: int = game.session.power
	click(where, MOUSE_BUTTON_LEFT)
	verify(is_equal_approx(game.session.grid.elevation[cell], height + 1.0) and game.session.power == power - 10, "Left click applies one 100-cm brush and charges ten")
	key(KEY_TAB)
	verify(game.session.speed == 2, "Tab selects double speed")
	key(KEY_TAB)
	verify(game.session.speed == 4, "Tab selects quadruple speed")
	key(KEY_TAB)
	verify(game.session.speed == 1, "Tab cycles back to normal speed")
	key(KEY_SPACE)
	verify(not game.session.paused, "Space resumes preparation")
	game.session.speed = 4
	game._refresh()
	game.set_process(true)
	var start := Time.get_ticks_msec()
	before = game.session.elapsed
	while Time.get_ticks_msec() - start < 2500:
		await process_frame
	game.set_process(false)
	game._finish_batch(true)
	var advance: float = game.session.elapsed - before
	print("REALTIME_4X: ", advance, " simulation seconds / 2.5 wall seconds")
	verify(advance >= 8.5 and advance <= 11.0, "4x simulation keeps real-time pace")
	game.session.paused = true
	game.session.phase_seconds = 150.4
	game._request_skip()
	before = game.session.elapsed
	game._process(1.0)
	verify(game.session.elapsed == before and game.hud.modal_kind == "skip", "Skipping asks confirmation and stops time")
	press("水の流れを進めて終える")
	verify(game.view.is_visible_in_tree() and game.hud.game_screen.visible and not game.hud.loading_screen.visible and not game.modal_open, "Fast-forward keeps the map and game HUD visible without a loading overlay")
	verify(game.hud.phase_label.text.contains("早送りします") and game.hud.toggle_button.disabled and game.hud.speed_button.disabled and game.hud.skip_button.disabled and game.hud.tool_buttons[1].disabled, "Fast-forward shows remaining time and disables conflicting actions")
	var skip_water: PackedFloat64Array = game.view.grid.water.duplicate()
	var skip_bar: float = game.hud.time_bar.value
	key(KEY_SPACE)
	key(KEY_TAB)
	var skip_power: int = game.session.power
	click(where, MOUSE_BUTTON_LEFT)
	verify(game.skipping and not game.session.paused and game.session.speed == 4 and game.session.power == skip_power, "Space, Tab and terrain clicks cannot interrupt or edit the fast-forward")
	var zoom_before: float = game.camera.zoom.x
	click(where, MOUSE_BUTTON_WHEEL_UP)
	verify(game.camera.zoom.x > zoom_before, "The map can still be zoomed during fast-forward")
	key(KEY_HOME)
	await capture("skip-start")
	game.set_process(true)
	var skip_wall_start := Time.get_ticks_msec()
	await create_timer(0.35).timeout
	await capture("skip-running")
	game.set_process(false)
	game._finish_batch(true)
	verify(game.skipping and game.view.grid.water != skip_water and game.hud.time_bar.value < skip_bar, "Water snapshots and remaining time visibly update while fast-forward is running")
	print("SKIP_RENDERED: ", game.session.elapsed - before, " simulation seconds / ", float(Time.get_ticks_msec() - skip_wall_start) / 1000.0, " wall seconds")
	game.set_process(true)
	while game.skipping:
		await process_frame
	game.set_process(false)
	game._finish_batch(true)
	verify(game.session.phase == GameSession.Phase.RAIN and game.session.transition_pending and game.hud.modal_kind == "transition", "Confirmed skip simulates every remaining tick and pauses before rainfall")
	verify(is_equal_approx(game.session.elapsed - before, 29.6), "Skip advances remaining water time rather than jumping the clock")
	await capture("rain-transition")
	press("進める")
	game._refresh()
	verify(game.audio.rain_player.playing and game.rain.emitting, "Rainfall starts environmental sound and particles")
	game.set_process(true)
	await create_timer(1.0).timeout
	game.set_process(false)
	game._finish_batch(true)
	game._refresh()
	await capture("rain")
	game.session.phase_seconds = 59.95
	game.session.advance_ticks(1)
	game._refresh()
	game._handle_phase()
	verify(game.hud.modal_kind == "report" and not game.audio.rain_player.playing, "Accounting opens report and stops rain sound")
	await capture("report")
	game.session.turn = 1
	game.session.development.current_seconds = 300.0
	game.session.development.current_wet.fill(0.0)
	game.session.development.previous_wet.fill(0.0)
	press("次の治水へ進む")
	verify(game.session.development.population() == 1 and game.session.turn == 2 and game.session.calendar().contains("夏"), "First settlement appears at the start of summer in the playable scene")
	await capture("arrival")
	press("進める")
	game.session.paused = true
	game._refresh()
	await capture("settlement")
	var seed: int = game.session.terrain_seed
	var water: PackedFloat64Array = game.session.grid.water.duplicate()
	game._return_title()
	verify(game.hud.continue_button.disabled == false, "Saved game enables continue at title")
	game._continue_game()
	verify(game.session.terrain_seed == seed and game.session.grid.water == water and game.session.development.population() == 1, "Title continuation restores edited world and households")
	verify(not game.hud.seed_label.text.contains("シナリオ"), "Only terrain seed is disclosed")
	verify(absf(game.session.solver.balance_error()) < 1e-6, "Threaded gameplay remains conservative")
	print("GAME_UI_RESULT: %d checks, %d failures" % [checks, failures])
	game.audio.set_muted(true)
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)
