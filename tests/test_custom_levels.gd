extends SceneTree
## Check the authoring-to-game boundary, including invalid and empty objectives.

const Level = preload("res://levels/level_definition.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game: Node = scene.instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound.set_muted(true)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--level="):
			var requested: FoldLevel = FoldLevel.load_level(argument.trim_prefix("--level="))
			_expect(requested != null and game.level.title == requested.title and game.started and game.hud._custom_level, "Command-line level launches the requested authored garden")
	var draft: FoldLevel = Level.create_default()
	draft.title = "A hand-built garden"
	draft.hints.clear()
	draft.seeds.clear()
	_expect(game.load_custom_level(draft), "A valid authored resource starts a playtest")
	_expect(game.started and game.levels.size() == 1 and game.level.title == draft.title, "Custom play starts with the authored level only")
	_expect(game.hud._custom_level and not game.hud._level_nav.visible, "Custom HUD hides campaign navigation")
	_expect(not game.hud._labyrinth_button.visible, "Custom play hides the campaign labyrinth shortcut")
	game._hint()
	_expect(game.hint_index == 0, "Empty custom hints are safe")
	var original_center: Vector4 = game.level.boxes[0].center
	draft.boxes[0].center.x += 100.0
	_expect(game.level.boxes[0].center == original_center, "Runtime snapshot is independent of the authoring resource")
	game.position4 = game.level.goal
	game._check_objectives()
	_expect(game.completed, "A garden with no echoes can complete at the gate")
	_expect(game.hud._next_button.text.contains("again"), "Custom completion offers replay")
	game._next_level()
	_expect(not game.completed and game.position4 == game.level.start, "Custom replay resets the current garden")
	var invalid: FoldLevel = Level.create_default()
	invalid.boxes[0].size.x = 0.0
	var previous: Dictionary = game.level.duplicate(true)
	_expect(not game.load_custom_level(invalid), "Invalid authored geometry is rejected")
	_expect(game.level == previous, "Invalid custom load preserves the running level")
	var negative_binding_count: int = InputMap.action_get_events("fold_negative").size()
	var positive_binding_count: int = InputMap.action_get_events("fold_positive").size()
	var second_game: Node = scene.instantiate()
	root.add_child(second_game)
	second_game.set_process(false)
	second_game.set_physics_process(false)
	second_game.sound.set_muted(true)
	_expect(negative_binding_count == 1 and positive_binding_count == 1, "Slice directions have separate keyboard bindings")
	_expect(InputMap.action_get_events("fold_negative").size() == negative_binding_count and InputMap.action_get_events("fold_positive").size() == positive_binding_count, "Instantiating another game does not duplicate global bindings")
	game.sound.stop_all()
	second_game.sound.stop_all()
	await create_timer(0.08).timeout
	game.queue_free()
	second_game.queue_free()
	await process_frame
	print("%s: %d custom-level integration checks." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
