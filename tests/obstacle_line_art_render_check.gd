extends SceneTree

const OUTPUT_DIR := "user://obstacle_line_art_check"

var _frames := 0
var _obstacle_off: Node3D
var _obstacle_red: Node3D
var _obstacle_blue: Node3D


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	var root_3d := Node3D.new()
	root.add_child(root_3d)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.4
	camera.position = Vector3(0.0, 3.1, 3.6)
	camera.rotation_degrees = Vector3(-35.0, 0.0, 0.0)
	camera.current = true
	root_3d.add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	light.light_energy = 1.8
	root_3d.add_child(light)

	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.2, 0.24, 0.17, 1.0)
	root_3d.add_child(environment)

	var scene := load("res://scenes/obstacle_tile_1x1.tscn") as PackedScene
	_obstacle_off = scene.instantiate() as Node3D
	_obstacle_red = scene.instantiate() as Node3D
	_obstacle_blue = scene.instantiate() as Node3D
	_obstacle_off.position = Vector3(-1.9, 0.12, 0.0)
	_obstacle_red.position = Vector3(0.0, 0.12, 0.0)
	_obstacle_blue.position = Vector3(1.9, 0.12, 0.0)
	root_3d.add_child(_obstacle_off)
	root_3d.add_child(_obstacle_red)
	root_3d.add_child(_obstacle_blue)

	_obstacle_off.set("line_art_enabled", 0.0)
	_obstacle_off.set("line_art_color", Color(1.0, 0.0, 0.0, 1.0))
	_obstacle_off.set("line_art_strength", 1.0)
	_obstacle_off.call("apply_cell_style", Vector2i.ZERO, Color.WHITE)

	_obstacle_red.set("line_art_enabled", 1.0)
	_obstacle_red.set("line_art_color", Color(1.0, 0.0, 0.0, 1.0))
	_obstacle_red.set("line_art_strength", 0.01)
	_obstacle_red.call("apply_cell_style", Vector2i.ZERO, Color.WHITE)

	_obstacle_blue.set("line_art_enabled", 1.0)
	_obstacle_blue.set("line_art_color", Color(0.0, 0.45, 1.0, 1.0))
	_obstacle_blue.set("line_art_strength", 1.0)
	_obstacle_blue.call("apply_cell_style", Vector2i.ZERO, Color.WHITE)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 12:
		var image := root.get_texture().get_image()
		if image != null:
			image.save_png("%s/render.png" % OUTPUT_DIR)
			print("OBSTACLE LINE ART RENDER:", ProjectSettings.globalize_path("%s/render.png" % OUTPUT_DIR))
		quit()
		return true
	return false
