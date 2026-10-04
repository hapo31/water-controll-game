extends SceneTree

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): push_error("Generation UI timed out"); quit(1))
	call_deferred("run")

func run() -> void:
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.save_path = "res://work/game/generation-ui-save.dat"
	game._new_game("31415")
	var monotonic := true
	var hidden := true
	var last_progress := 0.0
	var captured := false
	var start := Time.get_ticks_msec()
	while game.screen == "generating":
		await process_frame
		if game.screen != "generating":
			break
		var progress: float = game.generator.status().progress
		monotonic = monotonic and progress >= last_progress
		hidden = hidden and not game.view.visible and game.hud.loading_screen.visible
		last_progress = progress
		if progress > 0.3 and not captured:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://work/game/generating.png")
			captured = true
	var success: bool = monotonic and hidden and captured and game.session.terrain_seed == 31415 and game.hud.modal_kind == "transition" and game.hud.game_screen.visible
	print(JSON.stringify({"test": "GAME_GENERATION_UI", "success": success, "elapsed_ms": Time.get_ticks_msec() - start, "monotonic_progress": monotonic, "intermediate_terrain_hidden": hidden}))
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if success else 1)
