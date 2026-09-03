@tool
extends Control

const TEST_SCENE_PATH := "res://tests/shadertoy_dissolve_test.tscn"
const EFFECTS := [
	{
		"name": "디졸브 + 발광 · XdVBW1 (선택 Mesh)",
		"path": "res://resources/shadertoy_dissolve_mesh_material.tres",
		"detail": "선택한 MeshInstance3D에 적용하는 Shadertoy식 노이즈 디졸브입니다.",
		"edge_parameters": ["edge_color"],
	},
	{
		"name": "디졸브 + 발광 · XdVBW1 (테스트 화면)",
		"path": "res://resources/shadertoy_dissolve_test_material.tres",
		"detail": "Noxbuds Shadertoy의 3D SDF, 반사, FBM 디졸브를 Godot 전체 화면 셰이더로 옮긴 테스트입니다.",
		"edge_parameters": ["cyan_edge_color", "yellow_edge_color"],
	},
	{
		"name": "물",
		"path": "res://resources/lobby_water_material.tres",
		"detail": "테스트 씬 바닥에 적용된 기존 물 머티리얼입니다.",
	},
	{
		"name": "글로우",
		"path": "res://resources/shadertoy_dissolve_bloom_material.tres",
		"detail": "원본 Image 패스의 21 × 21 블룸 커널입니다.",
	},
]

var _picker: OptionButton
var _detail: Label
var _edge_colors: VBoxContainer
var _primary_picker: ColorPickerButton
var _secondary_picker: ColorPickerButton
var _status: Label
var _undo_redo: EditorUndoRedoManager
var _updating := false


func configure(undo_redo: EditorUndoRedoManager) -> void:
	_undo_redo = undo_redo


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var title := Label.new()
	title.text = "Shader Admin"
	title.add_theme_font_size_override("font_size", 24)
	root.add_child(title)
	var reference := LinkButton.new()
	reference.text = "원본: Shadertoy / XdVBW1 / Dissolve Effects"
	reference.uri = "https://www.shadertoy.com/view/XdVBW1"
	root.add_child(reference)
	_picker = OptionButton.new()
	for effect in EFFECTS:
		_picker.add_item(effect["name"])
	_picker.item_selected.connect(_select_effect)
	root.add_child(_picker)
	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_detail)
	_edge_colors = VBoxContainer.new()
	root.add_child(_edge_colors)
	_primary_picker = _add_color_picker("가장자리 색", 0)
	_secondary_picker = _add_color_picker("보조 가장자리 색", 1)
	var inspect := Button.new()
	inspect.text = "선택 리소스 Inspector에서 조절"
	inspect.pressed.connect(_inspect_selected)
	root.add_child(inspect)
	var apply := Button.new()
	apply.text = "선택 Mesh에 적용"
	apply.tooltip_text = "씬 트리에서 선택한 MeshInstance3D에 현재 효과를 Material Override로 적용합니다."
	apply.pressed.connect(_apply_to_selected_meshes)
	root.add_child(apply)
	var open_test := Button.new()
	open_test.text = "Shadertoy 테스트 씬 열기"
	open_test.pressed.connect(_open_test_scene)
	root.add_child(open_test)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)
	_select_effect(0)


func _select_effect(index: int) -> void:
	_detail.text = EFFECTS[index]["detail"]
	var parameters: Array = EFFECTS[index].get("edge_parameters", [])
	_edge_colors.visible = not parameters.is_empty()
	_secondary_picker.get_parent().visible = parameters.size() > 1
	if _edge_colors.visible:
		_sync_edge_colors()


func _add_color_picker(label_text: String, parameter_index: int) -> ColorPickerButton:
	var row := HBoxContainer.new()
	_edge_colors.add_child(row)
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(44, 26)
	picker.color_changed.connect(_set_edge_color.bind(parameter_index))
	row.add_child(picker)
	return picker


func _sync_edge_colors() -> void:
	var material := load(EFFECTS[_picker.selected]["path"]) as ShaderMaterial
	if material == null:
		return
	var parameters: Array = EFFECTS[_picker.selected]["edge_parameters"]
	_updating = true
	_primary_picker.color = material.get_shader_parameter(parameters[0])
	if parameters.size() > 1:
		_secondary_picker.color = material.get_shader_parameter(parameters[1])
	_updating = false


func _set_edge_color(color: Color, parameter_index: int) -> void:
	if _updating or _undo_redo == null:
		return
	var material := load(EFFECTS[_picker.selected]["path"]) as ShaderMaterial
	if material == null:
		return
	var parameters: Array = EFFECTS[_picker.selected].get("edge_parameters", [])
	if parameter_index >= parameters.size():
		return
	var parameter: String = parameters[parameter_index]
	var previous := material.get_shader_parameter(parameter)
	_undo_redo.create_action("Shadertoy 가장자리 색 변경")
	_undo_redo.add_do_method(material, "set_shader_parameter", parameter, color)
	_undo_redo.add_undo_method(material, "set_shader_parameter", parameter, previous)
	_undo_redo.commit_action()


func _inspect_selected() -> void:
	var resource := load(EFFECTS[_picker.selected]["path"])
	if resource == null:
		push_error("Shader Admin resource could not be loaded")
		return
	EditorInterface.inspect_object(resource)


func _apply_to_selected_meshes() -> void:
	var source := load(EFFECTS[_picker.selected]["path"]) as Material
	if source == null:
		_status.text = "선택 효과를 불러오지 못했습니다."
		return
	var meshes: Array[MeshInstance3D] = []
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node is MeshInstance3D:
			meshes.append(node)
	if meshes.is_empty():
		_status.text = "씬 트리에서 MeshInstance3D를 먼저 선택하세요."
		return
	_undo_redo.create_action("Shader Admin: 선택 Mesh에 효과 적용")
	for mesh in meshes:
		var material := source.duplicate() as Material
		if material is ShaderMaterial:
			var parameters: Array = EFFECTS[_picker.selected].get("edge_parameters", [])
			if not parameters.is_empty():
				(material as ShaderMaterial).set_shader_parameter(parameters[0], _primary_picker.color)
			if parameters.size() > 1:
				(material as ShaderMaterial).set_shader_parameter(parameters[1], _secondary_picker.color)
		_undo_redo.add_do_property(mesh, "material_override", material)
		_undo_redo.add_undo_property(mesh, "material_override", mesh.material_override)
		_undo_redo.add_do_reference(material)
	_undo_redo.commit_action()
	_status.text = "%d개 Mesh에 적용했습니다. Ctrl+Z로 되돌릴 수 있습니다." % meshes.size()


func _open_test_scene() -> void:
	EditorInterface.open_scene_from_path(TEST_SCENE_PATH)
