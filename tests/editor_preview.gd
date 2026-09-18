extends SceneTree
## Render the authoring panel at desktop and compact editor-workspace sizes.
## Run without --headless; captures are written to test-output/.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 800)
	var panel: Control = load("res://addons/fold_level_editor/level_editor.gd").new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel._open_level("res://levels/02_the_missing_span.tres")
	panel._select_object(4)
	await _capture(panel, "level-editor-xz")
	var projection: OptionButton = panel.find_child("Projection", true, false)
	projection.select(1)
	projection.item_selected.emit(1)
	await _capture(panel, "level-editor-xw")
	root.size = Vector2i(900, 680)
	await _capture(panel, "level-editor-compact")
	root.size = Vector2i(1280, 800)
	panel._load_sample(4)
	await _capture(panel, "level-editor-120-cell")
	root.size = Vector2i(900, 680)
	await _capture(panel, "level-editor-120-cell-compact")
	panel.queue_free()
	await process_frame
	print("PASS: level editor panel rendered at desktop and compact sizes.")
	quit()

func _capture(panel: Control, filename: String) -> void:
	await create_timer(0.2).timeout
	panel.canvas.fit_level()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-output/%s.png" % filename)
