class_name LevelData
extends RefCounted


## 참고 이미지 느낌에 맞춘 세로형 테스트 스테이지 데이터.
## cats 항목은 [x, y, facing_direction, tint_name] 형식으로 정의한다.
static func get_test_level() -> Dictionary:
	return {
		"grid_size": Vector2i(7, 9),
		"obstacles": [
			[2, 4], [3, 4], [4, 4],
			[2, 5], [3, 5], [4, 5],
			[2, 6], [3, 6], [4, 6],
		],
		"cats": [
			[2, 1, "up", "cream"],
			[4, 1, "up", "sky"],
			[0, 6, "down", "lime"],
			[6, 6, "down", "rose"],
		],
	}
