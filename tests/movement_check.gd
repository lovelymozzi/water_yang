extends SceneTree

# 이동 스펙(1_움직임고찰.md) 회귀 검사. 렌더가 없으므로 기하 수치로만 본다.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/movement_check.gd

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
	var cat: CatEntity = manager.get_cats()[0]
	_check_rig(cat)
	_check_bone_placement(cat, "정지")
	_check_trace(manager, cat)
	_check_bridge(manager, cat)
	_check_self_block(cat)
	_check_movement(manager, cat)
	_check_lead_flip(manager, cat)
	_check_corner(cat)
	_check_drag(manager, cat)
	_check_detour(manager, cat)
	_check_ear_pose_survives(cat)
	_check_footprint_fill(manager, cat)
	_report()
	return true


# 스펙 6절. 코너를 낀 자세에서도 모든 본이 셀 중심 폴리라인 위에 있어야 한다.
func _check_corner(cat: CatEntity) -> void:
	var turn := Vector2i(cat.facing_dir.y, cat.facing_dir.x)
	if turn == Vector2i.ZERO:
		turn = Vector2i.RIGHT
	cat.path_queue.clear()
	cat.request_path_to(cat.body_cells[0] + turn)
	_expect(cat.path_queue.size() == 1, "코너 요청이 큐 1개가 아니다: %d" % cat.path_queue.size())

	cat.advance(0.5 / cat.move_speed_cells)
	_check_bone_placement(cat, "코너전이중")
	cat.advance(0.6 / cat.move_speed_cells)
	_expect(
		cat.body_cells[0] != cat.body_cells[1] and (cat.body_cells[0] - cat.body_cells[1]) == turn,
		"코너 이동 결과가 기대와 다르다: %s" % [cat.body_cells]
	)
	_check_bone_placement(cat, "코너후")


# 스펙 2절. 넉넉한 그랩, 터치 유지, 강제 릴리즈.
func _check_drag(manager: LevelManager, cat: CatEntity) -> void:
	var controller: Node = _scene.get_node("DragController")
	var camera: Camera3D = _scene.get_viewport().get_camera_3d()
	if camera == null:
		_expect(false, "카메라를 찾지 못했다")
		return

	var lead: Vector2i = cat.get_lead_cell()
	var lead_world: Vector3 = manager.grid_to_world(lead, manager.cat_world_y)
	# 끝 셀 중심에서 1.1칸 빗겨 눌러도 잡혀야 한다.
	var offset_world: Vector3 = lead_world + Vector3(0.0, 0.0, -1.1 * manager.tile_size)
	_send_touch(controller, camera.unproject_position(offset_world), true)
	_expect(controller._cat == cat, "빗겨 누른 그랩이 실패했다")

	# 잡고 있는 동안 다른 끝을 눌러도 리드가 넘어가지 않는다.
	var other_world: Vector3 = manager.grid_to_world(cat.body_cells[cat.body_cells.size() - 1], manager.cat_world_y)
	var lead_before: bool = cat._lead_is_tail
	_send_touch(controller, camera.unproject_position(other_world), true)
	_expect(cat._lead_is_tail == lead_before, "드래그 도중 리드가 반대쪽으로 넘어갔다")

	# 보드 밖으로 계속 끌면 별도 알림 없이 터치가 끝난다.
	var outside: Vector3 = manager.grid_to_world(Vector2i(lead.x, lead.y), manager.cat_world_y)
	outside.z -= manager.tile_size * (lead.y + 4)
	_send_drag(controller, camera.unproject_position(outside))
	controller._process(0.016)
	_expect(not controller._has_pointer, "막힌 채 멀어졌는데 터치가 끝나지 않았다")


# 스펙 3절. 손가락이 벽을 통과해도 옆이 열려 있으면 우회하고, 벽을 뚫지는 않는다.
func _check_detour(manager: LevelManager, cat: CatEntity) -> void:
	cat.grid_pos = Vector2i(1, 4)
	manager.update_cat_occupancy(cat)
	var wall := Vector2i(1, 3)
	manager._set_cell_state(wall, LevelManager.CellState.OBSTACLE)

	cat.path_queue.clear()
	cat.request_path_to(Vector2i(1, 2))
	_expect(not cat.path_queue.is_empty(), "벽 옆이 열려 있는데 우회하지 못했다")
	_expect(not cat.path_queue.has(wall), "우회 경로가 벽을 통과했다: %s" % [cat.path_queue])
	_expect(cat.path_queue.back() == Vector2i(1, 2), "우회 경로가 목표에 닿지 않았다: %s" % [cat.path_queue])
	var previous: Vector2i = cat.body_cells[0]
	for cell in cat.path_queue:
		var step: Vector2i = cell - previous
		_expect(absi(step.x) + absi(step.y) == 1, "우회 경로에 비인접 점프가 있다: %s" % [cat.path_queue])
		previous = cell
	print("[우회] 벽 %s 를 %d칸으로 돌았다: %s" % [wall, cat.path_queue.size(), cat.path_queue])

	# 벽 뒤가 완전히 막히면 아무것도 넣지 않고 막힘 표시가 선다.
	cat.path_queue.clear()
	for cell in [Vector2i(0, 4), Vector2i(2, 4), Vector2i(0, 3), Vector2i(2, 3)]:
		manager._set_cell_state(cell, LevelManager.CellState.OBSTACLE)
	cat.request_path_to(Vector2i(1, 2))
	_expect(cat.path_queue.is_empty(), "완전히 막혔는데 경로가 생겼다: %s" % [cat.path_queue])
	_expect(cat.is_blocked(), "완전히 막혔는데 막힘 표시가 서지 않았다")
	_expect(not cat.can_enter(wall), "벽으로 들어갈 수 있다고 판정했다")


func _send_touch(controller: Node, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = position
	event.pressed = pressed
	controller._unhandled_input(event)


func _send_drag(controller: Node, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = position
	controller._unhandled_input(event)


func _check_rig(cat: CatEntity) -> void:
	var chain: Array = cat._bone_chain
	_expect(chain.size() > 2, "본 체인이 비어 있다 (size=%d)" % chain.size())
	var skeleton: Skeleton3D = cat._skeleton
	if chain.is_empty() or skeleton == null:
		return
	_expect(
		skeleton.get_bone_name(chain[0]) == "Bone002",
		"체인 시작이 Bone002 가 아니다: %s" % skeleton.get_bone_name(chain[0])
	)
	_expect(
		skeleton.get_bone_name(chain[chain.size() - 1]) == "Bone022",
		"체인 끝이 Bone022 가 아니다: %s" % skeleton.get_bone_name(chain[chain.size() - 1])
	)


# 스펙 6절. 본은 셀 중심 폴리라인 위에만 놓이고, 양 끝 본은 끝 셀 중심에 정확히 온다.
func _check_bone_placement(cat: CatEntity, label: String) -> void:
	var skeleton: Skeleton3D = cat._skeleton
	if skeleton == null or cat._bone_chain.is_empty():
		return
	var polyline: PackedVector3Array = cat._body_polyline()
	var manager: LevelManager = cat.level_manager
	var head_bone: int = cat._bone_chain[0]
	var tail_bone: int = cat._bone_chain[cat._bone_chain.size() - 1]
	var head_world: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(head_bone).origin
	var tail_world: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(tail_bone).origin

	var model_head: Vector3 = polyline[polyline.size() - 1] if cat._lead_is_tail else polyline[0]
	var model_tail: Vector3 = polyline[0] if cat._lead_is_tail else polyline[polyline.size() - 1]
	_expect(
		head_world.distance_to(model_head) < 0.02,
		"%s: 머리 본이 끝점에서 %.4f 벗어났다" % [label, head_world.distance_to(model_head)]
	)
	_expect(
		tail_world.distance_to(model_tail) < 0.02,
		"%s: 꼬리 본이 끝점에서 %.4f 벗어났다" % [label, tail_world.distance_to(model_tail)]
	)

	# 모든 체인 본이 폴리라인 위에 있어야 한다. 그리드 중앙만 관통한다는 규칙의 계측이다.
	var worst := 0.0
	for bone_index in cat._bone_chain:
		var world: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bone_index).origin
		worst = maxf(worst, _distance_to_polyline(world, polyline))
	_expect(worst < 0.02, "%s: 본이 폴리라인에서 최대 %.4f 벗어났다" % [label, worst])
	print("[%s] 끝점 오차 머리=%.5f 꼬리=%.5f, 폴리라인 최대 이탈=%.5f" % [
		label, head_world.distance_to(model_head), tail_world.distance_to(model_tail), worst
	])


# 스펙 3절의 핵심. 손가락이 고양이보다 빨라도 그린 궤적을 그대로 지연 추종하며,
# 지그재그를 직선으로 펴는 지름길이 생기지 않는다.
func _check_trace(manager: LevelManager, cat: CatEntity) -> void:
	cat.grid_pos = Vector2i(3, 4)
	manager.update_cat_occupancy(cat)
	var traced: Array[Vector2i] = [Vector2i(3, 3), Vector2i(2, 3), Vector2i(2, 2), Vector2i(3, 2)]
	_expect(traced.size() <= cat.path_queue_max, "궤적이 큐 상한보다 길다")

	# 손가락이 먼저 다 지나간다. 고양이는 아직 한 칸도 움직이지 않은 상태다.
	for cell in traced:
		cat.request_path_to(cell)
	_expect(cat.path_queue == traced, "궤적이 큐에 그대로 담기지 않았다: %s" % [cat.path_queue])

	# 손을 뗀 뒤 잔여 경로를 완주한다. 지나간 리드 셀 순서가 궤적과 같아야 한다.
	var visited: Array[Vector2i] = []
	var elapsed := 0.0
	var previous: Vector2i = cat.body_cells[0]
	while not (cat.path_queue.is_empty() and not cat._is_moving) and elapsed < 2.0:
		cat.advance(1.0 / 120.0)
		elapsed += 1.0 / 120.0
		if cat.body_cells[0] != previous:
			previous = cat.body_cells[0]
			visited.append(previous)
	_expect(visited == traced, "완주 경로가 궤적과 다르다: %s" % [visited])
	_expect(elapsed <= 0.6, "완주가 0.5초를 크게 넘었다: %.3f초" % elapsed)
	print("[추종] 궤적 %d칸 완주 %.3f초, 경로 일치=%s" % [traced.size(), elapsed, visited == traced])


# 스펙 3절. 벽을 가로지르는 목표는 브릿지로 우회하고, 지름길은 생기지 않는다.
func _check_bridge(manager: LevelManager, cat: CatEntity) -> void:
	cat.grid_pos = Vector2i(1, 4)
	manager.update_cat_occupancy(cat)
	var start: Array[Vector2i] = cat.body_cells.duplicate()
	cat.path_queue.clear()
	var target: Vector2i = start[0] + Vector2i(2, 0)
	cat.request_path_to(target)
	_expect(cat.path_queue.size() == 2, "브릿지 길이가 2가 아니다: %d" % cat.path_queue.size())
	if cat.path_queue.size() == 2:
		_expect(
			cat.path_queue[0] == start[0] + Vector2i(1, 0) and cat.path_queue[1] == target,
			"브릿지 경로가 인접 연쇄가 아니다: %s" % [cat.path_queue]
		)

	# 큐 상한을 넘는 목표는 아무것도 넣지 않는다.
	cat.path_queue.clear()
	var far: Vector2i = start[0] + Vector2i(cat.path_queue_max + 1, 0)
	_expect(manager.is_inside_grid(far), "테스트 목표가 보드 밖이다: %s" % [far])
	cat.request_path_to(far)
	_expect(cat.path_queue.is_empty(), "상한 초과 목표가 큐에 들어갔다: %s" % [cat.path_queue])
	_expect(cat.is_blocked(), "상한 초과인데 막힘 표시가 서지 않았다")

	# 보드 밖도 닿을 수 없는 상태로 본다. 강제 릴리즈가 걸려야 하기 때문이다.
	cat.path_queue.clear()
	cat.request_path_to(Vector2i(-3, start[0].y))
	_expect(cat.path_queue.is_empty(), "보드 밖 목표가 큐에 들어갔다: %s" % [cat.path_queue])
	_expect(cat.is_blocked(), "보드 밖인데 막힘 표시가 서지 않았다")
	cat.path_queue.clear()


# 스펙 4절. 자기 몸은 뒤끝 칸까지 막힌다. 대기 후 통과 같은 것은 없다.
func _check_self_block(cat: CatEntity) -> void:
	for index in range(1, cat.body_cells.size()):
		_expect(
			not cat.can_enter(cat.body_cells[index]),
			"자기 몸 %s 로 들어갈 수 있다고 판정했다" % [cat.body_cells[index]]
		)


# 스펙 4절. 한 스텝은 정확히 한 칸이고 전이 중 점유는 한 칸 늘어난다.
func _check_movement(manager: LevelManager, cat: CatEntity) -> void:
	var before: Array[Vector2i] = cat.body_cells.duplicate()
	var length := before.size()
	cat.path_queue.clear()
	cat.request_path_to(before[0] + cat.facing_dir)
	_expect(cat.path_queue.size() == 1, "한 칸 요청이 큐 1개가 아니다: %d" % cat.path_queue.size())

	cat.advance(0.5 / cat.move_speed_cells)
	_expect(cat._is_moving, "전이가 시작되지 않았다")
	_expect(
		cat.get_occupied_cells().size() == length + 1,
		"전이 중 점유가 %d 칸이다 (기대 %d)" % [cat.get_occupied_cells().size(), length + 1]
	)
	_check_bone_placement(cat, "전이중")

	cat.advance(0.6 / cat.move_speed_cells)
	_expect(not cat._is_moving, "전이가 끝나지 않았다")
	_expect(cat.body_cells.size() == length, "몸 길이가 변했다: %d" % cat.body_cells.size())
	_expect(
		cat.body_cells[0] == before[0] + cat.facing_dir,
		"한 스텝에 한 칸을 넘게 이동했다: %s -> %s" % [before[0], cat.body_cells[0]]
	)
	_expect(
		cat.get_occupied_cells().size() == length,
		"정지 상태 점유가 %d 칸이다" % cat.get_occupied_cells().size()
	)
	_check_bone_placement(cat, "이동후")


# 스펙 2절. 반대쪽 끝을 잡으면 리드가 넘어가고, 모델 머리는 반대편 끝점에 놓인다.
func _check_lead_flip(manager: LevelManager, cat: CatEntity) -> void:
	var before: Array[Vector2i] = cat.body_cells.duplicate()
	cat.begin_drag(before[before.size() - 1])
	_expect(cat._lead_is_tail, "리드가 반대쪽으로 넘어가지 않았다")
	_expect(cat.body_cells[0] == before[before.size() - 1], "레일이 뒤집히지 않았다")
	cat.advance(0.0)
	_check_bone_placement(cat, "리드반전")

	var lead: Vector2i = cat.body_cells[0]
	cat.request_path_to(lead + cat.facing_dir)
	cat.advance(1.2 / cat.move_speed_cells)
	_expect(
		cat.body_cells[0] == lead + cat.facing_dir,
		"반전 후 이동이 안 됐다: %s" % [cat.body_cells[0]]
	)
	_check_bone_placement(cat, "반전이동후")


# 본 포즈 계산이 체인 밖 본을 rest 로 덮으면 귀 모션이 매 프레임 지워진다.
func _check_ear_pose_survives(cat: CatEntity) -> void:
	var skeleton: Skeleton3D = cat._skeleton
	var ear: int = skeleton.find_bone("Bone032")
	_expect(ear >= 0, "귀 본 Bone032 를 찾지 못했다")
	if ear < 0:
		return
	cat._apply_ear_twitch_pose(1.0, 0)
	var twitched: Quaternion = skeleton.get_bone_pose_rotation(ear)
	# 이동 포즈를 한 번 돌린 뒤에도 귀 포즈가 남아 있어야 한다.
	cat.advance(0.0)
	var after: Quaternion = skeleton.get_bone_pose_rotation(ear)
	_expect(
		after.is_equal_approx(twitched),
		"이동 포즈가 귀 포즈를 덮었다: %s -> %s" % [twitched, after]
	)
	cat._apply_ear_twitch_pose(0.0, 0)
	print("[귀] 이동 포즈 적용 후에도 귀 포즈 유지됨")


# 스킨된 메시가 발자국을 정확히 채우는지. 정점 실측은 tests/measure_extent.gd 가 하고,
# 여기서는 그 근거인 오버행 보정값과 양끝 본이 자기 셀 안에 남는지를 지킨다.
func _check_footprint_fill(manager: LevelManager, cat: CatEntity) -> void:
	cat.grid_pos = Vector2i(1, 4)
	manager.update_cat_occupancy(cat)
	cat.advance(0.0)

	var tile: float = manager.tile_size
	var half: float = tile * 0.5
	_expect(cat._head_mesh_overhang > 0.0, "머리쪽 메시 오버행을 재지 못했다")
	_expect(cat._tail_mesh_overhang > 0.0, "꼬리쪽 메시 오버행을 재지 못했다")

	# 체인 길이 = 발자국 - 앞뒤 오버행. 이래야 메시 양끝이 발자국 양끝에 맞는다.
	var polyline: PackedVector3Array = cat._body_polyline()
	var total := 0.0
	for index in range(1, polyline.size()):
		total += polyline[index - 1].distance_to(polyline[index])
	_expect(
		absf(total - cat._target_chain_world_length()) < 0.001,
		"폴리라인 길이 %.4f 가 목표 체인 길이 %.4f 와 다르다" % [total, cat._target_chain_world_length()]
	)
	# 메시 끝이 발자국 안쪽으로 얼마나 들어오는지. 요청한 여백 근처여야 한다.
	var model_scale: float = cat._grid_fitted_model_scale()
	var wanted: float = cat.footprint_margin_cells * tile
	for side in [
		[cat._head_mesh_overhang, "머리"], [cat._tail_mesh_overhang, "꼬리"]
	]:
		var gap: float = half - (cat._end_extension(side[0]) + side[0] * model_scale)
		_expect(gap > 0.0, "%s쪽 여백이 없다: %.4f" % [side[1], gap])
		_expect(
			absf(gap - wanted) < 0.03 * tile,
			"%s쪽 여백 %.3f칸이 목표 %.2f칸과 다르다" % [side[1], gap / tile, cat.footprint_margin_cells]
		)

	# 양끝 본은 자기 끝 셀을 벗어나지 않는다. 정지 중에 옆 칸을 침범하면 점유가 거짓이 된다.
	var lead_center: Vector3 = manager.grid_to_world(cat.body_cells[0], manager.cat_world_y)
	var far_center: Vector3 = manager.grid_to_world(
		cat.body_cells[cat.body_cells.size() - 1], manager.cat_world_y
	)
	_expect(
		polyline[0].distance_to(lead_center) < half,
		"리드쪽 끝점이 자기 셀을 벗어났다: %.4f >= %.4f" % [polyline[0].distance_to(lead_center), half]
	)
	var far_point: Vector3 = polyline[polyline.size() - 1]
	_expect(
		far_point.distance_to(far_center) < half,
		"반대쪽 끝점이 자기 셀을 벗어났다: %.4f >= %.4f" % [far_point.distance_to(far_center), half]
	)
	print("[발자국] %d칸=%.2f, 체인=%.3f, 여백 %.2f칸씩, 양끝 셀 이탈 없음" % [
		cat.body_cells.size(), float(cat.body_cells.size()) * tile, total, cat.footprint_margin_cells
	])


func _distance_to_polyline(point: Vector3, polyline: PackedVector3Array) -> float:
	var best := INF
	for index in range(1, polyline.size()):
		var a: Vector3 = polyline[index - 1]
		var b: Vector3 = polyline[index]
		var span: Vector3 = b - a
		var length_squared: float = span.length_squared()
		var closest: Vector3 = a
		if length_squared > 0.000001:
			closest = a + span * clampf((point - a).dot(span) / length_squared, 0.0, 1.0)
		best = minf(best, point.distance_to(closest))
	return best


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("MOVEMENT CHECK: PASS")
		return
	print("MOVEMENT CHECK: FAIL (%d)" % _failures.size())
	for failure in _failures:
		print("  - ", failure)
