extends SceneTree
## Exercise the shape-only ascent through actual jumping and folding physics.
## godot --headless --path . --script tests/test_shape_course.gd

const COURSE_PATH := "res://levels/05_the_folded_ascent.tres"
const Solids = preload("res://scripts/solid_geometry.gd")
const DT := 1.0 / 60.0
const POSITION_EPSILON := 0.018
const MAX_SEGMENT_FRAMES := 300

var game: Node
var checks := 0
var failures := 0
var simulated_frames := 0
var jumps_landed := 0
var folds_completed := 0
var simulation_delta := DT


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var authored := FoldLevel.load_level(COURSE_PATH)
	if not _expect(authored != null, "The folded ascent resource loads"):
		quit(1)
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound.set_muted(true)
	game.capture_mode = true
	game._select_level(4)
	if _expect(game.level.title == authored.title, "The ascent is the fifth playable campaign level"):
		_test_authored_course(authored)
		_test_complete_route()
		_test_jump_required()
		_test_checkpoint_recovery()
		_test_checkpoint_safety()
		_test_locked_exit()
	game.sound.stop_all()
	await create_timer(0.08).timeout
	game.queue_free()
	await process_frame
	print("%s: %d shape-course checks; %d physics frames." % ["PASS" if failures == 0 else "FAIL", checks, simulated_frames])
	quit(0 if failures == 0 else 1)


func _test_authored_course(authored: FoldLevel) -> void:
	_expect(authored.validation_errors().is_empty() and authored.validation_warnings().is_empty(), "The ascent has valid geometry and supported endpoints and checkpoints")
	_expect(authored.boxes.is_empty(), "There is no broad floor or box bridge between the 4D shapes")
	_expect(authored.shapes.size() >= 9 and authored.jump_segments.size() >= 8, "The course requires a sustained sequence of shape-to-shape jumps")
	var kinds: Array[String] = []
	var all_solid := true
	for shape: FoldShape in authored.shapes:
		all_solid = all_solid and shape.representation == "solid"
		if shape.kind not in kinds:
			kinds.append(shape.kind)
	_expect(all_solid and game.shape_solids.is_empty() and game.filled_solids.size() == authored.shapes.size(), "Every platform uses its real filled 4D shape collision")
	_expect(kinds.size() >= 3, "The ascent crosses at least three different regular 4D shapes")
	_expect(authored.solution.front() == authored.start and authored.solution.back() == authored.goal, "The route connects the launch shape to the summit gate")
	var minimum: Vector4 = authored.start
	var maximum: Vector4 = authored.start
	for point: Vector4 in authored.solution:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	for axis in range(4):
		_expect(maximum[axis] - minimum[axis] > 1.0, "The jumping route traverses dimension %s" % "XYZW"[axis])
	_expect(not authored.seeds.is_empty() and authored.echo_checkpoints.size() == authored.seeds.size(), "Every echo has a recovery checkpoint")


func _test_complete_route() -> void:
	for frames_per_second in [30, 60, 120]:
		simulation_delta = 1.0 / frames_per_second
		_complete_route_at_rate(frames_per_second)
	simulation_delta = DT


func _complete_route_at_rate(frames_per_second: int) -> void:
	game._select_level(4)
	jumps_landed = 0
	folds_completed = 0
	var route: Array = game.level.solution
	var reached_all := true
	for waypoint in range(1, route.size()):
		if not _move_to(route[waypoint], waypoint - 1 in game.level.jump_segments, "course waypoint %d" % waypoint):
			reached_all = false
			break
	_expect(reached_all and jumps_landed == game.level.jump_segments.size(), "Every authored jump leaves its shape and lands on the next supported target")
	_expect(folds_completed >= 3, "Completing the ascent requires switching between Z and W routes")
	_expect(game._collected_count() == game.collected.size(), "The route collects every echo through real four-dimensional proximity")
	_expect(game.completed and game.grounded and game.position4.distance_to(game.level.goal) < POSITION_EPSILON, "The full jump-and-fold route finishes standing at the unlocked summit at %d Hz" % frames_per_second)


func _test_jump_required() -> void:
	game._select_level(4)
	var target: Vector4 = game.level.solution[1]
	var reached := false
	for unused in range(180):
		var difference: Vector4 = target - game.position4
		_step(Vector2(difference.x, difference.z).normalized())
		reached = reached or (game.grounded and game.position4.distance_to(target) < POSITION_EPSILON)
		if game.position4.y < game.level.start.y - 0.6:
			break
	_expect(not reached and game.position4.y < target.y - POSITION_EPSILON, "Walking without jumping cannot reach the first shape's summit (feet=%s)" % game.position4)
	_expect(game._collected_count() == 0 and not game.completed, "A failed walking shortcut grants no echo or completion")


func _test_checkpoint_recovery() -> void:
	game._select_level(4)
	var route: Array = game.level.solution
	var first_echo_waypoint := 0
	for waypoint in range(1, route.size()):
		if not _move_to(route[waypoint], waypoint - 1 in game.level.jump_segments, "checkpoint setup %d" % waypoint):
			return
		if game._collected_count() > 0:
			first_echo_waypoint = waypoint
			break
	if not _expect(first_echo_waypoint > 0, "Jumping to the first echo establishes a real checkpoint"):
		return
	var saved: Vector4 = game.respawn_position
	var collected_before: Array = game.collected.duplicate()
	_expect(saved == game.level.echo_checkpoints[0] and saved != game.level.start, "The first echo saves its tesseract landing position")
	var fell := false
	var returned := false
	# Step off the safe tesseract into empty Z space, then let gravity recover.
	if not _fold_to(0):
		return
	for unused in range(300):
		_step(Vector2.ZERO if fell else Vector2.UP)
		if game.position4.y < saved.y - 1.0:
			fell = true
		if fell and game.position4.distance_to(saved) < POSITION_EPSILON:
			returned = true
			break
	_expect(fell and returned, "Missing the platform automatically returns to the latest echo checkpoint")
	_expect(game.collected == collected_before, "Automatic checkpoint recovery preserves collected echoes")
	_expect(game.grounded and game.active_axis == 0 and is_zero_approx(game.angle), "Recovery restores stable ground and the Z view")
	if returned and first_echo_waypoint + 1 < route.size():
		_expect(_move_to(route[first_echo_waypoint + 1], first_echo_waypoint in game.level.jump_segments, "jump after recovery"), "The recovered traveler can fold and jump onward immediately")


func _test_checkpoint_safety() -> void:
	game._select_level(4)
	for index in range(game.level.echo_checkpoints.size()):
		var checkpoint: Vector4 = game.level.echo_checkpoints[index]
		# Isolate every authored recovery location, including later checkpoints.
		game.position4 = checkpoint
		game.vertical_speed = 0.0
		game.grounded = true
		var stable := true
		for axis in [0, 1, 0]:
			stable = _fold_to(axis) and stable
			for unused in range(30):
				_step(Vector2.ZERO)
				stable = stable and game.grounded and game.position4.distance_to(checkpoint) < POSITION_EPSILON
		var clear := true
		for solid: Dictionary in game.filled_solids:
			clear = clear and not Solids.intersects_player(game.position4, solid, game.RADIUS, game.HEIGHT)
		_expect(stable and clear, "Checkpoint %d remains supported and unobstructed while idle and folding" % (index + 1))


func _test_locked_exit() -> void:
	game._select_level(4)
	# Goal fixtures isolate echo gating from the separately verified traversal.
	game.position4 = game.level.goal
	game._check_objectives()
	_expect(not game.completed and game._collected_count() == 0, "Reaching the summit before collecting echoes leaves the gate locked")
	game.collected.fill(true)
	game.collected[0] = false
	game._check_objectives()
	_expect(not game.completed, "A single missing echo still prevents course completion")


func _move_to(target: Vector4, jump: bool, label: String) -> bool:
	var difference: Vector4 = target - game.position4
	if absf(difference.z) > POSITION_EPSILON:
		if not _fold_to(0):
			return false
	elif absf(difference.w) > POSITION_EPSILON:
		if not _fold_to(1):
			return false
	if not _expect(game.grounded, label + ": starts from solid ground"):
		return false
	var airborne := false
	for frame in range(MAX_SEGMENT_FRAMES):
		difference = target - game.position4
		var horizontal := Vector2(difference.x, difference.z if game.active_axis == 0 else difference.w)
		var motion: Vector2 = horizontal / (game.SPEED * simulation_delta)
		_step(motion.limit_length(), jump and frame == 0)
		airborne = airborne or not game.grounded
		if game.position4.distance_to(target) < POSITION_EPSILON and game.grounded:
			if jump:
				jumps_landed += 1
			return _expect(not jump or airborne, label + ": reaches its supported target after a real jump" if jump else label + ": reaches its supported target")
	return _expect(false, "%s: timed out at %s aiming for %s (grounded=%s)" % [label, game.position4, target, game.grounded])


func _fold_to(axis: int) -> bool:
	var target_angle: float = PI / 2.0 if axis == 1 else 0.0
	if is_equal_approx(game.angle, target_angle):
		return true
	if not _expect(game.grounded, "Slice changes begin on a supported shape"):
		return false
	var before: Vector4 = game.position4
	for unused in range(120):
		var remaining: float = target_angle - game.angle
		if is_zero_approx(remaining):
			break
		if not game.rotate_slice(signf(remaining), minf(simulation_delta, absf(remaining) / game.ROTATION_SPEED)):
			return _expect(false, "The active route allows folding")
	game.rotate_slice(0.0, simulation_delta)
	folds_completed += 1
	return _expect(not game.rotating and is_equal_approx(game.angle, target_angle) and game.active_axis == axis and before == game.position4, "Folding exposes the next dimension without moving the traveler")


func _step(motion: Vector2, jump: bool = false) -> void:
	game.simulate_motion(motion, simulation_delta, jump)
	simulated_frames += 1


func _expect(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
	return condition
