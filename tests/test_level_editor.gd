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
	_test_solid_shapes()
	_test_echo_metadata()
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

func _test_solid_shapes() -> void:
	var document := Document.new()
	for kind: String in Document.Polytopes.TYPES:
		var index: int = document.add_shape(kind, "solid")
		_expect(document.shape_at(index).representation == "solid" and document.object_name(index).begins_with("Solid "), "Adding solid %s keeps its representation and visible label" % kind)
	var solid: int = 2 + document.level.boxes.size()
	document.level.solution = [document.level.start, document.level.goal]
	var saved_route := document.level.solution.duplicate()
	document.set_shape_representation(solid, "edges")
	_expect(document.shape_at(solid).representation == "edges" and document.level.solution.is_empty(), "Changing representation invalidates the recorded route")
	document.undo()
	_expect(document.shape_at(solid).representation == "solid" and document.level.solution == saved_route, "Undo restores the solid and its recorded route")
	document.redo()
	_expect(document.shape_at(solid).representation == "edges", "Redo restores an edge frame")
	document.set_shape_representation(solid, "solid")
	var duplicate: int = document.duplicate_object(solid)
	document.set_shape_representation(duplicate, "edges")
	_expect(document.shape_at(solid).representation == "solid" and document.shape_at(duplicate).representation == "edges", "A duplicated solid has an independent representation")
	_expect(document.save_level(TEST_PATH) == OK, "All six solids save alongside an edge frame")
	var reopened := Document.new()
	_expect(reopened.open_level(TEST_PATH) == OK and reopened.level.to_dictionary() == document.level.to_dictionary(), "Mixed solid and frame representations survive a save and reopen")
	var before: Dictionary = document.level.to_dictionary()
	document.set_shape_representation(solid, "unsupported")
	_expect(document.level.to_dictionary() == before and document.add_shape("tesseract", "unsupported") == -1, "Unsupported representations cannot be authored")
	document.shape_at(solid).representation = "unsupported"
	_expect(document.save_level(TEST_PATH) == ERR_INVALID_DATA, "An invalid representation cannot overwrite the saved level")
	var legacy := Document.new()
	_expect(legacy.open_level("res://levels/samples/tesseract.tres") == OK and legacy.level.shapes[0].representation == "edges", "Existing shape resources default to edge frames")


func _test_echo_metadata() -> void:
	var document := Document.new()
	_expect(document.open_level("res://levels/04_the_fourfold_labyrinth.tres") == OK, "The labyrinth opens in the level editor")
	var original: Dictionary = document.level.to_dictionary()
	var echo: int = 2 + document.level.boxes.size() + document.level.shapes.size()
	var position: Vector4 = document.object_position(echo)
	var checkpoint: Vector4 = document.level.echo_checkpoints[0]
	var delta := Vector4(0.5, 0.8, -0.5, 1.0)
	document.set_position(echo, position + delta, true)
	document.set_position(echo, position + delta * 2.0, true)
	_expect(document.level.echo_checkpoints[0].is_equal_approx(checkpoint + delta * 2.0), "Moving an echo shifts its checkpoint by the same four-dimensional delta")
	_expect((document.level.seeds[0] - document.level.echo_checkpoints[0]).is_equal_approx(position - checkpoint), "Moving an echo preserves the checkpoint's feet offset")
	document.undo()
	_expect(document.level.to_dictionary() == original, "Undo restores the entire merged echo move and its checkpoint")
	document.redo()
	_expect(document.level.echo_checkpoints[0].is_equal_approx(checkpoint + delta * 2.0), "Redo restores the moved checkpoint with its echo")
	var added: int = document.add_object("echo")
	_expect(document.level.echo_names[-1] == "Echo 6" and document.level.echo_checkpoints[-1] == Vector4.ZERO, "Adding an echo supplies a name and checkpoint beneath its floating center")
	_expect(document.level.validation_errors().is_empty(), "Adding a named echo keeps the resource valid")
	var before_duplicate: Dictionary = document.level.to_dictionary()
	var duplicate: int = document.duplicate_object(echo)
	_expect(document.level.echo_names[-1] == document.level.echo_names[0] + " (copy)", "Duplicating an echo retains its name with a copy suffix")
	_expect(document.level.echo_checkpoints[-1].is_equal_approx(document.level.echo_checkpoints[0] + Vector4(1, 0, 0, 0)), "Duplicating an echo offsets its checkpoint with its position")
	document.undo()
	_expect(document.level.to_dictionary() == before_duplicate, "Undo removes an echo duplicate and both metadata entries")
	document.redo()
	_expect(document.level.validation_errors().is_empty() and duplicate == document.object_count() - 1, "Redo restores a valid echo duplicate with paired metadata")
	var before_delete: Dictionary = document.level.to_dictionary()
	document.delete_object(added)
	_expect(document.level.echo_names.size() == document.level.seeds.size() and document.level.echo_checkpoints.size() == document.level.seeds.size(), "Deleting an echo keeps both metadata arrays paired")
	_expect(document.level.echo_names[-1] == document.level.echo_names[0] + " (copy)", "Deleting a middle echo preserves the next echo's metadata")
	document.undo()
	_expect(document.level.to_dictionary() == before_delete, "Undo restores a deleted echo and its metadata")
	document.redo()
	_expect(document.save_level(TEST_PATH) == OK, "The edited labyrinth saves after echo operations")
	var reopened := Document.new()
	_expect(reopened.open_level(TEST_PATH) == OK and reopened.level.to_dictionary() == document.level.to_dictionary(), "Edited echo names and checkpoints survive saving and reopening")
	for names_enabled: bool in [false, true]:
		for checkpoints_enabled: bool in [false, true]:
			var legacy := Document.new()
			if names_enabled:
				legacy.level.echo_names = ["First"]
			if checkpoints_enabled:
				legacy.level.echo_checkpoints = [Vector4.ZERO]
			var new_echo: int = legacy.add_object("echo")
			var cloned_echo: int = legacy.duplicate_object(new_echo)
			legacy.set_position(cloned_echo, Vector4(2.0, 1.85, 1.0, 2.0))
			legacy.delete_object(new_echo)
			_expect(legacy.level.echo_names.is_empty() == not names_enabled and legacy.level.echo_checkpoints.is_empty() == not checkpoints_enabled and legacy.level.validation_errors().is_empty(), "Echo metadata stays optional and independent (names %s, checkpoints %s)" % [names_enabled, checkpoints_enabled])


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
	document.set_shape_representation(frame, "solid")
	_expect(canvas._hit_test(interior) == frame, "A solid's projected interior selects the complete shape")
	_expect(canvas._shape_polygon(frame, true).size() == 4, "A tesseract solid has a filled square projection in its central slice")
	canvas.slice_position = 3.0
	_expect(canvas._shape_polygon(frame, true).is_empty(), "A solid outside the slice has no highlighted filled projection")
	_expect(canvas._hit_test(interior) == frame, "A dimmed solid remains selectable for repositioning")
	canvas.slice_position = 0.0
	canvas.vertical_axis = 3
	_expect(canvas._shape_polygon(frame, true).size() == 4, "Solid slice projection also works in XW view")
	canvas.vertical_axis = 2
	_drag(canvas, interior, interior + Vector2(36.0, -36.0))
	_expect(document.object_position(frame).is_equal_approx(Vector4(10.0, 1.5, 1.0, 0.0)), "Dragging a solid interior moves its whole shape")
	document.undo()
	_expect(document.object_position(frame).is_equal_approx(Vector4(9.0, 1.5, 0.0, 0.0)), "A solid interior drag is one undo operation")
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
