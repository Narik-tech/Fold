extends SceneTree
## Exercises the document transaction boundary and actual canvas input handlers.

const Document = preload("res://addons/fold_level_editor/level_document.gd")
const Canvas = preload("res://addons/fold_level_editor/level_canvas.gd")
const TEST_PATH := "res://test-output/fold_editor_regression.tres"
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var document := Document.new()
	_expect(document.level.validation_errors().is_empty(), "New document is immediately playable")
	_expect(document.save_level(TEST_PATH) == OK and not document.is_dirty(), "Save establishes a clean baseline")
	document.set_metadata(&"title", "My custom garden")
	document.set_metadata(&"title", "My custom garden!")
	_expect(document.is_dirty(), "Text edits mark the document dirty")
	document.undo()
	_expect(not document.is_dirty(), "Undo merges a text edit and returns to the saved state")
	document.redo()
	_expect(document.level.title == "My custom garden!", "Redo restores authored text")
	var wall: int = document.add_object("wall")
	document.set_position(wall, Vector4(1.0, 1.5, 0.0, 2.0))
	var duplicate: int = document.duplicate_object(wall)
	document.set_size(duplicate, Vector4(1.0, 4.0, 5.0, 2.0))
	_expect(document.object_size(wall) != document.object_size(duplicate), "Duplicated boxes are independent resources")
	var count: int = document.object_count()
	document.delete_object(duplicate)
	_expect(document.object_count() == count - 1, "Delete removes a selected object")
	document.undo()
	_expect(document.object_count() == count, "Undo restores deleted geometry")
	document.redo()
	_expect(document.object_count() == count - 1, "Redo reapplies deletion")
	document.delete_object(0)
	document.delete_object(1)
	_expect(document.object_count() == count - 1, "Start and goal cannot be deleted")
	_expect(document.save_level(TEST_PATH) == OK, "Authored geometry saves")
	var reopened := Document.new()
	_expect(reopened.open_level(TEST_PATH) == OK, "Saved document reopens")
	_expect(reopened.level.to_dictionary() == document.level.to_dictionary(), "Reopening preserves the full document")
	document.set_size(2, Vector4.ZERO)
	_expect(document.save_level(TEST_PATH) == ERR_INVALID_DATA, "Invalid edit cannot overwrite a valid file")
	var intact := Document.new()
	intact.open_level(TEST_PATH)
	_expect(intact.level.to_dictionary() == reopened.level.to_dictionary(), "Rejected save preserves existing contents")
	var previous: Dictionary = reopened.level.to_dictionary()
	_expect(reopened.open_level("res://test-output/fold_editor_missing_file.tres") != OK, "Missing files fail safely")
	_expect(reopened.level.to_dictionary() == previous, "Failed open preserves the active document")
	var shared_source: FoldLevel = FoldLevel.create_default()
	shared_source.boxes.append(shared_source.boxes[0])
	var independent := Document.new()
	independent.set_level(shared_source)
	var old_center: Vector4 = shared_source.boxes[0].center
	independent.set_position(2, old_center + Vector4(1, 0, 0, 0))
	_expect(shared_source.boxes[0].center == old_center and independent.object_position(3) == old_center, "Editing one list item isolates both its source and aliased boxes")
	independent.undo()
	_expect(independent.object_position(2) == old_center, "History restores the independent box copy")
	_test_shapes()
	await _test_canvas()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	print("%s: %d level-editor checks." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _test_shapes() -> void:
	var document := Document.new()
	var original_echo: Vector4 = document.level.seeds[0]
	for kind: String in Document.Polytopes.TYPES:
		var index: int = document.add_shape(kind)
		_expect(document.is_shape(index) and document.shape_at(index).kind == kind, "Adding %s selects one complete frame" % kind)
	_expect(document.object_name(document.object_count() - 1) == "Echo 1" and document.object_position(document.object_count() - 1) == original_echo, "Shapes retain echo names and positions after shifted selection IDs")
	var frame: int = 2 + document.level.boxes.size()
	document.set_shape_scale(frame, 6.75)
	document.set_edge_thickness(frame, 0.125)
	var position := Vector4(3.25, 2.0, -1.0, 1.5)
	document.set_position(frame, position)
	_expect(document.shape_at(frame).center == position and is_equal_approx(document.shape_at(frame).scale, 6.75), "Frame position and uniform scale are authored independently")
	var clone: int = document.duplicate_object(frame)
	document.set_shape_scale(clone, 8.5)
	_expect(document.shape_at(clone).center == position + Vector4(1, 0, 0, 0) and is_equal_approx(document.shape_at(frame).scale, 6.75), "Duplicating a frame makes an independent offset resource")
	document.undo()
	_expect(is_equal_approx(document.shape_at(clone).scale, 6.75), "Undo restores a whole frame's scale")
	document.redo()
	_expect(is_equal_approx(document.shape_at(clone).scale, 8.5), "Redo reapplies frame scale")
	document.delete_object(clone)
	_expect(document.level.shapes.size() == 6 and document.level.seeds[0] == original_echo, "Deleting a frame preserves echoes")
	document.undo()
	_expect(document.level.shapes.size() == 7, "Undo restores a deleted frame")
	var echo: int = document.object_count() - 1
	document.set_position(echo, original_echo + Vector4(0, 0, 0, 2))
	_expect(document.level.seeds[0].w == original_echo.w + 2, "Echo movement uses its shifted index after adding frames")
	_expect(document.save_level(TEST_PATH) == OK, "All six frame kinds save in one resource")
	var reopened := Document.new()
	_expect(reopened.open_level(TEST_PATH) == OK and reopened.level.to_dictionary() == document.level.to_dictionary(), "Frame kinds, centers, scales, and thicknesses survive saving and reopening")
	document.set_shape_scale(frame, -1.0)
	_expect(document.save_level(TEST_PATH) == ERR_INVALID_DATA, "Invalid frame scale cannot overwrite a saved level")
	var source: FoldLevel = reopened.level
	source.shapes.append(source.shapes[0])
	var independent := Document.new()
	independent.set_level(source)
	independent.set_position(frame, Vector4.ZERO)
	_expect(source.shapes[0].center == position and independent.level.shapes[-1].center == position, "Editing aliased frame resources isolates the source and every list entry")
	var previous_count: int = independent.object_count()
	_expect(independent.add_shape("unsupported") == -1 and independent.object_count() == previous_count, "An unknown frame kind does not create an invalid object")

func _test_canvas() -> void:
	var document := Document.new()
	document.set_position(0, Vector4(-3.0, 1.25, 1.1, 2.25))
	var canvas: Control = Canvas.new()
	root.add_child(canvas)
	canvas.size = Vector2(800, 600)
	canvas.set_document(document)
	canvas.object_moved.connect(func(index: int, position: Vector4) -> void: document.set_position(index, position))
	await process_frame
	var start: Vector2 = canvas.world_to_canvas(Vector2(-3.0, 1.1))
	_expect(canvas._hit_test(start) == 0, "Start marker is selectable above the floor")
	_drag(canvas, start, canvas.world_to_canvas(Vector2(-1.12, 2.12)))
	_expect(document.level.start.is_equal_approx(Vector4(-1.0, 1.25, 2.0, 2.25)), "XZ drag snaps and preserves Y and hidden W")
	document.undo()
	_expect(document.level.start.is_equal_approx(Vector4(-3.0, 1.25, 1.1, 2.25)), "A whole canvas drag is one undo operation")
	document.redo()
	canvas.vertical_axis = 3
	start = canvas.world_to_canvas(Vector2(-1.0, 2.25))
	_drag(canvas, start, canvas.world_to_canvas(Vector2(1.12, 3.12)))
	_expect(document.level.start.is_equal_approx(Vector4(1.0, 1.25, 2.0, 3.0)), "XW drag changes W while preserving hidden Z and Y")
	var test_point := Vector2(-4.6, 2.35)
	_expect(canvas.canvas_to_world(canvas.world_to_canvas(test_point)).is_equal_approx(test_point), "Projection coordinates round-trip")
	var frame: int = document.add_shape("tesseract")
	document.set_position(frame, Vector4(9.0, 1.5, 0.0, 0.0))
	document.set_shape_scale(frame, 4.0)
	canvas.vertical_axis = 2
	_expect(canvas._shape_vertices(frame).size() == 16, "Canvas uses the actual tesseract vertices")
	var edge_point: Vector2 = canvas.world_to_canvas(Vector2(11.0, 1.0))
	_expect(canvas._hit_test(edge_point) == frame, "Projected frame edges select the complete shape")
	var interior: Vector2 = canvas.world_to_canvas(Vector2(10.0, 1.0))
	_expect(canvas._hit_test(interior) == -1, "An open frame interior is not a filled rectangle hit target")
	_drag(canvas, edge_point, edge_point + Vector2(36.0, -36.0))
	_expect(document.object_position(frame).is_equal_approx(Vector4(10.0, 1.5, 1.0, 0.0)), "Dragging a frame edge moves its center and preserves height and hidden coordinate")
	document.undo()
	_expect(document.object_position(frame).is_equal_approx(Vector4(9.0, 1.5, 0.0, 0.0)), "Dragging a whole frame is one undo operation")
	var clipped: PackedFloat32Array = canvas._slice_segment(Vector4(0, 0, 0, -1), Vector4(0, 0, 0, 1), 0.2)
	_expect(clipped.size() == 2 and is_equal_approx(clipped[0], 0.45) and is_equal_approx(clipped[1], 0.55), "Frame slice highlighting clips to only the hidden-axis edge interval")
	canvas.queue_free()
	await process_frame

func _drag(canvas: Control, from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	canvas._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.relative = to - from
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	canvas._gui_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = to
	canvas._gui_input(release)

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
