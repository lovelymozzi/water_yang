@tool
extends EditorPlugin

# 메인 스크린 탭 "StageAdmin". 실제 UI 는 전부 admin_panel.gd 에 있다.

var _panel: Control


func _enter_tree() -> void:
	_panel = preload("res://addons/stage_admin/admin_panel.gd").new()
	EditorInterface.get_editor_main_screen().add_child(_panel)
	_make_visible(false)


func _exit_tree() -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "StageAdmin"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("GridMap", "EditorIcons")


func _make_visible(visible: bool) -> void:
	if _panel != null:
		_panel.visible = visible
