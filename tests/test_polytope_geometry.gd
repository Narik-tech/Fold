extends SceneTree
## Regular topology, scale, authored-data persistence, and resource isolation.
## godot --headless --path . --script tests/test_polytope_geometry.gd

const Geometry = preload("res://scripts/polytope_geometry.gd")
const ShapeDefinition = preload("res://levels/shape_definition.gd")
const LevelDefinition = preload("res://levels/level_definition.gd")
const COUNTS: Array[Vector3i] = [Vector3i(5, 10, 4), Vector3i(16, 32, 4),
	Vector3i(8, 24, 6), Vector3i(24, 96, 8), Vector3i(600, 1200, 4), Vector3i(120, 720, 12)]
const LEVEL_PATH: String = "res://test-output/polytope_roundtrip.tres"
const EXTERNAL_PATH: String = "res://test-output/polytope_external_shape.tres"
const EXTERNAL_LEVEL_PATH: String = "res://test-output/polytope_external_level.tres"

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_test_topology()
	_test_scaling_and_validation()
	_test_level_edge_warnings()
	_test_persistence()
	if failures.is_empty():
		print("PASS: %d polytope checks; six regular shapes, scale, cache, save/load, and isolation verified." % checks)
		quit(0)
	else:
		printerr("FAIL: %d of %d polytope checks failed." % [failures.size(), checks])
		quit(1)


func _test_topology() -> void:
	for index in range(Geometry.TYPES.size()):
		var kind: String = Geometry.TYPES[index]
		var topology: Dictionary = Geometry.topology(kind)
		var vertices: Array[Vector4] = topology.vertices
		var edges: Array[Vector2i] = topology.edges
		var counts: Vector3i = COUNTS[index]
		_expect(vertices.size() == counts.x and edges.size() == counts.y, "%s has the correct vertex and edge counts" % kind)
		var centroid := Vector4.ZERO
		var unit_radius: bool = true
		var unique_vertices: Dictionary = {}
		for vertex in vertices:
			centroid += vertex
			unit_radius = unit_radius and absf(vertex.length() - 1.0) < 0.00001
			unique_vertices[vertex] = true
		_expect(unit_radius and centroid.length() < 0.0001, "%s is centered at the origin with unit circumradius" % kind)
		_expect(unique_vertices.size() == vertices.size(), "%s vertices are unique" % kind)
		var degrees := PackedInt32Array()
		degrees.resize(vertices.size())
		var edge_set: Dictionary = {}
		var valid_edges: bool = true
		var length_squared: float = vertices[edges[0].x].distance_squared_to(vertices[edges[0].y])
		for edge in edges:
			valid_edges = valid_edges and edge.x >= 0 and edge.y < vertices.size() and edge.x < edge.y
			valid_edges = valid_edges and absf(vertices[edge.x].distance_squared_to(vertices[edge.y]) - length_squared) < 0.00001
			degrees[edge.x] += 1
			degrees[edge.y] += 1
			edge_set[edge] = true
		_expect(valid_edges and edge_set.size() == edges.size(), "%s has unique, equal-length, correctly indexed edges" % kind)
		var regular: bool = true
		for degree in degrees:
			regular = regular and degree == counts.z
		_expect(regular, "%s has the expected degree at every vertex" % kind)
		var all_nearest: bool = true
		for a in range(vertices.size()):
			for b in range(a + 1, vertices.size()):
				var distance: float = vertices[a].distance_squared_to(vertices[b])
				all_nearest = all_nearest and distance >= length_squared - 0.00001
				all_nearest = all_nearest and (edge_set.has(Vector2i(a, b)) == (absf(distance - length_squared) < 0.00001))
		_expect(all_nearest, "%s connects exactly its nearest neighbors" % kind)
		# Check graph connectivity independently of vertex degrees and edge totals.
		var visited: Dictionary = {0: true}
		var frontier: Array[int] = [0]
		while not frontier.is_empty():
			var current: int = frontier.pop_back()
			for edge in edges:
				var neighbor: int = edge.y if edge.x == current else (edge.x if edge.y == current else -1)
				if neighbor >= 0 and not visited.has(neighbor):
					visited[neighbor] = true
					frontier.append(neighbor)
		_expect(visited.size() == vertices.size(), "%s is connected" % kind)
		topology.vertices[0] = Vector4(99, 99, 99, 99)
		topology.edges.clear()
		var fresh: Dictionary = Geometry.topology(kind)
		_expect(fresh.edges.size() == counts.y and fresh.vertices[0].length() < 1.001, "%s cache cannot be changed through returned arrays" % kind)
	_expect(Geometry.topology("unknown").vertices.is_empty(), "Unknown kinds do not produce fallback geometry")


func _test_scaling_and_validation() -> void:
	var shape: FoldShape = ShapeDefinition.new()
	shape.center = Vector4(2, 3, -1, 4)
	shape.scale = 7.5
	for kind in Geometry.TYPES:
		shape.kind = kind
		var expected: Array[Vector4] = Geometry.topology(kind).vertices
		var actual: Array[Vector4] = shape.world_vertices()
		var scaled: bool = true
		for index in range(actual.size()):
			scaled = scaled and actual[index].is_equal_approx(shape.center + expected[index] * shape.scale)
		_expect(scaled and actual.size() == expected.size(), "%s translates and scales in all four axes" % kind)
	_expect(shape.to_dictionary().size() == 5 and shape.to_dictionary().representation == "edges",
		"Snapshots include the representation and default legacy shapes to edge frames")
	_expect(shape.validation_errors().is_empty(), "Positive finite shape dimensions validate")
	shape.scale = -1
	_expect(not shape.validation_errors().is_empty(), "Negative scale is rejected")
	shape.scale = INF
	_expect(not shape.validation_errors().is_empty(), "Infinite scale is rejected")
	shape.scale = 2
	shape.edge_thickness = 0
	_expect(not shape.validation_errors().is_empty(), "Zero edge thickness is rejected")
	shape.edge_thickness = INF
	_expect(not shape.validation_errors().is_empty(), "Infinite edge thickness is rejected")
	shape.edge_thickness = 0.1
	shape.center.w = INF
	_expect(not shape.validation_errors().is_empty(), "Infinite coordinates are rejected")
	shape.center = Vector4.ZERO
	shape.kind = "sphere"
	_expect(not shape.validation_errors().is_empty(), "Unsupported shape kinds are rejected")


func _test_level_edge_warnings() -> void:
	var level: FoldLevel = LevelDefinition.create_default()
	level.boxes.clear()
	var shape: FoldShape = ShapeDefinition.new()
	shape.center = Vector4.ZERO
	level.shapes = [shape]
	level.start = Vector4(0.0, 2.09, 2.0, 2.0)
	level.goal = Vector4(0.0, 2.09, -2.0, 2.0)
	level.solution = [level.start, level.goal]
	_expect(level.validation_errors().is_empty(), "An edge-only level is valid without box platforms")
	_expect(level.validation_warnings().is_empty(), "Shape beams can support level endpoints")
	level.start.y = 1.8
	var blocked_warning: bool = false
	for warning in level.validation_warnings():
		blocked_warning = blocked_warning or warning.contains("Start overlaps a solid shape edge")
	_expect(blocked_warning, "Endpoint validation detects obstructing edge beams")
	level.start.y = 2.09
	shape.center.x = 100
	var unsupported_warning: bool = false
	for warning in level.validation_warnings():
		unsupported_warning = unsupported_warning or warning.contains("Start is not on a platform")
	_expect(unsupported_warning, "Editing shape coordinates refreshes cached validation geometry")
	shape.center.x = 0
	level.solution = [level.start, level.goal]
	_expect(level.validation_warnings().is_empty(), "Restoring shape coordinates restores valid support")
	level.shapes.clear()
	_expect(not level.validation_errors().is_empty(), "Removing all boxes and shapes rejects an empty world")


func _test_persistence() -> void:
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var level: FoldLevel = LevelDefinition.create_default()
	_expect(not level.to_dictionary().has("shapes"), "Legacy box-only snapshots keep their original dictionary contract")
	for kind in Geometry.TYPES:
		var shape: FoldShape = ShapeDefinition.new()
		shape.kind = kind
		shape.scale = 6.5
		shape.edge_thickness = 0.12
		shape.center.w = 1.25
		level.shapes.append(shape)
	var snapshot: Dictionary = level.to_dictionary()
	snapshot.shapes[0].scale = 1.0
	snapshot.shapes[1].center.w = 12
	snapshot.shapes.pop_back()
	_expect(level.shapes.size() == 6 and level.shapes[0].scale == 6.5 and level.shapes[1].center.w == 1.25, "Runtime snapshots cannot mutate authored shapes")
	_expect(ResourceSaver.save(level, LEVEL_PATH) == OK, "A level saves all six authored shape resources")
	var first: FoldLevel = LevelDefinition.load_level(LEVEL_PATH)
	var second: FoldLevel = LevelDefinition.load_level(LEVEL_PATH)
	if _expect(first != null and second != null, "Saved shapes reopen"):
		_expect(first.to_dictionary() == level.to_dictionary(), "All shape fields survive save/load")
		first.shapes[0].scale = 20
		_expect(second.shapes[0].scale == 6.5 and level.shapes[0].scale == 6.5, "Shape subresources are independent across editor/play sessions")
		level.shapes[0].scale = 9.0
		_expect(ResourceSaver.save(level, LEVEL_PATH) == OK, "Shape edits replace the saved resource")
		var latest: FoldLevel = LevelDefinition.load_level(LEVEL_PATH)
		_expect(latest != null and latest.shapes[0].scale == 9.0, "Reopening gets newly saved shape values")
	var external: FoldShape = ShapeDefinition.new()
	_expect(ResourceSaver.save(external, EXTERNAL_PATH) == OK, "External shape fixture saves")
	var cached: FoldShape = load(EXTERNAL_PATH) as FoldShape
	level.shapes = [cached]
	_expect(ResourceSaver.save(level, EXTERNAL_LEVEL_PATH) == OK, "A level can reference an external shape")
	var external_level: FoldLevel = LevelDefinition.load_level(EXTERNAL_LEVEL_PATH)
	if _expect(external_level != null, "External shape reference reopens"):
		external_level.shapes[0].scale = 100
		_expect(cached.scale == 4 and external_level.shapes[0].resource_path.is_empty(), "Loaded external shapes become isolated local resources")
	external.scale = 8
	_expect(ResourceSaver.save(external, EXTERNAL_PATH) == OK, "External shape changes save")
	var refreshed: FoldLevel = LevelDefinition.load_level(EXTERNAL_LEVEL_PATH)
	_expect(refreshed != null and refreshed.shapes[0].scale == 8, "External shape references refresh independently of the resource cache")
	_expect(cached.scale == 4, "Refreshing does not mutate a cached external shape")
	level.shapes = [null]
	_expect(not level.validation_errors().is_empty(), "Empty shape resources fail level validation")
	level.shapes = [ShapeDefinition.new()]
	level.shapes[0].scale = 0
	_expect(not level.validation_errors().is_empty(), "Level validation includes invalid shape dimensions")
	for path in [LEVEL_PATH, EXTERNAL_PATH, EXTERNAL_LEVEL_PATH]:
		DirAccess.remove_absolute(path)


func _expect(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("  " + message)
	return condition
