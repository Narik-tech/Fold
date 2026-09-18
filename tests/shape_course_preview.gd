extends SceneTree
## Render the jumping course at its entrance, dimensional turns, and summit.
## Run without --headless; output goes to test-output/shape-course-*.png.

var game: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://test-output")
	root.size = Vector2i(1280, 800)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.capture_mode = true
	game.set_physics_process(false)
	game.sound.set_muted(true)
	game._select_level(4)
	game.hud._toast_panel.hide()
	await _capture("entrance")
	await _view_at(Vector4(6, 0.7, 0, 0), PI / 2.0, Vector2(0, 1), 1, "first-fold")
	await _view_at(Vector4(12, 2.1, 0, 6), 0.0, Vector2(0, 1), 3, "across-z")
	await _view_at(Vector4(18, 3.5, 6, 6), PI / 2.0, Vector2(0, 1), 5, "summit-approach")
	game.sound.stop_all()
	game.queue_free()
	await process_frame
	print("PASS: jumping course entrance, folds, and summit rendered.")
	quit()


func _view_at(feet: Vector4, view_angle: float, facing: Vector2, echoes: int, filename: String) -> void:
	game.position4 = feet
	game.angle = view_angle
	game.active_axis = 1 if view_angle > 0.0 else 0
	game.hint_index = echoes
	for index in range(game.collected.size()):
		game.collected[index] = index < echoes
	game._refresh_view()
	game.world.reset_camera(feet, view_angle, facing)
	await _capture(filename)


func _capture(filename: String) -> void:
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-output/shape-course-%s.png" % filename)
