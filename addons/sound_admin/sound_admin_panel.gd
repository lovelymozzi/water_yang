@tool
extends Control

const SOUND_DIR := "res://src/sound"
const EXTENSIONS := ["mp3", "ogg", "wav", "flac"]
const SOUND_ROLES := {
	"floraphonic-casual-click-pop-ui-3-262120_optimized.mp3": "웹 UI 버튼 클릭 / 첫 입력 오디오 권한 해제",
	"stu9-cute-cat-352656_optimized.mp3": "고양이 입 열기 효과음",
	"gargamel10-teleport-game-sound-effect-379236_optimized.mp3": "고양이가 짝 구멍에 흡수될 때",
	"geoffharvey-fat-cat-374614_optimized.mp3": "로비 진입·복귀 BGM",
	"loswin23-bird-chirping-567995_optimized.mp3": "인게임 진입·설정에서 켤 때 BGM",
}
const BINDINGS := [
	{"id": "button", "label": "UI 버튼 클릭", "when": "모든 UI 버튼 터치", "targets": [{"path": "res://godot-shell.html", "marker": "const BUTTON_CLICK_SFX =", "prefix": "./sound/"}]},
	{"id": "mouth", "label": "고양이 입 열기", "when": "고양이가 입을 열 때", "targets": [{"path": "res://godot-shell.html", "marker": "const CAT_MOUTH_SFX =", "prefix": "./sound/"}]},
	{"id": "absorb", "label": "고양이 구멍 흡수", "when": "짝 구멍으로 들어갈 때", "targets": [{"path": "res://godot-shell.html", "marker": "const CAT_HOLE_ABSORB_SFX =", "prefix": "./sound/"}, {"path": "res://scripts/cat_entity.gd", "marker": "const ABSORB_SOUND := preload(", "prefix": "res://src/sound/"}]},
	{"id": "lobby_bgm", "label": "로비 BGM", "when": "로비 진입·복귀", "targets": [{"path": "res://godot-shell.html", "marker": "const LOBBY_BGM =", "prefix": "./sound/"}]},
	{"id": "ingame_bgm", "label": "인게임 BGM", "when": "인게임 진입 또는 설정에서 활성화", "targets": [{"path": "res://godot-shell.html", "marker": "const INGAME_BGM =", "prefix": "./sound/"}]},
]

var _paths := PackedStringArray()
var _usages: Dictionary = {}
var _selected := -1
var _list: SoundList
var _info: RichTextLabel
var _status: Label
var _name: LineEdit
var _preview: AudioStreamPlayer
var _volume: HSlider
var _picker: FileDialog
var _confirm: ConfirmationDialog
var _rename_dialog: ConfirmationDialog
var _rename_input: LineEdit
var _rename_target := ""
var _pending: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_refresh()


func _exit_tree() -> void:
	if _preview != null:
		_preview.stop()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var title := Label.new()
	title.text = "Sound Admin  ·  src/sound"
	title.add_theme_font_size_override("font_size", 20)
	root.add_child(title)
	var hint := Label.new()
	hint.text = "연결된 항목 제목 오른쪽의 파란 영역에 다른 사운드를 드롭하면 즉시 교체됩니다."
	root.add_child(hint)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 400
	split.add_child(left)
	var refresh := Button.new()
	refresh.text = "연결 목록 새로고침"
	refresh.pressed.connect(_refresh)
	left.add_child(refresh)
	_list = SoundList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.sound_selected.connect(_select)
	_list.sound_activated.connect(_preview_selected)
	_list.files_dropped.connect(_add_files)
	_list.sound_replacement_requested.connect(_request_file_replacement)
	_list.rename_requested.connect(_open_context_rename)
	left.add_child(_list)
	var add_drop := AddDropZone.new()
	add_drop.custom_minimum_size.y = 64
	add_drop.files_dropped.connect(_add_files)
	left.add_child(add_drop)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 320
	split.add_child(right)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.custom_minimum_size.y = 220
	right.add_child(_info)
	var add := Button.new()
	add.text = "사운드 추가…"
	add.tooltip_text = "파일을 src/sound/로 복사합니다."
	add.pressed.connect(_pick_sound)
	right.add_child(add)
	var preview_row := HBoxContainer.new()
	right.add_child(preview_row)
	var play := Button.new()
	play.text = "미리 듣기"
	play.pressed.connect(_preview_selected)
	preview_row.add_child(play)
	var stop := Button.new()
	stop.text = "중지"
	stop.pressed.connect(_stop_preview)
	preview_row.add_child(stop)
	var volume_label := Label.new()
	volume_label.text = "미리듣기 볼륨"
	right.add_child(volume_label)
	_volume = HSlider.new()
	_volume.min_value = -50.0
	_volume.max_value = 0.0
	_volume.step = 1.0
	_volume.value = -8.0
	_volume.value_changed.connect(_set_preview_volume)
	right.add_child(_volume)
	var rename_label := Label.new()
	rename_label.text = "파일 이름"
	right.add_child(rename_label)
	_name = LineEdit.new()
	_name.placeholder_text = "예: button_click.ogg"
	right.add_child(_name)
	var rename := Button.new()
	rename.text = "이름 변경"
	rename.pressed.connect(_rename_selected)
	right.add_child(rename)
	var remove := Button.new()
	remove.text = "선택 사운드 삭제…"
	remove.pressed.connect(_delete_selected)
	right.add_child(remove)
	var trash := TrashDropZone.new()
	trash.custom_minimum_size.y = 64
	trash.sound_dropped.connect(_request_delete)
	right.add_child(trash)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_status)

	_preview = AudioStreamPlayer.new()
	add_child(_preview)
	_picker = FileDialog.new()
	_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_picker.access = FileDialog.ACCESS_FILESYSTEM
	_picker.filters = PackedStringArray(["*.mp3, *.ogg, *.wav, *.flac ; Audio files"])
	_picker.files_selected.connect(_add_files)
	add_child(_picker)
	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(_confirm_pending)
	add_child(_confirm)
	_rename_dialog = ConfirmationDialog.new()
	_rename_dialog.title = "사운드 이름 변경"
	_rename_dialog.dialog_text = "새 파일 이름을 입력하세요."
	_rename_dialog.get_ok_button().text = "이름 변경"
	_rename_input = LineEdit.new()
	_rename_input.placeholder_text = "예: button_click.ogg"
	_rename_input.position = Vector2(16, 66)
	_rename_input.size = Vector2(388, 32)
	_rename_dialog.add_child(_rename_input)
	_rename_dialog.confirmed.connect(_confirm_context_rename)
	add_child(_rename_dialog)


func _refresh() -> void:
	_stop_preview()
	_paths = PackedStringArray()
	var dir := DirAccess.open(SOUND_DIR)
	if dir == null:
		_status.text = "사운드 폴더를 열 수 없습니다: %s" % SOUND_DIR
		return
	var names: Array[String] = []
	for file_name in dir.get_files():
		if is_sound_file_name(file_name):
			names.append(file_name)
	names.sort()
	for file_name in names:
		_paths.append(SOUND_DIR.path_join(file_name))
	_usages = _scan_usages()
	_list.set_sounds(_paths, _usages)
	_selected = -1
	_name.text = ""
	_info.text = "[b]%d개 사운드[/b]\n항목을 선택하면 사용 시점과 연결 위치를 보여 줍니다." % _paths.size()
	_status.text = ""


func _select(index: int) -> void:
	_selected = index
	_list.select_sound(index)
	var path := _selected_path()
	var file_name := path.get_file()
	_name.text = file_name
	var uses: Array = _usages.get(file_name, [])
	var role := str(SOUND_ROLES.get(file_name, "연결되지 않음 — 추가만 된 사운드입니다."))
	var details := "[b]%s[/b]\n%s\n\n[b]언제 재생되나[/b]\n%s\n\n[b]현재 연결 위치 (%d)[/b]" % [file_name, _format_size(FileAccess.get_file_as_bytes(path).size()), role, uses.size()]
	for use in uses:
		details += "\n• %s" % use
	_info.text = details


func _selected_path() -> String:
	return _paths[_selected] if _selected >= 0 and _selected < _paths.size() else ""


func _pick_sound() -> void:
	_picker.popup_centered_ratio(0.7)


func _add_files(from_paths: PackedStringArray) -> void:
	var sources := PackedStringArray()
	var target_names := {}
	for from_path in from_paths:
		var file_name := from_path.get_file()
		if not is_sound_file_name(file_name):
			continue
		if ProjectSettings.localize_path(from_path) == SOUND_DIR.path_join(file_name):
			continue
		if not target_names.has(file_name):
			sources.append(from_path)
			target_names[file_name] = true
	if sources.is_empty():
		_status.text = "추가할 mp3, ogg, wav, flac 파일을 드롭하세요."
		return
	var overwrite_count := 0
	for from_path in sources:
		if FileAccess.file_exists(SOUND_DIR.path_join(from_path.get_file())):
			overwrite_count += 1
	_request_confirmation("add", {"sources": sources}, "%d개 사운드를 추가할까요?%s" % [sources.size(), " 기존 파일 %d개는 교체됩니다." % overwrite_count if overwrite_count else ""])


func _preview_selected(_unused: int = -1) -> void:
	var path := _selected_path()
	if path.is_empty():
		_status.text = "미리 들을 사운드를 선택하세요."
		return
	var stream := load(path) as AudioStream
	if stream == null:
		_status.text = "오디오를 불러오지 못했습니다: %s" % path.get_file()
		return
	_preview.stream = stream
	_preview.play()
	_status.text = "재생 중: %s" % path.get_file()


func _stop_preview() -> void:
	if _preview != null:
		_preview.stop()


func _set_preview_volume(value: float) -> void:
	_preview.volume_db = value


func _rename_selected() -> void:
	_request_rename(_selected_path(), _name.text)


func _open_context_rename(index: int) -> void:
	_select(index)
	_rename_target = _selected_path()
	_rename_input.text = _rename_target.get_file()
	_rename_dialog.popup_centered(Vector2i(420, 150))
	_rename_input.grab_focus()
	_rename_input.select_all()


func _confirm_context_rename() -> void:
	_request_rename(_rename_target, _rename_input.text)


func _request_rename(from_path: String, input_name: String) -> void:
	var file_name := input_name.strip_edges()
	if from_path.is_empty():
		_status.text = "이름을 바꿀 사운드를 선택하세요."
		return
	if not is_sound_file_name(file_name):
		_status.text = "파일명은 mp3, ogg, wav, flac 형식이어야 합니다."
		return
	var target := SOUND_DIR.path_join(file_name)
	if target == from_path:
		return
	if FileAccess.file_exists(target):
		_request_confirmation("rename", {"from": from_path, "to": target}, "%s 을(를) 덮어쓰고 이름을 바꿀까요?" % file_name)
		return
	if _rename_sound(from_path, target):
		EditorInterface.get_resource_filesystem().scan()
		_refresh()


func _delete_selected() -> void:
	_request_delete(_selected_path())


func _request_delete(path: String) -> void:
	if path.is_empty():
		_status.text = "삭제할 사운드를 선택하거나 휴지통으로 드래그하세요."
		return
	var uses: Array = _usages.get(path.get_file(), [])
	_request_confirmation("delete", {"path": path}, "%s 을(를) 삭제할까요?%s 이 작업은 되돌릴 수 없습니다." % [path.get_file(), " 현재 %d개 코드 연결이 있습니다." % uses.size() if not uses.is_empty() else ""])


func _request_confirmation(action: String, data: Dictionary, message: String) -> void:
	_pending = data
	_pending["action"] = action
	_confirm.dialog_text = message
	_confirm.popup_centered()


func _confirm_pending() -> void:
	var action := str(_pending.get("action", ""))
	match action:
		"add":
			var added := 0
			for source in _pending["sources"]:
				var from_path := str(source)
				var target := SOUND_DIR.path_join(from_path.get_file())
				if FileAccess.file_exists(target) and DirAccess.remove_absolute(ProjectSettings.globalize_path(target)) != OK:
					_status.text = "기존 파일 삭제 실패: %s" % target.get_file()
					return
				if DirAccess.copy_absolute(_absolute_path(from_path), ProjectSettings.globalize_path(target)) != OK:
					_status.text = "추가 실패: %s" % from_path.get_file()
					return
				added += 1
			_status.text = "%d개 사운드 추가 완료" % added
		"rename":
			if not _rename_sound(str(_pending["from"]), str(_pending["to"])):
				return
		"delete":
			if DirAccess.remove_absolute(ProjectSettings.globalize_path(str(_pending["path"]))) != OK:
				_status.text = "삭제 실패"
				return
			_status.text = "삭제 완료"
		"replace_file_bindings":
			for binding in _pending["bindings"]:
				if not _replace_binding(binding, str(_pending["sound"])):
					return
			_status.text = "연결 %d개 교체 완료: %s" % [_pending["bindings"].size(), str(_pending["sound"]).get_file()]
	_pending.clear()
	EditorInterface.get_resource_filesystem().scan()
	_refresh()


func _rename_sound(from_path: String, target: String) -> bool:
	var bindings := _bindings_for_file(from_path.get_file())
	var old_web_path := "res://web/sound".path_join(from_path.get_file())
	if FileAccess.file_exists(target) and DirAccess.remove_absolute(ProjectSettings.globalize_path(target)) != OK:
		_status.text = "기존 파일 삭제 실패: %s" % target.get_file()
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(from_path), ProjectSettings.globalize_path(target)) != OK:
		_status.text = "이름 변경 실패"
		return false
	for binding in bindings:
		if not _replace_binding(binding, target):
			return false
	if FileAccess.file_exists(old_web_path):
		if not _sync_web_copy(target) or DirAccess.remove_absolute(ProjectSettings.globalize_path(old_web_path)) != OK:
			_status.text = "웹 사운드 이름 변경 실패"
			return false
	_status.text = "이름 변경 및 연결 %d개 갱신 완료: %s" % [bindings.size(), target.get_file()]
	return true


func _scan_usages() -> Dictionary:
	var usages := {}
	_scan_directory("res://scripts", usages)
	_scan_file("res://godot-shell.html", usages)
	return usages


func _scan_directory(directory: String, usages: Dictionary) -> void:
	for file_name in DirAccess.get_files_at(directory):
		if file_name.get_extension() == "gd":
			_scan_file(directory.path_join(file_name), usages)
	for child in DirAccess.get_directories_at(directory):
		_scan_directory(directory.path_join(child), usages)


func _scan_file(path: String, usages: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var line_number := 0
	while not file.eof_reached():
		line_number += 1
		var line := file.get_line().strip_edges()
		for sound_path in _paths:
			var file_name := sound_path.get_file()
			if file_name in line:
				if not usages.has(file_name):
					usages[file_name] = []
				usages[file_name].append("%s:%d — %s" % [path.trim_prefix("res://"), line_number, line])


func _binding_file(binding: Dictionary) -> String:
	var target: Dictionary = binding["targets"][0]
	var file := FileAccess.open(str(target["path"]), FileAccess.READ)
	if file == null:
		return "연결 파일을 읽지 못함"
	while not file.eof_reached():
		var line := file.get_line()
		if line.strip_edges().begins_with(str(target["marker"])):
			return _quoted_file(line)
	return "연결 없음"


func _request_file_replacement(sound_path: String, target_path: String) -> void:
	if sound_path == target_path:
		return
	var bindings := _bindings_for_file(target_path.get_file())
	if bindings.is_empty():
		_status.text = "%s 은(는) 현재 관리 가능한 연결이 없습니다." % target_path.get_file()
		return
	_request_confirmation("replace_file_bindings", {"bindings": bindings, "sound": sound_path}, "%s 이(가) 맡은 연결 %d개를 %s 로 교체할까요?" % [target_path.get_file(), bindings.size(), sound_path.get_file()])


func _bindings_for_file(file_name: String) -> Array:
	var bindings: Array = []
	for binding in BINDINGS:
		if _binding_file(binding) == file_name:
			bindings.append(binding)
	return bindings


func _replace_binding(binding: Dictionary, sound_path: String) -> bool:
	var file_name := sound_path.get_file()
	var changes: Array[Dictionary] = []
	for target in binding["targets"]:
		var path := str(target["path"])
		var source := FileAccess.open(path, FileAccess.READ)
		if source == null:
			_status.text = "연결 파일을 읽지 못했습니다: %s" % path
			return false
		var lines := source.get_as_text().split("\n", true)
		var changed := false
		for index in lines.size():
			if lines[index].strip_edges().begins_with(str(target["marker"])):
				lines[index] = _replace_quoted_file(lines[index], str(target["prefix"]), file_name)
				changed = true
				break
		if not changed:
			_status.text = "연결 위치를 찾지 못했습니다: %s" % path
			return false
		changes.append({"path": path, "text": "\n".join(lines)})

	if not _sync_web_copy(sound_path):
		return false
	for change in changes:
		var output := FileAccess.open(str(change["path"]), FileAccess.WRITE)
		if output == null:
			_status.text = "연결 파일을 쓸 수 없습니다: %s" % change["path"]
			return false
		output.store_string(str(change["text"]))
	return true


func _sync_web_copy(sound_path: String) -> bool:
	var web_target := "res://web/sound".path_join(sound_path.get_file())
	if FileAccess.file_exists(web_target) and DirAccess.remove_absolute(ProjectSettings.globalize_path(web_target)) != OK:
		_status.text = "웹 사운드 교체 실패: %s" % web_target.get_file()
		return false
	if DirAccess.copy_absolute(ProjectSettings.globalize_path(sound_path), ProjectSettings.globalize_path(web_target)) != OK:
		_status.text = "웹 사운드 복사 실패: %s" % sound_path.get_file()
		return false
	return true


static func _quoted_file(line: String) -> String:
	var quote := "'" if "'" in line else "\""
	var first := line.find(quote)
	var last := line.rfind(quote)
	return line.substr(first + 1, last - first - 1).get_file() if first >= 0 and last > first else "연결 없음"


static func _replace_quoted_file(line: String, prefix: String, file_name: String) -> String:
	var quote := "'" if "'" in line else "\""
	var first := line.find(quote)
	var last := line.rfind(quote)
	return line.left(first + 1) + prefix + file_name + line.substr(last) if first >= 0 and last > first else line


static func _absolute_path(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("res://") else path


static func is_sound_file_name(file_name: String) -> bool:
	return not file_name.is_empty() and file_name.get_file() == file_name and not ("\\" in file_name) and EXTENSIONS.has(file_name.get_extension().to_lower())


static func _format_size(bytes: int) -> String:
	return "%.1f KB" % (float(bytes) / 1024.0) if bytes < 1024 * 1024 else "%.1f MB" % (float(bytes) / (1024.0 * 1024.0))


class SoundList extends ScrollContainer:
	signal files_dropped(paths: PackedStringArray)
	signal sound_replacement_requested(sound_path: String, target_path: String)
	signal sound_selected(index: int)
	signal sound_activated(index: int)
	signal rename_requested(index: int)

	var _rows: VBoxContainer

	func _ready() -> void:
		_rows = VBoxContainer.new()
		_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(_rows)

	func set_sounds(paths: PackedStringArray, usages: Dictionary) -> void:
		for child in _rows.get_children():
			child.queue_free()
		for index in paths.size():
			var path := paths[index]
			var file_name := path.get_file()
			var row := SoundRow.new()
			var bytes := FileAccess.get_file_as_bytes(path).size()
			var size_text := "%.1f KB" % (float(bytes) / 1024.0) if bytes < 1024 * 1024 else "%.1f MB" % (float(bytes) / (1024.0 * 1024.0))
			row.setup(index, path, size_text, (usages.get(file_name, []) as Array).size())
			row.sound_selected.connect(sound_selected.emit)
			row.sound_activated.connect(sound_activated.emit)
			row.sound_replacement_requested.connect(sound_replacement_requested.emit)
			row.rename_requested.connect(rename_requested.emit)
			_rows.add_child(row)

	func select_sound(index: int) -> void:
		for child in _rows.get_children():
			(child as SoundRow).set_selected((child as SoundRow)._index == index)

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("files")

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		var paths := PackedStringArray()
		for path in data["files"]:
			paths.append(str(path))
		files_dropped.emit(paths)


class SoundRow extends PanelContainer:
	signal sound_selected(index: int)
	signal sound_activated(index: int)
	signal sound_replacement_requested(sound_path: String, target_path: String)
	signal rename_requested(index: int)

	var _index := -1
	var _path := ""
	var _selected := false
	var _menu: PopupMenu

	func setup(index: int, path: String, size_text: String, connection_count: int) -> void:
		_index = index
		_path = path
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(details)
		var title := Label.new()
		title.text = path.get_file()
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		details.add_child(title)
		var meta := Label.new()
		meta.text = "%s  ·  %s" % [size_text, "연결 %d" % connection_count if connection_count else "미연결"]
		meta.add_theme_font_size_override("font_size", 12)
		meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
		details.add_child(meta)
		var slot := InlineReplaceZone.new()
		slot.custom_minimum_size = Vector2(150, 46)
		slot.sound_dropped.connect(sound_replacement_requested.emit)
		row.add_child(slot)
		slot.setup(path, connection_count > 0)
		_menu = PopupMenu.new()
		_menu.add_item("이름 변경…", 0)
		_menu.id_pressed.connect(_on_menu_selected)
		add_child(_menu)
		_apply_selection_style()

	func set_selected(selected: bool) -> void:
		_selected = selected
		_apply_selection_style()

	func _apply_selection_style() -> void:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("315d86") if _selected else Color("22262c")
		style.border_color = Color("8ed6ff") if _selected else Color("3b424c")
		style.set_border_width_all(2 if _selected else 1)
		style.set_corner_radius_all(6)
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		add_theme_stylebox_override("panel", style)

	func _gui_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.button_index == MOUSE_BUTTON_RIGHT and click.pressed:
			sound_selected.emit(_index)
			_menu.position = DisplayServer.mouse_get_position()
			_menu.popup()
			accept_event()
			return
		if click != null and click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
			sound_selected.emit(_index)
			if click.double_click:
				sound_activated.emit(_index)

	func _get_drag_data(_at_position: Vector2) -> Variant:
		var preview := Label.new()
		preview.text = _path.get_file()
		set_drag_preview(preview)
		return {"sound_admin_path": _path}

	func _on_menu_selected(id: int) -> void:
		if id == 0:
			rename_requested.emit(_index)


class InlineReplaceZone extends PanelContainer:
	signal sound_dropped(sound_path: String, target_path: String)

	var _target_path := ""
	var _replaceable := false
	var _label: Label

	func _ready() -> void:
		_label = Label.new()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(_label)
		_refresh_label()

	func setup(target_path: String, replaceable: bool) -> void:
		_target_path = target_path
		_replaceable = replaceable
		var style := StyleBoxFlat.new()
		style.bg_color = Color("244d73") if replaceable else Color("30343a")
		style.border_color = Color("65c8ff") if replaceable else Color("545b66")
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		add_theme_stylebox_override("panel", style)
		_refresh_label()

	func _refresh_label() -> void:
		if _label != null:
			_label.text = "사운드 교체" if _replaceable else "연결 없음"

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return _replaceable and data is Dictionary and data.has("sound_admin_path")

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		sound_dropped.emit(str(data["sound_admin_path"]), _target_path)


class AddDropZone extends PanelContainer:
	signal files_dropped(paths: PackedStringArray)

	func _ready() -> void:
		var label := Label.new()
		label.text = "파일을 여기에 드롭해 추가\nmp3 · ogg · wav · flac"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(label)

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("files")

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		var paths := PackedStringArray()
		for path in data["files"]:
			paths.append(str(path))
		files_dropped.emit(paths)


class TrashDropZone extends PanelContainer:
	signal sound_dropped(path: String)

	func _ready() -> void:
		var label := Label.new()
		label.text = "휴지통\n목록 항목을 여기로 드래그해 삭제"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(label)

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("sound_admin_path")

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		sound_dropped.emit(str(data["sound_admin_path"]))
