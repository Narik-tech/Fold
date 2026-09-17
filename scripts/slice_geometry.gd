class_name SliceGeometry
extends RefCounted
## Exact intersections of axis-aligned four-dimensional solids with a 3D view.
##
## X and Y remain unchanged. The view's depth coordinate, u, describes the line
## z = pivot.z + u * cos(angle), w = pivot.w + u * sin(angle).
## Consequently the pivot is always drawn at depth zero. Box centers and sizes
## use world-space (x, y, z, w); returned centers and sizes use (x, y, u).

const EPSILON: float = 0.00001


## Slice a solid with the current view. Invisible or zero-volume sections return
## {visible: false}; visible sections also contain Vector3 center and size keys.
## The slab calculation is exact for any Z-W angle, including quarter turns.
static func slice_box(
	center: Vector4, size: Vector4, pivot: Vector4, angle: float
) -> Dictionary:
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0 or size.w <= 0.0:
		return {"visible": false}

	var half_size: Vector4 = size * 0.5
	var interval: Vector2 = Vector2(-INF, INF)
	interval = _clip_slab(
		interval, pivot.z, cos(angle), center.z - half_size.z, center.z + half_size.z
	)
	if interval.x > interval.y:
		return {"visible": false}
	interval = _clip_slab(
		interval, pivot.w, sin(angle), center.w - half_size.w, center.w + half_size.w
	)
	if interval.y - interval.x <= EPSILON:
		return {"visible": false}

	return {
		"visible": true,
		"center": Vector3(center.x, center.y, (interval.x + interval.y) * 0.5),
		"size": Vector3(size.x, size.y, interval.y - interval.x),
	}


## Test a player's 4D axis-aligned volume against a world-space solid. Position
## is at the player's feet: Y runs from position.y to position.y + height,
## while X, Z, and W extend by radius in both directions. Merely touching a
## surface is not penetration, which permits standing on floors during turns.
static func intersects_player(
	position: Vector4,
	center: Vector4,
	size: Vector4,
	radius: float = 0.28,
	height: float = 1.25
) -> bool:
	if radius < 0.0 or height <= 0.0:
		return false
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0 or size.w <= 0.0:
		return false

	var half_size: Vector4 = size * 0.5
	return (
		absf(position.x - center.x) < radius + half_size.x - EPSILON
		and absf(position.z - center.z) < radius + half_size.z - EPSILON
		and absf(position.w - center.w) < radius + half_size.w - EPSILON
		and position.y < center.y + half_size.y - EPSILON
		and position.y + height > center.y - half_size.y + EPSILON
	)


## Intersect the running u interval with one axis-aligned slab. A parallel line
## either leaves the interval unchanged or produces the empty [INF, -INF].
static func _clip_slab(
	interval: Vector2, origin: float, direction: float, minimum: float, maximum: float
) -> Vector2:
	if absf(direction) < EPSILON:
		if origin < minimum - EPSILON or origin > maximum + EPSILON:
			return Vector2(INF, -INF)
		return interval

	var first: float = (minimum - origin) / direction
	var second: float = (maximum - origin) / direction
	return Vector2(maxf(interval.x, minf(first, second)), minf(interval.y, maxf(first, second)))
