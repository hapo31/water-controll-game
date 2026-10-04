class_name WorldView
extends Node2D

const HALF_W := 12.0
const HALF_H := 6.0
const HEIGHT_SCALE := 9.0
const WATER_SHADER = preload("res://scripts/view/water_surface.gdshader")
var grid: GridState:
	set(value):
		grid = value
		terrain_dirty = true
		invalidate_terrain()
var terrain_dirty := true
var state_dirty := true
var state_image: Image
var state_texture: ImageTexture
var water_material := ShaderMaterial.new()
var mesh := ArrayMesh.new()
var vertices := PackedVector2Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()
var uvs := PackedVector2Array()
var quad_uv := Vector2.ZERO
var state_data := PackedFloat32Array()
var selected := -1
var show_flow := true
var hovered := -1
var hover_fill: Polygon2D
var hover_outline: Line2D
var selection_outline: Line2D
var boundary_rate := FixedMap.INFLOW_PER_CELL
var physical_units := false

func _ready() -> void:
	water_material.shader = WATER_SHADER
	water_material.set_shader_parameter("half_tile", Vector2(HALF_W, HALF_H))
	water_material.set_shader_parameter("height_scale", HEIGHT_SCALE)
	material = water_material
	# Keep cursor redraws independent of the full terrain draw.
	selection_outline = Line2D.new()
	selection_outline.default_color = Color(1.0, 0.78, 0.35)
	selection_outline.width = 2.5
	selection_outline.antialiased = true
	selection_outline.visible = false
	add_child(selection_outline)
	hover_fill = Polygon2D.new()
	hover_fill.color = Color(1.0, 1.0, 1.0, 0.28)
	hover_fill.visible = false
	add_child(hover_fill)
	hover_outline = Line2D.new()
	hover_outline.default_color = Color.WHITE
	hover_outline.width = 2.5
	hover_outline.antialiased = true
	hover_outline.visible = false
	add_child(hover_outline)

func set_hovered(cell: int) -> void:
	hovered = cell
	update_highlights()

func update_highlights() -> void:
	if grid == null:
		return
	selection_outline.visible = selected >= 0 and selected != hovered
	if selection_outline.visible:
		selection_outline.points = _cell_outline(selected)
	hover_fill.visible = hovered >= 0
	hover_outline.visible = hovered >= 0
	if hovered >= 0:
		var polygon := _cell_polygon(hovered)
		hover_fill.polygon = polygon
		polygon.append(polygon[0])
		hover_outline.points = polygon

func _cell_polygon(cell: int) -> PackedVector2Array:
	var x := cell % grid.width
	var y := cell / grid.width
	return diamond(project(x, y, grid.surface(cell)))

func _cell_outline(cell: int) -> PackedVector2Array:
	var polygon := _cell_polygon(cell)
	polygon.append(polygon[0])
	return polygon

func project(x: int, y: int, elevation: float) -> Vector2:
	return Vector2((x - y) * HALF_W, (x + y) * HALF_H - elevation * HEIGHT_SCALE)

func diamond(center: Vector2) -> PackedVector2Array:
	return PackedVector2Array([center + Vector2(0, -HALF_H), center + Vector2(HALF_W, 0),
		center + Vector2(0, HALF_H), center + Vector2(-HALF_W, 0)])

func invalidate_terrain() -> void:
	invalidate_state()

func invalidate_state() -> void:
	state_dirty = true
	queue_redraw()

func _draw() -> void:
	if grid == null:
		return
	if terrain_dirty:
		_rebuild_mesh()
	if state_dirty:
		_upload_state()
		state_dirty = false
	draw_mesh(mesh, null)
	var source_group := PackedInt32Array()
	for cell in grid.source_cells:
		if not source_group.is_empty() and cell > source_group[-1] + 1:
			_draw_boundary(source_group, "流入", boundary_rate, Color(0.35, 1.0, 0.85))
			source_group.clear()
		source_group.append(cell)
	if not source_group.is_empty():
		_draw_boundary(source_group, "流入", boundary_rate, Color(0.35, 1.0, 0.85))
	for marker in grid.landmarks:
		_draw_marker(marker.cell.x, marker.cell.y, marker.label, Color(0.96, 0.92, 0.72))
func _rebuild_mesh() -> void:
	vertices.clear()
	colors.clear()
	indices.clear()
	uvs.clear()
	for diagonal in range(grid.width + grid.height - 1):
		for x in range(maxi(0, diagonal - grid.height + 1), mini(grid.width - 1, diagonal) + 1):
			_build_cell(x, diagonal - x)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	terrain_dirty = false

func _upload_state() -> void:
	if state_image == null or state_image.get_width() != grid.width or state_image.get_height() != grid.height:
		state_image = Image.create(grid.width, grid.height, false, Image.FORMAT_RGBAF)
		state_texture = ImageTexture.create_from_image(state_image)
		water_material.set_shader_parameter("cell_state", state_texture)
		water_material.set_shader_parameter("grid_size", Vector2(grid.width, grid.height))
	var max_surface := 0.0
	var count := grid.water.size()
	state_data.resize(count * 4)
	var depths := grid.water
	var heights := grid.elevation
	var flows := grid.flow
	var sea := grid.sea
	for i in count:
		var depth := maxf(0.0, grid.sea_level - heights[i]) if sea[i] else depths[i]
		state_data[i * 4] = depth
		state_data[i * 4 + 1] = flows[i].x
		state_data[i * 4 + 2] = flows[i].y
		state_data[i * 4 + 3] = heights[i]
		max_surface = maxf(max_surface, heights[i] + depth)
	state_image.set_data(grid.width, grid.height, false, Image.FORMAT_RGBAF, state_data.to_byte_array())
	state_texture.update(state_image)
	water_material.set_shader_parameter("show_flow", show_flow)
	# Shader displacement must be included in culling bounds, including deep water.
	var bounds := Rect2(-grid.height * HALF_W - HALF_W, -max_surface * HEIGHT_SCALE - HALF_H - 32.0,
		(grid.width + grid.height) * HALF_W + 2.0 * HALF_W,
		(grid.width + grid.height) * HALF_H + (max_surface + 0.5) * HEIGHT_SCALE + 64.0)
	RenderingServer.canvas_item_set_custom_rect(get_canvas_item(), true, bounds)
	mesh.custom_aabb = AABB(Vector3(bounds.position.x, bounds.position.y, 0), Vector3(bounds.size.x, bounds.size.y, 0.1))

func _build_cell(x: int, y: int) -> void:
	var i := grid.index(x, y)
	var p := project(x, y, 0.0)
	var top := diamond(p)
	var u := (x + 0.5) / grid.width
	var v := (y + 0.5) / grid.height
	var color := Color.WHITE
	if grid.river[i]:
		color = Color(0.68, 0.80, 0.84)
	if grid.sea[i]:
		color = Color(0.78, 0.74, 0.62)
	# Vertex heights come from the state texture, including neighbouring walls.
	# Geometry is built once for the map, so held terrain edits do not rebuild it.
	quad_uv = Vector2(-4.0 - u, v)
	_append_quad(PackedVector2Array([top[1], top[2], top[2], top[1]]), color.darkened(0.32))
	uvs[uvs.size() - 2].x = -5.0 - u
	uvs[uvs.size() - 1].x = -5.0 - u
	_append_quad(PackedVector2Array([top[2], top[3], top[3], top[2]]), color.darkened(0.18))
	uvs[uvs.size() - 2].x = -6.0 - u
	uvs[uvs.size() - 1].x = -6.0 - u
	_append_quad(top, color)
	quad_uv = Vector2(-1.0 - u, v)
	_append_quad(PackedVector2Array([top[1], top[2], top[2], top[1]]), Color(0.9, 0.9, 0.9))
	uvs[uvs.size() - 2].x = -2.0 - u
	uvs[uvs.size() - 1].x = -2.0 - u
	_append_quad(top, Color.WHITE)
	if x % 3 == 0 and y % 3 == 0 and not grid.sea[i]:
		quad_uv = Vector2(-3.0 - u, v)
		var end := p + Vector2(7.0, 0.0)
		_append_line(p - Vector2(2.0, 0.0), end, Color(0.8, 0.95, 1.0, 0.85), 1.0)
		_append_line(end, end - Vector2.RIGHT.rotated(0.6) * 3.0, Color(0.8, 0.95, 1.0), 1.0)
		_append_line(end, end - Vector2.RIGHT.rotated(-0.6) * 3.0, Color(0.8, 0.95, 1.0), 1.0)
func _draw_boundary(cells: PackedInt32Array, label: String, rate: float, color: Color) -> void:
	var center := Vector2.ZERO
	var direction := Vector2(-HALF_W, HALF_H).normalized()
	for cell in cells:
		var p := project(cell % grid.width, cell / grid.width, grid.surface(cell))
		center += p
		var polygon := diamond(p)
		draw_colored_polygon(polygon, Color(color, 0.32))
		polygon.append(polygon[0])
		draw_polyline(polygon, color, 2.0, true)
		var tip := p + direction * 8.0
		draw_line(p - direction * 7.0, tip, color, 2.0, true)
		draw_line(tip, tip - direction.rotated(0.65) * 4.0, color, 2.0, true)
		draw_line(tip, tip - direction.rotated(-0.65) * 4.0, color, 2.0, true)
	center /= cells.size()
	var scale := 1.0 / get_global_transform_with_canvas().get_scale().x
	var anchor := center + Vector2(-45.0, -24.0) * scale
	if physical_units and cells.size() == 1 and grid.source_cells.find(cells[0]) == 1:
		anchor = center + Vector2(-90.0, -52.0) * scale
	draw_line(center, anchor, color, 1.5, true)
	var text := "%s  %+.1f/秒 × %dマス" % [label, rate, cells.size()]
	if physical_units:
		text = "%s  %.0f cm³/s" % [label, rate * cells.size()]
	draw_string(ThemeDB.fallback_font, anchor + Vector2(5, 0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(13 * scale), color)

func _draw_marker(x: int, y: int, text: String, color: Color) -> void:
	var p := project(x, y, grid.surface(grid.index(x, y)))
	var scale := 1.0 / get_global_transform_with_canvas().get_scale().x
	var offset := Vector2(0, -20.0) * scale
	draw_line(p, p + offset, color, scale)
	draw_circle(p, 2.0 * scale, color)
	draw_string(ThemeDB.fallback_font, p + offset + Vector2(4, 0) * scale, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(14 * scale), color)
func pick(local_point: Vector2) -> int:
	if grid == null:
		return -1
	# Height only changes screen Y. Screen X restricts candidates to at most
	# three x-y diagonals, even for tall terrain and very deep water.
	var min_difference := ceili(local_point.x / HALF_W - 1.0 - 0.00001)
	var max_difference := floori(local_point.x / HALF_W + 1.0 + 0.00001)
	if min_difference >= grid.width or max_difference <= -grid.height:
		return -1
	for diagonal in range(grid.width + grid.height - 2, -1, -1):
		for difference in range(max_difference, min_difference - 1, -1):
			if (diagonal + difference) % 2 != 0:
				continue
			var x := (diagonal + difference) / 2
			var y := diagonal - x
			if x < 0 or x >= grid.width or y < 0 or y >= grid.height:
				continue
			var i := grid.index(x, y)
			if Geometry2D.is_point_in_polygon(local_point, diamond(project(x, y, grid.surface(i)))):
				return i
	return -1

func _append_quad(points: PackedVector2Array, color: Color) -> void:
	# Keep the original cell/face order so transparent water blends correctly.
	var first := vertices.size()
	vertices.append_array(points)
	for _point in points:
		colors.append(color)
		uvs.append(quad_uv)
	indices.append_array(PackedInt32Array([first, first + 1, first + 2,
		first, first + 2, first + 3]))

func _append_line(start: Vector2, end: Vector2, color: Color, width: float) -> void:
	var offset := (end - start).orthogonal().normalized() * width * 0.5
	_append_quad(PackedVector2Array([start + offset, end + offset,
		end - offset, start - offset]), color)
