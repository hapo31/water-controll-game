extends SceneTree
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
 checks += 1
 if not value:
  failures += 1
  push_error(message)
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 DirAccess.make_dir_recursive_absolute("res://work/basin")
 root.size = Vector2i(1360, 860)
 var main = load("res://scenes/main.tscn").instantiate()
 root.add_child(main)
 await process_frame
 await RenderingServer.frame_post_draw
 await process_frame
 main._home()
 main._refresh()
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://work/basin/overview.png")
 var grid: GridState = main.experiment.grid
 var sea_cell := grid.index(175,239)
 var old_sea := grid.elevation[sea_cell]
 main._edit_terrain(sea_cell, 0.5)
 main._edit_terrain(sea_cell, -0.5)
 check(grid.elevation[sea_cell] == old_sea, "Both editing tools must reject sea")
 var land := grid.index(185,168)
 var old_land := grid.elevation[land]
 var mesh = main.view.mesh
 main._edit_terrain(land, 0.5)
 check(grid.elevation[land] == old_land + 0.5, "Land remains editable")
 check(not main.view.terrain_dirty and main.view.mesh == mesh, "Editing must reuse terrain geometry")
 main._edit_terrain(land,-0.5)
 main.view.selected = sea_cell
 main._refresh()
 check(main.hud.cell_info.text.contains("編集不可"), "Sea inspection explains the edit lock")
 main.camera.zoom = Vector2.ONE * 0.6
 main.camera.position = main.view.project(124,110,grid.surface(grid.index(124,110))) - Vector2(250,0)
 main.view.queue_redraw()
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://work/basin/lake.png")
 main._home()
 main._toggle()
 var start := Time.get_ticks_usec()
 var last := start
 var intervals: Array[float] = []
 while Time.get_ticks_usec() - start < 10000000:
  await process_frame
  var now := Time.get_ticks_usec()
  intervals.append((now-last)/1000.0)
  last = now
 main._toggle()
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://work/basin/running.png")
 intervals.sort()
 print(JSON.stringify({"frames": intervals.size(), "average_fps": intervals.size()/10.0, "p95_ms": intervals[int(intervals.size()*.95)], "simulation_seconds": main.experiment.elapsed, "step_ms": main.experiment.step_ms, "summary": main.experiment.summary, "checks": checks, "failures": failures}))
 check(main.experiment.elapsed > 3.0, "Worker advances the simulation")
 check(absf(main.experiment.summary.balance_error)<1e-6, "Threaded water budget is conserved")
 check(main.experiment.solver.drained > 0.0, "The river discharges into the sea")
 check(grid.surface(sea_cell)==0.0 and grid.water[sea_cell]==0.0, "The sea retains a fixed visual surface and no stored water")
 # Exercise control changes while a worker tick is still outstanding.
 main.set_process(false)
 main._toggle()
 main._process(0.05)
 check(main.simulation_thread.is_started(), "A worker tick is pending")
 main._set_weather(RainExperiment.Weather.NORMAL)
 check(not main.simulation_thread.is_started() and main.experiment.running, "Weather change joins the pending tick and keeps playback")
 check(absf(main.experiment.summary.balance_error)<1e-6, "Joining for a weather change preserves the water ledger")
 main._process(0.05)
 main._reset_water()
 check(main.experiment.grid.water == main.experiment.grid.initial_water and main.experiment.running, "Water reset safely joins the worker and restores initial water")
 check(main.experiment.weather == RainExperiment.Weather.NORMAL, "Water reset retains the chosen weather")
 main._process(0.05)
 main._reset_terrain()
 check(not main.simulation_thread.is_started() and not main.experiment.running, "Full reset leaves no pending worker and pauses")
 check(main.experiment.elapsed == 0.0 and main.experiment.weather == RainExperiment.Weather.HEAVY, "Full reset restores the clock and weather")
 check(main.experiment.grid.water == main.experiment.grid.initial_water, "Full reset restores lake and river water together with terrain")
 print("UI_RESULT: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)
