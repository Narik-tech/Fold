@tool
class_name FoldShape
extends Resource
## A regular 4D polytope made only of solid edge beams, with open cells/faces.

const Geometry = preload("res://scripts/polytope_geometry.gd")

@export_enum("5-cell", "tesseract", "16-cell", "24-cell", "120-cell", "600-cell") var kind: String = "tesseract"
@export var center: Vector4 = Vector4(0.0, 3.0, 0.0, 0.0)
## Center-to-vertex distance. Edge thickness is independent of this scale.
@export var scale: float = 4.0
## Full width of the solid edge beams in world units.
@export var edge_thickness: float = 0.18


func to_dictionary() -> Dictionary:
	return {"kind": kind, "center": center, "scale": scale, "edge_thickness": edge_thickness}


func world_vertices() -> Array[Vector4]:
	var vertices: Array[Vector4] = Geometry.topology(kind).vertices
	for index in range(vertices.size()):
		vertices[index] = center + vertices[index] * scale
	return vertices


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if kind not in Geometry.TYPES:
		errors.append("Choose a supported regular 4D shape.")
	if not center.is_finite():
		errors.append("Center must contain finite X, Y, Z, and W coordinates.")
	if not is_finite(scale) or scale <= 0.0:
		errors.append("Scale must be finite and greater than zero.")
	if not is_finite(edge_thickness) or edge_thickness <= 0.0:
		errors.append("Edge thickness must be finite and greater than zero.")
	return errors
