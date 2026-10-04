class_name WaterSimulator
extends RefCounted

const FIXED_DT := 0.05
const CONDUCTIVITY := 30.0
# Exact relaxation of an isolated pair: a larger head gap transfers more water.
# The coefficient stays below 1/2, so an edge cannot overshoot equal water levels.
const PAIR_WEIGHT := 0.5 * (1.0 - exp(-2.0 * CONDUCTIVITY * FIXED_DT))
const HALF_PAIR_WEIGHT := 0.5 * (1.0 - exp(-CONDUCTIVITY * FIXED_DT))
const SWEEP_ORDER := [0, 1, 2, 3, 2, 1, 0]

var grid: GridState
var inlets := PackedInt32Array()
var outlets := PackedInt32Array()
var outlet_capacity := 1.2
var initial_water := 0.0
var rain_added := 0.0
var inflow_added := 0.0
var drained := 0.0
var last_drained := 0.0
var evaporated := 0.0
var east := PackedFloat64Array()
var south := PackedFloat64Array()
var land_count := 0
var edge_groups: Array[PackedInt32Array] = []
var track_origins := false
var measure_discharge := false

func _init(state: GridState) -> void:
	grid = state
	initial_water = grid.total_water()
	var count := grid.water.size()
	east.resize(count)
	south.resize(count)
	for group in 4:
		edge_groups.append(PackedInt32Array())
	for y in grid.height:
		for x in grid.width:
			var i := x + y * grid.width
			if not grid.sea[i]:
				land_count += 1
			if x + 1 < grid.width and not (grid.sea[i] and grid.sea[i + 1]):
				edge_groups[x % 2].append(i)
			if y + 1 < grid.height and not (grid.sea[i] and grid.sea[i + grid.width]):
				edge_groups[2 + y % 2].append(i)

func step(rain_rate: float = 0.0, inflow_rate: float = 0.0,
		evaporation_rate: float = 0.0) -> void:
	assert(rain_rate >= 0.0 and inflow_rate >= 0.0 and evaporation_rate >= 0.0)
	var depths := grid.water
	var heights := grid.elevation
	var sea := grid.sea
	var flow := grid.flow
	var peaks := grid.peak_depth
	var origins := grid.origin_mask
	var count := depths.size()
	var width := grid.width
	var rain := rain_rate * FIXED_DT
	var inflow := inflow_rate * FIXED_DT / inlets.size() if not inlets.is_empty() else 0.0
	var evaporation := evaporation_rate * FIXED_DT
	east.fill(0.0)
	south.fill(0.0)
	last_drained = 0.0
	for i in inlets:
		depths[i] += inflow
		if track_origins:
			origins[i] |= 1 << inlets.find(i)
	if rain > 0.0:
		for i in count:
			if not sea[i]:
				depths[i] += rain
	# A symmetric forward/backward sweep completes inside every public tick.
	# Publishing alternating orders on separate ticks causes wet/dry flashing.
	for pass_index in SWEEP_ORDER.size():
		var group: int = SWEEP_ORDER[pass_index]
		var weight := PAIR_WEIGHT if pass_index == 3 else HALF_PAIR_WEIGHT
		var offset := 1 if group < 2 else width
		var transfers := east if group < 2 else south
		for i in edge_groups[group]:
			var j := i + offset
			if depths[i] == 0.0 and depths[j] == 0.0:
				continue
			var head_i := grid.sea_level if sea[i] else heights[i] + depths[i]
			var head_j := grid.sea_level if sea[j] else heights[j] + depths[j]
			var amount := clampf(weight * (head_i - head_j), -depths[j], depths[i])
			depths[i] -= amount
			depths[j] += amount
			if track_origins and absf(amount) > 1e-10:
				if amount > 0.0:
					origins[j] |= origins[i]
				else:
					origins[i] |= origins[j]
			# The sea only accepts water. Its visible reservoir never supplies land.
			if sea[i]:
				last_drained += depths[i]
				depths[i] = 0.0
			if sea[j]:
				last_drained += depths[j]
				depths[j] = 0.0
			transfers[i] += amount
		if group < 2:
			east = transfers
		else:
			south = transfers
	for i in outlets:
		var amount := minf(depths[i], outlet_capacity * FIXED_DT)
		depths[i] -= amount
		last_drained += amount
	var evaporated_tick := 0.0
	for i in count:
		var amount := minf(depths[i], evaporation)
		depths[i] -= amount
		evaporated_tick += amount
		peaks[i] = maxf(peaks[i], depths[i])
		flow[i] = Vector2(east[i] + (east[i - 1] if i % width > 0 else 0.0),
			south[i] + (south[i - width] if i >= width else 0.0))
		if measure_discharge:
			grid.discharge[i] = (absf(east[i]) + absf(south[i])
				+ (absf(east[i - 1]) if i % width > 0 else 0.0)
				+ (absf(south[i - width]) if i >= width else 0.0)) * 0.5 / FIXED_DT
	evaporated += evaporated_tick
	rain_added += rain * land_count
	if not inlets.is_empty():
		inflow_added += inflow_rate * FIXED_DT
	drained += last_drained
	grid.water = depths
	grid.flow = flow
	grid.peak_depth = peaks
	if track_origins:
		grid.origin_mask = origins

func balance_error() -> float:
	return grid.total_water() - (initial_water + rain_added + inflow_added - drained - evaporated)
