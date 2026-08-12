@tool
extends TextureRect

## Screen-space fog controls. All position values are viewport-height ratios.
@export_group("Top Fog")
@export_range(0.0, 1.0, 0.01) var screen_y := 0.0:
	set(value):
		screen_y = value
		_apply_fog()

@export_range(0.05, 1.0, 0.01) var height_ratio := 0.34:
	set(value):
		height_ratio = value
		_apply_fog()

@export_range(0.0, 1.0, 0.01) var density := 0.46:
	set(value):
		density = value
		_apply_fog()

@export_range(0.0, 1.0, 0.01) var fade_start := 0.42:
	set(value):
		fade_start = value
		_apply_fog()

@export var fog_color := Color(0.842, 0.927, 0.785, 1.0):
	set(value):
		fog_color = value
		_apply_fog()


# Duplicating a fog Control in the editor can leave both nodes pointing at
# the same GradientTexture2D. Keep a private copy before modifying its
# gradient so each fog node has an independent color and density.
var _gradient_isolated := false


func _ready() -> void:
	_apply_fog()


func _apply_fog() -> void:
	if not is_inside_tree():
		return

	anchor_top = screen_y
	anchor_bottom = minf(screen_y + height_ratio, 1.0)

	var gradient_texture := _get_local_gradient_texture()
	if gradient_texture == null or gradient_texture.gradient == null:
		return

	var gradient := gradient_texture.gradient
	gradient.set_offset(1, fade_start)
	gradient.set_color(0, Color(fog_color.r, fog_color.g, fog_color.b, density))
	gradient.set_color(1, Color(fog_color.r, fog_color.g, fog_color.b, density * 0.43))
	gradient.set_color(2, Color(fog_color.r, fog_color.g, fog_color.b, 0.0))


func _get_local_gradient_texture() -> GradientTexture2D:
	var gradient_texture := texture as GradientTexture2D
	if gradient_texture == null:
		return null
	if not _gradient_isolated:
		gradient_texture = gradient_texture.duplicate(true) as GradientTexture2D
		texture = gradient_texture
		_gradient_isolated = true
	return gradient_texture
