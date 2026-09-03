@tool
extends Control

const TEST_SCENE_PATH := "res://tests/shadertoy_dissolve_test.tscn"
const EFFECTS := [
	{
		"name": "디졸브 + 발광 · XdVBW1",
		"path": "res://resources/shadertoy_dissolve_test_material.tres",
		"detail": "Noxbuds Shadertoy의 3D SDF, 반사, FBM 디졸브를 Godot 전체 화면 셰이더로 옮긴 테스트입니다.",
	},
	{
		"name": "물",
		"path": "res://resources/lobby_water_material.tres",
		"detail": "테스트 씬 바닥에 적용된 기존 물 머티리얼입니다.",
	},
	{
		"name": "글로우",
		"path": "res://resources/shadertoy_test_environment.tres",
		"detail": "발광 경계의 블룸 강도를 결정하는 테스트 환경입니다.",
	},
]

var _picker: OptionButton
var _detail: Label


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
	var inspect := Button.new()
	inspect.text = "선택 리소스 Inspector에서 조절"
	inspect.pressed.connect(_inspect_selected)
	root.add_child(inspect)
	var open_test := Button.new()
	open_test.text = "Shadertoy 테스트 씬 열기"
	open_test.pressed.connect(_open_test_scene)
	root.add_child(open_test)
	_select_effect(0)


func _select_effect(index: int) -> void:
	_detail.text = EFFECTS[index]["detail"]


func _inspect_selected() -> void:
	var resource := load(EFFECTS[_picker.selected]["path"])
	if resource == null:
		push_error("Shader Admin resource could not be loaded")
		return
	EditorInterface.inspect_object(resource)


func _open_test_scene() -> void:
	EditorInterface.open_scene_from_path(TEST_SCENE_PATH)
