@tool
class_name MapGeneratorTool
extends Node

# 에디터에서 맵을 뽑는 버튼. `LevelManager` 의 Inspector 를 더 불리지 않기 위해 별도 노드로
# 분리했다. `MainScene` 아래에 두고 `Generate Level` 을 누르면 현재 씬의 LayoutCats /
# LayoutHoles / LayoutObstacles 가 새 배치로 교체된다.
#
# 헤드리스로는 렌더를 볼 수 없으므로 **꺾인 시작 몸의 본 포즈는 이 버튼으로 눈으로 확인한다.**
# 규칙과 절차는 `2_맵생성기.md` 가 단일 기준이다.

@export var level_manager_path: NodePath = ^"../LevelManager"

# 켜 두면 게임을 실행하는 순간 아래 시드로 맵을 만들어 판을 갈아 끼운다. 사람이 특정 시드를
# 직접 플레이해서 재미를 판단할 때 쓴다. 씬 파일의 손 배치를 덮어쓰지 않으므로 시드만 바꿔
# 가며 계속 돌려 볼 수 있다. **켜져 있으면 손 배치 레벨은 플레이할 수 없다.**
@export var generate_on_play: bool = false

@export_group("Generation")
@export var generator_seed: int = 0
@export_range(2, 8, 1) var cat_count: int = 4
# 겉 고양이가 빠진 자리에 안쪽 고양이가 이어서 남는 몸체 수. 각 중첩마다 별도 색·구멍 하나가 든다.
@export_range(0, 4, 1) var nested_two_count: int = 0
@export_range(2, 8, 1) var body_length_min: int = 3
@export_range(2, 8, 1) var body_length_max: int = 4
@export_range(1, 24, 1) var reverse_steps_min: int = 5
@export_range(1, 32, 1) var reverse_steps_max: int = 12
# A → B → C 를 요구하면 3 이다. 올리면 재시도가 크게 늘어난다.
@export_range(1, 8, 1) var min_chain_depth: int = 3
@export_range(0.0, 1.0, 0.05) var obstacle_fill_ratio: float = 0.55
@export_range(1, 400, 1) var max_attempts: int = 80
# 얼음 기믹. 첫 탈출 구멍을 뺀 구멍마다 이 확률로 얼음을 덮는다. 0 = 얼음 없음.
@export_range(0.0, 1.0, 0.05) var ice_chance: float = 0.0
# 얼음 숫자 상한. 0 = 풀이상 안전한 최댓값(그 구멍이 쓰이기 전까지 빠지는 고양이 수)을 쓴다.
@export_range(0, 8, 1) var ice_number_max: int = 0

@export_group("Output")
@export_dir var json_directory: String = "res://resources/levels"
@export_dir var scene_directory: String = "res://scenes/levels"

@export_tool_button("Generate Level", "RandomNumberGenerator")
var generate_action: Callable = generate_level

@export_tool_button("Save Level Files", "Save")
var save_action: Callable = save_level_files

# 마지막으로 생성한 레벨. 저장 버튼이 이걸 쓴다. 씬 파일에는 저장되지 않는다.
var _last_level: Dictionary = {}


func _ready() -> void:
	if Engine.is_editor_hint() or not generate_on_play:
		return
	# **검증 하네스에서는 절대 자동 생성하지 않는다.** `generate_on_play` 는 씬 파일에 저장되는
	# 값이라, 켜 둔 채로 두면 main_scene 을 읽는 모든 하네스가 손 배치 대신 생성 레벨을 받는다.
	# `movement_check` / `hole_check` / `obstacle_check` 는 손 배치를 전제하므로 통째로 깨진다.
	# `--script` 로 띄운 실행은 하네스나 도구이고, F5/F6 실제 플레이에는 이 인자가 없다.
	if OS.get_cmdline_args().has("--script"):
		return
	# LevelManager 가 자기 _ready 에서 씬 배치를 먼저 읽게 두고 그 뒤에 갈아 끼운다.
	# 여기서 바로 하면 우리가 심은 고양이를 LevelManager 가 다시 지운다.
	call_deferred("generate_level")


func generate_level() -> void:
	var manager: LevelManager = _find_manager()
	if manager == null:
		push_error("MapGeneratorTool: LevelManager 를 찾지 못했다 (%s)" % level_manager_path)
		return

	var config := MapGenerator.default_config()
	config.base_seed = generator_seed
	config.grid_size = manager.grid_size
	config.cat_count = cat_count
	config.nested_two_count = nested_two_count
	config.color_count = maxi(manager.pair_colors.size(), 1)
	config.body_length_min = mini(body_length_min, body_length_max)
	config.body_length_max = maxi(body_length_min, body_length_max)
	config.reverse_steps_min = mini(reverse_steps_min, reverse_steps_max)
	config.reverse_steps_max = maxi(reverse_steps_min, reverse_steps_max)
	config.min_chain_depth = min_chain_depth
	config.obstacle_fill_ratio = obstacle_fill_ratio
	config.max_attempts = max_attempts
	config.ice_chance = ice_chance
	config.ice_number_max = ice_number_max

	var generator := MapGenerator.new()
	var level: Dictionary = generator.generate(config)
	if not bool(level["ok"]):
		push_error("MapGeneratorTool: 생성 실패 — %s" % level["reason"])
		for failure in (level.get("failures", []) as Array).slice(0, 10):
			print("  ", failure)
		return

	_last_level = level
	LevelLayoutWriter.apply_to_manager(manager, level)
	print(_report(level))


func save_level_files() -> void:
	if _last_level.is_empty():
		push_error("MapGeneratorTool: 먼저 Generate Level 을 눌러야 저장할 것이 있다")
		return

	var seed_value: int = int(_last_level["seed"])
	var json_path: String = "%s/level_%d.json" % [json_directory, seed_value]
	var json_error: Error = LevelLayoutWriter.save_json(_last_level, json_path)
	if json_error != OK:
		push_error("MapGeneratorTool: JSON 저장 실패 %s (%d)" % [json_path, json_error])
	else:
		print("[생성기] 저장: ", json_path)

	var root: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else owner
	if root == null:
		push_warning("MapGeneratorTool: 편집 중인 씬 루트가 없어 씬 저장을 건너뛴다")
		return
	var scene_path: String = "%s/level_%d.tscn" % [scene_directory, seed_value]
	var scene_error: Error = LevelLayoutWriter.save_scene(root, scene_path)
	if scene_error != OK:
		push_error("MapGeneratorTool: 씬 저장 실패 %s (%d)" % [scene_path, scene_error])
	else:
		print("[생성기] 저장: ", scene_path)


func _find_manager() -> LevelManager:
	var node: Node = get_node_or_null(level_manager_path)
	if node is LevelManager:
		return node as LevelManager
	# 경로가 틀어졌으면 형제/부모 트리에서 하나 찾아 준다.
	var parent: Node = get_parent()
	if parent != null:
		for sibling in parent.get_children():
			if sibling is LevelManager:
				return sibling as LevelManager
	return null


func _report(level: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("[생성기] 시드 %d (시도 %d회째)" % [int(level["seed"]), int(level["attempt"])])
	lines.append(
		"  탈출 순서 %s / 의존 사슬 깊이 %d %s"
		% [level["escape_order"], int(level["dependency"]["chain_depth"]), level["dependency"]["chain"]]
	)
	lines.append(
		"  기록된 풀이 %d수 / 오토솔버 %d수 %d노드 / 장애물 %d칸"
		% [
			int(level["stats"]["solution_length"]),
			int(level["stats"]["solver_moves"]),
			int(level["stats"]["solver_nodes"]),
			int(level["stats"]["obstacle_cells"]),
		]
	)
	lines.append("  " + (level["dependency"]["describe"] as String).replace("\n", "\n  "))
	return "\n".join(lines)
