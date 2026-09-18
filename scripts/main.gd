extends Node3D
## FOLD: a 3D cross-section through four-dimensional boxes, beams, and polytopes.
## Owns session state and four-dimensional simulation.
## Child scenes provide rendering, interface, and audio through explicit APIs.

const Geometry = preload("res://scripts/slice_geometry.gd")
const Edges = preload("res://scripts/edge_geometry.gd")
const Solids = preload("res://scripts/solid_geometry.gd")
const Levels = preload("res://scripts/level_data.gd")
const SPEED: float = 4.2
const ROTATION_SPEED: float = PI / 2.0
const GRAVITY: float = 18.0
const JUMP_SPEED: float = 7.2
const RADIUS: float = 0.27
const HEIGHT: float = 1.25

## Drag a FoldLevel resource here to run it instead of the built-in campaign.
@export var level_override: FoldLevel

@onready var world: FoldWorld = $World
@onready var hud: GameHUD = $HUD
@onready var sound: Soundscape = $Sound

var levels: Array[Dictionary] = []
var level_index: int = 0
var level: Dictionary = {}
var shape_solids: Array[Dictionary] = []
var filled_solids: Array[Dictionary] = []
var position4: Vector4 = Vector4.ZERO
var respawn_position: Vector4 = Vector4.ZERO
var vertical_speed: float = 0.0
var grounded: bool = false
var coyote: float = 0.0
var jump_buffer: float = 0.0
var active_axis: int = 0
var angle: float = 0.0
var rotating: bool = false
var started: bool = false
var paused: bool = false
var completed: bool = false
var collected: Array[bool] = []
var hint_index: int = 0
var clock: float = 0.0
var distance_walked: float = 0.0
var last_motion: Vector2 = Vector2.ZERO
var capture_mode: bool = false
var muted: bool = false

func _ready() -> void:
	get_window().focus_exited.connect(_on_focus_exited)
	hud.start_requested.connect(_start)
	hud.restart_requested.connect(_restart)
	hud.next_requested.connect(_next_level)
	hud.level_requested.connect(_select_level)
	hud.hint_requested.connect(_hint)
	hud.pause_requested.connect(_toggle_pause)
	levels = Levels.all_levels()
	hud.set_custom_level(false)
	_load_level(0)
	hud.show_title()
	_sync_mouse_mode()

	var args := OS.get_cmdline_user_args()
	capture_mode = "--capture" in args or "--capture-title" in args
	var custom_level := level_override
	for argument in args:
		if argument.begins_with("--level="):
			var path := argument.trim_prefix("--level=")
			custom_level = FoldLevel.load_level(path)
			if custom_level == null:
				push_warning("Could not load a FoldLevel resource from: %s" % path)
				hud.show_toast("Could not open the selected level.")
	if custom_level != null:
		load_custom_level(custom_level)
	if capture_mode:
		if "--capture-title" not in args:
			_start()
		if "--level2" in args:
			_select_level(1)
		if "--level3" in args:
			_select_level(2)
		if "--level4" in args:
			_select_level(3)
		if "--level5" in args:
			_select_level(4)
		if "--folded" in args:
			active_axis = 1
			angle = PI / 2.0
		if "--bridge" in args:
			position4.w = 2.65
		_capture.call_deferred()


## Validate before replacing the current session so invalid authoring data is harmless.
func load_custom_level(resource: FoldLevel) -> bool:
	if resource == null:
		return false
	var errors := resource.validation_errors()
	if not errors.is_empty():
		push_warning("Cannot play this level:\n%s" % "\n".join(errors))
		hud.show_toast("This level has errors. Check it in the level editor.")
		return false
	levels.clear()
	levels.append(resource.to_dictionary())
	hud.set_custom_level(true)
	_load_level(0)
	_start()
	return true


func _input(event: InputEvent) -> void:
	if not started or paused or completed or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		world.orbit_camera(event.screen_relative)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		# The hidden cursor must not activate HUD buttons during mouse look.
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
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
	if event.is_action_pressed("jump"):
		jump_buffer = 0.15

func _physics_process(delta: float) -> void:
	if not started or paused or completed:
		return
	# Folding steers the depth direction while movement and gravity keep running.
	rotate_slice(Input.get_axis("fold_negative", "fold_positive"), delta)
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	simulate_motion(_camera_relative_motion(input), delta)


func _camera_relative_motion(input: Vector2) -> Vector2:
	# Read the current view every tick, including while movement keys stay held.
	# Flatten pitch so looking up/down never changes walking speed or height.
	var right := Vector2(world.camera.global_basis.x.x, world.camera.global_basis.x.z).normalized()
	var back := Vector2(world.camera.global_basis.z.x, world.camera.global_basis.z.z).normalized()
	return right * input.x + back * input.y

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
	# View depth follows the current Z-W direction, including oblique/reversed slices.
	_move_depth(motion.y * SPEED * delta)
	vertical_speed -= GRAVITY * delta
	grounded = false
	_move_axis(1, vertical_speed * delta)
	distance_walked += Vector3(position4.x - before.x, position4.z - before.z, position4.w - before.w).length()
	if position4.y < -7.0:
		_respawn()
	_check_objectives()

## Sweep along the view's depth as one vector so a wall cannot push movement
## into the hidden dimension. X and vertical movement still slide independently.
func _move_depth(amount: float) -> void:
	if is_zero_approx(amount):
		return
	var direction := Vector4(0.0, 0.0, cos(angle), sin(angle))
	var travel := amount
	for box: Dictionary in level.get("boxes", []):
		travel = _clip_depth_motion(travel, _box_depth_interval(box, direction))
	for shape: Dictionary in shape_solids:
		if not Edges.bounds_overlap(shape, position4, RADIUS, HEIGHT, absf(travel)):
			continue
		for edge: Dictionary in shape.edges:
			if Edges.bounds_overlap(edge, position4, RADIUS, HEIGHT, absf(travel)):
				travel = _clip_depth_motion(travel, Edges.depth_movement_interval(edge, position4, angle, RADIUS, HEIGHT))
	for shape: Dictionary in filled_solids:
		if Edges.bounds_overlap(shape, position4, RADIUS, HEIGHT, absf(travel)):
			travel = _clip_depth_motion(travel, Solids.depth_movement_interval(shape, position4, angle, RADIUS, HEIGHT))
	position4 += direction * travel

func _box_depth_interval(box: Dictionary, direction: Vector4) -> Vector2:
	var center: Vector4 = box.center
	var half: Vector4 = box.size * 0.5
	if absf(position4.x - center.x) >= half.x + RADIUS - Geometry.EPSILON or position4.y >= center.y + half.y - Geometry.EPSILON or position4.y + HEIGHT <= center.y - half.y + Geometry.EPSILON:
		return Vector2(INF, -INF)
	var interval := Vector2(-INF, INF)
	for axis in [2, 3]:
		var low := center[axis] - half[axis] - RADIUS
		var high := center[axis] + half[axis] + RADIUS
		if absf(direction[axis]) < Geometry.EPSILON:
			if position4[axis] <= low + Geometry.EPSILON or position4[axis] >= high - Geometry.EPSILON:
				return Vector2(INF, -INF)
		else:
			var first := (low - position4[axis]) / direction[axis]
			var last := (high - position4[axis]) / direction[axis]
			interval.x = maxf(interval.x, minf(first, last))
			interval.y = minf(interval.y, maxf(first, last))
	return interval

func _clip_depth_motion(amount: float, interval: Vector2) -> float:
	if interval.y - interval.x <= Geometry.EPSILON:
		return amount
	if amount > 0.0 and interval.y > Geometry.EPSILON:
		return minf(amount, maxf(0.0, interval.x))
	if amount < 0.0 and interval.x < -Geometry.EPSILON:
		return maxf(amount, minf(0.0, interval.y))
	return amount

func _move_axis(axis: int, amount: float) -> void:
	# Small swept increments prevent tunneling through thin 4D obstacles.
	var count := maxi(1, ceili(absf(amount) / 0.08))
	var step := amount / float(count)
	for unused in range(count):
		var previous := position4[axis]
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
		for shape: Dictionary in shape_solids:
			if not Edges.bounds_overlap(shape, position4, RADIUS, HEIGHT, absf(step)):
				continue
			for edge: Dictionary in shape.edges:
				if not Edges.bounds_overlap(edge, position4, RADIUS, HEIGHT, absf(step)):
					continue
				var interval := Edges.movement_interval(edge, position4, axis, RADIUS, HEIGHT)
				var hit := false
				if step > 0.0 and previous <= interval.x + Edges.EPS and position4[axis] > interval.x:
					position4[axis] = interval.x
					hit = true
				elif step < 0.0 and previous >= interval.y - Edges.EPS and position4[axis] < interval.y:
					position4[axis] = interval.y
					hit = true
				if hit and axis == 1:
					grounded = step < 0.0
					vertical_speed = 0.0
		for shape: Dictionary in filled_solids:
			if not Edges.bounds_overlap(shape, position4, RADIUS, HEIGHT, absf(step)):
				continue
			var interval := Solids.movement_interval(shape, position4, axis, RADIUS, HEIGHT)
			var hit := false
			if step > 0.0 and previous <= interval.x + Solids.EPS and position4[axis] > interval.x:
				position4[axis] = interval.x
				hit = true
			elif step < 0.0 and previous >= interval.y - Solids.EPS and position4[axis] < interval.y:
				position4[axis] = interval.y
				hit = true
			if hit and axis == 1:
				grounded = step < 0.0
				vertical_speed = 0.0

## Holding Q/E changes the angle on the ground or in the air; release keeps it.
func rotate_slice(direction: float, delta: float) -> bool:
	if is_zero_approx(direction) or delta <= 0.0 or paused or completed or not started:
		rotating = false
		return false
	if not rotating:
		sound.play_fold()
	rotating = true
	angle = wrapf(angle + clampf(direction, -1.0, 1.0) * ROTATION_SPEED * delta, -PI, PI)
	active_axis = 1 if absf(sin(angle)) > absf(cos(angle)) else 0
	return true

func _check_objectives() -> void:
	var body_center := position4 + Vector4(0.0, 0.65, 0.0, 0.0)
	for i in range(collected.size()):
		if not collected[i] and body_center.distance_to(level.seeds[i]) < 0.88:
			collected[i] = true
			sound.play_seed(_collected_count() - 1)
			var checkpoints: Array = level.get("echo_checkpoints", [])
			if i < checkpoints.size():
				respawn_position = checkpoints[i]
			var names: Array = level.get("echo_names", [])
			if i < names.size():
				# A later echo can be found first; keep the earliest missing guidance.
				hint_index = _first_uncollected_echo()
				var message := "%s found · %d/%d echoes." % [names[i], _collected_count(), collected.size()]
				if i < checkpoints.size():
					message += " Checkpoint saved."
				if not collected.has(false):
					message += " The amber gate is open."
				hud.show_toast(message)
			else:
				hud.show_toast("All echoes found. Return to the amber gate." if _collected_count() == collected.size() else "An echo found in the quiet dimension.")
	if _collected_count() == collected.size() and position4.distance_to(level.goal) < 0.95:
		completed = true
		rotating = false
		_sync_mouse_mode()
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
	_refresh_view(delta)
	hud.update_state(_collected_count(), collected.size(), angle, position4, rotating)


func _refresh_view(delta: float = 0.0) -> void:
	world.update_slice(position4, angle, active_axis, rotating, collected, clock, RADIUS)
	var walking := last_motion.length() > 0.05 and started and not completed
	world.update_traveler(delta, clock, position4, angle, last_motion, distance_walked, grounded, walking)
	world.update_camera(delta)
	world.update_ambience(delta, clock)


func _start() -> void:
	started = true
	paused = false
	_sync_mouse_mode()
	hud.hide_title()
	hud.show_toast("Find the echoes. Reach the amber gate. Hold Q / E to turn your slice.")

func _restart() -> void:
	_load_level(level_index)
	started = true
	_sync_mouse_mode()
	hud.hide_title()
	sound.play_reset()

func _respawn() -> void:
	position4 = respawn_position
	vertical_speed = 0.0
	grounded = true
	active_axis = 0
	angle = 0.0
	rotating = false
	jump_buffer = 0.0
	last_motion = Vector2.ZERO
	_reset_camera()
	hud.show_toast("Back at your checkpoint. Your echoes are safe." if respawn_position != level.start else "Back on solid ground. Your echoes are safe.")
	sound.play_reset()

func _next_level() -> void:
	_select_level((level_index + 1) % levels.size())

func _select_level(index: int) -> void:
	_load_level(clampi(index, 0, levels.size() - 1))
	started = true
	_sync_mouse_mode()
	hud.hide_title()

func _toggle_pause() -> void:
	if not started or completed:
		return
	paused = not paused
	_sync_mouse_mode()
	hud.show_pause(paused)


func _sync_mouse_mode() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if started and not paused and not completed and not capture_mode else Input.MOUSE_MODE_VISIBLE


func _on_focus_exited() -> void:
	if started and not paused and not completed and not capture_mode:
		_toggle_pause()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _hint() -> void:
	var hints: Array = level.get("hints", [])
	if not level.get("echo_names", []).is_empty():
		if not collected.has(false):
			hud.show_hint(level.goal_hint)
		elif hint_index >= hints.size():
			hud.show_hint(level.goal_hint)
			hint_index = _first_uncollected_echo()
		else:
			hud.show_hint(hints[hint_index])
			hint_index += 1
		return
	if hints.is_empty():
		return
	hud.show_hint(hints[mini(hint_index, hints.size() - 1)])
	hint_index += 1


func _first_uncollected_echo() -> int:
	for index in range(collected.size()):
		if not collected[index]:
			return index
	return collected.size()

func _load_level(index: int) -> void:
	level_index = index
	level = levels[index]
	shape_solids = Edges.compile_shapes(level.get("shapes", []))
	filled_solids = Solids.compile_shapes(level.get("shapes", []))
	collected.clear()
	for seed: Vector4 in level.seeds:
		collected.append(false)
	world.load_level(level, index)
	position4 = level.start
	respawn_position = level.start
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
	last_motion = Vector2.ZERO
	distance_walked = 0.0
	hud.setup_level(index, levels.size(), level.title, level.subtitle, level.lesson, collected.size())
	_refresh_view()
	_reset_camera()


func _reset_camera() -> void:
	world.update_slice(position4, angle, active_axis, rotating, collected, clock, RADIUS)
	var toward_goal: Vector4 = level.goal - position4
	var facing := Vector2(toward_goal.x, toward_goal.z * cos(angle) + toward_goal.w * sin(angle))
	if facing.is_zero_approx():
		# A gate directly above or outside this slice gives no useful heading.
		# At an authored waypoint, face the next visible leg of its route.
		var route: Array = level.get("solution", [])
		var found_position := false
		for waypoint: Vector4 in route:
			if not found_position:
				found_position = waypoint.is_equal_approx(position4)
				continue
			var toward_waypoint := waypoint - position4
			facing = Vector2(toward_waypoint.x, toward_waypoint.z * cos(angle) + toward_waypoint.w * sin(angle))
			if not facing.is_zero_approx():
				break
	world.reset_camera(position4, angle, facing)


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
