class_name GameSession
extends RefCounted

enum Phase { PREPARE, RAIN, REPORT, GAME_OVER }
const PREPARE_SECONDS := 180.0
const RAIN_SECONDS := 60.0
const TURNS_PER_YEAR := 8
const EDIT_COST := 10
var grid: GridState
var solver: WaterSimulator
var development: DevelopmentSystem
var terrain_seed: int
var scenario_seed: int
var rng := RandomNumberGenerator.new()
var phase := Phase.PREPARE
var phase_seconds := 0.0
var elapsed := 0.0
var turn := 0
var power := 1000
var paused := false
var speed := 1
var transition_pending := true
var ever_settled := false
var weather := 0
var weather_multiplier := 1.0
var last_report := {}
# Extension points for future tutorial / historical report screens.
var event_log: Array[Dictionary] = []
var tutorial_state := {}
var notification := ""

func _init(state: GridState, ground_seed: int, event_seed: int) -> void:
	grid = state
	terrain_seed = ground_seed
	scenario_seed = event_seed
	rng.seed = scenario_seed
	development = DevelopmentSystem.new(grid.water.size())
	_create_solver()

func _create_solver() -> void:
	solver = WaterSimulator.new(grid)
	solver.inlets = grid.source_cells
	solver.measure_discharge = true

func inflow_rate() -> float:
	return GameUnits.BASE_INFLOW * (weather_multiplier if phase == Phase.RAIN else 1.0)

func global_rain_rate() -> float:
	return (0.0015 if weather < 2 else 0.0045) if phase == Phase.RAIN and weather % 2 == 1 else 0.0

func weather_label() -> String:
	return ["山で雨が降っています。", "流域全体で雨が降っています。",
		"山で豪雨が降っています。", "流域全体で豪雨が降っています。"][weather] if phase == Phase.RAIN else "雨は止んでいます。"

func calendar() -> String:
	return "%d年目 · %s · %d / 2" % [turn / TURNS_PER_YEAR + 1, ["春", "夏", "秋", "冬"][(turn % 8) / 2], turn % 2 + 1]

func remaining() -> float:
	return maxf(0.0, (PREPARE_SECONDS if phase == Phase.PREPARE else RAIN_SECONDS) - phase_seconds)

func dismiss_transition() -> void:
	transition_pending = false

func can_advance() -> bool:
	return not transition_pending and not paused and phase in [Phase.PREPARE, Phase.RAIN]

func advance_ticks(count: int) -> int:
	var advanced := 0
	for tick in count:
		if not can_advance():
			break
		solver.step(global_rain_rate(), inflow_rate(), 0.001 if phase == Phase.PREPARE else 0.0001)
		development.sample(grid, WaterSimulator.FIXED_DT)
		phase_seconds += WaterSimulator.FIXED_DT
		elapsed += WaterSimulator.FIXED_DT
		advanced += 1
		if remaining() < WaterSimulator.FIXED_DT * 0.5:
			if phase == Phase.PREPARE:
				_begin_rain()
			else:
				_finish_rain()
	return advanced

func _begin_rain() -> void:
	phase = Phase.RAIN
	phase_seconds = 0.0
	paused = false
	weather = rng.randi_range(0, 3)
	weather_multiplier = rng.randf_range(2.0, 3.0) if weather < 2 else rng.randf_range(4.0, 6.0)
	development.begin_rain_window()
	transition_pending = true
	notification = ""
	_record("rain", {"weather": weather, "multiplier": weather_multiplier})

func _finish_rain() -> void:
	var reward := 0
	var lost_houses := 0
	var lost_people := 0
	var rows: Array[Dictionary] = []
	for house in development.houses:
		if house.population == 0:
			continue
		var peak := 0.0
		for cell in house.cells:
			peak = maxf(peak, grid.peak_depth[cell])
		var people: int = house.population
		var status := "無事でした。"
		if peak >= GameUnits.LOSS_DEPTH:
			lost_houses += 1
			lost_people += people
			house.population = 0
			status = "住民を失いました。"
		elif peak >= GameUnits.REWARD_DEPTH:
			status = "床上まで水が入りました。"
		else:
			reward += people * 100
		rows.append({"id": house.id, "population": people, "peak_cm": peak * 100.0, "status": status})
	var before := power
	var penalty := lost_houses * 400
	power = maxi(0, power + reward - penalty)
	last_report = {"turn": turn, "reward": reward, "penalty": penalty, "before": before,
		"power": power, "population": development.population(), "lost_people": lost_people,
		"lost_houses": lost_houses, "rows": rows, "weather": weather, "multiplier": weather_multiplier}
	phase = Phase.REPORT
	phase_seconds = 0.0
	transition_pending = false
	paused = false
	if turn + 1 >= TURNS_PER_YEAR and (power == 0 or (ever_settled and development.population() == 0)):
		phase = Phase.GAME_OVER
		last_report["reason"] = "神力が尽きました。" if power == 0 else "水害で住民をすべて失いました。"
	_record("report", last_report.duplicate(true))

func next_turn() -> void:
	if phase != Phase.REPORT:
		return
	turn += 1
	phase = Phase.PREPARE
	phase_seconds = 0.0
	paused = false
	transition_pending = true
	grid.peak_depth = grid.water.duplicate()
	development.assess_window()
	development.refresh_eligibility(grid)
	var growth := development.grow(turn)
	notification = "%d人が家族に加わりました。" % growth if growth > 0 else ""
	if turn >= TURNS_PER_YEAR and turn % 4 == 0:
		var house := development.settle(grid, rng, turn)
		if not house.is_empty():
			ever_settled = true
			notification += ("\n" if not notification.is_empty() else "") + "1人が移住し、家を建てました。"
			_record("settlement", {"house_id": house.id, "anchor": house.anchor})
		else:
			notification += ("\n" if not notification.is_empty() else "") + "移住できる土地が見つかりませんでした。"

func edit_terrain(cell: int, direction: int) -> bool:
	if phase != Phase.PREPARE or transition_pending or power < EDIT_COST or cell < 0 or cell >= grid.water.size() or grid.sea[cell] or direction not in [-1, 1]:
		return false
	var x := cell % grid.width
	var y := cell / grid.width
	# A compact, smooth brush: center ±100 cm, neighbours taper to zero.
	for yy in range(maxi(0, y - 3), mini(grid.height, y + 4)):
		for xx in range(maxi(0, x - 3), mini(grid.width, x + 4)):
			var distance := Vector2(xx - x, yy - y).length()
			if distance >= 3.0:
				continue
			var i := grid.index(xx, yy)
			if not grid.sea[i]:
				var t := distance / 3.0
				var weight := 1.0 - t * t * (3.0 - 2.0 * t)
				grid.elevation[i] += direction * weight
	power -= EDIT_COST
	development.refresh_eligibility(grid)
	return true

func _record(kind: String, data: Dictionary) -> void:
	event_log.append({"kind": kind, "turn": turn, "seconds": elapsed, "data": data})

func to_data() -> Dictionary:
	return {"version": 1, "terrain_seed": terrain_seed, "scenario_seed": scenario_seed,
		"rng_state": rng.state, "phase": phase, "phase_seconds": phase_seconds, "elapsed": elapsed,
		"turn": turn, "power": power, "paused": paused, "speed": speed,
		"transition_pending": transition_pending, "ever_settled": ever_settled,
		"weather": weather, "weather_multiplier": weather_multiplier, "last_report": last_report,
		"notification": notification, "event_log": event_log, "tutorial_state": tutorial_state,
		"grid": {"width": grid.width, "height": grid.height, "elevation": grid.elevation,
			"water": grid.water, "peak_depth": grid.peak_depth, "river": grid.river,
			"sea": grid.sea, "lake": grid.lake, "source_cells": grid.source_cells,
			"initial_water": grid.initial_water, "flow": grid.flow, "origin_mask": grid.origin_mask,
			"discharge": grid.discharge}, "development": development.to_data(),
		"ledger": {"initial_water": solver.initial_water, "rain_added": solver.rain_added,
			"inflow_added": solver.inflow_added, "drained": solver.drained, "evaporated": solver.evaporated}}

static func from_data(data: Dictionary) -> GameSession:
	var gd: Dictionary = data.grid
	var state := GridState.new(gd.width, gd.height)
	for key in ["elevation", "water", "peak_depth", "river", "sea", "lake", "source_cells", "initial_water", "flow", "origin_mask", "discharge"]:
		state.set(key, gd[key])
	var result := GameSession.new(state, data.terrain_seed, data.scenario_seed)
	for key in ["phase", "phase_seconds", "elapsed", "turn", "power", "paused", "speed", "transition_pending", "ever_settled", "weather", "weather_multiplier", "last_report", "notification", "tutorial_state"]:
		result.set(key, data[key])
	result.event_log.assign(data.event_log)
	result.rng.state = data.rng_state
	result.development.restore(data.development)
	result.development.refresh_eligibility(result.grid)
	for key in data.ledger:
		result.solver.set(key, data.ledger[key])
	return result
