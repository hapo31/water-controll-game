class_name GameWorldView
extends WorldView

var development: DevelopmentSystem
var eligibility_texture: ImageTexture

func _ready() -> void:
	super._ready()
	physical_units = true

func _upload_state() -> void:
	super._upload_state()
	if development == null:
		return
	var mask := Image.create_from_data(grid.width, grid.height, false, Image.FORMAT_R8, development.eligible)
	if eligibility_texture == null:
		eligibility_texture = ImageTexture.create_from_image(mask)
		water_material.set_shader_parameter("settlement_mask", eligibility_texture)
	else:
		eligibility_texture.update(mask)
	water_material.set_shader_parameter("show_settlement", true)

func _draw() -> void:
	super._draw()
	if grid == null or development == null:
		return
	for house in development.houses:
		_draw_house(house)

func _draw_house(house: Dictionary) -> void:
	var cell: int = house.anchor
	var x := cell % grid.width
	var y := cell / grid.width
	var z := grid.elevation[cell]
	var base := PackedVector2Array([project(x, y, z) + Vector2(0, -HALF_H),
		project(x + 2, y, z) + Vector2(HALF_W, 0),
		project(x + 2, y + 3, z) + Vector2(0, HALF_H),
		project(x, y + 3, z) + Vector2(-HALF_W, 0)])
	var roof := base.duplicate()
	for n in roof.size():
		roof[n] -= Vector2(0, 22)
	var inhabited: bool = house.population > 0
	draw_colored_polygon(PackedVector2Array([roof[1], roof[2], base[2], base[1]]), Color("c9b890") if inhabited else Color("777f77"))
	draw_colored_polygon(PackedVector2Array([roof[2], roof[3], base[3], base[2]]), Color("a7916d") if inhabited else Color("5e6963"))
	draw_colored_polygon(roof, Color("634e44") if inhabited else Color("59665e"))
	draw_line(roof[0], roof[2], Color("948577"), 2.0)
	var center := (roof[0] + roof[2]) * 0.5
	var scale := 1.0 / get_global_transform_with_canvas().get_scale().x
	draw_circle(center - Vector2(0, 11) * scale, 12 * scale, Color("172a29"))
	draw_string(ThemeDB.fallback_font, center + Vector2(-5, -6) * scale,
		str(house.population), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(15 * scale), Color("f4ead2"))
