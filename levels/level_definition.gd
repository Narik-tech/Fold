@tool
class_name FoldLevel
extends Resource
## Editable puzzle data. Feet coordinates are used for the start, exit, and
## solution; seeds are floating centers. Runtime dictionaries are independent
## copies, so a play session never changes the author's resource.

const BoxDefinition = preload("res://levels/box_definition.gd")
const Geometry = preload("res://scripts/slice_geometry.gd")
const EdgeGeometry = preload("res://scripts/edge_geometry.gd")
const PLAYER_RADIUS: float = 0.27
const PLAYER_HEIGHT: float = 1.25
const SUPPORT_EPSILON: float = 0.05

@export_category("Story")
@export var title: String = "Untitled level"
@export var subtitle: String = ""
@export_multiline var lesson: String = ""
@export var hints: Array[String] = []

@export_category("World")
@export var start: Vector4 = Vector4(-4.0, 0.0, 0.0, 0.0)
@export var goal: Vector4 = Vector4(4.0, 0.0, 0.0, 0.0)
@export var goal_hint: String = ""
@export var boxes: Array[FoldBox] = []
@export var shapes: Array[FoldShape] = []
@export var seeds: Array[Vector4] = []

@export_category("Optional wayfinding")
## When provided, each entry corresponds to the echo at the same index.
@export var echo_names: Array[String] = []
@export var echo_checkpoints: Array[Vector4] = []
## Waymarks use feet coordinates and are decorative, never solid.
@export var waymark_positions: Array[Vector4] = []
@export var waymark_labels: Array[String] = []

@export_category("Optional solution")
@export var solution: Array[Vector4] = []
## Zero-based indices of segments that need a jump: 0 joins waypoints 0 and 1.
@export var jump_segments: Array[int] = []

var _validated_shape_data: Array[Dictionary] = []
var _validated_shape_geometry: Array[Dictionary] = []


func to_dictionary() -> Dictionary:
	var runtime_boxes: Array[Dictionary] = []
	for box in boxes:
		if box != null:
			runtime_boxes.append(box.to_dictionary())
	var snapshot: Dictionary = {
		"title": title,
		"subtitle": subtitle,
		"lesson": lesson,
		"hints": hints.duplicate(),
		"start": start,
		"goal": goal,
		"goal_hint": goal_hint,
		"boxes": runtime_boxes,
		"seeds": seeds.duplicate(),
		"solution": solution.duplicate(),
		"jump_segments": jump_segments.duplicate(),
	}
	for field: String in ["echo_names", "echo_checkpoints", "waymark_positions", "waymark_labels"]:
		var values: Array = get(field)
		if not values.is_empty():
			snapshot[field] = values.duplicate()
	# Preserve the original dictionary contract for existing box-only levels.
	if not shapes.is_empty():
		var runtime_shapes: Array[Dictionary] = []
		for shape in shapes:
			if shape != null:
				runtime_shapes.append(shape.to_dictionary())
		snapshot["shapes"] = runtime_shapes
	return snapshot


static func create_default() -> FoldLevel:
	var level := FoldLevel.new()
	level.title = "My first fold"
	level.subtitle = "A new direction awaits."
	level.lesson = "Collect every echo, then reach the exit."
	level.goal_hint = "Collect the echo and walk to the exit."
	level.hints = ["The echo floats above the center of the platform."]
	var floor_box := BoxDefinition.new()
	floor_box.center = Vector4(0.0, -0.5, 0.0, 0.0)
	floor_box.size = Vector4(12.0, 1.0, 8.0, 8.0)
	level.boxes = [floor_box]
	level.seeds = [Vector4(0.0, 0.85, 0.0, 0.0)]
	level.solution = [level.start, Vector4.ZERO, level.goal]
	return level


## Bypass the resource cache so re-opening a file sees the latest saved data
## and each editor/play session owns its own geometry subresources. External
## resources are refreshed individually, then made local to the loaded level.
static func load_level(path: String) -> FoldLevel:
	if not ResourceLoader.exists(path):
		return null
	var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var level := resource as FoldLevel
	if level == null:
		return null
	for index in range(level.boxes.size()):
		var box: FoldBox = level.boxes[index]
		if box == null:
			continue
		if not box.resource_path.is_empty() and not box.is_built_in():
			# IGNORE keeps external dependencies cached; deep ignore would also
			# reload this executing script. Refresh data dependencies explicitly.
			box = ResourceLoader.load(box.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as FoldBox
			if box == null:
				return null
		level.boxes[index] = box.duplicate() as FoldBox
	for index in range(level.shapes.size()):
		var shape: FoldShape = level.shapes[index]
		if shape == null:
			continue
		if not shape.resource_path.is_empty() and not shape.is_built_in():
			shape = ResourceLoader.load(shape.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as FoldShape
			if shape == null:
				return null
		level.shapes[index] = shape.duplicate() as FoldShape
	if not level.validation_errors().is_empty():
		return null
	return level


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if title.strip_edges().is_empty():
		errors.append("Give the level a title.")
	if not start.is_finite():
		errors.append("Start must contain finite X, Y, Z, and W coordinates.")
	if not goal.is_finite():
		errors.append("Exit must contain finite X, Y, Z, and W coordinates.")
	if boxes.is_empty() and shapes.is_empty():
		errors.append("Add at least one solid box or shape for the traveler to stand on.")
	for index in range(boxes.size()):
		var box: FoldBox = boxes[index]
		if box == null:
			errors.append("Box %d is empty; assign a FoldBox resource or remove it." % (index + 1))
			continue
		for message in box.validation_errors():
			errors.append("Box %d: %s" % [index + 1, message])
	for index in range(shapes.size()):
		var shape: FoldShape = shapes[index]
		if shape == null:
			errors.append("Shape %d is empty; assign a FoldShape resource or remove it." % (index + 1))
			continue
		for message in shape.validation_errors():
			errors.append("Shape %d: %s" % [index + 1, message])
	for index in range(seeds.size()):
		if not seeds[index].is_finite():
			errors.append("Echo %d must contain finite coordinates." % (index + 1))
	if not echo_names.is_empty() and echo_names.size() != seeds.size():
		errors.append("Echo names must contain one name per echo, or be empty.")
	if not echo_checkpoints.is_empty() and echo_checkpoints.size() != seeds.size():
		errors.append("Echo checkpoints must contain one feet position per echo, or be empty.")
	if waymark_positions.size() != waymark_labels.size():
		errors.append("Waymark positions and labels must contain the same number of entries.")
	for index in range(echo_checkpoints.size()):
		if not echo_checkpoints[index].is_finite():
			errors.append("Echo checkpoint %d must contain finite coordinates." % (index + 1))
	for index in range(waymark_positions.size()):
		if not waymark_positions[index].is_finite():
			errors.append("Waymark %d must contain finite coordinates." % (index + 1))
	for index in range(solution.size()):
		if not solution[index].is_finite():
			errors.append("Solution waypoint %d must contain finite coordinates." % (index + 1))
	var seen_segments: Array[int] = []
	for segment in jump_segments:
		if segment < 0 or segment >= solution.size() - 1:
			errors.append("Jump segment %d must join two existing solution waypoints." % segment)
		elif segment in seen_segments:
			errors.append("Jump segment %d is listed more than once." % segment)
		seen_segments.append(segment)
	return errors


## Warnings invite a human playtest; they do not reject experimental puzzles.
func validation_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not validation_errors().is_empty():
		return warnings
	var edge_shapes: Array[Dictionary] = _shape_geometry_for_validation()
	_validate_position(start, "Start", warnings, edge_shapes)
	_validate_position(goal, "Exit", warnings, edge_shapes)
	for index in range(echo_checkpoints.size()):
		_validate_position(echo_checkpoints[index], "Echo checkpoint %d" % (index + 1), warnings, edge_shapes)
	if seeds.is_empty():
		warnings.append("There are no echoes; the exit will be unlocked immediately.")
	if solution.is_empty():
		warnings.append("No solution route is recorded. Playtest the level to verify it can be completed.")
	else:
		if not solution[0].is_equal_approx(start):
			warnings.append("The first solution waypoint does not match the start.")
		if not solution[-1].is_equal_approx(goal):
			warnings.append("The last solution waypoint does not match the exit.")
	return warnings


func _shape_geometry_for_validation() -> Array[Dictionary]:
	var data: Array[Dictionary] = []
	for shape in shapes:
		data.append(shape.to_dictionary())
	if data != _validated_shape_data:
		_validated_shape_data = data
		_validated_shape_geometry = EdgeGeometry.compile_shapes(data)
	return _validated_shape_geometry


func _validate_position(position: Vector4, label: String, warnings: PackedStringArray,
		edge_shapes: Array[Dictionary]) -> void:
	var supported: bool = false
	var blocked: bool = false
	for box in boxes:
		var half_size: Vector4 = box.size * 0.5
		if (
			absf(position.y - (box.center.y + half_size.y)) <= SUPPORT_EPSILON
			and absf(position.x - box.center.x) < half_size.x + PLAYER_RADIUS
			and absf(position.z - box.center.z) < half_size.z + PLAYER_RADIUS
			and absf(position.w - box.center.w) < half_size.w + PLAYER_RADIUS
		):
			supported = true
		if Geometry.intersects_player(position, box.center, box.size, PLAYER_RADIUS, PLAYER_HEIGHT):
			blocked = true
	var blocked_by_edge: bool = false
	for shape: Dictionary in edge_shapes:
		if not EdgeGeometry.bounds_overlap(shape, position, PLAYER_RADIUS, PLAYER_HEIGHT, SUPPORT_EPSILON):
			continue
		for edge: Dictionary in shape.edges:
			if not EdgeGeometry.bounds_overlap(edge, position, PLAYER_RADIUS, PLAYER_HEIGHT, SUPPORT_EPSILON):
				continue
			var interval: Vector2 = EdgeGeometry.movement_interval(edge, position, 1, PLAYER_RADIUS, PLAYER_HEIGHT)
			if interval.x <= interval.y and absf(position.y - interval.y) <= SUPPORT_EPSILON:
				supported = true
			if EdgeGeometry.intersects_player(position, edge, PLAYER_RADIUS, PLAYER_HEIGHT):
				blocked_by_edge = true
	if not supported:
		warnings.append("%s is not on a platform top. Place its feet on a supporting box or shape edge." % label)
	if blocked:
		warnings.append("%s overlaps a solid box. Leave room for the traveler's height and width." % label)
	if blocked_by_edge:
		warnings.append("%s overlaps a solid shape edge. Leave room for the traveler's height and width." % label)
	if position.y < -7.0:
		warnings.append("%s is below the fall boundary (Y -7); the traveler will respawn there." % label)
