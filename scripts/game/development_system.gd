class_name DevelopmentSystem
extends RefCounted

const PATCH_SIZE := 10
const MAX_PATCH_RELIEF := 1.0
const HOUSE_WIDTH := 3
const HOUSE_HEIGHT := 4
const YEAR_TURNS := 8
var houses: Array[Dictionary] = []
var eligible := PackedByteArray()
var patches := PackedInt32Array()
var current_wet := PackedFloat64Array()
var previous_wet := PackedFloat64Array()
var current_seconds := 0.0
var previous_seconds := 0.0
var observing := false
var next_id := 1
var assessed_fraction := PackedFloat64Array()
var assessed_seconds := 0.0

func _init(count: int = 4096) -> void:
	eligible.resize(count)
	current_wet.resize(count)
	previous_wet.resize(count)
	assessed_fraction.resize(count)
	assessed_fraction.fill(1.0)

func begin_rain_window() -> void:
	previous_wet = current_wet.duplicate()
	previous_seconds = current_seconds
	current_wet.fill(0.0)
	current_seconds = 0.0
	observing = true

func sample(grid: GridState, dt: float) -> void:
	if not observing:
		return
	current_seconds += dt
	for i in grid.water.size():
		if grid.water[i] >= GameUnits.WET_DEPTH:
			current_wet[i] += dt

func wet_fraction(cell: int) -> float:
	var seconds := current_seconds + previous_seconds
	return (current_wet[cell] + previous_wet[cell]) / seconds if seconds > 0.0 else 1.0

func assess_window() -> void:
	# Freeze the completed observation at the start of preparation. Terrain edits
	# later in that phase must not dilute the measured rainfall window with dry time.
	assessed_seconds = current_seconds + previous_seconds
	for cell in assessed_fraction.size():
		assessed_fraction[cell] = wet_fraction(cell)

func house_at(cell: int) -> Dictionary:
	for house in houses:
		if house.cells.has(cell):
			return house
	return {}

func population() -> int:
	var result := 0
	for house in houses:
		result += house.population
	return result

func refresh_eligibility(grid: GridState) -> void:
	eligible.fill(0)
	patches.clear()
	if assessed_seconds < 60.0 - 0.001:
		return
	var occupied := PackedByteArray()
	occupied.resize(grid.water.size())
	for house in houses:
		for cell in house.cells:
			occupied[cell] = 1
	# A summed-area table checks the entire 10×10 square, including its interior.
	var stride := grid.width + 1
	var prefix := PackedInt32Array()
	prefix.resize(stride * (grid.height + 1))
	for y in grid.height:
		for x in grid.width:
			var cell := grid.index(x, y)
			var unsuitable := int(grid.sea[cell] != 0 or grid.river[cell] != 0
				or grid.source_cells.has(cell) or occupied[cell] != 0 or assessed_fraction[cell] >= 0.15)
			var p := x + 1 + (y + 1) * stride
			prefix[p] = unsuitable + prefix[p - 1] + prefix[p - stride] - prefix[p - stride - 1]
	for y in range(grid.height - PATCH_SIZE + 1):
		for x in range(grid.width - PATCH_SIZE + 1):
			var a := x + y * stride
			var b := x + PATCH_SIZE + y * stride
			var c := x + (y + PATCH_SIZE) * stride
			var d := x + PATCH_SIZE + (y + PATCH_SIZE) * stride
			if prefix[d] - prefix[b] - prefix[c] + prefix[a] != 0:
				continue
			if not _patch_is_flat(grid, x, y):
				continue
			patches.append(grid.index(x, y))
			for yy in range(y, y + PATCH_SIZE):
				for xx in range(x, x + PATCH_SIZE):
					eligible[grid.index(xx, yy)] = 1

func _patch_is_flat(grid: GridState, x: int, y: int) -> bool:
	var lowest := INF
	var highest := -INF
	for yy in range(y, y + PATCH_SIZE):
		for xx in range(x, x + PATCH_SIZE):
			var elevation := grid.elevation[grid.index(xx, yy)]
			lowest = minf(lowest, elevation)
			highest = maxf(highest, elevation)
			if highest - lowest > MAX_PATCH_RELIEF:
				return false
	return true

func settle(grid: GridState, rng: RandomNumberGenerator, turn: int) -> Dictionary:
	refresh_eligibility(grid)
	if patches.is_empty():
		return {}
	var patch := patches[rng.randi_range(0, patches.size() - 1)]
	var x := patch % grid.width + rng.randi_range(0, PATCH_SIZE - HOUSE_WIDTH)
	var y := patch / grid.width + rng.randi_range(0, PATCH_SIZE - HOUSE_HEIGHT)
	var cells := PackedInt32Array()
	var highest := -INF
	for yy in range(y, y + HOUSE_HEIGHT):
		for xx in range(x, x + HOUSE_WIDTH):
			var cell := grid.index(xx, yy)
			cells.append(cell)
			highest = maxf(highest, grid.elevation[cell])
	for cell in cells:
		grid.elevation[cell] = highest
	var house := {"id": next_id, "anchor": grid.index(x, y), "cells": cells,
		"population": 1, "built_turn": turn, "growth_turn": turn}
	next_id += 1
	houses.append(house)
	refresh_eligibility(grid)
	return house

func grow(turn: int) -> int:
	var added := 0
	for house in houses:
		if house.population > 0 and turn - house.growth_turn >= YEAR_TURNS:
			if house.population < 4:
				house.population += 1
				added += 1
			house.growth_turn = turn
	return added

func to_data() -> Dictionary:
	return {"houses": houses, "current_wet": current_wet, "previous_wet": previous_wet,
		"current_seconds": current_seconds, "previous_seconds": previous_seconds,
		"observing": observing, "next_id": next_id, "eligible": eligible, "patches": patches,
		"assessed_fraction": assessed_fraction, "assessed_seconds": assessed_seconds}

func restore(data: Dictionary) -> void:
	houses.assign(data.houses)
	current_wet = data.current_wet
	previous_wet = data.previous_wet
	current_seconds = data.current_seconds
	previous_seconds = data.previous_seconds
	observing = data.observing
	next_id = data.next_id
	eligible = data.eligible
	patches = data.patches
	if data.has("assessed_fraction"):
		assessed_fraction = data.assessed_fraction
		assessed_seconds = data.assessed_seconds
	else:
		assess_window()
