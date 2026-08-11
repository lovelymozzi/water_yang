extends SceneTree

# 스킨된 메시가 실제로 어디까지 뻗는지 잰다. 렌더가 없으므로 CPU 스키닝으로 정점을 직접 옮긴다.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/measure_extent.gd

var _frames := 0
var _scene: Node


func _initialize() -> void:
	_scene = (load("res://scenes/main_scene.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 10:
		return false
	var manager: LevelManager = _scene.get_node("LevelManager")
	var cat: CatEntity = manager.get_cats()[0]
	var skeleton: Skeleton3D = cat._skeleton

	var cells: Array = cat.body_cells
	var tile: float = manager.tile_size
	print("몸 셀 수 = %d  %s" % [cells.size(), cells])
	print("타일 = %.2f, fbx_scale_per_tile = %.2f, 모델 스케일 = %.3f" % [
		tile, cat.fbx_scale_per_tile, cat._grid_fitted_model_scale()
	])

	# 몸 축(머리 셀 -> 꼬리 셀) 위의 좌표로 환산해서 잰다.
	var head_center: Vector3 = manager.grid_to_world(cells[0], manager.cat_world_y)
	var tail_center: Vector3 = manager.grid_to_world(cells[cells.size() - 1], manager.cat_world_y)
	var axis: Vector3 = (tail_center - head_center).normalized()

	var head_bone: int = cat._bone_chain[0]
	var tail_bone: int = cat._bone_chain[cat._bone_chain.size() - 1]
	var head_bone_world: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(head_bone).origin
	var tail_bone_world: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(tail_bone).origin

	var minimum := INF
	var maximum := -INF
	for mesh_instance in _find_meshes(cat):
		for bounds in _skinned_extent(mesh_instance, skeleton, head_center, axis):
			minimum = minf(minimum, bounds)
			maximum = maxf(maximum, bounds)

	# 축 위 좌표: 0 = 머리 셀 중심, 양수 = 꼬리 방향. 단위는 타일.
	var footprint_head := -0.5
	var footprint_tail := (cells.size() - 1) + 0.5
	print("")
	print("축 좌표(타일 단위, 0 = 머리 셀 중심, %+.1f/%+.1f = 발자국 양끝)" % [footprint_head, footprint_tail])
	print("  발자국          %7.3f ~ %7.3f  (%d칸)" % [footprint_head, footprint_tail, cells.size()])
	print("  본 체인 양끝    %7.3f ~ %7.3f" % [
		(head_bone_world - head_center).dot(axis) / tile,
		(tail_bone_world - head_center).dot(axis) / tile
	])
	print("  메시 실제 범위  %7.3f ~ %7.3f" % [minimum / tile, maximum / tile])
	print("")
	print("빈 공간: 머리쪽 %.3f칸, 꼬리쪽 %.3f칸" % [
		minimum / tile - footprint_head, footprint_tail - maximum / tile
	])
	print("메시가 본 체인보다 내민 양: 머리쪽 %.3f칸, 꼬리쪽 %.3f칸" % [
		(head_bone_world - head_center).dot(axis) / tile - minimum / tile,
		maximum / tile - (tail_bone_world - head_center).dot(axis) / tile
	])
	return true


func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_find_meshes(child))
	return found


# 정점마다 지배본들의 (현재 글로벌 포즈 x rest 글로벌 역행렬)을 가중 적용한다.
func _skinned_extent(
	mesh_instance: MeshInstance3D, skeleton: Skeleton3D, origin: Vector3, axis: Vector3
) -> Array[float]:
	var mesh: Mesh = mesh_instance.mesh
	# 메시 정점은 본 rest 공간이 아니라 Skin 의 바인드 공간에 있다.
	# get_bone_global_rest().affine_inverse() 를 역바인드로 쓰면 전혀 다른 곳으로 날아간다.
	var skin_matrices := _skin_matrices(mesh_instance, skeleton)
	var minimum := INF
	var maximum := -INF

	for surface_index in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if vertices.is_empty() or bones.is_empty():
			continue
		var per_vertex: int = bones.size() / vertices.size()
		for vertex_index in vertices.size():
			var skinned := Vector3.ZERO
			var total_weight := 0.0
			for slot in per_vertex:
				var weight: float = weights[vertex_index * per_vertex + slot]
				if weight <= 0.0:
					continue
				var bind: int = bones[vertex_index * per_vertex + slot]
				if not skin_matrices.has(bind):
					continue
				skinned += (skin_matrices[bind] * vertices[vertex_index]) * weight
				total_weight += weight
			if total_weight <= 0.0:
				continue
			var world: Vector3 = skeleton.global_transform * (skinned / total_weight)
			var along: float = (world - origin).dot(axis)
			minimum = minf(minimum, along)
			maximum = maxf(maximum, along)
	return [minimum, maximum]


# 바인드 인덱스 -> (현재 글로벌 포즈 x 바인드 포즈). 바인드 포즈가 곧 역바인드 행렬이다.
func _skin_matrices(mesh_instance: MeshInstance3D, skeleton: Skeleton3D) -> Dictionary:
	var matrices := {}
	var skin: Skin = mesh_instance.skin
	if skin == null:
		return matrices
	for bind_index in skin.get_bind_count():
		var bone_name: String = skin.get_bind_name(bind_index)
		var bone: int = skeleton.find_bone(bone_name) if bone_name != "" else skin.get_bind_bone(bind_index)
		if bone < 0 or bone >= skeleton.get_bone_count():
			continue
		matrices[bind_index] = skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind_index)
	return matrices
