@tool
extends VBoxContainer

## Inspector-local authoring UI. Changes are recorded through Godot's
## EditorUndoRedoManager, so they save with the scene and can be undone.

const MAX_PALETTE_COLORS := 32
const DEFAULT_NEW_COLOR := Color("#FFFFFF")

var _manager: LevelManager
var _undo_redo: EditorUndoRedoManager
var _swatches: GridContainer
var _color_picker: ColorPickerButton
var _status: Label
var _shader_controls: VBoxContainer
var _selected_index := 0
var _updating := false


func configure(manager: LevelManager, undo_redo: EditorUndoRedoManager) -> void:
	_manager = manager
	_undo_redo = undo_redo
	_build_ui()
	_rebuild_swatches()
	_sync_shader_controls()


func _build_ui() -> void:
	add_theme_constant_override("separation", 6)
	var separator := HSeparator.new()
	add_child(separator)
	var title := Label.new()
	title.text = "CAT & HOLE PALETTE STUDIO"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)
	var hint := Label.new()
	hint.text = "같은 색 ID의 고양이와 홀이 함께 갱신됩니다."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.72, 0.78, 0.86)
	add_child(hint)

	_swatches = GridContainer.new()
	_swatches.columns = 4
	_swatches.add_theme_constant_override("h_separation", 4)
	_swatches.add_theme_constant_override("v_separation", 4)
	add_child(_swatches)
	var color_row := HBoxContainer.new()
	add_child(color_row)
	_color_picker = ColorPickerButton.new()
	_color_picker.custom_minimum_size = Vector2(52, 28)
	_color_picker.color_changed.connect(_on_color_changed)
	color_row.add_child(_color_picker)
	var add := Button.new()
	add.text = "+ 추가"
	add.pressed.connect(_add_color)
	color_row.add_child(add)
	var remove := Button.new()
	remove.text = "선택 삭제"
	remove.pressed.connect(_remove_selected_color)
	color_row.add_child(remove)

	var shader_separator := HSeparator.new()
	add_child(shader_separator)
	var shader_title := Label.new()
	shader_title.text = "공통 셰이더 미리보기"
	add_child(shader_title)
	_shader_controls = VBoxContainer.new()
	_shader_controls.add_theme_constant_override("separation", 3)
	add_child(_shader_controls)
	_add_shader_slider("그림자", "shadow_darkness", 0.0, 1.0, 0.01)
	_add_shader_slider("림 라이트", "rim_strength", 0.0, 1.0, 0.01)
	_add_shader_slider("외곽선", "outline_width", 0.001, 0.04, 0.001)
	_add_shader_slider("라인 강도", "line_art_strength", 0.0, 1.0, 0.01)
	var steps := OptionButton.new()
	steps.name = "toon_steps"
	for value in range(2, 6):
		steps.add_item("툰 단계 %d" % value, value)
	steps.item_selected.connect(_on_toon_steps_selected)
	_shader_controls.add_child(steps)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(0.62, 0.86, 0.68)
	add_child(_status)


func _add_shader_slider(label_text: String, property_name: String, minimum: float, maximum: float, step: float) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 70
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = property_name
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_shader_value_changed.bind(property_name))
	row.add_child(slider)
	_shader_controls.add_child(row)


func _rebuild_swatches() -> void:
	for child in _swatches.get_children():
		child.queue_free()
	var colors := _manager.pair_colors
	_selected_index = clampi(_selected_index, 0, max(0, colors.size() - 1))
	for index in colors.size():
		var button := Button.new()
		button.text = "%02d" % (index + 1)
		button.tooltip_text = "색상 ID %d" % index
		button.custom_minimum_size = Vector2(48, 31)
		var style := StyleBoxFlat.new()
		style.bg_color = colors[index]
		style.corner_radius_top_left = 5
		style.corner_radius_top_right = 5
		style.corner_radius_bottom_left = 5
		style.corner_radius_bottom_right = 5
		style.border_color = Color.WHITE if index == _selected_index else Color(0.1, 0.1, 0.1)
		style.set_border_width_all(3 if index == _selected_index else 1)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_color_override("font_color", Color.BLACK if colors[index].get_luminance() > 0.58 else Color.WHITE)
		button.pressed.connect(_select_color.bind(index))
		_swatches.add_child(button)
	_updating = true
	_color_picker.color = colors[_selected_index] if not colors.is_empty() else DEFAULT_NEW_COLOR
	_updating = false
	_status.text = "선택 ID %d · 팔레트 %d색 · Undo/Redo 지원" % [_selected_index, colors.size()]


func _select_color(index: int) -> void:
	_selected_index = index
	_rebuild_swatches()


func _on_color_changed(color: Color) -> void:
	if _updating or _selected_index >= _manager.pair_colors.size():
		return
	var next := _manager.pair_colors
	next[_selected_index] = color
	_commit_property("고양이 & 홀 색상 변경", "pair_colors", next)
	_rebuild_swatches()


func _add_color() -> void:
	var next := _manager.pair_colors
	if next.size() >= MAX_PALETTE_COLORS:
		_status.text = "최대 %d개까지 추가할 수 있습니다." % MAX_PALETTE_COLORS
		return
	next.append(_color_picker.color if not next.is_empty() else DEFAULT_NEW_COLOR)
	_commit_property("고양이 & 홀 색상 추가", "pair_colors", next)
	_selected_index = next.size() - 1
	_rebuild_swatches()


func _remove_selected_color() -> void:
	var next := _manager.pair_colors
	if next.size() <= 1:
		_status.text = "최소 한 개의 색상은 유지합니다."
		return
	next.remove_at(_selected_index)
	_commit_property("고양이 & 홀 색상 삭제", "pair_colors", next)
	_selected_index = maxi(0, _selected_index - 1)
	_rebuild_swatches()


func _on_shader_value_changed(value: float, property_name: String) -> void:
	if not _updating:
		_commit_shader_property(property_name, value)


func _on_toon_steps_selected(index: int) -> void:
	if not _updating:
		_commit_shader_property("toon_steps", index + 2)


func _commit_property(action_name: String, property_name: String, value: Variant) -> void:
	var previous: Variant = _manager.get(property_name)
	_undo_redo.create_action(action_name)
	_undo_redo.add_do_property(_manager, property_name, value)
	_undo_redo.add_undo_property(_manager, property_name, previous)
	_undo_redo.commit_action()


func _commit_shader_property(property_name: String, value: Variant) -> void:
	var cats := _layout_cats()
	if cats.is_empty():
		return
	_undo_redo.create_action("고양이 & 홀 셰이더 조정")
	for cat in cats:
		var previous: Variant = cat.get(property_name)
		_undo_redo.add_do_property(cat, property_name, value)
		_undo_redo.add_undo_property(cat, property_name, previous)
	_undo_redo.commit_action()
	_manager.request_preview_refresh()
	_status.text = "%s 조정됨 · 고양이와 홀 미리보기 갱신" % property_name


func _sync_shader_controls() -> void:
	var cats := _layout_cats()
	if cats.is_empty():
		return
	var cat := cats[0]
	_updating = true
	for child in _shader_controls.get_children():
		if child is HBoxContainer:
			var slider := child.get_child(1) as HSlider
			slider.value = float(cat.get(slider.name))
	var steps := _shader_controls.get_node_or_null("toon_steps") as OptionButton
	if steps != null:
		steps.select(clampi(cat.toon_steps - 2, 0, 3))
	_updating = false


func _layout_cats() -> Array[CatEntity]:
	var result: Array[CatEntity] = []
	var layout := _manager.get_node_or_null("LayoutCats")
	if layout == null:
		return result
	for child in layout.get_children():
		if child is CatEntity:
			result.append(child as CatEntity)
	return result
