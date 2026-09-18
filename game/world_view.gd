class_name FoldWorld
extends Node3D
## Self-contained visual projection of a four-dimensional level.
## The session supplies simulation values explicitly; this scene never reads its parent.

const Geometry = preload("res://scripts/slice_geometry.gd")
const Edges = preload("res://scripts/edge_geometry.gd")

@onready var level_root: Node3D = $LevelGeometry

var box_visuals: Array[MeshInstance3D] = []
var shape_visuals: Array[MeshInstance3D] = []
var shape_fringes: Array[MeshInstance3D] = []
var shape_solids: Array[Dictionary] = []
var _shape_slice_key := Vector4(INF, INF, INF, INF)
var seed_visuals: Array[Node3D] = []
var camera: Camera3D
var _level: Dictionary = {}
var decorations: Array[Dictionary] = []
var materials: Dictionary = {}
var hero: Node3D
var hero_body: Node3D
var scarf: MeshInstance3D
var hero_shadow: MeshInstance3D
var goal_root: Node3D
var portal_inner: MeshInstance3D
var motes: Array[MeshInstance3D] = []


func _ready() -> void:
	_setup_materials()
	_setup_environment()
	_build_hero()


## Rebuild only level-owned visuals; environment, camera, and traveler persist.
func load_level(data: Dictionary, decoration_seed: int = 0) -> void:
	_level = data
	for child in level_root.get_children():
		level_root.remove_child(child)
		child.queue_free()
	box_visuals.clear()
	shape_visuals.clear()
	shape_fringes.clear()
	shape_solids = Edges.compile_shapes(_level.get("shapes", []))
	_shape_slice_key = Vector4(INF, INF, INF, INF)
	seed_visuals.clear()
	decorations.clear()
	for box: Dictionary in _level.boxes:
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		mesh.material_override = materials.get(box.kind, materials.stone)
		level_root.add_child(mesh)
		box_visuals.append(mesh)
	for shape in shape_solids:
		var mesh := MeshInstance3D.new()
		mesh.material_override = materials.edge
		level_root.add_child(mesh)
		shape_visuals.append(mesh)
		var fringe := MeshInstance3D.new()
		fringe.material_override = materials.fringe
		fringe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level_root.add_child(fringe)
		shape_fringes.append(fringe)
	for seed: Vector4 in _level.seeds:
		var root := Node3D.new()
		level_root.add_child(root)
		var crystal := _mesh_sphere(0.22, materials.gold, 4, 2)
		crystal.scale = Vector3(0.8, 1.55, 0.8)
		root.add_child(crystal)
		var halo := _ring(0.4, 0.013, materials.gold_dim)
		root.add_child(halo)
		var beam := _box(Vector3(0.018, 0.4, 0.018), materials.gold_dim)
		beam.position.y = -0.52
		root.add_child(beam)
		seed_visuals.append(root)
	_build_goal()
	_build_decorations(decoration_seed)


func update_slice(position4: Vector4, angle: float, _active_axis: int, rotating: bool,
		collected: Array[bool], clock: float, player_radius: float) -> void:
	if _level.is_empty():
		return
	var visible_player_depth := position4.z * cos(angle) + position4.w * sin(angle)
	_update_shape_slices(position4, angle, rotating, player_radius)
	for i in range(box_visuals.size()):
		var box: Dictionary = _level.boxes[i]
		var section: Dictionary = Geometry.slice_box(box.center, box.size, position4, angle)
		var visual := box_visuals[i]
		var is_fringe := false
		# A finite traveler can touch a solid just outside the mathematical plane.
		# Show those contact margins as translucent silhouettes rather than letting
		# them become invisible walls or invisible support at a slice boundary.
		if not section.visible and not rotating:
			# The traveler's collision footprint stays axis-aligned in Z and W,
			# so both axes contribute to contact at an oblique slice angle.
			var margin_size: Vector4 = box.size + Vector4(0, 0, player_radius * 2.0, player_radius * 2.0)
			section = Geometry.slice_box(box.center, margin_size, position4, angle)
			is_fringe = section.visible
		visual.material_override = materials.fringe if is_fringe else materials.get(box.kind, materials.stone)
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if is_fringe else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		visual.visible = section.visible
		if section.visible:
			visual.position = section.center + Vector3(0, 0, visible_player_depth)
			visual.scale = section.size
	for i in range(seed_visuals.size()):
		var pos: Vector4 = _level.seeds[i]
		var hidden := _hidden_distance(pos, position4, angle)
		var visual := seed_visuals[i]
		visual.visible = not collected[i] and absf(hidden) < 0.95
		if visual.visible:
			visual.position = _project(pos, angle) + Vector3(0, sin(clock * 2.1 + float(i)) * 0.11, 0)
			visual.rotation.y = clock * 0.65
			visual.scale = Vector3.ONE * sqrt(maxf(0.0, 1.0 - pow(hidden / 0.95, 2)))
	for deco: Dictionary in decorations:
		var node: Node3D = deco.node
		var hidden := _hidden_distance(deco.position, position4, angle)
		node.visible = absf(hidden) < deco.radius
		if node.visible:
			node.position = _project(deco.position, angle)
			node.scale = Vector3.ONE * clampf(1.0 - pow(absf(hidden) / float(deco.radius), 3), 0.01, 1.0)
	goal_root.visible = absf(_hidden_distance(_level.goal, position4, angle)) < 0.95
	goal_root.position = _project(_level.goal, angle)
	portal_inner.visible = not collected.has(false)
	if portal_inner.visible:
		portal_inner.scale.x = 0.92 + sin(clock * 2.5) * 0.08


func _update_shape_slices(position4: Vector4, angle: float,
		rotating: bool, player_radius: float) -> void:
	var hidden := -position4.z * sin(angle) + position4.w * cos(angle)
	var key := Vector4(hidden, angle, 0.0 if rotating else player_radius, 0.0)
	if _shape_slice_key.is_equal_approx(key):
		return
	_shape_slice_key = key
	for index in range(shape_solids.size()):
		var edges: Array = shape_solids[index].edges
		var mesh := Edges.slice_mesh(edges, position4, angle)
		shape_visuals[index].mesh = mesh
		shape_visuals[index].visible = mesh.get_surface_count() > 0
		shape_fringes[index].visible = false
		if not rotating:
			var fringe := Edges.slice_mesh(edges, position4, angle, player_radius, Edges.BOTH_DEPTH_AXES)
			shape_fringes[index].mesh = fringe
			shape_fringes[index].visible = fringe.get_surface_count() > 0

func update_traveler(delta: float, clock: float, position4: Vector4, angle: float,
		last_motion: Vector2, distance_walked: float, grounded: bool, walking: bool) -> void:
	hero.position = _project(position4, angle)
	hero_body.position.y = absf(sin(distance_walked * 7.0)) * 0.055 if walking and grounded else sin(clock * 2.0) * 0.014
	if walking:
		var facing := atan2(last_motion.x, last_motion.y)
		hero_body.rotation.y = lerp_angle(hero_body.rotation.y, facing, minf(delta * 13.0, 1.0))
	scarf.rotation.x = -0.25 + sin(clock * 5.0) * 0.11 + (0.3 if walking else 0.0)
	var ground_y: float = -100.0
	for box: Dictionary in _level.get("boxes", []):
		var center: Vector4 = box.center
		var half: Vector4 = box.size * 0.5
		if absf(position4.x - center.x) < half.x and absf(position4.z - center.z) < half.z and absf(position4.w - center.w) < half.w:
			var top := center.y + half.y
			if top <= position4.y + 0.05:
				ground_y = maxf(ground_y, top)
	hero_shadow.visible = ground_y > -10.0
	hero_shadow.position = Vector3(hero.position.x, ground_y + 0.012, hero.position.z)
	hero_shadow.scale = Vector3.ONE * clampf(1.0 - (position4.y - ground_y) * 0.16, 0.4, 1.0)

func update_ambience(delta: float, clock: float) -> void:
	for i in range(motes.size()):
		motes[i].position.y = -0.6 + sin(clock * 0.22 + float(i) * 1.7) * 2.4
		motes[i].position.x += sin(clock * 0.12 + float(i)) * delta * 0.06


func _setup_materials() -> void:
	var stone_shader := preload("res://assets/stone.gdshader")
	var palette := {
		"stone": [Color("819579"), Color("3c5650")],
		"wall": [Color("d5b792"), Color("a88769")],
		"bridge": [Color("79b6ad"), Color("386f70")],
		"step": [Color("c7c4a4"), Color("718d7c")]
	}
	for key: String in palette:
		var mat := ShaderMaterial.new()
		mat.shader = stone_shader
		mat.set_shader_parameter("top_color", palette[key][0])
		mat.set_shader_parameter("side_color", palette[key][1])
		mat.set_shader_parameter("tile_scale", 0.9 if key == "wall" else 1.1)
		materials[key] = mat
	materials["ivory"] = _material(Color("f1ead7"))
	materials["dark"] = _material(Color("233f41"))
	materials["scarf"] = _material(Color("d58d55"))
	materials["gold"] = _material(Color("ffdc92"), 1.4)
	materials["gold_dim"] = _material(Color("ceac73"), 0.35)
	materials["leaf"] = _material(Color("67856a"))
	materials["leaf_light"] = _material(Color("a8b784"))
	materials["bark"] = _material(Color("53665a"))
	materials["petal"] = _material(Color("ecc5ad"))
	materials["water"] = _material(Color("1e3a40"))
	materials["water"].shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials["mote"] = _material(Color("8da797"), 0.4)
	var shadow := _material(Color(0.06, 0.11, 0.10, 0.24))
	shadow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials["shadow"] = shadow
	var fringe := _material(Color(0.48, 0.75, 0.70, 0.22))
	fringe.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fringe.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials["fringe"] = fringe
	materials["edge"] = _material(Color("89d0ca"), 0.12)

func _material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.86
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("162c34")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b5cbc2")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("203d43")
	env.fog_light_energy = 0.4
	env.fog_density = 0.006
	var environment := WorldEnvironment.new()
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -34, 0)
	sun.light_color = Color("ffe1b0")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_bias = 0.05
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-28, 135, 0)
	fill.light_color = Color("7badb0")
	fill.light_energy = 0.3
	add_child(fill)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 19.0
	camera.position = Vector3(10, 20, 21)
	add_child(camera)
	camera.look_at(Vector3(0, 0.1, 0))
	camera.current = true
	# An understated circular plinth grounds the floating architecture.
	var plinth := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 11.5
	cylinder.bottom_radius = 11.5
	cylinder.height = 0.12
	cylinder.radial_segments = 96
	plinth.mesh = cylinder
	plinth.material_override = materials.water
	plinth.position.y = -2.1
	add_child(plinth)
	for radius: float in [9.6, 11.0, 13.3, 16.0]:
		var ripple := _ring(radius, 0.012, materials.water)
		ripple.position.y = -2.0
		add_child(ripple)
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	for i in range(38):
		var mote := _mesh_sphere(rng.randf_range(0.015, 0.035), materials.mote, 6, 3)
		mote.position = Vector3(rng.randf_range(-13, 13), rng.randf_range(-1, 4), rng.randf_range(-9, 9))
		add_child(mote)
		motes.append(mote)

func _build_hero() -> void:
	hero = Node3D.new()
	hero.name = "Traveler"
	add_child(hero)
	hero_body = Node3D.new()
	hero.add_child(hero_body)
	var robe := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.19
	cylinder.bottom_radius = 0.29
	cylinder.height = 0.64
	cylinder.radial_segments = 8
	robe.mesh = cylinder
	robe.material_override = materials.ivory
	robe.position.y = 0.5
	hero_body.add_child(robe)
	var head := _mesh_sphere(0.245, materials.ivory, 12, 6)
	head.position.y = 1.02
	hero_body.add_child(head)
	var face := _box(Vector3(0.24, 0.11, 0.065), materials.dark)
	face.position = Vector3(0, 1.03, 0.207)
	hero_body.add_child(face)
	for x: float in [-0.065, 0.065]:
		var eye := _box(Vector3(0.025, 0.04, 0.014), materials.gold)
		eye.position = Vector3(x, 1.035, 0.247)
		hero_body.add_child(eye)
	var collar := _box(Vector3(0.46, 0.12, 0.39), materials.scarf)
	collar.position.y = 0.79
	hero_body.add_child(collar)
	scarf = _box(Vector3(0.13, 0.43, 0.06), materials.scarf)
	scarf.position = Vector3(-0.16, 0.57, -0.24)
	scarf.rotation_degrees.x = -20
	hero_body.add_child(scarf)
	for x: float in [-0.12, 0.12]:
		var foot := _box(Vector3(0.14, 0.16, 0.22), materials.dark)
		foot.position = Vector3(x, 0.1, 0.03)
		hero_body.add_child(foot)
	# A small locator remains visible when a tall wall occludes the traveler.
	var beacon_material := _material(Color(0.98, 0.85, 0.59, 0.85))
	beacon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beacon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_material.no_depth_test = true
	var beacon := _mesh_sphere(0.085, beacon_material, 4, 2)
	beacon.position.y = 1.57
	beacon.scale.y = 1.35
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hero.add_child(beacon)
	hero_shadow = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.36
	disc.bottom_radius = 0.36
	disc.height = 0.006
	disc.radial_segments = 32
	hero_shadow.mesh = disc
	hero_shadow.material_override = materials.shadow
	hero_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hero_shadow)

func _build_goal() -> void:
	goal_root = Node3D.new()
	level_root.add_child(goal_root)
	var base := _box(Vector3(1.5, 0.13, 1.2), materials.dark)
	base.position.y = 0.065
	goal_root.add_child(base)
	for x: float in [-0.59, 0.59]:
		var pillar := _box(Vector3(0.15, 2.1, 0.22), materials.gold_dim)
		pillar.position = Vector3(x, 1.1, 0)
		goal_root.add_child(pillar)
		var inset := _box(Vector3(0.025, 1.8, 0.24), materials.gold)
		inset.position = Vector3(x * 0.82, 1.1, 0)
		goal_root.add_child(inset)
	var lintel := _box(Vector3(1.5, 0.16, 0.33), materials.gold_dim)
	lintel.position.y = 2.2
	goal_root.add_child(lintel)
	var crown := _mesh_sphere(0.13, materials.gold, 4, 2)
	crown.position.y = 2.53
	goal_root.add_child(crown)
	portal_inner = _box(Vector3(0.97, 1.87, 0.025), materials.gold_dim)
	var portal_mat := _material(Color(1.0, 0.79, 0.40, 0.12), 0.6)
	portal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	portal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	portal_inner.material_override = portal_mat
	portal_inner.position.y = 1.13
	goal_root.add_child(portal_inner)

func _build_decorations(decoration_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 131 + decoration_seed * 37
	for box: Dictionary in _level.boxes:
		if box.kind != "stone":
			continue
		var center: Vector4 = box.center
		var size: Vector4 = box.size
		var surface: float = center.y + size.y * 0.5
		for i in range(int(size.x * 1.6)):
			var x := center.x + rng.randf_range(-size.x * 0.43, size.x * 0.43)
			var z := center.z + size.z * (0.42 if i % 2 == 0 else -0.42)
			var pos := Vector4(x, surface, z, center.w)
			var plant := Node3D.new()
			level_root.add_child(plant)
			for j in range(3):
				var grass := _box(Vector3(0.035, rng.randf_range(0.15, 0.35), 0.045), materials.leaf_light)
				grass.position = Vector3(float(j - 1) * 0.085, 0.1, 0)
				grass.rotation_degrees.z = float(j - 1) * -23
				plant.add_child(grass)
			decorations.append({"node": plant, "position": pos, "radius": 0.48})
		# A small sculpted tree at the far outer corner of each island.
		var tree_pos := Vector4(center.x - size.x * 0.32, surface, center.z - size.z * 0.37, center.w)
		var tree := Node3D.new()
		level_root.add_child(tree)
		var trunk := _box(Vector3(0.12, 1.35, 0.12), materials.bark)
		trunk.position.y = 0.68
		trunk.rotation_degrees.z = -8
		tree.add_child(trunk)
		for i in range(4):
			var leaf := _mesh_sphere(0.52 - float(i) * 0.045, materials.leaf if i % 2 == 0 else materials.leaf_light, 7, 4)
			leaf.position = Vector3(sin(float(i) * 2.8) * 0.33, 1.2 + float(i) * 0.22, cos(float(i) * 2.8) * 0.25)
			leaf.scale.y = 0.58
			tree.add_child(leaf)
		decorations.append({"node": tree, "position": tree_pos, "radius": 0.8})

func _project(pos: Vector4, angle: float) -> Vector3:
	return Vector3(pos.x, pos.y, pos.z * cos(angle) + pos.w * sin(angle))

func _hidden_distance(pos: Vector4, position4: Vector4, angle: float) -> float:
	return -(pos.z - position4.z) * sin(angle) + (pos.w - position4.w) * cos(angle)

func _box(size: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	return node

func _mesh_sphere(radius: float, material: Material, segments: int = 12, rings: int = 6) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = rings
	node.mesh = mesh
	node.material_override = material
	return node

func _ring(radius: float, width: float, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - width
	mesh.outer_radius = radius + width
	mesh.rings = 64
	mesh.ring_segments = 6
	node.mesh = mesh
	node.material_override = material
	return node

