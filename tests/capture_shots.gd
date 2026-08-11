extends SceneTree

# 이동 자세를 눈으로 확인하기 위한 캡처. 렌더가 필요하므로 --headless 없이 돌린다.
#   /Applications/Godot.app/Contents/MacOS/Godot --script tests/capture_shots.gd

const OUTPUT_DIR := "user://shots"

var _scene: Node
var _frames := 0
var _shot := 0
var _reverse := false


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
	if _frames == 22:
		# 후미가 이미 보드 끝에 닿아 있다. 계속 뒤로 밀어 가장자리를 타고 흐르게 한다.
		_reverse = true
		return false
	if _reverse:
		var cat: CatEntity = (_scene.get_node("LevelManager") as LevelManager).get_cats()[0]
		cat.request_path_to(cat.body_cells[1])
	if _frames > 22 and _frames % 5 == 0 and _shot < 12:
		_shot += 1
		_save("%02d_move" % _shot)
		return false
	return _frames > 110


func _save(label: String) -> void:
	var image: Image = root.get_texture().get_image()
	if image == null:
		return
	image.save_png("%s/%s.png" % [OUTPUT_DIR, label])
