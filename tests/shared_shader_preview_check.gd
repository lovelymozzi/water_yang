extends SceneTree

var _scene: Node
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = (load("res://scenes/main_scene.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	for _frame in 10:
		await process_frame

	var manager := _scene.get_node("LevelManager") as LevelManager
	var expected := {
		"shadow_darkness": 0.91,
		"rim_strength": 0.73,
		"outline_width": 0.021,
		"line_art_strength": 0.37,
	}
	var cats: Array[CatEntity] = []
	for child in manager.get_node("LayoutCats").get_children():
		if child is CatEntity:
			var cat := child as CatEntity
			cats.append(cat)
			for property_name in expected:
				cat.set(property_name, expected[property_name])

	manager.refresh_shared_shader_preview()
	for cat in cats:
		_expect(
			is_equal_approx(
				float(cat._cat_material.get_shader_parameter("shadow_darkness")),
				float(expected["shadow_darkness"])
			),
			"Cat shader did not receive shadow_darkness"
		)
		_expect(
			is_equal_approx(
				float(cat._cat_material.get_shader_parameter("rim_strength")),
				float(expected["rim_strength"])
			),
			"Cat shader did not receive rim_strength"
		)
		_expect(
			is_equal_approx(
				float(cat._outline_material.get_shader_parameter("outline_width")),
				float(expected["outline_width"])
			),
			"Cat outline did not receive outline_width"
		)
		_expect(
			is_equal_approx(
				float(cat._cat_material.get_shader_parameter("line_art_strength")),
				float(expected["line_art_strength"])
			),
			"Cat shader did not receive line_art_strength"
		)

	for hole in manager.get_node("HoleVisuals").get_children():
		var style: Dictionary = hole.get("_cat_visual_style")
		if style.is_empty():
			continue
		for property_name in expected:
			_expect(
				is_equal_approx(float(style[property_name]), float(expected[property_name])),
				"CatHole did not receive %s" % property_name
			)

	if _failures.is_empty():
		print("SHARED SHADER PREVIEW CHECK: PASS")
		quit(0)
	else:
		print("SHARED SHADER PREVIEW CHECK: FAIL\n%s" % "\n".join(_failures))
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
