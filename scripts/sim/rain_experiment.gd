class_name RainExperiment
extends RefCounted

const Map = preload("res://scripts/model/fixed_map.gd")
const Solver = preload("res://scripts/sim/water_simulator.gd")
enum Weather { SUNNY, NORMAL, HEAVY }

# The display reads this snapshot; the worker owns solver.grid independently.
var grid: GridState
var solver: WaterSimulator
var elapsed := 0.0
var rain_elapsed := 0.0
var weather := Weather.HEAVY
var heavy: bool:
	get:
		return weather == Weather.HEAVY
var running := false
var step_ms := 0.0
var summary := {}
var _step_raining := false
var _step_heavy := false

func _init(is_heavy: bool = true, _is_reinforced: bool = false) -> void:
	weather = Weather.HEAVY if is_heavy else Weather.NORMAL
	grid = Map.create()
	_create_solver()

func _create_solver() -> void:
	solver = Solver.new(grid.simulation_copy())
	solver.inlets = Map.inlet_cells(grid)
	update_summary()

func set_weather(value: int) -> void:
	if value < Weather.SUNNY or value > Weather.HEAVY or value == weather:
		return
	if weather == Weather.SUNNY or value == Weather.SUNNY:
		rain_elapsed = 0.0
	weather = value

func reset_water() -> void:
	grid.water = grid.initial_water.duplicate()
	grid.peak_depth = grid.water.duplicate()
	grid.flow.fill(Vector2.ZERO)
	_create_solver()

func prepare_step() -> void:
	solver.grid.elevation = grid.elevation
	_step_raining = is_raining()
	_step_heavy = heavy

func advance_water() -> float:
	var start := Time.get_ticks_usec()
	var rain := (0.012 if _step_heavy else 0.003) if _step_raining else 0.0
	solver.step(rain, Map.INFLOW_PER_CELL * solver.inlets.size(), 0.0005 if _step_raining else 0.006)
	return (Time.get_ticks_usec() - start) / 1000.0

func publish_step() -> void:
	grid.water = solver.grid.water
	grid.flow = solver.grid.flow
	grid.peak_depth = solver.grid.peak_depth
	elapsed += Solver.FIXED_DT
	if _step_raining:
		rain_elapsed += Solver.FIXED_DT
	update_summary()

func tick() -> void:
	prepare_step()
	step_ms = advance_water()
	publish_step()

func update_summary() -> void:
	var volume := grid.total_water()
	summary = {"water": volume, "inundated_now": grid.inundated_cells(),
		"inundated_peak": grid.inundated_cells(true),
		"balance_error": volume - (solver.initial_water + solver.rain_added + solver.inflow_added - solver.drained - solver.evaporated),
		"rain": solver.rain_added, "inflow": solver.inflow_added,
		"drained": solver.drained, "evaporated": solver.evaporated,
		"drain_rate": solver.last_drained / Solver.FIXED_DT}

func is_raining() -> bool:
	return weather != Weather.SUNNY

func weather_label() -> String:
	return ["晴れ", "通常", "豪雨"][weather]

func phase_label() -> String:
	return "降雨" if is_raining() else "流下・蒸発"

func metrics() -> Dictionary:
	var result := summary.duplicate()
	result["weather"] = weather_label()
	result["seconds"] = elapsed
	return result
