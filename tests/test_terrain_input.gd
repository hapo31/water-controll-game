extends SceneTree

var main: Node
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run_checks")

func verify(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func point_for(x: int, y: int) -> Vector2:
	main.camera.force_update_scroll()
	var grid: GridState = main.experiment.grid
	return main.view.get_global_transform_with_canvas() * main.view.project(x, y, grid.surface(grid.index(x, y)))

func move_pointer(point: Vector2, held: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	main.pointer_inside = true
	root.push_input(event, true)

func left_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event, true)

func run_checks() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame
	main.set_process(false)
	for mode in [1, 2]:
		main._reset_terrain()
		main.experiment.grid.elevation.fill(3.0)
		main.experiment.grid.water.fill(0.0)
		main.view.invalidate_terrain()
		main.hud.tool_requested.emit(mode)
		var grid: GridState = main.experiment.grid
		var cell := grid.index(38, 32)
		var next_cell := grid.index(42, 32)
		var change := 0.5 if mode == 1 else -0.5
		var point := point_for(38, 32)
		move_pointer(point, false)
		await process_frame
		left_button(point, true)
		verify(is_equal_approx(grid.elevation[cell], 3.0 + change), "Press edits immediately, mode %d" % mode)
		main._update_held_terrain_edit(0.14)
		verify(is_equal_approx(grid.elevation[cell], 3.0 + change), "Hold waits for repeat interval")
		main._update_held_terrain_edit(0.02)
		verify(is_equal_approx(grid.elevation[cell], 3.0 + change * 2), "Hold edits the same cell again")
		main._update_held_terrain_edit(1.0)
		verify(is_equal_approx(grid.elevation[cell], 3.0 + change * 3), "Slow frame does not create an edit burst")
		var next_point := point_for(42, 32)
		move_pointer(next_point, true)
		verify(is_equal_approx(grid.elevation[next_cell], 3.0 + change), "Dragging edits the newly entered cell")
		left_button(next_point, false)
		var after_release := grid.elevation[next_cell]
		main._update_held_terrain_edit(0.5)
		verify(grid.elevation[next_cell] == after_release and not main.terrain_edit_active, "Release stops repeated editing")
		next_point = point_for(42, 32)
		move_pointer(next_point, false)
		left_button(next_point, true)
		for tick in 100:
			main._update_held_terrain_edit(0.15)
		verify(grid.elevation[next_cell] == (FixedMap.MAX_EDIT_HEIGHT if mode == 1 else -4.0), "Terrain height stays within limits")
		left_button(Vector2(100, 100), false)
		verify(not main.terrain_edit_active, "Release over UI stops editing")
		point = point_for(38, 32)
		move_pointer(point, false)
		left_button(point, true)
		move_pointer(Vector2(100, 100), true)
		await process_frame
		var before_ui := grid.elevation[cell]
		main._update_held_terrain_edit(0.5)
		verify(grid.elevation[cell] == before_ui and not main.terrain_edit_active, "UI blocks repeated editing")
		left_button(Vector2(100, 100), false)
		point = point_for(38, 32)
		move_pointer(point, false)
		left_button(point, true)
		main.get_window().focus_exited.emit()
		verify(not main.terrain_edit_active, "Losing focus cancels the edit stroke")
		left_button(point, false)
		move_pointer(point_for(38, 32), false)
		left_button(point_for(38, 32), true)
		main.hud.tool_requested.emit(0)
		verify(not main.terrain_edit_active, "Changing tools cancels the edit stroke")
		left_button(point_for(38, 32), false)
		main.hud.tool_requested.emit(mode)
		main._toggle()
		var before_running := grid.elevation[cell]
		move_pointer(point_for(38, 32), false)
		left_button(point_for(38, 32), true)
		main._update_held_terrain_edit(0.5)
		verify(grid.elevation[cell] == before_running and not main.terrain_edit_active, "Terrain remains locked while simulation runs")
		left_button(point_for(38, 32), false)
		main._toggle()
	print("TERRAIN_INPUT_CHECKS: %d, FAILURES: %d" % [checks, failures])
	quit(1 if failures else 0)
