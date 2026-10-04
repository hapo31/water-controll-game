extends Control

func _ready() -> void:
	custom_minimum_size = Vector2(72, 44)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	for n in 2:
		var x := 7.0 + n * 29.0
		var points := PackedVector2Array([Vector2(x, 5), Vector2(x + 24, 22), Vector2(x, 39)])
		var shadow := points.duplicate()
		for i in shadow.size():
			shadow[i] += Vector2(2, 2)
		draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.55))
		draw_colored_polygon(points, Color("f0e7cf"))
