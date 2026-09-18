extends SceneTree
## Resource migration, validation, persistence, and session isolation.
## godot --headless --path . --script tests/test_level_resources.gd

const LevelDefinition = preload("res://levels/level_definition.gd")
const BoxDefinition = preload("res://levels/box_definition.gd")
const Campaign = preload("res://scripts/level_data.gd")
const ROUNDTRIP_PATH: String = "res://test-output/resource_roundtrip.tres"
const WRONG_TYPE_PATH: String = "res://test-output/resource_wrong_type.tres"
const INVALID_PATH: String = "res://test-output/resource_invalid.tres"
const EXTERNAL_BOX_PATH: String = "res://test-output/resource_external_box.tres"
const EXTERNAL_LEVEL_PATH: String = "res://test-output/resource_external_level.tres"
const SELF_CONTAINED_PATH: String = "res://test-output/resource_self_contained.tres"

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_test_campaign_migration()
	_test_snapshot_isolation()
	_test_roundtrip_and_cache()
	_test_external_boxes()
	_test_validation()
	if failures.is_empty():
		print("PASS: %d level resource checks; original campaign, validation, save/load, and isolation verified." % checks)
		quit(0)
	else:
		printerr("FAIL: %d of %d level resource checks failed." % [failures.size(), checks])
		quit(1)


func _test_campaign_migration() -> void:
	var expected: Array[Dictionary] = _original_levels()
	var actual: Array[Dictionary] = Campaign.all_levels()
	_expect(actual.size() == 5, "The campaign contains the original gardens, the labyrinth, and the folded ascent")
	for index in range(mini(expected.size(), actual.size())):
		_expect(actual[index] == expected[index], "Level %d preserves every original authored field" % (index + 1))
	var definitions: Array[FoldLevel] = Campaign.definitions()
	for index in range(definitions.size()):
		_expect(definitions[index].validation_errors().is_empty(), "Campaign level %d has valid resource data" % (index + 1))
		_expect(definitions[index].validation_warnings().is_empty(), "Campaign level %d has supported, unobstructed endpoints" % (index + 1))
	var routes: Array[Array] = Campaign.solutions()
	_expect(routes.size() == actual.size(), "Every campaign level exposes its authored route")
	for index in range(mini(expected.size(), routes.size())):
		_expect(routes[index] == expected[index].solution, "The solutions API preserves original route %d" % (index + 1))
	if actual.size() > 3:
		var maze: Dictionary = actual[3]
		_expect(maze.title == "04  /  The fourfold labyrinth" and maze.seeds.size() == 5, "The fourth garden is the five-echo labyrinth")
		_expect(maze.solution.size() > 2 and not maze.jump_segments.is_empty(), "The labyrinth includes an authored route with vertical traversal")
		if not maze.solution.is_empty():
			_expect(maze.solution.front() == maze.start and maze.solution.back() == maze.goal, "The labyrinth route connects its entrance to its exit")
			var minimum: Vector4 = maze.solution[0]
			var maximum: Vector4 = maze.solution[0]
			for point: Vector4 in maze.solution:
				for axis in range(4):
					minimum[axis] = minf(minimum[axis], point[axis])
					maximum[axis] = maxf(maximum[axis], point[axis])
			for axis in range(4):
				_expect(maximum[axis] - minimum[axis] > 1.0, "The labyrinth route traverses dimension %s" % "XYZW"[axis])
	if actual.size() > 4:
		var ascent: Dictionary = actual[4]
		_expect(ascent.title == "05  /  The folded ascent", "The fifth garden is the folded ascent")
		_expect(ascent.boxes.is_empty() and not ascent.get("shapes", []).is_empty(), "The ascent uses 4D shapes without a continuous box floor")
		_expect(ascent.jump_segments.size() >= 8, "The ascent records a sustained sequence of shape-to-shape jumps")
		_expect(ascent.get("echo_checkpoints", []).size() == ascent.seeds.size() and not ascent.seeds.is_empty(), "Every ascent echo saves a recovery checkpoint")


func _test_snapshot_isolation() -> void:
	var level: FoldLevel = LevelDefinition.create_default()
	var snapshot: Dictionary = level.to_dictionary()
	snapshot.boxes[0].size.x = 100.0
	snapshot.boxes.append({"center": Vector4.ZERO, "size": Vector4.ONE, "kind": "wall"})
	snapshot.hints.append("Changed during play")
	snapshot.seeds[0] = Vector4.ONE
	snapshot.solution.clear()
	snapshot.jump_segments.append(0)
	_expect(level.boxes.size() == 1 and level.boxes[0].size.x == 12.0, "Runtime geometry does not mutate the authoring resource")
	_expect(level.hints.size() == 1 and is_equal_approx(level.seeds[0].y, 0.85), "Runtime hints and echoes are independent arrays")
	_expect(level.solution.size() == 3 and level.jump_segments.is_empty(), "Runtime solution data is independent")
	var first: Array[FoldLevel] = Campaign.definitions()
	var second: Array[FoldLevel] = Campaign.definitions()
	first[0].boxes[0].center.x = 50.0
	first[0].hints.clear()
	_expect(second[0].boxes[0].center.x == 0.0 and second[0].hints.size() == 3, "Campaign sessions do not share box resources or hint arrays")
	_expect(Campaign.all_levels()[0] == _original_levels()[0], "A later campaign load still matches the authored file")


func _test_roundtrip_and_cache() -> void:
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var authored: FoldLevel = LevelDefinition.create_default()
	authored.title = "A handmade level"
	authored.subtitle = "Roundtrip metadata"
	authored.lesson = "Line one\nLine two"
	authored.goal_hint = "Find the higher plane."
	authored.hints = ["First hint", "Second hint"]
	authored.boxes[0].center.w = 1.5
	authored.boxes[0].kind = "bridge"
	authored.start = Vector4(-4.0, 0.0, 0.5, 1.5)
	authored.goal = Vector4(4.0, 0.0, 0.5, 1.5)
	authored.seeds = [Vector4(0.0, 0.85, 0.5, 1.5), Vector4(2.0, 0.85, 0.5, 1.5)]
	authored.solution = [authored.start, Vector4(0.0, 0.0, 0.5, 1.5), authored.goal]
	authored.jump_segments = [1]
	if not _expect(ResourceSaver.save(authored, ROUNDTRIP_PATH) == OK, "A custom level saves as a native .tres resource"):
		return
	var restored: FoldLevel = LevelDefinition.load_level(ROUNDTRIP_PATH)
	if _expect(restored != null, "A saved custom level reopens"):
		_expect(restored.to_dictionary() == authored.to_dictionary(), "Every custom field survives the save/load roundtrip")
		_expect(restored.boxes[0] != authored.boxes[0], "Reopened geometry is a distinct resource")
	var cached: FoldLevel = load(ROUNDTRIP_PATH) as FoldLevel
	authored.title = "Saved after the first load"
	authored.boxes[0].center.w = -1.5
	_expect(ResourceSaver.save(authored, ROUNDTRIP_PATH) == OK, "An edited resource can replace its own file")
	var latest: FoldLevel = LevelDefinition.load_level(ROUNDTRIP_PATH)
	if _expect(latest != null, "The updated custom level reopens"):
		_expect(latest.title == authored.title and latest.boxes[0].center.w == -1.5, "Reopen bypasses stale root and nested resource caches")
		_expect(cached.title == "A handmade level" and cached.boxes[0].center.w == 1.5, "Reopening does not mutate an existing session")
	_expect(ResourceSaver.save(Resource.new(), WRONG_TYPE_PATH) == OK, "Wrong-type test fixture saves")
	_expect(LevelDefinition.load_level(WRONG_TYPE_PATH) == null, "Opening a different resource type returns null")
	_expect(LevelDefinition.load_level("res://test-output/missing_level.tres") == null, "Opening a missing file returns null")
	authored.boxes[0].size.w = 0.0
	_expect(ResourceSaver.save(authored, INVALID_PATH) == OK, "Invalid-data test fixture saves")
	_expect(LevelDefinition.load_level(INVALID_PATH) == null, "Opening invalid authored geometry returns null")
	for path in [ROUNDTRIP_PATH, WRONG_TYPE_PATH, INVALID_PATH]:
		DirAccess.remove_absolute(path)


func _test_external_boxes() -> void:
	var authored_box: FoldBox = BoxDefinition.new()
	_expect(ResourceSaver.save(authored_box, EXTERNAL_BOX_PATH) == OK, "External box fixture saves")
	var cached_box: FoldBox = load(EXTERNAL_BOX_PATH) as FoldBox
	var authored_level: FoldLevel = LevelDefinition.create_default()
	authored_level.boxes = [cached_box]
	_expect(ResourceSaver.save(authored_level, EXTERNAL_LEVEL_PATH) == OK, "A level can reference an external FoldBox resource")
	var first: FoldLevel = LevelDefinition.load_level(EXTERNAL_LEVEL_PATH)
	var second: FoldLevel = LevelDefinition.load_level(EXTERNAL_LEVEL_PATH)
	if _expect(first != null and second != null, "Levels with external geometry reopen"):
		first.boxes[0].center.x = 99.0
		_expect(second.boxes[0].center.x == 0.0 and cached_box.center.x == 0.0, "External geometry is independent across sessions and the resource cache")
		_expect(first.boxes[0].resource_path.is_empty(), "Loaded geometry belongs to the level being edited")
	authored_box.center.w = 3.0
	_expect(ResourceSaver.save(authored_box, EXTERNAL_BOX_PATH) == OK, "External box edits save")
	var latest: FoldLevel = LevelDefinition.load_level(EXTERNAL_LEVEL_PATH)
	if _expect(latest != null, "A level reloads edited external geometry"):
		_expect(latest.boxes[0].center.w == 3.0 and cached_box.center.w == 0.0, "External geometry refresh bypasses stale cache without modifying existing sessions")
		_expect(ResourceSaver.save(latest, SELF_CONTAINED_PATH) == OK, "An edited level saves its own geometry")
		_expect(not FileAccess.get_file_as_string(SELF_CONTAINED_PATH).contains(EXTERNAL_BOX_PATH), "Saved copies contain their geometry instead of sharing mutable external data")
	for path in [EXTERNAL_BOX_PATH, EXTERNAL_LEVEL_PATH, SELF_CONTAINED_PATH]:
		DirAccess.remove_absolute(path)


func _test_validation() -> void:
	var level: FoldLevel = LevelDefinition.create_default()
	_expect(level.validation_errors().is_empty() and level.validation_warnings().is_empty(), "The starter level is valid and ready to play")
	level.hints.clear()
	level.solution.clear()
	_expect(level.validation_errors().is_empty(), "Hints and a proof route are optional for custom levels")
	_expect(_contains(level.validation_warnings(), "No solution route"), "A missing proof route invites a human playtest")
	level.start = Vector4(100.0, 0.0, 0.0, 0.0)
	level.goal = Vector4(0.0, -0.5, 0.0, 0.0)
	_expect(_contains(level.validation_warnings(), "Start is not on a platform"), "Unsupported starts have actionable warnings")
	_expect(_contains(level.validation_warnings(), "Exit overlaps a solid"), "Obstructed exits have actionable warnings")
	level.start.y = -8.0
	_expect(_contains(level.validation_warnings(), "fall boundary"), "Endpoints below the respawn boundary are flagged")
	level = LevelDefinition.create_default()
	level.title = "   "
	level.start.x = NAN
	level.goal.w = INF
	level.boxes[0].size.w = -1.0
	level.boxes[0].kind = "unknown"
	level.boxes.append(null)
	level.seeds.append(Vector4(INF, 0.0, 0.0, 0.0))
	level.solution.append(Vector4(0.0, NAN, 0.0, 0.0))
	level.jump_segments = [-1, 0, 0, 20]
	var errors: PackedStringArray = level.validation_errors()
	_expect(_contains(errors, "title"), "Blank titles are rejected")
	_expect(_contains(errors, "Start must contain finite") and _contains(errors, "Exit must contain finite"), "Start and exit reject non-finite coordinates")
	_expect(_contains(errors, "greater than zero") and _contains(errors, "Kind must be"), "Box size and visual kind are checked")
	_expect(_contains(errors, "Box 2 is empty"), "Unassigned box resources are rejected")
	_expect(_contains(errors, "Echo 2") and _contains(errors, "waypoint 4"), "Echo and solution coordinates reject non-finite values")
	_expect(_contains(errors, "existing solution waypoints") and _contains(errors, "more than once"), "Jump segments reject invalid and duplicate indices")
	level = LevelDefinition.create_default()
	level.boxes[0].center.z = NAN
	level.boxes[0].size.x = INF
	_expect(level.validation_errors().size() == 2, "Box coordinates and sizes must both be finite")
	level.boxes.clear()
	_expect(_contains(level.validation_errors(), "at least one solid"), "An empty world is rejected")


func _contains(messages: PackedStringArray, fragment: String) -> bool:
	for message in messages:
		if fragment in message:
			return true
	return false


func _expect(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)
	return condition


# Frozen pre-refactor fixtures: changes to the campaign require an intentional update.
func _original_levels() -> Array[Dictionary]:
	return [
		{
			"title": "01  /  A direction unseen",
			"subtitle": "The wall has another edge.",
			"lesson": "Rotate your view to walk along W. The same place can open in another direction.",
			"hints": [
				"This wall fills the Z direction, but it is thin along W.",
				"Before the wall, rotate to reveal W and walk toward W +2.4.",
				"Cross the wall's X position, collect the echo, then return to W 0 for the exit."
			],
			"start": Vector4(-5.1, 0.0, 0.0, 0.0),
			"goal": Vector4(5.15, 0.0, 0.0, 0.0),
			"goal_hint": "Return to W 0 on the far side.",
			"boxes": [
				_box(Vector4(0.0, -0.5, 0.0, 0.0), Vector4(13.0, 1.0, 7.2, 7.2), "stone"),
				_box(Vector4(0.0, 1.85, 0.0, 0.0), Vector4(0.65, 3.7, 10.0, 1.6), "wall")
			],
			"seeds": [Vector4(0.0, 0.85, 0.0, 2.4)],
			"solution": [
				Vector4(-5.1, 0.0, 0.0, 0.0),
				Vector4(-2.2, 0.0, 0.0, 0.0),
				Vector4(-2.2, 0.0, 0.0, 2.4),
				Vector4(0.0, 0.0, 0.0, 2.4),
				Vector4(2.2, 0.0, 0.0, 2.4),
				Vector4(2.2, 0.0, 0.0, 0.0),
				Vector4(5.15, 0.0, 0.0, 0.0)
			],
			"jump_segments": []
		},
		{
			"title": "02  /  The missing span",
			"subtitle": "A crossing, just out of plane.",
			"lesson": "A bridge can be present in the world and absent from your current slice.",
			"hints": [
				"The space between these islands is too wide for a jump.",
				"Rotate while still on the first island. Look along positive W for a narrow bridge.",
				"At Z 0, move to W +2.65. Walk across X, then return to W 0."
			],
			"start": Vector4(-5.2, 0.0, 0.0, 0.0),
			"goal": Vector4(5.2, 0.0, 0.0, 0.0),
			"goal_hint": "Find the bridge at W +2.65.",
			"boxes": [
				_box(Vector4(-4.65, -0.5, 0.0, 0.0), Vector4(3.7, 1.0, 7.2, 7.2), "stone"),
				_box(Vector4(4.65, -0.5, 0.0, 0.0), Vector4(3.7, 1.0, 7.2, 7.2), "stone"),
				_box(Vector4(0.0, -0.25, 0.0, 2.65), Vector4(6.8, 0.5, 1.7, 1.2), "bridge")
			],
			"seeds": [Vector4(-1.4, 0.85, 0.0, 2.65), Vector4(1.4, 0.85, 0.0, 2.65)],
			"solution": [
				Vector4(-5.2, 0.0, 0.0, 0.0),
				Vector4(-4.0, 0.0, 0.0, 0.0),
				Vector4(-4.0, 0.0, 0.0, 2.65),
				Vector4(-1.4, 0.0, 0.0, 2.65),
				Vector4(1.4, 0.0, 0.0, 2.65),
				Vector4(4.0, 0.0, 0.0, 2.65),
				Vector4(4.0, 0.0, 0.0, 0.0),
				Vector4(5.2, 0.0, 0.0, 0.0)
			],
			"jump_segments": []
		},
		{
			"title": "03  /  Two turns from home",
			"subtitle": "Carry one direction into another.",
			"lesson": "Keep your position in the hidden axis. Use both Z and W, then climb toward the last echo.",
			"hints": [
				"Pass the first wall at W +2.4 and collect the first echo.",
				"Between the walls, return to W 0. Rotate back to Z and pass the next wall at Z +2.4.",
				"After the second echo, stop at X +0.85 and return to Z 0. Jump up the three low steps."
			],
			"start": Vector4(-5.2, 0.0, 0.0, 0.0),
			"goal": Vector4(5.05, 2.4, 0.0, 0.0),
			"goal_hint": "The exit waits above Z 0, W 0.",
			"boxes": [
				_box(Vector4(0.0, -0.5, 0.0, 0.0), Vector4(13.0, 1.0, 7.2, 7.2), "stone"),
				_box(Vector4(-2.7, 2.0, 0.0, 0.0), Vector4(0.7, 4.0, 10.0, 1.8), "wall"),
				_box(Vector4(0.0, 2.0, 0.0, 0.0), Vector4(0.7, 4.0, 1.8, 10.0), "wall"),
				_box(Vector4(1.9, 0.4, 0.0, 0.0), Vector4(1.2, 0.8, 2.3, 2.3), "step"),
				_box(Vector4(3.2, 0.8, 0.0, 0.0), Vector4(1.5, 1.6, 2.3, 2.3), "step"),
				_box(Vector4(4.95, 1.2, 0.0, 0.0), Vector4(2.1, 2.4, 2.3, 2.3), "step")
			],
			"seeds": [
				Vector4(-1.2, 0.85, 0.0, 2.4),
				Vector4(0.85, 0.85, 2.4, 0.0),
				Vector4(3.15, 2.45, 0.0, 0.0)
			],
			"solution": [
				Vector4(-5.2, 0.0, 0.0, 0.0),
				Vector4(-4.1, 0.0, 0.0, 0.0),
				Vector4(-4.1, 0.0, 0.0, 2.4),
				Vector4(-1.2, 0.0, 0.0, 2.4),
				Vector4(-1.2, 0.0, 0.0, 0.0),
				Vector4(-1.2, 0.0, 2.4, 0.0),
				Vector4(0.85, 0.0, 2.4, 0.0),
				Vector4(0.85, 0.0, 0.0, 0.0),
				Vector4(1.9, 0.8, 0.0, 0.0),
				Vector4(3.15, 1.6, 0.0, 0.0),
				Vector4(4.65, 2.4, 0.0, 0.0),
				Vector4(5.05, 2.4, 0.0, 0.0)
			],
			"jump_segments": [7, 8, 9]
		}
	]



static func _box(center: Vector4, size: Vector4, kind: String) -> Dictionary:
	return {"center": center, "size": size, "kind": kind}
