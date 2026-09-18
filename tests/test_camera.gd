extends SceneTree
## Check mouse orbit, camera-relative keyboard movement, and camera clearance.
## godot --headless --path . --script tests/test_camera.gd

const DT: float = 1.0 / 60.0
var game: Node
var checks: int = 0
var failures: Array[String] = []
var has_mouse_capture: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound.set_muted(true)
	_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "The title screen leaves the pointer visible")
	var title_basis: Basis = game.world.camera.basis
	_mouse_event(Vector2(100.0, 40.0))
	_expect(game.world.camera.basis.is_equal_approx(title_basis), "Mouse motion on the title screen leaves the camera alone")
	game._start()
	has_mouse_capture = DisplayServer.get_name() != "headless"
	if has_mouse_capture:
		_expect(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Starting captures the pointer for mouse look")
	else:
		print("INFO: Headless display cannot capture the pointer; run without --headless to cover captured mouse events.")
	_test_campaign_resets()
	_test_translation_turning_and_idle()
	_test_mouse_orbit()
	_test_fold_tracking()
	_test_camera_relative_keyboard()
	_test_held_input_steering()
	_test_folding_collision()
	_test_mouse_input_lifecycle()
	_test_pause_and_respawn()
	_test_wall_clearance()
	_test_edge_frame_clearance()
	game.sound.stop_all()
	await create_timer(0.08).timeout
	game.queue_free()
	await process_frame
	_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Leaving the game releases the pointer")
	if failures.is_empty():
		print("PASS: all %d third-person camera and movement checks passed." % checks)
		quit(0)
	else:
		printerr("FAIL: %d of %d camera checks failed." % [failures.size(), checks])
		quit(1)


func _test_campaign_resets() -> void:
	_expect(game.world.camera.projection == Camera3D.PROJECTION_PERSPECTIVE,
		"The traveler is viewed through a perspective camera")
	for index in range(game.levels.size()):
		game._select_level(index)
		var expected := _project(game.level.start, 0.0)
		_expect(game.world.hero.position.is_equal_approx(expected),
			"Level %d immediately places the traveler at the new start" % index)
		_expect(game.world.camera.position.distance_to(expected) < 9.0 and _is_behind(),
			"Level %d immediately places the camera behind the traveler" % index)
		_expect(game.world.camera.position.y > expected.y + 1.0,
			"Level %d views the traveler from above shoulder height" % index)


func _test_translation_turning_and_idle() -> void:
	_load_fixture()
	_settle()
	var start_camera: Vector3 = game.world.camera.position
	var start_hero: Vector3 = game.world.hero.position
	var start_basis: Basis = game.world.camera.basis
	var largest_follow_error := 0.0
	for unused in range(30):
		game.simulate_motion(Vector2.RIGHT, DT)
		game._process(DT)
		largest_follow_error = maxf(largest_follow_error,
			(game.world.camera.position - start_camera).distance_to(game.world.hero.position - start_hero))
	game.last_motion = Vector2.ZERO
	_settle()
	var hero_delta: Vector3 = game.world.hero.position - start_hero
	var camera_delta: Vector3 = game.world.camera.position - start_camera
	_expect(hero_delta.x > 2.0 and camera_delta.distance_to(hero_delta) < 0.02 and largest_follow_error < 0.001,
		"The camera follows every movement frame without translation lag or offset drift")
	for unused in range(30):
		game.simulate_motion(Vector2.DOWN, DT)
		game._process(DT)
	game.last_motion = Vector2.ZERO
	_settle()
	_expect(game.world.camera.basis.is_equal_approx(start_basis),
		"Changing the traveler's facing never turns the camera without mouse input")
	var resting_position: Vector3 = game.world.camera.position
	var resting_basis: Basis = game.world.camera.basis
	_settle()
	_expect(game.world.camera.position.distance_to(resting_position) < 0.001
		and game.world.camera.basis.is_equal_approx(resting_basis),
		"Idle animation leaves camera position and heading stable")


func _test_mouse_orbit() -> void:
	_load_fixture()
	var before: Vector4 = game.position4
	var hero_position: Vector3 = game.world.hero.position
	var initial_forward := _camera_forward()
	game.world.orbit_camera(Vector2(200.0, 0.0))
	var orbited_forward := _camera_forward()
	_expect(initial_forward.dot(orbited_forward) < 0.95,
		"Horizontal mouse motion changes camera heading immediately")
	_expect(initial_forward.cross(orbited_forward) > 0.0,
		"Moving the mouse right turns the view to the right")
	_expect(game.position4 == before and game.world.hero.position == hero_position,
		"Orbiting the view leaves the player's position unchanged")
	var initial_pitch := asin(game.world.camera.basis.z.y)
	game.world.orbit_camera(Vector2(0.0, 100000.0))
	var upper_pitch := asin(game.world.camera.basis.z.y)
	_expect(upper_pitch > initial_pitch and absf(upper_pitch - deg_to_rad(70.0)) < 0.001,
		"Looking down stops at a safe 70-degree overhead camera elevation")
	var upper_basis: Basis = game.world.camera.basis
	game.world.orbit_camera(Vector2(0.0, 100000.0))
	_expect(game.world.camera.basis.is_equal_approx(upper_basis), "Pitch remains stable at its upper limit")
	game.world.orbit_camera(Vector2(0.0, -100000.0))
	var lower_pitch := asin(game.world.camera.basis.z.y)
	_expect(absf(lower_pitch - deg_to_rad(-15.0)) < 0.001,
		"Looking up stops at a safe minus-15-degree low camera elevation")
	var lower_basis: Basis = game.world.camera.basis
	game.world.orbit_camera(Vector2(0.0, -100000.0))
	_expect(game.world.camera.basis.is_equal_approx(lower_basis), "Pitch remains stable at its lower limit")
	_expect(_camera_forward().dot(orbited_forward) > 0.999,
		"Vertical mouse motion does not change the horizontal movement heading")
	game.world.orbit_camera(Vector2(123456.0, 0.0))
	_expect(game.world.camera.transform.is_finite(), "Repeated full mouse turns retain a finite camera transform")


func _test_fold_tracking() -> void:
	_load_fixture()
	game.position4 = Vector4(1.0, 0.0, 3.0, -2.0)
	game.world.orbit_camera(Vector2(100.0, -40.0))
	_settle()
	var physical_position: Vector4 = game.position4
	var initial_basis: Basis = game.world.camera.basis
	var previous_hero: Vector3 = game.world.hero.position
	var previous_camera: Vector3 = game.world.camera.position
	for test_angle: float in [PI / 4.0, PI / 2.0, 3.0 * PI / 4.0, -PI / 4.0]:
		var turn: float = test_angle - game.angle
		game.rotate_slice(signf(turn), absf(turn) / game.ROTATION_SPEED)
		game.rotate_slice(0.0, DT)
		_settle()
		var expected := _project(physical_position, test_angle)
		_expect(game.position4 == physical_position and game.world.hero.position.is_equal_approx(expected),
			"Folding to %.2f tracks the projected traveler without changing 4D coordinates" % test_angle)
		var hero_delta: Vector3 = game.world.hero.position - previous_hero
		var camera_delta: Vector3 = game.world.camera.position - previous_camera
		_expect(camera_delta.distance_to(hero_delta) < 0.02 and game.world.camera.basis.is_equal_approx(initial_basis),
			"The camera follows the Z/W projection while retaining its heading at %.2f" % test_angle)
		previous_hero = game.world.hero.position
		previous_camera = game.world.camera.position


func _test_camera_relative_keyboard() -> void:
	for key: Key in [KEY_W, KEY_D, KEY_A, KEY_S]:
		_load_fixture()
		game.world.orbit_camera(Vector2(260.0, 120.0))
		_settle()
		var right := Vector2(game.world.camera.global_basis.x.x, game.world.camera.global_basis.x.z).normalized()
		var back := Vector2(game.world.camera.global_basis.z.x, game.world.camera.global_basis.z.z).normalized()
		var expected: Vector2 = {KEY_W: -back, KEY_D: right, KEY_A: -right, KEY_S: back}[key]
		var before: Vector4 = game.position4
		var camera_basis: Basis = game.world.camera.basis
		_key_event(key, true)
		for unused in range(90):
			game._physics_process(DT)
			game._process(DT)
		_key_event(key, false)
		game._physics_process(DT)
		var change: Vector4 = game.position4 - before
		var horizontal := Vector2(change.x, change.z)
		_expect(horizontal.normalized().dot(expected) > 0.999
			and absf(horizontal.length() - game.SPEED * DT * 90.0) < 0.02,
			"Holding %s follows the current oblique view at full walking speed" % OS.get_keycode_string(key))
		_expect(is_zero_approx(change.w), "Camera steering preserves the hidden coordinate for %s" % OS.get_keycode_string(key))
		_expect(is_zero_approx(change.y), "Camera pitch does not add vertical motion to %s" % OS.get_keycode_string(key))
		_expect(game.world.camera.basis.is_equal_approx(camera_basis),
			"Walking %s does not turn the camera in response to player facing" % OS.get_keycode_string(key))
	_load_fixture()
	game.world.orbit_camera(Vector2(-180.0, 100000.0))
	var before: Vector4 = game.position4
	var diagonal := (_camera_forward() + _camera_right()).normalized()
	_key_event(KEY_W, true)
	_key_event(KEY_D, true)
	for unused in range(30):
		game._physics_process(DT)
		game._process(DT)
	_key_event(KEY_W, false)
	_key_event(KEY_D, false)
	var change: Vector4 = game.position4 - before
	var horizontal := Vector2(change.x, change.z)
	_expect(horizontal.normalized().dot(diagonal) > 0.999 and absf(horizontal.length() - game.SPEED * DT * 30.0) < 0.001,
		"W+D follows the camera diagonal at normal speed even at maximum camera pitch")
	_expect(is_zero_approx(change.y), "A steep camera view cannot lift the walking player off the ground")
	# At an oblique fold the same keyboard heading moves only within the slice.
	game.rotate_slice(1.0, 0.5)
	game.rotate_slice(0.0, DT)
	_settle()
	before = game.position4
	_key_event(KEY_D, true)
	for unused in range(30):
		game._physics_process(DT)
		game._process(DT)
	_key_event(KEY_D, false)
	game._physics_process(DT)
	change = game.position4 - before
	_expect(absf(-sin(game.angle) * change.z + cos(game.angle) * change.w) < 0.001,
		"Camera-relative keyboard motion preserves the hidden coordinate in an oblique slice")
	var projected := Vector2(change.x, change.z * cos(game.angle) + change.w * sin(game.angle))
	_expect(projected.normalized().dot(_camera_right()) > 0.999,
		"A folded slice retains camera-relative screen direction")


func _test_held_input_steering() -> void:
	_load_fixture()
	_key_event(KEY_W, true)
	game._physics_process(DT)
	game._process(DT)
	var prior_forward := _camera_forward()
	game.world.orbit_camera(Vector2(500.0, -40.0))
	var forward := _camera_forward()
	var before: Vector4 = game.position4
	game._physics_process(DT)
	game._process(DT)
	var change: Vector4 = game.position4 - before
	_expect(prior_forward.dot(forward) < 0.5 and Vector2(change.x, change.z).normalized().dot(forward) > 0.999,
		"Turning the mouse changes held W movement on the very next physics frame")
	# Camera motion during a fold must also affect keys that remain held throughout it.
	_key_event(KEY_Q, true)
	var walking_distance := 0.0
	var follows_slice := true
	for unused in range(30):
		before = game.position4
		game._physics_process(DT)
		game._process(DT)
		change = game.position4 - before
		walking_distance += Vector3(change.x, change.z, change.w).length()
		var projected := Vector2(change.x, change.z * cos(game.angle) + change.w * sin(game.angle))
		follows_slice = follows_slice and projected.normalized().dot(forward) > 0.999
	_expect(follows_slice and absf(walking_distance - game.SPEED * DT * 30.0) < 0.001,
		"Held W keeps full speed and camera direction throughout continuous slice rotation")
	game.world.orbit_camera(Vector2(-330.0, 20.0))
	forward = _camera_forward()
	before = game.position4
	game._physics_process(DT)
	change = game.position4 - before
	var projected := Vector2(change.x, change.z * cos(game.angle) + change.w * sin(game.angle))
	_expect(game.rotating and projected.normalized().dot(forward) > 0.999
		and absf(projected.length() - game.SPEED * DT) < 0.001,
		"Held W responds to a new mouse heading on the next frame while Q stays held")
	_key_event(KEY_Q, false)
	before = game.position4
	game._physics_process(DT)
	_key_event(KEY_W, false)
	change = game.position4 - before
	projected = Vector2(change.x, change.z * cos(game.angle) + change.w * sin(game.angle))
	_expect(not game.rotating and projected.normalized().dot(forward) > 0.999
		and absf(projected.length() - game.SPEED * DT) < 0.001,
		"Releasing Q preserves the current camera-relative walking direction and speed")
	game._physics_process(DT)


func _test_folding_collision() -> void:
	var fixture := _fixture()
	var wall := FoldBox.new()
	wall.center = Vector4(2.0, 2.0, 0.0, 0.0)
	wall.size = Vector4(0.4, 4.0, 80.0, 80.0)
	wall.kind = "wall"
	fixture.boxes.append(wall)
	_expect(game.load_custom_level(fixture), "Concurrent fold collision fixture loads")
	game.world.orbit_camera(Vector2(-_camera_forward().angle() / game.world.mouse_sensitivity, 0.0))
	_key_event(KEY_W, true)
	_key_event(KEY_E, true)
	_key_event(KEY_SPACE, true)
	_key_event(KEY_SPACE, false)
	var crossed_wall := false
	for unused in range(60):
		game._physics_process(DT)
		game._process(DT)
		crossed_wall = crossed_wall or game.position4.x > 1.8 - game.RADIUS + 0.001
	_expect(not crossed_wall and game.position4.x > 1.5 and game.rotating,
		"Walking and jumping during a held fold still collide with the wall")
	_expect(game.grounded and is_zero_approx(game.position4.y) and is_zero_approx(game.vertical_speed),
		"Walking into a wall while rotating preserves gravity and landing")
	_key_event(KEY_W, false)
	_key_event(KEY_E, false)
	game._physics_process(DT)


func _test_mouse_input_lifecycle() -> void:
	_load_fixture()
	if has_mouse_capture:
		var initial_basis: Basis = game.world.camera.basis
		var initial_forward := _camera_forward()
		_mouse_event(Vector2(90.0, -25.0), 2.0)
		_expect(not game.world.camera.basis.is_equal_approx(initial_basis),
			"Captured mouse events reach the orbit camera during play")
		_expect(_camera_forward().dot(initial_forward.rotated(90.0 * game.world.mouse_sensitivity)) > 0.999,
			"Mouse sensitivity uses screen pixels independently of viewport stretching")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var before: Basis = game.world.camera.basis
	_mouse_event(Vector2(140.0, 20.0))
	_expect(game.world.camera.basis.is_equal_approx(before), "An uncaptured pointer cannot change the view")
	game._toggle_pause()
	_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Pausing releases the pointer for menus")
	_mouse_event(Vector2(140.0, 20.0))
	_expect(game.world.camera.basis.is_equal_approx(before), "Mouse motion while paused leaves the view unchanged")
	game._toggle_pause()
	if has_mouse_capture:
		_expect(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Resuming recaptures the pointer")
	game.get_window().focus_exited.emit()
	_expect(game.paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Losing application focus pauses play and releases the pointer")
	game.get_window().focus_entered.emit()
	_expect(game.paused, "Regaining focus waits for an explicit resume")
	game._toggle_pause()
	game.collected.fill(true)
	game.position4 = game.level.goal
	game._check_objectives()
	_expect(game.completed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Completing a level releases the pointer")
	before = game.world.camera.basis
	_mouse_event(Vector2(140.0, 20.0))
	_expect(game.world.camera.basis.is_equal_approx(before), "Mouse motion on the completion screen leaves the view unchanged")
	game._restart()
	if has_mouse_capture:
		_expect(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Restarting recaptures the pointer")
	game._toggle_pause()
	game._select_level(0)
	if has_mouse_capture:
		_expect(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Selecting a level recaptures the pointer")


func _test_pause_and_respawn() -> void:
	_load_fixture()
	for unused in range(30):
		game.simulate_motion(Vector2.DOWN, DT)
		game._process(DT)
	game._toggle_pause()
	var camera_position: Vector3 = game.world.camera.position
	var camera_basis: Basis = game.world.camera.basis
	for unused in range(30):
		game._process(DT)
		game._physics_process(DT)
	_expect(game.world.camera.position == camera_position and game.world.camera.basis == camera_basis,
		"Pausing freezes the follow camera")
	game._toggle_pause()
	game.position4 = Vector4(10.0, -8.0, 3.0, 2.0)
	game._physics_process(DT)
	_expect(game.position4 == game.level.start and game.world.hero.position.is_equal_approx(_project(game.level.start, 0.0)),
		"Falling immediately resets the traveler and camera target to the start")
	_expect(game.world.camera.position.distance_to(game.world.hero.position) < 9.0 and _is_behind(),
		"Respawn snaps the camera behind the traveler without flying across the map")
	game.position4 = Vector4(20.0, 0.0, 10.0, 0.0)
	_settle()
	game._restart()
	_expect(game.world.hero.position.is_equal_approx(_project(game.level.start, 0.0)) and _is_behind()
		and game.world.camera.position.distance_to(game.world.hero.position) < 9.0,
		"Restart immediately restores the follow camera at the level start")


func _test_wall_clearance() -> void:
	var fixture := _fixture()
	var wall := FoldBox.new()
	wall.center = Vector4(-2.0, 2.0, 0.0, 0.0)
	wall.size = Vector4(0.4, 4.0, 30.0, 30.0)
	wall.kind = "wall"
	fixture.boxes.append(wall)
	_expect(game.load_custom_level(fixture), "Camera obstruction fixture loads")
	_settle()
	_expect(game.world.camera.position.x > -1.8,
		"A wall behind the traveler pulls the camera in front of its visible face")
	_expect(_is_behind(), "Wall avoidance retains a view from behind the traveler")


func _test_edge_frame_clearance() -> void:
	var fixture := _fixture()
	var frame := FoldShape.new()
	frame.kind = "tesseract"
	frame.scale = 4.0
	frame.edge_thickness = 0.2
	# The near vertical beam is at X -1, Z 0 and intersects the camera arm.
	frame.center = Vector4(-3.0, 2.0, 2.0, -2.0)
	fixture.shapes = [frame]
	_expect(game.load_custom_level(fixture), "Camera edge-beam obstruction fixture loads")
	_settle()
	_expect(game.world.camera.position.x > -0.9,
		"A visible 4D edge beam pulls the camera in front of its triangle surface")
	game.position4.w = 2.0
	_settle()
	_expect(game.world.camera.position.x < -4.5,
		"Moving to a slice without the beam releases its camera obstruction")
	# Centering the open face on the arm leaves a clear line between the beams.
	frame.center.z = 0.0
	_expect(game.load_custom_level(fixture), "Camera open-frame fixture loads")
	_settle()
	_expect(game.world.camera.position.x < -4.5,
		"An edge frame's empty face does not obstruct the camera as a solid bounding box")


func _fixture() -> FoldLevel:
	var level := FoldLevel.create_default()
	level.start = Vector4.ZERO
	level.goal = Vector4(25.0, 0.0, 0.0, 0.0)
	level.boxes[0].size = Vector4(80.0, 1.0, 80.0, 80.0)
	level.seeds = [Vector4(20.0, 0.85, 20.0, 0.0)]
	level.solution.clear()
	return level


func _load_fixture() -> void:
	_expect(game.load_custom_level(_fixture()), "Open camera movement fixture loads")


func _settle() -> void:
	for unused in range(240):
		game._process(DT)


func _is_behind() -> bool:
	var offset: Vector3 = game.world.camera.position - game.world.hero.position
	var facing: Vector3 = game.world.hero_body.basis.z
	return Vector2(offset.x, offset.z).normalized().dot(Vector2(facing.x, facing.z).normalized()) < -0.99


func _project(position4: Vector4, angle: float) -> Vector3:
	return Vector3(position4.x, position4.y, position4.z * cos(angle) + position4.w * sin(angle))


func _key_event(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _mouse_event(relative: Vector2, viewport_scale: float = 1.0) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative * viewport_scale
	event.screen_relative = relative
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _camera_forward() -> Vector2:
	return -Vector2(game.world.camera.global_basis.z.x, game.world.camera.global_basis.z.z).normalized()


func _camera_right() -> Vector2:
	return Vector2(game.world.camera.global_basis.x.x, game.world.camera.global_basis.x.z).normalized()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)
