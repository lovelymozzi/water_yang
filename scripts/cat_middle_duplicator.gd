class_name CatMiddleDuplicator
extends RefCounted

# 몸 중간 복제. 길이가 늘 때 기존 구간을 잡아늘리는 대신 **본과 링 기하를 함께 복제**해
# 꽂는다. 그래서 길이가 길어져도 링 밀도와 꺾임 모양이 길이 3과 동일하게 유지된다.
#
# ## 왜 "본만 복사"로는 안 되는가
#
# 표면은 링(정점 고리) 사이에서 직선이다. 본을 아무리 촘촘히 넣어도 링이 없는 구간은
# 코너에서 직선으로 질러간다. 그래서 본 하나당 링 하나를 쌍으로 복제해야 한다.
#
# ## 계측으로 확인한 cat1.fbx 의 구조 (tests/length_check.gd 가 재검증)
#
# - 서피스 1(Material cat_tile)이 늘어나는 관이다. 28정점 링의 스택이며 링 간격은
#   본 간격과 같고(모델 ~0.02), 반경 프로파일이 전 구간 동일해 어디서 복제해도 이음새가 없다.
# - Bone008 링은 유일하게 웨이트 1.0 짜리 순수 링이다. 여기가 복제 삽입 지점이다.
# - UV V 는 링마다 +0.0451 씩 균일하게 전진한다. 복제 링도 같은 증분으로 이어 주면
#   기존 uv_tiling 텍스처 방식이 그대로 유지된다(복제 후 신축 배율이 ~1 이라 항등이 된다).
#
# ## 스켈레톤 삽입 방식
#
# Godot 는 부모 본 인덱스가 자식보다 작아야 하므로 Bone009 를 새 본에 리페어런트할 수 없다.
# 대신 새 본 사슬(BoneMid001..K)을 Bone008 아래에 달고, **Bone009 의 rest 오프셋을
# (K+1)×단위로 늘려** Bone009 이후 전체가 삽입 길이만큼 밀려나게 한다. 포즈는 어차피
# `CatEntity` 가 폴리라인 호 길이로 전 체인을 매 프레임 덮어쓰므로 부모 관계는 rest 계산에만
# 쓰인다. 체인 순서는 부모 걷기로 나오지 않으므로 `CatEntity._build_bone_chain()` 이
# `inserted` 목록을 Bone008 뒤에 이어 붙인다.

const CUT_BONE_NAME := "Bone008"
const NEXT_BONE_NAME := "Bone009"
# 링 B(꼬리쪽 이웃 링)를 찾기 위한 두 번째 본. 그 링은 Bone009/010 을 0.5/0.5 로 쓴다.
const NEXT_NEXT_BONE_NAME := "Bone010"
const INSERTED_NAME_FORMAT := "BoneMid%03d"
const TILE_SURFACE_INDEX := 1
const PURE_WEIGHT_THRESHOLD := 0.99


# 늘어난 길이(모델 단위)를 본+링 복제로 흡수한다. 반환은 삽입한 본 인덱스 목록(머리→꼬리 순).
# 나머지 끝수(단위의 ±절반)는 기존 신축 배율이 흡수하므로 배율은 항상 1±6% 안에 머문다.
static func extend(
	skeleton: Skeleton3D, mesh_instance: MeshInstance3D, extra_model_length: float
) -> Array[int]:
	var inserted: Array[int] = []
	if skeleton == null or mesh_instance == null or mesh_instance.mesh == null:
		return inserted

	var cut_bone: int = skeleton.find_bone(CUT_BONE_NAME)
	var next_bone: int = skeleton.find_bone(NEXT_BONE_NAME)
	if cut_bone < 0 or next_bone < 0:
		return inserted

	var unit_rest: Transform3D = skeleton.get_bone_rest(next_bone)
	var unit_length: float = unit_rest.origin.length()
	if unit_length <= 0.000001:
		return inserted

	var count: int = int(round(extra_model_length / unit_length))
	if count <= 0:
		return inserted

	inserted = _insert_bones(skeleton, cut_bone, next_bone, unit_rest, count)
	if inserted.is_empty():
		return inserted

	if not _duplicate_rings(skeleton, mesh_instance, inserted):
		# 메시 수술이 실패하면 본만 남는다. 이 상태로도 포즈는 돌지만 관이 늘어나므로
		# 원인을 찾을 수 있게 소리 내고 진행한다.
		push_error("CatMiddleDuplicator: 링 복제 실패. 본 %d개만 삽입됐다" % inserted.size())
	return inserted


# ---------------------------------------------------------------- 스켈레톤

static func _insert_bones(
	skeleton: Skeleton3D,
	cut_bone: int,
	next_bone: int,
	unit_rest: Transform3D,
	count: int
) -> Array[int]:
	var inserted: Array[int] = []
	var parent: int = cut_bone
	for index in range(1, count + 1):
		var bone_name: String = INSERTED_NAME_FORMAT % index
		if skeleton.find_bone(bone_name) >= 0:
			push_error("CatMiddleDuplicator: %s 가 이미 있다. 중복 호출이다" % bone_name)
			return [] as Array[int]
		skeleton.add_bone(bone_name)
		var bone: int = skeleton.find_bone(bone_name)
		skeleton.set_bone_parent(bone, parent)
		skeleton.set_bone_rest(bone, unit_rest)
		# 새 본의 초기 포즈를 rest 로 맞춘다. 안 하면 첫 프레임 전까지 원점에 뭉친다.
		skeleton.set_bone_pose_position(bone, unit_rest.origin)
		skeleton.set_bone_pose_rotation(bone, unit_rest.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(bone, Vector3.ONE)
		inserted.append(bone)
		parent = bone

	# Bone009 의 rest 를 (K+1)×단위로 늘려 꼬리쪽 전체를 삽입 길이만큼 민다.
	# 리페어런트가 아니므로 부모 인덱스 순서 제약을 건드리지 않는다.
	var stretched: Transform3D = unit_rest
	stretched.origin = unit_rest.origin * float(count + 1)
	skeleton.set_bone_rest(next_bone, stretched)
	skeleton.set_bone_pose_position(next_bone, stretched.origin)
	return inserted


# ---------------------------------------------------------------- 메시

# 서피스 1 의 [링A(Bone008) → 링B(Bone009/010)] 밴드를 삽입 본마다 복제한다.
# 링A 의 정점을 그대로 복사하고 바인드만 새 본으로 바꾸면, rest 스키닝이 복사 링을
# 새 본 자리에 앉힌다(바인드 포즈를 Bone008 것과 같게 두기 때문이다).
static func _duplicate_rings(
	skeleton: Skeleton3D, mesh_instance: MeshInstance3D, inserted: Array[int]
) -> bool:
	var source_mesh: ArrayMesh = mesh_instance.mesh as ArrayMesh
	if source_mesh == null or source_mesh.get_surface_count() <= TILE_SURFACE_INDEX:
		return false
	var skin: Skin = mesh_instance.skin
	if skin == null:
		return false
	# 메시와 스킨은 FBX 리소스를 다른 고양이와 공유한다. 편집 전에 반드시 사본을 만든다.
	skin = skin.duplicate()
	mesh_instance.skin = skin

	var cut_bind: int = _find_bind(skeleton, skin, CUT_BONE_NAME)
	var next_bind: int = _find_bind(skeleton, skin, NEXT_BONE_NAME)
	var next_next_bind: int = _find_bind(skeleton, skin, NEXT_NEXT_BONE_NAME)
	if cut_bind < 0 or next_bind < 0 or next_next_bind < 0:
		return false

	var arrays: Array = source_mesh.surface_get_arrays(TILE_SURFACE_INDEX)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.is_empty() or bones.is_empty() or indices.is_empty():
		return false
	var slots: int = bones.size() / vertices.size()

	# 링A: Bone008 웨이트가 1.0 인 정점. 링B: Bone009 와 Bone010 을 함께 쓰는 정점.
	var ring_a: Array[int] = []
	var ring_b: Array[int] = []
	for vertex in vertices.size():
		var uses_next := false
		var uses_next_next := false
		for slot in slots:
			var weight: float = weights[vertex * slots + slot]
			if weight <= 0.001:
				continue
			var bind: int = bones[vertex * slots + slot]
			if bind == cut_bind and weight >= PURE_WEIGHT_THRESHOLD:
				ring_a.append(vertex)
			elif bind == next_bind:
				uses_next = true
			elif bind == next_next_bind:
				uses_next_next = true
		if uses_next and uses_next_next:
			ring_b.append(vertex)
	if ring_a.is_empty() or ring_b.is_empty():
		return false

	# 두 링 사이의 원본 밴드 삼각형. 이것이 복제 밴드의 위상 템플릿이 된다.
	var in_a: Dictionary = {}
	for vertex in ring_a:
		in_a[vertex] = true
	var in_b: Dictionary = {}
	for vertex in ring_b:
		in_b[vertex] = true
	var template: Array[int] = []
	var kept_indices: PackedInt32Array = PackedInt32Array()
	for triangle in range(0, indices.size(), 3):
		var touches_a := false
		var touches_b := false
		var contained := true
		for corner in 3:
			var vertex: int = indices[triangle + corner]
			if in_a.has(vertex):
				touches_a = true
			elif in_b.has(vertex):
				touches_b = true
			else:
				contained = false
		if contained and touches_a and touches_b:
			for corner in 3:
				template.append(indices[triangle + corner])
		else:
			kept_indices.append(indices[triangle])
			kept_indices.append(indices[triangle + 1])
			kept_indices.append(indices[triangle + 2])
	if template.is_empty():
		return false

	# 링B 정점 → 링A 파트너. 복제 링은 링A 모양이므로, 밴드 위상을 복제 링끼리 잇는 데 쓴다.
	# 파트너는 링 중심 기준 각도가 가장 가까운 정점이다(두 링의 단면 프로파일이 같다).
	var partner: Dictionary = _match_by_angle(skeleton, skin, arrays, ring_a, ring_b)
	if partner.is_empty():
		return false

	# 링A 와 링B 의 UV V 간격. 복제 링마다 이만큼 전진시켜 텍스처 밀도를 원본과 같게 유지한다.
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var v_step: float = _average_v(uvs, ring_b) - _average_v(uvs, ring_a)

	# 새 바인드: 삽입 본마다 Bone008 의 바인드 포즈를 복사한다. 정점도 링A 를 그대로 복사하므로
	# rest 스키닝 결과가 "링A 모양을 새 본 프레임에 놓은 것"이 된다.
	var cut_bind_pose: Transform3D = skin.get_bind_pose(cut_bind)
	var inserted_binds: Array[int] = []
	for bone in inserted:
		var bind: int = skin.get_bind_count()
		skin.add_bind(bone, cut_bind_pose)
		skin.set_bind_name(bind, skeleton.get_bone_name(bone))
		inserted_binds.append(bind)

	# 복제 링 정점 추가. copies[layer][ring_a 안의 순번] = 새 정점 인덱스.
	#
	# 웨이트는 원본 링과 같은 **이웃 본 0.5/0.5** 다. 단일 본 1.0 으로 물리면 코너에서
	# 이웃 링끼리 90도로 확 꺾여 안쪽이 접히고, 뒤집힌 면으로 아웃라인 껍데기가 비집고
	# 나와 검은 쐐기가 보인다. 0.5/0.5 는 방향을 두 본에 걸쳐 섞어 코너를 둥글린다.
	var mutable: Array = arrays.duplicate()
	var copies: Array = []
	for layer in inserted.size():
		var previous_bind: int = cut_bind if layer == 0 else inserted_binds[layer - 1]
		var layer_map: Dictionary = {}
		for position in ring_a.size():
			var source: int = ring_a[position]
			var created: int = _append_vertex_copy(
				mutable, source, slots,
				previous_bind, inserted_binds[layer],
				v_step * float(layer + 1)
			)
			layer_map[source] = created
		copies.append(layer_map)

	# 밴드 연결. 층 0 은 링A 원본, 층 K 는 링B 원본과 잇는다. 모든 층이 같은 템플릿을 쓰므로
	# 감기 방향이 일관된다.
	var new_indices: PackedInt32Array = kept_indices
	for layer in inserted.size() + 1:
		for corner in template.size():
			var vertex: int = template[corner]
			if in_a.has(vertex):
				# 밴드의 머리쪽 링: 층 0 이면 원본 링A, 아니면 layer-1 번째 복제 링.
				new_indices.append(
					vertex if layer == 0 else int((copies[layer - 1] as Dictionary)[vertex])
				)
			else:
				# 밴드의 꼬리쪽 링: 마지막 층이면 원본 링B, 아니면 파트너의 layer 번째 복제.
				if layer == inserted.size():
					new_indices.append(vertex)
				else:
					new_indices.append(int((copies[layer] as Dictionary)[int(partner[vertex])]))
	mutable[Mesh.ARRAY_INDEX] = new_indices

	# 새 메시로 교체. 서피스 0 은 그대로 옮기고 머티리얼 슬롯을 보존한다.
	# (인스턴스별 표시는 set_surface_override_material 이라 메시 교체 후에도 유지된다.)
	var rebuilt := ArrayMesh.new()
	for surface in source_mesh.get_surface_count():
		var surface_arrays: Array = (
			mutable if surface == TILE_SURFACE_INDEX else source_mesh.surface_get_arrays(surface)
		)
		rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)
		rebuilt.surface_set_material(surface, source_mesh.surface_get_material(surface))
	mesh_instance.mesh = rebuilt
	return true


static func _find_bind(skeleton: Skeleton3D, skin: Skin, bone_name: String) -> int:
	for bind in skin.get_bind_count():
		var name: String = skin.get_bind_name(bind)
		if name == bone_name:
			return bind
		if name == "" and skin.get_bind_bone(bind) == skeleton.find_bone(bone_name):
			return bind
	return -1


# 링B 의 각 정점을 링 중심 기준 각도로 링A 정점과 짝짓는다.
static func _match_by_angle(
	skeleton: Skeleton3D, skin: Skin, arrays: Array, ring_a: Array[int], ring_b: Array[int]
) -> Dictionary:
	var rest: Dictionary = _rest_positions(skeleton, skin, arrays, ring_a + ring_b)
	if rest.is_empty():
		return {}

	var center_a: Vector3 = _center(rest, ring_a)
	var center_b: Vector3 = _center(rest, ring_b)
	var partner: Dictionary = {}
	for vertex_b in ring_b:
		var offset_b: Vector3 = (rest[vertex_b] as Vector3) - center_b
		var angle_b: float = atan2(offset_b.z, offset_b.x)
		var best: int = ring_a[0]
		var best_delta: float = 100.0
		for vertex_a in ring_a:
			var offset_a: Vector3 = (rest[vertex_a] as Vector3) - center_a
			var delta: float = absf(angle_difference(atan2(offset_a.z, offset_a.x), angle_b))
			if delta < best_delta:
				best_delta = delta
				best = vertex_a
		partner[vertex_b] = best
	return partner


# rest 포즈로 스키닝한 정점 위치. 정점은 바인드 공간에 있으므로 이 변환 없이는 링이 안 보인다.
static func _rest_positions(
	skeleton: Skeleton3D, skin: Skin, arrays: Array, wanted: Array
) -> Dictionary:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var slots: int = bones.size() / vertices.size()

	var bind_matrices: Dictionary = {}
	for bind in skin.get_bind_count():
		var name: String = skin.get_bind_name(bind)
		var bone: int = skeleton.find_bone(name) if name != "" else skin.get_bind_bone(bind)
		if bone >= 0:
			bind_matrices[bind] = skeleton.get_bone_global_rest(bone) * skin.get_bind_pose(bind)

	var positions: Dictionary = {}
	for vertex in wanted:
		var accumulated := Vector3.ZERO
		var total := 0.0
		for slot in slots:
			var weight: float = weights[vertex * slots + slot]
			if weight <= 0.001:
				continue
			var bind: int = bones[vertex * slots + slot]
			if bind_matrices.has(bind):
				accumulated += (bind_matrices[bind] as Transform3D) * vertices[vertex] * weight
				total += weight
		if total <= 0.0:
			return {}
		positions[vertex] = accumulated / total
	return positions


static func _center(rest: Dictionary, ring: Array[int]) -> Vector3:
	var total := Vector3.ZERO
	for vertex in ring:
		total += rest[vertex] as Vector3
	return total / float(ring.size())


static func _average_v(uvs: PackedVector2Array, ring: Array[int]) -> float:
	if uvs.is_empty() or ring.is_empty():
		return 0.0
	var total := 0.0
	for vertex in ring:
		total += uvs[vertex].y
	return total / float(ring.size())


# 링A 정점 하나를 복사해 배열 끝에 붙인다. 위치·노멀·탄젠트는 그대로 두고(바인드 포즈가
# 같으므로 스키닝이 새 본 자리로 옮긴다) 바인드와 UV V 만 바꾼다.
#
# 존재하는 **모든** 정점 배열을 확장해야 한다. FBX 임포트가 UV2·CUSTOM 같은 배열을 함께
# 실어 오는데, 하나라도 길이가 어긋나면 `add_surface_from_arrays` 가 서피스를 통째로 거부해
# 몸통이 사라진다. 그래서 배열별 스트라이드(정점당 원소 수)를 재서 일반 복사한다.
static func _append_vertex_copy(
	arrays: Array,
	source: int,
	slots: int,
	bind_a: int,
	bind_b: int,
	v_offset: float
) -> int:
	var vertex_count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()

	for array_index in Mesh.ARRAY_MAX:
		if array_index == Mesh.ARRAY_INDEX or arrays[array_index] == null:
			continue
		# 팩드 배열은 COW 라 꺼내서 고친 뒤 반드시 되넣어야 한다.
		var data: Variant = arrays[array_index]
		match array_index:
			Mesh.ARRAY_BONES:
				for slot in slots:
					data.append(bind_a if slot == 0 else (bind_b if slot == 1 else 0))
			Mesh.ARRAY_WEIGHTS:
				for slot in slots:
					data.append(0.5 if slot <= 1 else 0.0)
			Mesh.ARRAY_TEX_UV:
				data.append((data[source] as Vector2) + Vector2(0.0, v_offset))
			_:
				var stride: int = int(float(data.size()) / float(vertex_count))
				for component in stride:
					data.append(data[source * stride + component])
		arrays[array_index] = data
	return vertex_count
