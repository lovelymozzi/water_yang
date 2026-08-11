extends SceneTree

# 이동 자세를 눈으로 확인하기 위한 캡처. 렌더가 필요하므로 --headless 없이 돌린다.
#   /Applications/Godot.app/Contents/MacOS/Godot --script tests/capture_shots.gd

const OUTPUT_DIR := "user://shots"

var _scene: Node
var _frames := 0
var _shot := 0
var _route: Array[Vector2i] = []


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
		var cat: CatEntity = (_scene.get_node("LevelManager") as LevelManager).get_cats()[0]
		var lead: Vector2i = cat.get_lead_cell()
		# 직선 → 90도 코너 → 직선 → 반대 코너. 코너가 몸을 타고 내려가는 모습을 담는다.
		for step in [
			Vector2i(0, -1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(1, 0),
			Vector2i(0, 1), Vector2i(0, 1), Vector2i(1, 0),
		]:
			lead += step
			_route.append(lead)
		return false
	if not _route.is_empty():
		var cat: CatEntity = (_scene.get_node("LevelManager") as LevelManager).get_cats()[0]
		# 손가락이 앞서가듯 큐에 여유가 생길 때마다 다음 셀을 흘려 넣는다.
		if cat.path_queue.size() < cat.path_queue_max:
			cat.request_path_to(_route.pop_front())
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
