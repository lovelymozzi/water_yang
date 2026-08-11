@tool
extends Node3D

@export var flower_material: Material


func _ready() -> void:
	call_deferred("_apply_flower_material")


func _apply_flower_material() -> void:
	if flower_material == null:
		return
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
