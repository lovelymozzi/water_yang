@tool
extends EditorPlugin

const PALETTE_INSPECTOR := preload("res://addons/cat_hole_palette_inspector/palette_inspector.gd")

var _inspector_plugin: EditorInspectorPlugin


func _enter_tree() -> void:
	_inspector_plugin = PALETTE_INSPECTOR.new()
	_inspector_plugin.configure(get_undo_redo())
	add_inspector_plugin(_inspector_plugin)


func _exit_tree() -> void:
	if _inspector_plugin != null:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null
