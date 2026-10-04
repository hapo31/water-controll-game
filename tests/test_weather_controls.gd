extends SceneTree
var main: Node
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("verify_controls")

func verify(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func press_button(label: String) -> void:
	for button in main.hud.find_children("*", "Button", true, false):
		if button.text == label:
			button.pressed.emit()
			return
	verify(false, "Missing control: " + label)

func select_weather(value: int) -> void:
	main.hud.weather_select.select(value)
	main.hud.weather_select.item_selected.emit(value)

func verify_controls() -> void:
	DirAccess.make_dir_recursive_absolute("res://work/basin")
	root.size = Vector2i(1360, 860)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame
	main.set_process(false)
	main._home()
	verify(main.hud.weather_select.item_count == 3, "Three weather options")
	main.experiment.grid.elevation[main.experiment.grid.index(38, 32)] += 2.0
	for tick in 40:
		main.experiment.tick()
	main._toggle()
	var original_grid: GridState = main.experiment.grid
	var heights := original_grid.elevation.duplicate()
	var water := original_grid.water.duplicate()
	for weather in [RainExperiment.Weather.SUNNY, RainExperiment.Weather.NORMAL, RainExperiment.Weather.HEAVY]:
		select_weather(weather)
		verify(main.experiment.weather == weather and main.experiment.grid == original_grid,
			"Selector changes weather without replacing the map")
		verify(main.experiment.grid.water == water and main.experiment.grid.elevation == heights,
			"Selector preserves terrain and water")
		verify(main.rain.visible == (weather != RainExperiment.Weather.SUNNY),
			"Particle visibility follows the selected weather")
	select_weather(RainExperiment.Weather.NORMAL)
	var elapsed: float = main.experiment.elapsed
	press_button("水の状態を初期化")
	verify(main.experiment.grid.elevation == heights and main.experiment.grid.water == FixedMap.create().water,
		"Water reset restores water without changing edited terrain")
	verify(main.experiment.elapsed == elapsed and main.experiment.weather == RainExperiment.Weather.NORMAL and main.experiment.running,
		"Water reset keeps the weather and playback settings")
	press_button("地形を初期化")
	var initial := FixedMap.create()
	verify(main.experiment.grid.elevation == initial.elevation and main.experiment.grid.water == initial.water,
		"Terrain reset restores both terrain and water")
	verify(main.experiment.elapsed == 0.0 and main.experiment.solver.rain_added == 0.0 and main.experiment.summary.drained == 0.0,
		"Full reset clears the clock and water measurements")
	verify(not main.experiment.running and main.experiment.weather == RainExperiment.Weather.HEAVY and main.hud.weather_select.selected == RainExperiment.Weather.HEAVY,
		"Full reset restores the initial weather and paused state")
	verify(not main.rain.visible and view_selection_cleared(), "Full reset clears particles and cell selection")
	select_weather(RainExperiment.Weather.NORMAL)
	main._toggle()
	for tick in 40:
		main.experiment.tick()
	main._refresh()
	await create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://work/basin/weather-controls.png")
	print("WEATHER_UI_CHECKS: %d, FAILURES: %d" % [checks, failures])
	quit(1 if failures else 0)

func view_selection_cleared() -> bool:
	return main.view.selected == -1
