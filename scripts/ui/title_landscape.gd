extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0d2125"))
	var center := Vector2(size.x * 0.5, size.y * 0.66)
	var tile := Vector2(27, 13)
	for diagonal in 36:
		for x in range(maxi(0, diagonal - 17), mini(17, diagonal) + 1):
			var y := diagonal - x
			var river := absf(x - (8.0 + sin(y * 0.4) * 2.0)) < 1.5
			var height := (17 - y) * 3.0 + sin(x * 0.38) * 14.0
			var p := center + Vector2((x - y) * tile.x, (x + y - 18) * tile.y - height)
			var polygon := PackedVector2Array([p + Vector2(0, -tile.y), p + Vector2(tile.x, 0), p + Vector2(0, tile.y), p - Vector2(tile.x, 0)])
			var shade := 0.04 * sin(x * 2.0 + y)
			draw_colored_polygon(polygon, Color(0.17 + shade, 0.33 + shade, 0.27 + shade, 0.65) if not river else Color(0.15, 0.49, 0.55, 0.8))
			draw_polyline(PackedVector2Array([polygon[1], polygon[2], polygon[3]]), Color(0.07, 0.17, 0.18, 0.5), 1.0)
