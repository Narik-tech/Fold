extends Node3D
## FOLD: a 3D cross-section through a world of four-dimensional boxes and beams.
## Owns session state and four-dimensional simulation.
## Child scenes provide rendering, interface, and audio through explicit APIs.

const Geometry = preload("res://scripts/slice_geometry.gd")
const Edges = preload("res://scripts/edge_geometry.gd")
const Levels = preload("res://scripts/level_data.gd")
const SPEED: float = 4.2
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
var capture_mode: bool = false
var muted: bool = false

func _ready() -> void:
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

	var args := OS.get_cmdline_user_args()
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
	var right := Vector2(world.camera.global_basis.x.x, world.camera.global_basis.x.z).normalized()
	var back := Vector2(world.camera.global_basis.z.x, world.camera.global_basis.z.z).normalized()
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
	_refresh_view(delta)
	hud.update_state(_collected_count(), collected.size(), angle, position4, rotating)


func _refresh_view(delta: float = 0.0) -> void:
	world.update_slice(position4, angle, active_axis, rotating, collected, clock, RADIUS)
	var walking := last_motion.length() > 0.05 and started and not completed and not rotating
	world.update_traveler(delta, clock, position4, angle, last_motion, distance_walked, grounded, walking)
	world.update_ambience(delta, clock)


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
	shape_solids = Edges.compile_shapes(level.get("shapes", []))
	collected.clear()
	for seed: Vector4 in level.seeds:
		collected.append(false)
	world.load_level(level, index)
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
	last_motion = Vector2.ZERO
	distance_walked = 0.0
	hud.setup_level(index, levels.size(), level.title, level.subtitle, level.lesson, collected.size())
	_refresh_view()


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
