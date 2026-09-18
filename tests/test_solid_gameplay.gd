extends SceneTree
## Exercise filled faces through the same motion, validation, and camera APIs as play.

const Solids = preload("res://scripts/solid_geometry.gd")
const DT := 1.0 / 60.0
var game: Node
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound.set_muted(true)
	_test_movement()
	_test_validation()
	_test_rendering_and_camera()
	game.sound.stop_all()
	await create_timer(0.08).timeout
	game.queue_free()
	await process_frame
	print("%s: %d solid face gameplay checks." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)


func _fixture() -> FoldLevel:
	var level := FoldLevel.create_default()
	level.start = Vector4(-3, 0, 0, 0)
	level.goal = Vector4(25, 0, 0, 0)
	level.boxes[0].size = Vector4(80, 1, 80, 80)
	level.seeds = [Vector4(20, 0.85, 0, 0)]
	level.solution = [level.start, level.goal]
	var shape := FoldShape.new()
	shape.representation = "solid"
	shape.center = Vector4(0, 2, 0, 0)
	shape.scale = 4.0
	level.shapes = [shape]
	return level


func _test_movement() -> void:
	var level := _fixture()
	_expect(game.load_custom_level(level), "A solid tesseract loads into the actual game")
	_expect(game.shape_solids.is_empty() and game.filled_solids.size() == 1,
		"A solid shape compiles once as a filled volume without edge beams")
	game._move_axis(0, 10.0)
	_expect(absf(game.position4.x + 2.27) < 0.001,
		"Swept motion stops at a filled face away from every edge")
	for unused in range(30):
		game.simulate_motion(Vector2.RIGHT, DT)
	_expect(absf(game.position4.x + 2.27) < 0.001 and game.grounded,
		"Holding movement into a face preserves stable floor contact")
	game.position4 = Vector4(0, 6, 0, 0)
	game._move_axis(1, -6.0)
	_expect(absf(game.position4.y - 4.0) < 0.001 and game.grounded,
		"The traveler lands on the middle of a solid face")
	for unused in range(30):
		game.simulate_motion(Vector2(0.2, 0.2), DT)
	_expect(absf(game.position4.y - 4.0) < 0.001 and game.grounded,
		"Walking on the face remains grounded without blocking tangential movement")
	game.position4 = Vector4(-3, 0, 0, 2.28)
	game._move_axis(0, 6.0)
	_expect(absf(game.position4.x - 3.0) < 0.001,
		"Moving beyond the solid in W opens passage for the whole traveler")
	for angle: float in [0.0, PI / 4.0, PI / 2.0, -PI / 4.0, 3.0 * PI / 4.0]:
		game.angle = angle
		var direction := Vector4(0, 0, cos(angle), sin(angle))
		game.position4 = direction * -5.0
		game._move_depth(10.0)
		var expected := -2.27 / maxf(absf(cos(angle)), absf(sin(angle)))
		_expect(absf(direction.dot(game.position4) - expected) < 0.001,
			"Depth sweep stops at the solid face at angle %.3f" % angle)
		_expect(absf(-game.position4.z * sin(angle) + game.position4.w * cos(angle)) < 0.0001,
			"Face contact keeps the same hidden coordinate during a fold")
		_expect(not Solids.intersects_player(game.position4, game.filled_solids[0]),
			"Swept contact does not leave the traveler inside the solid")
	level.shapes[0].representation = "edges"
	_expect(game.load_custom_level(level), "Switching the resource back to an edge frame reloads")
	game._move_axis(0, 6.0)
	_expect(absf(game.position4.x - 3.0) < 0.001 and game.filled_solids.is_empty(),
		"Edge frames still have an open center after switching modes")
	var filled := level.shapes[0].duplicate() as FoldShape
	filled.representation = "solid"
	filled.center.x = 10
	level.shapes.append(filled)
	_expect(game.load_custom_level(level) and game.shape_solids.size() == 1 and game.filled_solids.size() == 1
		and game.world.shape_visuals.size() == 2, "Edge frames and solids coexist in one level")


func _test_validation() -> void:
	var level := _fixture()
	level.start = Vector4(0, 4, 0, 0)
	level.solution[0] = level.start
	_expect(level.validation_warnings().is_empty(), "Solid faces support authored start positions")
	level.start.y = 0
	level.solution[0] = level.start
	_expect(_has_warning(level, "Start overlaps a solid shape."),
		"Validation detects a start inside the solid interior")
	level.shapes[0].representation = "edges"
	_expect(not _has_warning(level, "Start overlaps a solid shape."),
		"Changing representation refreshes cached collision validation")
	level.shapes[0].representation = "solid"
	level.shapes[0].center.x = 10
	_expect(not _has_warning(level, "Start overlaps a solid shape."),
		"Moving the solid refreshes cached collision validation")


func _test_rendering_and_camera() -> void:
	var level := _fixture()
	level.start = Vector4.ZERO
	level.shapes[0].center.x = -3.2
	_expect(game.load_custom_level(level), "Solid camera fixture loads")
	for unused in range(120):
		game._process(DT)
	_expect(game.world.shape_visuals[0].visible and game.world._camera_shapes[0] != null,
		"Opaque solid faces provide actual triangle surfaces for the camera")
	_expect(game.world.camera.position.x > -1.2,
		"A solid face pulls the camera in front of the surface")
	game.position4.w = 2.1
	game.world.update_slice(game.position4, 0.0, 0, false, game.collected, 0, game.RADIUS)
	_expect(not game.world.shape_visuals[0].visible and game.world.shape_fringes[0].visible,
		"A solid just outside the slice shows its nearby contact silhouette")
	_expect(game.world._camera_shapes[0] == null,
		"Contact silhouettes do not obstruct the camera")
	game.position4.w = 2.5
	game.world.update_slice(game.position4, 0.0, 0, false, game.collected, 0, game.RADIUS)
	_expect(not game.world.shape_visuals[0].visible and not game.world.shape_fringes[0].visible,
		"A solid beyond the traveler's width disappears from this slice")


func _has_warning(level: FoldLevel, text: String) -> bool:
	for warning in level.validation_warnings():
		if warning.contains(text):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
