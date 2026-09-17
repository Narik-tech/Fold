extends SceneTree
## Runs actual gameplay physics and objectives without rendered frames or input.
## godot --headless --path . --script tests/test_playthrough.gd

const DT: float = 1.0 / 60.0
const POSITION_EPSILON: float = 0.018
const MAX_SEGMENT_FRAMES: int = 600

var game: Node
var checks: int = 0
var failures: Array[String] = []
var simulated_frames: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load(str(ProjectSettings.get_setting("application/run/main_scene")))
	if scene == null:
		printerr("FAIL: Project main scene could not be loaded.")
		quit(1)
		return
	game = scene.instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound.set_muted(true)
	game._start()
	_expect(game.started, "The title screen starts the game")
	_test_level_routes()
	_test_wall_obstruction()
	_test_missing_bridge()
	_test_respawn_retains_echoes()
	_test_grounded_folding()
	_test_gate_requires_echoes()
	_test_repeat_loading()
	# Let the audio mix thread release stopped playback after this accelerated
	# run, which otherwise quits within a single real frame of cleanup.
	game.sound.stop_all()
	await create_timer(0.08).timeout
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: %d gameplay checks; %d physics frames; all 3 levels completed through movement, folds, and jumps." % [checks, simulated_frames])
		quit(0)
	else:
		printerr("FAIL: %d of %d gameplay checks failed." % [failures.size(), checks])
		quit(1)


func _test_level_routes() -> void:
	for index in range(game.levels.size()):
		game._select_level(index)
		var route: Array = game.level.solution
		var jumps: Array = game.level.jump_segments
		var reached_all: bool = true
		for waypoint in range(1, route.size()):
			if not _move_to(route[waypoint], waypoint - 1 in jumps, "level %d waypoint %d" % [index + 1, waypoint]):
				reached_all = false
				break
		_expect(reached_all, "Level %d follows every solution waypoint" % (index + 1))
		_expect(game._collected_count() == game.collected.size(), "Level %d collects every echo through real proximity" % (index + 1))
		_expect(game.completed, "Level %d reaches its unlocked exit" % (index + 1))
		_expect(game.grounded and game.position4.distance_to(game.level.goal) < POSITION_EPSILON, "Level %d finishes standing at its exit" % (index + 1))
		print("Level %d: %d/%d echoes, completed=%s, feet=%s" % [index + 1, game._collected_count(), game.collected.size(), game.completed, game.position4])


func _test_wall_obstruction() -> void:
	game._select_level(0)
	for unused in range(150):
		_step(Vector2.RIGHT)
	_expect(game.position4.x < -0.58 and game.position4.x > -0.7, "The first wall blocks direct X movement at W 0")
	_expect(game.grounded and is_zero_approx(game.position4.w), "Wall collision keeps the traveler supported in the original slice")
	_expect(game._collected_count() == 0 and not game.completed, "Walking into the wall cannot collect its hidden echo or complete the level")


func _test_missing_bridge() -> void:
	game._select_level(1)
	var fell: bool = false
	for unused in range(100):
		_step(Vector2.RIGHT)
		if game.position4.y < -1.0:
			fell = true
			break
	_expect(fell, "The bridge provides no floor in the W 0 slice")
	_expect(is_zero_approx(game.position4.w), "The missing-bridge regression stays at W 0")
	_expect(not game.completed, "Falling into the direct island gap does not complete the level")


func _test_respawn_retains_echoes() -> void:
	game._select_level(0)
	var route: Array = game.level.solution
	for waypoint in range(1, 4):
		if not _move_to(route[waypoint], false, "respawn setup waypoint %d" % waypoint):
			return
	_expect(game._collected_count() == 1, "Respawn setup collects an echo through movement")
	var fell: bool = false
	var respawned: bool = false
	for unused in range(180):
		_step(Vector2.DOWN)
		if game.position4.y < -1.0:
			fell = true
		if fell and game.position4.distance_to(game.level.start) < POSITION_EPSILON:
			respawned = true
			break
	_expect(fell and respawned, "Falling below the world automatically respawns the traveler")
	_expect(game._collected_count() == 1, "Automatic respawn preserves collected echoes")
	_expect(game.grounded and game.active_axis == 0 and is_zero_approx(game.angle), "Respawn restores a grounded Z view")


func _test_grounded_folding() -> void:
	game._select_level(0)
	_step(Vector2.ZERO, true)
	_expect(not game.grounded, "Jump input launches the traveler")
	var airborne_position: Vector4 = game.position4
	_expect(not game.request_fold(), "Folding is rejected while airborne")
	_expect(not game.rotating and game.active_axis == 0 and game.position4 == airborne_position, "Rejected fold preserves the current plane and position")
	for unused in range(90):
		_step(Vector2.ZERO)
		if game.grounded:
			break
	_expect(game.grounded, "The traveler lands after a stationary jump")
	_expect(_fold_to(1), "A grounded traveler can complete the fold animation")
	_expect(_fold_to(0), "Folding back restores the original view")


func _test_gate_requires_echoes() -> void:
	game._select_level(0)
	# A fixture at the exit isolates the objective rule from traversal.
	game.position4 = game.level.goal
	game._check_objectives()
	_expect(not game.completed, "The gate remains locked when an echo is missing")
	game._select_level(0)
	# At the same visible point but a different hidden coordinate, the echo
	# must not be collected: objective distance is measured in all four axes.
	var echo: Vector4 = game.level.seeds[0]
	game.position4 = Vector4(echo.x, 0.0, echo.z, 0.0)
	game._check_objectives()
	_expect(game._collected_count() == 0, "Echo proximity includes the hidden W coordinate")


func _test_repeat_loading() -> void:
	for iteration in range(2):
		for index in range(game.levels.size()):
			game._select_level(index)
			var worlds: int = 0
			for child: Node in game.get_children():
				if child.name == &"FourDimensionalGarden":
					worlds += 1
			_expect(worlds == 1 and game.world_root.name == &"FourDimensionalGarden" and game.world_root.get_parent() == game, "Reload %d/%d retains one attached world" % [iteration, index])
			_expect(game.box_visuals.size() == game.level.boxes.size() and game.seed_visuals.size() == game.level.seeds.size(), "Reload %d/%d rebuilds the expected visual arrays" % [iteration, index])
			_expect(game._collected_count() == 0 and not game.completed, "Reload %d/%d resets objectives" % [iteration, index])
			_expect(game.position4 == game.level.start and game.grounded and game.active_axis == 0 and not game.rotating, "Reload %d/%d resets traversal state" % [iteration, index])


func _move_to(target: Vector4, jump: bool, label: String) -> bool:
	var difference: Vector4 = target - game.position4
	if absf(difference.z) > POSITION_EPSILON:
		if not _fold_to(0):
			return _expect(false, label + ": could not expose Z")
	elif absf(difference.w) > POSITION_EPSILON:
		if not _fold_to(1):
			return _expect(false, label + ": could not expose W")
	if jump and not _expect(game.grounded, label + ": begins jump from solid ground"):
		return false
	for frame in range(MAX_SEGMENT_FRAMES):
		difference = target - game.position4
		var horizontal: Vector2 = Vector2(difference.x, difference.z if game.active_axis == 0 else difference.w)
		var scale: float = game.SPEED * DT
		var motion: Vector2 = horizontal / scale
		if motion.length() > 1.0:
			motion = motion.normalized()
		_step(motion, jump and frame == 0)
		if game.position4.distance_to(target) < POSITION_EPSILON and game.grounded:
			return _expect(true, label + ": reached supported target")
	return _expect(false, "%s: timed out at %s aiming for %s (grounded=%s)" % [label, game.position4, target, game.grounded])


func _fold_to(axis: int) -> bool:
	if game.active_axis == axis:
		return true
	if not _expect(game.grounded, "Plane changes begin on solid ground"):
		return false
	var before: Vector4 = game.position4
	if not game.request_fold():
		return false
	for unused in range(60):
		game._physics_process(DT)
		if not game.rotating:
			break
	return _expect(not game.rotating and game.active_axis == axis and before == game.position4, "Animated fold changes the visible axis while preserving all four coordinates")


func _step(motion: Vector2, jump: bool = false) -> void:
	game.simulate_motion(motion, DT, jump)
	simulated_frames += 1


func _expect(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)
	return condition
