@tool
class_name LevelManager
extends Node3D

signal level_cleared

const CAT_ENTITY_SCRIPT = preload("res://scripts/cat_entity.gd")
const OBSTACLE_MARKER_SCRIPT = preload("res://scripts/obstacle_marker.gd")
const TILE_HEIGHT := 0.12
const OBSTACLE_HEIGHT := 1.3
const TILE_CORNER_RADIUS := 0.14
const BOARD_CORNER_RADIUS := 0.42
const ROUND_CORNER_SEGMENTS := 6
# 빠른 스와이프 한 번이 만들어낼 수 있는 최대 셀 이동 수.
const MAX_DRAG_STEPS_PER_EVENT := 8

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

@export_range(0.0, 0.6, 0.01) var tile_gap: float = 0.12:
	set(value):
		tile_gap = value
		request_preview_refresh()

@export_range(0.0, 4.0, 0.1) var board_side_margin: float = 0.7:
	set(value):
		board_side_margin = value
		request_preview_refresh()

@export_range(0.0, 6.0, 0.1) var board_vertical_margin: float = 2.0:
	set(value):
		board_vertical_margin = value
		request_preview_refresh()

@export var cat_world_y: float = 0.78:
	set(value):
		cat_world_y = value
		request_preview_refresh()

@export var obstacles_enabled: bool = false:
	set(value):
		obstacles_enabled = value
		request_preview_refresh()

# 이미 열린 씬에서도 Inspector 버튼으로 에디터용 보드를 즉시 다시 만든다.
@export_tool_button("Refresh Board Preview", "Reload") var refresh_board_preview_action = refresh_board_preview

var _grid_state: Array = []
var _grid_refs: Array = []
var _cats: Array[CatEntity] = []
var _preview_refresh_queued: bool = false

var _board_root: Node3D
var _tiles_root: Node3D
var _obstacles_root: Node3D
var _layout_cats_root: Node3D
var _layout_obstacles_root: Node3D
var _drag_cat: CatEntity
var _drag_endpoint: StringName = &""


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
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_endpoint_drag(event.position)
		else:
			_end_endpoint_drag()
	elif event is InputEventMouseMotion and _drag_cat != null and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_update_endpoint_drag(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_begin_endpoint_drag(event.position)
		else:
			_end_endpoint_drag()
	elif event is InputEventScreenDrag and _drag_cat != null:
		_update_endpoint_drag(event.position)


func request_preview_refresh() -> void:
	if not is_inside_tree():
		return

	if _preview_refresh_queued:
		return

	_preview_refresh_queued = true
	call_deferred("_refresh_preview_deferred")


func refresh_board_preview() -> void:
	if Engine.is_editor_hint():
		request_preview_refresh()


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
	update_cat_occupancy(cat)


func release_cat_cell(cat: CatEntity) -> void:
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell := Vector2i(x, y)
			if _get_cell_ref(cell) == cat:
				_set_cell_state(cell, CellState.EMPTY)
				_set_cell_ref(cell, null)


func update_cat_occupancy(cat: CatEntity) -> void:
	release_cat_cell(cat)
	for cell in cat.body_cells:
		if is_inside_grid(cell):
			_set_cell_state(cell, CellState.CAT)
			_set_cell_ref(cell, cat)


func can_extend_cat_to(cat: CatEntity, cell: Vector2i) -> bool:
	if not is_inside_grid(cell):
		return false
	return _get_cell_state(cell) == CellState.EMPTY


func can_place_cat_body(cat: CatEntity, candidate: Array[Vector2i]) -> bool:
	var body_cells := {}
	for cell in candidate:
		# 같은 셀을 다시 지나가면 몸통끼리도 겹친다.
		if body_cells.has(cell):
			return false
		body_cells[cell] = true

	for cell in candidate:
		if not is_inside_grid(cell):
			return false
		var occupant: Variant = _get_cell_ref(cell)
		# 현재 이 고양이가 차지하던 셀은 후보 경로를 검사하는 동안만 통과를 허용한다.
		if occupant != null and occupant != cat:
			return false
	return true


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
	var board_size := Vector3(
		grid_size.x * tile_size + board_side_margin * 2.0,
		0.36,
		grid_size.y * tile_size + board_vertical_margin * 2.0
	)
	var board := _create_rounded_prism(
		"BoardBase", board_size, BOARD_CORNER_RADIUS,
		_make_material(Color(0.83, 0.62, 0.42, 1.0))
	)
	board.position = Vector3(0.0, -0.18, 0.0)
	_board_root.add_child(board)


func _build_grid_tiles() -> void:
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell: Vector2i = Vector2i(x, y)
			var tile_side := maxf(tile_size - tile_gap, 0.01)
			var tile := _create_rounded_prism(
				"Tile_%d_%d" % [x, y],
				Vector3(tile_side, TILE_HEIGHT, tile_side),
				TILE_CORNER_RADIUS,
				_make_material(_tile_color_for(cell))
			)
			tile.position = grid_to_world(cell, TILE_HEIGHT * 0.5)
			_tiles_root.add_child(tile)


func _create_rounded_prism(
	shape_name: String,
	size: Vector3,
	corner_radius: float,
	material: Material
) -> CSGPolygon3D:
	var half_width := size.x * 0.5
	var half_depth := size.z * 0.5
	var radius := minf(corner_radius, minf(half_width, half_depth) * 0.45)
	var centers := [
		Vector2(half_width - radius, half_depth - radius),
		Vector2(-half_width + radius, half_depth - radius),
		Vector2(-half_width + radius, -half_depth + radius),
		Vector2(half_width - radius, -half_depth + radius),
	]
	var outline := PackedVector2Array()

	for corner_index in range(centers.size()):
		var start_angle := float(corner_index) * PI * 0.5
		for segment in range(ROUND_CORNER_SEGMENTS + 1):
			var angle := start_angle + PI * 0.5 * float(segment) / float(ROUND_CORNER_SEGMENTS)
			outline.append(centers[corner_index] + Vector2(cos(angle), sin(angle)) * radius)

	var prism := CSGPolygon3D.new()
	prism.name = shape_name
	prism.polygon = outline
	prism.mode = CSGPolygon3D.MODE_DEPTH
	prism.depth = size.y
	prism.material = material
	# 기본 폴리곤의 깊이 축(Z)을 월드의 높이 축(Y)으로 바꾼다.
	prism.rotation.x = -PI * 0.5
	prism.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return prism


func _sync_obstacle_layout() -> void:
	if not obstacles_enabled:
		for child in _layout_obstacles_root.get_children():
			if child.get_script() == OBSTACLE_MARKER_SCRIPT:
				child.call("set_preview_visible", false)
		return

	for child in _layout_obstacles_root.get_children():
		if child.get_script() != OBSTACLE_MARKER_SCRIPT:
			continue

		child.call("set_preview_visible", true)
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
		if Engine.is_editor_hint():
			cat.level_manager = self
			cat.refresh_editor_preview()
		else:
			cat.initialize_runtime(self)

		if not is_inside_grid(cat.grid_pos):
			continue

		update_cat_occupancy(cat)
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


func _begin_endpoint_drag(screen_pos: Vector2) -> void:
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
	if collider is Area3D and (collider as Area3D).has_meta("cat_endpoint"):
		var handle := collider as Area3D
		var cat := handle.get_parent().get_parent() as CatEntity
		if cat != null:
			_drag_cat = cat
			_drag_endpoint = handle.get_meta("cat_endpoint") as StringName
			_drag_cat.begin_drag()


func _update_endpoint_drag(screen_pos: Vector2) -> void:
	if _drag_cat == null:
		return
	var target_cell: Variant = _screen_to_grid_cell(screen_pos)
	if target_cell == null:
		return
	_step_drag_towards(target_cell as Vector2i)


func _step_drag_towards(target_cell: Vector2i) -> void:
	# 한 번의 입력 이벤트에서 손가락이 여러 칸을 지나가도 그 입력을 버리지 않는다.
	# 다만 실제 이동은 언제나 인접 한 칸씩이므로 몸통은 그리드를 벗어나지 않는다.
	for _step in range(MAX_DRAG_STEPS_PER_EVENT):
		var endpoint_cell: Vector2i = (
			_drag_cat.get_head_cell() if _drag_endpoint == &"head" else _drag_cat.get_tail_cell()
		)
		var delta: Vector2i = target_cell - endpoint_cell
		if delta == Vector2i.ZERO:
			return

		# 남은 거리가 큰 축을 먼저 시도하고, 막히면 나머지 축으로 우회한다.
		var prefer_x: bool = absi(delta.x) >= absi(delta.y)
		var primary: Vector2i = _axis_step(delta, prefer_x)
		var secondary: Vector2i = _axis_step(delta, not prefer_x)

		if primary != Vector2i.ZERO and _drag_cat.drag_endpoint_to(_drag_endpoint, endpoint_cell + primary):
			continue
		if secondary != Vector2i.ZERO and _drag_cat.drag_endpoint_to(_drag_endpoint, endpoint_cell + secondary):
			continue
		return


func _axis_step(delta: Vector2i, use_x: bool) -> Vector2i:
	if use_x:
		return Vector2i(signi(delta.x), 0)
	return Vector2i(0, signi(delta.y))


func _end_endpoint_drag() -> void:
	if _drag_cat != null:
		# 손을 놓으면 가장 가까운 그리드 정위치로 각지게 수렴한다.
		_drag_cat.end_drag()
	_drag_cat = null
	_drag_endpoint = &""


func _screen_to_grid_cell(screen_pos: Vector2) -> Variant:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var plane := Plane(Vector3.UP, cat_world_y)
	var hit: Variant = plane.intersects_ray(origin, direction)
	if hit == null:
		return null
	var world_pos := hit as Vector3
	var grid_origin := grid_to_world(Vector2i.ZERO)
	return Vector2i(
		roundi((world_pos.x - grid_origin.x) / tile_size),
		roundi((world_pos.z - grid_origin.z) / tile_size)
	)


func _get_cell_state(cell: Vector2i) -> int:
	return _grid_state[cell.y][cell.x]


func _set_cell_state(cell: Vector2i, state: int) -> void:
	_grid_state[cell.y][cell.x] = state


func _get_cell_ref(cell: Vector2i) -> Variant:
	return _grid_refs[cell.y][cell.x]


func _set_cell_ref(cell: Vector2i, value: Variant) -> void:
	_grid_refs[cell.y][cell.x] = value
