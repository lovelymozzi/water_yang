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
	var expected_outline_brightness := 1.37
	var cats: Array[CatEntity] = []
	var expected_outline_colors_by_color_id: Dictionary = {}
	for child in manager.get_node("LayoutCats").get_children():
		if child is CatEntity:
			var cat := child as CatEntity
			cats.append(cat)
			for property_name in expected:
				cat.set(property_name, expected[property_name])
			cat.outline_brightness = expected_outline_brightness

	manager.refresh_shared_shader_preview()
	for cat in cats:
		var expected_outline_color: Color = manager.get_pair_color(cat.color_id).darkened(0.27)
		expected_outline_color = Color(
			minf(expected_outline_color.r * expected_outline_brightness, 1.0),
			minf(expected_outline_color.g * expected_outline_brightness, 1.0),
			minf(expected_outline_color.b * expected_outline_brightness, 1.0),
			cat.outline_color.a
		)
		expected_outline_colors_by_color_id[cat.color_id] = expected_outline_color
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
		var actual_outline_color: Color = cat._outline_material.get_shader_parameter("outline_color")
		_expect(
			is_equal_approx(actual_outline_color.r, expected_outline_color.r)
			and is_equal_approx(actual_outline_color.g, expected_outline_color.g)
			and is_equal_approx(actual_outline_color.b, expected_outline_color.b)
			and is_equal_approx(actual_outline_color.a, expected_outline_color.a),
			"Cat outline did not receive outline_brightness"
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
		var layout_hole_name := "Hole_%s" % String(hole.name).trim_prefix("CatHole_")
		var layout_hole := manager.get_node("LayoutHoles").get_node_or_null(layout_hole_name)
		var expected_outline_color: Variant = null
		if layout_hole != null:
			expected_outline_color = expected_outline_colors_by_color_id.get(int(layout_hole.get("color_id")), null)
		var hole_outline_color: Color = style["outline_color"] if style["outline_color"] is Color else Color()
		var expected_hole_outline_color: Color = expected_outline_color if expected_outline_color != null else Color()
		for property_name in expected:
			_expect(
				is_equal_approx(float(style[property_name]), float(expected[property_name])),
				"CatHole did not receive %s" % property_name
			)
		_expect(
			expected_outline_color != null
			and style["outline_color"] is Color
			and is_equal_approx(hole_outline_color.r, expected_hole_outline_color.r)
			and is_equal_approx(hole_outline_color.g, expected_hole_outline_color.g)
			and is_equal_approx(hole_outline_color.b, expected_hole_outline_color.b)
			and is_equal_approx(hole_outline_color.a, expected_hole_outline_color.a),
			"CatHole did not receive outline_brightness"
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
