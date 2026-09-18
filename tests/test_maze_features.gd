extends SceneTree
## Optional maze metadata, forgiving checkpoints, and slice-aware wayfinding.
## godot --headless --path . --script tests/test_maze_features.gd

const Level = preload("res://levels/level_definition.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _draft() -> FoldLevel:
	var draft: FoldLevel = Level.create_default()
	draft.seeds = [Vector4(-2, 0.85, 0, 0), Vector4(2, 0.85, 0, 0)]
	draft.echo_names = ["Garden", "Crown"]
	draft.echo_checkpoints = [Vector4(-2, 0, 0, 0), Vector4(2, 0, 0, 0)]
	draft.waymark_positions = [Vector4.ZERO, Vector4(0, 0, 0, 3)]
	draft.waymark_labels = ["GARDEN", "CROWN"]
	draft.hints = ["Find Garden", "Find Crown"]
	draft.goal_hint = "Return to the amber gate."
	return draft


func _run() -> void:
	_test_metadata()
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game: Node = scene.instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound.set_muted(true)
	game.capture_mode = true
	var draft := _draft()
	_expect(game.load_custom_level(draft), "Wayfinding metadata loads into a playable session")
	game._hint()
	_expect(game.hud._lesson_label.text == draft.hints[0], "Hints begin with the first echo")
	game.position4 = draft.echo_checkpoints[1]
	game._check_objectives()
	_expect(game.respawn_position == draft.echo_checkpoints[1], "The collected echo saves its authored checkpoint")
	_expect(game.hud._toast_label.text.contains("Crown") and game.hud._toast_label.text.contains("1/2") and game.hud._toast_label.text.contains("Checkpoint saved"), "Pickup feedback names the echo and confirms progress and checkpoint")
	game._hint()
	_expect(game.hud._lesson_label.text == draft.hints[0], "Out-of-order collection preserves guidance for an earlier missing echo")
	game._hint()
	game._hint()
	_expect(game.hud._lesson_label.text == draft.goal_hint, "Repeated hints eventually explain the goal")
	game._hint()
	_expect(game.hud._lesson_label.text == draft.hints[0], "After the gate hint, guidance cycles back to the earliest missing echo")
	game.position4.y = -8.0
	game.simulate_motion(Vector2.ZERO, 1.0 / 60.0)
	_expect(game.position4 == draft.echo_checkpoints[1] and game.collected == [false, true], "Falling returns to the checkpoint and preserves collected echoes")
	game._refresh_view()
	_expect(game.world.echo_rings[1].visible and not game.world.seed_visuals[1].visible, "Collected named echoes leave a quiet ring")
	_expect(game.world.waymark_visuals[0].visible and not game.world.waymark_visuals[1].visible, "Waymarks in another W slice are hidden")
	var label: Label3D = game.world.waymark_labels[0]
	var camera: Camera3D = game.world.camera
	camera.position = label.global_position + Vector3(0, 0, 0.5)
	camera.look_at(label.global_position)
	game.world._update_waymark_labels()
	var focal_pixels := root.get_visible_rect().size.y / (2.0 * tan(deg_to_rad(camera.fov) * 0.5))
	var letter_pixels := float(label.font_size) * label.pixel_size * label.scale.x * focal_pixels / 0.5
	_expect(letter_pixels <= game.world.WAYMARK_MAX_TEXT_PIXELS + 0.01 and label.position.y >= 2.0, "Nearby waymark lettering is capped and raised above the traveler")
	game.position4.w = 3.0
	game._refresh_view()
	_expect(not game.world.waymark_visuals[0].visible and game.world.waymark_visuals[1].visible and not game.world.echo_rings[1].visible, "Waymarks and collected rings follow the current four-dimensional slice")
	game.position4 = draft.echo_checkpoints[0]
	game._check_objectives()
	_expect(game.respawn_position == draft.echo_checkpoints[0], "The most recently collected echo replaces the checkpoint")
	game._hint()
	_expect(game.hud._lesson_label.text == draft.goal_hint, "All echoes collected gives the final gate hint")
	game._restart()
	_expect(game.respawn_position == draft.start and game.position4 == draft.start and game.collected == [false, false], "Restart resets the checkpoint and echoes")
	draft.goal = draft.start + Vector4(0, 2, 0, 3)
	draft.solution = [draft.start, draft.start + Vector4(0, 0, 2, 0), draft.goal]
	game.load_custom_level(draft)
	_expect(is_zero_approx(game.world.hero_body.rotation.y), "A gate outside the current slice faces the traveler along the first visible route leg")
	var legacy: FoldLevel = Level.create_default()
	game.load_custom_level(legacy)
	_expect(is_equal_approx(game.world.hero_body.rotation.y, PI / 2.0), "A visible goal preserves the original reset heading")
	game.position4 = Vector4.ZERO
	game._check_objectives()
	game._respawn()
	_expect(game.position4 == legacy.start and game.collected == [true], "Levels without checkpoints retain the original respawn behavior")
	_expect(game.world.echo_rings.is_empty() and game.world.waymark_visuals.is_empty(), "Existing levels keep their original visuals")
	game.sound.stop_all()
	await create_timer(0.08).timeout
	game.queue_free()
	await process_frame
	print("%s: %d maze feature checks." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)


func _test_metadata() -> void:
	var legacy: FoldLevel = Level.create_default()
	var old_data := legacy.to_dictionary()
	for field: String in ["echo_names", "echo_checkpoints", "waymark_positions", "waymark_labels"]:
		_expect(not old_data.has(field), "Empty optional %s preserves the original dictionary contract" % field)
	var draft := _draft()
	_expect(draft.validation_errors().is_empty() and draft.validation_warnings().is_empty(), "Supported checkpoints and paired metadata validate")
	var data := draft.to_dictionary()
	data.echo_names[0] = "Changed"
	data.echo_checkpoints[0] = Vector4.ONE
	data.waymark_positions.clear()
	data.waymark_labels.clear()
	_expect(draft.echo_names[0] == "Garden" and draft.echo_checkpoints[0].y == 0.0 and draft.waymark_positions.size() == 2 and draft.waymark_labels.size() == 2, "Runtime metadata arrays cannot mutate the resource")
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var path := "res://test-output/maze_metadata_roundtrip.tres"
	_expect(ResourceSaver.save(draft, path) == OK, "Wayfinding metadata can be saved")
	var restored := Level.load_level(path)
	_expect(restored != null and restored.to_dictionary() == draft.to_dictionary(), "All optional metadata survives a native resource roundtrip")
	draft.echo_names.pop_back()
	_expect(not draft.validation_errors().is_empty(), "Unpaired echo names are rejected")
	draft = _draft()
	draft.echo_checkpoints.pop_back()
	_expect(not draft.validation_errors().is_empty(), "Unpaired echo checkpoints are rejected")
	draft = _draft()
	draft.waymark_labels.pop_back()
	_expect(not draft.validation_errors().is_empty(), "Unpaired waymark labels are rejected")
	draft = _draft()
	draft.echo_checkpoints[0].y = INF
	_expect(not draft.validation_errors().is_empty(), "Non-finite checkpoint coordinates are rejected")
	draft = _draft()
	draft.waymark_positions[0].w = INF
	_expect(not draft.validation_errors().is_empty(), "Non-finite waymark coordinates are rejected")
	draft = _draft()
	draft.echo_checkpoints[0].y = 2.0
	_expect("\n".join(draft.validation_warnings()).contains("Echo checkpoint 1 is not on a platform"), "Unsupported checkpoints produce a playtest warning")
	draft.echo_checkpoints[0].y = -0.2
	_expect("\n".join(draft.validation_warnings()).contains("Echo checkpoint 1 overlaps a solid box"), "Obstructed checkpoints produce a playtest warning")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
