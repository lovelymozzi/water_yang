@tool
extends RefCounted

# 이미 만들어 둔 스테이지 파일의 **순서만** 다시 매긴다. 맵은 한 칸도 건드리지 않는다.
# (생성기는 난이도 순 정렬을 하지 않는다 — stage_batch_generator.gd 주석 참조. 그 "게임이
#  완성된 뒤 전체 맵을 놓고 한 번에 배당하는 별도 작업"이 여기다.)
#
# 두 가지를 동시에 만족시킨다.
#   1. 난이도 리듬 — 난이도 띠를 주기로 반복해 놓되 띠 안은 오름차순이라 추세는 우상향.
#      단조 증가로 줄 세우면 후반이 전부 고비라 플레이어가 지친다. 주기는 패턴으로 고른다
#      (`PATTERNS`): 진폭 1짜리 퐁당퐁당 [쉬움·어려움]도, 6주기
#      [쉬움·쉬움·어려움·쉬움·쉬움·매우어려움]처럼 큰 산을 띄엄띄엄 두는 것도 같은 코드다.
#   2. 기믹 첫 등장과 연습 구간 — 기믹이 든 판은 그 기믹의 첫 등장 스테이지보다 앞에 놓지
#      않고, 첫 등장 자리부터 이어지는 몇 판(`TEACH_FOLLOW_UP`)은 그 기믹 판으로만 채운다.
#      1번보다 **우선**한다. 배우지 않은 규칙이 튀어나오거나, 한 번 보고 지나가 못 배우는
#      것이 난이도 리듬이 조금 흔들리는 것보다 나쁘다.

# 기믹 키 → 표시 이름. 여기 있는 키만 게이트를 건다.
# 중첩은 깊이별로 따로 가르친다 — 2중첩을 본 적 없는 판에 3중첩이 튀어나오면 규칙이 두 겹
# 한꺼번에 들어온다. 순서는 이 사전 순서가 아니라 각 게이트 값이 정한다.
const GIMMICK_NAMES := {"ice": "얼음", "nested2": "2중첩", "nested3": "3중첩"}


# 레벨 하나가 쓰는 기믹 키 집합.
static func gimmicks_of(level: Dictionary) -> Dictionary:
	var found: Dictionary = {}
	for hole in level.get("holes", []):
		if int((hole as Dictionary).get("ice_count", 0)) > 0:
			found["ice"] = true
			break
	# 겉 색 말고 **안쪽 색 개수**가 깊이다. 1개면 2중첩, 2개 이상이면 3중첩. 3중첩만 든 판은
	# 3중첩 게이트만 받는다 — 2중첩 연습 구간을 3중첩 판으로 채우면 그게 곧 조기 등장이다.
	for cat in level.get("cats", []):
		var depth: int = ((cat as Dictionary).get("nested_color_ids", []) as Array).size()
		if depth == 1:
			found["nested2"] = true
		elif depth >= 2:
			found["nested3"] = true
	return found


# 난이도 패턴. 한 주기에 자리마다 몇 번째 난이도 띠를 놓을지 적는다(0 = 가장 쉬운 띠).
# 띠 개수는 패턴에 나온 숫자 개수로 정해지고, 각 띠의 크기는 그 숫자가 주기에서 차지하는
# 비율 그대로다 — 6주기 [0,0,1,0,0,2] 면 판의 2/3 가 쉬운 띠, 1/6 이 어려운 띠, 1/6 이
# 매우 어려운 띠로 갈린다.
const PATTERNS := {
	"alternate": {"name": "퐁당퐁당 (쉬움·어려움)", "steps": [0, 1]},
	"six": {"name": "6주기 (쉬움·쉬움·어려움·쉬움·쉬움·매우어려움)", "steps": [0, 0, 1, 0, 0, 2]},
	"warmup_six": {"name": "30레벨 평탄화 + 6주기", "steps": [0, 0, 1, 0, 0, 2], "warmup": 30},
}
const DEFAULT_PATTERN := "alternate"

# 기믹을 처음 보여 준 뒤 몇 판을 더 그 기믹으로 채울 것인가. 한 번 보고 지나가면 규칙을
# 못 배운다 — 첫 등장 자리와 이어지는 이만큼을 전부 그 기믹 판으로 깐다(연습 구간).
# 첫 등장을 1(=제한 없음)로 둔 기믹에는 연습 구간도 없다.
const TEACH_FOLLOW_UP := 3


static func pattern_steps(key: String) -> Array[int]:
	var steps: Array[int] = []
	steps.assign(PATTERNS.get(key, PATTERNS[DEFAULT_PATTERN])["steps"])
	return steps


# levels 를 재배치한 **원본 인덱스 순서**를 돌려준다.
# gates: {기믹키: 첫 등장 스테이지(1부터)}. 없는 키·1 이하는 제한 없음.
# steps: 난이도 패턴 한 주기(위 PATTERNS). warmup_stages 동안은 가장 쉬운 띠만 오름차순으로 채운다.
static func arrange(
	levels: Array, gates: Dictionary, steps: Array[int] = [0, 1], warmup_stages: int = 0
) -> Array[int]:
	var count: int = levels.size()
	if steps.is_empty():
		steps = [0, 1]
	# 각 판이 놓일 수 있는 가장 이른 스테이지(1부터). 기믹 여러 개면 가장 늦은 쪽을 따른다.
	var earliest: Array[int] = []
	var by_score: Array[int] = []
	var has: Array = []
	for index in count:
		var floor_stage: int = 1
		has.append(gimmicks_of(levels[index]))
		for key in has[index]:
			floor_stage = maxi(floor_stage, int(gates.get(key, 1)))
		earliest.append(floor_stage)
		by_score.append(index)

	# 점수 같으면 원래 순번으로 갈라 결과를 결정적으로 만든다.
	by_score.sort_custom(func(a: int, b: int) -> bool:
		var score_a: int = LevelSolver.stored_difficulty_score(levels[a].get("stats", {}))
		var score_b: int = LevelSolver.stored_difficulty_score(levels[b].get("stats", {}))
		return a < b if score_a == score_b else score_a < score_b
	)

	# 자리마다 어느 띠에서 뽑을지 먼저 깔고, 띠별 자리 수만큼 정렬된 목록을 잘라 담는다.
	# 띠 크기를 패턴 등장 횟수로 정하므로 어떤 패턴을 넣어도 판이 남거나 모자라지 않는다.
	var tiers: Array[int] = []
	var band_count: Dictionary = {}
	for position in count:
		var tier: int = 0 if position < warmup_stages else steps[(position - warmup_stages) % steps.size()]
		tiers.append(tier)
		band_count[tier] = int(band_count.get(tier, 0)) + 1
	var bands: Dictionary = {}
	var cursor: int = 0
	var tier_keys: Array = band_count.keys()
	tier_keys.sort()
	for tier in tier_keys:
		var size: int = int(band_count[tier])
		var band: Array[int] = []
		band.assign(by_score.slice(cursor, cursor + size))
		bands[tier] = band
		cursor += size

	# 연습 구간: 첫 등장 자리와 그 뒤 TEACH_FOLLOW_UP 판은 그 기믹이 **든 판만** 놓는다.
	var required: Array = []
	required.resize(count)
	for position in count:
		required[position] = ""
	for key in gates:
		var gate: int = int(gates[key])
		if gate <= 1:
			continue
		for offset in TEACH_FOLLOW_UP + 1:
			var position: int = gate - 1 + offset
			# 두 기믹의 연습 구간이 겹치면 먼저 시작한 쪽이 그 자리를 갖는다. 한 판에 둘 다
			# 넣으라고 하면 그런 판이 없을 때 양쪽 다 흐지부지된다.
			if position < count and str(required[position]).is_empty():
				required[position] = key

	var order: Array[int] = []
	for position in count:
		var stage_number: int = position + 1
		var need: String = str(required[position])
		var picked: int = _take_allowed(bands[tiers[position]], earliest, stage_number, has, need)
		if picked < 0:
			# 제 띠가 비었거나 전부 기믹 게이트에 걸렸다. 가까운 띠부터 훑는다.
			picked = _take_nearest_band(
				bands, tier_keys, tiers[position], earliest, stage_number, has, need
			)
		if picked < 0 and not need.is_empty():
			# 그 기믹 판이 동났다. 연습 구간을 짧게 끝내는 편이 자리를 비우는 것보다 낫다 —
			# 실제로 몇 판 깔렸는지는 `teaching_fill()` 이 드러낸다.
			picked = _take_allowed(bands[tiers[position]], earliest, stage_number, has, "")
			if picked < 0:
				picked = _take_nearest_band(
					bands, tier_keys, tiers[position], earliest, stage_number, has, ""
				)
		if picked < 0:
			# 남은 판이 전부 게이트에 걸린다(첫 등장을 너무 뒤로 잡았을 때). 그래도 자리는
			# 채워야 하므로 가장 덜 미뤄진 판을 쓴다 — 게이트가 몇 판 당겨졌는지는
			# `first_appearances()` 가 실제 첫 등장으로 드러낸다.
			picked = _take_least_gated(bands, tier_keys, earliest)
		order.append(picked)
	return order


# 기믹별 실제 첫 등장 스테이지(1부터). 안 나오면 0.
static func first_appearances(levels: Array, order: Array[int]) -> Dictionary:
	var found: Dictionary = {}
	for key in GIMMICK_NAMES:
		found[key] = 0
	for position in order.size():
		for key in gimmicks_of(levels[order[position]]):
			if int(found.get(key, 0)) == 0:
				found[key] = position + 1
	return found


# 연습 구간이 실제로 몇 판 채워졌는지. {기믹키: [채운 판, 목표 판]}. 게이트 없는 기믹은 뺀다.
static func teaching_fill(levels: Array, order: Array[int], gates: Dictionary) -> Dictionary:
	var filled: Dictionary = {}
	for key in gates:
		var gate: int = int(gates[key])
		if gate <= 1:
			continue
		var done: int = 0
		var wanted: int = 0
		for offset in TEACH_FOLLOW_UP + 1:
			var position: int = gate - 1 + offset
			if position >= order.size():
				break
			wanted += 1
			if gimmicks_of(levels[order[position]]).has(key):
				done += 1
		filled[key] = [done, wanted]
	return filled


# pool 에서 stage_number 에 놓아도 되는 첫 판을 꺼낸다. need 가 비어 있지 않으면 그 기믹이
# 든 판만 본다. 없으면 -1.
static func _take_allowed(
	pool: Array[int], earliest: Array[int], stage_number: int, has: Array, need: String = ""
) -> int:
	for slot in pool.size():
		var index: int = pool[slot]
		if earliest[index] > stage_number:
			continue
		if not need.is_empty() and not (has[index] as Dictionary).has(need):
			continue
		pool.remove_at(slot)
		return index
	return -1


# 제 띠에서 못 뽑았을 때. 난이도가 가까운 띠부터(거리 같으면 쉬운 쪽) 훑는다.
static func _take_nearest_band(
	bands: Dictionary, tier_keys: Array, tier: int, earliest: Array[int], stage_number: int,
	has: Array, need: String = ""
) -> int:
	var sorted_keys: Array = tier_keys.duplicate()
	sorted_keys.sort_custom(func(a: int, b: int) -> bool:
		var distance_a: int = absi(a - tier)
		var distance_b: int = absi(b - tier)
		return a < b if distance_a == distance_b else distance_a < distance_b
	)
	for key in sorted_keys:
		var picked: int = _take_allowed(bands[key], earliest, stage_number, has, need)
		if picked >= 0:
			return picked
	return -1


# 전 띠를 통틀어 첫 등장 제한이 가장 이른 판을 꺼낸다.
static func _take_least_gated(bands: Dictionary, tier_keys: Array, earliest: Array[int]) -> int:
	var best_tier: int = -1
	var best_slot: int = -1
	for key in tier_keys:
		var slot: int = _least_gated_slot(bands[key], earliest)
		if slot < 0:
			continue
		if best_slot < 0 or earliest[bands[key][slot]] < earliest[bands[best_tier][best_slot]]:
			best_tier = key
			best_slot = slot
	if best_slot < 0:
		return -1
	return _take_at(bands[best_tier], best_slot)


static func _least_gated_slot(pool: Array[int], earliest: Array[int]) -> int:
	var best: int = -1
	for slot in pool.size():
		if best < 0 or earliest[pool[slot]] < earliest[pool[best]]:
			best = slot
	return best


static func _take_at(pool: Array[int], slot: int) -> int:
	var index: int = pool[slot]
	pool.remove_at(slot)
	return index


# 파일을 새 순서대로 stage_001.json 부터 다시 매긴다. 이름이 서로 겹치므로 임시 이름을
# 한 번 거친다(바로 최종 이름으로 옮기면 아직 안 옮긴 파일을 덮어쓴다).
# 순번의 구멍은 여기서만 메운다 — 재배치는 목록 전체를 다시 세우는 작업이라 구멍을 남기면
# "몇 번째 스테이지"와 파일 번호가 계속 어긋난다.
static func apply_order(dir_path: String, paths: PackedStringArray, order: Array[int]) -> String:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return "폴더를 열 수 없다: %s" % dir_path
	var temporary: PackedStringArray = PackedStringArray()
	for position in order.size():
		var source: String = paths[order[position]].get_file()
		var staged: String = "rearrange_%03d.json" % position
		var error: Error = dir.rename(source, staged)
		if error != OK:
			return "임시 이름으로 못 옮겼다: %s (%d)" % [source, error]
		temporary.append(staged)
	for position in temporary.size():
		var error: Error = dir.rename(temporary[position], "stage_%03d.json" % (position + 1))
		if error != OK:
			return "최종 이름으로 못 옮겼다: %s (%d)" % [temporary[position], error]
	return ""
