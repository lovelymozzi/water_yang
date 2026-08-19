@tool
extends Node3D

const LOBBY_GROUND_LAND_MATERIAL: StandardMaterial3D = preload("res://resources/lobby_ground_land_material.tres")
const LOBBY_GROUND_WATER_MATERIAL: StandardMaterial3D = preload("res://resources/lobby_ground_water_material.tres")

@export_group("Lobby Flower Glow")
@export_range(0.0, 8.0, 0.05) var flower_glow_energy_cap := 1.4
@export_range(0.1, 4.0, 0.05) var flower_glow_range_cap := 0.65


func _ready() -> void:
	var ground_mesh := get_node("LobbyGround/LobbyGround") as MeshInstance3D
	ground_mesh.set_surface_override_material(0, LOBBY_GROUND_LAND_MATERIAL)
	ground_mesh.set_surface_override_material(1, LOBBY_GROUND_WATER_MATERIAL)


func _process(_delta: float) -> void:
	for node in find_children("FlowerGlow", "OmniLight3D", true, false):
		var flower_glow := node as OmniLight3D
		flower_glow.light_energy = minf(flower_glow.light_energy, flower_glow_energy_cap)
		flower_glow.omni_range = minf(flower_glow.omni_range, flower_glow_range_cap)
