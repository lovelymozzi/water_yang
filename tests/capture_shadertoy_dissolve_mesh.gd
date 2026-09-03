extends SceneTree

const OUTPUT_PATH := "user://shadertoy_dissolve_mesh.png"
const DISSOLVE_MATERIAL := preload("res://resources/shadertoy_dissolve_mesh_material.tres")

var _frames := 0


func _initialize() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 4.0)
	scene.add_child(camera)
	var mesh := MeshInstance3D.new()
	mesh.mesh = SphereMesh.new()
	var material := DISSOLVE_MATERIAL.duplicate() as ShaderMaterial
	material.set_shader_parameter("dissolve_speed", 0.0)
	mesh.material_override = material
	scene.add_child(mesh)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 180:
		root.get_texture().get_image().save_png(OUTPUT_PATH)
		print("[shadertoy-dissolve-mesh] ", ProjectSettings.globalize_path(OUTPUT_PATH))
		quit()
	return false
