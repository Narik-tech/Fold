@tool
class_name FoldBox
extends Resource
## A solid axis-aligned box in X, Y (height), Z, and W.

@export var center: Vector4 = Vector4.ZERO
@export var size: Vector4 = Vector4(1.0, 1.0, 1.0, 1.0)
@export_enum("stone", "wall", "bridge", "step") var kind: String = "stone"


func to_dictionary() -> Dictionary:
	return {"center": center, "size": size, "kind": kind}


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if not center.is_finite():
		errors.append("Center must contain finite X, Y, Z, and W coordinates.")
	if not size.is_finite():
		errors.append("Size must contain finite X, Y, Z, and W values.")
	elif size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0 or size.w <= 0.0:
		errors.append("Size must be greater than zero on every axis.")
	if kind not in ["stone", "wall", "bridge", "step"]:
		errors.append("Kind must be stone, wall, bridge, or step.")
	return errors
