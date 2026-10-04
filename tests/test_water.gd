extends SceneTree

const Grid = preload("res://scripts/model/grid_state.gd")
const Solver = preload("res://scripts/sim/water_simulator.gd")
const Experiment = preload("res://scripts/sim/rain_experiment.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	_test_closed_system()
	_test_static_surface()
	_test_barrier()
	_test_budget_and_drying()
	_test_constant_boundaries()
	_test_flow_response()
	_test_steady_channel()
	_test_settling()
	_test_sea()
	_test_constant_rain_stability()
	_test_basin_map()
	_test_weather_switching()
	_test_water_reset()
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _test_closed_system() -> void:
	var grid := Grid.new(8, 8)
	for i in grid.water.size():
		grid.elevation[i] = float((i * 13) % 7) * 0.3
	grid.water[27] = 19.0
	var sim := Solver.new(grid)
	for tick in 400:
		sim.step()
	check(absf(grid.total_water() - 19.0) < 1e-8, "Closed basin must conserve volume")
	check(absf(sim.balance_error()) < 1e-8, "Closed basin budget")
	var non_negative := true
	for amount in grid.water:
		non_negative = non_negative and amount >= 0.0 and is_finite(amount)
	check(non_negative, "No negative or non-finite water")

func _test_static_surface() -> void:
	var grid := Grid.new(3, 1)
	grid.elevation = PackedFloat64Array([0.0, 1.0, 2.0])
	grid.water = PackedFloat64Array([3.0, 2.0, 1.0])
	var sim := Solver.new(grid)
	for tick in 40:
		sim.step()
	check(grid.water == PackedFloat64Array([3.0, 2.0, 1.0]), "Equal surfaces must remain still")

func _test_barrier() -> void:
	var grid := Grid.new(3, 1)
	grid.elevation = PackedFloat64Array([0.0, 2.0, 0.0])
	grid.water[0] = 1.0
	var sim := Solver.new(grid)
	for tick in 100:
		sim.step()
	check(grid.water[1] == 0.0 and grid.water[2] == 0.0, "No flow through a dry crest")
	grid.water[0] += 3.0
	for tick in 100:
		sim.step()
	check(grid.water[2] > 0.5, "Water above crest must reach the far side")
	check(absf(grid.total_water() - 4.0) < 1e-8, "Overtopping conserves water")

func _test_budget_and_drying() -> void:
	var grid := Grid.new(4, 4)
	var sim := Solver.new(grid)
	sim.inlets = PackedInt32Array([0])
	sim.outlets = PackedInt32Array([15])
	for tick in 200:
		sim.step(0.1, 0.7, 0.02)
	check(absf(sim.rain_added - 16.0) < 1e-8, "Uniform rainfall amount")
	check(absf(sim.inflow_added - 7.0) < 1e-8, "External inlet amount")
	check(sim.drained > 0.0 and sim.evaporated > 0.0, "Drain and evaporation are active")
	check(absf(sim.balance_error()) < 1e-8, "Open system budget")
	var dry_grid := Grid.new(1, 1)
	dry_grid.water[0] = 0.001
	var drying := Solver.new(dry_grid)
	drying.step(0.0, 0.0, 1.0)
	check(dry_grid.water[0] == 0.0, "Evaporation clamps to available water")
	check(absf(drying.evaporated - 0.001) < 1e-10, "Evaporation records actual amount")
	drying.step(0.0, 0.0, 1.0)
	check(absf(drying.balance_error()) < 1e-10, "Already dry cells do not lose water")
	var boundary_grid := Grid.new(1, 1)
	boundary_grid.water[0] = 0.01
	var boundary := Solver.new(boundary_grid)
	boundary.outlets = PackedInt32Array([0])
	boundary.step()
	check(boundary_grid.water[0] >= 0.0 and absf(boundary.balance_error()) < 1e-10,
		"Boundary drainage cannot remove too much")

func _test_weather_switching() -> void:
	var experiment := Experiment.new()
	for tick in 30:
		experiment.tick()
	experiment.grid.elevation[experiment.grid.index(38, 32)] += 1.0
	experiment.running = true
	var elevations := experiment.grid.elevation.duplicate()
	var water := experiment.grid.water.duplicate()
	var peaks := experiment.grid.peak_depth.duplicate()
	var solver := experiment.solver
	var elapsed := experiment.elapsed
	var ledger := [solver.initial_water, solver.rain_added, solver.inflow_added, solver.drained, solver.evaporated]
	for weather in [Experiment.Weather.SUNNY, Experiment.Weather.NORMAL, Experiment.Weather.HEAVY]:
		experiment.set_weather(weather)
		check(experiment.grid.elevation == elevations and experiment.grid.water == water,
			"Weather changes preserve every terrain and water cell")
		check(experiment.solver == solver and ledger == [solver.initial_water, solver.rain_added, solver.inflow_added, solver.drained, solver.evaporated],
			"Weather changes preserve the solver and water ledger")
		check(experiment.elapsed == elapsed and experiment.running and experiment.grid.peak_depth == peaks,
			"Weather changes preserve time, playback and peak water history")
	experiment.set_weather(Experiment.Weather.SUNNY)
	var old_rain := solver.rain_added
	var old_inflow := solver.inflow_added
	var old_evaporation := solver.evaporated
	var old_total := experiment.grid.total_water()
	experiment.tick()
	check(solver.rain_added == old_rain and absf(solver.inflow_added - old_inflow - FixedMap.INFLOW_PER_CELL * solver.inlets.size() * Solver.FIXED_DT) < 1e-10, "Sun stops rain while the constant inlet stays active")
	check(solver.evaporated > old_evaporation and experiment.grid.total_water() < old_total, "Sun continues evaporation and drainage")
	experiment.set_weather(Experiment.Weather.NORMAL)
	experiment.tick()
	var normal_rain := solver.rain_added - old_rain
	old_rain = solver.rain_added
	experiment.set_weather(Experiment.Weather.HEAVY)
	experiment.tick()
	check(absf((solver.rain_added - old_rain) / normal_rain - 4.0) < 1e-8, "Heavy rain immediately uses four times the normal rate")
	experiment.elapsed = 31.0
	experiment.tick()
	check(experiment.is_raining() and experiment.running, "Weather persists beyond the former automatic stop time")
	check(absf(solver.balance_error()) < 1e-6, "Mixed weather retains the water budget")

func _test_water_reset() -> void:
	var experiment := Experiment.new(false, true)
	for tick in 30:
		experiment.tick()
	experiment.grid.elevation[experiment.grid.index(38, 32)] += 2.0
	experiment.running = true
	var elevations := experiment.grid.elevation.duplicate()
	var elapsed := experiment.elapsed
	var rain_elapsed := experiment.rain_elapsed
	var weather := experiment.weather
	experiment.reset_water()
	check(experiment.grid.elevation == elevations, "Water reset preserves edited terrain")
	check(experiment.grid.water == Experiment.Map.create().water, "Water reset restores initial river water")
	check(experiment.grid.peak_depth == experiment.grid.water and experiment.summary.drained == 0.0,
		"Water reset clears water measurements")
	check(experiment.elapsed == elapsed and experiment.rain_elapsed == rain_elapsed and experiment.weather == weather and experiment.running,
		"Water reset preserves time, weather and playback")
	check(experiment.solver.rain_added == 0.0 and experiment.solver.inflow_added == 0.0 and absf(experiment.solver.balance_error()) < 1e-8,
		"Water reset starts a balanced new ledger")
	experiment.tick()
	check(absf(experiment.solver.balance_error()) < 1e-6, "Water simulation continues after water reset")
func _test_constant_boundaries() -> void:
	var source_grid := Grid.new(4, 1)
	var source := Solver.new(source_grid)
	source.inlets = PackedInt32Array([0, 1, 2, 3])
	for tick in 20:
		source.step(0.0, 4.8, 0.0)
	var uniform := true
	for amount in source_grid.water:
		uniform = uniform and absf(amount - 1.2) < 1e-10
	check(uniform and absf(source.balance_error()) < 1e-10,
		"Constant inlet volume is spread evenly across the river width")
	for height in [-100.0, 100.0]:
		var drain_grid := Grid.new(1, 1)
		drain_grid.elevation[0] = height
		drain_grid.water[0] = 10.0
		var drain := Solver.new(drain_grid)
		drain.outlets = PackedInt32Array([0])
		for tick in 20:
			drain.step()
		check(absf(drain.drained - 1.2) < 1e-10 and absf(drain_grid.water[0] - 8.8) < 1e-10,
			"Drain removes a fixed amount independent of ground or water-surface elevation")
		check(absf(drain.last_drained - 0.06) < 1e-10 and absf(drain.balance_error()) < 1e-10,
			"Drain records its actual tick volume and conserves the ledger")
	var dry_grid := Grid.new(1, 1)
	dry_grid.water[0] = 0.01
	var sink := Solver.new(dry_grid)
	sink.outlets = PackedInt32Array([0])
	sink.step()
	check(dry_grid.water[0] == 0.0 and sink.last_drained == 0.01,
		"An undersupplied drain removes only the remaining water")
	sink.step()
	check(sink.last_drained == 0.0 and absf(sink.drained - 0.01) < 1e-10,
		"A dry drain stays active without creating negative water")
func _test_flow_response() -> void:
	var transfers: Array[float] = []
	for difference in [1.0, 2.0]:
		var grid := Grid.new(2, 1)
		grid.water = PackedFloat64Array([2.0 + difference, 2.0])
		var solver := Solver.new(grid)
		solver.step()
		transfers.append(solver.east[0])
		var remaining_difference: float = difference * exp(-2.0 * Solver.CONDUCTIVITY * Solver.FIXED_DT)
		check(absf(grid.water[0] - grid.water[1] - remaining_difference) < 1e-10,
			"Two wet cells relax according to the water-surface difference")
		check(grid.water[0] > grid.water[1] and absf(solver.balance_error()) < 1e-10,
			"Faster flow approaches equal levels without reversing the gradient or losing water")
	check(absf(transfers[1] - 2.0 * transfers[0]) < 1e-10,
		"Twice the surface difference causes twice the transfer when water is available")
	var checker := Grid.new(5, 5)
	for y in 5:
		for x in 5:
			checker.water[checker.index(x, y)] = float((x + y) % 2)
	var solver := Solver.new(checker)
	for tick in 100:
		solver.step()
	var min_depth := 1.0
	var max_depth := 0.0
	for depth in checker.water:
		min_depth = minf(min_depth, depth)
		max_depth = maxf(max_depth, depth)
	check(min_depth >= 0.0 and max_depth <= 1.0 and max_depth - min_depth < 1e-6,
		"Fast two-dimensional flow smooths alternating peaks instead of oscillating")

func _test_steady_channel() -> void:
	var grid := Grid.new(1, 64)
	var rate := 1.2
	for y in 64:
		grid.water[y] = 2.0 + (63 - y) * 0.08
	var solver := Solver.new(grid)
	solver.inlets = PackedInt32Array([0])
	solver.outlets = PackedInt32Array([63])
	var edge_totals := PackedFloat64Array()
	edge_totals.resize(63)
	for tick in 6000:
		solver.step(0.0, rate, 0.0)
		if tick >= 5000:
			for y in 63:
				edge_totals[y] += solver.south[y]
	var error := 0.0
	for amount in edge_totals:
		error = maxf(error, absf(amount / (1000.0 * Solver.FIXED_DT) - rate))
	check(error < 0.005, "A long channel carries the complete 1.2 per second through every edge")
	check(absf(solver.drained - solver.inflow_added) < 1e-7, "Matched source and drain retain the total water")
	check(grid.water[0] < 10.0 and absf(solver.balance_error()) < 1e-7, "Continuous input does not accumulate indefinitely upstream")

func _test_settling() -> void:
	var grid := Grid.new(5, 5)
	grid.water[grid.index(2, 2)] = 3.0
	var sim := Solver.new(grid)
	for tick in 200:
		sim.step()
	var max_error := 0.0
	for depth in grid.water:
		max_error = maxf(max_error, absf(depth - 3.0 / 25.0))
	check(max_error < 1e-10, "A closed flat basin converges to a level surface without a preferred axis")

func _test_sea() -> void:
	var grid := Grid.new(2, 1)
	grid.elevation = PackedFloat64Array([1.0, -5.0])
	grid.water[0] = 2.0
	grid.sea[1] = 1
	var solver := Solver.new(grid)
	for tick in 40:
		solver.step(0.1, 0.0, 0.02)
	check(solver.drained > 1.0, "Inland water flows out through the coast")
	check(grid.water[1] == 0.0 and grid.visible_depth(1) == 5.0 and grid.surface(1) == 0.0,
		"Sea drainage keeps the visible water level and depth fixed")
	check(absf(solver.rain_added - 0.2) < 1e-10, "Sea rain is excluded from the land water ledger")
	check(absf(solver.balance_error()) < 1e-9, "All water absorbed by the sea is recorded as drainage")
	grid = Grid.new(2, 1)
	grid.elevation = PackedFloat64Array([-2.0, -5.0])
	grid.sea[1] = 1
	solver = Solver.new(grid)
	for tick in 20:
		solver.step()
	check(grid.total_water() == 0.0, "The visual ocean cannot fill excavated land by reverse flow")
	check(grid.inundated_cells() == 0 and grid.inundated_cells(true) == 0,
		"The sea is excluded from flood counts")
	grid = Grid.new(1, 1)
	grid.elevation[0] = -3.0
	grid.sea[0] = 1
	solver = Solver.new(grid)
	for tick in 10:
		solver.step(100.0, 0.0, 100.0)
	check(grid.visible_depth(0) == 3.0 and solver.rain_added == 0.0 and solver.evaporated == 0.0,
		"Neither heavy rain nor evaporation changes the visual sea reservoir")

func _test_basin_map() -> void:
	var grid := FixedMap.create()
	check(grid.width == 256 and grid.height == 256, "The map contains 256 by 256 editable or sea cells")
	var duplicate := FixedMap.create()
	check(grid.elevation == duplicate.elevation and grid.water == duplicate.water and grid.sea == duplicate.sea,
		"The basin is deterministic")
	check(grid.source_cells.size() == 15, "Three tributary inlets span five cells each")
	var placement_valid := true
	for i in grid.source_cells:
		placement_valid = placement_valid and i < grid.width and grid.river[i] == 1 and not grid.sea[i]
	check(placement_valid, "All sources occupy the upstream edge of a river")
	var lake_cells := 0
	var mountain_cells := 0
	var sea_cells := 0
	var level_lake := true
	for i in grid.water.size():
		if grid.lake[i]:
			lake_cells += 1
			level_lake = level_lake and absf(grid.surface(i) - FixedMap.LAKE_LEVEL) < 1e-10
		if grid.elevation[i] > 20.0:
			mountain_cells += 1
		if grid.sea[i]:
			sea_cells += 1
	check(lake_cells > 2000 and level_lake, "The shared lake begins with a flat continuous water surface")
	check(mountain_cells > 1000, "Mountains rise above the upstream river valleys")
	check(sea_cells > 7000, "A broad coastal sea occupies the downstream side")
	check(absf(FixedMap.main_river_x(152) - FixedMap.main_river_x(199)) > 40.0,
		"The main river has substantial opposing bends")
	# Walk backwards from the sea through non-rising downstream river surfaces.
	var reachable := PackedByteArray()
	reachable.resize(grid.water.size())
	var queue := FixedMap.outlet_cells(grid)
	for cell in queue:
		reachable[cell] = 1
	var position := 0
	while position < queue.size():
		var cell := queue[position]
		position += 1
		for delta in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var x: int = cell % grid.width + delta.x
			var y: int = cell / grid.width + delta.y
			if x < 0 or x >= grid.width or y < 0 or y >= grid.height:
				continue
			var other := grid.index(x,y)
			if not reachable[other] and grid.river[other] and grid.surface(other) >= grid.surface(cell) - 1e-9:
				reachable[other] = 1
				queue.append(other)
	var connected := true
	for cell in grid.source_cells:
		connected = connected and reachable[cell] == 1
	check(connected and reachable[grid.index(124,110)], "Every tributary and the lake connect downhill to the sea")
	var experiment := Experiment.new()
	for weather in [Experiment.Weather.SUNNY, Experiment.Weather.NORMAL, Experiment.Weather.HEAVY]:
		experiment.set_weather(weather)
		var before := experiment.solver.inflow_added
		for tick in 20:
			experiment.tick()
		check(absf(experiment.solver.inflow_added - before - 18.0) < 1e-8,
			"All weather settings retain the total inlet rate of 18 per second")
	for tick in 140:
		experiment.tick()
	check(experiment.solver.drained > 0.0, "The complete basin drains to the sea while rain continues")
	check(absf(experiment.solver.balance_error()) < 1e-6, "The full basin water ledger balances")
	var valid_water := true
	for i in grid.water.size():
		var depth := experiment.grid.water[i]
		valid_water = valid_water and is_finite(depth) and depth >= 0.0
		if grid.sea[i]:
			valid_water = valid_water and depth == 0.0 and experiment.grid.surface(i) == 0.0
	check(valid_water, "All basin water remains finite and nonnegative and sea storage stays empty")
	experiment.reset_water()
	check(experiment.solver.inlets == grid.source_cells and experiment.grid.water == grid.initial_water,
		"Reset restores the initial lake and river water and every inlet")
func _test_constant_rain_stability() -> void:
	var grid := Grid.new(32, 32)
	for y in grid.height:
		for x in grid.width:
			var i := grid.index(x,y)
			grid.elevation[i] = (31-y) * 0.15 + (31-x) * 0.05
			if y == 31:
				grid.sea[i] = 1
				grid.elevation[i] = -1.0
	var solver := Solver.new(grid)
	for tick in 180:
		solver.step(0.012, 0.0, 0.0005)
	var previous := grid.water.duplicate()
	var max_change := 0.0
	for tick in 20:
		solver.step(0.012, 0.0, 0.0005)
		for i in grid.water.size():
			max_change = maxf(max_change, absf(grid.water[i] - previous[i]))
		previous = grid.water.duplicate()
	check(max_change < 1e-8, "Steady rain on a slope must not alternate wet and dry cells every tick")
	check(absf(solver.balance_error()) < 1e-8, "Stable slope runoff preserves the water ledger")