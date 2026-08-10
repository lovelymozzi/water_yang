extends SceneTree
var _scene: Node
var _n := 0
var _lm: LevelManager
var _cat: CatEntity
var _cam: Camera3D
var _press: Vector2

func _initialize() -> void:
	_scene = (load("res://scenes/main_scene.tscn") as PackedScene).instantiate()
	root.add_child(_scene)

func _process(_d: float) -> bool:
	_n += 1
	if _n < 20: return false   # 물리/Area3D 등록 대기
	if _n == 20:
		_lm = _scene.get_node("LevelManager")
		_cat = _lm.get_node("LayoutCats").get_child(0)
		_cam = _scene.get_node("Camera3D")
		var handle: Area3D = _cat.get_node("EndpointHandles/HeadHandle")
		_press = _cam.unproject_position(handle.global_position)
		print("[1] 머리 핸들 화면좌표 = ", _press, "  body=", _cat.body_cells)
		return false
	if _n == 21:
		print("[2] 마우스 누르기 -> _unhandled_input")
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.position = _press
		_lm._unhandled_input(ev)
		print("[3] 누르기 반환됨. drag_cat=", _lm.get("_drag_cat"), " endpoint=", _lm.get("_drag_endpoint"))
		return false
	if _n >= 22 and _n <= 60:
		var step := _n - 21
		var mv := InputEventMouseMotion.new()
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		mv.position = _press + Vector2(0.0, -float(step) * 4.0)
		print("[4] 모션 %d  pos=%s" % [step, str(mv.position)])
		_lm._unhandled_input(mv)
		print("    반환됨. %s" % _cat.describe_state())
		return false
	if _n == 61:
		print("[5] 마우스 놓기")
		var up := InputEventMouseButton.new()
		up.button_index = MOUSE_BUTTON_LEFT
		up.pressed = false
		up.position = _press
		_lm._unhandled_input(up)
		print("[6] 완료 — 프리즈 없음")
		return true
	return false
