extends SceneTree
## Filled 4D hulls, watertight sections, and exact player-box swept collision.

const Solid = preload("res://scripts/solid_geometry.gd")
const Polytopes = preload("res://scripts/polytope_geometry.gd")
const CELL_COUNTS: Array[int] = [5, 8, 16, 24, 120, 600]
const CELL_VERTICES: Array[int] = [4, 8, 4, 6, 20, 4]
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_hulls_and_meshes()
	_test_exact_box_collision()
	_test_contact_silhouettes()
	_test_scale_extremes()
	print("%s: %d solid geometry checks." % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)


func _shape(kind: String, center: Vector4 = Vector4.ZERO, scale: float = 4.0) -> Dictionary:
	return {"kind": kind, "center": center, "scale": scale, "representation": "solid", "edge_thickness": 0.18}


func _test_hulls_and_meshes() -> void:
	_expect(Solid.compile_shapes([{"kind": "tesseract"}]).is_empty(), "Legacy edge shapes are excluded from filled solids")
	for index in range(Polytopes.TYPES.size()):
		var kind: String = Polytopes.TYPES[index]
		var started := Time.get_ticks_msec()
		var compiled := Solid.compile_shape(_shape(kind))
		print("  %s: %d cells, %d collision facets, first compile %d ms" % [kind, compiled.planes.size(), compiled.collision_planes.size(), Time.get_ticks_msec() - started])
		_expect(compiled.planes.size() == CELL_COUNTS[index], "%s has the correct number of solid cells" % kind)
		var hull_valid := true
		for plane: Dictionary in compiled.planes:
			var touching := 0
			for vertex: Vector4 in compiled.vertices:
				var clearance: float = plane.bound - plane.normal.dot(vertex)
				hull_valid = hull_valid and clearance > -0.0001
				if absf(clearance) < 0.0001:
					touching += 1
			hull_valid = hull_valid and touching == CELL_VERTICES[index]
		_expect(hull_valid, "%s planes bound the exact regular-polytope cells" % kind)
		_expect(Solid.intersects_player(Vector4(0, -0.625, 0, 0), compiled), "%s center is solid" % kind)
		_expect(not Solid.intersects_player(Vector4(9, -0.625, 0, 0), compiled), "%s exterior remains traversable" % kind)
		for angle in [0.0, 0.27, PI / 4.0, PI / 2.0, -0.71]:
			var pivot := Vector4(0, 0, 0.13, 0.07)
			var normal := Vector4(0, 0, -sin(angle), cos(angle))
			var points := Solid.slice_points(compiled, pivot, angle)
			var valid := points.size() >= 4
			for point in points:
				valid = valid and absf(normal.dot(point - pivot)) < 0.0001
				for plane: Dictionary in compiled.planes:
					valid = valid and plane.normal.dot(point) < plane.bound + 0.0001
			_expect(valid, "%s section lies in the actual hull and slicing plane" % kind)
			var mesh := Solid.slice_mesh(compiled, pivot, angle)
			_expect(_volume(mesh) > 0.01, "%s arbitrary-angle section has positive enclosed volume" % kind)
			_expect(_closed_outward(mesh), "%s arbitrary-angle section is closed and faces outward" % kind)
		_expect(Solid.slice_points(compiled, Vector4(0, 0, 0, 9), 0).is_empty(), "%s disappears outside its 4D extent" % kind)
		var translated := Solid.compile_shape(_shape(kind, Vector4(5, -2, 8, 3), 8.0))
		var same := true
		for vertex in range(compiled.vertices.size()):
			same = same and translated.vertices[vertex].is_equal_approx(compiled.vertices[vertex] * 2.0 + Vector4(5, -2, 8, 3))
		_expect(same, "%s uses center and circumradius in all dimensions" % kind)
		compiled.vertices[0] = Vector4.ONE * 100
		compiled.planes[0].bound = 100
		compiled.edges.clear()
		var fresh := Solid.compile_shape(_shape(kind))
		_expect(fresh.vertices[0].length() < 4.001 and fresh.planes[0].bound < 4.001 and not fresh.edges.is_empty(), "%s compiled edits cannot mutate cached unit geometry" % kind)
	var cube := Solid.compile_shape(_shape("tesseract"))
	_expect(absf(_volume(Solid.slice_mesh(cube, Vector4.ZERO, 0)) - 64.0) < 0.0001, "Tesseract cardinal slice is an exact cube")
	_expect(absf(_volume(Solid.slice_mesh(cube, Vector4.ZERO, PI / 4.0)) - 64.0 * sqrt(2.0)) < 0.0001, "Tesseract diagonal slice has exact depth")
	_expect(absf(_volume(Solid.slice_mesh(cube, Vector4(0, 0, 0, 2), 0)) - 64.0) < 0.0001, "A boundary cell still has its exact three-dimensional volume")
	var cross_polytope := Solid.compile_shape(_shape("16-cell"))
	_expect(absf(_volume(Solid.slice_mesh(cross_polytope, Vector4.ZERO, 0)) - 256.0 / 3.0) < 0.0002, "16-cell central slice is the exact octahedron")
	_expect(Solid.slice_mesh(cross_polytope, Vector4(0, 0, 0, 4), 0).get_surface_count() == 0, "A tangent vertex has no opaque volume")


func _test_exact_box_collision() -> void:
	var cube := Solid.compile_shape(_shape("tesseract"))
	_expect(not Solid.intersects_player(Vector4(0, 2, 0, 0), cube), "Standing exactly on a face is contact, not overlap")
	_expect(Solid.intersects_player(Vector4(0, 1.999, 0, 0), cube), "Penetrating a top face is blocked")
	_expect(Solid.movement_interval(cube, Vector4(-9, 0, 0, 0), 0).is_equal_approx(Vector2(-2.27, 2.27)), "A long wall sweep finds both exact X boundaries")
	_expect(Solid.movement_interval(cube, Vector4(0, 9, 0, 0), 1).is_equal_approx(Vector2(-3.25, 2)), "Vertical interval accounts for feet and height")
	var tangent := Solid.depth_movement_interval(cube, Vector4(0, 2, 0, 0), PI / 4)
	_expect(tangent.x > tangent.y, "Ground contact permits oblique travel on a solid top")
	var cross_polytope := Solid.compile_shape(_shape("16-cell", Vector4.ZERO, 1.0))
	# Original octahedral facets expanded alone incorrectly admit this point;
	# the coordinate-projection facets enforce its exact distance from the hull.
	_expect(not Solid.intersects_player(Vector4(1.3, -0.625, 0, 0), cross_polytope), "Projected facets eliminate false collision beyond an axial vertex")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3021
	for sample_index in range(120):
		var point := Vector4(rng.randf_range(-1.7, 1.7), rng.randf_range(-2.0, 1.2), rng.randf_range(-1.7, 1.7), rng.randf_range(-1.7, 1.7))
		var distance := maxf(0, absf(point.x) - 0.27) + maxf(0, absf(point.z) - 0.27) + maxf(0, absf(point.w) - 0.27)
		distance += maxf(0, maxf(point.y, -point.y - 1.25))
		_expect(Solid.intersects_player(point, cross_polytope) == (distance < 1.0 - 0.00001), "Cross-polytope collision matches independent L1 box distance")
	for kind in Polytopes.TYPES:
		var compiled := Solid.compile_shape(_shape(kind))
		for angle in [-2.35, -0.65, 0.0, 0.54, PI / 2.0, 2.41]:
			var direction := Vector4(0, 0, cos(angle), sin(angle))
			var origin := Vector4(0.1, -0.625, 0, 0) - direction * 8.0
			var interval := Solid.depth_movement_interval(compiled, origin, angle)
			_expect(interval.x < interval.y and interval.x > 0, "%s depth sweep encounters the solid hull" % kind)
			_expect(not Solid.intersects_player(origin + direction * (interval.x - 0.002), compiled)
				and Solid.intersects_player(origin + direction * (interval.x + 0.002), compiled), "%s swept entry agrees with collision" % kind)
			_expect(not Solid.intersects_player(origin + direction * (interval.y + 0.002), compiled)
				and Solid.intersects_player(origin + direction * (interval.y - 0.002), compiled), "%s swept exit agrees with collision" % kind)
			var reversed := Solid.depth_movement_interval(compiled, origin, angle + PI)
			_expect(absf(reversed.x + interval.y) < 0.0001 and absf(reversed.y + interval.x) < 0.0001, "%s reversed depth has reversed interval" % kind)
		for axis in [2, 3]:
			var point := Vector4(0, -0.3, 0.2, -0.1)
			var axis_interval := Solid.movement_interval(compiled, point, axis)
			var depth := Solid.depth_movement_interval(compiled, point, 0.0 if axis == 2 else PI / 2.0)
			_expect((axis_interval - Vector2.ONE * point[axis]).is_equal_approx(depth), "%s cardinal and depth collision use the same solid" % kind)


func _test_contact_silhouettes() -> void:
	var cube := Solid.compile_shape(_shape("tesseract"))
	_expect(Solid.slice_mesh(cube, Vector4(0, 0, 0, 2.2), 0).get_surface_count() == 0, "Opaque geometry stays on its mathematical slice")
	_expect(absf(_volume(Solid.slice_mesh(cube, Vector4(0, 0, 0, 2.2), 0, 0.27)) - 16.0 * 4.54) < 0.001,
		"Near-slice contact silhouette expands exactly in Z and W")
	_expect(Solid.slice_mesh(cube, Vector4(0, 0, 0, 2.28), 0, 0.27).get_surface_count() == 0, "Outside contact range the silhouette disappears")
	for kind in Polytopes.TYPES:
		var compiled := Solid.compile_shape(_shape(kind))
		for angle in [0.0, 0.32, PI / 4, -0.62]:
			var mesh := Solid.slice_mesh(compiled, Vector4.ZERO, angle, 0.27)
			_expect(_volume(mesh) >= _volume(Solid.slice_mesh(compiled, Vector4.ZERO, angle)) - 0.001, "%s contact volume contains its opaque slice" % kind)
			_expect(_closed_outward(mesh), "%s expanded contact silhouette is closed at %f" % [kind, angle])


func _volume(mesh: ArrayMesh) -> float:
	if mesh.get_surface_count() == 0:
		return 0.0
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var volume := 0.0
	for index in range(0, vertices.size(), 3):
		volume += vertices[index].dot(vertices[index + 1].cross(vertices[index + 2])) / 6.0
	return absf(volume)


func _test_scale_extremes() -> void:
	for kind in Polytopes.TYPES:
		var unit := Solid.compile_shape(_shape(kind, Vector4.ZERO, 1.0))
		for scale: float in [0.001, 10000.0]:
			var center := Vector4(3, -2, 5, -4) * scale
			var compiled := Solid.compile_shape(_shape(kind, center, scale))
			for angle in [0.0, 0.32, PI / 4.0]:
				var baseline := _volume(Solid.slice_mesh(unit, Vector4.ZERO, angle))
				var mesh := Solid.slice_mesh(compiled, center, angle)
				var volume := _volume(mesh) / pow(scale, 3)
				_expect(absf(volume - baseline) < baseline * 0.0002, "%s translated scale %s preserves its exact slice volume" % [kind, scale])
				var margin_mesh := Solid.slice_mesh(compiled, center, angle, scale * 0.1)
				var margin_baseline := _volume(Solid.slice_mesh(unit, Vector4.ZERO, angle, 0.1))
				_expect(absf(_volume(margin_mesh) / pow(scale, 3) - margin_baseline) < margin_baseline * 0.0002,
					"%s translated scale %s preserves its contact silhouette" % [kind, scale])
			_expect(Solid.slice_mesh(compiled, center, 0.32, 0.27).get_surface_count() > 0, "%s scale %s supports the full player contact margin" % [kind, scale])


func _closed_outward(mesh: ArrayMesh) -> bool:
	if mesh.get_surface_count() == 0:
		return false
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var edges: Dictionary = {}
	for index in range(0, vertices.size(), 3):
		if (vertices[index + 1] - vertices[index]).cross(vertices[index + 2] - vertices[index]).dot(normals[index]) >= -0.000001:
			printerr("    degenerate triangle ", vertices[index], " / ", vertices[index + 1], " / ", vertices[index + 2])
			return false
		for side in range(3):
			var a := (vertices[index + side] * 10000.0).round()
			var b := (vertices[index + (side + 1) % 3] * 10000.0).round()
			var key := "%s:%s" % [a, b] if str(a) < str(b) else "%s:%s" % [b, a]
			edges[key] = edges.get(key, 0) + 1
	for count: int in edges.values():
		if count != 2:
			printerr("    unmatched mesh edge count ", count, " edge ", edges.find_key(count))
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("  " + message)
