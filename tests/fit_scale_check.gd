extends Node

# 판이 기준(7x10)을 넘을 때 타일이 비율대로 줄어드는지 확인한다. `LevelManager` 가 오토로드
# (`UiBridge`) 를 참조하므로 `--script` 가 아니라 **씬으로** 띄워야 컴파일된다.
#
#   /Applications/Godot.app/Contents/MacOS/Godot --headless res://tests/fit_scale_check.tscn


func _ready() -> void:
	var lm := LevelManager.new()
	lm.tile_size = 2.0
	var cases := [
		[Vector2i(7, 9), 2.0],                  # 기준 이하 — 손대지 않는다
		[Vector2i(7, 10), 2.0],
		[Vector2i(8, 10), 2.0 * 7.0 / 8.0],     # 가로만 초과
		[Vector2i(9, 10), 2.0 * 7.0 / 9.0],
		[Vector2i(7, 11), 2.0 * 10.0 / 11.0],   # 세로만 초과
		[Vector2i(9, 11), 2.0 * 7.0 / 9.0],     # 둘 다 초과 — 더 센 쪽 하나만
	]
	var failures: Array[String] = []
	for case in cases:
		lm.grid_size = case[0]
		var got: float = lm.fitted_tile_size()
		if absf(got - float(case[1])) > 1e-6:
			failures.append("%s -> %f (기대 %f)" % [case[0], got, case[1]])
	lm.free()
	for line in failures:
		printerr("[축소 검사] ", line)
	if failures.is_empty():
		print("[축소 검사] 통과")
	get_tree().quit(0 if failures.is_empty() else 1)
