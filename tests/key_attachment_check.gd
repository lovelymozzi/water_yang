extends SceneTree

# Runtime verification for the orange cat's key attachment.
# Run with:
#   Godot --headless --path . --script tests/key_attachment_check.gd

var _scene: Node3D
var _frames := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_scene = (load("res://scenes/main_scene.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 20:
		return false

	var manager := _scene.get_node_or_null("LevelManager") as LevelManager
	var camera := _scene.get_node_or_null("Camera3D") as Camera3D
	if manager == null:
		_failures.append("LevelManager missing")
	elif camera == null:
		_failures.append("Camera3D missing")
	else:
		var orange_cats: Array[CatEntity] = []
		for cat in manager.get_cats():
			if cat is CatEntity and (cat as CatEntity).color_id == 0:
				orange_cats.append(cat as CatEntity)
		if orange_cats.is_empty():
			_failures.append("No runtime orange cat (color_id 0)")
		for cat in orange_cats:
			var attachment := cat._skeleton.get_node_or_null("NeckKeyAttachment") as BoneAttachment3D
			var key := attachment.get_node_or_null("Key") as Node3D if attachment != null else null
			var mesh := key.get_node_or_null("key1") as MeshInstance3D if key != null else null
			if attachment == null:
				_failures.append("%s: Bone004 attachment missing" % cat.name)
				continue
			if attachment.bone_name != "Bone004":
				_failures.append("%s: attachment bone is %s" % [cat.name, attachment.bone_name])
			if key == null or mesh == null:
				_failures.append("%s: key node or mesh missing" % cat.name)
				continue
			var screen := camera.unproject_position(mesh.global_position)
			print("[key] cat=", cat.name,
				" bone_world=", attachment.global_position,
				" key_local=", key.position,
				" key_world=", key.global_position,
				" mesh_local=", mesh.position,
				" mesh_world=", mesh.global_position,
				" screen=", screen,
				" behind_camera=", camera.is_position_behind(mesh.global_position),
				" visible=", mesh.is_visible_in_tree())
			if camera.is_position_behind(mesh.global_position):
				_failures.append("%s: key is behind the camera" % cat.name)
			if not mesh.is_visible_in_tree():
				_failures.append("%s: key mesh is hidden" % cat.name)
			if mesh.global_position.y <= cat.global_position.y + 0.5:
				_failures.append("%s: key is not sufficiently above the cat mesh" % cat.name)
			var material := mesh.material_override as ShaderMaterial
			if material == null or material.shader.resource_path != "res://scripts/key_toon.gdshader":
				_failures.append("%s: cat-style key toon material is missing" % cat.name)
			elif material.next_pass == null:
				_failures.append("%s: cat-style key outline pass is missing" % cat.name)
			elif material.get_shader_parameter("albedo_tex") == null:
				_failures.append("%s: cat1.jpeg is not assigned to the key toon material" % cat.name)

	if _failures.is_empty():
		print("KEY ATTACHMENT CHECK: PASS")
		quit()
		return true
	print("KEY ATTACHMENT CHECK: FAIL (%d)" % _failures.size())
	for failure in _failures:
		print("  - ", failure)
	quit(1)
	return true
