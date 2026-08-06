@tool
class_name LevelManager
extends Node3D

signal level_cleared

const CAT_ENTITY_SCRIPT = preload("res://scripts/cat_entity.gd")
const OBSTACLE_MARKER_SCRIPT = preload("res://scripts/obstacle_marker.gd")
const TILE_HEIGHT := 0.12
const OBSTACLE_HEIGHT := 1.3

enum CellState {
	EMPTY,
	OBSTACLE,
	CAT,
}

@export var grid_size: Vector2i = Vector2i(7, 9):
	set(value):
		grid_size = value
		request_preview_refresh()

@export var tile_size: float = 2.0:
	set(value):
		tile_size = value
		request_preview_refresh()

@export var cat_world_y: float = 0.78:
	set(value):
		cat_world_y = value
		request_preview_refresh()

var _grid_state: Array = []
var _grid_refs: Array = []
var _cats: Array[CatEntity] = []
var _preview_refresh_queued: bool = false

var _board_root: Node3D
var _tiles_root: Node3D
var _obstacles_root: Node3D
var _layout_cats_root: Node3D
var _layout_obstacles_root: Node3D


func _ready() -> void:
	_setup_roots()
	if Engine.is_editor_hint():
		request_preview_refresh()
	else:
		_rebuild_from_scene_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_CHILD_ORDER_CHANGED and Engine.is_editor_hint():
		request_preview_refresh()


func _unhandled_input(event: InputEvent) -> void:
	# 마우스 클릭과 모바일 터치를 모두 같은 선택 흐름으로 처리한다.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_pointer_select(event.position)
	elif event is InputEventScreenTouch and event.pressed:
		_handle_pointer_select(event.position)


func request_preview_refresh() -> void:
	if not is_inside_tree():
		return

	if _preview_refresh_queued:
		return

	_preview_refresh_queued = true
	call_deferred("_refresh_preview_deferred")


func _refresh_preview_deferred() -> void:
	_preview_refresh_queued = false
	_setup_roots()
	_rebuild_from_scene_layout()


func is_inside_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_size.x and cell.y >= 0 and cell.y < grid_size.y


func grid_to_world(cell: Vector2i, y: float = 0.0) -> Vector3:
	var board_origin: Vector3 = Vector3(
		-((grid_size.x - 1) * tile_size) * 0.5,
		y,
		-((grid_size.y - 1) * tile_size) * 0.5
	)
	return board_origin + Vector3(cell.x * tile_size, 0.0, cell.y * tile_size)


func grid_dir_to_world(dir: Vector2i) -> Vector3:
	return Vector3(dir.x, 0.0, dir.y).normalized()


func occupy_cat_cell(cat: CatEntity) -> void:
	_set_cell_state(cat.grid_pos, CellState.CAT)
	_set_cell_ref(cat.grid_pos, cat)


func release_cat_cell(cat: CatEntity) -> void:
	if not is_inside_grid(cat.grid_pos):
		return

	if _get_cell_ref(cat.grid_pos) != cat:
		return

	_set_cell_state(cat.grid_pos, CellState.EMPTY)
	_set_cell_ref(cat.grid_pos, null)


func get_escape_result(cat: CatEntity) -> Dictionary:
	var probe: Vector2i = cat.grid_pos + cat.facing_dir

	# 바라보는 방향으로 그리드 끝까지 훑어서 다른 고양이나 장애물이 있는지 본다.
	while is_inside_grid(probe):
		if _get_cell_state(probe) != CellState.EMPTY:
			return {
				"is_path_clear": false,
				"blocking_cell": probe,
			}
		probe += cat.facing_dir

	var furthest_cell: Vector2i = cat.grid_pos
	while is_inside_grid(furthest_cell + cat.facing_dir):
		furthest_cell += cat.facing_dir

	return {
		"is_path_clear": true,
		"exit_world_position": grid_to_world(furthest_cell, cat_world_y) + grid_dir_to_world(cat.facing_dir) * tile_size * 1.4,
	}


func on_cat_escaped(cat: CatEntity) -> void:
	_cats.erase(cat)
	if _cats.is_empty():
		level_cleared.emit()


func _setup_roots() -> void:
	_board_root = _ensure_named_child(self, "BoardVisuals")
	_tiles_root = _ensure_named_child(self, "TileVisuals")
	_obstacles_root = _ensure_named_child(self, "ObstacleVisuals")
	_layout_cats_root = _ensure_named_child(self, "LayoutCats")
	_layout_obstacles_root = _ensure_named_child(self, "LayoutObstacles")


func _ensure_named_child(parent: Node3D, child_name: String) -> Node3D:
	var node := parent.get_node_or_null(child_name)
	if node is Node3D:
		return node as Node3D

	var created := Node3D.new()
	created.name = child_name
	parent.add_child(created)
	if Engine.is_editor_hint():
		created.owner = owner
	return created


func _rebuild_from_scene_layout() -> void:
	_clear_generated_nodes()
	_initialize_grid_arrays()
	_build_board_base()
	_build_grid_tiles()
	_sync_obstacle_layout()
	_sync_cat_layout()


func _clear_generated_nodes() -> void:
	for child in _board_root.get_children():
		child.queue_free()

	for child in _tiles_root.get_children():
		child.queue_free()

	for child in _obstacles_root.get_children():
		child.queue_free()

	_cats.clear()


func _initialize_grid_arrays() -> void:
	_grid_state.clear()
	_grid_refs.clear()

	for y in range(grid_size.y):
		var state_row: Array[int] = []
		var ref_row: Array = []
		for x in range(grid_size.x):
			state_row.append(CellState.EMPTY)
			ref_row.append(null)
		_grid_state.append(state_row)
		_grid_refs.append(ref_row)


func _build_board_base() -> void:
	# 세로 화면에서 보드가 또렷하게 보이도록 바닥 베이스를 먼저 깐다.
	var board_mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var board_mesh: BoxMesh = BoxMesh.new()
	board_mesh.size = Vector3(
		grid_size.x * tile_size + tile_size * 0.7,
		0.36,
		grid_size.y * tile_size + tile_size * 0.7
	)
	board_mesh_instance.mesh = board_mesh
	board_mesh_instance.position = Vector3(0.0, -0.18, 0.0)
	board_mesh_instance.material_override = _make_material(Color(0.83, 0.62, 0.42, 1.0))
	_board_root.add_child(board_mesh_instance)


func _build_grid_tiles() -> void:
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell: Vector2i = Vector2i(x, y)
			var tile: MeshInstance3D = MeshInstance3D.new()
			var tile_mesh: BoxMesh = BoxMesh.new()
			tile_mesh.size = Vector3(tile_size * 0.94, TILE_HEIGHT, tile_size * 0.94)
			tile.mesh = tile_mesh
			tile.position = grid_to_world(cell, TILE_HEIGHT * 0.5)
			tile.material_override = _make_material(_tile_color_for(cell))
			_tiles_root.add_child(tile)


func _sync_obstacle_layout() -> void:
	for child in _layout_obstacles_root.get_children():
		if child.get_script() != OBSTACLE_MARKER_SCRIPT:
			continue

		child.call("refresh_editor_preview")
		var marker_grid_pos: Vector2i = child.get("grid_pos")

		if not is_inside_grid(marker_grid_pos):
			continue

		_set_cell_state(marker_grid_pos, CellState.OBSTACLE)
		_build_obstacle_visual(marker_grid_pos)


func _sync_cat_layout() -> void:
	for child in _layout_cats_root.get_children():
		if child.get_script() != CAT_ENTITY_SCRIPT:
			continue

		var cat := child as CatEntity
		cat.level_manager = self
		cat.refresh_editor_preview()

		if not is_inside_grid(cat.grid_pos):
			continue

		occupy_cat_cell(cat)
		_cats.append(cat)


func _build_obstacle_visual(cell: Vector2i) -> void:
	var obstacle: MeshInstance3D = MeshInstance3D.new()
	var obstacle_mesh: BoxMesh = BoxMesh.new()
	obstacle_mesh.size = Vector3(tile_size * 0.94, OBSTACLE_HEIGHT * 0.38, tile_size * 0.94)
	obstacle.mesh = obstacle_mesh
	obstacle.position = grid_to_world(cell, OBSTACLE_HEIGHT * 0.19)
	obstacle.material_override = _make_material(Color(0.95, 0.86, 0.70, 1.0))
	_obstacles_root.add_child(obstacle)


func _make_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	return material


func _tile_color_for(cell: Vector2i) -> Color:
	if (cell.x + cell.y) % 2 == 0:
		return Color(0.95, 0.77, 0.62, 1.0)
	return Color(0.93, 0.72, 0.56, 1.0)


func _handle_pointer_select(screen_pos: Vector2) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return

	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_end: Vector3 = ray_origin + camera.project_ray_normal(screen_pos) * 200.0

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return

	var collider: Variant = result.get("collider")
	if collider is CatEntity:
		(collider as CatEntity).try_escape()


func _get_cell_state(cell: Vector2i) -> int:
	return _grid_state[cell.y][cell.x]


func _set_cell_state(cell: Vector2i, state: int) -> void:
	_grid_state[cell.y][cell.x] = state


func _get_cell_ref(cell: Vector2i) -> Variant:
	return _grid_refs[cell.y][cell.x]


func _set_cell_ref(cell: Vector2i, value: Variant) -> void:
	_grid_refs[cell.y][cell.x] = value
