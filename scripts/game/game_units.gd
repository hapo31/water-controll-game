class_name GameUnits
extends RefCounted

# One horizontal cell and one vertical terrain unit both represent 100 cm.
const HEIGHT_CM := 100.0
const CELL_AREA_CM2 := 10000.0
const VOLUME_CM3 := HEIGHT_CM * CELL_AREA_CM2
const WET_DEPTH := 0.01 # 1 cm; excludes the solver's numerical water film.
const REWARD_DEPTH := 0.5
const LOSS_DEPTH := 1.0
const BASE_INFLOW := 1.8 # 600,000 cm³/s at each of three inlets.

static func depth_cm(depth: float) -> float:
	return depth * HEIGHT_CM

static func flow_cm3(rate: float) -> float:
	return rate * VOLUME_CM3
