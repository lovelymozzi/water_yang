@tool
extends Node3D

@export var flower_material: Material
@export var appearance: CatAppearance:
	set(value):
		if appearance != null and appearance.changed.is_connected(_apply_appearance):
			appearance.changed.disconnect(_apply_appearance)
		appearance = value
		if appearance != null:
			appearance.changed.connect(_apply_appearance)
		_apply_appearance()


func _ready() -> void:
	call_deferred("_apply_flower_material")


func _apply_flower_material() -> void:
	if flower_material == null:
		return
	_apply_to_meshes(self)
	_apply_appearance()


func _apply_appearance() -> void:
	if appearance == null or not flower_material is ShaderMaterial:
		return
	var toon_material := flower_material as ShaderMaterial
	toon_material.set_shader_parameter("tint_color", appearance.tint_color)
	toon_material.set_shader_parameter("shadow_steps", appearance.toon_steps)
	toon_material.set_shader_parameter("shadow_darkness", appearance.shadow_darkness)
	toon_material.set_shader_parameter("rim_strength", appearance.rim_strength)
	toon_material.set_shader_parameter("line_art_tex", appearance.line_art_texture)
	toon_material.set_shader_parameter("line_art_enabled", 1.0 if appearance.line_art_texture != null else 0.0)
	toon_material.set_shader_parameter("line_art_color", appearance.line_art_color)
	toon_material.set_shader_parameter("line_art_strength", appearance.line_art_strength)
	var outline_material := toon_material.next_pass as ShaderMaterial
	if outline_material != null:
		# CatHole uses the same shared outline settings as Cat2. Its shader only
		# changes the expansion direction because this FBX is almost flat.
		outline_material.set_shader_parameter("outline_color", appearance.outline_color)
		outline_material.set_shader_parameter("outline_width", appearance.outline_width)
		outline_material.set_shader_parameter("top_outline_scale", appearance.top_outline_scale)
		outline_material.set_shader_parameter("bottom_outline_scale", appearance.bottom_outline_scale)
	# Reassign the override so @tool previews refresh after an external resource
	# changes. Updating a shared ShaderMaterial alone can leave the editor's
	# imported-FBX render instance stale.
	if is_inside_tree():
		_apply_to_meshes(self)


func _apply_to_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var source_material := mesh_instance.mesh.surface_get_material(surface_index)
				if source_material != null and source_material.resource_name.to_lower() == "flower":
					mesh_instance.set_surface_override_material(surface_index, flower_material)
	for child in node.get_children():
		_apply_to_meshes(child)
