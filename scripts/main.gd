extends Node3D
## FOLD: a 3D cross-section through an axis-aligned four-dimensional world.
## Simulation stays in Vector4. Rendering alone maps the active slice to Vector3.

const Geometry = preload("res://scripts/slice_geometry.gd")
const Levels = preload("res://scripts/level_data.gd")
const HUD = preload("res://scripts/game_hud.gd")
const Sound = preload("res://scripts/soundscape.gd")
const SPEED: float = 4.2
const GRAVITY: float = 18.0
const JUMP_SPEED: float = 7.2
const RADIUS: float = 0.27
const HEIGHT: float = 1.25

var levels: Array[Dictionary] = []
var level_index: int = 0
var level: Dictionary = {}
var position4: Vector4 = Vector4.ZERO
var vertical_speed: float = 0.0
var grounded: bool = false
var coyote: float = 0.0
var jump_buffer: float = 0.0
var active_axis: int = 0
var angle: float = 0.0
var rotating: bool = false
var rotation_elapsed: float = 0.0
var rotation_from: float = 0.0
var rotation_to: float = 0.0
var started: bool = false
var paused: bool = false
var completed: bool = false
var collected: Array[bool] = []
var hint_index: int = 0
var clock: float = 0.0
var distance_walked: float = 0.0
var last_motion: Vector2 = Vector2.ZERO
var world_root: Node3D
var box_visuals: Array[MeshInstance3D] = []
var seed_visuals: Array[Node3D] = []
var decorations: Array[Dictionary] = []
var materials: Dictionary = {}
var hero: Node3D
var hero_body: Node3D
var scarf: MeshInstance3D
var hero_shadow: MeshInstance3D
var goal_root: Node3D
var portal_inner: MeshInstance3D
var camera: Camera3D
var hud: CanvasLayer
var sound: Node
var motes: Array[MeshInstance3D] = []
var capture_mode: bool = false
var muted: bool = false

func _ready() -> void:
	_setup_input()
	_setup_materials()
	_setup_environment()
	_build_hero()
	hud = HUD.new()
	add_child(hud)
	hud.start_requested.connect(_start)
	hud.restart_requested.connect(_restart)
	hud.next_requested.connect(_next_level)
	hud.level_requested.connect(_select_level)
	hud.hint_requested.connect(_hint)
	hud.pause_requested.connect(_toggle_pause)
	sound = Sound.new()
	add_child(sound)
	levels = Levels.all_levels()
	_load_level(0)
	hud.show_title()
	var args := OS.get_cmdline_user_args()
	if "--capture" in args or "--capture-title" in args:
		capture_mode = true
		if "--capture-title" not in args:
			_start()
		if "--level2" in args:
			_select_level(1)
		if "--level3" in args:
			_select_level(2)
		if "--folded" in args:
			active_axis = 1
			angle = PI / 2.0
		if "--bridge" in args:
			position4.w = 2.65
		_capture.call_deferred()

func _setup_input() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"jump": [KEY_SPACE], "fold": [KEY_Q, KEY_E], "restart": [KEY_R],
		"hint": [KEY_H], "pause_game": [KEY_ESCAPE], "mute": [KEY_M]
	}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mute"):
		muted = not muted
		sound.set_muted(muted)
		hud.show_toast("Sound off" if muted else "Sound on")
	if not started:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
			_start()
		return
	if event.is_action_pressed("pause_game"):
		_toggle_pause()
	if paused:
		return
	if event.is_action_pressed("restart"):
		_restart()
	if event.is_action_pressed("hint"):
		_hint()
	if completed:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
			_next_level()
		return
	if event.is_action_pressed("fold"):
		request_fold()
	if event.is_action_pressed("jump"):
		jump_buffer = 0.15

func _physics_process(delta: float) -> void:
	if not started or paused or completed:
		return
	if rotating:
		rotation_elapsed += delta
		var t := clampf(rotation_elapsed / 0.7, 0.0, 1.0)
		var ease_t := t * t * (3.0 - 2.0 * t)
		angle = lerpf(rotation_from, rotation_to, ease_t)
		if t >= 1.0:
			rotating = false
			angle = rotation_to
			active_axis = 1 if angle > 0.5 else 0
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Match the orthographic camera: W goes up-screen, D goes right-screen.
	var right := Vector2(camera.global_basis.x.x, camera.global_basis.x.z).normalized()
	var back := Vector2(camera.global_basis.z.x, camera.global_basis.z.z).normalized()
	var motion := right * input.x + back * input.y
	simulate_motion(motion, delta)

## Shared by real input and deterministic playthrough tests.
func simulate_motion(motion: Vector2, delta: float, jump: bool = false) -> void:
	if jump:
		jump_buffer = 0.15
	jump_buffer = maxf(0.0, jump_buffer - delta)
	coyote = 0.12 if grounded else maxf(0.0, coyote - delta)
	if jump_buffer > 0.0 and coyote > 0.0:
		vertical_speed = JUMP_SPEED
		grounded = false
		coyote = 0.0
		jump_buffer = 0.0
		if is_instance_valid(sound):
			sound.play_jump()
	last_motion = motion
	if motion.length() > 1.0:
		motion = motion.normalized()
	var before := position4
	_move_axis(0, motion.x * SPEED * delta)
	_move_axis(2 if active_axis == 0 else 3, motion.y * SPEED * delta)
	vertical_speed -= GRAVITY * delta
	grounded = false
	_move_axis(1, vertical_speed * delta)
	distance_walked += Vector2(position4.x - before.x, (position4.z - before.z) + (position4.w - before.w)).length()
	if position4.y < -7.0:
		_respawn()
	_check_objectives()

func _move_axis(axis: int, amount: float) -> void:
	# Small swept increments prevent tunneling through thin 4D obstacles.
	var count := maxi(1, ceili(absf(amount) / 0.08))
	var step := amount / float(count)
	for unused in range(count):
		position4[axis] += step
		for box: Dictionary in level.get("boxes", []):
			var center: Vector4 = box.center
			var size: Vector4 = box.size
			if not Geometry.intersects_player(position4, center, size, RADIUS, HEIGHT):
				continue
			var lo: float = center[axis] - size[axis] * 0.5
			var hi: float = center[axis] + size[axis] * 0.5
			if axis == 1:
				if step < 0.0:
					position4.y = hi
					grounded = true
				else:
					position4.y = lo - HEIGHT
				vertical_speed = 0.0
			else:
				position4[axis] = lo - RADIUS if step > 0.0 else hi + RADIUS

func request_fold() -> bool:
	if rotating or paused or completed or not started:
		return false
	if not grounded:
		hud.show_toast("Touch down before folding.")
		return false
	rotating = true
	rotation_elapsed = 0.0
	rotation_from = angle
	rotation_to = PI / 2.0 if active_axis == 0 else 0.0
	sound.play_fold()
	return true

func _check_objectives() -> void:
	var body_center := position4 + Vector4(0.0, 0.65, 0.0, 0.0)
	for i in range(collected.size()):
		if not collected[i] and body_center.distance_to(level.seeds[i]) < 0.88:
			collected[i] = true
			sound.play_seed(_collected_count() - 1)
			hud.show_toast("All echoes found. Return to the amber gate." if _collected_count() == collected.size() else "An echo found in the quiet dimension.")
	if _collected_count() == collected.size() and position4.distance_to(level.goal) < 0.95:
		completed = true
		hud.show_completion(level_index == levels.size() - 1)
		sound.play_complete()

func _collected_count() -> int:
	var count: int = 0
	for value: bool in collected:
		if value:
			count += 1
	return count

func _process(delta: float) -> void:
	if paused:
		return
	clock += delta
	_update_world_visuals()
	_update_hero(delta)
	if is_instance_valid(hud):
		hud.update_state(_collected_count(), collected.size(), angle, position4, rotating)
	for i in range(motes.size()):
		motes[i].position.y = -0.6 + sin(clock * 0.22 + float(i) * 1.7) * 2.4
		motes[i].position.x += sin(clock * 0.12 + float(i)) * delta * 0.06

func _start() -> void:
	started = true
	paused = false
	hud.hide_title()
	hud.show_toast("Find the echoes. Reach the amber gate. Q / E folds the world.")

func _restart() -> void:
	_load_level(level_index)
	started = true
	hud.hide_title()
	sound.play_reset()

func _respawn() -> void:
	position4 = level.start
	vertical_speed = 0.0
	grounded = true
	active_axis = 0
	angle = 0.0
	rotating = false
	jump_buffer = 0.0
	hud.show_toast("Back on solid ground. Your echoes are safe.")
	sound.play_reset()

func _next_level() -> void:
	_select_level((level_index + 1) % levels.size())

func _select_level(index: int) -> void:
	_load_level(clampi(index, 0, levels.size() - 1))
	started = true
	hud.hide_title()

func _toggle_pause() -> void:
	if not started or completed:
		return
	paused = not paused
	hud.show_pause(paused)

func _hint() -> void:
	var hints: Array = level.get("hints", [])
	if hints.is_empty():
		return
	hud.show_hint(hints[mini(hint_index, hints.size() - 1)])
	hint_index += 1

func _load_level(index: int) -> void:
	level_index = index
	level = levels[index]
	if is_instance_valid(world_root):
		remove_child(world_root)
		world_root.queue_free()
	world_root = Node3D.new()
	world_root.name = "FourDimensionalGarden"
	add_child(world_root)
	box_visuals.clear()
	seed_visuals.clear()
	decorations.clear()
	collected.clear()
	for box: Dictionary in level.boxes:
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		mesh.material_override = materials.get(box.kind, materials.stone)
		world_root.add_child(mesh)
		box_visuals.append(mesh)
	for seed: Vector4 in level.seeds:
		collected.append(false)
		var root := Node3D.new()
		world_root.add_child(root)
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
	_build_decorations()
	position4 = level.start
	vertical_speed = 0.0
	grounded = true
	active_axis = 0
	angle = 0.0
	rotating = false
	completed = false
	paused = false
	coyote = 0.0
	jump_buffer = 0.0
	hint_index = 0
	hud.setup_level(index, levels.size(), level.title, level.subtitle, level.lesson, collected.size())
	_update_world_visuals()

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
	world_root.add_child(goal_root)
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

func _build_decorations() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 131 + level_index * 37
	for box: Dictionary in level.boxes:
		if box.kind != "stone":
			continue
		var center: Vector4 = box.center
		var size: Vector4 = box.size
		var surface: float = center.y + size.y * 0.5
		for i in range(int(size.x * 1.6)):
			var x := center.x + rng.randf_range(-size.x * 0.43, size.x * 0.43)
			var z := center.z + size.z * (0.42 if i % 2 == 0 else -0.42)
			var pos := Vector4(x, surface, z, 0)
			var plant := Node3D.new()
			world_root.add_child(plant)
			for j in range(3):
				var grass := _box(Vector3(0.035, rng.randf_range(0.15, 0.35), 0.045), materials.leaf_light)
				grass.position = Vector3(float(j - 1) * 0.085, 0.1, 0)
				grass.rotation_degrees.z = float(j - 1) * -23
				plant.add_child(grass)
			decorations.append({"node": plant, "position": pos, "radius": 0.48})
		# A small sculpted tree at the far outer corner of each island.
		var tree_pos := Vector4(center.x - size.x * 0.32, surface, center.z - size.z * 0.37, 0)
		var tree := Node3D.new()
		world_root.add_child(tree)
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

func _update_world_visuals() -> void:
	if level.is_empty():
		return
	var visible_player_depth := position4.z * cos(angle) + position4.w * sin(angle)
	for i in range(box_visuals.size()):
		var box: Dictionary = level.boxes[i]
		var section: Dictionary = Geometry.slice_box(box.center, box.size, position4, angle)
		var visual := box_visuals[i]
		var is_fringe := false
		# A finite traveler can touch a solid just outside the mathematical plane.
		# Show those contact margins as translucent silhouettes rather than letting
		# them become invisible walls or invisible support at a slice boundary.
		if not section.visible and not rotating:
			var margin_size: Vector4 = box.size
			margin_size[3 if active_axis == 0 else 2] += RADIUS * 2.0
			section = Geometry.slice_box(box.center, margin_size, position4, angle)
			is_fringe = section.visible
		visual.material_override = materials.fringe if is_fringe else materials.get(box.kind, materials.stone)
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if is_fringe else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		visual.visible = section.visible
		if section.visible:
			visual.position = section.center + Vector3(0, 0, visible_player_depth)
			visual.scale = section.size
	for i in range(seed_visuals.size()):
		var pos: Vector4 = level.seeds[i]
		var hidden := _hidden_distance(pos)
		var visual := seed_visuals[i]
		visual.visible = not collected[i] and absf(hidden) < 0.95
		if visual.visible:
			visual.position = _project(pos) + Vector3(0, sin(clock * 2.1 + float(i)) * 0.11, 0)
			visual.rotation.y = clock * 0.65
			visual.scale = Vector3.ONE * sqrt(maxf(0.0, 1.0 - pow(hidden / 0.95, 2)))
	for deco: Dictionary in decorations:
		var node: Node3D = deco.node
		var hidden := _hidden_distance(deco.position)
		node.visible = absf(hidden) < deco.radius
		if node.visible:
			node.position = _project(deco.position)
			node.scale = Vector3.ONE * clampf(1.0 - pow(absf(hidden) / float(deco.radius), 3), 0.01, 1.0)
	goal_root.visible = absf(_hidden_distance(level.goal)) < 0.95
	goal_root.position = _project(level.goal)
	portal_inner.visible = _collected_count() == collected.size()
	if portal_inner.visible:
		portal_inner.scale.x = 0.92 + sin(clock * 2.5) * 0.08

func _project(pos: Vector4) -> Vector3:
	return Vector3(pos.x, pos.y, pos.z * cos(angle) + pos.w * sin(angle))

func _hidden_distance(pos: Vector4) -> float:
	return -(pos.z - position4.z) * sin(angle) + (pos.w - position4.w) * cos(angle)

func _update_hero(delta: float) -> void:
	hero.position = _project(position4)
	var walking := last_motion.length() > 0.05 and started and not completed and not rotating
	hero_body.position.y = absf(sin(distance_walked * 7.0)) * 0.055 if walking and grounded else sin(clock * 2.0) * 0.014
	if walking:
		var facing := atan2(last_motion.x, last_motion.y)
		hero_body.rotation.y = lerp_angle(hero_body.rotation.y, facing, minf(delta * 13.0, 1.0))
	scarf.rotation.x = -0.25 + sin(clock * 5.0) * 0.11 + (0.3 if walking else 0.0)
	var ground_y: float = -100.0
	for box: Dictionary in level.get("boxes", []):
		var center: Vector4 = box.center
		var half: Vector4 = box.size * 0.5
		if absf(position4.x - center.x) < half.x and absf(position4.z - center.z) < half.z and absf(position4.w - center.w) < half.w:
			var top := center.y + half.y
			if top <= position4.y + 0.05:
				ground_y = maxf(ground_y, top)
	hero_shadow.visible = ground_y > -10.0
	hero_shadow.position = Vector3(hero.position.x, ground_y + 0.012, hero.position.z)
	hero_shadow.scale = Vector3.ONE * clampf(1.0 - (position4.y - ground_y) * 0.16, 0.4, 1.0)

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

func _capture() -> void:
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://test-output")
	var suffix := "title" if not started else "level%d" % (level_index + 1)
	if "--folded" in OS.get_cmdline_user_args():
		suffix += "-folded"
	if "--bridge" in OS.get_cmdline_user_args():
		suffix += "-bridge"
	get_viewport().get_texture().get_image().save_png("res://test-output/%s.png" % suffix)
	print("Captured ", suffix)
	get_tree().quit()
