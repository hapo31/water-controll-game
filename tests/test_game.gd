extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func verify(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func flat_grid() -> GridState:
	var grid := GridState.new(64, 64)
	grid.elevation.fill(2.0)
	grid.source_cells = PackedInt32Array([grid.index(10, 4), grid.index(30, 4), grid.index(50, 4)])
	grid.initial_water = grid.water.duplicate()
	return grid

func session() -> GameSession:
	return GameSession.new(flat_grid(), 42, 73)

func house(state: GameSession, x: int, population: int, peak: float) -> void:
	var cells := PackedInt32Array()
	for y in range(20, 24):
		for xx in range(x, x + 3):
			var cell := state.grid.index(xx, y)
			cells.append(cell)
			state.grid.peak_depth[cell] = peak
	state.development.houses.append({"id": x, "anchor": cells[0], "cells": cells, "population": population, "built_turn": 8, "growth_turn": 8})

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://work/game")
	_test_phase_and_weather()
	_test_brush()
	_test_report()
	_test_development()
	_test_origins()
	_test_saves()
	var start := Time.get_ticks_msec()
	var generator := TerrainGenerator.new(20261004)
	var grid := generator.generate()
	print("GENERATION_MS: ", Time.get_ticks_msec() - start)
	verify(grid.width == 64 and grid.height == 64 and grid.source_cells.size() == 3, "Playable map size and three inlets")
	verify(generator.mountains.size() in [3, 4] and generator.traces.size() == 3, "Three river-carving passes with three or four peaks")
	var northern := true
	for peak in generator.mountains:
		northern = northern and peak.y < 5
	for cell in grid.source_cells:
		northern = northern and cell / 64 < 5
	verify(northern, "Mountain peaks and inlets occupy the northern five rows")
	var river_rows := 0
	var merged := false
	for y in 63:
		var found := false
		for x in 64:
			found = found or grid.river[grid.index(x, y)] != 0
		if found:
			river_rows += 1
	for trace in generator.traces:
		for mask in trace.origins:
			merged = merged or mask in [3, 5, 6, 7]
	verify(river_rows >= 55, "Simulation-carved channels reach the downstream region")
	verify(merged, "River tracing retains combined source provenance")
	verify(generator.status().progress == 1.0, "Generation progress reaches completion")
	var playable := GameSession.new(grid, 20261004, 9876)
	verify(SaveStore.new().write(playable, "res://work/game/generated.dat"), "Generated map available for rendered integration test")
	var regen := TerrainGenerator.new(20261004).generate()
	verify(regen.elevation == grid.elevation and regen.river == grid.river and regen.source_cells == grid.source_cells, "Same terrain seed reproduces carved terrain and initial water")
	var other := TerrainGenerator.new(20261005).generate()
	verify(other.elevation != grid.elevation and other.source_cells != grid.source_cells, "Different terrain seeds produce different terrain")
	playable.dismiss_transition()
	var simulation_start := Time.get_ticks_msec()
	playable.advance_ticks(200)
	var duration := Time.get_ticks_msec() - simulation_start
	print("GAME_TICK_MS: ", float(duration) / 200)
	verify(absf(playable.solver.balance_error()) < 1e-6, "Gameplay retains the water budget")
	var valid := true
	for value in grid.water:
		valid = valid and is_finite(value) and value >= 0.0
	verify(valid, "All generated and simulated water remains finite and nonnegative")
	print("GAME_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_phase_and_weather() -> void:
	var state := session()
	verify(state.power == 1000 and state.development.population() == 0, "Initial power and uninhabited spring")
	verify(state.advance_ticks(4) == 0, "Phase transition freezes time")
	state.dismiss_transition()
	state.phase_seconds = 179.95
	state.advance_ticks(1)
	verify(state.phase == GameSession.Phase.RAIN and state.phase_seconds == 0.0 and state.transition_pending, "Three-minute preparation enters paused rainfall transition")
	var multiplier: float = state.weather_multiplier
	verify(multiplier == (10.0 if state.weather < 2 else 40.0), "Rain uses ten times base inflow; heavy rain uses forty times")
	verify(is_equal_approx(state.inflow_rate(), GameUnits.BASE_INFLOW * multiplier), "Inflow reflects rainfall strength")
	state.dismiss_transition()
	state.phase_seconds = 59.95
	state.advance_ticks(1)
	verify(state.phase == GameSession.Phase.REPORT and not state.can_advance(), "Sixty simulation seconds lead to a paused report")
	var old_power := state.power
	state.advance_ticks(100)
	verify(state.power == old_power and state.phase_seconds == 0.0, "Report neither advances time nor awards twice")
	state.next_turn()
	verify(state.turn == 1 and state.phase == GameSession.Phase.PREPARE and state.transition_pending, "Next result click begins the next turn")
	state.turn = 7
	verify(state.calendar().contains("冬") and state.calendar().contains("2 / 2"), "Two turns per season, eight turns per year")
	for weather in range(4):
		state.phase = GameSession.Phase.RAIN
		state.weather = weather
		verify((state.global_rain_rate() > 0.0) == (weather % 2 == 1), "Mountain-only events do not rain on the entire grid")
	var seen := {}
	for n in 32:
		state._begin_rain()
		seen[state.weather] = true
		verify(state.weather_multiplier == (10.0 if state.weather < 2 else 40.0), "Weather uses the fixed multiplier for its rain strength")
	verify(seen.size() == 4, "Scenario RNG can select all four events")

func _test_brush() -> void:
	var state := session()
	state.dismiss_transition()
	var center := state.grid.index(20, 20)
	verify(state.edit_terrain(center, 1), "Brush usable while time runs")
	verify(state.grid.elevation[center] == 3.0 and state.power == 990, "One click raises the center by 100 cm for ten power")
	verify(state.grid.elevation[center + 1] > 2.0 and state.grid.elevation[center + 1] < 3.0 and state.grid.elevation[center + 3] == 2.0, "Brush tapers smoothly into nearby terrain")
	state.paused = true
	verify(state.edit_terrain(center, -1) and is_equal_approx(state.grid.elevation[center], 2.0), "Paused digging remains available")
	state.power = 9
	verify(not state.edit_terrain(center, 1) and state.power == 9, "Insufficient power never charges or edits")
	state.power = 100
	state.grid.sea[center] = 1
	verify(not state.edit_terrain(center, 1), "Sea is the downstream boundary")
	state.grid.sea[center] = 0
	state.phase = GameSession.Phase.RAIN
	verify(not state.edit_terrain(center, 1), "Rain phase locks terrain actions")

func _test_report() -> void:
	var state := session()
	state.turn = 8
	state.ever_settled = true
	house(state, 2, 4, 0.49999)
	house(state, 10, 2, 0.5)
	house(state, 20, 3, 0.9999)
	house(state, 30, 2, 1.0)
	state._finish_rain()
	verify(state.last_report.reward == 400 and state.last_report.penalty == 400 and state.power == 1000, "50 cm removes rewards; 100 cm loses a household and costs 400")
	verify(state.development.population() == 9 and state.last_report.lost_people == 2, "Lost house residents are removed while flooded survivors remain")
	verify(state.phase == GameSession.Phase.REPORT, "Survivors allow endless play")
	var extinct := session()
	extinct.turn = 8
	extinct.ever_settled = true
	house(extinct, 2, 1, 1.0)
	extinct._finish_rain()
	verify(extinct.phase == GameSession.Phase.GAME_OVER, "Flood extinction ends the game")
	var powerless := session()
	powerless.turn = 8
	powerless.power = 0
	powerless._finish_rain()
	verify(powerless.phase == GameSession.Phase.GAME_OVER, "Zero power after accounting ends the game")
	var grace := session()
	grace.power = 0
	grace._finish_rain()
	verify(grace.phase == GameSession.Phase.REPORT, "The first uninhabited year cannot end the game")
	var clamped := session()
	clamped.turn = 8
	clamped.ever_settled = true
	clamped.power = 10
	house(clamped, 2, 1, 2.0)
	clamped._finish_rain()
	verify(clamped.power == 0, "Penalty clamps power at zero")

func _test_development() -> void:
	var state := session()
	var dev := state.development
	dev.current_seconds = 300.0
	dev.current_wet.fill(300.0)
	for y in range(15, 25):
		for x in range(15, 25):
			dev.current_wet[state.grid.index(x, y)] = 44.9
	dev.assess_window()
	dev.refresh_eligibility(state.grid)
	verify(dev.patches.size() == 1, "Entire 10 by 10 patch must satisfy less than 15 percent wet time")
	var middle := state.grid.index(20, 20)
	dev.current_wet[middle] = 45.0
	dev.assess_window()
	dev.refresh_eligibility(state.grid)
	verify(dev.patches.is_empty(), "Exactly 15 percent and an interior wet hole both prevent settlement")
	dev.current_wet[middle] = 0.0
	state.grid.elevation[middle] = 2.5
	dev.assess_window()
	dev.refresh_eligibility(state.grid)
	dev.current_seconds += 180.0
	dev.refresh_eligibility(state.grid)
	verify(dev.assessed_seconds == 300.0, "Preparation edits do not dilute the completed migration observation")
	state.phase = GameSession.Phase.REPORT
	state.turn = 1
	state.next_turn()
	verify(state.turn == 2 and dev.houses.size() == 1 and dev.population() == 1 and state.ever_settled, "First household arrives after two turns")
	var built: Dictionary = dev.houses[0]
	var level := true
	for cell in built.cells:
		level = level and state.grid.elevation[cell] == state.grid.elevation[built.cells[0]]
	verify(built.cells.size() == 12 and level, "New 3 by 4 house flattens its land to the highest footprint cell")
	verify(dev.grow(9) == 0 and dev.grow(10) == 1, "Population grows after a full year, never early")
	dev.grow(18)
	dev.grow(26)
	dev.grow(34)
	verify(dev.population() == 4, "Household population stops at four")
	var growing := session()
	growing.development.current_seconds = 300.0
	growing.phase = GameSession.Phase.REPORT
	growing.next_turn()
	verify(growing.turn == 1 and growing.development.houses.is_empty(), "No residents arrive after only one spring turn")
	var restored := GameSession.from_data(growing.to_data())
	growing.phase = GameSession.Phase.REPORT
	restored.phase = GameSession.Phase.REPORT
	growing.next_turn()
	restored.next_turn()
	verify(growing.turn == 2 and growing.development.houses.size() == 1 and growing.calendar().contains("夏") and growing.calendar().contains("1 / 2"), "The first arrival starts summer turn one")
	verify(restored.development.houses == growing.development.houses and restored.rng.state == growing.rng.state, "Continuation before summer reproduces the first migration")
	for turn in range(3, 6):
		growing.phase = GameSession.Phase.REPORT
		growing.next_turn()
	verify(growing.development.houses.size() == 1, "The next migration waits four turns after the first arrival")
	growing.phase = GameSession.Phase.REPORT
	growing.next_turn()
	verify(growing.turn == 6 and growing.development.houses.size() == 2 and growing.development.population() == 2, "Further households arrive every half year")
	for turn in range(7, 10):
		growing.phase = GameSession.Phase.REPORT
		growing.next_turn()
	verify(growing.development.population() == 2, "Early arrival does not shorten annual household growth")
	growing.phase = GameSession.Phase.REPORT
	growing.next_turn()
	verify(growing.turn == 10 and growing.development.houses.size() == 3 and growing.development.population() == 4, "Annual household growth and half-year settlement combine")
	var observed := DevelopmentSystem.new(4096)
	observed.begin_rain_window()
	state.grid.water[middle] = 0.01
	observed.sample(state.grid, 60.0)
	state.grid.water[middle] = 0.0
	observed.sample(state.grid, 180.0)
	observed.begin_rain_window()
	observed.sample(state.grid, 60.0)
	verify(is_equal_approx(observed.wet_fraction(middle), 0.2) and observed.previous_seconds + observed.current_seconds == 300.0, "Rain through the next-next planning phase is a 300-second observation window")
	observed.begin_rain_window()
	verify(observed.previous_seconds == 60.0, "Old wet history expires rather than averaging across the whole game")

func _test_origins() -> void:
	var grid := GridState.new(3, 1)
	grid.water = PackedFloat64Array([1.0, 0.0, 1.0])
	var solver := WaterSimulator.new(grid)
	solver.inlets = PackedInt32Array([0, 2])
	solver.track_origins = true
	solver.measure_discharge = true
	solver.step(0.0, 0.2, 0.0)
	verify(grid.origin_mask[1] == 3, "Confluence records both inlet origins")
	verify(grid.discharge[1] > 0.0 and absf(solver.balance_error()) < 1e-10, "Discharge instrumentation preserves mass")
	verify(GameUnits.depth_cm(0.5) == 50.0 and GameUnits.flow_cm3(0.6) == 600000.0, "Water and discharge units convert consistently")

func _test_saves() -> void:
	var state := session()
	state.dismiss_transition()
	state.edit_terrain(state.grid.index(20, 20), 1)
	state.advance_ticks(3)
	state._begin_rain()
	state.dismiss_transition()
	state.advance_ticks(3)
	var store := SaveStore.new()
	var path := "res://work/game/test-save.dat"
	verify(store.write(state, path), "Save writes complete game state")
	var data := store.read(path)
	verify(not data.is_empty(), "Saved data passes integrity and schema checks")
	var restored := GameSession.from_data(data)
	verify(restored.terrain_seed == state.terrain_seed and restored.scenario_seed == state.scenario_seed and restored.rng.state == state.rng.state, "Both seeds and scenario RNG position round trip")
	verify(restored.grid.elevation == state.grid.elevation and restored.grid.water == state.grid.water and restored.phase == state.phase and restored.phase_seconds == state.phase_seconds, "Terrain, water, phase and partial clock round trip")
	state.advance_ticks(5)
	restored.advance_ticks(5)
	verify(state.grid.water == restored.grid.water and absf(restored.solver.balance_error()) < 1e-8, "Continuation produces identical water and conserved ledger")
	state._begin_rain()
	restored._begin_rain()
	verify(state.weather == restored.weather and state.weather_multiplier == restored.weather_multiplier, "Next event is identical after continuation")
	verify(store.write(restored, path), "Atomic replacement can overwrite a previous save")
	var bad := FileAccess.open(path, FileAccess.WRITE)
	bad.store_string("broken")
	bad.close()
	verify(store.read(path).is_empty() and not store.error_message.is_empty(), "Corrupted save is rejected without a crash")
