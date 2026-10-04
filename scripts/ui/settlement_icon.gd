extends Control

func _ready() -> void:
	custom_minimum_size = Vector2(34, 32)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(3, 16), Vector2(13, 6), Vector2(23, 16)]), Color("f0bb79"))
	draw_rect(Rect2(6, 16, 15, 12), Color("f0bb79"))
	draw_rect(Rect2(12, 20, 4, 8), Color("23352e"))
	draw_circle(Vector2(27, 9), 7, Color("b0d19c"))
	draw_polyline(PackedVector2Array([Vector2(23, 9), Vector2(26, 12), Vector2(31, 6)]), Color("23352e"), 2.0, true)
