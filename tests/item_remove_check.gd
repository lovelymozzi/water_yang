extends Node

## 실행: Godot --headless --path . res://tests/item_remove_check.tscn
## (--script 모드는 UiBridge 오토로드가 등록되지 않아 씬 실행으로 돌린다)

const OBSTACLE_BLOCK_SCENE := preload("res://scenes/obstacle_block.tscn")
const TARGET_CELL := Vector2i(1, 1)


func _ready() -> void:
	var manager := LevelManager.new()
	manager.name = "LevelManager"
	manager.grid_size = Vector2i(3, 3)
	manager.obstacles_enabled = true
	add_child(manager)
	await get_tree().process_frame

	var marker := OBSTACLE_BLOCK_SCENE.instantiate()
	marker.grid_pos = TARGET_CELL
	marker.block_size = Vector2i.ONE
	manager.get_node("LayoutObstacles").add_child(marker)
	manager.rebuild_now()

	assert(manager.get_obstacle_cells().has(TARGET_CELL), "FAIL: 장애물이 배치되지 않음")
	assert(manager.remove_obstacle(TARGET_CELL), "FAIL: 장애물 제거 실패")
	assert(not manager.get_obstacle_cells().has(TARGET_CELL), "FAIL: 장애물 셀이 남음")
	assert(not manager.is_cell_blocked_for(null, TARGET_CELL), "FAIL: 제거한 칸이 계속 막힘")
	assert(
		manager.get_node("ObstacleVisuals").get_node_or_null("ItemRemoveShards") != null,
		"FAIL: 제거 파티클이 생성되지 않음"
	)
	print("PASS: item remove clears obstacle and spawns particles")
	get_tree().quit(0)
