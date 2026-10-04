extends "res://tests/test_game.gd"

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://work/game")
	_test_phase_and_weather()
	_test_brush()
	_test_report()
	_test_development()
	_test_origins()
	_test_saves()
	print("GAME_RULES_RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
