class_name TerrainGenerator
extends RefCounted

const SIZE := 64
const TRACE_TICKS := 1800
var terrain_seed: int
var sectional_channels := true
var grid: GridState
var progress := 0.0
var stage := "地形を作っています。"
var mutex := Mutex.new()
var mountains: Array[Vector2i] = []
var traces: Array[Dictionary] = []
var cancelled := false

func cancel() -> void:
	mutex.lock()
	cancelled = true
	mutex.unlock()

func _is_cancelled() -> bool:
	mutex.lock()
	var result := cancelled
	mutex.unlock()
	return result

func _init(value: int, use_sections: bool = true) -> void:
	terrain_seed = value
	sectional_channels = use_sections

func status() -> Dictionary:
	mutex.lock()
	var result := {"progress": progress, "stage": stage}
	mutex.unlock()
	return result

func _progress(value: float, message: String) -> void:
	mutex.lock()
	progress = value
	stage = message
	mutex.unlock()

func generate() -> GridState:
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = terrain_seed
	noise.frequency = 0.055
	noise.fractal_octaves = 3
	grid = GridState.new(SIZE, SIZE)
	var peak_count := rng.randi_range(3, 4)
	for n in peak_count:
		mountains.append(Vector2i(roundi(5.0 + n * 54.0 / (peak_count - 1)) + rng.randi_range(-2, 2), rng.randi_range(0, 4)))
	for y in SIZE:
		for x in SIZE:
			var i := grid.index(x, y)
			var z := (SIZE - 1 - y) * 0.08 + noise.get_noise_2d(x, y) * 0.65
			for peak in mountains:
				z += 5.0 * exp(-Vector2(x - peak.x, y - peak.y).length_squared() / 70.0)
			grid.elevation[i] = z
			if y == SIZE - 1:
				grid.sea[i] = 1
				grid.elevation[i] = -1.0
	# Three valleys between summits, all within five cells of the northern edge.
	for n in 3:
		var a: Vector2i = mountains[n % (peak_count - 1)]
		var b: Vector2i = mountains[n % (peak_count - 1) + 1]
		var fraction := 0.5 if peak_count == 4 else (0.35 if n == 0 else 0.65 if n == 2 else 0.5)
		var x := roundi(lerpf(a.x, b.x, fraction))
		if n == 2 and peak_count == 3:
			x = roundi(lerpf(mountains[1].x, mountains[2].x, 0.72))
		var cell := grid.index(x, 4)
		grid.source_cells.append(cell)
		grid.water[cell] = 0.1
	_progress(0.08, "水を流して、川筋を探しています。")
	for pass_index in 3:
		var solver := WaterSimulator.new(grid)
		solver.inlets = grid.source_cells
		solver.track_origins = true
		solver.measure_discharge = true
		var maxima := PackedFloat64Array()
		maxima.resize(SIZE * SIZE)
		for tick in TRACE_TICKS:
			if tick % 30 == 0 and _is_cancelled():
				return null
			solver.step(0.0, GameUnits.BASE_INFLOW, 0.0001)
			for i in maxima.size():
				maxima[i] = maxf(maxima[i], grid.discharge[i])
			if tick % 30 == 0:
				_progress(0.08 + (pass_index + float(tick) / TRACE_TICKS) * 0.28,
					"水を流して、川筋を探しています。（%d / 3）" % (pass_index + 1))
		var centers := _channel_centers(maxima)
		var lowering := PackedFloat64Array()
		lowering.resize(maxima.size())
		for cell in centers:
			grid.river[cell] = 1
			lowering[cell] = 0.5
			var x: int = cell % SIZE
			var y: int = cell / SIZE
			for direction in [-1, 1]:
				var reach := rng.randi_range(1, 3)
				for distance in range(1, reach + 1):
					var xx: int = x + direction * distance
					if xx >= 0 and xx < SIZE:
						var bank := grid.index(xx, y)
						lowering[bank] = maxf(lowering[bank], rng.randf_range(0.1, 0.4))
		for i in lowering.size():
			if not grid.sea[i]:
				grid.elevation[i] -= lowering[i]
		traces.append({"centers": centers, "flow": maxima, "origins": grid.origin_mask.duplicate()})
		# Every pass measures the newly carved ground from an empty catchment.
		grid.water.fill(0.0)
		grid.origin_mask.fill(0)
	_progress(0.94, "川に水を戻しています。")
	var settle := WaterSimulator.new(grid)
	settle.inlets = grid.source_cells
	settle.measure_discharge = true
	settle.track_origins = true
	for tick in 800:
		if tick % 40 == 0 and _is_cancelled():
			return null
		settle.step(0.0, GameUnits.BASE_INFLOW, 0.001)
		if tick % 40 == 0:
			_progress(0.94 + float(tick) / 800.0 * 0.06, "川に水を戻しています。")
	grid.initial_water = grid.water.duplicate()
	grid.peak_depth = grid.water.duplicate()
	_progress(1.0, "地形ができました。")
	return grid

func _channel_centers(flows: PackedFloat64Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	if not sectional_channels:
		var maximum := 0.0
		for i in flows.size():
			if not grid.sea[i]:
				maximum = maxf(maximum, flows[i])
		for i in flows.size():
			if not grid.sea[i] and maximum > 0.0 and absf(flows[i] - maximum) < 1e-9:
				result.append(i)
		return result
	# Compare each tributary / merged provenance within every N-S cross-section.
	for y in SIZE - 1:
		for mask in range(1, 8):
			var maximum := 0.0
			for x in SIZE:
				var i := grid.index(x, y)
				if grid.origin_mask[i] == mask:
					maximum = maxf(maximum, flows[i])
			if maximum < 0.00001:
				continue
			for x in SIZE:
				var i := grid.index(x, y)
				if grid.origin_mask[i] == mask and absf(flows[i] - maximum) < 1e-9:
					result.append(i)
	return result
