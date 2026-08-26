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
	var row := SoundAdmin.SoundRow.new()
	row._index = 3
	var rename_result := {"index": -1}
	row.rename_requested.connect(func(index: int) -> void: rename_result["index"] = index)
	row._on_menu_selected(0)
	assert(rename_result["index"] == 3)
	row.free()
	print("SOUND ADMIN CHECK: PASS")
	quit()
