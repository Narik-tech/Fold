extends SceneTree
## Render all sample gardens, then inspect intermediate folding of the 120-cell.
## Run without --headless; output goes to test-output/shape-*.png.

const SAMPLES := ["5_cell", "tesseract", "16_cell", "24_cell", "120_cell", "600_cell"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.sound.set_muted(true)
	for sample in SAMPLES:
		game.load_custom_level(FoldLevel.load_level("res://levels/samples/%s.tres" % sample))
		await _capture("shape-" + sample)
	game.load_custom_level(FoldLevel.load_level("res://levels/samples/120_cell.tres"))
	game.position4 = Vector4(0, 0, 0.65, 0)
	game.rotating = true
	game.angle = PI / 4.0
	await _capture("shape-120_cell-folding")
	game.rotating = false
	game.active_axis = 1
	game.angle = PI / 2.0
	await _capture("shape-120_cell-folded")
	game.sound.stop_all()
	game.queue_free()
	await process_frame
	print("PASS: all six shape samples and the 120-cell fold rendered.")
	quit()


func _capture(filename: String) -> void:
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-output/%s.png" % filename)
