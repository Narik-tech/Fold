extends SceneTree
## Verify inspector wiring and unsaved-change protection at the UI boundary.

const EditorPanel = preload("res://addons/fold_level_editor/level_editor.gd")
const TEST_PATH := "res://test-output/editor_ui_regression.tres"
var checks := 0
var failures := 0
var pending_ran := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var panel: Control = EditorPanel.new()
	root.add_child(panel)
	panel._open_level("res://levels/02_the_missing_span.tres")
	panel._select_object(4)
	_expect(is_equal_approx(panel._position_fields[3].value, 2.65), "Inspector preserves fractional hidden coordinates")
	_expect(is_equal_approx(panel._position_fields[1].value, -0.25), "Inspector preserves negative quarter heights")
	_expect(is_equal_approx(panel._size_fields[1].value, 0.5), "Size controls preserve authored dimensions")
	panel._position_fields[3].value = 3.125
	_expect(is_equal_approx(panel.document.level.boxes[2].center.w, 3.125), "Inspector changes the selected object's W coordinate")
	_expect(panel.document.level.solution.is_empty() and panel.document.level.jump_segments.is_empty(), "Geometry edits invalidate the old solution proof")
	panel._undo()
	_expect(is_equal_approx(panel.document.level.boxes[2].center.w, 2.65) and not panel.document.level.solution.is_empty(), "Undo restores geometry and recorded solution")
	panel._new_level()
	panel.document.save_level(TEST_PATH)
	panel.document.set_metadata(&"title", "Saved edit")
	panel.document.save_level(TEST_PATH)
	panel._undo()
	_expect(panel.document.is_dirty() and not panel.document.can_undo(), "Undo after Save may leave dirty state with empty undo history")
	panel._guard_changes(func(): pending_ran = true)
	_expect(panel._discard_dialog.visible and not pending_ran, "New/Open requires a decision even when dirty history is empty")
	panel._discard_dialog.hide()
	panel._discard_dialog.canceled.emit()
	_expect(not panel._pending_action.is_valid(), "Cancel clears the pending destructive transition")
	if "--playtest" in OS.get_cmdline_user_args():
		await _test_playtest(panel)
	panel.document.save_level(TEST_PATH)
	panel._draft_timer.stop()
	panel.queue_free()
	await process_frame
	DirAccess.remove_absolute(TEST_PATH)
	print("%s: %d editor UI checks." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _test_playtest(panel: Control) -> void:
	# Optional desktop integration: actually opens and closes a game window.
	var previous_path: String = panel.document.path
	panel.playtest()
	await create_timer(1.5).timeout
	var preview_pid: int = panel._preview_pid
	_expect(preview_pid > 0 and OS.is_process_running(preview_pid), "Playtest starts the actual Godot game process")
	var preview: FoldLevel = FoldLevel.load_level(EditorPanel.PREVIEW_PATH)
	_expect(preview != null and preview.to_dictionary() == panel.document.level.to_dictionary(), "Playtest serializes the complete current draft")
	_expect(panel.document.path == previous_path and panel.document.is_dirty(), "Playtest keeps the authoring file and unsaved status")
	panel.stop_playtest()
	await create_timer(0.2).timeout
	_expect(panel._preview_pid == -1 and not OS.is_process_running(preview_pid), "Stop closes the process owned by this playtest")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
