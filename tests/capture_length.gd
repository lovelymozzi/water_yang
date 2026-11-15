extends Node

# 길이별 자세를 렌더해 남긴다. 헤드리스가 아니어야 렌더된다.
#   Godot 4.7.2 --path . tests/capture_length.tscn
#
# 볼 것: 길이가 늘어도 꺾임 모양과 링 밀도가 길이 3과 같은지(중간복제), 코너가 잘리지
# 않는지, 텍스처 밀도가 일정한지, 이음새가 없는지.

const OUTPUT_DIR := "user://shots_length"

var _scene: Node
var _manager: LevelManager
var _frames := 0
var _stage := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	UiBridge.standalone_autostart = false
	_scene = (load("res://scenes/main_scene.tscn") as PackedScene).instantiate()
	_scene.set_script(null)
	add_child(_scene)
	for overlay in ["IceDissolveMesh", "IceDissolveSnowTop", "IceDissolveSnowBottom"]:
		_scene.get_node("Camera3D/" + overlay).hide()
	print("[shots] ", ProjectSettings.globalize_path(OUTPUT_DIR))


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 20 and _stage < 3:
		return
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
		return
	if _stage == 0:
		_save("0_straight")
		_clear_board()
		# 꺾인 몸: 길이 12 S자 + 길이 7 L자 (점유 칸은 겹치지 않는다).
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
		for i in 2:
			hook.append(Vector2i(5 - i, 4))
		_spawn(hook, 1)
		_stage = 1
		return
	if _stage == 1:
		_save("1_bent")
		_clear_board()
		_spawn([Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(3, 4), Vector2i(3, 3), Vector2i(3, 2)], 2)
		_spawn([Vector2i(6, 2), Vector2i(6, 3), Vector2i(5, 3)], 0)
		_stage = 2
		return
	if _stage == 2:
		_save("2_tight_bends")
		var cat := _manager.get_cats()[0] as CatEntity
		cat.request_path_to(cat.get_head_cell() + Vector2i.UP)
		_stage = 3
		_frames = 0
		return
	if _stage == 3:
		_save("3_bend_%02d" % _frames)
		var cat := _manager.get_cats()[0] as CatEntity
		cat.advance(1.0 / (cat.move_speed_cells * 16.0))
		if _frames <= 16:
			return
		set_process(false)
		_scene.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit()


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
	var cat := (load("res://scenes/cat_entity.tscn") as PackedScene).instantiate() as CatEntity
	cat.color_id = color_id
	cat.tint_from_pair_color = true
	cat.initial_body_cells = body
	_manager.get_node("LayoutCats").add_child(cat)
	cat.initialize_runtime(_manager)
	_manager.update_cat_occupancy(cat)
	_manager._cats.append(cat)
	cat.advance(0.0)
	cat.set_process(false)


func _save(label: String) -> void:
	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		return
	image.save_png("%s/%s.png" % [OUTPUT_DIR, label])
	print("[shot] ", label)
