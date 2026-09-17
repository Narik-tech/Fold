extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await _capture("hud-title-1280")
	main._start()
	await _capture("hud-game-1280")
	main._toggle_pause()
	await _capture("hud-pause-1280")
	main.hud.show_completion(true)
	await _capture("hud-complete-1280")
	main._select_level(2)
	main._hint()
	main._hint()
	main._hint()
	await _capture("hud-hint-1280")
	root.size = Vector2i(1600, 900)
	await _capture("hud-hint-1600")
	main.hud.show_title()
	await _capture("hud-title-1600")
	print("HUD preview states captured successfully")
	quit()

func _capture(filename: String) -> void:
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-output/%s.png" % filename)
