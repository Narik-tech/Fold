extends SceneTree
## Render the maze's entrance, fold court, sky walk, and menu for visual review.
## Run without --headless. Images are saved in test-output/maze-*.png.

var game: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.capture_mode = true
	game.set_physics_process(false)
	game.sound.set_muted(true)
	await _capture("title")
	game._select_level(3)
	game.hud._toast_panel.hide()
	await _capture("entrance")
	game.position4 = Vector4(-5, 0, 0, 0)
	game.angle = PI / 2.0
	game.active_axis = 1
	game._refresh_view()
	game.world.reset_camera(game.position4, game.angle, Vector2(0, 1))
	await _capture("fold-court")
	game.position4 = Vector4(11.2, 3.2, 0, 0)
	game.angle = PI / 2.0
	game._refresh_view()
	game.world.reset_camera(game.position4, game.angle, Vector2(0, 1))
	await _capture("sky-walk")
	game.position4 = Vector4(5, 3.2, -5, 5)
	game.angle = 0.0
	game.active_axis = 0
	game._refresh_view()
	game.world.reset_camera(game.position4, game.angle, Vector2(-1, 0))
	await _capture("home")
	game._toggle_pause()
	await _capture("pause")
	game.sound.stop_all()
	game.queue_free()
	await process_frame
	print("PASS: maze views and chapter navigation rendered.")
	quit()


func _capture(filename: String) -> void:
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-output/maze-%s.png" % filename)
