extends Node

## 아이템 대상 밖을 누르면 선택 모드가 해제되어 다음 고양이 드래그가 가능해야 한다.

func _ready() -> void:
	var scene := load("res://scenes/main_scene.tscn") as PackedScene
	var main := scene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var controller: DragController = main.get_node("DragController")
	controller.begin_cat_selection()
	controller._press(0, Vector2(-1000.0, -1000.0))
	assert(not controller._selecting_cat, "FAIL: 이동 아이템 대상 밖 탭 뒤 선택 모드가 남음")
	var cat: CatEntity = main.level_manager.get_cats()[0]
	var camera: Camera3D = main.get_node("Camera3D")
	controller._press(0, camera.unproject_position(main.level_manager.grid_to_world(cat.get_lead_cell(), main.level_manager.cat_world_y)))
	assert(controller._has_pointer, "FAIL: 선택 취소 뒤 일반 고양이 드래그가 시작되지 않음")
	controller._release_pointer(0)
	print("PASS: item target miss cancels selection and restores drag")
	get_tree().quit(0)
