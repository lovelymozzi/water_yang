extends SceneTree

# 구멍 흡입을 눈으로 확인하기 위한 캡처. 렌더가 필요하므로 --headless 없이 돌린다.
#   /Applications/Godot.app/Contents/MacOS/Godot --script tests/capture_hole.gd

const OUTPUT_DIR := "user://shots_hole"
# 고양이를 구멍 옆칸까지 끌고 가는 손가락 궤적.
const TRACE := [
	Vector2i(1, 3), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)
]

var _scene: Node
var _frames := 0
var _shot := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_scene = (load("res://scenes/main_scene.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	print("[shots] ", ProjectSettings.globalize_path(OUTPUT_DIR))


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		_save("00_rest")
		return false
	if _frames < 20:
		return false

	var manager: LevelManager = _scene.get_node("LevelManager")
	var cats: Array[CatEntity] = manager.get_cats()
	if not cats.is_empty():
		var cat: CatEntity = cats[0]
		if not cat.is_absorbing():
			for cell in TRACE:
				cat.request_path_to(cell)
	if _frames % 3 == 0 and _shot < 24:
		_shot += 1
		_save("%02d_absorb" % _shot)
		return false
	return _frames > 140


func _save(label: String) -> void:
	var image: Image = root.get_texture().get_image()
	if image == null:
		return
	image.save_png("%s/%s.png" % [OUTPUT_DIR, label])
