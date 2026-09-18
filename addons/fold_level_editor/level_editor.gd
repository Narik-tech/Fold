@tool
extends VBoxContainer
## UI composition. All data changes go through the injected document model;
## the canvas emits intent and never writes level data itself.

const Document = preload("res://addons/fold_level_editor/level_document.gd")
const Canvas = preload("res://addons/fold_level_editor/level_canvas.gd")
const Polytopes = preload("res://scripts/polytope_geometry.gd")
const DRAFT_PATH := "user://fold_editor_draft.tres"
const PREVIEW_PATH := "user://fold_editor_playtest.tres"

var document := Document.new()
var canvas: Control
var selection := 0
var _objects: ItemList
var _path_label: Label
var _selected_label: Label
var _status: RichTextLabel
var _undo_button: Button
var _redo_button: Button
var _delete_button: Button
var _duplicate_button: Button
var _stop_button: Button
var _restore_button: Button
var _position_fields: Array[SpinBox] = []
var _size_fields: Array[SpinBox] = []
var _size_group: VBoxContainer
var _shape_group: VBoxContainer
var _shape_kind: OptionButton
var _shape_scale: SpinBox
var _edge_thickness: SpinBox
var _shape_details: Label
var _samples_menu: MenuButton
var _metadata_fields: Dictionary = {}
var _open_dialog: FileDialog
var _save_dialog: FileDialog
var _discard_dialog: ConfirmationDialog
var _message_dialog: AcceptDialog
var _pending_action: Callable
var _refreshing := false
var _preview_pid := -1
var _draft_timer: Timer
var _slice_label: Label


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_build_toolbar()
	_build_workspace()
	_build_dialogs()
	_status = RichTextLabel.new()
	_status.custom_minimum_size.y = 66
	_status.bbcode_enabled = false
	add_child(_status)
	_draft_timer = Timer.new()
	_draft_timer.one_shot = true
	_draft_timer.wait_time = 1.5
	_draft_timer.timeout.connect(save_recovery)
	add_child(_draft_timer)
	document.changed.connect(_on_document_changed)
	_refresh_all()
	canvas.call_deferred("fit_level")
	_restore_button.visible = FileAccess.file_exists(DRAFT_PATH)


func _exit_tree() -> void:
	stop_playtest()
	if document.is_dirty():
		save_recovery()


func _button(parent: Node, text: String, action: Callable, tooltip: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label


func _build_toolbar() -> void:
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	_button(toolbar, "New", func(): _guard_changes(_new_level), "Create a playable starter platform")
	_button(toolbar, "Open…", func(): _guard_changes(_show_open), "Open a FoldLevel .tres resource; editing uses an independent copy")
	_samples_menu = MenuButton.new()
	_samples_menu.text = "4D Samples"
	_samples_menu.tooltip_text = "Open a simple playable garden for each regular 4D shape"
	for kind: String in Polytopes.TYPES:
		_samples_menu.get_popup().add_item(Document.SHAPE_LABELS[kind])
	_samples_menu.get_popup().id_pressed.connect(_open_sample)
	toolbar.add_child(_samples_menu)
	_button(toolbar, "Save", _save, "Save validated level (Ctrl+S)")
	_button(toolbar, "Save As…", _show_save_as, "Save a copy, usually in res://levels/custom/")
	_undo_button = _button(toolbar, "Undo", _undo, "Undo level edit (Ctrl+Z)")
	_redo_button = _button(toolbar, "Redo", _redo, "Redo level edit (Ctrl+Shift+Z)")
	_button(toolbar, "▶ Playtest", playtest, "Run the current valid draft in a separate game window")
	_stop_button = _button(toolbar, "■ Stop", stop_playtest)
	_stop_button.disabled = true
	_restore_button = _button(toolbar, "Restore draft", func(): _guard_changes(_restore_draft), "Recover the local draft preserved from an earlier editor session")
	_path_label = _label(self, "")
	_path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var instructions := _label(self, "Add objects → select → drag on the grid → set height Y → playtest. Wheel: zoom · middle drag: pan.")
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_workspace() -> void:
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	var objects_column := VBoxContainer.new()
	objects_column.custom_minimum_size.x = 160.0
	split.add_child(objects_column)
	_label(objects_column, "OBJECTS")
	_objects = ItemList.new()
	_objects.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_objects.item_selected.connect(_select_object)
	objects_column.add_child(_objects)
	var add_grid := GridContainer.new()
	add_grid.columns = 2
	objects_column.add_child(add_grid)
	for pair in [["+ Floor", "stone"], ["+ Wall", "wall"], ["+ Bridge", "bridge"], ["+ Step", "step"], ["+ Echo", "echo"]]:
		_button(add_grid, pair[0], _add_object.bind(pair[1]))
	_label(objects_column, "4D EDGE FRAMES")
	_shape_kind = OptionButton.new()
	for kind: String in Polytopes.TYPES:
		_shape_kind.add_item(Document.SHAPE_LABELS[kind])
	_shape_kind.select(Polytopes.TYPES.find("tesseract"))
	_shape_kind.tooltip_text = "Six regular convex 4D polytopes; only their edges are solid"
	objects_column.add_child(_shape_kind)
	_button(objects_column, "+ 4D Shape", _add_selected_shape, "Add one scalable edge frame; move, duplicate, and delete it as a single object")
	_duplicate_button = _button(objects_column, "Duplicate", _duplicate_selected)
	_delete_button = _button(objects_column, "Delete", _delete_selected, "Start and Goal are required and cannot be deleted")
	var content := HSplitContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(content)
	var viewport := VBoxContainer.new()
	viewport.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(viewport)
	var view_controls := HBoxContainer.new()
	viewport.add_child(view_controls)
	var projection := OptionButton.new()
	projection.name = "Projection"
	projection.add_item("Top view: X / Z")
	projection.add_item("Top view: X / W")
	projection.item_selected.connect(_set_projection)
	view_controls.add_child(projection)
	_button(view_controls, "Fit", func(): canvas.fit_level())
	var slice_controls := HBoxContainer.new()
	viewport.add_child(slice_controls)
	_slice_label = _label(slice_controls, "Slice W")
	var slice := _spin(slice_controls, -10000.0, 10000.0, 0.25)
	slice.value_changed.connect(func(value: float): canvas.slice_position = value; canvas.queue_redraw())
	_label(slice_controls, "Snap")
	var snap := OptionButton.new()
	for label in ["Off", "0.1", "0.25", "0.5", "1.0"]:
		snap.add_item(label)
	snap.select(2)
	snap.item_selected.connect(func(index: int): canvas.snap_step = [0.0, 0.1, 0.25, 0.5, 1.0][index])
	slice_controls.add_child(snap)
	canvas = Canvas.new()
	canvas.set_document(document)
	canvas.object_selected.connect(_select_object)
	canvas.object_moved.connect(_move_object)
	viewport.add_child(canvas)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size.x = 255.0
	content.add_child(tabs)
	_build_object_inspector(tabs)
	_build_metadata_inspector(tabs)


func _scroll_column(parent: Node, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)
	return column


func _build_object_inspector(parent: Node) -> void:
	var column := _scroll_column(parent, "Object")
	_selected_label = _label(column, "")
	_label(column, "Position / center")
	var grid := GridContainer.new()
	grid.columns = 2
	column.add_child(grid)
	for axis in 4:
		_label(grid, ["X", "Y · height", "Z", "W"][axis])
		var field := _spin(grid, -10000.0, 10000.0, 0.001)
		field.value_changed.connect(_position_changed.bind(axis))
		field.get_line_edit().focus_exited.connect(document.break_merge)
		_position_fields.append(field)
	_size_group = VBoxContainer.new()
	column.add_child(_size_group)
	_label(_size_group, "Full size / thickness")
	var size_grid := GridContainer.new()
	size_grid.columns = 2
	_size_group.add_child(size_grid)
	for axis in 4:
		_label(size_grid, ["X", "Y", "Z", "W"][axis])
		var field := _spin(size_grid, 0.001, 10000.0, 0.001)
		field.value_changed.connect(_size_changed.bind(axis))
		field.get_line_edit().focus_exited.connect(document.break_merge)
		_size_fields.append(field)
	_shape_group = VBoxContainer.new()
	column.add_child(_shape_group)
	_label(_shape_group, "Scale · center to vertex")
	_shape_scale = _spin(_shape_group, 0.001, 10000.0, 0.001)
	_shape_scale.tooltip_text = "Uniform size in all four axes; vertices lie this far from the center"
	_shape_scale.value_changed.connect(_shape_scale_changed)
	_shape_scale.get_line_edit().focus_exited.connect(document.break_merge)
	_label(_shape_group, "Edge thickness")
	_edge_thickness = _spin(_shape_group, 0.001, 10000.0, 0.001)
	_edge_thickness.tooltip_text = "Full width of each solid edge, independent of shape scale"
	_edge_thickness.value_changed.connect(_edge_thickness_changed)
	_edge_thickness.get_line_edit().focus_exited.connect(document.break_merge)
	_shape_details = _label(_shape_group, "")
	_shape_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var frame_help := _label(_shape_group, "Only edges are solid. Faces and cells are open for walking and folding through. Select any projected edge or the center handle to move the whole frame.")
	frame_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var help := _label(column, "Y is vertical in both views.\nStart / Goal: Y is feet height.\nEcho: Y is floating center.\nBox top = center Y + size Y ÷ 2.\n\nDimmed objects lie outside the chosen hidden-axis slice. Switch X/Z ↔ X/W to place them.\n\nGeometry edits clear any recorded solution route. Playtest to verify the puzzle.")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_metadata_inspector(parent: Node) -> void:
	var column := _scroll_column(parent, "Level")
	for item in [["Title", "title", false], ["Subtitle", "subtitle", false], ["Lesson", "lesson", true], ["Hints · one per line", "hints", true], ["Goal hint", "goal_hint", true]]:
		_label(column, item[0])
		var property: String = item[1]
		if item[2]:
			var edit := TextEdit.new()
			edit.custom_minimum_size.y = 92.0
			edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			edit.text_changed.connect(_metadata_changed.bind(property))
			edit.focus_exited.connect(document.break_merge)
			column.add_child(edit)
			_metadata_fields[property] = edit
		else:
			var edit := LineEdit.new()
			edit.text_changed.connect(func(_value: String): _metadata_changed(property))
			edit.focus_exited.connect(document.break_merge)
			column.add_child(edit)
			_metadata_fields[property] = edit


func _spin(parent: Node, minimum: float, maximum: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	# Arrow step is convenient, but authored coordinates may be arbitrary decimals.
	spin.rounded = false
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.custom_minimum_size.x = 100.0
	parent.add_child(spin)
	return spin


func _build_dialogs() -> void:
	_open_dialog = FileDialog.new()
	_open_dialog.title = "Open FOLD level"
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = FileDialog.ACCESS_RESOURCES
	_open_dialog.filters = PackedStringArray(["*.tres ; FOLD level resource"])
	_open_dialog.current_dir = "res://levels/"
	_open_dialog.file_selected.connect(_open_level)
	add_child(_open_dialog)
	_save_dialog = FileDialog.new()
	_save_dialog.title = "Save FOLD level"
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_RESOURCES
	_save_dialog.filters = PackedStringArray(["*.tres ; FOLD level resource"])
	_save_dialog.file_selected.connect(_save_to)
	_save_dialog.canceled.connect(func(): _pending_action = Callable())
	add_child(_save_dialog)
	_discard_dialog = ConfirmationDialog.new()
	_discard_dialog.title = "Unsaved level changes"
	_discard_dialog.dialog_text = "Save the current level before continuing?"
	_discard_dialog.ok_button_text = "Save"
	_discard_dialog.add_button("Discard", true, "discard")
	_discard_dialog.confirmed.connect(_save)
	_discard_dialog.custom_action.connect(func(_action: StringName): _run_pending())
	_discard_dialog.canceled.connect(func(): _pending_action = Callable())
	add_child(_discard_dialog)
	_message_dialog = AcceptDialog.new()
	add_child(_message_dialog)


func _on_document_changed() -> void:
	_refresh_overview()
	_draft_timer.start()


func _refresh_overview() -> void:
	selection = clampi(selection, 0, document.object_count() - 1)
	_objects.clear()
	for index in document.object_count():
		_objects.add_item(document.object_name(index))
	_objects.select(selection)
	canvas.selection = selection
	canvas.queue_redraw()
	_path_label.text = ("● " if document.is_dirty() else "✓ ") + ("Untitled — use Save As to create a level" if document.path.is_empty() else document.path)
	_undo_button.disabled = not document.can_undo()
	_redo_button.disabled = not document.can_redo()
	var errors := document.level.validation_errors()
	var warnings := document.level.validation_warnings()
	var lines := PackedStringArray()
	for message in errors:
		lines.append("ERROR · " + message)
	for message in warnings:
		lines.append("NOTE · " + message)
	if lines.is_empty():
		lines.append("Ready to playtest. All coordinates are world units; boxes extend in X, Y, Z and W.")
	_status.text = "\n".join(lines)


func _refresh_all() -> void:
	_refresh_overview()
	_refresh_properties()
	_refreshing = true
	for property in _metadata_fields:
		var value: Variant = document.level.get(property)
		_metadata_fields[property].text = "\n".join(value) if property == "hints" else str(value)
	_refreshing = false


func _refresh_properties() -> void:
	_refreshing = true
	_selected_label.text = document.object_name(selection)
	var position := document.object_position(selection)
	var dimensions := document.object_size(selection)
	for axis in 4:
		_position_fields[axis].set_value_no_signal(position[axis])
		_size_fields[axis].set_value_no_signal(dimensions[axis])
	_size_group.visible = document.is_box(selection)
	_shape_group.visible = document.is_shape(selection)
	if document.is_shape(selection):
		var shape: FoldShape = document.shape_at(selection)
		_shape_scale.set_value_no_signal(shape.scale)
		_edge_thickness.set_value_no_signal(shape.edge_thickness)
		var topology: Dictionary = Polytopes.topology(shape.kind)
		_shape_details.text = "%d vertices · %d solid edges" % [topology.vertices.size(), topology.edges.size()]
	_delete_button.disabled = selection < 2
	_duplicate_button.disabled = selection < 2
	_refreshing = false


func _select_object(index: int) -> void:
	document.break_merge()
	selection = index
	_objects.select(index)
	canvas.selection = index
	canvas.queue_redraw()
	_refresh_properties()


func _move_object(index: int, position: Vector4) -> void:
	document.set_position(index, position)
	_refresh_properties()


func _position_changed(value: float, axis: int) -> void:
	if _refreshing:
		return
	var position := document.object_position(selection)
	position[axis] = value
	document.set_position(selection, position, true)


func _size_changed(value: float, axis: int) -> void:
	if _refreshing:
		return
	var dimensions := document.object_size(selection)
	dimensions[axis] = value
	document.set_size(selection, dimensions)


func _shape_scale_changed(value: float) -> void:
	if not _refreshing:
		document.set_shape_scale(selection, value)


func _edge_thickness_changed(value: float) -> void:
	if not _refreshing:
		document.set_edge_thickness(selection, value)


func _metadata_changed(property: String) -> void:
	if _refreshing:
		return
	var text: String = _metadata_fields[property].text
	if property == "hints":
		var hints: Array[String] = []
		for line in text.split("\n"):
			if not line.strip_edges().is_empty():
				hints.append(line)
		document.set_metadata(property, hints)
	else:
		document.set_metadata(property, text)


func _set_projection(index: int) -> void:
	canvas.vertical_axis = 2 if index == 0 else 3
	_slice_label.text = "Slice W" if index == 0 else "Slice Z"
	canvas.fit_level()


func _add_object(kind: String) -> void:
	_select_object(document.add_object(kind))


func _add_selected_shape() -> void:
	_select_object(document.add_shape(Polytopes.TYPES[_shape_kind.selected]))


func _open_sample(index: int) -> void:
	_guard_changes(_load_sample.bind(index))


func _load_sample(index: int) -> void:
	var kind: String = Polytopes.TYPES[index]
	var path := "res://levels/samples/%s.tres" % kind.replace("-", "_")
	_open_level(path)
	if document.path == path and not document.level.shapes.is_empty():
		_select_object(2 + document.level.boxes.size())


func _duplicate_selected() -> void:
	_select_object(document.duplicate_object(selection))


func _delete_selected() -> void:
	document.delete_object(selection)
	_refresh_properties()


func _undo() -> void:
	document.undo()
	_refresh_all()


func _redo() -> void:
	document.redo()
	_refresh_all()


func _guard_changes(action: Callable) -> void:
	if document.is_dirty():
		_pending_action = action
		_discard_dialog.popup_centered()
	else:
		action.call()


func _run_pending() -> void:
	_discard_dialog.hide()
	var action := _pending_action
	_pending_action = Callable()
	if action.is_valid():
		action.call()


func _new_level() -> void:
	document.new_level()
	_clear_recovery()
	selection = 0
	_refresh_all()
	canvas.fit_level()


func _show_open() -> void:
	_open_dialog.popup_centered_ratio(0.75)


func _open_level(path: String) -> void:
	var error := document.open_level(path)
	if error != OK:
		_show_message("Could not open level", "Select a valid FoldLevel .tres resource.\nThe current level has been kept.")
		return
	_clear_recovery()
	selection = 0
	_refresh_all()
	canvas.fit_level()


func _save() -> void:
	if not _validate_for_action():
		_pending_action = Callable()
		return
	if document.path.is_empty():
		_show_save_as()
	else:
		_save_to(document.path)


func _show_save_as() -> void:
	if not _validate_for_action():
		return
	DirAccess.make_dir_recursive_absolute("res://levels/custom")
	_save_dialog.current_dir = "res://levels/custom/" if document.path.is_empty() else document.path.get_base_dir()
	_save_dialog.current_file = "my_level.tres" if document.path.is_empty() else document.path.get_file()
	_save_dialog.popup_centered_ratio(0.75)


func _save_to(path: String) -> void:
	if not path.ends_with(".tres"):
		path += ".tres"
	var error := document.save_level(path)
	if error != OK:
		_show_message("Save failed", "Could not save %s (error %d).\nReview the validation messages and choose a writable resource path." % [path, error])
		_pending_action = Callable()
		return
	_clear_recovery()
	_run_pending()


func _validate_for_action() -> bool:
	var errors := document.level.validation_errors()
	if errors.is_empty():
		return true
	_show_message("Fix these issues first", "\n".join(errors))
	return false


func _show_message(title: String, message: String) -> void:
	_message_dialog.title = title
	_message_dialog.dialog_text = message
	_message_dialog.popup_centered(Vector2i(560, 220))


func playtest() -> void:
	if not _validate_for_action():
		return
	if ResourceSaver.save(document.level, PREVIEW_PATH) != OK:
		_show_message("Playtest failed", "Could not write the temporary preview level.")
		return
	stop_playtest()
	_preview_pid = OS.create_process(OS.get_executable_path(), PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--", "--level=" + PREVIEW_PATH]))
	if _preview_pid < 0:
		_show_message("Playtest failed", "Godot could not start a game window.")
	else:
		_stop_button.disabled = false


func stop_playtest() -> void:
	if _preview_pid > 0 and OS.is_process_running(_preview_pid):
		OS.kill(_preview_pid)
	_preview_pid = -1
	if is_instance_valid(_stop_button):
		_stop_button.disabled = true


func save_recovery() -> void:
	if document.is_dirty():
		ResourceSaver.save(document.level, DRAFT_PATH)


func save_external_data() -> void:
	if not document.is_dirty():
		return
	if not document.path.is_empty() and document.level.validation_errors().is_empty():
		if document.save_level(document.path) == OK:
			_clear_recovery()
			return
	save_recovery()


func _restore_draft() -> void:
	var draft := ResourceLoader.load(DRAFT_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as FoldLevel
	if draft == null:
		_show_message("No draft available", "The recovery resource could not be read.")
		return
	document.set_level(draft, "", true)
	_refresh_all()
	canvas.fit_level()
	_restore_button.hide()


func _clear_recovery() -> void:
	if FileAccess.file_exists(DRAFT_PATH):
		DirAccess.remove_absolute(DRAFT_PATH)
	_restore_button.hide()


func _shortcut_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.ctrl_pressed and event.keycode == KEY_S:
		_save()
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and event.keycode == KEY_Z:
		# Text fields retain their own undo; document history is also on the toolbar.
		var focused := get_viewport().gui_get_focus_owner()
		if focused is LineEdit or focused is TextEdit:
			return
		if event.shift_pressed:
			_redo()
		else:
			_undo()
		get_viewport().set_input_as_handled()
