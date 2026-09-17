extends SceneTree
## Run with: godot --headless --path . --script tests/test_slice_geometry.gd

const Geometry = preload("res://scripts/slice_geometry.gd")
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_test_cardinal_slices()
	_test_oblique_slices()
	_test_player_overlap()
	if failures == 0:
		print("Slice geometry: all %d checks passed." % checks)
	else:
		push_error("Slice geometry: %d of %d checks failed." % [failures, checks])
	quit(1 if failures else 0)


func _test_cardinal_slices() -> void:
	var center := Vector4(7.0, 4.0, 5.0, 2.0)
	var size := Vector4(2.0, 3.0, 4.0, 6.0)
	var pivot := Vector4(100.0, 100.0, 3.0, 2.0)
	var section: Dictionary = Geometry.slice_box(center, size, pivot, 0.0)
	_expect(section.visible, "zero-angle slice is visible")
	_expect_vector(section.center, Vector3(7.0, 4.0, 2.0), "world X/Y and relative depth")
	_expect_vector(section.size, Vector3(2.0, 3.0, 4.0), "zero-angle section dimensions")

	section = Geometry.slice_box(center, size, Vector4(0.0, 0.0, 5.0, 0.0), PI / 2.0)
	_expect(section.visible, "quarter-turn slice is visible")
	_expect_vector(section.center, Vector3(7.0, 4.0, 2.0), "quarter-turn reads W as depth")
	_expect_vector(section.size, Vector3(2.0, 3.0, 6.0), "quarter-turn width equals W extent")

	section = Geometry.slice_box(center, size, pivot, PI)
	_expect(section.visible, "half-turn slice is visible")
	_expect_vector(section.center, Vector3(7.0, 4.0, -2.0), "half-turn reverses depth")
	_expect_vector(section.size, Vector3(2.0, 3.0, 4.0), "negative direction keeps positive size")

	section = Geometry.slice_box(center, size, Vector4.ZERO, 0.0)
	_expect(section.visible, "parallel slice within the W slab is visible")
	section = Geometry.slice_box(center, size, Vector4(0.0, 0.0, 0.0, 8.0), 0.0)
	_expect(not section.visible, "parallel slice outside the W slab disappears")
	section = Geometry.slice_box(center, Vector4(2.0, 3.0, 0.0, 6.0), pivot, 0.0)
	_expect(not section.visible, "degenerate boxes have no volume")


func _test_oblique_slices() -> void:
	var center := Vector4.ZERO
	var size := Vector4(2.0, 2.0, 2.0, 2.0)
	var section: Dictionary = Geometry.slice_box(center, size, Vector4.ZERO, PI / 4.0)
	_expect(section.visible, "diagonal slice is visible")
	_expect_vector(section.center, Vector3.ZERO, "centered diagonal is centered")
	_expect_vector(section.size, Vector3(2.0, 2.0, 2.0 * sqrt(2.0)), "diagonal section follows both slabs")

	section = Geometry.slice_box(center, size, Vector4(0.0, 0.0, 0.0, 2.0), PI / 4.0)
	_expect(not section.visible, "corner-only intersection has no thickness")

	# Off-center slices shorten continuously; this checks both active endpoints.
	var pivot := Vector4(0.0, 0.0, 0.0, 0.5)
	section = Geometry.slice_box(center, size, pivot, PI / 4.0)
	_expect(section.visible, "offset diagonal slice is visible")
	_expect_vector(section.center, Vector3(0.0, 0.0, -0.25 * sqrt(2.0)), "offset diagonal center")
	_expect_vector(section.size, Vector3(2.0, 2.0, 1.5 * sqrt(2.0)), "offset diagonal shrinks")
	var half_depth: float = section.size.z * 0.5
	for depth in [section.center.z - half_depth, section.center.z + half_depth]:
		var world_z: float = pivot.z + depth * cos(PI / 4.0)
		var world_w: float = pivot.w + depth * sin(PI / 4.0)
		_expect(absf(world_z) <= 1.0001 and absf(world_w) <= 1.0001, "slice endpoints stay inside the 4D solid")


func _test_player_overlap() -> void:
	var box_center := Vector4(0.0, 0.0, 0.0, 0.0)
	var box_size := Vector4(2.0, 2.0, 2.0, 2.0)
	_expect(Geometry.intersects_player(Vector4.ZERO, box_center, box_size), "player within solid penetrates")
	_expect(not Geometry.intersects_player(Vector4(0.0, 1.0, 0.0, 0.0), box_center, box_size), "feet on floor do not penetrate")
	_expect(Geometry.intersects_player(Vector4(0.0, 0.99, 0.0, 0.0), box_center, box_size), "feet below floor penetrate")
	_expect(not Geometry.intersects_player(Vector4(0.0, -2.25, 0.0, 0.0), box_center, box_size), "head touching ceiling does not penetrate")
	_expect(not Geometry.intersects_player(Vector4(1.28, 0.0, 0.0, 0.0), box_center, box_size), "side contact is not penetration")
	_expect(Geometry.intersects_player(Vector4(1.27, 0.0, 0.0, 0.0), box_center, box_size), "small side overlap is penetration")
	_expect(not Geometry.intersects_player(Vector4(0.0, 0.0, 0.0, 2.0), box_center, box_size), "separation in W prevents overlap")
	_expect(not Geometry.intersects_player(Vector4(0.0, 0.0, 2.0, 0.0), box_center, box_size), "separation in Z prevents overlap")


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _expect_vector(actual: Vector3, expected: Vector3, description: String) -> void:
	_expect(actual.distance_to(expected) < 0.0001, "%s: %s == %s" % [description, actual, expected])
