# 맵 자동생성기 (역설계 + 의존성 그래프 + 오토솔버)

## Context

현재 레벨은 `scenes/main_scene.tscn` 에 손으로 배치한 고양이 4마리 + 구멍 4개뿐이다. 이 퍼즐의 재미는
**A가 나가려면 B가 먼저 나가야 하고, B는 C가 먼저 나가야 한다**는 순서 강제(소프트락)에서 나오는데,
손 배치로는 그 의존성이 실제로 강제되는지도, 풀이가 존재하는지도 보장할 수 없다.

그래서 생성기를 만든다. 핵심 결정 세 가지:

1. **역설계(reverse design)** — 다 풀린 상태(고양이 전원 탈출)에서 시작해 고양이를 구멍 옆에 되돌려
   놓고 거꾸로 걸어 나오게 한다. 모든 역주행 한 스텝은 정방향 한 스텝의 역이므로, 생성이 끝난
   순간 풀이 수순이 곧 손에 들려 있다. 풀이가 없는 맵이 나올 수 없다.
2. **의존성 그래프** — 역설계 순서(마지막 탈출자를 먼저 배치)가 곧 위상 순서다. 뒤에 배치하는
   고양이의 시작 몸을 앞서 배치한 고양이의 이동 경로 위에 얹어 의존 간선을 **의도적으로** 만들고,
   생성 후 실측으로 그 간선이 진짜인지 검증한다.
3. **기믹은 역설계에 포함한다** — 역설계가 끝난 맵에 기믹을 나중에 꽂으면 기록된 풀이가 무효가 되어
   풀이 없는 맵이 될 수 있다. 지금 기믹이 하나도 없으므로 **확장 지점과 이 위험을 주석·문서로만
   남기고** 실제 기믹 로직은 넣지 않는다. (장애물은 예외 — 아래 "장애물 주입"의 안전성 논증 참고.)

## 데드락이 없다는 것의 근거

솔버를 어디까지 돌릴지는 이 논증에 달려 있으므로 먼저 정리한다.

- **한 칸 이동은 항상 되돌릴 수 있다.** 끝 `e` 를 칸 `c` 로 옮긴 뒤 반대쪽 끝을 방금 비운 칸으로
  옮기면 원래 상태다. 그 칸은 자기가 비운 칸이라 비어 있고, 장애물·구멍일 수 없으며, 되돌아간
  상태는 원래 흡입이 걸리지 않은 상태였으므로 흡입도 새로 걸리지 않는다.
- **흡입은 되돌릴 수 없지만 칸을 비우기만 한다.** 고양이는 서로에게 장애물일 뿐이므로, 한 마리가
  사라지는 것은 남은 고양이의 풀이를 절대 없애지 않는다.

⇒ **시작 상태가 풀리면 도달 가능한 모든 상태도 풀린다.** 따라서 솔버는 "최소 수순"을 구할 필요가
없고 **풀이 존재 + 의존성 강제**만 확인하면 된다. 무작위 플레이 샘플링으로 경험적 뒷받침만 덧붙인다.

## 규칙 모델 (기존 구현에서 읽어낸 것)

생성기·솔버는 아래를 **정확히** 복제해야 한다. 어긋나면 "생성기는 풀린다는데 게임에서 안 풀린다"가 된다.

| 규칙 | 출처 |
| --- | --- |
| 새로 점유하는 칸 조건: 보드 안 + 장애물 아님 + 구멍 아님 + 다른 고양이 아님 + **자기 몸 아님(뒤끝 포함)** | `cat_entity.gd:809 can_enter()`, `cat_entity.gd:681 _can_slide_into()`, `level_manager.gd:215 is_cell_blocked_for()` |
| 전진과 후진의 조건이 동일 → 원자 이동은 "두 끝 중 하나를 인접한 빈 칸으로" 하나뿐 | 위 두 함수가 같은 집합인 것 |
| 흡입은 **강제**다. 두 끝 중 하나가 짝 색 구멍과 4방향 인접하면 그 순간 사라진다 | `cat_entity.gd:712 _try_begin_absorb()`, `level_manager.gd:543 adjacent_hole()` |
| 구멍은 경로가 아니다 | `level_manager.gd:222` |
| 색 짝: 같은 `color_id` 만, `-1` 은 와일드카드 | `level_manager.gd:535 color_ids_pair()` |
| **시작부터 짝 구멍에 인접한 배치는 레벨 설계 오류** | `DEVELOPMENT_RULES.md:87` |

`_reverse_target()` 의 벽 슬라이드 무작위성은 모델에 넣지 않는다. 재생은 항상 "잡은 끝을 빈 칸으로"만
하므로(자기 몸을 가리키지 않으므로) 후진 슬라이드 경로를 타지 않는다.

## 구현

### 1. `scripts/puzzle_state.gd` — 헤드리스 규칙 모델 (신규, `class_name PuzzleState extends RefCounted`)

실제 `CatEntity` 는 FBX·셰이더·스켈레톤을 들고 있어 수만 번 탐색에 쓸 수 없다. 노드 없는 순수 모델을 둔다.

- 상태: `grid_size`, `obstacles: Dictionary`, `holes: Dictionary`(cell → color_id),
  `cats: Array[Dictionary]` (`{id, color, cells: Array[Vector2i]}`), 점유 역인덱스 `Dictionary`.
- `can_enter(cat_id, cell)` / `legal_moves()` / `apply_move(move)` / `clone()` / `key()` / `is_solved()`.
  각 함수 주석에 위 표의 원본 함수명을 적어 대조 지점을 남긴다.
- `apply_move()` 는 몸을 한 칸 밀고 나서 `_resolve_absorption(cat_id)` 를 호출한다. **움직인 고양이만**
  본다(고양이 제거는 새 인접을 만들지 않는다). 흡입은 선택이 아니라 강제다.
- 이동 표현은 인덱스가 아니라 **칸**으로 한다: `{cat_id, from_end_cell, to_cell}`. 실제 게임은
  `_flip_lead()` 가 `body_cells` 를 뒤집으므로 "끝 0/1" 인덱스로 기록하면 재생 때 어긋난다.
- **기믹 확장 지점**: `gimmicks: Dictionary`(cell → 규칙 배열)와 `apply_move()` 안의
  `_apply_gimmicks_on_commit(cat_id)` 훅을 비워 둔다. 훅 위에 "기믹을 역설계 이후에 주입하면
  기록된 풀이가 무효가 될 수 있으므로 반드시 역설계 루프 안에서 함께 되돌려야 한다"는 주석을 단다.

### 2. `scripts/dependency_graph.gd` — 의존성 그래프 (신규, `class_name LevelDependencyGraph`)

- 간선 `u → v` = "u가 탈출하려면 v가 먼저 나가야 한다".
- `add_edge()`, `topological_order()`, `longest_chain_depth()`, `has_cycle()`, `describe()`.
- **순환이 있으면 아무도 먼저 못 나간다 = 소프트락**이므로 즉시 생성 실패로 처리한다.
- 두 그래프를 만들어 비교한다.
  - *의도 간선*: 역설계에서 σ_j 의 시작 몸이 σ_k(k>j) 의 기록 경로와 겹칠 때.
  - *실측 간선*: 아래 `can_escape_alone()` 으로 확인한 것. **A→B→C 가 진짜 강제되는지의 근거는 이쪽이다.**

### 3. `scripts/level_solver.gd` — 오토솔버 (신규, `class_name LevelSolver`)

- `solve(state, node_budget) -> {found, moves, nodes}` — 백트래킹 DFS + 방문 상태 해시 테이블.
  수 정렬은 "끝 하나가 짝 구멍 인접칸에 가까워지는 수 우선". 기록된 풀이가 존재하므로 빠르게 끝난다.
- `can_escape_alone(state, cat_id, frozen_ids) -> bool` — 다른 고양이를 전부 고정한 채 그 고양이의
  몸 배치만 BFS. 상태공간이 작다. 의존성 실측과 "이 고양이는 갇혔는가" 진단에 쓴다.
- `random_play_probe(state, tries, rng)` — 무작위로 몇 수 둔 뒤에도 `solve()` 가 성공하는지 본다.
  위 가역성 논증의 경험적 뒷받침.
- 파일 머리 주석에 데드락 논증을 그대로 적어 둔다. 최소 수순은 구하지 않는다는 것과 그 이유까지.

### 4. `scripts/map_generator.gd` — 역설계 생성기 (신규, `class_name MapGenerator`)

`RandomNumberGenerator` 를 시드로 고정해 같은 시드가 같은 맵을 낸다.

설정: `seed`, `grid_size`(기본 `Vector2i(7, 9)`), `cat_count`(기본 4), `body_length_min/max`,
`reverse_steps_min/max`, `min_chain_depth`(기본 3 — A→B→C), `obstacle_fill_ratio`, `max_attempts`.

**Phase 0 — 구멍 배치.** `cat_count` 개를 서로 체비셰프 거리 2 이상으로 놓고 색을 하나씩 배정한다
(색 수는 `LevelManager.pair_colors.size()` 를 넘지 않게. 기본은 색 중복 없음 — 중복되면 순서 강제가 약해진다).
와일드카드 구멍은 기본적으로 만들지 않는다(모든 고양이가 그 주변을 피해야 해서 역주행이 크게 막힌다).

**Phase 1 — 역설계 루프.** `k = cat_count-1` 부터 `0` 까지 (마지막에 탈출하는 고양이를 먼저 배치).
σ_k 를 되돌릴 때 이미 배치된 σ_{k+1}.. 의 **시작 몸**이 정적 장애물이다. 이것이 정방향에서
"σ_k 가 움직일 때 뒤 순번 고양이들은 아직 제자리"라는 상황과 정확히 일치한다.

1. *흡입 순간 만들기*: 구멍 H_k 의 인접 빈 칸 `a` 를 잡고, `a` 를 한쪽 끝으로 하는 길이 L 의 몸을
   빈 칸 위로 뻗는다(꺾여도 된다).
2. *역주행*: `reverse_steps` 번 반복. 한 스텝의 역은 `cells' = cells[1..L-1] + [d]`
   (`d` 는 `cells[L-1]` 에 인접, 빈 칸, 자기 몸 아님) 또는 반대쪽 끝의 대칭형. 정방향 수
   `{cat_id, from_end_cell, to_cell}` 를 풀이 앞에 붙인다.
   - **조기 흡입 가드**: 역주행 중간 상태의 두 끝 중 어느 쪽도 **짝 색 구멍 전부**에 대해 4방향
     인접이면 안 된다. 정방향에서 거기 닿는 순간 강제로 빨려 들어가 풀이가 끊긴다. 위반하는 후보 스텝은 버린다.
   - 막히면 몇 스텝 되감고 다른 방향으로 재시도(제한 횟수 후 이 고양이 전체 재시도).
3. *의존성 유도*: σ_k 의 후보 스텝을 고를 때, 결과 몸이 **이미 기록된 σ_{k+1}.. 의 경로 칸**을 많이
   덮는 쪽에 가중치를 준다. 그러면 σ_{k+1} 은 σ_k 가 빠져야 지나갈 수 있으므로 간선 σ_{k+1} → σ_k 가 생긴다.
4. 역주행이 끝난 자리가 그대로 σ_k 의 **시작 몸**이다(꺾인 몸 허용이라 직선 강제가 없다).

**Phase 2 — 장애물 주입(역설계 후, 미사용 칸만).** 풀이 전 구간에서 어느 고양이든 밟은 칸,
구멍 칸, 시작·종료 몸 칸을 모두 모아 `touched` 를 만들고, **그 밖의 칸에만** 장애물을 채운다.
기록된 풀이가 그 칸을 한 번도 밟지 않으므로 풀이는 그대로 유효하고, 위 논증에 의해 데드락도 없다.
(기믹과 달리 장애물은 "칸을 뺏는" 순수 감산이라 이 논증이 성립한다 — 문서에 이 차이를 명시한다.)
인접한 칸은 사각형으로 묶어 `ObstacleMarker.block_size` 한 개로 낸다(칸마다 노드를 만들지 않는 기존 규칙).

**Phase 3 — 검증과 재시도.** `LevelSolver.solve()` 성공, 실측 의존성 그래프 비순환 +
`chain_depth >= min_chain_depth`, 시작 배치 규칙(보드 안 / 겹침 없음 / 4방향 인접 체인 /
구멍 칸 아님 / **짝 구멍에 인접하지 않음**) 전부 통과할 때까지 시드를 올려 `max_attempts` 회 재시도.

출력 Dictionary: `seed`, `grid_size`, `obstacles[{grid_pos, block_size}]`,
`holes[{grid_pos, color_id}]`, `cats[{body_cells, color_id}]`, `solution[]`, `escape_order[]`,
`dependency_graph{edges, chain_depth}`.

### 5. `scripts/cat_entity.gd` — 꺾인 시작 몸 지원 (수정)

지금은 `grid_pos`+`facing_name`+`initial_length` 로 **직선 몸만** 만들 수 있다(`_reset_straight_body()`, 818행).

- `@export var initial_body_cells: Array[Vector2i] = []` 추가.
- `_reset_straight_body()` → `_reset_initial_body()` 로 바꾸고, `initial_body_cells` 가 크기 2 이상의
  유효한 4방향 인접·자기교차 없는 체인이면 그것을 `body_cells` 로 쓰고, **아니면 기존 직선 로직으로
  그대로 폴백한다.** 손 배치와 기존 하네스(`hole_check.gd:221`, `movement_check.gd` 다수가 `grid_pos`
  대입에 직선 몸을 기대)는 전혀 영향을 받지 않는다.
- 경로를 쓸 때는 `grid_pos ← body_cells[0]`, `facing_dir ← body_cells[0] - body_cells[1]`,
  `initial_length ← size` 를 파생시킨다. 세터 재진입을 막는 `_applying_initial_body` 가드 플래그를 둔다.
- 포즈 쪽은 손댈 게 없다. `_sync_to_grid_position()` 은 `get_head_cell()` 을, `_update_visual_pose()` 는
  `body_cells` 폴리라인을 쓰므로 **이동 중 꺾인 몸과 같은 코드 경로**다.
- `DEVELOPMENT_RULES.md:36`("세터가 몸을 직선으로 되돌리므로…")을 새 동작에 맞게 고친다.

### 6. `scenes/cat_entity.tscn` — 고양이 템플릿 (신규)

생성 고양이가 손 배치 고양이와 같아 보여야 한다. `main_scene.tscn` 의 `Cat_C0`(59–79행) 튜닝값
(`fbx_scale_per_tile 7.5`, `tint_from_pair_color = true`, 그라디언트/아웃라인/라인아트)을 옮겨 담고
`grid_pos`/`color_id`/`initial_body_cells` 만 생성기가 채운다. 장애물이 `obstacle_block.tscn` 을
인스턴스로 떨어뜨리는 것과 같은 방식이다(`DEVELOPMENT_RULES.md:17`). 기존 씬의 고양이는 건드리지 않는다.

### 7. `scripts/level_layout_writer.gd` + `scripts/map_generator_tool.gd` — 출력 (신규)

`level_layout_writer.gd`:
- `apply_to_manager(manager, level)` — `LayoutCats`/`LayoutHoles`/`LayoutObstacles` 를 비우고
  `cat_entity.tscn`, `HoleMarker`, `obstacle_block.tscn` 을 인스턴스로 채운다. 에디터에서는 `owner` 를
  지정해 씬에 저장되게 하고, 마지막에 `manager.request_preview_refresh()`(`level_manager.gd:151`)를 부른다.
- `save_scene(level, path)` — `scenes/levels/level_<seed>.tscn` 으로 저장.
- `to_json(level)` / `from_json(dict)` — `resources/levels/level_<seed>.json`. 풀이 수순과 의존성
  그래프까지 함께 저장해 시드 회귀와 테스트 재현에 쓴다.

`map_generator_tool.gd` (`@tool extends Node`, `main_scene.tscn` 에 `MapGenerator` 노드로 추가):
시드·고양이 수·의존 깊이 등 설정을 Inspector 로 노출하고
`@export_tool_button("Generate Level")` + `("Save Level Files")` 두 버튼을 둔다. `LevelManager` 의
Inspector 를 더 불리지 않기 위해 별도 노드로 분리한다. 생성 리포트(탈출 순서, 의존 깊이, 풀이 길이,
탐색 노드 수)를 콘솔에 찍는다.

### 8. `2_맵생성기.md` (현재 빈 파일) + `DEVELOPMENT_RULES.md`

`1_움직임고찰.md` 와 같은 문체로 단일 기준 문서를 쓴다: 용어, 원자 이동 정의, 역설계 절차,
의존성 그래프 정의, 솔버 범위와 데드락 논증, 장애물 사후 주입의 안전성 논증, **기믹 역주입 위험과
"기믹이 생기면 반드시 역설계 루프 안에서 함께 되돌린다"는 규칙**. `DEVELOPMENT_RULES.md` 에는
현재 상태 항목과 "맵 생성은 `2_맵생성기.md` 가 단일 기준" 포인터, 회귀 검사 명령을 추가한다.

## 검증

### 하네스 (서로 독립. `DEVELOPMENT_RULES.md:122` 규칙)

1. **`tests/puzzle_state_parity_check.gd`** — 모델 대조. 여러 무작위 배치에서 `PuzzleState.can_enter()`
   와 실제 `CatEntity.can_enter()` / `LevelManager.is_cell_blocked_for()` / `adjacent_hole()` 결과를
   전 칸에 대해 비교한다. **"계산한 값과 실제가 어긋나는 것"이 이 프로젝트의 단골 실패 모드이므로
   이 대조를 반드시 회귀로 둔다.**
2. **`tests/generator_check.gd`** — 시드 20개 생성 후: 생성 성공, `solve()` 성공, `chain_depth >= 3`,
   시작 배치 규칙 전부(특히 짝 구멍 인접 금지), 장애물이 풀이 칸을 덮지 않음, 의존성 그래프 비순환,
   실측 간선이 의도 간선을 포함, 기록된 풀이가 `PuzzleState` 에서 그대로 재생됨,
   `random_play_probe()` 후에도 풀림.
3. **`tests/generator_replay_check.gd`** — **오토솔버 검증의 최종 근거.** 생성 레벨을 실제
   `main_scene` 에 주입하고 기록된 풀이를 진짜 게임 코드로 재생한다. 수 하나마다:
   움직일 끝이 `body_cells.back()` 이면 `begin_drag(body_cells.back())` 로 리드를 넘기고
   (`cat_entity.gd:440`), `request_path_to(to_cell)` 후 커밋될 때까지 `advance(1.0/60.0)`.
   자기 몸을 가리키지 않으므로 후진 벽 슬라이드 무작위성을 타지 않는다.
   전원 흡입 + `level_cleared` 발생을 확인한다.

### 명령

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --check-only --script scripts/map_generator.gd 2>&1 | grep -iE "error|warning"
```

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/puzzle_state_parity_check.gd && /Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/generator_check.gd && /Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/generator_replay_check.gd
```

기존 3종이 깨지지 않았는지 함께 돌린다(`initial_body_cells` 폴백 확인).

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/movement_check.gd && /Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/hole_check.gd && /Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/obstacle_check.gd
```

### 눈으로 확인

`--check-only` 는 에러가 있어도 종료코드가 0이라 반드시 `grep` 으로 걸러야 보인다.
헤드리스로는 렌더를 볼 수 없으므로, 생성 결과는 에디터에서 `MapGenerator` 노드의
`Generate Level` 버튼을 눌러 보드·고양이·구멍 배치를 직접 확인한다. 특히 **꺾인 시작 몸의 본 포즈**가
정상인지(얼굴이 위, 코너에서 몸이 옆 칸으로 밀리지 않는지) 본다. 필요하면
`tests/capture_shots.gd` 방식으로 생성 레벨 스크린샷을 남긴다.
`DEVELOPMENT_RULES.md:107` — 시각적으로 확인하지 못한 기능은 완료로 표현하지 않는다.

## 범위에서 빼는 것

- **최소 수순 계산.** 고양이 4마리 × 63칸이면 상태공간이 폭발한다. 데드락 논증이 있으므로 필요도 없다.
  난이도 수치는 기록된 풀이 길이와 의존 깊이로 대신한다.
- **실제 기믹 로직.** 확장 지점과 위험 주석만 남긴다.
- 기존 `main_scene.tscn` 의 손 배치 고양이·구멍 값 변경 (임의로 되돌리지 않는다).
