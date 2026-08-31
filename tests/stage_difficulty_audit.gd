extends SceneTree

# 기존 스테이지를 바꾸지 않고 난이도 v2 후보를 산출한다.
# v2 = 전체 탈출 비용 점수 + 공간 압박(최대 15) + 긴 몸 제약(최대 15).
const LEVELS_DIR := "res://resources/levels"
const REPORT_PATH := "res://resources/difficulty_audit.json"
const NODE_BUDGET := 400000


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("merge"):
		_merge_reports()
		quit()
		return
	if OS.get_cmdline_user_args().has("apply"):
		_apply_scores()
		quit()
		return
	var stage_filter: int = _stage_argument()
	var first_stage: int = _int_argument("from", 0)
	var last_stage: int = _int_argument("to", 999999)
	var report_path: String = _report_argument()
	var names: Array[String] = []
	var levels_path := ProjectSettings.globalize_path(LEVELS_DIR)
	var dir := DirAccess.open(levels_path)
	if dir == null:
		push_error("난이도 감사: 스테이지 폴더를 열 수 없다")
		quit(1)
		return
	for file_name in dir.get_files():
		if file_name.begins_with("stage_") and file_name.ends_with(".json"):
			names.append(file_name)
	names.sort()

	var rows: Array[Dictionary] = []
	var unknown: int = 0
	for file_name in names:
		var stage: int = int(file_name.get_basename().trim_prefix("stage_"))
		if stage_filter >= 0 and stage != stage_filter:
			continue
		if stage_filter < 0 and (stage < first_stage or stage > last_stage):
			continue
		var level: Dictionary = _load_level("%s/%s" % [levels_path, file_name])
		if level.is_empty():
			unknown += 1
			continue
		var state := _to_puzzle_state(level)
		var costs := LevelSolver.new().early_escape_costs(state, 0, 8, NODE_BUDGET)
		var breakdown := LevelSolver.difficulty_breakdown(state, costs)
		var base_score: int = int(breakdown["base_score"])
		if base_score < 0:
			unknown += 1
		var stored_stats: Dictionary = level.get("stats", {})
		var stored_score: int = int(stored_stats.get(
			"difficulty_score", LevelSolver.difficulty_score(stored_stats.get("early_clearing", []))
		))
		var v2_score: int = int(breakdown["difficulty_score"])
		rows.append({
			"stage": int(file_name.get_basename().trim_prefix("stage_")),
			"stored_score": stored_score,
			"escape_costs": costs,
			"base_score": base_score,
			"open_cells": breakdown["open_cells"],
			"board_cells": breakdown["board_cells"],
			"open_ratio": breakdown["open_ratio"],
			"max_body_length": breakdown["max_body_length"],
			"long_body_excess": breakdown["long_body_excess"],
			"space_score": breakdown["space_score"],
			"body_score": breakdown["body_score"],
			"difficulty_score_v2": v2_score,
		})

	var report := {
		"formula": {
			"base": "LevelSolver.difficulty_score(all physical cats and nested layers, limit 8)",
			"space": "round(clamp((0.20 - open_ratio) / 0.20, 0, 1) * 15)",
			"long_body": "min(sum(max(body_length - 5, 0)), 15)",
			"v2": "base + space + long_body",
		},
		"stage_count": rows.size(),
		"unknown_count": unknown,
		"stages": rows,
	}
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("난이도 감사: 보고서를 저장할 수 없다")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()

	var v2_values: Array[int] = []
	for row in rows:
		if int(row["difficulty_score_v2"]) >= 0:
			v2_values.append(int(row["difficulty_score_v2"]))
	v2_values.sort()
	var stage_three: Dictionary = {}
	for row in rows:
		if int(row["stage"]) == 3:
			stage_three = row
			break
	if v2_values.is_empty():
		print("[난이도 감사] %d개 완료 / 미확정 %d" % [rows.size(), unknown])
		quit(1)
		return
	print("[난이도 감사] %d개 완료 / 미확정 %d / v2 %d~%d / 중앙값 %d" % [
		rows.size(), unknown, v2_values.front(), v2_values.back(), v2_values[v2_values.size() / 2],
	])
	if not stage_three.is_empty():
		print("[난이도 감사] stage_003: 기존 %d / 전체탈출 %d / 공간 %d / 긴몸 %d / v2 %d / 비용 %s" % [
			int(stage_three["stored_score"]), int(stage_three["base_score"]),
			int(stage_three["space_score"]), int(stage_three["body_score"]),
			int(stage_three["difficulty_score_v2"]), stage_three["escape_costs"],
		])
	quit()


func _stage_argument() -> int:
	return _int_argument("stage", -1)


func _int_argument(name: String, fallback: int) -> int:
	for arg in OS.get_cmdline_user_args():
		var prefix := "%s=" % name
		if arg.begins_with(prefix):
			return int(arg.trim_prefix(prefix))
	return fallback


func _report_argument() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("report="):
			return arg.trim_prefix("report=")
	return REPORT_PATH


func _merge_reports() -> void:
	var directory := ProjectSettings.globalize_path("res://resources")
	var dir := DirAccess.open(directory)
	var rows: Array[Dictionary] = []
	var formula: Dictionary = {}
	var stages: Dictionary = {}
	var unknown: int = 0
	if dir != null:
		for file_name in dir.get_files():
			if not (file_name.begins_with("difficulty_audit_") and file_name.ends_with(".json")):
				continue
			var part: Dictionary = _load_level("%s/%s" % [directory, file_name])
			formula = part.get("formula", formula)
			unknown += int(part.get("unknown_count", 0))
			for row in part.get("stages", []):
				var stage: int = int(row["stage"])
				if stages.has(stage):
					push_error("난이도 감사: stage_%03d 결과가 중복됐다" % stage)
					return
				stages[stage] = true
				rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["stage"]) < int(b["stage"]))
	var report := {"formula": formula, "stage_count": rows.size(), "unknown_count": unknown, "stages": rows}
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("난이도 감사: 최종 보고서를 저장할 수 없다")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[난이도 감사] 최종 보고서: %d개 / 미확정 %d" % [rows.size(), unknown])


func _apply_scores() -> void:
	var report := _load_level(REPORT_PATH)
	var scores: Dictionary = {}
	for row in report.get("stages", []):
		scores[int(row["stage"])] = row
	var directory := ProjectSettings.globalize_path(LEVELS_DIR)
	var dir := DirAccess.open(directory)
	var updated: int = 0
	if dir != null:
		for file_name in dir.get_files():
			if not (file_name.begins_with("stage_") and file_name.ends_with(".json")):
				continue
			var stage: int = int(file_name.get_basename().trim_prefix("stage_"))
			if not scores.has(stage):
				push_error("난이도 감사: stage_%03d 결과가 없다" % stage)
				return
			var path := "%s/%s" % [directory, file_name]
			var level := _load_level(path)
			var stats: Dictionary = level.get("stats", {})
			var row: Dictionary = scores[stage]
			stats["early_clearing"] = row["escape_costs"]
			stats["difficulty_score"] = int(row["difficulty_score_v2"])
			level["stats"] = stats
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file == null:
				push_error("난이도 감사: stage_%03d를 저장할 수 없다" % stage)
				return
			file.store_string(JSON.stringify(level, "  "))
			file.close()
			updated += 1
	print("[난이도 감사] 점수 반영: %d개" % updated)


# UI 의존성을 피하기 위해 JSON을 모델로만 읽는다. 얼음과 중첩 레이어도 실제 규칙대로 넣는다.
func _load_level(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _cell(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))


func _to_puzzle_state(level: Dictionary) -> PuzzleState:
	var state := PuzzleState.create(_cell(level["grid_size"]))
	for entry in level.get("holes", []):
		var cell := _cell(entry["grid_pos"])
		state.add_hole(cell, int(entry["color_id"]))
		state.add_ice(cell, int(entry.get("ice_count", 0)))
	for entry in level.get("obstacles", []):
		var origin := _cell(entry["grid_pos"])
		var size := _cell(entry["block_size"])
		for y in size.y:
			for x in size.x:
				state.add_obstacle(origin + Vector2i(x, y))
	for index in level.get("cats", []).size():
		var entry: Dictionary = level["cats"][index]
		var body: Array[Vector2i] = []
		for cell in entry["body_cells"]:
			body.append(_cell(cell))
		var nested: Array[int] = []
		for color in entry.get("nested_color_ids", []):
			nested.append(int(color))
		state.add_cat(index, int(entry["color_id"]), body, nested)
	return state
