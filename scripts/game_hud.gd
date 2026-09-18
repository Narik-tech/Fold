class_name GameHUD
extends CanvasLayer

signal start_requested
signal restart_requested
signal next_requested
signal level_requested(index: int)
signal hint_requested
signal pause_requested
signal quit_requested

const INK := Color("e8e8d8")
const MUTED := Color("a8bcb5")
const TEAL := Color("80c4af")
const GOLD := Color("edc482")
const PANEL := Color(0.055, 0.13, 0.13, 0.93)

class OrientationView extends Control:
	var angle: float = 0.0
	var hidden_coordinate: float = 0.0
	var is_rotating: bool = false

	func _draw() -> void:
		var center := Vector2(65, 65)
		var radius: float = 41.0
		draw_arc(center, radius, 0.0, TAU, 72, Color(0.45, 0.67, 0.61, 0.3), 1.0, true)
		draw_line(center + Vector2(-51, 0), center + Vector2(51, 0), Color(0.45, 0.67, 0.61, 0.2), 1.0, true)
		draw_line(center + Vector2(0, -51), center + Vector2(0, 51), Color(0.45, 0.67, 0.61, 0.2), 1.0, true)
		var axis := Vector2(cos(angle), -sin(angle)) * radius
		var other := Vector2(sin(angle), cos(angle)) * radius
		draw_line(center - axis, center + axis, Color("83c9b1"), 2.0, true)
		draw_line(center - other * 0.72, center + other * 0.72, Color(0.93, 0.76, 0.48, 0.55), 1.0, true)
		draw_circle(center + axis, 4.0, Color("edc482"))
		draw_circle(center, 3.0, Color("e8e8d8"))
		var font: Font = ThemeDB.fallback_font
		draw_string(font, Vector2(118, 70), "Z", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("a8bcb5"))
		draw_string(font, Vector2(61, 12), "W", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("a8bcb5"))
		if is_rotating:
			draw_arc(center, radius + 5.0, -angle - 0.28, -angle + 0.28, 18, Color("edc482"), 2.0, true)

var _root: Control
var _game_ui: Control
var _chapter_label: Label
var _title_label: Label
var _subtitle_label: Label
var _seed_label: Label
var _seed_dots: Label
var _lesson_heading: Label
var _lesson_label: Label
var _slice_label: Label
var _coordinate_label: Label
var _orientation: OrientationView
var _title_overlay: Control
var _campaign_label: Label
var _labyrinth_button: Button
var _ascent_button: Button
var _pause_overlay: Control
var _completion_overlay: Control
var _completion_title: Label
var _completion_copy: Label
var _next_button: Button
var _toast_panel: PanelContainer
var _toast_label: Label
var _level_buttons: Array[Button] = []
var _level_nav: HBoxContainer
var _pause_level_buttons: Array[Button] = []
var _pause_chapters: VBoxContainer
var _pause_level_nav: HBoxContainer
var _custom_level: bool = false
var _toast_time: float = 0.0
var _final_level: bool = false
var _built: bool = false
var _current_lesson: String = ""

func _ready() -> void:
	layer = 10
	_build()
	show_title()

func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast_panel.modulate.a = minf(_toast_time * 2.0, 1.0)
		if _toast_time <= 0.0:
			_toast_panel.hide()

func _style(background: Color, border: Color = Color.TRANSPARENT, radius: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 13
	style.content_margin_bottom = 13
	return style

func _label(text_value: String, font_size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text_value: String, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size = Vector2(0, 46)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color("102c2b") if primary else INK)
	button.add_theme_color_override("font_hover_color", Color("102c2b") if primary else Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color("102c2b") if primary else INK)
	button.add_theme_stylebox_override("normal", _style(TEAL if primary else Color(0.1, 0.21, 0.21, 0.8), Color(0.5, 0.72, 0.65, 0.26), 7))
	button.add_theme_stylebox_override("hover", _style(Color("a0dcc5") if primary else Color("254c46"), TEAL, 7))
	button.add_theme_stylebox_override("pressed", _style(Color("6ead98") if primary else Color("183a36"), TEAL, 7))
	return button

func _full_control(parent: Node) -> Control:
	var control := Control.new()
	parent.add_child(control)
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control

func _build() -> void:
	if _built:
		return
	_built = true
	_root = _full_control(self)
	_game_ui = _full_control(_root)
	_build_topbar()
	_build_footer()
	_build_orientation()
	_build_toast()
	_build_title()
	_build_pause()
	_build_completion()

func _build_topbar() -> void:
	var chapter := VBoxContainer.new()
	_game_ui.add_child(chapter)
	chapter.position = Vector2(34, 28)
	chapter.add_theme_constant_override("separation", 3)
	chapter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chapter_label = _label("F O L D     /     CHAPTER 01", 11, TEAL)
	chapter.add_child(_chapter_label)
	_title_label = _label("The hidden path", 28)
	chapter.add_child(_title_label)
	_subtitle_label = _label("A garden with another side.", 12, MUTED)
	chapter.add_child(_subtitle_label)
	_level_nav = HBoxContainer.new()
	_game_ui.add_child(_level_nav)
	_level_nav.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_level_nav.offset_top = 29
	_level_nav.offset_bottom = 71
	_level_nav.add_theme_constant_override("separation", 7)
	var seeds := VBoxContainer.new()
	_game_ui.add_child(seeds)
	seeds.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	seeds.offset_left = -254
	seeds.offset_right = -34
	seeds.offset_top = 29
	seeds.offset_bottom = 109
	seeds.add_theme_constant_override("separation", 2)
	seeds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var seed_heading := _label("ECHOES FOUND", 10, MUTED)
	seed_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	seeds.add_child(seed_heading)
	_seed_label = _label("0 / 2", 25)
	_seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	seeds.add_child(_seed_label)
	_seed_dots = _label("○  ○", 14, GOLD)
	_seed_dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	seeds.add_child(_seed_dots)

func _build_footer() -> void:
	var lesson_panel := PanelContainer.new()
	_game_ui.add_child(lesson_panel)
	lesson_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	lesson_panel.offset_left = 34
	lesson_panel.offset_right = 434
	lesson_panel.offset_top = -199
	lesson_panel.offset_bottom = -83
	lesson_panel.add_theme_stylebox_override("panel", _style(Color(0.055, 0.13, 0.13, 0.84), Color(0.51, 0.75, 0.65, 0.15), 10))
	lesson_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lesson_box := VBoxContainer.new()
	lesson_panel.add_child(lesson_box)
	lesson_box.add_theme_constant_override("separation", 5)
	_lesson_heading = _label("A NEW PERSPECTIVE", 10, TEAL)
	lesson_box.add_child(_lesson_heading)
	_lesson_label = _label("Turn the world to discover a path.", 13, INK)
	_lesson_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lesson_label.custom_minimum_size.x = 362
	lesson_box.add_child(_lesson_label)
	var hint := _button("H  ·  A little guidance")
	hint.custom_minimum_size.y = 27
	hint.add_theme_font_size_override("font_size", 10)
	var hint_style := _style(Color.TRANSPARENT, Color.TRANSPARENT, 4)
	hint_style.content_margin_left = 0
	hint_style.content_margin_right = 0
	hint_style.content_margin_top = 2
	hint_style.content_margin_bottom = 2
	hint.add_theme_stylebox_override("normal", hint_style)
	hint.add_theme_stylebox_override("hover", hint_style)
	hint.add_theme_stylebox_override("pressed", hint_style)
	hint.add_theme_color_override("font_hover_color", GOLD)
	hint.alignment = HORIZONTAL_ALIGNMENT_LEFT
	hint.pressed.connect(func() -> void: hint_requested.emit())
	lesson_box.add_child(hint)
	var controls_center := CenterContainer.new()
	_game_ui.add_child(controls_center)
	controls_center.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	controls_center.offset_top = -54
	controls_center.offset_bottom = -20
	controls_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var controls := HBoxContainer.new()
	controls_center.add_child(controls)
	controls.add_theme_constant_override("separation", 18)
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_key_group(controls, "MOUSE", "look")
	_add_key_group(controls, "W A S D", "move")
	_add_key_group(controls, "SPACE", "jump")
	_add_key_group(controls, "Q − / E +", "hold to fold")
	_add_key_group(controls, "R", "restart")
	_add_key_group(controls, "H", "hint")
	_add_key_group(controls, "M", "sound")
	_add_key_group(controls, "ESC", "pause / cursor")

func _add_key_group(parent: HBoxContainer, keys: String, action: String) -> void:
	var group := HBoxContainer.new()
	group.add_theme_constant_override("separation", 7)
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(group)
	var keycap := PanelContainer.new()
	keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var key_style := _style(Color(0.055, 0.13, 0.13, 0.8), Color(0.63, 0.76, 0.7, 0.24), 4)
	key_style.content_margin_left = 7
	key_style.content_margin_right = 7
	key_style.content_margin_top = 4
	key_style.content_margin_bottom = 4
	keycap.add_theme_stylebox_override("panel", key_style)
	keycap.add_child(_label(keys, 10, INK))
	group.add_child(keycap)
	group.add_child(_label(action, 11, MUTED))

func _build_orientation() -> void:
	var panel := PanelContainer.new()
	_game_ui.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -202
	panel.offset_right = -34
	panel.offset_top = -300
	panel.offset_bottom = -79
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(Color(0.055, 0.13, 0.13, 0.8), Color(0.51, 0.75, 0.65, 0.15), 10))
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_theme_constant_override("separation", 2)
	var heading := _label("YOUR CROSS-SECTION", 9, MUTED)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	_orientation = OrientationView.new()
	_orientation.custom_minimum_size = Vector2(132, 127)
	_orientation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_orientation)
	_slice_label = _label("XYZ   /   0.0°", 12, TEAL)
	_slice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_slice_label)
	_coordinate_label = _label("X +0.0   Y +0.0\nZ +0.0   W +0.0", 11, MUTED)
	_coordinate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_coordinate_label)

func _build_toast() -> void:
	_toast_panel = PanelContainer.new()
	_game_ui.add_child(_toast_panel)
	_toast_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast_panel.offset_left = -280
	_toast_panel.offset_right = 280
	_toast_panel.offset_top = 112
	_toast_panel.offset_bottom = 157
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.add_theme_stylebox_override("panel", _style(PANEL, Color(0.91, 0.74, 0.46, 0.4), 9))
	_toast_label = _label("", 13, GOLD)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_panel.add_child(_toast_label)
	_toast_panel.hide()

func _overlay() -> Control:
	var overlay := _full_control(_root)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.025, 0.085, 0.085, 0.85)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return overlay

func _overlay_box(overlay: Control, width: float, height: float) -> VBoxContainer:
	var center := CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	center.add_child(box)
	box.custom_minimum_size = Vector2(width, height)
	box.add_theme_constant_override("separation", 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box

func _center_label(box: VBoxContainer, text_value: String, font_size: int, color: Color = INK) -> Label:
	var label := _label(text_value, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	return label

func _gap(box: VBoxContainer, height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)

func _build_title() -> void:
	_title_overlay = _overlay()
	var box := _overlay_box(_title_overlay, 580, 575)
	_center_label(box, "A GARDEN BEYOND THREE DIMENSIONS", 11, TEAL)
	var wordmark := _center_label(box, "F O L D", 88)
	wordmark.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.18))
	wordmark.add_theme_constant_override("shadow_offset_y", 4)
	_center_label(box, "T H E   Q U I E T   D I M E N S I O N", 14, GOLD)
	_gap(box, 13)
	var intro := _center_label(box, "There is more to this garden than meets the eye.\nStep through a three-dimensional slice of a four-dimensional world.\nFold your perspective. Find the echoes. Make your way home.", 15, MUTED)
	intro.add_theme_constant_override("line_spacing", 7)
	_gap(box, 15)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var start := _button("Enter the garden   →", true)
	start.custom_minimum_size = Vector2(245, 51)
	start.pressed.connect(func() -> void: start_requested.emit())
	row.add_child(start)
	_labyrinth_button = _button("Explore the labyrinth   →")
	_labyrinth_button.custom_minimum_size = Vector2(245, 51)
	_labyrinth_button.pressed.connect(func() -> void: level_requested.emit(3))
	row.add_child(_labyrinth_button)
	_labyrinth_button.hide()
	var ascent_row := HBoxContainer.new()
	ascent_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(ascent_row)
	_ascent_button = _button("Jump the 4D shapes   →")
	_ascent_button.custom_minimum_size = Vector2(502, 51)
	_ascent_button.pressed.connect(func() -> void: level_requested.emit(4))
	ascent_row.add_child(_ascent_button)
	_ascent_button.hide()
	_gap(box, 13)
	_center_label(box, "MOUSE  look     ·     W A S D  move with camera     ·     SPACE  jump", 11, MUTED)
	_center_label(box, "Hold Q − / E + to fold     ·     ESC  pause / free cursor", 11, MUTED)
	_campaign_label = _center_label(box, "GARDENS TO EXPLORE  /  ONE EXTRA DIMENSION", 9, Color(0.55, 0.68, 0.62, 0.8))
	var footnote := _label("An original spatial puzzle", 10, MUTED)
	_title_overlay.add_child(footnote)
	footnote.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	footnote.offset_left = -130
	footnote.offset_right = 130
	footnote.offset_top = -35
	footnote.offset_bottom = -21
	footnote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_pause() -> void:
	_pause_overlay = _overlay()
	var box := _overlay_box(_pause_overlay, 400, 452)
	_center_label(box, "TAKE A BREATH", 11, TEAL)
	_center_label(box, "A quiet moment", 35)
	_center_label(box, "The garden will be here.", 14, MUTED)
	_gap(box, 12)
	var resume := _button("Return to the garden", true)
	resume.pressed.connect(func() -> void: pause_requested.emit())
	box.add_child(resume)
	var restart := _button("Begin this chapter again")
	restart.pressed.connect(func() -> void: restart_requested.emit())
	box.add_child(restart)
	_pause_chapters = VBoxContainer.new()
	_pause_chapters.add_theme_constant_override("separation", 7)
	box.add_child(_pause_chapters)
	_center_label(_pause_chapters, "CHOOSE A GARDEN", 10, TEAL)
	_pause_level_nav = HBoxContainer.new()
	_pause_level_nav.alignment = BoxContainer.ALIGNMENT_CENTER
	_pause_level_nav.add_theme_constant_override("separation", 7)
	_pause_chapters.add_child(_pause_level_nav)
	_pause_chapters.hide()
	var quit := _button("Quit to desktop")
	quit.pressed.connect(func() -> void: quit_requested.emit())
	box.add_child(quit)
	_center_label(box, "Cursor is free. ESC to return to mouse look.", 11, MUTED)
	_pause_overlay.hide()

func _build_completion() -> void:
	_completion_overlay = _overlay()
	var box := _overlay_box(_completion_overlay, 510, 340)
	_center_label(box, "✦   THE GARDEN REMEMBERS   ✦", 11, GOLD)
	_completion_title = _center_label(box, "A path revealed", 38)
	_completion_copy = _center_label(box, "Another perspective. Another possibility.", 15, MUTED)
	_completion_copy.add_theme_constant_override("line_spacing", 6)
	_gap(box, 22)
	_next_button = _button("The next garden   →", true)
	_next_button.pressed.connect(_on_next_pressed)
	box.add_child(_next_button)
	var replay := _button("Explore this chapter again")
	replay.pressed.connect(func() -> void: restart_requested.emit())
	box.add_child(replay)
	_completion_overlay.hide()

func _on_next_pressed() -> void:
	if _final_level:
		level_requested.emit(0)
	else:
		next_requested.emit()

func set_custom_level(value: bool) -> void:
	_custom_level = value
	if _built:
		_update_navigation_visibility()

func _chapter_button(index: int) -> Button:
	var button := _button("%02d" % (index + 1))
	button.custom_minimum_size = Vector2(50, 32)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_stylebox_override("normal", _style(Color(0.05, 0.14, 0.14, 0.68), Color(0.5, 0.72, 0.65, 0.18), 6))
	button.pressed.connect(func() -> void: level_requested.emit(index))
	return button

func _update_navigation_visibility() -> void:
	var show_chapters := not _custom_level and _level_buttons.size() > 1
	_level_nav.visible = show_chapters
	_pause_chapters.visible = show_chapters
	_labyrinth_button.visible = not _custom_level and _level_buttons.size() >= 4
	_ascent_button.visible = not _custom_level and _level_buttons.size() >= 5

func _setup_navigation(total: int) -> void:
	if _level_buttons.size() != total:
		for button: Button in _level_buttons:
			_level_nav.remove_child(button)
			button.queue_free()
		_level_buttons.clear()
		for button: Button in _pause_level_buttons:
			_pause_level_nav.remove_child(button)
			button.queue_free()
		_pause_level_buttons.clear()
		for index: int in range(total):
			var button := _chapter_button(index)
			_level_nav.add_child(button)
			_level_buttons.append(button)
			var pause_button := _chapter_button(index)
			_pause_level_nav.add_child(pause_button)
			_pause_level_buttons.append(pause_button)
	var nav_width := total * 50.0 + maxi(total - 1, 0) * 7.0
	_level_nav.offset_left = -nav_width / 2.0
	_level_nav.offset_right = nav_width / 2.0
	_update_navigation_visibility()

func setup_level(index: int, total: int, title: String, subtitle: String, lesson: String, seed_count: int) -> void:
	_build()
	_setup_navigation(total)
	if not _custom_level:
		_campaign_label.text = "%d GARDENS TO EXPLORE  /  ONE EXTRA DIMENSION" % total
	_chapter_label.text = "F O L D     /     CUSTOM GARDEN" if _custom_level else "F O L D     /     CHAPTER %02d OF %02d" % [index + 1, total]
	_title_label.text = title
	_subtitle_label.text = subtitle
	_current_lesson = lesson
	_lesson_heading.text = "A NEW PERSPECTIVE"
	_lesson_label.text = lesson
	_seed_label.text = "0 / %d" % seed_count
	_seed_dots.text = "○  ".repeat(seed_count).strip_edges()
	for button_index: int in range(_level_buttons.size()):
		_level_buttons[button_index].visible = button_index < total
		_level_buttons[button_index].add_theme_color_override("font_color", GOLD if button_index == index else MUTED)
		_pause_level_buttons[button_index].add_theme_color_override("font_color", GOLD if button_index == index else MUTED)
	_completion_overlay.hide()
	_pause_overlay.hide()
	_toast_panel.hide()
	_toast_time = 0.0

func update_state(collected: int, total: int, angle: float, pos4: Vector4, rotating: bool) -> void:
	if not _built:
		return
	_seed_label.text = "%d / %d" % [collected, total]
	_seed_dots.text = "●  ".repeat(collected) + "○  ".repeat(maxi(total - collected, 0))
	_orientation.angle = angle
	_orientation.hidden_coordinate = pos4.w
	_orientation.is_rotating = rotating
	_orientation.queue_redraw()
	var slice_name := "MIXED"
	if absf(sin(angle)) < 0.00001:
		slice_name = "XYZ"
	elif absf(cos(angle)) < 0.00001:
		slice_name = "XYW"
	var degrees := wrapf(snappedf(rad_to_deg(angle), 0.1), 0.0, 360.0)
	_slice_label.text = "%s   /   %.1f°" % [slice_name, degrees]
	_coordinate_label.text = "X %+.1f   Y %+.1f\nZ %+.1f   W %+.1f" % [pos4.x, pos4.y, pos4.z, pos4.w]

func show_toast(message: String) -> void:
	_build()
	_toast_label.text = message
	_toast_panel.modulate.a = 1.0
	_toast_panel.show()
	_toast_time = 4.5

func show_hint(message: String) -> void:
	_build()
	_lesson_heading.text = "A QUIET HINT"
	_lesson_label.text = message

func show_completion(final_level: bool) -> void:
	_build()
	_final_level = final_level
	_completion_title.text = "A world made wider" if final_level else "A path revealed"
	_completion_copy.text = "You found every garden's hidden side.\nThere is always another way to see." if final_level else "Another perspective. Another possibility.\nYour next garden is waiting."
	_next_button.text = "Return to the first garden   ↺" if final_level else "The next garden   →"
	if _custom_level:
		_completion_title.text = "Your garden, explored"
		_completion_copy.text = "Every echo found. A path to the gate.\nReturn to the editor to keep creating."
		_next_button.text = "Play this garden again   ↺"
	_pause_overlay.hide()
	_completion_overlay.show()

func show_pause(paused: bool) -> void:
	_build()
	_pause_overlay.visible = paused

func show_title() -> void:
	_build()
	_game_ui.hide()
	_title_overlay.show()
	_pause_overlay.hide()
	_completion_overlay.hide()

func hide_title() -> void:
	_build()
	_title_overlay.hide()
	_game_ui.show()
