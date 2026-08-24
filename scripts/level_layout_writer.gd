class_name LevelLayoutWriter
extends RefCounted

# `MapGenerator` 가 낸 레벨 Dictionary 를 실제 씬 노드와 파일로 내보낸다.
#
# 배치는 전부 기존 규칙대로 템플릿 인스턴스로만 한다. 고양이는 `scenes/cat_entity.tscn`,
# 장애물은 `scenes/obstacle_block.tscn`(칸마다 노드를 만들지 않고 `block_size` 로 묶는다),
# 구멍은 `HoleMarker` 다. 노드 Transform 을 손으로 옮기지 않고 `grid_pos` 만 지정하면
# `LevelManager` 가 `grid_to_world()` 로 맞춘다.

const CAT_SCENE_PATH := "res://scenes/cat_entity.tscn"
const OBSTACLE_SCENE_PATH := "res://scenes/obstacle_block.tscn"
const HOLE_SCRIPT_PATH := "res://scripts/hole_marker.gd"


# 레벨을 씬의 Layout* 노드에 심는다. 에디터에서는 `owner` 를 지정해 씬 파일에 저장되게 한다.
static func apply_to_manager(manager: LevelManager, level: Dictionary) -> void:
	var cat_scene: PackedScene = load(CAT_SCENE_PATH)
	var obstacle_scene: PackedScene = load(OBSTACLE_SCENE_PATH)
	var hole_script: Script = load(HOLE_SCRIPT_PATH)
	# 생성 노드의 owner 는 편집 중인 씬 루트여야 한다. LevelManager 가 루트면 자기 자신이다.
	var scene_owner: Node = manager.owner if manager.owner != null else manager

	manager.grid_size = level["grid_size"]
	# 장애물이 칸을 잠그지 않으면 생성한 풀이가 성립하지 않는다.
	manager.obstacles_enabled = true

	var cats_root: Node = _clear_layout_root(manager, "LayoutCats")
	var holes_root: Node = _clear_layout_root(manager, "LayoutHoles")
	var obstacles_root: Node = _clear_layout_root(manager, "LayoutObstacles")

	for entry in level["holes"]:
		var marker := Node3D.new()
		marker.set_script(hole_script)
		var cell: Vector2i = entry["grid_pos"]
		marker.name = "Hole_%d_%d" % [cell.x, cell.y]
		holes_root.add_child(marker)
		marker.set("grid_pos", cell)
		marker.set("color_id", int(entry["color_id"]))
		marker.set("ice_count", int(entry.get("ice_count", 0)))
		_claim(marker, scene_owner)

	for entry in level["obstacles"]:
		var block: Node = obstacle_scene.instantiate()
		var cell: Vector2i = entry["grid_pos"]
		block.name = "Obstacle_%d_%d" % [cell.x, cell.y]
		obstacles_root.add_child(block)
		block.set("grid_pos", cell)
		block.set("block_size", entry["block_size"])
		_claim(block, scene_owner)

	var cats: Array = level["cats"]
	for index in cats.size():
		var cat: Node = cat_scene.instantiate()
		cat.name = "Cat_%d" % index
		cats_root.add_child(cat)
		cat.set("color_id", int(cats[index]["color_id"]))
		# 꺾인 몸을 그대로 심는다. 세터가 grid_pos / facing_name / initial_length 를 파생시킨다.
		var body: Array[Vector2i] = []
		body.assign(cats[index]["body_cells"])
		cat.set("initial_body_cells", body)
		_claim(cat, scene_owner)

	manager.rebuild_now()


static func _clear_layout_root(manager: LevelManager, root_name: String) -> Node:
	var root: Node = manager.get_node_or_null(root_name)
	if root == null:
		root = Node3D.new()
		root.name = root_name
		manager.add_child(root)
		_claim(root, manager.owner if manager.owner != null else manager)
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()
	return root


# owner 는 에디터 여부와 무관하게 지정한다. `PackedScene.pack()` 이 owner 없는 노드를 통째로
# 빠뜨리므로, 이게 없으면 헤드리스에서 레벨 씬을 저장할 수 없다(빈 씬이 나온다).
static func _claim(node: Node, scene_owner: Node) -> void:
	if scene_owner != null and node != scene_owner:
		node.owner = scene_owner


# ---------------------------------------------------------------- 파일 출력

# 씬 하나를 통째로 저장한다. 저장 대상은 편집 중인 루트(카메라·조명 포함)이므로 그대로
# 실행할 수 있는 레벨 씬이 된다. 생성 노드에 owner 가 없으면 pack() 이 빠뜨린다.
static func save_scene(root: Node, path: String) -> Error:
	var error: Error = _ensure_directory(path)
	if error != OK:
		return error
	var packed := PackedScene.new()
	error = packed.pack(root)
	if error != OK:
		return error
	return ResourceSaver.save(packed, path)


static func save_json(level: Dictionary, path: String) -> Error:
	var error: Error = _ensure_directory(path)
	if error != OK:
		return error
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_json(level), "  "))
	file.close()
	return OK


static func load_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return from_json(parsed as Dictionary)
	return {}


static func _ensure_directory(path: String) -> Error:
	var directory: String = path.get_base_dir()
	if DirAccess.dir_exists_absolute(directory):
		return OK
	return DirAccess.make_dir_recursive_absolute(directory)


# JSON 은 Vector2i 를 모른다. 풀이 수순과 의존성 그래프까지 함께 저장해 시드 회귀와
# 테스트 재현에 쓴다.
static func to_json(level: Dictionary) -> Dictionary:
	var data: Dictionary = {
		"seed": int(level["seed"]),
		"grid_size": _pack_cell(level["grid_size"]),
		"holes": [],
		"obstacles": [],
		"cats": [],
		"solution": [],
		"escape_order": level["escape_order"],
		"dependency": {
			"edges": level["dependency"]["edges"],
			"chain_depth": int(level["dependency"]["chain_depth"]),
			"chain": level["dependency"]["chain"],
		},
		"stats": level["stats"],
	}
	for entry in level["holes"]:
		data["holes"].append({
			"grid_pos": _pack_cell(entry["grid_pos"]),
			"color_id": int(entry["color_id"]),
			"ice_count": int(entry.get("ice_count", 0)),
		})
	for entry in level["obstacles"]:
		data["obstacles"].append({
			"grid_pos": _pack_cell(entry["grid_pos"]),
			"block_size": _pack_cell(entry["block_size"]),
		})
	for entry in level["cats"]:
		var body: Array = []
		for cell in entry["body_cells"]:
			body.append(_pack_cell(cell))
		data["cats"].append({"body_cells": body, "color_id": int(entry["color_id"])})
	for move in level["solution"]:
		data["solution"].append({
			"cat_id": int(move["cat_id"]),
			"from_end_cell": _pack_cell(move["from_end_cell"]),
			"to_cell": _pack_cell(move["to_cell"]),
		})
	return data


static func from_json(data: Dictionary) -> Dictionary:
	var level: Dictionary = {
		"ok": true,
		"reason": "",
		"seed": int(data["seed"]),
		"attempt": -1,
		"grid_size": _unpack_cell(data["grid_size"]),
		"holes": [],
		"obstacles": [],
		"cats": [],
		"solution": [],
		"escape_order": [],
		"dependency": data.get("dependency", {}),
		"stats": data.get("stats", {}),
	}
	for value in data.get("escape_order", []):
		(level["escape_order"] as Array).append(int(value))
	for entry in data["holes"]:
		level["holes"].append({
			"grid_pos": _unpack_cell(entry["grid_pos"]),
			"color_id": int(entry["color_id"]),
			"ice_count": int(entry.get("ice_count", 0)),
		})
	for entry in data["obstacles"]:
		level["obstacles"].append({
			"grid_pos": _unpack_cell(entry["grid_pos"]),
			"block_size": _unpack_cell(entry["block_size"]),
		})
	for entry in data["cats"]:
		var body: Array[Vector2i] = []
		for cell in entry["body_cells"]:
			body.append(_unpack_cell(cell))
		level["cats"].append({"body_cells": body, "color_id": int(entry["color_id"])})
	for move in data["solution"]:
		level["solution"].append({
			"cat_id": int(move["cat_id"]),
			"from_end_cell": _unpack_cell(move["from_end_cell"]),
			"to_cell": _unpack_cell(move["to_cell"]),
		})
	return level


static func _pack_cell(cell: Vector2i) -> Array:
	return [cell.x, cell.y]


static func _unpack_cell(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))


# ---------------------------------------------------------------- 모델 변환

# 레벨 Dictionary 를 헤드리스 모델로 되돌린다. 솔버·검증 하네스가 쓴다.
static func to_puzzle_state(level: Dictionary) -> PuzzleState:
	var state := PuzzleState.create(level["grid_size"])
	for entry in level["holes"]:
		state.add_hole(entry["grid_pos"], int(entry["color_id"]))
	for entry in level["obstacles"]:
		for cell in PuzzleState.cells_of_block(entry):
			state.add_obstacle(cell)
	var cats: Array = level["cats"]
	for index in cats.size():
		var body: Array[Vector2i] = []
		body.assign(cats[index]["body_cells"])
		state.add_cat(index, int(cats[index]["color_id"]), body)
	return state
