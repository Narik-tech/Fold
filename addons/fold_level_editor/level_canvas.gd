@tool
extends Control
## Top-down projection. Dragging is a preview until released, then one edit.

signal object_selected(index: int)
signal object_moved(index: int, position: Vector4)

const Document = preload("res://addons/fold_level_editor/level_document.gd")
const Polytopes = preload("res://scripts/polytope_geometry.gd")
const BACKGROUND := Color("15242d")
const GRID_COLOR := Color("243942")
const TEXT_COLOR := Color("c7e1df")

var document: RefCounted
var selection := 0
var vertical_axis := 2
var slice_position := 0.0
var snap_step := 0.25
var zoom := 36.0
var view_center := Vector2.ZERO
var _dragging := false
var _panning := false
var _drag_position := Vector4.ZERO
var _drag_offset := Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(300.0, 300.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_CROSS


func set_document(value: RefCounted) -> void:
	document = value
	queue_redraw()


func hidden_axis() -> int:
	return 3 if vertical_axis == 2 else 2


func world_to_canvas(point: Vector2) -> Vector2:
	return size * 0.5 + Vector2(point.x - view_center.x, -point.y + view_center.y) * zoom


func canvas_to_world(point: Vector2) -> Vector2:
	var local := (point - size * 0.5) / zoom
	return view_center + Vector2(local.x, -local.y)


func fit_level() -> void:
	if document == null:
		return
	var bounds := Rect2()
	for index in document.object_count():
		var position: Vector4 = document.object_position(index)
		var dimensions: Vector4 = document.object_size(index)
		var center := Vector2(position.x, position[vertical_axis])
		var extent := Vector2(dimensions.x, dimensions[vertical_axis])
		var rect := Rect2(center - extent * 0.5, extent)
		bounds = rect if index == 0 else bounds.merge(rect)
	view_center = bounds.get_center()
	zoom = clampf(minf((size.x - 70.0) / maxf(bounds.size.x, 2.0), (size.y - 70.0) / maxf(bounds.size.y, 2.0)), 8.0, 120.0)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	_draw_grid()
	if document == null:
		return
	# Floors first; markers last so that small objects remain visible/selectable.
	for index in range(2, 2 + document.level.boxes.size()):
		_draw_object(index)
	for index in range(2 + document.level.boxes.size(), document.object_count()):
		_draw_object(index)
	_draw_object(0)
	_draw_object(1)
	if selection >= 0 and selection < document.object_count():
		_draw_object(selection, true)
	var font := get_theme_default_font()
	var axis := "Z" if vertical_axis == 2 else "W"
	var hidden := "W" if hidden_axis() == 3 else "Z"
	draw_string(font, Vector2(14, 24), "X →   %s ↑     slice %s = %.2f" % [axis, hidden, slice_position], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, TEXT_COLOR)
	draw_string(font, Vector2(14, size.y - 14), "Dimmed = outside slice • labels show Y height", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT_COLOR.darkened(0.25))


func _draw_grid() -> void:
	var corner_a := canvas_to_world(Vector2.ZERO)
	var corner_b := canvas_to_world(size)
	var spacing := 1.0 if zoom >= 18.0 else 5.0
	for x in range(int(floor(corner_a.x / spacing)), int(ceil(corner_b.x / spacing)) + 1):
		var screen := world_to_canvas(Vector2(x * spacing, 0.0)).x
		draw_line(Vector2(screen, 0.0), Vector2(screen, size.y), GRID_COLOR, 1.0)
	for y in range(int(floor(corner_b.y / spacing)), int(ceil(corner_a.y / spacing)) + 1):
		var screen := world_to_canvas(Vector2(0.0, y * spacing)).y
		draw_line(Vector2(0.0, screen), Vector2(size.x, screen), GRID_COLOR, 1.0)
	var origin := world_to_canvas(Vector2.ZERO)
	draw_line(Vector2(origin.x, 0.0), Vector2(origin.x, size.y), Color("41616a"), 1.0)
	draw_line(Vector2(0.0, origin.y), Vector2(size.x, origin.y), Color("41616a"), 1.0)


func _object_color(index: int) -> Color:
	if index == 0:
		return Color("72d5ca")
	if index == 1:
		return Color("f2be69")
	if document.is_shape(index):
		return Color("79d8ed")
	if not document.is_box(index):
		return Color("c4a0ff")
	match document.level.boxes[index - 2].kind:
		"wall": return Color("d07c80")
		"bridge": return Color("69b4d2")
		"step": return Color("b6b88a")
	return Color("66858d")


func _object_position(index: int) -> Vector4:
	return _drag_position if _dragging and index == selection else document.object_position(index)


func _object_rect(index: int) -> Rect2:
	var position := _object_position(index)
	var dimensions: Vector4 = document.object_size(index)
	var center := world_to_canvas(Vector2(position.x, position[vertical_axis]))
	var extent := Vector2(dimensions.x, dimensions[vertical_axis]) * zoom
	return Rect2(center - extent * 0.5, extent)


func _draw_object(index: int, selected_outline: bool = false) -> void:
	if document.is_shape(index):
		_draw_shape(index, selected_outline)
		return
	var position := _object_position(index)
	var dimensions: Vector4 = document.object_size(index)
	var in_slice := absf(position[hidden_axis()] - slice_position) <= dimensions[hidden_axis()] * 0.5
	var color := _object_color(index)
	var rect := _object_rect(index)
	var center := rect.get_center()
	if selected_outline:
		if document.is_box(index):
			draw_rect(rect.grow(3.0), Color.WHITE, false, 2.0)
		else:
			draw_arc(center, 13.0, 0.0, TAU, 32, Color.WHITE, 2.0, true)
		return
	if document.is_box(index):
		draw_rect(rect, Color(color, 0.36 if in_slice else 0.055))
		draw_rect(rect, Color(color, 0.9 if in_slice else 0.22), false, 1.5)
	else:
		draw_circle(center, 8.0, Color(color, 1.0 if in_slice else 0.3), true, -1.0, true)
		draw_circle(center, 10.0, Color(color, 1.0 if in_slice else 0.3), false, 1.0, true)
	var text := "%s  Y %.2f" % [document.object_name(index), position.y]
	var text_position := rect.position + Vector2(5.0, 17.0) if document.is_box(index) else center + Vector2(14.0, 5.0)
	draw_string(get_theme_default_font(), text_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(TEXT_COLOR, 1.0 if in_slice else 0.36))


func _project_point(point: Vector4) -> Vector2:
	return world_to_canvas(Vector2(point.x, point[vertical_axis]))


func _shape_vertices(index: int) -> Array[Vector4]:
	var shape: FoldShape = document.shape_at(index)
	var vertices: Array[Vector4] = []
	for vertex: Vector4 in Polytopes.topology(shape.kind).vertices:
		vertices.append(_object_position(index) + vertex * shape.scale)
	return vertices


func _slice_segment(a: Vector4, b: Vector4, thickness: float) -> PackedFloat32Array:
	# Clip the edge's centerline to the current hidden-axis slab. The complete
	# wireframe stays dimly visible so its connectivity is legible in both views.
	var hidden := hidden_axis()
	var delta := b[hidden] - a[hidden]
	var half := thickness * 0.5
	if absf(delta) < 0.000001:
		return PackedFloat32Array([0.0, 1.0]) if absf(a[hidden] - slice_position) <= half else PackedFloat32Array()
	var first := (slice_position - half - a[hidden]) / delta
	var last := (slice_position + half - a[hidden]) / delta
	var lower := maxf(0.0, minf(first, last))
	var upper := minf(1.0, maxf(first, last))
	return PackedFloat32Array([lower, upper]) if lower <= upper else PackedFloat32Array()


func _draw_shape(index: int, selected_outline: bool) -> void:
	var shape: FoldShape = document.shape_at(index)
	var vertices := _shape_vertices(index)
	var color := Color.WHITE if selected_outline else _object_color(index)
	var width := 2.8 if selected_outline else 1.5
	for edge: Vector2i in Polytopes.topology(shape.kind).edges:
		var a: Vector4 = vertices[edge.x]
		var b: Vector4 = vertices[edge.y]
		draw_line(_project_point(a), _project_point(b), Color(color, 0.24 if selected_outline else 0.18), width, true)
		var interval := _slice_segment(a, b, shape.edge_thickness)
		if not interval.is_empty():
			draw_line(_project_point(a.lerp(b, interval[0])), _project_point(a.lerp(b, interval[1])), Color(color, 0.95), width, true)
	var center := _project_point(_object_position(index))
	draw_circle(center, 10.0 if selected_outline else 5.0, Color(color, 0.95), false, 1.5, true)
	if not selected_outline:
		var text := "%s  Y %.2f" % [document.object_name(index), _object_position(index).y]
		draw_string(get_theme_default_font(), center + Vector2(14.0, -12.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT_COLOR)


func _hit_test(point: Vector2) -> int:
	# Markers take precedence, followed by actual frame edges or their center
	# handles. Empty projected interiors never act like filled shape hit boxes.
	for index in document.object_count():
		if not document.is_box(index) and not document.is_shape(index):
			if point.distance_to(_object_rect(index).get_center()) <= 15.0:
				return index
	var shape_hit := -1
	var nearest := INF
	for index in range(2 + document.level.boxes.size(), 2 + document.level.boxes.size() + document.level.shapes.size()):
		var distance := point.distance_to(_project_point(_object_position(index)))
		var vertices := _shape_vertices(index)
		var shape: FoldShape = document.shape_at(index)
		for edge: Vector2i in Polytopes.topology(shape.kind).edges:
			var closest := Geometry2D.get_closest_point_to_segment(point, _project_point(vertices[edge.x]), _project_point(vertices[edge.y]))
			distance = minf(distance, point.distance_to(closest))
		if distance <= 8.0 and distance < nearest:
			shape_hit = index
			nearest = distance
	if shape_hit >= 0:
		return shape_hit
	# Smallest hit wins among boxes so floor volumes cannot hide walls/steps.
	var found := -1
	var area := INF
	for index in document.object_count():
		if not document.is_box(index):
			continue
		var rect := _object_rect(index)
		if rect.grow(3.0).has_point(point) and rect.get_area() < area:
			found = index
			area = rect.get_area()
	return found


func _gui_input(event: InputEvent) -> void:
	if document == null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				var anchor := canvas_to_world(event.position)
				zoom = clampf(zoom * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 8.0, 180.0)
				view_center += anchor - canvas_to_world(event.position)
				queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var hit := _hit_test(event.position)
				if hit >= 0:
					selection = hit
					object_selected.emit(hit)
					_drag_position = document.object_position(hit)
					_drag_offset = Vector2(_drag_position.x, _drag_position[vertical_axis]) - canvas_to_world(event.position)
					_dragging = true
			elif _dragging:
				_dragging = false
				object_moved.emit(selection, _drag_position)
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion:
		if _panning:
			view_center += Vector2(-event.relative.x, event.relative.y) / zoom
			queue_redraw()
		elif _dragging:
			var point := canvas_to_world(event.position) + _drag_offset
			if snap_step > 0.0:
				point = point.snapped(Vector2.ONE * snap_step)
			_drag_position.x = point.x
			_drag_position[vertical_axis] = point.y
			queue_redraw()
