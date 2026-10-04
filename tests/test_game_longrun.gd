extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var data := SaveStore.new().read("res://work/game/generated.dat")
	if data.is_empty():
		push_error("Run test_game.gd before this lifecycle test")
		quit(1)
		return
	var state := GameSession.from_data(data)
	var largest_error := 0.0
	var largest_depth := 0.0
	var start := Time.get_ticks_msec()
	for turn in 8:
		state.dismiss_transition()
		while state.phase == GameSession.Phase.PREPARE:
			state.advance_ticks(200)
		state.dismiss_transition()
		while state.phase == GameSession.Phase.RAIN:
			state.advance_ticks(200)
		largest_error = maxf(largest_error, absf(state.solver.balance_error()))
		for peak in state.grid.peak_depth:
			largest_depth = maxf(largest_depth, peak)
		if state.phase != GameSession.Phase.REPORT:
			push_error("First uninhabited year ended unexpectedly")
			quit(1)
			return
		state.next_turn()
		print("LIFECYCLE_TURN: ", state.turn, " wet window: ", state.development.current_seconds + state.development.previous_seconds)
	var success := state.turn == 8 and state.development.population() == 1 and largest_error < 1e-6
	print(JSON.stringify({"test": "GAME_LIFECYCLE", "success": success,
		"elapsed_ms": Time.get_ticks_msec() - start, "simulation_seconds": state.elapsed,
		"population": state.development.population(), "eligible_patches": state.development.patches.size(),
		"largest_balance_error": largest_error, "largest_depth_cm": largest_depth * 100.0}))
	if success:
		SaveStore.new().write(state, "res://work/game/after-year.dat")
	else:
		push_error("Full first year failed to reach a safe settlement")
	quit(0 if success else 1)
