class_name SaveStore
extends RefCounted

const PATH := "user://suijin-save.dat"
const MAGIC := "SUIJIN_POC_1"
const MAX_BYTES := 32000000
const SESSION_KEYS := ["version", "terrain_seed", "scenario_seed", "rng_state", "phase", "phase_seconds", "elapsed", "turn", "power", "paused", "speed", "transition_pending", "ever_settled", "weather", "weather_multiplier", "last_report", "notification", "event_log", "tutorial_state", "grid", "development", "ledger"]
var error_message := ""

func write(session: GameSession, path: String = PATH) -> bool:
	var bytes := var_to_bytes(session.to_data())
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		error_message = "保存できませんでした。"
		return false
	file.store_pascal_string(MAGIC)
	file.store_pascal_string(bytes.hex_encode().sha256_text())
	file.store_32(bytes.size())
	file.store_buffer(bytes)
	file.flush()
	var err := file.get_error()
	file.close()
	if err != OK:
		error_message = "保存できませんでした。"
		return false
	var absolute := ProjectSettings.globalize_path(path)
	var temporary := ProjectSettings.globalize_path(temp_path)
	var backup := absolute + ".bak"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(absolute, backup) != OK:
			error_message = "保存できませんでした。"
			return false
	if DirAccess.rename_absolute(temporary, absolute) != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, absolute)
		error_message = "保存できませんでした。"
		return false
	error_message = ""
	return true

func read(path: String = PATH) -> Dictionary:
	error_message = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	if file.get_length() > MAX_BYTES or file.get_pascal_string() != MAGIC:
		error_message = "保存した記録を読み込めませんでした。"
		return {}
	var checksum := file.get_pascal_string()
	var length := file.get_32()
	if length > MAX_BYTES or length > file.get_length() - file.get_position():
		error_message = "保存した記録を読み込めませんでした。"
		return {}
	var bytes := file.get_buffer(length)
	if bytes.hex_encode().sha256_text() != checksum:
		error_message = "保存した記録を読み込めませんでした。"
		return {}
	var data: Variant = bytes_to_var(bytes)
	if not _valid(data):
		error_message = "保存した記録を読み込めませんでした。"
		return {}
	return data

func _valid(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	for key in SESSION_KEYS:
		if not data.has(key):
			return false
	if data.version != 1 or not data.grid is Dictionary or not data.development is Dictionary or not data.ledger is Dictionary:
		return false
	var gd: Dictionary = data.grid
	if not gd.has_all(["width", "height", "source_cells", "initial_water", "flow", "discharge", "origin_mask"]):
		return false
	if gd.width != TerrainGenerator.SIZE or gd.height != TerrainGenerator.SIZE:
		return false
	var count: int = gd.width * gd.height
	for key in ["elevation", "water", "peak_depth", "initial_water", "discharge"]:
		if not gd.has(key) or not gd[key] is PackedFloat64Array or gd[key].size() != count:
			return false
		for value in gd[key]:
			if not is_finite(value) or (key != "elevation" and value < 0.0):
				return false
	for key in ["river", "sea", "lake", "origin_mask"]:
		if not gd.has(key) or not gd[key] is PackedByteArray or gd[key].size() != count:
			return false
	if not gd.flow is PackedVector2Array or gd.flow.size() != count or not gd.source_cells is PackedInt32Array or gd.source_cells.size() != 3:
		return false
	for cell in gd.source_cells:
		if cell < 0 or cell >= count:
			return false
	var dev: Dictionary = data.development
	if not dev.has_all(["houses", "current_wet", "previous_wet", "current_seconds", "previous_seconds", "observing", "next_id", "eligible", "patches"]):
		return false
	if not dev.houses is Array or not dev.eligible is PackedByteArray or dev.eligible.size() != count or not dev.patches is PackedInt32Array:
		return false
	for key in ["current_wet", "previous_wet"]:
		if not dev[key] is PackedFloat64Array or dev[key].size() != count:
			return false
	if dev.has("assessed_fraction") and (not dev.assessed_fraction is PackedFloat64Array or dev.assessed_fraction.size() != count or not dev.has("assessed_seconds")):
		return false
	for house in dev.houses:
		if not house is Dictionary or not house.has_all(["id", "anchor", "cells", "population", "built_turn", "growth_turn"]):
			return false
		if not house.cells is PackedInt32Array or house.cells.size() != 12 or house.population < 0 or house.population > 4:
			return false
		for cell in house.cells:
			if cell < 0 or cell >= count:
				return false
	if not data.ledger.has_all(["initial_water", "rain_added", "inflow_added", "drained", "evaporated"]):
		return false
	return data.phase in [0, 1, 2, 3] and data.speed in [1, 2, 4] and data.weather in [0, 1, 2, 3] and data.turn >= 0 and data.power >= 0 and data.event_log is Array
