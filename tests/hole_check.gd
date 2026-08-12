extends SceneTree

# 구멍 흡입 회귀 검사. 렌더가 없으므로 기하 수치로만 본다.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/hole_check.gd

var _scene: Node
var _frames := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_scene = (load("res://scenes/main_scene.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 10:
		return false
	var manager: LevelManager = _scene.get_node("LevelManager")
	_check_layout(manager)
	_check_runtime_outline_sync(manager)
	_check_not_a_path(manager)
	_check_no_trigger_when_far(manager)
	_check_lead_absorb(manager)
	_check_rear_absorb(manager)
	_check_color_pair(manager)
	_check_clears_level(manager)
	_report()
	return true


# 씬에 놓인 구멍이 정확히 한 칸이고, 타일이 그 자리에 깔리지 않았다.
func _check_layout(manager: LevelManager) -> void:
	var holes: Array[Vector2i] = manager.get_hole_cells()
	_expect(not holes.is_empty(), "씬에 구멍이 하나도 없다")
	if holes.is_empty():
		return
	var hole: Vector2i = holes[0]
	_expect(manager.is_hole(hole), "구멍 칸이 is_hole() 로 조회되지 않는다: %s" % [hole])
	_expect(
		manager.get_node("TileVisuals").get_node_or_null("Tile_%d_%d" % [hole.x, hole.y]) == null,
		"구멍 칸에 타일이 깔렸다: %s" % [hole]
	)
	_expect(
		manager.get_node("HoleVisuals").get_node_or_null("CatHole_%d_%d" % [hole.x, hole.y]) != null,
		"구멍 비주얼이 만들어지지 않았다: %s" % [hole]
	)
	# 인접 조회는 4방향만이다. 대각선은 걸리지 않는다.
	_expect(manager.adjacent_hole(hole + Vector2i.LEFT) == hole, "옆칸에서 구멍을 못 찾았다")
	_expect(manager.adjacent_hole(hole + Vector2i(1, 1)) == null, "대각선이 인접으로 걸렸다")
	print("[구멍] %s 한 칸, 타일 없음, 4방향 인접만 걸림" % [hole])


# 구멍은 경로로 쓰이지 않는다. 브릿지가 구멍을 지나가면 인접 판정 전에 밟게 된다.
func _check_runtime_outline_sync(manager: LevelManager) -> void:
	var cat := manager.get_node_or_null("LayoutCats/Cat_C0") as CatEntity
	var hole := manager.get_node_or_null("HoleVisuals/CatHole_0_0")
	_expect(cat != null and hole != null, "Runtime outline sync test nodes are missing")
	if cat == null or hole == null:
		return
	var expected := 0.031
	cat.outline_width = expected
	# Property setters defer material application; invoke the same live update
	# path once so this test covers the non-editor (runtime) branch.
	cat.call("_apply_current_shader_parameters")
	_expect(
		is_equal_approx(float(hole.call("get_applied_outline_width")), expected),
		"Runtime cat outline was not copied to the matching CatHole"
	)
	print("[runtime outline] CatHole received %.3f" % expected)


func _check_not_a_path(manager: LevelManager) -> void:
	var hole: Vector2i = manager.get_hole_cells()[0]
	var cat: CatEntity = _fresh_cat(manager, hole + Vector2i(0, 3))
	_expect(not cat.can_enter(hole), "구멍으로 들어갈 수 있다고 판정했다")
	cat.path_queue.clear()
	cat.request_path_to(hole)
	_expect(cat.path_queue.is_empty(), "구멍으로 가는 경로가 생겼다: %s" % [cat.path_queue])


# 두 칸 떨어져 있으면 아무 일도 없다. 인접한 순간에만 걸려야 한다.
func _check_no_trigger_when_far(manager: LevelManager) -> void:
	var hole: Vector2i = manager.get_hole_cells()[0]
	var cat: CatEntity = _fresh_cat(manager, hole + Vector2i(0, 3))
	cat.request_path_to(hole + Vector2i(0, 2))
	cat.advance(1.2 / cat.move_speed_cells)
	_expect(cat.body_cells[0] == hole + Vector2i(0, 2), "이동이 되지 않았다: %s" % [cat.body_cells])
	_expect(not cat.is_absorbing(), "두 칸 떨어졌는데 흡입이 시작됐다")


# 리드가 구멍 옆칸에 들어선 순간 흡입이 시작되고, 몸 전체가 구멍으로 들어가 사라진다.
func _check_lead_absorb(manager: LevelManager) -> void:
	var hole: Vector2i = manager.get_hole_cells()[0]
	var cat: CatEntity = _fresh_cat(manager, hole + Vector2i(0, 2))
	var length: int = cat.body_cells.size()

	cat.request_path_to(hole + Vector2i(0, 1))
	cat.advance(0.5 / cat.move_speed_cells)
	_expect(not cat.is_absorbing(), "전이 중에 흡입이 시작됐다")
	cat.advance(0.6 / cat.move_speed_cells)
	_expect(cat.is_absorbing(), "구멍 옆칸에 들어섰는데 흡입이 시작되지 않았다")
	_expect(cat._absorb_cell == hole, "흡입 대상 구멍이 다르다: %s" % [cat._absorb_cell])
	_expect(cat._absorb_from_lead, "리드가 닿았는데 후미쪽 흡입으로 잡혔다")

	# 흡입이 시작되면 점유를 즉시 놓는다.
	for cell in cat.body_cells:
		_expect(
			not manager.is_cell_blocked_for(null, cell) or manager.is_hole(cell),
			"흡입 중인 고양이가 %s 를 아직 막고 있다" % [cell]
		)
	# 조작을 받지 않는다.
	cat.request_path_to(hole + Vector2i(0, 3))
	_expect(cat.path_queue.is_empty(), "흡입 중에 이동 요청이 큐에 들어갔다")
	_expect(cat.body_cells.size() == length, "흡입이 몸 길이를 바꿨다: %d" % cat.body_cells.size())

	# 머리 본이 구멍 중심을 지나 아래로 내려간다.
	var hole_center: Vector3 = manager.grid_to_world(hole, manager.cat_world_y)
	var progressed := false
	var sank := false
	var elapsed := 0.0
	while cat.is_absorbing() and elapsed < 3.0:
		cat.advance(1.0 / 120.0)
		elapsed += 1.0 / 120.0
		if not cat.is_absorbing():
			break
		var head: Vector3 = _head_bone_world(cat)
		if Vector2(head.x - hole_center.x, head.z - hole_center.z).length() < 0.05:
			progressed = true
		if head.y < hole_center.y - 0.4:
			sank = true
	_expect(progressed, "머리가 구멍 중심 위를 지나가지 않았다")
	_expect(sank, "머리가 구멍 아래로 내려가지 않았다")
	_expect(not cat.is_absorbing(), "흡입이 끝나지 않았다 (%.2f초)" % elapsed)
	_expect(not manager.get_cats().has(cat), "흡입이 끝났는데 고양이가 목록에 남았다")
	print("[흡입] 리드가 %.3f초에 구멍 %s 로 사라졌다" % [elapsed, hole])


# 후진에서는 후미가 리드가 가지 않은 칸으로 나간다. 그때는 후미쪽이 먼저 닿는다.
func _check_rear_absorb(manager: LevelManager) -> void:
	var hole: Vector2i = manager.get_hole_cells()[0]
	# 리드는 구멍에서 먼 쪽에 두고, 후미가 구멍 쪽을 향하게 세운다.
	var cat: CatEntity = _fresh_cat(manager, hole + Vector2i(0, 5), "down")
	var rear_before: Vector2i = cat.body_cells[cat.body_cells.size() - 1]
	_expect(rear_before == hole + Vector2i(0, 2), "후진 시작 자세가 기대와 다르다: %s" % [cat.body_cells])
	_expect(not cat.is_absorbing(), "시작 자세에서 이미 흡입됐다: %s" % [cat.body_cells])

	# 손가락으로 자기 몸을 가리키면 후진이다. 후미가 구멍 옆칸으로 밀려 나간다.
	cat.request_path_to(cat.body_cells[1])
	cat.advance(1.2 / cat.move_speed_cells)
	_expect(
		cat.body_cells[cat.body_cells.size() - 1] == hole + Vector2i(0, 1),
		"후미가 구멍 옆칸으로 밀리지 않았다: %s" % [cat.body_cells]
	)
	_expect(cat.is_absorbing(), "후미가 구멍 옆칸에 닿았는데 흡입이 시작되지 않았다")
	_expect(not cat._absorb_from_lead, "후미가 닿았는데 리드쪽 흡입으로 잡혔다")
	_expect(cat._absorb_cell == hole, "흡입 대상 구멍이 다르다: %s" % [cat._absorb_cell])

	# 후미쪽으로 들어가도 몸 전체가 사라진다.
	var hole_center: Vector3 = manager.grid_to_world(hole, manager.cat_world_y)
	var tail_sank := false
	var elapsed := 0.0
	while cat.is_absorbing() and elapsed < 3.0:
		cat.advance(1.0 / 120.0)
		elapsed += 1.0 / 120.0
		if cat.is_absorbing() and _tail_bone_world(cat).y < hole_center.y - 0.4:
			tail_sank = true
	_expect(tail_sank, "꼬리 본이 구멍 아래로 내려가지 않았다")
	_expect(not cat.is_absorbing(), "후미쪽 흡입이 끝나지 않았다 (%.2f초)" % elapsed)
	print("[흡입] 후미 %s 가 구멍 %s 로 %.3f초에 사라졌다" % [rear_before, hole, elapsed])


# 색이 짝이 아니면 옆칸에 들어서도 빠지지 않는다. 짝이면 같은 자리에서 빠진다.
func _check_color_pair(manager: LevelManager) -> void:
	var hole: Vector2i = manager.get_hole_cells()[0]
	var hole_color: int = manager.get_hole_color_id(hole)
	_expect(hole_color >= 0, "구멍에 색이 지정되지 않았다: %s" % [hole])
	var other_color: int = hole_color + 1

	_expect(
		manager.adjacent_hole(hole + Vector2i.LEFT, other_color) == null,
		"색이 다른데 인접 구멍으로 걸렸다"
	)
	_expect(
		manager.adjacent_hole(hole + Vector2i.LEFT, hole_color) == hole,
		"색이 같은데 인접 구멍을 못 찾았다"
	)
	_expect(
		manager.adjacent_hole(hole + Vector2i.LEFT, -1) == hole,
		"와일드카드가 구멍을 못 찾았다"
	)

	var mismatched: CatEntity = _fresh_cat(manager, hole + Vector2i(0, 2))
	mismatched.color_id = other_color
	mismatched.request_path_to(hole + Vector2i(0, 1))
	mismatched.advance(1.2 / mismatched.move_speed_cells)
	_expect(
		mismatched.body_cells[0] == hole + Vector2i(0, 1),
		"색이 다른 고양이가 구멍 옆칸으로 못 갔다: %s" % [mismatched.body_cells]
	)
	_expect(not mismatched.is_absorbing(), "색이 다른데 흡입이 시작됐다")

	var matched: CatEntity = _fresh_cat(manager, hole + Vector2i(0, 2))
	matched.color_id = hole_color
	matched.request_path_to(hole + Vector2i(0, 1))
	matched.advance(1.2 / matched.move_speed_cells)
	_expect(matched.is_absorbing(), "색이 같은데 흡입이 시작되지 않았다")
	_drain(matched)
	print("[색] 구멍 %s(색 %d) 는 같은 색 고양이만 받는다" % [hole, hole_color])


# 마지막 고양이가 흡입되면 클리어 신호가 나온다. 탈출과 같은 경로를 쓴다.
func _check_clears_level(manager: LevelManager) -> void:
	for cat in manager.get_cats().duplicate():
		_drain(cat)
	var cleared := [false]
	manager.level_cleared.connect(func(): cleared[0] = true)
	var hole: Vector2i = manager.get_hole_cells()[0]
	var last: CatEntity = _fresh_cat(manager, hole + Vector2i(0, 2))
	last.request_path_to(hole + Vector2i(0, 1))
	last.advance(1.2 / last.move_speed_cells)
	_expect(last.is_absorbing(), "마지막 고양이가 흡입되지 않았다")
	_drain(last)
	_expect(cleared[0], "마지막 고양이가 사라졌는데 클리어 신호가 없다")
	print("[클리어] 마지막 고양이 흡입으로 level_cleared 발생")


# 검사용 고양이를 구멍에서 떨어진 자리에 새로 만든다. 기존 고양이는 정리한다.
func _fresh_cat(manager: LevelManager, cell: Vector2i, facing := "up") -> CatEntity:
	for existing in manager.get_cats().duplicate():
		manager.release_cat_cell(existing)
		manager._cats.erase(existing)
		existing.get_parent().remove_child(existing)
		existing.queue_free()

	var cat := CatEntity.new()
	cat.set_script(load("res://scripts/cat_entity.gd"))
	cat.facing_name = facing
	cat.grid_pos = cell
	cat.initial_length = 4
	manager.get_node("LayoutCats").add_child(cat)
	cat.initialize_runtime(manager)
	manager.update_cat_occupancy(cat)
	manager._cats.append(cat)
	cat.advance(0.0)
	return cat


func _drain(cat: CatEntity) -> void:
	var elapsed := 0.0
	while is_instance_valid(cat) and cat.is_absorbing() and elapsed < 3.0:
		cat.advance(1.0 / 120.0)
		elapsed += 1.0 / 120.0


func _head_bone_world(cat: CatEntity) -> Vector3:
	return _bone_world(cat, cat._bone_chain[0])


func _tail_bone_world(cat: CatEntity) -> Vector3:
	return _bone_world(cat, cat._bone_chain[cat._bone_chain.size() - 1])


func _bone_world(cat: CatEntity, bone: int) -> Vector3:
	var skeleton: Skeleton3D = cat._skeleton
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("HOLE CHECK: PASS")
		return
	print("HOLE CHECK: FAIL (%d)" % _failures.size())
	for failure in _failures:
		print("  - ", failure)
