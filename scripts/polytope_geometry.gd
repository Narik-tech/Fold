@tool
@static_unload
extends RefCounted
## Edge skeletons of the six convex regular 4-polytopes. All vertices lie on
## the unit 3-sphere; scale is therefore the circumradius in world units.
## The 24-/600-cell construction and 120-cell dual follow Examples 1.26–1.27:
## https://www.math.ru.nl/~heckman/CoxeterGroups.pdf

const TYPES: Array[String] = ["5-cell", "tesseract", "16-cell", "24-cell", "120-cell", "600-cell"]
static var _cache: Dictionary = {}


## Return independent arrays so callers cannot damage another shape's cache.
static func topology(kind: String) -> Dictionary:
	if not _cache.has(kind):
		var vertices: Array[Vector4] = _vertices(kind)
		_cache[kind] = {"vertices": vertices, "edges": _nearest_edges(vertices)}
	return _cache[kind].duplicate(true)


static func _vertices(kind: String) -> Array[Vector4]:
	var vertices: Array[Vector4] = []
	match kind:
		"5-cell":
			var a: float = sqrt(5.0) / 4.0
			vertices = [Vector4(a, a, a, -0.25), Vector4(a, -a, -a, -0.25),
				Vector4(-a, a, -a, -0.25), Vector4(-a, -a, a, -0.25), Vector4(0, 0, 0, 1)]
		"tesseract":
			_append_cube(vertices)
		"16-cell":
			_append_axes(vertices)
		"24-cell":
			_append_axes(vertices)
			_append_cube(vertices)
		"600-cell":
			_append_axes(vertices)
			_append_cube(vertices)
			var phi: float = (1.0 + sqrt(5.0)) * 0.5
			for permutation in _even_permutations():
				for signs in range(8):
					var source := Vector4(phi * _sign(signs, 0), _sign(signs, 1), _sign(signs, 2) / phi, 0) * 0.5
					vertices.append(Vector4(source[permutation[0]], source[permutation[1]], source[permutation[2]], source[permutation[3]]))
		"120-cell":
			vertices = _dual_600_cell_vertices()
	return vertices


static func _append_axes(vertices: Array[Vector4]) -> void:
	for axis in range(4):
		var vertex := Vector4.ZERO
		vertex[axis] = 1.0
		vertices.append(vertex)
		vertices.append(-vertex)


static func _append_cube(vertices: Array[Vector4]) -> void:
	for signs in range(16):
		vertices.append(Vector4(_sign(signs, 0), _sign(signs, 1), _sign(signs, 2), _sign(signs, 3)) * 0.5)


static func _sign(bits: int, axis: int) -> float:
	return -1.0 if (bits & (1 << axis)) == 0 else 1.0


static func _even_permutations() -> Array[PackedInt32Array]:
	var result: Array[PackedInt32Array] = []
	for a in range(4):
		for b in range(4):
			if b == a:
				continue
			for c in range(4):
				if c == a or c == b:
					continue
				var permutation := PackedInt32Array([a, b, c, 6 - a - b - c])
				var inversions: int = 0
				for i in range(4):
					for j in range(i + 1, 4):
						if permutation[i] > permutation[j]:
							inversions += 1
				if inversions % 2 == 0:
					result.append(permutation)
	return result


static func _nearest_edges(vertices: Array[Vector4]) -> Array[Vector2i]:
	var edges: Array[Vector2i] = []
	var nearest_squared: float = INF
	for i in range(vertices.size()):
		for j in range(i + 1, vertices.size()):
			nearest_squared = minf(nearest_squared, vertices[i].distance_squared_to(vertices[j]))
	var tolerance: float = nearest_squared * 0.0001
	for i in range(vertices.size()):
		for j in range(i + 1, vertices.size()):
			if absf(vertices[i].distance_squared_to(vertices[j]) - nearest_squared) <= tolerance:
				edges.append(Vector2i(i, j))
	return edges


## Every four mutually adjacent 600-cell vertices form one tetrahedral cell.
## Their normalized centers are the 600 vertices of its dual, the 120-cell.
static func _dual_600_cell_vertices() -> Array[Vector4]:
	var primal: Dictionary = topology("600-cell")
	var vertices: Array[Vector4] = primal.vertices
	var neighbors: Array[Array] = []
	for _index in range(vertices.size()):
		neighbors.append([])
	for edge: Vector2i in primal.edges:
		neighbors[edge.x].append(edge.y)
		neighbors[edge.y].append(edge.x)
	var dual: Array[Vector4] = []
	for a in range(vertices.size()):
		for b: int in neighbors[a]:
			if b <= a:
				continue
			for c: int in neighbors[a]:
				if c <= b or c not in neighbors[b]:
					continue
				for d: int in neighbors[a]:
					if d > c and d in neighbors[b] and d in neighbors[c]:
						dual.append((vertices[a] + vertices[b] + vertices[c] + vertices[d]).normalized())
	return dual
