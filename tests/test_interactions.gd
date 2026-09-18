extends SceneTree
## Exercise the same InputEventKey dispatch used by a keyboard, including echo
## events, without driving the deterministic route tests or capturing images.
## godot --headless --path . --script tests/test_interactions.gd

const DT: float = 1.0 / 60.0
var game: Node
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await process_frame
	_test_title_and_mute()
	_test_pause_and_echo()
	_test_fold_and_jump()
	_test_rotation_timing_and_movement()
	_test_restart_and_respawn()
	_test_completion()
	_test_campaign_navigation()
	# Synchronous input checks finish before the next real audio mix tick.
	game.sound.stop_all()
	await create_timer(0.08).timeout
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: all %d keyboard interaction and state-transition checks passed." % checks)
		quit(0)
	else:
		printerr("FAIL: %d of %d interaction checks failed." % [failures.size(), checks])
		quit(1)


func _test_title_and_mute() -> void:
	_expect(not game.started and game.hud._title_overlay.visible, "Game begins at the title")
	_key_event(KEY_Q, true)
	game._physics_process(0.25)
	_key_event(KEY_Q, false)
	_expect(not game.rotating and is_zero_approx(game.angle), "Held slice input cannot leave the title")
	_tap(KEY_M)
	_expect(game.muted and game.sound.muted, "Mute works on the title")
	_echo(KEY_M)
	_expect(game.muted and game.sound.muted, "Keyboard repeat does not retrigger mute")
	_tap(KEY_ENTER)
	_expect(game.started and not game.hud._title_overlay.visible, "Enter starts through keyboard dispatch")
	_expect(game.muted and game.sound.muted, "Starting preserves sound preference")


func _test_pause_and_echo() -> void:
	_tap(KEY_ESCAPE)
	_expect(game.paused and game.hud._pause_overlay.visible, "Escape pauses and shows the menu")
	_echo(KEY_ESCAPE)
	_expect(game.paused, "Holding Escape does not unpause")
	var before: Vector4 = game.position4
	_tap(KEY_SPACE)
	_key_event(KEY_Q, true)
	game._physics_process(0.5)
	_key_event(KEY_Q, false)
	_expect(game.position4 == before and not game.rotating and is_zero_approx(game.jump_buffer), "Pause ignores jump and fold and freezes physics")
	_tap(KEY_M)
	_expect(not game.muted and not game.sound.muted, "Mute can be toggled while paused")
	_tap(KEY_M)
	_tap(KEY_ESCAPE)
	_expect(not game.paused and not game.hud._pause_overlay.visible, "Escape resumes the game")
	_tap(KEY_H)
	_expect(game.hint_index == 1, "Hint key advances once")
	_echo(KEY_H)
	_expect(game.hint_index == 1, "Holding H does not skip progressive hints")


func _test_fold_and_jump() -> void:
	var before: Vector4 = game.position4
	_tap(KEY_Q)
	game._physics_process(DT)
	_expect(not game.rotating and is_zero_approx(game.angle), "A released tap does not start an automatic fold")
	_key_event(KEY_Q, true)
	_key_event(KEY_D, true)
	game._physics_process(0.2)
	_expect(game.rotating and is_equal_approx(game.angle, -PI * 0.1), "Holding Q gradually turns the slice in the negative direction")
	_expect(game.position4 == before, "Held slice rotation pauses walking even when a movement key is held")
	_key_event(KEY_D, false)
	game._physics_process(0.1)
	_expect(is_equal_approx(game.angle, -PI * 0.15), "Q keeps turning on subsequent frames without keyboard repeat")
	var partial_angle: float = game.angle
	_key_event(KEY_Q, true, true)
	_expect(is_equal_approx(game.angle, partial_angle), "Keyboard repeat does not add an immediate angle step")
	_tap(KEY_ESCAPE)
	game._physics_process(0.5)
	_expect(is_equal_approx(game.angle, partial_angle), "Pause freezes a held partial rotation")
	_key_event(KEY_Q, false)
	_tap(KEY_ESCAPE)
	game._physics_process(DT)
	_expect(not game.rotating and is_equal_approx(game.angle, partial_angle), "Releasing Q while paused leaves the slice stopped after resuming")
	_key_event(KEY_E, true)
	game._physics_process(0.1)
	_expect(game.rotating and is_equal_approx(game.angle, partial_angle + PI * 0.05), "Holding E reverses the rotation direction")
	partial_angle = game.angle
	_key_event(KEY_Q, true)
	game._physics_process(0.1)
	_expect(not game.rotating and is_equal_approx(game.angle, partial_angle), "Holding Q and E together cancels rotation")
	_key_event(KEY_E, false)
	game._physics_process(0.1)
	_expect(game.rotating and is_equal_approx(game.angle, partial_angle - PI * 0.05), "Releasing E while holding Q resumes negative rotation")
	partial_angle = game.angle
	_key_event(KEY_Q, false)
	game._physics_process(DT)
	_expect(not game.rotating and is_equal_approx(game.angle, partial_angle), "Releasing both keys stops at the current intermediate angle")
	_expect(game.position4 == before, "Rotating the slice preserves all four world coordinates")
	game._restart()
	_key_event(KEY_E, true)
	game._physics_process(1.2)
	_expect(game.rotating and is_equal_approx(game.angle, PI * 0.6), "Holding E continues beyond the W view without snapping")
	game._physics_process(1.2)
	_expect(game.rotating and is_equal_approx(game.angle, -PI * 0.8), "Held rotation wraps smoothly through a half turn")
	_tap(KEY_SPACE)
	game._physics_process(0.2)
	_expect(game.grounded and is_zero_approx(game.jump_buffer), "A buffered jump expires while rotation holds the traveler in place")
	_key_event(KEY_E, false)
	game._physics_process(DT)
	_expect(game.grounded and is_zero_approx(game.vertical_speed), "Releasing rotation does not trigger an expired jump")
	game._restart()
	_tap(KEY_SPACE)
	_expect(game.jump_buffer > 0.1, "Space fills the jump buffer")
	game.jump_buffer = 0.03
	_echo(KEY_SPACE)
	_expect(is_equal_approx(game.jump_buffer, 0.03), "Keyboard repeat does not refill the jump buffer")
	game._physics_process(DT)
	_expect(not game.grounded and game.vertical_speed > 0.0, "Buffered keyboard jump launches the player")
	_key_event(KEY_Q, true)
	game._physics_process(DT)
	_key_event(KEY_Q, false)
	_expect(not game.rotating and is_zero_approx(game.angle), "Held slice input is rejected in the air")


func _test_rotation_timing_and_movement() -> void:
	game._restart()
	game.rotate_slice(1.0, 0.5)
	var coarse_angle: float = game.angle
	game._restart()
	for unused in range(60):
		game.rotate_slice(1.0, 0.5 / 60.0)
	_expect(is_equal_approx(game.angle, coarse_angle) and is_equal_approx(game.angle, PI / 4.0), "The same hold duration produces the same angle at different frame rates")
	for test_angle: float in [-3.0 * PI / 4.0, -PI / 4.0, PI / 4.0, 3.0 * PI / 4.0]:
		game._restart()
		game.rotate_slice(signf(test_angle), absf(test_angle) / (PI / 2.0))
		game.rotate_slice(0.0, DT)
		var before: Vector4 = game.position4
		game.simulate_motion(Vector2.DOWN, 0.1)
		var displacement: Vector4 = game.position4 - before
		var travel: float = game.SPEED * 0.1
		_expect(is_equal_approx(displacement.z, cos(test_angle) * travel) and is_equal_approx(displacement.w, sin(test_angle) * travel), "Movement follows the signed intermediate slice at angle %.2f" % test_angle)
		_expect(is_equal_approx(Vector2(displacement.z, displacement.w).length(), travel), "Intermediate slice movement preserves travel speed at angle %.2f" % test_angle)


func _test_restart_and_respawn() -> void:
	game.collected[0] = true
	_tap(KEY_R)
	_expect(game.position4 == game.level.start and game.grounded, "R restores the level start and ground state")
	_expect(game._collected_count() == 0 and game.active_axis == 0 and not game.completed, "Restart clears echoes and traversal state")
	_expect(game.muted and game.sound.muted, "Restart preserves the mute preference")
	_tap(KEY_H)
	_echo(KEY_R)
	_expect(game.hint_index == 1, "Holding R does not repeatedly reload the level")
	_key_event(KEY_Q, true)
	game._physics_process(0.2)
	_tap(KEY_R)
	_key_event(KEY_Q, false)
	_expect(not game.rotating and is_zero_approx(game.angle) and game.active_axis == 0, "Restart cancels an in-progress fold")
	_tap(KEY_ESCAPE)
	game.hud.restart_requested.emit()
	_expect(not game.paused and not game.hud._pause_overlay.visible, "Pause-menu restart closes the overlay and resumes")
	game.collected[0] = true
	game.position4 = Vector4(-5.0, -8.0, 2.0, 2.0)
	game.vertical_speed = -10.0
	game.grounded = false
	game._physics_process(DT)
	_expect(game.position4 == game.level.start and game.grounded, "Falling below the level respawns on the floor")
	_expect(game._collected_count() == 1, "Fall recovery keeps collected echoes")
	game._physics_process(DT)
	_expect(game.position4 == game.level.start and game.grounded, "A subsequent physics frame keeps respawn supported")


func _test_completion() -> void:
	game.position4 = game.level.goal
	game._check_objectives()
	_expect(game.completed and game.hud._completion_overlay.visible, "Unlocked gate opens the completion screen")
	_tap(KEY_ESCAPE)
	_expect(not game.paused, "Escape does not put a pause menu over completion")
	var before: Vector4 = game.position4
	_key_event(KEY_Q, true)
	game._physics_process(0.7)
	_key_event(KEY_Q, false)
	_expect(game.position4 == before and not game.rotating, "Completed levels reject movement and folding")
	_tap(KEY_ENTER)
	_expect(game.level_index == 1 and not game.completed and not game.hud._completion_overlay.visible, "Enter advances from completion to the next garden")
	_echo(KEY_ENTER)
	_expect(game.level_index == 1, "Repeating Enter does not skip the newly opened garden")


func _test_campaign_navigation() -> void:
	var total: int = game.levels.size()
	_expect(total == 4, "The maze is available as the fourth campaign garden")
	_expect(game.hud._level_buttons.size() == total and game.hud._pause_level_buttons.size() == total, "Both chapter menus show every campaign level")
	_expect(game.hud._campaign_label.text.begins_with("%d GARDENS" % total), "The title reflects the campaign's actual garden count")
	_tap(KEY_ESCAPE)
	_expect(game.hud._pause_chapters.visible, "Pause exposes chapter selection while the cursor is free")
	game.hud._pause_level_buttons[total - 1].pressed.emit()
	_expect(game.level_index == total - 1 and not game.paused, "The last pause-menu chapter button opens the labyrinth and resumes play")
	_expect(game.level.title == "04  /  The fourfold labyrinth" and game.hud._seed_label.text == "0 / 5", "The labyrinth starts with its five-echo objective")
	game.position4 = game.level.goal
	game._check_objectives()
	_expect(not game.completed, "The labyrinth exit waits for all five echoes")
	game.collected.fill(true)
	game._check_objectives()
	_expect(game.completed and game.hud._final_level, "The fourth garden receives campaign completion")
	_tap(KEY_ENTER)
	_expect(game.level_index == 0 and not game.completed, "Finishing the labyrinth returns to the first garden")
	_tap(KEY_ESCAPE)
	game.hud._pause_level_buttons[total - 2].pressed.emit()
	game.collected.fill(true)
	game.position4 = game.level.goal
	game._check_objectives()
	_expect(game.completed and not game.hud._final_level, "The third garden now leads onward instead of ending the campaign")
	_tap(KEY_ENTER)
	_expect(game.level_index == total - 1 and not game.completed, "The third garden advances directly to the labyrinth")
	game._select_level(0)
	game.started = false
	game._sync_mouse_mode()
	game.hud.show_title()
	_expect(game.hud._labyrinth_button.visible, "The title offers a direct labyrinth shortcut")
	game.hud._labyrinth_button.pressed.emit()
	_expect(game.level_index == 3 and game.started and not game.hud._title_overlay.visible, "The title shortcut starts the labyrinth immediately")


func _tap(key: Key) -> void:
	_key_event(key, true)
	_key_event(key, false)


func _echo(key: Key) -> void:
	_key_event(key, true, true)
	_key_event(key, false)


func _key_event(key: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)
