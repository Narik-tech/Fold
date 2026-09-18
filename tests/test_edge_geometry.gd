extends SceneTree
## Exact beam geometry, solid-edge collision and open-face traversal.

const Edges = preload("res://scripts/edge_geometry.gd")
const Level = preload("res://levels/level_definition.gd")
const Shape = preload("res://levels/shape_definition.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var beam := Edges.make_edge(Vector4(-2, 1, 0, 0), Vector4(2, 1, 0, 0), 0.2)
	_expect(Edges.intersects_player(Vector4.ZERO, beam), "A beam collides with the player's head/body")
	_expect(not Edges.intersects_player(Vector4(0, 1.1, 0, 0), beam), "Standing on a beam is surface contact")
	_expect(not Edges.intersects_player(Vector4(0, 0, 0, 0.38), beam), "Hidden-axis separation opens passage")
	_expect(Edges.intersects_player(Vector4(0, 0, 0, 0.36), beam), "Player thickness touches near-slice edges")
	var diagonal := Edges.make_edge(Vector4(-2, 0, -2, 0), Vector4(2, 4, 2, 0), 0.2)
	_expect(not Edges.intersects_player(Vector4(-1.5, 0, 1.5, 0), diagonal), "A diagonal beam's bounding box stays hollow")
	_expect(Edges.intersects_player(Vector4(0, 1.5, 0, 0), diagonal), "The actual diagonal edge is solid")
	var support := Edges.movement_interval(diagonal, Vector4(0, 0, 0, 0), 1)
	_expect(is_equal_approx(support.y, 2.46999), "Sloped beam support comes from its exact swept edge")
	_expect(Edges.slice_points(beam, Vector4(0, 0, 0, 1), 0).is_empty(), "Off-slice beam disappears")
	_expect(not Edges.slice_points(beam, Vector4(0, 0, 0, 0.2), 0, 0.27).is_empty(), "Contact margin remains visible")
	var hidden_diagonal := Edges.make_edge(Vector4.ZERO, Vector4(4, 0, 0, 4), 0.2)
	_expect(Edges.slice_mesh([hidden_diagonal], Vector4(0, 0, 0, 2), 0, 0.27).get_surface_count() > 0,
		"Diagonal contact margins remain visible around an existing opaque slice")
	var mesh := Edges.slice_mesh([beam], Vector4.ZERO, 0)
	_expect(absf(_volume(mesh) - 4.2 * 0.2 * 0.2) < 0.0001, "Cardinal beam mesh has the exact solid volume")
	var slanted := Edges.make_edge(Vector4(-2, 0, -2, 0), Vector4(2, 0, 2, 0), 0.2)
	_expect(absf(_volume(Edges.slice_mesh([slanted], Vector4.ZERO, 0)) - 0.328) < 0.0001, "Diagonal mesh sweeps a continuous square beam")
	var oblique := Edges.make_edge(Vector4(-1, -1, -1, -1), Vector4(1, 1, 1, 1), 0.2)
	for angle in [0.0, 0.21, PI / 4, PI / 2]:
		var points := Edges.slice_points(oblique, Vector4.ZERO, angle)
		_expect(points.size() >= 4, "Intermediate fold has a convex section")
		var normal := Vector4(0, 0, -sin(angle), cos(angle))
		var on_plane := true
		for point in points:
			on_plane = on_plane and absf(normal.dot(point)) < 0.0001
		_expect(on_plane, "Section vertices lie on the actual 4D slicing plane")
		_expect(_volume(Edges.slice_mesh([oblique], Vector4.ZERO, angle)) > 0.001, "Intermediate fold renders a closed solid section")
	await _test_gameplay()
	print("%s: %d edge geometry and gameplay checks." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)


func _volume(mesh: ArrayMesh) -> float:
	if mesh.get_surface_count() == 0:
		return 0.0
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var volume := 0.0
	for i in range(0, vertices.size(), 3):
		volume += vertices[i].dot(vertices[i + 1].cross(vertices[i + 2])) / 6.0
	return absf(volume)


func _test_gameplay() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound.set_muted(true)
	var level := Level.create_default()
	level.start = Vector4(-3, 0, 0, 0)
	level.goal = Vector4(5, 0, 0, 0)
	var shape := Shape.new()
	shape.center = Vector4(0, 1, 0, 2)
	shape.scale = 4.0
	shape.edge_thickness = 0.2
	level.shapes = [shape]
	_expect(game.load_custom_level(level), "Game loads a scalable edge-frame resource")
	for frame in range(90):
		game.simulate_motion(Vector2.RIGHT, 1.0 / 60.0)
	_expect(game.position4.x > 3.0 and game.grounded, "Player walks through tesseract faces and its hollow interior")
	game.position4 = Vector4(-3, 0, 2, 0)
	game._move_axis(0, 6.0)
	_expect(absf(game.position4.x + 2.37) < 0.001, "Solid vertical edge stops even a large movement")
	game.position4 = Vector4(-3, 0, 2, 0.5)
	game._move_axis(0, 6.0)
	_expect(game.position4.x > 2.9, "Moving through W lets the player pass the edge")
	game.position4 = Vector4(2, 5, 2, 0)
	game._move_axis(1, -6.0)
	_expect(absf(game.position4.y - 3.1) < 0.001 and game.grounded, "Player can land and stand on a solid edge")
	game.world.update_slice(game.position4, 0.4, 0, true, game.collected, 0, game.RADIUS)
	_expect(game.world.shape_visuals.size() == 1, "One editable shape owns one runtime solid mesh")
	game._select_level(0)
	_expect(game.world.shape_visuals.size() == 1, "Reload replaces shape visuals instead of accumulating them")
	game.sound.stop_all()
	await create_timer(0.08).timeout
	game.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
