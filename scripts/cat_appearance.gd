@tool
class_name CatAppearance
extends Resource

## Shared visual settings for all cat-shaped objects.
## Update this resource to keep movable cats and cat holes visually consistent.

@export_group("Toon Shader")
@export var tint_color: Color = Color(0.95577335, 0.8633, 0.97, 1.0):
	set(value):
		tint_color = value
		emit_changed()

@export_range(2, 5, 1) var toon_steps: int = 3:
	set(value):
		toon_steps = value
		emit_changed()

@export_range(0.0, 1.0, 0.01) var shadow_darkness: float = 0.0:
	set(value):
		shadow_darkness = value
		emit_changed()

@export_range(0.0, 1.0, 0.01) var rim_strength: float = 0.39:
	set(value):
		rim_strength = value
		emit_changed()

@export_group("Outline")
@export var outline_color: Color = Color(0.69, 0.565225, 0.4761, 0.6627451):
	set(value):
		outline_color = value
		emit_changed()

@export_range(0.001, 0.04, 0.001) var outline_width: float = 0.006:
	set(value):
		outline_width = value
		emit_changed()

@export_range(0.4, 1.2, 0.01) var top_outline_scale: float = 0.78:
	set(value):
		top_outline_scale = value
		emit_changed()

@export_range(0.8, 1.6, 0.01) var bottom_outline_scale: float = 0.84:
	set(value):
		bottom_outline_scale = value
		emit_changed()

@export_group("Internal Line Art")
@export var line_art_texture: Texture2D:
	set(value):
		line_art_texture = value
		emit_changed()

@export var line_art_color: Color = Color(0.2679695, 0.19882667, 0.1625919, 1.0):
	set(value):
		line_art_color = value
		emit_changed()

@export_range(0.0, 1.0, 0.01) var line_art_strength: float = 1.0:
	set(value):
		line_art_strength = value
		emit_changed()
