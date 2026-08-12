extends SceneTree

# 길이 신축(중간복제) 회귀 검사.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/length_check.gd
#
# 길이 증가는 잡아늘리기가 아니라 본+링 복제다(`CatMiddleDuplicator`). 여기서 지키는 것:
#   1. 잔여 신축 배율이 1±15% 안 — 복제가 증가분을 흡수하고 배율은 끝수만 다듬는다.
#      배율이 커지면 잡아늘리기로 퇴행한 것이다.
#   2. 몸이 자기 셀을 전부 덮는다 — 코너가 잘리면 코너 셀 중심 근처에 정점이 없다.
#      길이 8 기준으로 복제 전에는 이 값이 0.45타일까지 벌어졌다.
#   3. 본이 폴리라인 위에 있다(양끝 오버행 내밀기 제외).
#   4. 체인 본의 포즈 스케일 (1,1,1) — 비균일 본 스케일은 전단을 만든다.
#
# 렌더 확인은 tests/capture_length.gd (헤드리스 불가).

const COVERAGE_LIMIT_TILES := 0.15
const SCALE_MIN := 0.85
const SCALE_MAX := 1.15
# 길이 3 은 복제가 없는 압축 상태라 배율 하한만 다르다.
const SCALE_MIN_SHORTEST := 0.8

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
	_isolate_board(manager)

	# L자 몸: 코너 하나가 늘어나는 구간 한가운데 떨어진다.
	for length in [3, 4, 6, 8, 10, 12]:
		var half: int = maxi(length / 2, 2)
		var body: Array[Vector2i] = []
		for index in range(half):
			body.append(Vector2i(5, 1 + index))
		for index in range(1, length - half + 1):
			body.append(Vector2i(5 - index, half))
		_check_body(manager, body, "L자 길이 %d" % length, length)

	# S자 길이 12: 코너 두 개.
	var snake: Array[Vector2i] = []
	for index in 4:
		snake.append(Vector2i(1, 1 + index))
	for index in 2:
		snake.append(Vector2i(2 + index, 4))
	for index in 3:
		snake.append(Vector2i(3, 5 + index))
	for index in 3:
		snake.append(Vector2i(4 + index, 7))
	_check_body(manager, snake, "S자 길이 12", 12)

	_report()
	return true


func _check_body(
	manager: LevelManager, body: Array[Vector2i], label: String, length: int
) -> void:
	var cat := CatEntity.new()
	cat.set_script(load("res://scripts/cat_entity.gd"))
	cat.initial_body_cells = body
	manager.get_node("LayoutCats").add_child(cat)
	cat.initialize_runtime(manager)
	cat.advance(0.0)

	var tile: float = manager.tile_size
	var scale: float = cat._baseline_stretch_scale()
	var scale_min: float = SCALE_MIN_SHORTEST if length <= 3 else SCALE_MIN
	_expect(
		scale >= scale_min and scale <= SCALE_MAX,
		"%s: 잔여 배율이 %.3f 다 (%.2f~%.2f 밖, 잡아늘리기로 퇴행)" % [label, scale, scale_min, SCALE_MAX]
	)
	if length >= 5:
		_expect(
			not cat._inserted_mid_bones.is_empty(),
			"%s: 중간복제 본이 하나도 없다" % label
		)

	# 본 포즈 스케일.
	for bone in cat._bone_chain:
		var bone_scale: Vector3 = cat._skeleton.get_bone_pose_scale(bone)
		if (bone_scale - Vector3.ONE).length() > 0.001:
			_expect(false, "%s: %s 포즈 스케일이 %s 다" % [
				label, cat._skeleton.get_bone_name(bone), bone_scale
			])
			break

	# 본 → 폴리라인 이탈. 셀 중심 경로가 아니라 실제 포즈 폴리라인(`_body_polyline()`)에
	# 대해 잰다. 폴리라인은 양끝을 메시 오버행만큼 내밀어 두므로 끝 본들이 셀 중심 경로
	# 밖에 있는 것은 정상이다.
	var polyline: PackedVector3Array = cat._body_polyline()
	var worst_bone := 0.0
	for chain_index in cat._bone_chain.size():
		var bone: int = cat._bone_chain[chain_index]
		var world: Vector3 = (
			cat._skeleton.global_transform
			* cat._skeleton.get_bone_global_pose(bone).origin
		)
		worst_bone = maxf(worst_bone, _distance_to_polyline(polyline, world) / tile)
	_expect(
		worst_bone < 0.05,
		"%s: 본이 폴리라인에서 %.3f타일 벗어났다" % [label, worst_bone]
	)

	# 셀 커버리지. 스킨 정점을 CPU 로 옮겨 각 몸 셀 중심의 최근접 정점 거리를 잰다.
	var coverage: Dictionary = _cell_coverage(manager, cat, body)
	for cell in body:
		var gap: float = float(coverage[cell])
		_expect(
			gap < COVERAGE_LIMIT_TILES,
			"%s: 셀 %s 가 비었다 (최근접 정점 %.3f타일, 코너 잘림)" % [label, cell, gap]
		)

	print("[길이] %s: 배율 %.3f, 삽입본 %d, 본이탈 %.3f, 최대셀공백 %.3f" % [
		label, scale, cat._inserted_mid_bones.size(), worst_bone, _max_value(coverage)
	])

	manager.release_cat_cell(cat)
	manager._cats.erase(cat)
	cat.get_parent().remove_child(cat)
	cat.queue_free()


# ---------------------------------------------------------------- 도구

func _isolate_board(manager: LevelManager) -> void:
	for cat in manager.get_cats().duplicate():
		manager.release_cat_cell(cat)
		manager._cats.erase(cat)
		cat.get_parent().remove_child(cat)
		cat.queue_free()
	for node in manager.get_node("LayoutHoles").get_children():
		manager.get_node("LayoutHoles").remove_child(node)
		node.queue_free()
	for node in manager.get_node("LayoutObstacles").get_children():
		manager.get_node("LayoutObstacles").remove_child(node)
		node.queue_free()
	manager.rebuild_now()


func _distance_to_polyline(polyline: PackedVector3Array, world: Vector3) -> float:
	var best := INF
	for index in polyline.size() - 1:
		var a: Vector3 = polyline[index]
		var b: Vector3 = polyline[index + 1]
		var segment: Vector3 = b - a
		if segment.length_squared() < 0.000001:
			continue
		var t: float = clampf((world - a).dot(segment) / segment.length_squared(), 0.0, 1.0)
		best = minf(best, (a + segment * t - world).length())
	return best


# 셀 중심 → 최근접 스킨 정점의 수평 거리(타일). CPU 스키닝은 정점 셰이더를 거치지 않으므로
# 기하 자체의 커버리지를 잰다.
func _cell_coverage(
	manager: LevelManager, cat: CatEntity, body: Array[Vector2i]
) -> Dictionary:
	var coverage: Dictionary = {}
	for cell in body:
		coverage[cell] = INF
	var skeleton: Skeleton3D = cat._skeleton
	var tile: float = manager.tile_size

	for mesh_instance in _find_meshes(cat):
		var skin: Skin = mesh_instance.skin
		if skin == null:
			continue
		var matrices: Dictionary = {}
		for bind in skin.get_bind_count():
			var bone_name: String = skin.get_bind_name(bind)
			var bone: int = (
				skeleton.find_bone(bone_name) if bone_name != "" else skin.get_bind_bone(bind)
			)
			if bone >= 0:
				matrices[bind] = skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind)
		var mesh: Mesh = mesh_instance.mesh
		for surface in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if vertices.is_empty() or bones.is_empty():
				continue
			var slots: int = bones.size() / vertices.size()
			for vertex in vertices.size():
				var accumulated := Vector3.ZERO
				var total := 0.0
				for slot in slots:
					var weight: float = weights[vertex * slots + slot]
					if weight > 0.0 and matrices.has(bones[vertex * slots + slot]):
						accumulated += (
							(matrices[bones[vertex * slots + slot]] as Transform3D)
							* vertices[vertex]
						) * weight
						total += weight
				if total <= 0.0:
					continue
				var world: Vector3 = skeleton.global_transform * (accumulated / total)
				for cell in body:
					var center: Vector3 = manager.grid_to_world(cell, manager.cat_world_y)
					var distance: float = (
						Vector2(world.x - center.x, world.z - center.z).length() / tile
					)
					if distance < float(coverage[cell]):
						coverage[cell] = distance
	return coverage


func _max_value(coverage: Dictionary) -> float:
	var largest := 0.0
	for key in coverage:
		largest = maxf(largest, float(coverage[key]))
	return largest


func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_find_meshes(child))
	return found


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("LENGTH CHECK: PASS")
		return
	print("LENGTH CHECK: FAIL (%d)" % _failures.size())
	for failure in _failures:
		print("  - ", failure)
