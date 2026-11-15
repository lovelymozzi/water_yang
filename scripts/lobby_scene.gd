@tool
extends Node3D

const LOBBY_GROUND_LAND_MATERIAL: ShaderMaterial = preload("res://resources/lobby_ground_land_material.tres")
const LOBBY_GRASS_MATERIAL: ShaderMaterial = preload("res://resources/lobby_grass_material.tres")
const LOBBY_GROUND_WATER_MATERIAL: ShaderMaterial = preload("res://resources/lobby_ground_water_material.tres")
const LOBBY_WATER_MATERIAL: ShaderMaterial = preload("res://resources/lobby_water_material.tres")
const LOBBY_FOAM_COLOR := Color("66f8e0")

@export_group("Lobby Water")
@export_range(0.2, 4.0, 0.05) var underwater_depth := 0.8
@export_range(0.2, 1.0, 0.01) var underwater_density := 0.42

@export_group("Lobby Flower Glow")
@export_range(0.0, 8.0, 0.05) var flower_glow_energy_cap := 1.4
@export_range(0.1, 4.0, 0.05) var flower_glow_range_cap := 0.65


func _ready() -> void:
	_apply_lobby_materials()
	var water_mesh := get_node("LobbyGround/Water/water1") as MeshInstance3D
	var water_bounds := water_mesh.global_transform * water_mesh.get_aabb()
	var sparkles := get_node("WaterSparkles") as CPUParticles3D
	var shore_image: Image = LOBBY_WATER_MATERIAL.get_shader_parameter("shore_distance_map").get_image()
	var points := PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 91573
	# Keep the whole stationary glint clear of the actual cliff contact line.
	# Opaque terrain and cats still occlude these water-level particles in depth.
	for sample_index in 1024:
		var uv := Vector2(rng.randf_range(0.025, 0.975), rng.randf_range(0.05, 0.95))
		var pixel := Vector2i(uv * Vector2(shore_image.get_size()))
		if shore_image.get_pixelv(pixel).r * 2.0 < 0.55:
			continue
		points.append(Vector3((uv.x - 0.5) * water_bounds.size.x, 0.0, (uv.y - 0.5) * water_bounds.size.z))
	sparkles.global_position = water_bounds.get_center() + Vector3.UP * 0.035
	sparkles.emission_points = points
	sparkles.emitting = true


func _apply_lobby_materials() -> void:
	var sunlight := get_node("Camera3D/Sunlight").material_override as ShaderMaterial
	var sun_dust := get_node("Camera3D/SunDust") as CPUParticles3D
	var dust_material := sun_dust.mesh.material as ShaderMaterial
	# Keep the particle mask tied to the existing sunlight calibration.
	for parameter in ["light_color", "ray_sheet", "strength", "direction", "motion_speed", "vertical_fade"]:
		dust_material.set_shader_parameter(parameter, sunlight.get_shader_parameter(parameter))
	var ground_mesh := get_node("LobbyGround/LobbyGround") as MeshInstance3D
	var water_mesh := get_node("LobbyGround/Water/water1") as MeshInstance3D
	var underwater_mesh := get_node("UnderwaterIllustration") as MeshInstance3D
	var water_bounds := water_mesh.global_transform * water_mesh.get_aabb()
	var underwater_plane := underwater_mesh.mesh as PlaneMesh
	var underwater_size := Vector2(water_bounds.size.x, water_bounds.size.z)
	if not underwater_plane.size.is_equal_approx(underwater_size):
		underwater_plane.size = underwater_size
	underwater_mesh.global_position = water_bounds.get_center() - Vector3.UP * underwater_depth
	var underwater_material := underwater_mesh.material_override as ShaderMaterial
	var texture_size := (underwater_material.get_shader_parameter("illustration") as Texture2D).get_size()
	var illustration_scale := Vector2(
		underwater_size.x / (underwater_size.y * texture_size.aspect()), 1.0
	) * underwater_density
	underwater_material.set_shader_parameter("illustration_scale", illustration_scale)
	underwater_material.set_shader_parameter("illustration_offset", (Vector2.ONE - illustration_scale) * 0.5)
	underwater_material.set_shader_parameter("water_origin", Vector2(water_bounds.position.x, water_bounds.position.z))
	underwater_material.set_shader_parameter("water_size", underwater_size)
	ground_mesh.set_surface_override_material(0, LOBBY_GROUND_LAND_MATERIAL)
	ground_mesh.set_surface_override_material(1, LOBBY_GROUND_WATER_MATERIAL)
	water_mesh.material_override = LOBBY_WATER_MATERIAL
	LOBBY_WATER_MATERIAL.set_shader_parameter("water_origin", Vector2(water_bounds.position.x, water_bounds.position.z))
	LOBBY_WATER_MATERIAL.set_shader_parameter("water_size", underwater_size)
	water_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	LOBBY_WATER_MATERIAL.set_shader_parameter("ripple_color", LOBBY_FOAM_COLOR)
	LOBBY_GROUND_LAND_MATERIAL.set_shader_parameter("water_level", water_mesh.global_position.y)
	# Share the textured grass region; the lawn and each blade keep their own UV scale.
	for parameter in ["albedo_texture", "albedo_tint", "grass_use_texture_color", "grass_texture_region", "water_level", "shoreline_fade_height", "deep_fade_distance", "water_tint_strength", "shallow_water_color", "deep_water_color"]:
		for grass_material: ShaderMaterial in [LOBBY_GRASS_MATERIAL, LOBBY_GROUND_WATER_MATERIAL]:
			grass_material.set_shader_parameter(parameter, LOBBY_GROUND_LAND_MATERIAL.get_shader_parameter(parameter))
	# The cliff lip shares world UVs with the lawn; blades retain their authored UVs.
	for parameter in ["grass_world_uv", "albedo_uv_scale"]:
		LOBBY_GROUND_WATER_MATERIAL.set_shader_parameter(parameter, LOBBY_GROUND_LAND_MATERIAL.get_shader_parameter(parameter))
	# The atlas tint is a color gain; retain the serialized green outline.
	(LOBBY_GRASS_MATERIAL.next_pass as ShaderMaterial).set_shader_parameter("grass_wind_strength", LOBBY_GRASS_MATERIAL.get_shader_parameter("grass_wind_strength"))
	# The legacy painted shadow follows its visibility; real tree shadows now
	# shade both the lawn and blades, as in gameplay.
	var tree_shadow := get_node("LevelManager/TileVisuals/TreeShadowDecor") as Sprite3D
	for grass_pass: ShaderMaterial in [LOBBY_GRASS_MATERIAL, LOBBY_GRASS_MATERIAL.next_pass]:
		grass_pass.set_shader_parameter("grass_shadow_enabled", tree_shadow.visible)
		grass_pass.set_shader_parameter("grass_shadow_texture", tree_shadow.texture)
		grass_pass.set_shader_parameter("grass_shadow_inverse", tree_shadow.global_transform.affine_inverse())
		grass_pass.set_shader_parameter("grass_shadow_size", tree_shadow.texture.get_size() * tree_shadow.pixel_size)
		grass_pass.set_shader_parameter("grass_shadow_tint", tree_shadow.modulate)
	for decoration in get_node("LevelManager/TileVisuals").get_children():
		if decoration.scene_file_path != "res://scenes/grass_decor.tscn":
			continue
		for grass_mesh: MeshInstance3D in decoration.find_children("*", "MeshInstance3D", true, false):
			grass_mesh.material_override = LOBBY_GRASS_MATERIAL
			grass_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			grass_mesh.extra_cull_margin = 0.06


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		var grass_time := float(LOBBY_GRASS_MATERIAL.get_shader_parameter("grass_wind_time")) + delta
		LOBBY_GRASS_MATERIAL.set_shader_parameter("grass_wind_time", grass_time)
		(LOBBY_GRASS_MATERIAL.next_pass as ShaderMaterial).set_shader_parameter("grass_wind_time", grass_time)
		_apply_lobby_materials()
	for node in find_children("FlowerGlow", "OmniLight3D", true, false):
		var flower_glow := node as OmniLight3D
		flower_glow.light_energy = minf(flower_glow.light_energy, flower_glow_energy_cap)
		flower_glow.omni_range = minf(flower_glow.omni_range, flower_glow_range_cap)
