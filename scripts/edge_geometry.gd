@tool
extends RefCounted
## An edge is a line segment swept by a small axis-aligned 4D cube.
## Its convex volume supplies both collision and the rendered cross-section.
## Faces/cells of the parent polytope are never made solid.

const Polytopes = preload("res://scripts/polytope_geometry.gd")
const EPS := 0.00001
const BOTH_DEPTH_AXES := -1


static func compile_shapes(shapes: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for shape: Dictionary in shapes:
		if shape.get("representation", "edges") == "solid":
			continue
		var topology: Dictionary = Polytopes.topology(shape.kind)
		var edges: Array[Dictionary] = []
		var low := Vector4(INF, INF, INF, INF)
		var high := -low
		for pair: Vector2i in topology.edges:
			var a: Vector4 = shape.center + topology.vertices[pair.x] * float(shape.scale)
			var b: Vector4 = shape.center + topology.vertices[pair.y] * float(shape.scale)
			var edge := make_edge(a, b, float(shape.edge_thickness))
			edges.append(edge)
			low = low.min(edge.lo)
			high = high.max(edge.hi)
		result.append({"edges": edges, "lo": low, "hi": high})
	return result


static func make_edge(a: Vector4, b: Vector4, thickness: float) -> Dictionary:
	var half := Vector4.ONE * thickness * 0.5
	return {"a": a, "b": b, "half": half, "lo": a.min(b) - half, "hi": a.max(b) + half}


## Exact forbidden interval for the player's feet along one moving axis.
## Clip the edge parameter against the other three expanded player slabs.
## This also gives swept collision without tunneling or stair-stepped rods.
static func movement_interval(edge: Dictionary, position: Vector4, axis: int,
		radius: float = 0.27, height: float = 1.25) -> Vector2:
	var a: Vector4 = edge.a
	var direction: Vector4 = edge.b - a
	var half: Vector4 = edge.half
	var interval := Vector2(0.0, 1.0)
	for coordinate in range(4):
		if coordinate == axis:
			continue
		var minimum := position[coordinate] - (0.0 if coordinate == 1 else radius) - half[coordinate] + EPS
		var maximum := position[coordinate] + (height if coordinate == 1 else radius) + half[coordinate] - EPS
		if absf(direction[coordinate]) < EPS:
			if a[coordinate] < minimum or a[coordinate] > maximum:
				return Vector2(INF, -INF)
		else:
			var first := (minimum - a[coordinate]) / direction[coordinate]
			var last := (maximum - a[coordinate]) / direction[coordinate]
			interval.x = maxf(interval.x, minf(first, last))
			interval.y = minf(interval.y, maxf(first, last))
			if interval.x > interval.y:
				return Vector2(INF, -INF)
	var first := a[axis] + direction[axis] * interval.x
	var last := a[axis] + direction[axis] * interval.y
	return Vector2(minf(first, last) - half[axis] - (height if axis == 1 else radius),
		maxf(first, last) + half[axis] + (0.0 if axis == 1 else radius))


## Forbidden signed travel interval along the view's depth direction. Clip the
## player's center ray against the exact segment + expanded player-box volume.
## Z and W advance together, preserving the hidden coordinate even at contact.
static func depth_movement_interval(edge: Dictionary, position: Vector4, angle: float,
		radius: float = 0.27, height: float = 1.25) -> Vector2:
	var center := position + Vector4(0, height * 0.5, 0, 0)
	var travel := Vector4(0, 0, cos(angle), sin(angle))
	var half: Vector4 = edge.half + Vector4(radius, height * 0.5, radius, radius)
	var interval := Vector2(-INF, INF)
	for normal in _face_normals(edge.b - edge.a):
		var bound := maxf(normal.dot(edge.a), normal.dot(edge.b)) + normal.abs().dot(half)
		var clearance := bound - normal.dot(center)
		var speed := normal.dot(travel)
		if absf(speed) < EPS:
			# Tangential surface contact (including standing on a beam) does
			# not penetrate the solid and must not block depth movement.
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


static func intersects_player(position: Vector4, edge: Dictionary,
		radius: float = 0.27, height: float = 1.25) -> bool:
	var interval := movement_interval(edge, position, 0, radius, height)
	return position.x > interval.x + EPS and position.x < interval.y - EPS


static func bounds_overlap(bounds: Dictionary, position: Vector4, radius: float,
		height: float, padding: float = 0.0) -> bool:
	return (position.x + radius + padding >= bounds.lo.x and position.x - radius - padding <= bounds.hi.x
		and position.y + height + padding >= bounds.lo.y and position.y - padding <= bounds.hi.y
		and position.z + radius + padding >= bounds.lo.z and position.z - radius - padding <= bounds.hi.z
		and position.w + radius + padding >= bounds.lo.w and position.w - radius - padding <= bounds.hi.w)


## Slice the convex extrusion exactly. Its boundary edges are a subset of
## two 4D cubes' edges plus the 16 joins between corresponding cube corners.
## BOTH_DEPTH_AXES expands the solid by the player's axis-aligned Z/W footprint,
## giving contact silhouettes at any angle. A specific axis retains legacy margins.
static func slice_points(edge: Dictionary, pivot: Vector4, angle: float,
		margin: float = 0.0, hidden_axis: int = 3) -> Array[Vector4]:
	var normal := Vector4(0, 0, -sin(angle), cos(angle))
	var offset := normal.dot(pivot)
	var half := _margin_half(edge.half, margin, hidden_axis)
	var a: Vector4 = edge.a
	var b: Vector4 = edge.b
	var extent := absf(normal.z) * half.z + absf(normal.w) * half.w
	if minf(normal.dot(a), normal.dot(b)) - extent >= offset - EPS or maxf(normal.dot(a), normal.dot(b)) + extent <= offset + EPS:
		return []
	var corners: Array[Vector4] = []
	for endpoint in [a, b]:
		for mask in range(16):
			var point: Vector4 = endpoint
			for axis in range(4):
				point[axis] += half[axis] * (1.0 if mask & (1 << axis) else -1.0)
			corners.append(point)
	var points: Array[Vector4] = []
	for mask in range(32):
		for axis in range(5):
			var other := mask ^ (1 << axis)
			if mask < other:
				var first := corners[mask]
				var last := corners[other]
				var d0 := normal.dot(first) - offset
				var d1 := normal.dot(last) - offset
				if absf(d0) < EPS:
					_append_unique(points, first)
				if absf(d1) < EPS:
					_append_unique(points, last)
				if d0 * d1 < 0.0:
					_append_unique(points, first.lerp(last, d0 / (d0 - d1)))
	return points


static func _margin_half(half: Vector4, margin: float, hidden_axis: int) -> Vector4:
	if hidden_axis == BOTH_DEPTH_AXES:
		half.z += margin
		half.w += margin
	else:
		half[hidden_axis] += margin
	return half


static func _append_unique(points: Array[Vector4], point: Vector4) -> void:
	for existing in points:
		if existing.distance_squared_to(point) < EPS * EPS:
			return
	points.append(point)


## Supporting normals of segment + cube: cube faces, plus each two-axis
## normal perpendicular to the segment (the swept cube's ridge faces).
static func _face_normals(direction: Vector4) -> Array[Vector4]:
	var normals: Array[Vector4] = []
	for axis in range(4):
		var normal := Vector4.ZERO
		normal[axis] = 1.0
		normals.append(normal)
		normals.append(-normal)
		for other in range(axis + 1, 4):
			if absf(direction[axis]) < EPS or absf(direction[other]) < EPS:
				continue
			normal = Vector4.ZERO
			normal[axis] = direction[other]
			normal[other] = -direction[axis]
			normal = normal.normalized()
			normals.append(normal)
			normals.append(-normal)
	return normals


static func slice_mesh(edges: Array, pivot: Vector4, angle: float,
		margin: float = 0.0, hidden_axis: int = 3) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for edge: Dictionary in edges:
		if margin > 0.0:
			var direction: Vector4 = edge.b - edge.a
			var hidden_change := -direction.z * sin(angle) + direction.w * cos(angle)
			# A diagonal edge can extend past its opaque slice into the player's
			# depth footprint. Show that margin even if part is already solid.
			if absf(hidden_change) < EPS and not slice_points(edge, pivot, angle).is_empty():
				continue
		var points := slice_points(edge, pivot, angle, margin, hidden_axis)
		if points.size() < 4:
			continue
		_append_faces(edge, points, angle, margin, hidden_axis, vertices, normals)
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _append_faces(edge: Dictionary, points: Array[Vector4], angle: float,
		margin: float, hidden_axis: int, vertices: PackedVector3Array, normals: PackedVector3Array) -> void:
	var half := _margin_half(edge.half, margin, hidden_axis)
	var rendered_faces: Array[Vector4] = []
	for normal4 in _face_normals(edge.b - edge.a):
		var normal := Vector3(normal4.x, normal4.y, normal4.z * cos(angle) + normal4.w * sin(angle))
		if normal.length_squared() < EPS * EPS:
			continue
		normal = normal.normalized()
		var bound := maxf(normal4.dot(edge.a), normal4.dot(edge.b)) + normal4.abs().dot(half)
		var face: Array[Vector3] = []
		var center := Vector3.ZERO
		for point in points:
			if absf(normal4.dot(point) - bound) < EPS * 4.0:
				var projected := Vector3(point.x, point.y, point.z * cos(angle) + point.w * sin(angle))
				face.append(projected)
				center += projected
		if face.size() < 3:
			continue
		center /= float(face.size())
		# Coincident supporting planes can cut the same face at cardinal angles.
		var plane_key := Vector4(normal.x, normal.y, normal.z, normal.dot(center))
		var repeated := false
		for previous in rendered_faces:
			if previous.distance_squared_to(plane_key) < EPS * EPS:
				repeated = true
				break
		if repeated:
			continue
		rendered_faces.append(plane_key)
		var tangent := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
		var bitangent := normal.cross(tangent)
		# Some cube corners lie inside a swept face. Keep its convex boundary;
		# angular sorting alone would pull those interior points into the outline.
		var flat := PackedVector2Array()
		for point in face:
			flat.append(Vector2((point - center).dot(tangent), (point - center).dot(bitangent)))
		var hull := Geometry2D.convex_hull(flat)
		face.clear()
		for index in range(hull.size() - 1):
			face.append(center + tangent * hull[index].x + bitangent * hull[index].y)
		for index in range(1, face.size() - 1):
			var cross := (face[index] - face[0]).cross(face[index + 1] - face[0])
			if cross.length_squared() < EPS * EPS:
				continue
			# Godot uses clockwise winding when viewed from outside.
			if cross.dot(normal) > 0.0:
				vertices.append_array(PackedVector3Array([face[0], face[index + 1], face[index]]))
			else:
				vertices.append_array(PackedVector3Array([face[0], face[index], face[index + 1]]))
			normals.append_array(PackedVector3Array([normal, normal, normal]))
