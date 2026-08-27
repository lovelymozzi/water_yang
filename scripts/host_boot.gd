extends Node

const MAIN_SCENE := "res://scenes/main_scene.tscn"


func _ready() -> void:
	if UiBridge.is_hosted:
		return
	get_tree().call_deferred("change_scene_to_file", MAIN_SCENE)
