extends SceneTree

# 길이별 자세를 렌더해 남긴다. 헤드리스가 아니어야 렌더된다.
#   /Applications/Godot.app/Contents/MacOS/Godot --script tests/capture_length.gd
#
# 볼 것: 길이가 늘어도 꺾임 모양과 링 밀도가 길이 3과 같은지(중간복제), 코너가 잘리지
# 않는지, 텍스처 밀도가 일정한지, 이음새가 없는지.

const OUTPUT_DIR := "user://shots_length"

var _scene: Node
var _manager: LevelManager
var _frames := 0
var _stage := 0


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
		_clear_board()
		# 1장: 직선 길이 3/6/9 나란히
		var column := 0
		for length in [3, 6, 9]:
			var body: Array[Vector2i] = []
			for index in length:
				body.append(Vector2i(column, index))
			_spawn(body, column % 4)
			column += 2
		# 2장 예약: 꺾인 긴 몸
		return false
	if _stage == 0:
		_save("0_straight")
		_clear_board()
		# 꺾인 몸: 길이 12 S자 + 길이 8 L자
		var snake: Array[Vector2i] = []
		for i in 4:
			snake.append(Vector2i(1, 1 + i))
		for i in 2:
			snake.append(Vector2i(2 + i, 4))
		for i in 3:
			snake.append(Vector2i(3, 5 + i))
		for i in 3:
			snake.append(Vector2i(4 + i, 7))
		_spawn(snake, 0)
		var hook: Array[Vector2i] = []
		for i in 5:
			hook.append(Vector2i(6, 0 + i))
		for i in 3:
			hook.append(Vector2i(5 - i, 4))
		_spawn(hook, 1)
		_stage = 1
		return false
	if _stage == 1:
		_save("1_bent")
		return true
	return true


func _clear_board() -> void:
	for extra in _manager.get_cats().duplicate():
		_manager.release_cat_cell(extra)
		_manager._cats.erase(extra)
		extra.get_parent().remove_child(extra)
		extra.queue_free()
	for node in _manager.get_node("LayoutHoles").get_children():
		_manager.get_node("LayoutHoles").remove_child(node)
		node.queue_free()
	_manager.rebuild_now()


func _spawn(body: Array[Vector2i], color_id: int) -> void:
	var cat := CatEntity.new()
	cat.set_script(load("res://scripts/cat_entity.gd"))
	cat.color_id = color_id
	cat.tint_from_pair_color = true
	cat.tint_gradient_enabled = true
	cat.initial_body_cells = body
	_manager.get_node("LayoutCats").add_child(cat)
	cat.initialize_runtime(_manager)
	_manager.update_cat_occupancy(cat)
	_manager._cats.append(cat)
	cat.advance(0.0)


func _save(label: String) -> void:
	var image: Image = root.get_texture().get_image()
	if image == null:
		return
	image.save_png("%s/%s.png" % [OUTPUT_DIR, label])
	print("[shot] ", label)
