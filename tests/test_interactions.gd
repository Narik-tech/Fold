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
	_test_restart_and_respawn()
	_test_completion()
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
	_tap(KEY_Q)
	_expect(not game.rotating, "Fold input cannot leave the title")
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
	_tap(KEY_Q)
	game._physics_process(0.5)
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
	_expect(game.rotating and game.active_axis == 0, "Q begins a grounded fold")
	game._physics_process(0.23)
	var elapsed: float = game.rotation_elapsed
	var partial_angle: float = game.angle
	_echo(KEY_Q)
	_expect(is_equal_approx(game.rotation_elapsed, elapsed), "Key repeat does not restart a fold")
	_tap(KEY_ESCAPE)
	game._physics_process(0.5)
	_expect(game.rotating and is_equal_approx(game.angle, partial_angle), "Pause freezes a partial fold")
	_tap(KEY_ESCAPE)
	game._physics_process(0.5)
	_expect(not game.rotating and game.active_axis == 1 and is_equal_approx(game.angle, PI / 2.0), "Resumed fold reaches the W view")
	_expect(game.position4 == before, "Folding preserves all four world coordinates")
	_tap(KEY_E)
	game._physics_process(0.71)
	_expect(not game.rotating and game.active_axis == 0 and is_zero_approx(game.angle), "E folds back to the Z view")
	_tap(KEY_SPACE)
	_expect(game.jump_buffer > 0.1, "Space fills the jump buffer")
	game.jump_buffer = 0.03
	_echo(KEY_SPACE)
	_expect(is_equal_approx(game.jump_buffer, 0.03), "Keyboard repeat does not refill the jump buffer")
	game._physics_process(DT)
	_expect(not game.grounded and game.vertical_speed > 0.0, "Buffered keyboard jump launches the player")
	_tap(KEY_Q)
	_expect(not game.rotating, "Keyboard fold is rejected in the air")


func _test_restart_and_respawn() -> void:
	game.collected[0] = true
	_tap(KEY_R)
	_expect(game.position4 == game.level.start and game.grounded, "R restores the level start and ground state")
	_expect(game._collected_count() == 0 and game.active_axis == 0 and not game.completed, "Restart clears echoes and traversal state")
	_expect(game.muted and game.sound.muted, "Restart preserves the mute preference")
	_tap(KEY_H)
	_echo(KEY_R)
	_expect(game.hint_index == 1, "Holding R does not repeatedly reload the level")
	_tap(KEY_Q)
	game._physics_process(0.2)
	_tap(KEY_R)
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
	_tap(KEY_Q)
	game._physics_process(0.7)
	_expect(game.position4 == before and not game.rotating, "Completed levels reject movement and folding")
	_tap(KEY_ENTER)
	_expect(game.level_index == 1 and not game.completed and not game.hud._completion_overlay.visible, "Enter advances from completion to the next garden")
	_echo(KEY_ENTER)
	_expect(game.level_index == 1, "Repeating Enter does not skip the newly opened garden")


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
	root.push_input(event)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)
