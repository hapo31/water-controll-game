extends "res://tests/test_game.gd"

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://work/game")
	_test_flatness_limits()
	_test_terrain_changes()
	_test_flatness_restore()
	_test_generated_land()
	print("SETTLEMENT_FLATNESS_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func dry_development(count: int) -> DevelopmentSystem:
	var dev := DevelopmentSystem.new(count)
	dev.current_seconds = 300.0
	dev.assess_window()
	return dev

func highlighted(dev: DevelopmentSystem) -> int:
	var count := 0
	for cell in dev.eligible:
		count += int(cell != 0)
	return count

func _test_flatness_limits() -> void:
	var grid := GridState.new(10, 10)
	grid.elevation.fill(2.0)
	var dev := dry_development(100)
	dev.refresh_eligibility(grid)
	verify(dev.patches.size() == 1 and highlighted(dev) == 100, "A dry, level 10 by 10 area is fully eligible")
	var center := grid.index(5, 5)
	grid.elevation[center] = 3.0
	dev.refresh_eligibility(grid)
	verify(dev.patches.size() == 1, "Exactly 100 cm of relief is accepted")
	grid.elevation[center] = 3.0001
	dev.refresh_eligibility(grid)
	verify(dev.patches.is_empty() and highlighted(dev) == 0, "An interior peak above 100 cm excludes the entire patch and highlight")
	grid.elevation[center] = 2.0
	grid.elevation[grid.index(0, 0)] = 3.0
	grid.elevation[grid.index(9, 9)] = 1.9999
	dev.refresh_eligibility(grid)
	verify(dev.patches.is_empty(), "Relief includes both peaks and depressions")
	for y in 10:
		for x in 10:
			grid.elevation[grid.index(x, y)] = 2.0 + x * 0.12
	dev.refresh_eligibility(grid)
	verify(dev.patches.is_empty(), "A 108 cm slope is excluded even when each neighbouring step is only 12 cm")
	for y in 10:
		for x in 10:
			grid.elevation[grid.index(x, y)] = 2.0 + x * 0.08
	dev.refresh_eligibility(grid)
	verify(dev.patches.size() == 1, "A gentle 72 cm slope remains eligible")
	grid.elevation.fill(200.0)
	dev.refresh_eligibility(grid)
	verify(dev.patches.size() == 1, "Flatness measures relief rather than absolute altitude")
	grid.elevation.fill(2.0)
	dev.assessed_fraction[center] = 0.15
	dev.refresh_eligibility(grid)
	verify(dev.patches.is_empty(), "Flatness does not replace the existing flood-time condition")
	dev.assessed_fraction[center] = 0.0
	grid.river[center] = 1
	dev.refresh_eligibility(grid)
	verify(dev.patches.is_empty(), "River cells remain unsuitable even when they are flat")
	var small := GridState.new(9, 10)
	var small_dev := dry_development(90)
	small_dev.refresh_eligibility(small)
	verify(small_dev.patches.is_empty(), "A flat area smaller than 10 by 10 is still unsuitable")

func _test_terrain_changes() -> void:
	var state := session()
	state.dismiss_transition()
	state.development.current_seconds = 300.0
	state.development.assess_window()
	state.development.refresh_eligibility(state.grid)
	var center := state.grid.index(30, 30)
	verify(state.development.eligible[center] != 0, "Level land is highlighted before terrain changes")
	state.edit_terrain(center, 1)
	verify(state.development.eligible[center] != 0, "A 100 cm brush still meets the flatness boundary")
	state.edit_terrain(center, 1)
	verify(state.development.eligible[center] == 0, "Raising the center to 200 cm removes its migration highlight immediately")
	state.edit_terrain(center, -1)
	verify(state.development.eligible[center] != 0, "Lowering the land back restores the migration highlight")
	var grid := GridState.new(10, 10)
	var dev := dry_development(100)
	dev.refresh_eligibility(grid)
	grid.elevation[grid.index(5, 5)] = 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var rng_before := rng.state
	verify(dev.settle(grid, rng, 8).is_empty() and dev.houses.is_empty(), "Settlement rechecks terrain rather than accepting a stale suitable patch")
	verify(rng.state == rng_before, "An unsuitable migration attempt does not consume scenario randomness")

func _test_flatness_restore() -> void:
	var state := session()
	state.development.current_seconds = 300.0
	state.development.assess_window()
	for y in state.grid.height:
		for x in state.grid.width:
			state.grid.elevation[state.grid.index(x, y)] = 2.0 + x * 0.12
	house(state, 20, 1, 0.0)
	for cell in state.development.houses[0].cells:
		state.grid.elevation[cell] = 4.64
	state.ever_settled = true
	state.development.eligible.fill(1)
	state.development.patches = PackedInt32Array([state.grid.index(20, 20)])
	var store := SaveStore.new()
	var path := "res://work/game/flatness-save.dat"
	verify(store.write(state, path), "A save containing old suitability caches can be written")
	var restored := GameSession.from_data(store.read(path))
	verify(restored.development.patches.is_empty() and highlighted(restored.development) == 0, "Continuation rebuilds old suitability caches with the flatness rule")
	verify(restored.development.population() == 1, "Existing residents are preserved when an old save is continued")
	verify(restored.grid.elevation == state.grid.elevation and restored.grid.water == state.grid.water, "Suitability refresh does not alter saved terrain or water")
	verify(restored.power == state.power and restored.rng.state == state.rng.state, "Suitability refresh preserves power and the scenario RNG state")

func _test_generated_land() -> void:
	var path := "res://work/game/after-year.dat"
	if not FileAccess.file_exists(path):
		return
	var data := SaveStore.new().read(path)
	if data.is_empty():
		return
	var state := GameSession.from_data(data)
	verify(not state.development.patches.is_empty(), "The previously simulated first-year catchment retains suitable migration land")
	print("FLATNESS_FIRST_YEAR_PATCHES: ", state.development.patches.size())
