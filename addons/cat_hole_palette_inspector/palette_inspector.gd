@tool
extends EditorInspectorPlugin

const PALETTE_EDITOR := preload("res://addons/cat_hole_palette_inspector/palette_inspector_control.gd")
const LEVEL_MANAGER_SCRIPT_PATH := "res://scripts/level_manager.gd"

var _undo_redo: EditorUndoRedoManager


func configure(undo_redo: EditorUndoRedoManager) -> void:
	_undo_redo = undo_redo


func _can_handle(object: Object) -> bool:
	# Script-path matching remains reliable while Godot is rebuilding its
	# global-class cache, including immediately after this plugin is enabled.
	var script := object.get_script() as Script
	return script != null and script.resource_path == LEVEL_MANAGER_SCRIPT_PATH


func _parse_begin(object: Object) -> void:
	var editor := PALETTE_EDITOR.new()
	editor.configure(object as LevelManager, _undo_redo)
	add_custom_control(editor)
