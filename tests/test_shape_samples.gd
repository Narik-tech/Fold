extends SceneTree
## Complete every shape showcase through real movement and grounded folds.

const Level = preload("res://levels/level_definition.gd")
const Edges = preload("res://scripts/edge_geometry.gd")
const SAMPLE_NAMES: Array[String] = ["5_cell", "tesseract", "16_cell", "24_cell", "120_cell", "600_cell"]
const EXPECTED_KINDS: Array[String] = ["5-cell", "tesseract", "16-cell", "24-cell", "120-cell", "600-cell"]
const DT: float = 1.0 / 60.0
const EPSILON: float = 0.02

var game: Node
var checks: int = 0
var failures: int = 0
var frames: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound.set_muted(true)
	for index in range(SAMPLE_NAMES.size()):
		_test_sample(index)
	game.sound.stop_all()
	await create_timer(0.08).timeout
	game.queue_free()
	await process_frame
	print("%s: %d shape sample checks; %d physics frames across all six showcases." % ["PASS" if failures == 0 else "FAIL", checks, frames])
	quit(0 if failures == 0 else 1)


func _test_sample(index: int) -> void:
	var kind: String = EXPECTED_KINDS[index]
	var sample: FoldLevel = Level.load_level("res://levels/samples/%s.tres" % SAMPLE_NAMES[index])
	if not _expect(sample != null, kind + " sample loads as a valid level"):
		return
	_expect(sample.validation_warnings().is_empty(), kind + " has a supported, unobstructed start and exit")
	if not _expect(sample.shapes.size() == 1 and sample.shapes[0].kind == kind, kind + " showcases exactly its named shape"):
		return
	_expect(sample.seeds.size() == 2 and sample.hints.size() >= 3, kind + " includes two echoes and a fold walkthrough")
	_expect(sample.solution.size() >= 5 and sample.jump_segments.is_empty(), kind + " records a simple walking route")
	_expect(_route_clears_edges(sample), kind + " route fits the traveler's entire 4D body between solid edges")
	if not _expect(game.load_custom_level(sample), kind + " starts in the real game"):
		return
	_expect(game.level.get("shapes", []).size() == 1, kind + " survives the authoring-to-runtime boundary")
	var reached_all: bool = true
	for waypoint in range(1, sample.solution.size()):
		if not _move_to(sample.solution[waypoint]):
			_expect(false, "%s route stopped at %s aiming for %s" % [kind, game.position4, sample.solution[waypoint]])
			reached_all = false
			break
	_expect(reached_all, kind + " passes through its hollow frame using movement and folds")
	_expect(game._collected_count() == 2 and game.completed, kind + " collects both echoes and completes at the gate")
	_expect(game.grounded and game.position4.distance_to(sample.goal) < EPSILON, kind + " finishes on the broad floor")
	print("%s: collected=%d completed=%s feet=%s" % [kind, game._collected_count(), game.completed, game.position4])


## A continuous slab test for each straight route segment catches narrow beams
## between waypoints as well as unwanted solid faces or oversized edge bounds.
func _route_clears_edges(sample: FoldLevel) -> bool:
	var compiled: Array[Dictionary] = Edges.compile_shapes(sample.to_dictionary().shapes)
	for waypoint in range(1, sample.solution.size()):
		var before: Vector4 = sample.solution[waypoint - 1]
		var after: Vector4 = sample.solution[waypoint]
		var axis: int = 0 if not is_equal_approx(before.x, after.x) else 3
		for shape: Dictionary in compiled:
			for edge: Dictionary in shape.edges:
				var interval: Vector2 = Edges.movement_interval(edge, before, axis)
				if interval.x < maxf(before[axis], after[axis]) and interval.y > minf(before[axis], after[axis]):
					return false
	return true


func _move_to(target: Vector4) -> bool:
	var difference: Vector4 = target - game.position4
	var desired_axis: int = game.active_axis
	if absf(difference.w) > EPSILON:
		desired_axis = 1
	elif absf(difference.z) > EPSILON:
		desired_axis = 0
	var target_angle: float = PI / 2.0 if desired_axis == 1 else 0.0
	if not is_equal_approx(game.angle, target_angle):
		var before: Vector4 = game.position4
		for unused in range(120):
			var remaining: float = target_angle - game.angle
			if is_zero_approx(remaining):
				break
			if not game.rotate_slice(signf(remaining), minf(DT, absf(remaining) / (PI / 2.0))):
				return false
		game.rotate_slice(0.0, DT)
		if game.rotating or not is_equal_approx(game.angle, target_angle) or game.active_axis != desired_axis or game.position4 != before:
			return false
	for unused in range(300):
		difference = target - game.position4
		var horizontal := Vector2(difference.x, difference.z if game.active_axis == 0 else difference.w)
		var motion: Vector2 = horizontal / (game.SPEED * DT)
		if motion.length() > 1.0:
			motion = motion.normalized()
		game.simulate_motion(motion, DT)
		frames += 1
		if game.position4.distance_to(target) < EPSILON and game.grounded:
			return true
	return false


func _expect(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
	return condition
