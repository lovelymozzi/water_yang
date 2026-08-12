extends SceneTree

# 생성한 레벨을 눈으로 확인하기 위한 캡처. 렌더가 필요하므로 --headless 없이 돌린다.
#   /Applications/Godot.app/Contents/MacOS/Godot --script tests/capture_generated.gd
#
# 특히 **꺾인 시작 몸의 본 포즈**를 본다. 얼굴이 위를 보는지, 코너에서 몸이 옆 칸으로
# 밀리지 않는지, 생성 고양이가 손 배치 고양이와 같아 보이는지.

const OUTPUT_DIR := "user://shots_generated"
const CAPTURE_SEEDS := [11, 2200066, 4400132]

var _scene: Node
var _manager: LevelManager
var _generator := MapGenerator.new()
var _frames := 0
var _index := 0
var _wait := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_scene = (load("res://scenes/main_scene.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	print("[shots] ", ProjectSettings.globalize_path(OUTPUT_DIR))


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 20:
		return false
	if _manager == null:
		_manager = _scene.get_node("LevelManager")

	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			_save("%02d_seed" % _index)
			_index += 1
		return false

	if _index >= CAPTURE_SEEDS.size():
		return true

	var config := MapGenerator.default_config()
	config.base_seed = CAPTURE_SEEDS[_index]
	config.grid_size = _manager.grid_size
	config.color_count = _manager.pair_colors.size()
	var level: Dictionary = _generator.generate(config)
	if not bool(level["ok"]):
		print("생성 실패 시드 %d: %s" % [config.base_seed, level["reason"]])
		_index += 1
		return false

	LevelLayoutWriter.apply_to_manager(_manager, level)
	for entry in level["cats"]:
		print("  고양이 색 %d 몸 %s" % [int(entry["color_id"]), entry["body_cells"]])
	# 스켈레톤 포즈가 자리를 잡을 프레임을 준다.
	_wait = 8
	return false


func _save(label: String) -> void:
	var image: Image = root.get_texture().get_image()
	if image == null:
		return
	image.save_png("%s/%s.png" % [OUTPUT_DIR, label])
	print("[shot] ", label)
