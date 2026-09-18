@tool
@static_unload
extends RefCounted
## Filled convex regular 4-polytopes. Rendering intersects their actual edges
## with the view; collision clips against the exact polytope + player-box sum.

const Polytopes = preload("res://scripts/polytope_geometry.gd")
const EPS: float = 0.00001
static var _cache: Dictionary = {}


static func compile_shapes(shapes: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for shape: Dictionary in shapes:
		if shape.get("representation", "edges") == "solid":
			result.append(compile_shape(shape))
	return result


static func compile_shape(shape: Dictionary) -> Dictionary:
	var unit := _unit_data(str(shape.kind))
	var center: Vector4 = shape.center
	var scale: float = float(shape.scale)
	var vertices: Array[Vector4] = []
	var low := Vector4(INF, INF, INF, INF)
	var high := -low
	for vertex: Vector4 in unit.vertices:
		var point := center + vertex * scale
		vertices.append(point)
		low = low.min(point)
		high = high.max(point)
	return {"representation": "solid", "kind": str(shape.kind), "center": center, "scale": scale,
		"vertices": vertices, "edges": unit.edges.duplicate(),
		"planes": _transform_planes(unit.planes, center, scale),
		"collision_planes": _transform_planes(unit.collision_planes, center, scale), "lo": low, "hi": high}


static func _transform_planes(planes: Array, center: Vector4, scale: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for plane: Dictionary in planes:
		result.append({"normal": plane.normal, "bound": plane.bound * scale + plane.normal.dot(center)})
	return result


## Forbidden absolute feet-coordinate interval, including arbitrarily long
## swept motion. The unbounded direction is clipped against every sum facet.
static func movement_interval(solid: Dictionary, feet: Vector4, axis: int,
		radius: float = 0.27, height: float = 1.25) -> Vector2:
	var direction := Vector4.ZERO
	direction[axis] = 1.0
	var interval := _travel_interval(solid, feet, direction, radius, height)
	return interval + Vector2.ONE * feet[axis]


static func depth_movement_interval(solid: Dictionary, feet: Vector4, angle: float,
		radius: float = 0.27, height: float = 1.25) -> Vector2:
	return _travel_interval(solid, feet, Vector4(0, 0, cos(angle), sin(angle)), radius, height)


static func _travel_interval(solid: Dictionary, feet: Vector4, direction: Vector4,
		radius: float, height: float) -> Vector2:
	if radius < 0.0 or height <= 0.0 or solid.vertices.is_empty():
		return Vector2(INF, -INF)
	var center := feet + Vector4(0, height * 0.5, 0, 0)
	var half := Vector4(radius, height * 0.5, radius, radius)
	var interval := Vector2(-INF, INF)
	for plane: Dictionary in solid.collision_planes:
		var normal: Vector4 = plane.normal
		var clearance: float = plane.bound + normal.abs().dot(half) - normal.dot(center)
		var speed := normal.dot(direction)
		if absf(speed) < EPS:
			# Tangent contact is not penetration: standing on a surface must
			# permit horizontal movement, including during an oblique fold.
			if clearance <= EPS:
				return Vector2(INF, -INF)
			continue
		var contact := clearance / speed
		if speed > 0.0:
			interval.y = minf(interval.y, contact)
		else:
			interval.x = maxf(interval.x, contact)
		if interval.y - interval.x <= EPS:
			return Vector2(INF, -INF)
	return interval


static func intersects_player(feet: Vector4, solid: Dictionary,
		radius: float = 0.27, height: float = 1.25) -> bool:
	var interval := movement_interval(solid, feet, 0, radius, height)
	return feet.x > interval.x + EPS and feet.x < interval.y - EPS


## World-space vertices of a section. Optional margin adds the player's Z/W
## footprint for translucent contact silhouettes outside the mathematical view.
## Every edge of a Minkowski sum is a translated edge of one of its operands;
## the extra candidate segments are harmless interior points removed by faces.
static func slice_points(solid: Dictionary, pivot: Vector4, angle: float,
		margin: float = 0.0) -> Array[Vector4]:
	var center: Vector4 = solid.center
	var scale: float = solid.scale
	var points := _slice_local_points(_unit_data(solid.kind), (pivot - center) / scale, angle, margin / scale)
	for index in range(points.size()):
		points[index] = center + points[index] * scale
	return points


## Hull construction stays at unit scale: fixed world tolerances otherwise
## erase small valid shapes or lose face membership for large translated ones.
static func _slice_local_points(solid: Dictionary, pivot: Vector4, angle: float,
		margin: float) -> Array[Vector4]:
	var normal := Vector4(0, 0, -sin(angle), cos(angle))
	var offset := normal.dot(pivot)
	var minimum: float = INF
	var maximum: float = -INF
	for vertex: Vector4 in solid.vertices:
		var distance := normal.dot(vertex)
		minimum = minf(minimum, distance)
		maximum = maxf(maximum, distance)
	var extent := maxf(0.0, margin) * (absf(normal.z) + absf(normal.w))
	# A view coincident with a boundary cell can still have 3D volume.
	if minimum - extent > offset + EPS or maximum + extent < offset - EPS:
		return []
	var points: Array[Vector4] = []
	if margin <= 0.0:
		for edge: Vector2i in solid.edges:
			_intersect_segment(points, solid.vertices[edge.x], solid.vertices[edge.y], normal, offset)
	else:
		var shifts: Array[Vector4] = [Vector4(0, 0, -margin, -margin), Vector4(0, 0, margin, -margin),
			Vector4(0, 0, -margin, margin), Vector4(0, 0, margin, margin)]
		for shift in shifts:
			for edge: Vector2i in solid.edges:
				_intersect_segment(points, solid.vertices[edge.x] + shift, solid.vertices[edge.y] + shift, normal, offset)
		for vertex: Vector4 in solid.vertices:
			for pair in [Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 3), Vector2i(2, 3)]:
				_intersect_segment(points, vertex + shifts[pair.x], vertex + shifts[pair.y], normal, offset)
	return points


static func _intersect_segment(points: Array[Vector4], a: Vector4, b: Vector4,
		normal: Vector4, offset: float) -> void:
	var first := normal.dot(a) - offset
	var last := normal.dot(b) - offset
	if absf(first) < EPS:
		_append_unique(points, a)
	if absf(last) < EPS:
		_append_unique(points, b)
	# When an edge already lies in the plane, opposite rounding errors at its
	# endpoints must not create an arbitrary additional interior intersection.
	if (first < -EPS and last > EPS) or (first > EPS and last < -EPS):
		_append_unique(points, a.lerp(b, first / (first - last)))


static func _append_unique(points: Array[Vector4], point: Vector4) -> void:
	for existing in points:
		if existing.distance_squared_to(point) < EPS * EPS:
			return
	points.append(point)


## Flat-shaded watertight boundary in the same absolute (X,Y,view-depth)
## coordinate system as edge meshes and the world camera.
static func slice_mesh(solid: Dictionary, pivot: Vector4, angle: float,
		margin: float = 0.0) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var scale: float = solid.scale
	var origin: Vector4 = solid.center
	var unit := _unit_data(solid.kind)
	margin /= scale
	var points := _slice_local_points(unit, (pivot - origin) / scale, angle, margin)
	if points.size() < 4 or not _has_volume(points):
		return mesh
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var planes: Array = unit.collision_planes if margin > 0.0 else unit.planes
	var rendered: Array[Vector4] = []
	for plane: Dictionary in planes:
		var normal4: Vector4 = plane.normal
		var normal := Vector3(normal4.x, normal4.y, normal4.z * cos(angle) + normal4.w * sin(angle))
		if normal.length_squared() < EPS * EPS:
			continue
		normal = normal.normalized()
		var bound: float = plane.bound + maxf(0.0, margin) * (absf(normal4.z) + absf(normal4.w))
		var face_tolerance := EPS * 0.25 + absf(bound) * 0.00000025
		var face: Array[Vector3] = []
		var center := Vector3.ZERO
		for point in points:
			if absf(normal4.dot(point) - bound) < face_tolerance:
				var projected := Vector3(point.x, point.y, point.z * cos(angle) + point.w * sin(angle))
				face.append(projected)
				center += projected
		if face.size() < 3:
			continue
		center /= float(face.size())
		var plane_key := Vector4(normal.x, normal.y, normal.z, normal.dot(center))
		var repeated := false
		for previous in rendered:
			if previous.distance_squared_to(plane_key) < EPS * EPS:
				repeated = true
				break
		if repeated:
			continue
		rendered.append(plane_key)
		var tangent := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
		var bitangent := normal.cross(tangent)
		var flat := PackedVector2Array()
		for point in face:
			flat.append(Vector2((point - center).dot(tangent), (point - center).dot(bitangent)))
		var hull := Geometry2D.convex_hull(flat)
		var original_face := face.duplicate()
		face.clear()
		for index in range(hull.size() - 1):
			# Use the original shared vertex, avoiding separate floating-point
			# reconstructions of each face's supposedly identical boundary.
			var nearest := 0
			var distance: float = INF
			for candidate in range(flat.size()):
				var squared := flat[candidate].distance_squared_to(hull[index])
				if squared < distance:
					nearest = candidate
					distance = squared
			face.append(original_face[nearest])
		_remove_collinear(face)
		for index in range(1, face.size() - 1):
			var cross := (face[index] - face[0]).cross(face[index + 1] - face[0])
			if cross.length_squared() < EPS * EPS * EPS * EPS:
				continue
			# Godot's front faces use clockwise winding from outside.
			if cross.dot(normal) > 0.0:
				vertices.append_array(PackedVector3Array([face[0], face[index + 1], face[index]]))
			else:
				vertices.append_array(PackedVector3Array([face[0], face[index], face[index + 1]]))
			normals.append_array(PackedVector3Array([normal, normal, normal]))
	if not vertices.is_empty():
		var projected_origin := Vector3(origin.x, origin.y, origin.z * cos(angle) + origin.w * sin(angle))
		for index in range(vertices.size()):
			vertices[index] = projected_origin + vertices[index] * scale
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The projected candidates include points along true hull edges. Float noise
## can make Geometry2D retain those as tiny corners, leaving sliver triangles
## and different subdivisions on neighboring faces unless they are removed.
static func _remove_collinear(face: Array[Vector3]) -> void:
	var changed := true
	while changed and face.size() >= 3:
		changed = false
		for index in range(face.size()):
			var a := face[(index + face.size() - 1) % face.size()]
			var b := face[index]
			var c := face[(index + 1) % face.size()]
			if (b - a).cross(c - a).length() <= EPS * (c - a).length():
				face.remove_at(index)
				changed = true
				break


static func _has_volume(points: Array[Vector4]) -> bool:
	var basis: Array[Vector4] = []
	for index in range(1, points.size()):
		var direction := points[index] - points[0]
		for previous in basis:
			direction -= previous * previous.dot(direction)
		if direction.length_squared() > EPS * EPS:
			basis.append(direction.normalized())
			if basis.size() == 3:
				return true
	return false


static func _unit_data(kind: String) -> Dictionary:
	if _cache.has(kind):
		return _cache[kind]
	var topology := Polytopes.topology(kind)
	var vertices: Array[Vector4] = topology.vertices
	var normals := _cell_normals(kind)
	var planes: Array[Dictionary] = []
	for normal in normals:
		planes.append({"normal": normal, "bound": _support(vertices, normal)})
	var collision_planes := _box_sum_planes(vertices, topology.edges, planes)
	var result := {"vertices": vertices, "edges": topology.edges, "planes": planes, "collision_planes": collision_planes}
	_cache[kind] = result
	return result


## Cells correspond to vertices of the dual. The self-dual 24-cell's dual
## orientation is the D4 roots because our source uses axes plus cube corners.
static func _cell_normals(kind: String) -> Array[Vector4]:
	var normals: Array[Vector4] = []
	match kind:
		"5-cell":
			for vertex: Vector4 in Polytopes.topology(kind).vertices:
				normals.append(-vertex)
		"tesseract":
			normals = Polytopes.topology("16-cell").vertices
		"16-cell":
			normals = Polytopes.topology("tesseract").vertices
		"24-cell":
			for a in range(4):
				for b in range(a + 1, 4):
					for signs in range(4):
						var normal := Vector4.ZERO
						normal[a] = 1.0 if signs & 1 else -1.0
						normal[b] = 1.0 if signs & 2 else -1.0
						normals.append(normal.normalized())
		"120-cell":
			normals = Polytopes.topology("600-cell").vertices
		"600-cell":
			normals = Polytopes.topology("120-cell").vertices
	return normals


static func _support(vertices: Array[Vector4], normal: Vector4) -> float:
	var bound: float = -INF
	for vertex in vertices:
		bound = maxf(bound, normal.dot(vertex))
	return bound


## A 4D Minkowski sum facet either comes from a cell, a projected face,
## a projected edge, or the box itself. Include the normals of all coordinate
## projections, then discard candidates whose support face has rank below 3.
## Expanding only the original cells would over-block corners and slopes.
static func _box_sum_planes(vertices: Array[Vector4], edges: Array[Vector2i],
		planes: Array[Dictionary]) -> Array[Dictionary]:
	if vertices.is_empty():
		return []
	var candidates: Dictionary = {}
	for plane in planes:
		_add_normal(candidates, plane.normal)
	for axis in range(4):
		var normal := Vector4.ZERO
		normal[axis] = 1.0
		_add_normal(candidates, normal)
	var neighbors: Array[Array] = []
	for _index in range(vertices.size()):
		neighbors.append([])
	for edge in edges:
		neighbors[edge.x].append(edge.y)
		neighbors[edge.y].append(edge.x)
		var direction := vertices[edge.y] - vertices[edge.x]
		for a in range(4):
			for b in range(a + 1, 4):
				var normal := Vector4.ZERO
				normal[a] = direction[b]
				normal[b] = -direction[a]
				_add_normal(candidates, normal)
	for index in range(vertices.size()):
		var adjacent: Array = neighbors[index]
		for a in range(adjacent.size()):
			var first: Vector4 = vertices[adjacent[a]] - vertices[index]
			for b in range(a + 1, adjacent.size()):
				var last: Vector4 = vertices[adjacent[b]] - vertices[index]
				for omitted in range(4):
					var axes: Array[int] = []
					for coordinate in range(4):
						if coordinate != omitted:
							axes.append(coordinate)
					var cross := Vector3(first[axes[0]], first[axes[1]], first[axes[2]]).cross(
						Vector3(last[axes[0]], last[axes[1]], last[axes[2]]))
					var normal := Vector4.ZERO
					for coordinate in range(3):
						normal[axes[coordinate]] = cross[coordinate]
					_add_normal(candidates, normal)
	var result: Array[Dictionary] = []
	for candidate: Vector4 in candidates.values():
		for normal in [candidate, -candidate]:
			var bound := _support(vertices, normal)
			if _is_sum_facet(vertices, normal, bound):
				result.append({"normal": normal, "bound": bound})
	return result


static func _add_normal(candidates: Dictionary, normal: Vector4) -> void:
	if normal.length_squared() < EPS * EPS:
		return
	normal = normal.normalized()
	# Dual vertices and projected cross products use single-precision vectors.
	# Restore exact coordinate zeros before facet classification; otherwise a
	# nearly axial duplicate can cut a visible hairline into an expanded mesh.
	for coordinate in range(4):
		if absf(normal[coordinate]) < EPS * 8.0:
			normal[coordinate] = 0.0
	normal = normal.normalized()
	for coordinate in range(4):
		if absf(normal[coordinate]) > EPS:
			if normal[coordinate] < 0.0:
				normal = -normal
			break
	var key := Vector4i(roundi(normal.x / EPS), roundi(normal.y / EPS), roundi(normal.z / EPS), roundi(normal.w / EPS))
	if not candidates.has(key):
		candidates[key] = normal


static func _is_sum_facet(vertices: Array[Vector4], normal: Vector4, bound: float) -> bool:
	var basis: Array[Vector4] = []
	for coordinate in range(4):
		if absf(normal[coordinate]) < EPS:
			var direction := Vector4.ZERO
			direction[coordinate] = 1.0
			basis.append(direction)
	if basis.size() >= 3:
		return true
	var first := Vector4.ZERO
	var found := false
	for vertex in vertices:
		if absf(normal.dot(vertex) - bound) > EPS:
			continue
		if not found:
			first = vertex
			found = true
			continue
		var direction := vertex - first
		for previous in basis:
			direction -= previous * previous.dot(direction)
		if direction.length_squared() > EPS * EPS:
			basis.append(direction.normalized())
			if basis.size() >= 3:
				return true
	return false
