extends SceneTree
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var e := RainExperiment.new()
 for n in 100:
  e.tick()
 var flips := 0
 var shallow_delta := 0.0
 var lake_delta := 0.0
 var mean: float = 0.0
 var before_previous := e.grid.water.duplicate()
 var previous := e.grid.water.duplicate()
 var reversals := 0
 var start := Time.get_ticks_usec()
 for n in 20:
  e.tick()
  for i in e.grid.water.size():
   var depth := e.grid.water[i]
   if not e.grid.sea[i]:
    if (depth > 0.003) != (previous[i] > 0.003):
     flips += 1
    if depth < 0.15 and previous[i] < 0.15:
     shallow_delta += absf(depth-previous[i])
    if e.grid.lake[i]:
     lake_delta = maxf(lake_delta,absf(depth-previous[i]))
    if (depth-previous[i]) * (previous[i]-before_previous[i]) < -0.000001:
     reversals += 1
   mean += absf(depth-previous[i])
  before_previous = previous
  previous = e.grid.water.duplicate()
 print(JSON.stringify({"visibility_flips_per_tick":flips/20.0,"depth_reversals_per_tick":reversals/20.0,"shallow_delta_per_tick":shallow_delta/20.0,"lake_max_delta":lake_delta,"all_delta_per_tick":mean/20.0,"step_ms":e.step_ms,"balance_error":e.solver.balance_error(),"time_ms":(Time.get_ticks_usec()-start)/1000.0}))
 quit()
