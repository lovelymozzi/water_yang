extends SceneTree

const SoundAdmin := preload("res://addons/sound_admin/sound_admin_panel.gd")


func _init() -> void:
	assert(SoundAdmin.is_sound_file_name("button_click.ogg"))
	assert(SoundAdmin.is_sound_file_name("music.mp3"))
	assert(not SoundAdmin.is_sound_file_name("voice.txt"))
	assert(not SoundAdmin.is_sound_file_name("../voice.ogg"))
	assert(SoundAdmin._absolute_path("res://src/sound/test.ogg").ends_with("src/sound/test.ogg"))
	assert(SoundAdmin._quoted_file("const BGM = './sound/music.ogg';") == "music.ogg")
	assert(SoundAdmin._replace_quoted_file("const BGM = './sound/music.ogg';", "./sound/", "new.ogg") == "const BGM = './sound/new.ogg';")
	var binding_kinds := {}
	for binding in SoundAdmin.BINDINGS:
		binding_kinds[binding["id"]] = binding["kind"]
	assert(SoundAdmin.SOUND_ROLES["bubble_pop.mp3"] == "고양이가 흡수된 뒤 cat_hole 메시가 사라지기 시작할 때")
	assert(SoundAdmin.SOUND_ROLES["Time_out2.mp3"] == "고양이 구멍 팝 소리 위에 겹쳐 재생되어 더 또렷하게 들리게 할 때")
	assert(binding_kinds["item_move_hole_pop"] == "VFX 버튼")
	assert(binding_kinds["cat_hole_pop_overlay"] == "VFX 버튼")
	assert(binding_kinds["ice_freezing"] == "VFX 버튼")
	assert(binding_kinds["digging"] == "VFX 버튼")
	assert(binding_kinds["lobby_bgm"] == "BGM 버튼")
	var row := SoundAdmin.SoundRow.new()
	row.setup(3, "res://src/sound/Ui_button_sound.mp3", "1.0 KB", 0, [], [
		{"id": "digging", "kind": "VFX 버튼", "label": "삽 아이템"},
		{"id": "lobby_bgm", "kind": "BGM 버튼", "label": "로비 BGM"},
	])
	var rename_result := {"index": -1}
	var row_binding_result := {"id": "", "path": ""}
	row.rename_requested.connect(func(index: int) -> void: rename_result["index"] = index)
	row.binding_requested.connect(func(id: String, path: String) -> void:
		row_binding_result["id"] = id
		row_binding_result["path"] = path
	)
	row._on_menu_selected(0)
	assert(rename_result["index"] == 3)
	row._on_binding_selected(2)
	assert(row_binding_result["id"] == "lobby_bgm")
	assert(row_binding_result["path"] == "res://src/sound/Ui_button_sound.mp3")
	row.free()
	var connected_row := SoundAdmin.SoundRow.new()
	connected_row.setup(4, "res://src/sound/Lobby_Bgm.mp3", "1.0 KB", 1, ["[BGM 버튼] 로비 BGM"], [
		{"id": "digging", "kind": "VFX 버튼", "label": "삽 아이템", "file": "diggingt_optimized.mp3"},
		{"id": "lobby_bgm", "kind": "BGM 버튼", "label": "로비 BGM", "file": "Lobby_Bgm.mp3"},
	])
	assert(connected_row._binding_picker.selected == 2)
	connected_row.free()
	var binding_row := SoundAdmin.BindingRow.new()
	var replace_result := {"id": "", "path": ""}
	binding_row.binding_replacement_requested.connect(func(id: String, path: String) -> void:
		replace_result["id"] = id
		replace_result["path"] = path
	)
	binding_row.setup({"id": "digging", "kind": "VFX 버튼", "label": "삽 아이템", "file": "diggingt_optimized.mp3", "when": "테스트", "targets": "godot-shell.html"})
	binding_row._drop_data(Vector2.ZERO, {"sound_admin_path": "res://src/sound/Ui_button_sound.mp3"})
	assert(replace_result["id"] == "digging")
	assert(replace_result["path"] == "res://src/sound/Ui_button_sound.mp3")
	binding_row.free()
	print("SOUND ADMIN CHECK: PASS")
	quit()
