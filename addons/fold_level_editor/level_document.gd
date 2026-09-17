@tool
extends RefCounted
## Editable copy and local history. No dependency on the editor UI or game tree.
## Selection IDs: start=0, goal=1, then boxes, then echoes.

signal changed

const Level = preload("res://levels/level_definition.gd")
const Box = preload("res://levels/box_definition.gd")
const HISTORY_LIMIT := 100

var level: FoldLevel
var path := ""
var _saved_state: Dictionary = {}
var _undo: Array[FoldLevel] = []
var _redo: Array[FoldLevel] = []
var _merge_key := ""


func _init() -> void:
	new_level()


func new_level() -> void:
	set_level(Level.create_default())


func set_level(source: FoldLevel, source_path: String = "", dirty: bool = false) -> void:
	level = source.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as FoldLevel
	# Two entries may reference one resource on disk, but each list item must
	# remain independently movable in the authoring session.
	for index in level.boxes.size():
		if level.boxes[index] != null:
			level.boxes[index] = level.boxes[index].duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as FoldBox
	path = source_path
	_saved_state = {} if dirty else level.to_dictionary().duplicate(true)
	_undo.clear()
	_redo.clear()
	_merge_key = ""
	changed.emit()


func open_level(source_path: String) -> Error:
	var loaded := Level.load_level(source_path)
	if loaded == null:
		return ERR_FILE_UNRECOGNIZED
	set_level(loaded, source_path)
	return OK


func save_level(target_path: String) -> Error:
	if not level.validation_errors().is_empty():
		return ERR_INVALID_DATA
	if not target_path.ends_with(".tres"):
		return ERR_INVALID_PARAMETER
	var result := ResourceSaver.save(level, target_path)
	if result == OK:
		path = target_path
		_saved_state = level.to_dictionary().duplicate(true)
		_merge_key = ""
		changed.emit()
	return result


func is_dirty() -> bool:
	return _saved_state != level.to_dictionary()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func break_merge() -> void:
	_merge_key = ""


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(level.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as FoldLevel)
	level = _undo.pop_back()
	_merge_key = ""
	changed.emit()


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(level.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as FoldLevel)
	level = _redo.pop_back()
	_merge_key = ""
	changed.emit()


func _remember(merge_key: String = "") -> void:
	if merge_key.is_empty() or merge_key != _merge_key:
		_undo.append(level.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as FoldLevel)
		if _undo.size() > HISTORY_LIMIT:
			_undo.pop_front()
	_redo.clear()
	_merge_key = merge_key


func _invalidate_solution() -> void:
	# A route belongs to the geometry it was recorded against. Undo restores both.
	level.solution.clear()
	level.jump_segments.clear()


func set_metadata(property: StringName, value: Variant) -> void:
	if property not in [&"title", &"subtitle", &"lesson", &"hints", &"goal_hint"]:
		return
	if level.get(property) == value:
		return
	_remember("metadata:" + str(property))
	level.set(property, value)
	changed.emit()


func object_count() -> int:
	return 2 + level.boxes.size() + level.seeds.size()


func is_box(index: int) -> bool:
	return index >= 2 and index < 2 + level.boxes.size()


func object_name(index: int) -> String:
	if index == 0:
		return "Start"
	if index == 1:
		return "Goal"
	if is_box(index):
		var kind: String = level.boxes[index - 2].kind
		return "%s %d" % ["Floor" if kind == "stone" else kind.capitalize(), index - 1]
	return "Echo %d" % (index - level.boxes.size() - 1)


func object_position(index: int) -> Vector4:
	if index == 0:
		return level.start
	if index == 1:
		return level.goal
	if is_box(index):
		return level.boxes[index - 2].center
	return level.seeds[index - 2 - level.boxes.size()]


func object_size(index: int) -> Vector4:
	return level.boxes[index - 2].size if is_box(index) else Vector4.ONE * 0.5


func set_position(index: int, position: Vector4, merge: bool = false) -> void:
	if index < 0 or index >= object_count() or object_position(index) == position:
		return
	_remember("position:%d" % index if merge else "")
	_invalidate_solution()
	if index == 0:
		level.start = position
	elif index == 1:
		level.goal = position
	elif is_box(index):
		level.boxes[index - 2].center = position
	else:
		level.seeds[index - 2 - level.boxes.size()] = position
	changed.emit()


func set_size(index: int, dimensions: Vector4) -> void:
	if not is_box(index) or object_size(index) == dimensions:
		return
	_remember("size:%d" % index)
	_invalidate_solution()
	level.boxes[index - 2].size = dimensions
	changed.emit()


func add_object(kind: String) -> int:
	_remember()
	_invalidate_solution()
	var selected: int
	if kind == "echo":
		level.seeds.append(Vector4(0.0, 0.85, 0.0, 0.0))
		selected = object_count() - 1
	else:
		var box := Box.new()
		box.kind = kind
		match kind:
			"stone":
				box.center = Vector4(0.0, -0.5, 0.0, 0.0)
				box.size = Vector4(4.0, 1.0, 4.0, 4.0)
			"wall":
				box.center = Vector4(0.0, 1.5, 0.0, 0.0)
				box.size = Vector4(0.5, 3.0, 4.0, 1.0)
			"bridge":
				box.center = Vector4(0.0, -0.25, 0.0, 0.0)
				box.size = Vector4(4.0, 0.5, 1.5, 1.5)
			_:
				box.kind = "step"
				box.center = Vector4(0.0, 0.4, 0.0, 0.0)
				box.size = Vector4(1.5, 0.8, 2.0, 2.0)
		level.boxes.append(box)
		selected = 1 + level.boxes.size()
	changed.emit()
	return selected


func delete_object(index: int) -> void:
	if index < 2 or index >= object_count():
		return
	_remember()
	if is_box(index):
		level.boxes.remove_at(index - 2)
	else:
		level.seeds.remove_at(index - 2 - level.boxes.size())
	_invalidate_solution()
	changed.emit()


func duplicate_object(index: int) -> int:
	if index < 2 or index >= object_count():
		return index
	_remember()
	_invalidate_solution()
	var offset := Vector4(1.0, 0.0, 0.0, 0.0)
	var selected: int
	if is_box(index):
		var box: FoldBox = level.boxes[index - 2].duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		box.center += offset
		level.boxes.append(box)
		selected = 1 + level.boxes.size()
	else:
		level.seeds.append(object_position(index) + offset)
		selected = object_count() - 1
	changed.emit()
	return selected
