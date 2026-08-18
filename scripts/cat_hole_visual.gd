@tool
extends Node3D

# 탈출구 한 개의 비주얼. cat_hole1.fbx 는 메시 하나에 "flower"(테두리)와
# "hole"(가운데 구덩이) 두 서피스를 갖고 있어, 표면 이름으로 재질을 갈아끼운다.
#
# 색의 출처가 둘로 갈리지 않게 역할을 나눠 둔다.
#   - 스타일(툰 단계, 그림자, 림, 라인아트, 아웃라인 색/비율)은 `CatAppearance` 하나에서 오고
#     움직이는 고양이와 공유한다. 아웃라인 폭은 `CatEntity.cat_hole_outline_width`로 따로 관리한다.
#   - 색만 구멍마다 다르다. `LevelManager.pair_colors` 의 짝 색이며 LevelManager 가
#     `apply_hole_colors()` 로 넣어 준다. 이 값이 `CatAppearance.tint_color` 를 덮는다.
#     짝 색이 표시색을 못 이기면 플레이어가 짝을 볼 수 없다.

const FLOWER_SURFACE_NAME := "flower"
const HOLE_SURFACE_NAME := "hole"
const HOLE_TEXTURE := preload("res://water_yang/hole1.jpg")
const HOLE_SPIN_SHADER := preload("res://scripts/hole_spin.gdshader")
const HOLE_ROTATION_DURATION := 4.0

# CatHole only: keep enough toon shading for its rotating flower to read as a
# solid object, even when the matching cat's runtime style is very flat.
@export_range(0.0, 1.0, 0.01) var flower_shadow_darkness := 0.32

@export var flower_material: Material:
	set(value):
		flower_material = value
		_request_apply()

@export var appearance: CatAppearance:
	set(value):
		if appearance != null and appearance.changed.is_connected(_request_apply):
			appearance.changed.disconnect(_request_apply)
		appearance = value
		if appearance != null:
			appearance.changed.connect(_request_apply)
		_request_apply()

var _pair_color := Color(1.0, 1.0, 1.0, 1.0)
var _pit_color := Color(0.06, 0.07, 0.05, 1.0)
var _has_pair_color := false
var _cat_visual_style: Dictionary = {}
var _pit_material: ShaderMaterial


func _ready() -> void:
	call_deferred("_apply_surface_materials")


# LevelManager 가 구멍마다 한 번 부른다. 꽃잎과 구덩이 색이 같은 color_id 에서
# 나와야 하므로 둘을 함께 받는다.
func apply_hole_colors(flower_color: Color, pit_color: Color) -> void:
	_pair_color = flower_color
	_pit_color = pit_color
	_has_pair_color = true
	_apply_surface_materials()


# The LevelManager finds the layout cat with the same color_id and gives its
# effective shader settings to this hole.  This preserves per-cat CatHole outline
# width and toon choices rather than forcing every hole to use the shared fallback.
func apply_cat_visual_style(style: Dictionary) -> void:
	_cat_visual_style = style.duplicate()
	_apply_surface_materials()


# Used by the regression check to verify that a runtime cat edit reached the
# exact material-style snapshot consumed by this CatHole.
func get_applied_outline_width() -> float:
	return float(_cat_visual_style.get("outline_width", -1.0))


# 에셋 크기와 무관하게 정확히 한 칸을 덮게 맞춘다. 타일 크기를 바꿔도 따라간다.
func fit_to_tile(tile_side: float) -> void:
	var mesh_instance := _find_mesh_instance(self)
	if mesh_instance == null or mesh_instance.mesh == null:
		return

	# 메시 로컬 AABB 를 메시 노드 변환까지 태워야 FBX 의 Z-up 회전이 반영된다.
	var bounds: AABB = mesh_instance.transform * mesh_instance.mesh.get_aabb()
	var footprint: float = maxf(bounds.size.x, bounds.size.z)
	if footprint <= 0.0001:
		return

	scale = Vector3.ONE * (tile_side / footprint)


func _request_apply() -> void:
	if not is_inside_tree():
		return
	call_deferred("_apply_surface_materials")


func _apply_surface_materials() -> void:
	_apply_to_meshes(self, _build_flower_material(), _build_pit_material())


func _apply_to_meshes(node: Node, flower: Material, hole: Material) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var source_material := mesh_instance.mesh.surface_get_material(surface_index)
				if source_material == null:
					continue
				match source_material.resource_name.to_lower():
					FLOWER_SURFACE_NAME:
						if flower != null:
							mesh_instance.set_surface_override_material(surface_index, flower)
					HOLE_SURFACE_NAME:
						if hole != null:
							mesh_instance.set_surface_override_material(surface_index, hole)
	for child in node.get_children():
		_apply_to_meshes(child, flower, hole)


# 원본 재질은 모든 구멍이 공유한다. 구멍마다 색이 달라야 하므로 복제한 뒤 칠한다.
# 복제하지 않고 공유 재질에 쓰면 마지막 구멍의 색이 넷 다에 적용된다.
func _build_flower_material() -> Material:
	if flower_material == null:
		return null

	var tinted := flower_material.duplicate() as ShaderMaterial
	if tinted == null:
		return flower_material

	if appearance != null:
		tinted.set_shader_parameter("tint_color", appearance.tint_color)
		tinted.set_shader_parameter("shadow_steps", appearance.toon_steps)
		tinted.set_shader_parameter("shadow_darkness", appearance.shadow_darkness)
		tinted.set_shader_parameter("rim_strength", appearance.rim_strength)
		tinted.set_shader_parameter("line_art_tex", appearance.line_art_texture)
		tinted.set_shader_parameter(
			"line_art_enabled", 1.0 if appearance.line_art_texture != null else 0.0
		)
		tinted.set_shader_parameter("line_art_color", appearance.line_art_color)
		tinted.set_shader_parameter("line_art_strength", appearance.line_art_strength)

	# The pair color remains the fallback for levels without a matching layout
	# cat.  A matching cat's full style below takes precedence.
	if _has_pair_color:
		tinted.set_shader_parameter("tint_color", _pair_color)
	_apply_toon_style(tinted)
	# Apply this after the paired cat's style.  The level currently gives cats a
	# very low shadow value, which otherwise makes CatHole's surface shading
	# effectively disappear.
	tinted.set_shader_parameter("shadow_darkness", flower_shadow_darkness)

	var outline := tinted.next_pass as ShaderMaterial
	if outline != null:
		# The outline style comes from the matching cat. Its width is independently
		# controlled by CatEntity.cat_hole_outline_width because this FBX is nearly
		# flat and needs a different visual weight from the movable cat.
		var outline_copy := outline.duplicate() as ShaderMaterial
		if appearance != null:
			outline_copy.set_shader_parameter("outline_color", appearance.outline_color)
			outline_copy.set_shader_parameter("outline_width", appearance.outline_width)
			outline_copy.set_shader_parameter("top_outline_scale", appearance.top_outline_scale)
			outline_copy.set_shader_parameter("bottom_outline_scale", appearance.bottom_outline_scale)
		_apply_outline_style(outline_copy)
		tinted.next_pass = outline_copy

	return tinted


func _apply_toon_style(material: ShaderMaterial) -> void:
	if _cat_visual_style.is_empty():
		return
	for parameter in [
		"tint_color", "toon_steps", "shadow_darkness", "rim_strength",
		"line_art_tex", "line_art_eye_mask", "line_art_enabled",
		"line_art_color", "line_art_strength", "tint_exclusion_mask",
		"tint_exclusion_enabled",
	]:
		material.set_shader_parameter(parameter, _cat_visual_style[parameter])


func _apply_outline_style(material: ShaderMaterial) -> void:
	if _cat_visual_style.is_empty():
		return
	for parameter in [
		"outline_color", "outline_width", "top_outline_scale", "bottom_outline_scale",
	]:
		material.set_shader_parameter(parameter, _cat_visual_style[parameter])


func _build_pit_material() -> Material:
	if not _has_pair_color:
		return null

	if _pit_material == null:
		_pit_material = ShaderMaterial.new()
		_pit_material.shader = HOLE_SPIN_SHADER
		_pit_material.set_shader_parameter("albedo_tex", HOLE_TEXTURE)
		_pit_material.set_shader_parameter("rotation_duration", HOLE_ROTATION_DURATION)
	return _pit_material


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null
