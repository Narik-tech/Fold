@tool
extends EditorPlugin
## Owns the main-screen panel and its lifetime; game code never depends on it.

const LevelEditor = preload("res://addons/fold_level_editor/level_editor.gd")

var _panel: Control


func _enter_tree() -> void:
	_panel = LevelEditor.new()
	EditorInterface.get_editor_main_screen().add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.hide()


func _exit_tree() -> void:
	if is_instance_valid(_panel):
		_panel.queue_free()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if is_instance_valid(_panel):
		_panel.visible = visible


func _get_plugin_name() -> String:
	return "FOLD Levels"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Grid", "EditorIcons")


func _get_unsaved_status(for_scene: String) -> String:
	if for_scene.is_empty() and is_instance_valid(_panel) and _panel.document.is_dirty():
		return "FOLD Levels has unsaved edits. Save updates an existing valid level, or keeps a local recovery draft for an unnamed or invalid level."
	return ""


func _save_external_data() -> void:
	if is_instance_valid(_panel):
		_panel.save_external_data()
