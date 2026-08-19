@tool
class_name LevelManager
extends Node3D

signal level_cleared

const CAT_ENTITY_SCRIPT = preload("res://scripts/cat_entity.gd")
const OBSTACLE_MARKER_SCRIPT = preload("res://scripts/obstacle_marker.gd")
const HOLE_MARKER_SCRIPT = preload("res://scripts/hole_marker.gd")
const BOARD_VISUAL_TEXTURE = preload("res://water_yang/bg_tile1_1.jpg")
const FLOOR_TILE_SCENE = preload("res://scenes/path_tile_1x1.tscn")
const PATH_PREVIEW_SCENE = preload("res://scenes/path_tile_1x1.tscn")
const ICE_BLOCK_SCENE = preload("res://scenes/ice_block.tscn")
const TILE_HEIGHT := 0.12
const TILE_CORNER_RADIUS := 0.14
const BOARD_CORNER_RADIUS := 0.42
const ROUND_CORNER_SEGMENTS := 6

enum CellState {
	EMPTY,
	OBSTACLE,
	CAT,
	HOLE,
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

@export_range(-0.2, 0.2, 0.01) var board_visual_y_offset: float = 0.0:
	set(value):
		board_visual_y_offset = value
		request_preview_refresh()

@export_group("Board Texture")
@export var board_visual_texture: Texture2D = BOARD_VISUAL_TEXTURE:
	set(value):
		board_visual_texture = value
		request_preview_refresh()

@export var board_texture_tiling: Vector2 = Vector2.ONE:
	set(value):
		board_texture_tiling = Vector2(maxf(value.x, 0.01), maxf(value.y, 0.01))
		request_preview_refresh()

@export_group("Board Tiles")
@export var floor_tile_scene: PackedScene = FLOOR_TILE_SCENE:
	set(value):
		floor_tile_scene = value
		request_preview_refresh()

@export_range(0.02, 0.4, 0.01) var floor_tile_height: float = TILE_HEIGHT:
	set(value):
		floor_tile_height = value
		request_preview_refresh()

@export var show_grid_tiles: bool = true:
	set(value):
		show_grid_tiles = value
		request_preview_refresh()

@export var cat_world_y: float = 0.78:
	set(value):
		cat_world_y = value
		request_preview_refresh()

@export var obstacles_enabled: bool = false:
	set(value):
		obstacles_enabled = value
		request_preview_refresh()

# 장애물 에셋. 구멍이 `hole_scene` 을 쓰는 것과 같은 방식이며, 비어 있으면 아래에서 타일과
# 같은 모양의 덩어리를 만들어 놓는다. **잠긴 칸은 반드시 보여야 한다** — 안 보이면 플레이어가
# 못 움직이는 이유가 벽인지 버그인지 구분할 수 없다.
@export var obstacle_scene: PackedScene = preload("res://scenes/obstacle_tile_1x1.tscn"):
	set(value):
		obstacle_scene = value
		request_preview_refresh()

@export_range(0.1, 1.2, 0.01) var obstacle_fbx_height: float = 0.55:
	set(value):
		obstacle_fbx_height = value
		request_preview_refresh()

@export_group("Path Preview")
@export var path_preview_scene: PackedScene = PATH_PREVIEW_SCENE:
	set(value):
		path_preview_scene = value
		request_preview_refresh()

@export_range(0.02, 0.4, 0.01) var path_preview_height: float = 0.12:
	set(value):
		path_preview_height = value
		request_preview_refresh()

@export_color_no_alpha var path_preview_color: Color = Color(0.64, 0.79, 0.40, 1.0):
	set(value):
		path_preview_color = value
		request_preview_refresh()

# 탈출구 에셋. 구멍 칸마다 한 개씩 생성하고 색 짝 팔레트로 틴트한다.
@export var hole_scene: PackedScene = preload("res://scenes/cat_hole.tscn"):
	set(value):
		hole_scene = value
		request_preview_refresh()

@export_range(-0.4, 0.6, 0.01) var hole_visual_height: float = 0.0:
	set(value):
		hole_visual_height = value
		request_preview_refresh()

@export var show_hole_visuals: bool = true:
	set(value):
		show_hole_visuals = value
		request_preview_refresh()

# 이미 열린 씬에서도 Inspector 버튼으로 에디터용 보드를 즉시 다시 만든다.
@export_group("Visual Colors")
@export_color_no_alpha var board_visuals_color: Color = Color(0.83, 0.62, 0.42, 1.0):
	set(value):
		board_visuals_color = value
		request_preview_refresh()

@export_color_no_alpha var tile_primary_color: Color = Color(0.95, 0.77, 0.62, 1.0):
	set(value):
		tile_primary_color = value
		request_preview_refresh()

@export_color_no_alpha var tile_secondary_color: Color = Color(0.93, 0.72, 0.56, 1.0):
	set(value):
		tile_secondary_color = value
		request_preview_refresh()

# 잠긴 칸은 타일과 **한눈에 구분되어야** 한다. 타일과 비슷한 색으로 두면 덩어리를 그려도
# 플레이어에게는 그냥 타일로 보여서, 못 움직이는 이유가 벽인지 버그인지 알 수 없다.
@export_color_no_alpha var obstacle_primary_color: Color = Color(0.40, 0.32, 0.23, 1.0):
	set(value):
		obstacle_primary_color = value
		request_preview_refresh()

@export_color_no_alpha var obstacle_secondary_color: Color = Color(0.34, 0.27, 0.19, 1.0):
	set(value):
		obstacle_secondary_color = value
		request_preview_refresh()

@export_color_no_alpha var hole_rim_color: Color = Color(0.27, 0.33, 0.18, 1.0):
	set(value):
		hole_rim_color = value
		request_preview_refresh()

@export_color_no_alpha var hole_pit_color: Color = Color(0.06, 0.07, 0.05, 1.0):
	set(value):
		hole_pit_color = value
		request_preview_refresh()

# 색 페어 팔레트. 배열 인덱스가 곧 `color_id` 이며, 고양이와 구멍은 이 하나의 표에서
# 같은 색을 받는다. 짝 판정과 표시색이 갈라지지 않게 하려는 것이다.
@export var pair_colors: PackedColorArray = PackedColorArray([
	Color("#F39C6B"), Color("#6FA9E8"), Color("#75C978"), Color("#E888A9"),
	Color("#C795E8"), Color("#F2C94C"), Color("#5DC8C2"), Color("#F08B5B"),
	Color("#9FCB5A"), Color("#7795EA"), Color("#E979CB"), Color("#64B9E4"),
	Color("#E8A4D2"), Color("#B6A16D"), Color("#6CBF97"), Color("#DD7373"),
	Color("#A78BE3"), Color("#D6B85B"), Color("#5BB3A8"), Color("#E58FBA"),
]):
	set(value):
		pair_colors = value
		request_preview_refresh()

@export_tool_button("Refresh Board Preview", "Reload") var refresh_board_preview_action = refresh_board_preview

var _grid_state: Array = []
var _grid_refs: Array = []
var _cats: Array[CatEntity] = []
var _hole_cells: Array[Vector2i] = []
var _obstacle_cells: Array[Vector2i] = []
# _hole_cells 와 같은 순서의 색 인덱스. -1 은 아무 색이나 받는 와일드카드다.
var _hole_color_ids: Array[int] = []
var _hole_ice_covers: Array[bool] = []
var _preview_refresh_queued: bool = false

var _board_root: Node3D
var _tiles_root: Node3D
var _obstacles_root: Node3D
var _holes_root: Node3D
var _path_preview_root: Node3D
var _layout_cats_root: Node3D
var _layout_obstacles_root: Node3D
var _layout_holes_root: Node3D
var _highlight_root: Node3D
var _highlight_tiles: Array[MeshInstance3D] = []


func _ready() -> void:
	_setup_roots()
	if Engine.is_editor_hint():
		request_preview_refresh()
	else:
		_rebuild_from_scene_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_CHILD_ORDER_CHANGED and Engine.is_editor_hint():
		request_preview_refresh()


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


# 배치를 바꾼 직후 보드를 즉시 다시 만든다. `request_preview_refresh()` 는 다음 프레임으로
# 미루므로, 프레임을 기다릴 수 없는 맵 생성기와 검증 하네스는 이쪽을 쓴다.
func rebuild_now() -> void:
	_preview_refresh_queued = false
	_setup_roots()
	_rebuild_from_scene_layout()


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
	# 걸침을 포함한 점유다. 표시용과 판정용이 같은 집합이어야 한다.
	for cell in cat.get_occupied_cells():
		# 구멍 칸은 고양이가 덮어쓰지 않는다. 덮으면 구멍이 사라져 흡입 판정이 죽는다.
		if is_inside_grid(cell) and not is_hole(cell):
			_set_cell_state(cell, CellState.CAT)
			_set_cell_ref(cell, cat)
	_refresh_occupancy_highlight()
	_refresh_path_preview()


# 자기 자신을 뺀 차단 여부. 자기 몸 판정은 시간 전개가 필요해 CatEntity 가 따로 본다.
func is_cell_blocked_for(cat: CatEntity, cell: Vector2i) -> bool:
	if not is_inside_grid(cell):
		return true
	var state: int = _get_cell_state(cell)
	if state == CellState.OBSTACLE:
		return true
	# 구멍은 경로로 쓰지 않는다. 흡입은 인접 판정으로만 일어나므로 구멍 칸에
	# 직접 들어가는 이동은 애초에 계획되지 않아야 한다.
	if state == CellState.HOLE:
		return true
	return state == CellState.CAT and _get_cell_ref(cell) != cat


func _refresh_occupancy_highlight() -> void:
	if _highlight_tiles.is_empty():
		return
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var index: int = y * grid_size.x + x
			if index >= _highlight_tiles.size():
				continue
			var tile: MeshInstance3D = _highlight_tiles[index]
			# Keep occupancy data for gameplay, but do not tint tiles beneath cats.
			tile.visible = false


func _build_occupancy_highlight() -> void:
	_highlight_tiles.clear()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.34)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(tile_size - tile_gap, tile_size - tile_gap)
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var tile := MeshInstance3D.new()
			tile.name = "Highlight_%d_%d" % [x, y]
			tile.mesh = mesh
			tile.material_override = material
			tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tile.position = grid_to_world(Vector2i(x, y), TILE_HEIGHT + 0.01)
			tile.visible = false
			_highlight_root.add_child(tile)
			_highlight_tiles.append(tile)


func refresh_path_preview() -> void:
	_refresh_path_preview()


func _refresh_path_preview() -> void:
	if _path_preview_root == null:
		return
	_free_children(_path_preview_root)
	if path_preview_scene == null:
		return

	var seen := {}
	for cat in _cats:
		if cat == null or not is_instance_valid(cat) or not cat.has_method("get_preview_path_cells"):
			continue
		for cell_variant in cat.call("get_preview_path_cells"):
			var cell := cell_variant as Vector2i
			if not is_inside_grid(cell) or is_hole(cell) or seen.has(cell):
				continue
			seen[cell] = true
			var visual := path_preview_scene.instantiate() as Node3D
			if visual == null:
				continue
			visual.name = "Path_%d_%d" % [cell.x, cell.y]
			visual.position = grid_to_world(cell, TILE_HEIGHT)
			for property_info in visual.get_property_list():
				if property_info.get("name") == "cast_shadow":
					visual.set("cast_shadow", false)
					break
			if visual.has_method("apply_cell_style"):
				visual.call("apply_cell_style", cell, path_preview_color, path_preview_height)
			_path_preview_root.add_child(visual)


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
	_holes_root = _ensure_named_child(self, "HoleVisuals")
	_path_preview_root = _ensure_named_child(self, "PathPreviewVisuals")
	_highlight_root = _ensure_named_child(self, "OccupancyHighlights")
	_layout_cats_root = _ensure_named_child(self, "LayoutCats")
	_layout_obstacles_root = _ensure_named_child(self, "LayoutObstacles")
	_layout_holes_root = _ensure_named_child(self, "LayoutHoles")


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
	# 구멍 칸은 타일을 깔지 않으므로 타일보다 먼저 확정해야 한다.
	_sync_hole_layout()
	_build_board_base()
	_build_grid_tiles()
	_build_hole_visuals()
	_build_occupancy_highlight()
	_sync_obstacle_layout()
	_build_obstacle_visuals()
	_sync_cat_layout()
	_refresh_path_preview()
	_sync_hole_visual_styles()


func _clear_generated_nodes() -> void:
	_free_children(_board_root)
	# TileVisuals also holds manually placed scene decorations. Keep those
	# marked as persistent when the generated board tiles are rebuilt.
	_free_children(_tiles_root, "persistent_tile_visuals")
	_free_children(_obstacles_root)
	_free_children(_holes_root)
	_free_children(_path_preview_root)
	_free_children(_highlight_root)

	_highlight_tiles.clear()
	_hole_cells.clear()
	_hole_color_ids.clear()
	_hole_ice_covers.clear()
	_obstacle_cells.clear()
	_cats.clear()


# 생성 노드를 지운다. **`queue_free()` 만 부르면 안 된다** — 해제가 프레임 끝으로 미뤄지므로
# 같은 프레임에 보드를 다시 만들면 옛 노드가 자식으로 남아 개수가 두 배로 보인다.
# 트리에서 먼저 떼어 내야 `rebuild_now()` 직후의 조회가 맞는다.
func _free_children(root: Node3D, keep_group: String = "") -> void:
	for child in root.get_children():
		if keep_group != "" and child.is_in_group(keep_group):
			continue
		root.remove_child(child)
		child.queue_free()


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
		_make_board_material(board_size)
	)
	board.position = Vector3(0.0, -0.18 + board_visual_y_offset, 0.0)
	_board_root.add_child(board)


func _build_grid_tiles() -> void:
	if not show_grid_tiles:
		return

	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell: Vector2i = Vector2i(x, y)
			if is_hole(cell):
				continue
			if floor_tile_scene != null:
				var visual := floor_tile_scene.instantiate() as Node3D
				if visual != null:
					visual.name = "Tile_%d_%d" % [x, y]
					visual.position = grid_to_world(cell, 0.0)
					if visual.has_method("apply_cell_style"):
						visual.call("apply_cell_style", cell, _tile_color_for(cell), floor_tile_height)
					_tiles_root.add_child(visual)
					continue
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
	for child in _layout_obstacles_root.get_children():
		if child.get_script() != OBSTACLE_MARKER_SCRIPT:
			continue

		# Keep editor markers visible for layout and color editing even when
		# obstacles are disabled for gameplay.
		# 마커는 아무것도 그리지 않는다. 보이는 것은 아래 `_build_obstacle_visuals()` 가 만드는
		# 덩어리이며 에디터와 실행에서 같은 것이 보인다. 마커가 따로 상자를 그리면 그 위에
		# 정체불명의 반투명 사각형이 겹쳐 보인다(구멍 마커와 같은 이유다).
		child.call("refresh_preview")

		if not obstacles_enabled:
			continue

		for cell in child.call("get_cells"):
			if is_inside_grid(cell):
				_set_cell_state(cell, CellState.OBSTACLE)
				_obstacle_cells.append(cell)


func _sync_hole_layout() -> void:
	for child in _layout_holes_root.get_children():
		if child.get_script() != HOLE_MARKER_SCRIPT:
			continue

		# 마커는 그리는 것이 없다. 보이는 것은 아래에서 만드는 캣홀 비주얼뿐이다.
		child.call("refresh_editor_preview")

		var marker_grid_pos: Vector2i = child.get("grid_pos")
		if not is_inside_grid(marker_grid_pos) or _hole_cells.has(marker_grid_pos):
			continue

		_hole_cells.append(marker_grid_pos)
		_hole_color_ids.append(int(child.get("color_id")))
		_hole_ice_covers.append(bool(child.get("ice_cover")))
		_set_cell_state(marker_grid_pos, CellState.HOLE)


func _build_hole_visuals() -> void:
	if not show_hole_visuals or hole_scene == null:
		return

	var tile_side := maxf(tile_size - tile_gap, 0.01)
	for index in _hole_cells.size():
		var cell: Vector2i = _hole_cells[index]
		var color_id: int = _hole_color_ids[index]
		var visual := hole_scene.instantiate() as Node3D
		if visual == null:
			continue

		visual.name = "CatHole_%d_%d" % [cell.x, cell.y]
		# 구멍 칸에는 타일을 깔지 않으므로 보드 베이스 윗면(y=0)에 앉힌다.
		visual.position = grid_to_world(cell, hole_visual_height)
		_holes_root.add_child(visual)

		# 크기와 색은 노드가 트리에 들어간 뒤에 준다. 에셋이 자기 _ready 에서 원본
		# 재질을 먼저 깔기 때문에, 색 짝 틴트는 그 뒤에 덮어써야 남는다.
		visual.call("apply_cat_visual_style", _get_hole_cat_visual_style(color_id))
		visual.call("fit_to_tile", tile_side)
		visual.call(
			"apply_hole_colors",
			get_hole_rim_color(color_id),
			get_hole_pit_color(color_id)
		)
		if _hole_ice_covers[index]:
			var ice_cover := ICE_BLOCK_SCENE.instantiate() as Node3D
			if ice_cover != null:
				ice_cover.name = "IceCover"
				visual.add_child(ice_cover)
				# CatHole은 fit_to_tile()에서 원본 FBX 크기만큼 스케일된다. ice도 그
				# 자식이므로 그 스케일을 상쇄해야 obstacle_tile_1x1.fbx의 1.88폭이
				# 정확히 한 타일(기본 1.88)에 머문다.
				ice_cover.scale = Vector3.ONE / visual.scale
				ice_cover.position = Vector3(0.0, TILE_HEIGHT / visual.scale.y, 0.0)
				ice_cover.call("apply_cell_style", cell, Color.WHITE, obstacle_fbx_height)


# 잠긴 칸을 눈에 보이게 그린다. 에셋(`obstacle_scene`)이 있으면 그것을 붙이고, 없으면 타일과
# 같은 둥근 덩어리를 타일 위에 얹는다. 높이는 고양이(`cat_world_y`)보다 낮게 두어 고양이를
# 가리지 않는다.
func _build_obstacle_visuals() -> void:
	var block_side := maxf(tile_size - tile_gap, 0.01)
	for cell in _obstacle_cells:
		if obstacle_scene != null:
			var visual := obstacle_scene.instantiate() as Node3D
			if visual != null:
				visual.name = "Obstacle_%d_%d" % [cell.x, cell.y]
				visual.position = grid_to_world(cell, TILE_HEIGHT)
				if visual.has_method("apply_cell_style"):
					visual.call("apply_cell_style", cell, get_obstacle_color(cell), obstacle_fbx_height)
				_obstacles_root.add_child(visual)
				continue
		var block := _create_rounded_prism(
			"Obstacle_%d_%d" % [cell.x, cell.y],
			Vector3(block_side, obstacle_fbx_height, block_side),
			TILE_CORNER_RADIUS,
			_make_material(get_obstacle_color(cell))
		)
		block.position = grid_to_world(cell, TILE_HEIGHT + obstacle_fbx_height * 0.5)
		_obstacles_root.add_child(block)


func _get_hole_cat_visual_style(color_id: int) -> Dictionary:
	# A color_id identifies both the gameplay pair and its visual counterpart.
	# Read the editable layout node instead of generated runtime cats because
	# holes are built before _sync_cat_layout() initializes those runtime nodes.
	if color_id < 0:
		return {}
	for child in _layout_cats_root.get_children():
		# Inspector edits can briefly leave an @tool CatEntity as an editor
		# placeholder. It retains its script resource but cannot use script APIs.
		if child.get_script() != CAT_ENTITY_SCRIPT or not child.has_method("get_hole_visual_style"):
			continue
		var cat := child as CatEntity
		if cat != null and cat.color_id == color_id:
			return cat.get_hole_visual_style(get_pair_color(color_id))
	return {}


# Hole visuals are created before their movable-cat counterparts.  Run a
# second pass after the cats have rebuilt their shader materials so outline
# colour, width and top/bottom weighting are always copied from the matching
# cat rather than remaining on a creation-time fallback.
func _sync_hole_visual_styles() -> void:
	if _holes_root == null:
		return
	var visuals := _holes_root.get_children()
	for index in mini(visuals.size(), _hole_color_ids.size()):
		visuals[index].call("apply_cat_visual_style", _get_hole_cat_visual_style(_hole_color_ids[index]))


# Called directly by CatEntity after an Inspector shader edit. This keeps the
# matching CatHole outline in sync in the same editor update, without relying
# on a deferred board preview rebuild.
func sync_hole_visual_style_for_color(color_id: int) -> void:
	if _holes_root == null or color_id < 0:
		return
	var visuals := _holes_root.get_children()
	for index in mini(visuals.size(), _hole_color_ids.size()):
		if _hole_color_ids[index] == color_id:
			visuals[index].call("apply_cat_visual_style", _get_hole_cat_visual_style(color_id))


# Runs after the palette Inspector changes a shared shader control.  Editing a
# layout node updates the saved value, but an editor preview may still be using
# materials made before that value was applied.  Refresh the existing cats and
# holes directly instead of rebuilding the board (which reparses the Inspector
# while its slider is being dragged).
func refresh_shared_shader_preview() -> void:
	for child in _layout_cats_root.get_children():
		if child.get_script() != CAT_ENTITY_SCRIPT:
			continue
		if Engine.is_editor_hint():
			if child.has_method("refresh_editor_preview"):
				child.call("refresh_editor_preview")
		elif child.has_method("_apply_current_shader_parameters"):
			child.call("_apply_current_shader_parameters")
	_sync_hole_visual_styles()


func is_hole(cell: Vector2i) -> bool:
	return _hole_cells.has(cell)


func get_hole_cells() -> Array[Vector2i]:
	return _hole_cells


# 구멍의 색 인덱스. 구멍이 아니거나 와일드카드면 -1 이다.
func get_hole_color_id(cell: Vector2i) -> int:
	var index: int = _hole_cells.find(cell)
	if index < 0:
		return -1
	return _hole_color_ids[index]


# color_id → 실제 색. 팔레트를 벗어난 값과 와일드카드(-1)는 하양이다. 색이 곧 짝이므로
# 고양이와 구멍이 이 함수 하나만 쓰게 한다.
func get_pair_color(color_id: int) -> Color:
	if color_id < 0 or color_id >= pair_colors.size():
		return Color(1.0, 1.0, 1.0, 1.0)
	return pair_colors[color_id]


# 와일드카드 구멍은 색 없이 예전 톤을 그대로 쓴다.
func get_hole_rim_color(color_id: int) -> Color:
	if color_id < 0 or color_id >= pair_colors.size():
		return hole_rim_color
	return get_pair_color(color_id)


func get_hole_pit_color(color_id: int) -> Color:
	if color_id < 0 or color_id >= pair_colors.size():
		return hole_pit_color
	return get_pair_color(color_id).darkened(0.72)


# 색이 짝인지. 한쪽이 와일드카드(-1)면 아무 색과도 짝이 된다.
func color_ids_pair(cat_color_id: int, hole_color_id: int) -> bool:
	if cat_color_id < 0 or hole_color_id < 0:
		return true
	return cat_color_id == hole_color_id


# 셀에 인접(4방향)한 구멍. 없으면 null. 흡입 판정의 단일 기준이다.
# color_id 를 주면 색이 짝인 구멍만 걸린다. -1 은 색을 보지 않는다.
func adjacent_hole(cell: Vector2i, color_id: int = -1) -> Variant:
	for dir in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var neighbour: Vector2i = cell + dir
		if not is_hole(neighbour):
			continue
		if not color_ids_pair(color_id, get_hole_color_id(neighbour)):
			continue
		return neighbour
	return null


func _sync_cat_layout() -> void:
	for child in _layout_cats_root.get_children():
		if child.get_script() != CAT_ENTITY_SCRIPT:
			continue

		var cat := child as CatEntity
		if cat == null:
			continue
		if Engine.is_editor_hint():
			# Avoid property assignments and method calls until the @tool script is
			# available again after the Inspector has finished rebuilding it.
			if not child.has_method("refresh_editor_preview"):
				continue
			cat.level_manager = self
			cat.refresh_editor_preview()
		else:
			cat.initialize_runtime(self)

		if not is_inside_grid(cat.grid_pos):
			continue

		update_cat_occupancy(cat)
		_cats.append(cat)


func _make_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	return material


func _make_board_material(board_size: Vector3) -> StandardMaterial3D:
	var material := _make_material(board_visuals_color)
	if board_visual_texture != null:
		material.albedo_texture = board_visual_texture
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		material.texture_repeat = true
		material.uv1_scale = Vector3(
			maxf(board_size.x / tile_size, 0.01) * board_texture_tiling.x,
			maxf(board_size.z / tile_size, 0.01) * board_texture_tiling.y,
			1.0
		)
	return material


func _tile_color_for(cell: Vector2i) -> Color:
	if (cell.x + cell.y) % 2 == 0:
		return tile_primary_color
	return tile_secondary_color


func get_obstacle_color(cell: Vector2i) -> Color:
	if (cell.x + cell.y) % 2 == 0:
		return obstacle_primary_color
	return obstacle_secondary_color


func get_cats() -> Array[CatEntity]:
	return _cats


func board_point_to_grid_cell(board_point: Vector3) -> Variant:
	var grid_origin := grid_to_world(Vector2i.ZERO)
	return Vector2i(
		roundi((board_point.x - grid_origin.x) / tile_size),
		roundi((board_point.z - grid_origin.z) / tile_size)
	)


func screen_to_board_point(screen_pos: Vector2) -> Variant:
	return _screen_to_board_point(screen_pos)


func _screen_to_board_point(screen_pos: Vector2) -> Variant:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return null
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var plane := Plane(Vector3.UP, cat_world_y)
	return plane.intersects_ray(origin, direction)


func screen_to_grid_cell(screen_pos: Vector2) -> Variant:
	var hit: Variant = _screen_to_board_point(screen_pos)
	if hit == null:
		return null
	return board_point_to_grid_cell(hit as Vector3)


func _get_cell_state(cell: Vector2i) -> int:
	return _grid_state[cell.y][cell.x]


func _set_cell_state(cell: Vector2i, state: int) -> void:
	_grid_state[cell.y][cell.x] = state


func _get_cell_ref(cell: Vector2i) -> Variant:
	return _grid_refs[cell.y][cell.x]


func _set_cell_ref(cell: Vector2i, value: Variant) -> void:
	_grid_refs[cell.y][cell.x] = value
