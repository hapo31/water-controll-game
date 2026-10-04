class_name FixedMap
extends RefCounted

const Grid = preload("res://scripts/model/grid_state.gd")
const SIZE := 256
const INFLOW_PER_CELL := 1.2
const DRAIN_PER_CELL := 1.2
const LAKE_LEVEL := 5.5
const MAX_EDIT_HEIGHT := 40.0

static func coast_y(x: float) -> float:
	return 219.0 + 7.0 * sin(x * 0.038) + 3.0 * sin(x * 0.086)

static func tributary_x(branch: int, y: float) -> float:
	var t := clampf(y / 100.0, 0.0, 1.0)
	var starts := [38.0, 126.0, 213.0]
	var ends := [100.0, 124.0, 148.0]
	return lerpf(starts[branch], ends[branch], t) + sin(t * PI) * sin(y * 0.095 + branch) * 8.0

static func main_river_x(y: float) -> float:
	return 124.0 + 28.0 * sin((y - 129.0) * 0.067)

static func create(_reinforced: bool = false) -> GridState:
	var grid := Grid.new(SIZE, SIZE)
	var noise := FastNoiseLite.new()
	noise.seed = 42017
	noise.frequency = 0.032
	noise.fractal_octaves = 3
	for y in SIZE:
		var upstream := maxf(0.0, (98.0 - y) / 98.0)
		for x in SIZE:
			var i := grid.index(x, y)
			var coast := coast_y(x)
			if y >= coast:
				grid.sea[i] = 1
				grid.elevation[i] = -1.3 - (y - coast) * 0.04
				continue
			var n := noise.get_noise_2d(x, y)
			var z := 1.0 + maxf(0.0, 212.0 - y) * 0.052
			# Broad mountain ridges and small irregular slopes surround carved valleys.
			z += upstream * (7.0 + 11.0 * pow(absf(sin(x * 0.052 + y * 0.009)), 2.0))
			z += n * (0.35 + upstream * 2.5)
			z = minf(z, 0.35 + (coast - y) * 0.35)
			var channel_level := INF
			if y <= 102:
				for branch in 3:
					var distance := absf(x - tributary_x(branch, y))
					var level := LAKE_LEVEL + maxf(0.0, 89.0 - y) * 0.13
					var half_width := 2.5 + y * 0.025
					if distance <= half_width:
						channel_level = minf(channel_level, level)
					elif distance < half_width + 8.0:
						z = minf(z, level + 0.8 + (distance - half_width) * 0.55)
			if y >= 123:
				var distance := absf(x - main_river_x(y))
				var half_width := 5.5 + (y - 123) * 0.025
				var level := maxf(0.08, LAKE_LEVEL - maxf(0.0, y - 129.0) * 0.062)
				if distance <= half_width:
					channel_level = minf(channel_level, level)
				elif distance < half_width + 10.0:
					z = minf(z, level + 0.65 + (distance - half_width) * 0.13)
			var lx := (x - 124.0) / 36.0
			var ly := (y - 110.0) / 25.0
			var lake_radius := sqrt(lx * lx + ly * ly)
			if lake_radius < 1.0:
				grid.lake[i] = 1
				grid.river[i] = 1
				z = 2.6 + 1.5 * pow(lake_radius, 3.0)
				grid.water[i] = LAKE_LEVEL - z
			elif is_finite(channel_level):
				grid.river[i] = 1
				z = channel_level - 0.7
				grid.water[i] = 0.7
			elif lake_radius < 1.25:
				z = maxf(z, LAKE_LEVEL + 0.65 + (lake_radius - 1.0) * 2.0)
			# A shallow floodplain hollow retains rain away from the main channel.
			if pow((x - 185.0) / 15.0, 2.0) + pow((y - 168.0) / 11.0, 2.0) < 1.0:
				z -= 1.1
			grid.elevation[i] = z
			if y == 0 and grid.river[i]:
				grid.source_cells.append(i)
	grid.peak_depth = grid.water.duplicate()
	grid.initial_water = grid.water.duplicate()
	grid.landmarks = [
		{"cell": Vector2i(72, 27), "label": "山地"},
		{"cell": Vector2i(124, 110), "label": "合流湖"},
		{"cell": Vector2i(121, 176), "label": "蛇行する本流"},
		{"cell": Vector2i(185, 168), "label": "低地の窪地"},
		{"cell": Vector2i(175, 239), "label": "海 / 排水域"},
	]
	return grid

static func inlet_cells(grid: GridState) -> PackedInt32Array:
	return grid.source_cells

static func outlet_cells(grid: GridState) -> PackedInt32Array:
	# Sea cells absorb incoming water at the fixed sea level, without a storage cap.
	var result := PackedInt32Array()
	for i in grid.sea.size():
		if grid.sea[i]:
			result.append(i)
	return result
