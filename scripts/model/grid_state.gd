class_name GridState
extends RefCounted

var width: int
var height: int
var elevation := PackedFloat64Array()
var water := PackedFloat64Array()
var river := PackedByteArray()
var sea := PackedByteArray()
var lake := PackedByteArray()
var sea_level := 0.0
var initial_water := PackedFloat64Array()
var source_cells := PackedInt32Array()
var landmarks: Array[Dictionary] = []
var peak_depth := PackedFloat64Array()
var flow := PackedVector2Array()
# Optional gameplay diagnostics; legacy laboratory units remain unchanged.
var origin_mask := PackedByteArray()
var discharge := PackedFloat64Array()

func _init(w: int = 256, h: int = 256) -> void:
	width = w
	height = h
	var count := w * h
	elevation.resize(count)
	water.resize(count)
	river.resize(count)
	sea.resize(count)
	lake.resize(count)
	peak_depth.resize(count)
	flow.resize(count)
	origin_mask.resize(count)
	discharge.resize(count)

func index(x: int, y: int) -> int:
	return x + y * width

func surface(i: int) -> float:
	return sea_level if sea[i] else elevation[i] + water[i]

func visible_depth(i: int) -> float:
	return maxf(0.0, sea_level - elevation[i]) if sea[i] else water[i]

func total_water() -> float:
	var total := 0.0
	for amount in water:
		total += amount
	return total

func inundated_cells(use_peak: bool = false) -> int:
	var count := 0
	for i in water.size():
		var depth := peak_depth[i] if use_peak else water[i]
		if river[i] == 0 and sea[i] == 0 and depth >= 0.25:
			count += 1
	return count

func simulation_copy() -> GridState:
	var result := GridState.new(width, height)
	result.elevation = elevation
	result.water = water
	result.river = river
	result.sea = sea
	result.lake = lake
	result.sea_level = sea_level
	result.peak_depth = peak_depth
	result.flow = flow
	result.origin_mask = origin_mask
	result.discharge = discharge
	return result
