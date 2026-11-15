# 고양이 액체 이야기 — 게임 연결 기록

2026-11-15. 현재 버전은 [revision-08](revision-08/README.md)의 무대사 만화다. 사용자가 이번 만화에 한해 UI 씬·이벤트·진입 분기·필요 연결 코드의 직접 추가를 허용했고, 해당 범위에서 UI Editor 원본과 실행용 데이터를 함께 갱신했다.

## 실제 흐름

1. 기존 splash 로딩 후 터치한다. 완료 이력이 없거나 `?story=replay`이면 `StoryIntro01`로 간다.
2. 240ms 뒤 첫 컷이 기존 200ms 스탬프 모션으로 나타난다. 대사·설명·타이핑·안내 글자는 없다.
3. 하단 오른쪽 `next`를 한 번 누를 때마다 다음 컷을 추가하고 이전 컷은 남긴다. 네 번째 컷의 next는 `story.pageComplete` 문서 엣지로 `StoryIntro02`에 간다.
4. 여덟 번째 컷의 next는 완료 저장 후 `story.finish` 문서 엣지로 기존 로비 홈 탭에 도착한다. 스테이지를 자동 시작하거나 하트를 소비하지 않는다.
5. 하단 왼쪽 `skip`은 두 페이지의 어느 컷에서나, 첫 컷 전에도 완료 저장 후 로비로 간다.
6. 완료 후 재접속은 기존 splash → 로비 흐름이며 끝내기 전에 새로고침하면 첫 페이지부터 다시 볼 수 있다.

## 파일과 배선

| 씬 | UUID | 사용자 입력 | 페이지 종료 문서 엣지 |
| --- | --- | --- | --- |
| StoryIntro01 | 91b7f29b-8b6d-41b7-a08a-99a0a1dfb401 | story-advance-01:click (next), story-skip-01:click | story.pageComplete |
| StoryIntro02 | 91b7f29b-8b6d-41b7-a08a-99a0a1dfb402 | story-advance-02:click (next), story-skip-02:click | story.finish |

- `.ui-editor/scenes/StoryIntro*.scene.json`과 `web/ui/StoryIntro*.contract.json`에 같은 레이아웃·배경·이미지·이벤트를 저장했다. 남은 visibility 위젯은 `story.panel01`~`panel08`과 `story.nextReady`다. 텍스트 바인딩은 없다.
- 두 scene-flow 파일에는 첫 입장 분기 1개, 페이지 문서 엣지 2개, skip 엣지 2개가 있다. `SCENES.md`도 현재 상태를 선언한다.
- `web/story-intro.js`의 기존 `attachStoryIntro`는 첫 입장 조건·visibility·next 입력·skip 완료 조건을 공급한다. 페이지 이동은 `flow.fire`, skip 이동은 FlowDriver 버튼 엣지에 맡긴다.
- `story.complete` 조건은 진행 중 상태가 있을 때만 완료 저장한다. 완료와 skip은 rAF와 next 구독을 즉시 정리하므로 연타가 저장을 중복하지 않는다. 초기 대기 이후 지속 실행하는 rAF나 타이핑 루프가 없다.
- `godot-shell.html`, `web/index.html`은 CSS/JS `cat-liquid-v9`을 사용한다. 스토리/흐름/계약 JSON은 HTTP 재검증하며, 기존 splash 디코드 대기에 두 씬을 포함한다.
- 새 `story_cat_liquid_full_card_01.webp`~`08.webp`은 770×384를 1/2배로 표시한다. 새 경로로 이전 이미지 캐시와 구분한다. 원화/비프레임 컷은 중복 선로딩하지 않는다.
- 카드 크기는 385×192, x4, y4/200/396/592다. 대사창을 없애 화면 대부분을 그림으로 채웠다. skip은 x16, next는 x297, 두 버튼 모두 y800/80×44다.
- 사선 프레임, 상점 배경, 컷 누적 등장, 움직임 줄이기 설정은 유지한다. `sceneAnimations`는 비어 있고 입력 없이 다음 컷으로 진행하지 않는다.
- 레이아웃을 HTML로 재구현하거나 SceneRenderer/FlowDriver/기타 매니저/Godot 본체를 수정하지 않았다.

## 그림과 다국어

기존 괴짜 연구자·게임 고양이를 참조해 세로 공간이 더 넉넉한 2:1 구도로 8컷을 새로 그렸다. Sunburst 1024×1024 원화 네 장에 각 두 컷을 담고 실제 흰 여백을 측정해 분리했다. 그림 속 대사·설명칸·효과음 글자는 없고, 연구 노트에는 컵/상자 고양이 도형만 있다. 문자열은 skip/next 두 개다.

언어별 대사 데이터와 대사 UI를 제거했으며, 표정·행동·물건·같은 색 고양이/차원문으로 이야기를 전달한다. 실제 유변학 논문 정보는 스토리 JSON에 보존하고 등장 박사와 차원문은 창작으로 구분한다. 원화·프롬프트·사용량은 `revision-08/`에 있다. 게임의 3D 메시를 렌더한 그림이거나 실제 게임 화면과 픽셀 단위로 같다는 뜻은 아니다.

## 저장과 다시보기

완료 키는 기존 `leonout_story_cat_liquid_seen_v1`이며 `GAME_STORAGE_KEYS`와 로컬/Hub 저장 흐름에 포함된다. 마지막 next 또는 skip에서만 저장한다. 페이지 진입/넘기기에는 저장하지 않는다.

http://localhost:8080/web/?story=replay 는 완료 이력을 삭제하지 않고 다시 볼 수 있는 주소다. 기존 URL에 쿼리가 있으면 `&story=replay`를 붙인다.

## 검증

- `node tests/story_intro_check.mjs`: 실제 publish FlowDriver와 렌더러/DOM 대역으로 무대사 계약, 하단 skip/next, 초기 등장, next 진행, 두 문서 엣지, 첫 컷 전/두 페이지 skip, 키보드, 연타 1회 저장, 캐시 재입장/재접속/다시보기를 확인했고 통과했다.
- `splash_cache_check.mjs`, `ui_bare_asset_paths_check.mjs`도 통과했다.
- 원화 네 장과 두 페이지 배치 시안을 파일로 확인하고 WebP 디코드·크기·해시·컷 분리 좌표·대사 필드 부재를 확인했다. 시안 PNG/JPG/GIF는 실제 게임 캡처가 아니다.
- 기존 publish 보고서는 2026-08-31 기록이며 errors 0개/warnings 8개다. 이번 검사 결과로 덮어쓰지 않았다.
- 프로젝트 규칙에 따라 실제 게임의 브라우저·시각 확인은 사용자가 수행한다.

앞선 시안과 사용량은 revision-03~07 폴더에 보존했다.
