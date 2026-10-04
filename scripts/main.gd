extends Node2D

const Experiment = preload("res://scripts/sim/rain_experiment.gd")
const Solver = preload("res://scripts/sim/water_simulator.gd")
const TERRAIN_EDIT_INTERVAL := 0.15
@onready var view: WorldView = $WorldView
@onready var camera: Camera2D = $Camera2D
@onready var hud: DebugHUD = $DebugHUD
@onready var rain: RainEffect = $RainLayer/RainParticles
var experiment: RainExperiment
var accumulator := 0.0
var simulation_thread := Thread.new()
var tool_mode := 0
var hover_dirty := true
var pointer_inside := true
var pointer_position := Vector2.ZERO
var terrain_edit_active := false
var edit_cell := -1
var edit_repeat_remaining := 0.0

func _ready() -> void:
	pointer_position = get_viewport().get_mouse_position()
	get_viewport().mouse_entered.connect(_pointer_entered)
	get_viewport().mouse_exited.connect(_pointer_exited)
	get_window().focus_exited.connect(_stop_terrain_edit)
	hud.water_reset_requested.connect(_reset_water)
	hud.terrain_reset_requested.connect(_reset_terrain)
	hud.weather_requested.connect(_set_weather)
	hud.toggle_requested.connect(_toggle)
	hud.step_requested.connect(_single_step)
	hud.home_requested.connect(_home)
	hud.tool_requested.connect(_set_tool_mode)
	_create_experiment()
	_home()

func _create_experiment() -> void:
	_finish_tick(true)
	experiment = Experiment.new()
	rain.reset_weather()
	view.grid = experiment.grid
	view.selected = -1
	view.set_hovered(-1)
	accumulator = 0.0
	_refresh()

func _reset_water() -> void:
	_stop_terrain_edit()
	_finish_tick(true)
	experiment.reset_water()
	_refresh()

func _reset_terrain() -> void:
	_stop_terrain_edit()
	_create_experiment()

func _set_weather(value: int) -> void:
	_stop_terrain_edit()
	_finish_tick(true)
	experiment.set_weather(value)
	_refresh()

func _home() -> void:
	var size := get_viewport_rect().size
	var map_width := (experiment.grid.width + experiment.grid.height) * WorldView.HALF_W
	var map_height := (experiment.grid.width + experiment.grid.height) * WorldView.HALF_H + 340.0
	var zoom_level := minf((size.x - 370.0) / map_width, (size.y - 90.0) / map_height)
	camera.zoom = Vector2.ONE * maxf(0.08, zoom_level)
	camera.position = Vector2(-175.0 / camera.zoom.x, map_height * 0.5 - 220.0)
	view.queue_redraw()
	hover_dirty = true

func _finish_tick(wait: bool = false) -> bool:
	if not simulation_thread.is_started():
		return false
	if simulation_thread.is_alive() and not wait:
		return false
	experiment.step_ms = simulation_thread.wait_to_finish()
	experiment.publish_step()
	return true

func _exit_tree() -> void:
	if simulation_thread.is_started():
		simulation_thread.wait_to_finish()

func _process(delta: float) -> void:
	var changed := _finish_tick()
	if experiment.running:
		accumulator = minf(accumulator + delta, 0.2)
		if accumulator >= Solver.FIXED_DT and not simulation_thread.is_started():
			accumulator -= Solver.FIXED_DT
			experiment.prepare_step()
			simulation_thread.start(experiment.advance_water)
	if changed:
		_refresh()
	_update_held_terrain_edit(delta)
	if hover_dirty:
		_update_hover()
func _set_tool_mode(mode: int) -> void:
	_stop_terrain_edit()
	tool_mode = mode

func _stop_terrain_edit() -> void:
	terrain_edit_active = false
	edit_cell = -1
	edit_repeat_remaining = 0.0

func _edit_terrain(cell: int, change: float) -> void:
	if cell < 0 or experiment.running or experiment.grid.sea[cell]:
		return
	view.selected = cell
	experiment.grid.elevation[cell] = clampf(experiment.grid.elevation[cell] + change, -4.0, FixedMap.MAX_EDIT_HEIGHT)
	view.invalidate_terrain()
	_refresh()

func _update_held_terrain_edit(delta: float) -> void:
	if not terrain_edit_active:
		return
	if experiment.running or tool_mode == 0 or not pointer_inside:
		_stop_terrain_edit()
		return
	if not get_viewport_rect().has_point(pointer_position) or get_viewport().gui_get_hovered_control() != null:
		_stop_terrain_edit()
		return
	edit_repeat_remaining -= delta
	if edit_repeat_remaining <= 0.0 and edit_cell >= 0:
		# Repeat on the pressed cell until the pointer moves, even as its height changes.
		# Do not catch up missed repeats in a burst after a slow frame.
		edit_repeat_remaining = TERRAIN_EDIT_INTERVAL
		_edit_terrain(edit_cell, 0.5 if tool_mode == 1 else -0.5)

func _input(event: InputEvent) -> void:
	# Observe motion even when UI controls consume the event.
	if event is InputEventMouse:
		pointer_position = event.position
		hover_dirty = true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_stop_terrain_edit()
	if event is InputEventMouseMotion and not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_stop_terrain_edit()

func _pointer_entered() -> void:
	pointer_inside = true
	pointer_position = get_viewport().get_mouse_position()
	hover_dirty = true

func _pointer_exited() -> void:
	_stop_terrain_edit()
	pointer_inside = false
	view.set_hovered(-1)

func _update_hover() -> void:
	hover_dirty = false
	if not pointer_inside or not get_viewport_rect().has_point(pointer_position):
		view.set_hovered(-1)
		return
	if get_viewport().gui_get_hovered_control() != null:
		view.set_hovered(-1)
		return
	view.set_hovered(_cell_at_position(pointer_position))

func _cell_at_position(screen_position: Vector2) -> int:
	camera.force_update_scroll()
	return view.pick(view.get_global_transform_with_canvas().affine_inverse() * screen_position)

func _toggle() -> void:
	_stop_terrain_edit()
	_finish_tick(true)
	experiment.running = not experiment.running
	accumulator = 0.0
	_refresh()

func _single_step() -> void:
	if not experiment.running:
		experiment.tick()
		_refresh()

func _refresh() -> void:
	view.invalidate_state()
	view.update_highlights()
	hover_dirty = true
	rain.update_weather(experiment.is_raining(), experiment.running, experiment.heavy)
	hud.update_state(experiment, view.selected)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_toggle()
	if event is InputEventMouseMotion:
		if event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			_stop_terrain_edit()
			camera.position -= event.relative / camera.zoom
		elif terrain_edit_active and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			var cell := _cell_at_position(event.position)
			if cell != edit_cell:
				edit_cell = cell
				edit_repeat_remaining = TERRAIN_EDIT_INTERVAL
				_edit_terrain(edit_cell, 0.5 if tool_mode == 1 else -0.5)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = Vector2.ONE * minf(2.5, camera.zoom.x * 1.12)
			view.queue_redraw()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = Vector2.ONE * maxf(0.08, camera.zoom.x / 1.12)
			view.queue_redraw()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			view.selected = _cell_at_position(event.position)
			if view.selected >= 0 and tool_mode != 0 and not experiment.running and not experiment.grid.sea[view.selected]:
				terrain_edit_active = true
				edit_cell = view.selected
				edit_repeat_remaining = TERRAIN_EDIT_INTERVAL
				_edit_terrain(view.selected, 0.5 if tool_mode == 1 else -0.5)
			else:
				_refresh()
