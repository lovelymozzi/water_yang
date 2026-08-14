extends SceneTree

const OUTPUT_PATH := "user://path_tile_shadow_render.png"

var _frames := 0


func _initialize() -> void:
	var root_3d := Node3D.new()
	root.add_child(root_3d)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.5
	camera.position = Vector3(0.0, 4.8, 4.6)
	camera.rotation_degrees = Vector3(-47.0, 0.0, 0.0)
	camera.current = true
	root_3d.add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-58.0, -24.0, 0.0)
	light.light_energy = 1.6
	light.shadow_enabled = true
	light.shadow_bias = 0.02
	light.shadow_normal_bias = 0.2
	light.shadow_opacity = 1.0
	light.directional_shadow_max_distance = 40.0
	light.directional_shadow_pancake_size = 16.0
	root_3d.add_child(light)

	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.78, 0.73, 0.62, 1.0)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.5, 0.47, 0.41, 1.0)
	environment.environment.ambient_light_energy = 0.45
	root_3d.add_child(environment)

	var tile_scene := load("res://scenes/path_tile_1x1.tscn") as PackedScene
	var tile := tile_scene.instantiate() as Node3D
	tile.position = Vector3.ZERO
	tile.set("shadow_darkness", 0.35)
	tile.set("shadow_receive_strength", 1.3)
	root_3d.add_child(tile)

	var caster := MeshInstance3D.new()
	caster.mesh = BoxMesh.new()
	caster.scale = Vector3(1.15, 0.9, 1.15)
	caster.position = Vector3(0.1, 0.85, -0.05)
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var caster_material := StandardMaterial3D.new()
	caster_material.albedo_color = Color(0.96, 0.63, 0.28, 1.0)
	caster.material_override = caster_material
	root_3d.add_child(caster)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 12:
		var image := root.get_texture().get_image()
		if image != null:
			image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
			print("PATH TILE SHADOW RENDER:", ProjectSettings.globalize_path(OUTPUT_PATH))
		quit()
		return true
	return false
