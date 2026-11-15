# 고양이 액체 이야기 — 게임 연결 기록

2026-11-15. 현재 버전은 [revision-07](revision-07/README.md)이다. 사용자가 이번 만화에 한해 UI 씬·이벤트·진입 분기·필요 연결 코드의 직접 추가를 명시적으로 허용했고, 이 범위에서 UI Editor 원본과 실행용 데이터를 함께 갱신했다. 다른 UI나 매니저의 직접 수정 예외는 아니다.

## 실제 흐름

1. 기존 splash 로딩을 끝내고 터치한다. 완료 이력이 없거나 `?story=replay`이면 `StoryIntro01`로 간다.
2. 240ms 뒤 첫 가로 컷이 200ms 스탬프 모션으로 나타난다. 독백은 38ms마다 한글 한 음절씩 출력한다.
3. 진행 글자는 `next` 하나다. 누르면 타이핑 중에도 바로 다음 컷이 추가된다. 이전 컷은 남는다. 그림·대사창 터치, 문장 완성용 추가 클릭, 안내 문구, skip은 없다.
4. 네 번째 컷에서 next를 누르면 문서 엣지 `story.pageComplete`를 발화해 `StoryIntro02`로 간다. 같은 방식으로 네 컷을 진행한다.
5. 여덟 번째 컷의 next는 완료를 저장하고 `story.finish` 문서 엣지로 기존 navigation의 로비 홈 탭에 도착한다. 스테이지를 자동 시작하거나 하트를 소비하지 않는다.
6. 완료 후 재접속은 기존 splash → 로비 흐름이다. 끝내기 전에 새로고침하면 1페이지부터 다시 볼 수 있다.

## 파일과 배선

| 씬 | UUID | 사용자 입력 | 페이지 종료 문서 엣지 |
| --- | --- | --- | --- |
| StoryIntro01 | 91b7f29b-8b6d-41b7-a08a-99a0a1dfb401 | story-advance-01:click (next) | story.pageComplete |
| StoryIntro02 | 91b7f29b-8b6d-41b7-a08a-99a0a1dfb402 | story-advance-02:click (next) | story.finish |

- `.ui-editor/scenes/StoryIntro*.scene.json`과 `web/ui/StoryIntro*.contract.json`에 같은 레이아웃·배경·이미지·바인딩·이벤트를 저장했다.
- `.ui-editor/scene-flow.json`과 `web/ui/scene-flow.json`에는 첫 입장 분기 1개, 페이지 문서 엣지 2개가 있다. 기존 skip 엣지 2개는 제거했다. `SCENES.md`도 현재 키/이벤트에 맞췄다.
- `web/story-intro.js`는 `attachStoryIntro`에서 첫 입장 조건, 공개 `story.panel01`~`panel08` 및 `story.nextReady` visibility, `story.dialogue` 텍스트 바인딩, 입력과 타이핑을 공급한다. 페이지 이동은 `flow.fire`로 문서 엣지를 실행한다.
- `Intl.Segmenter('ko', {granularity:'grapheme'})`로 분해된 자모도 한 음절씩 출력한다. next 입력 전에 이전 rAF를 취소하며 마지막 컷에서는 현재 상태와 구독을 먼저 정리해 연타로 전환·저장이 중복되지 않게 한다.
- `godot-shell.html`, `web/index.html`은 CSS/JS `cat-liquid-v8`을 사용하고 이야기 JSON과 UI JSON은 HTTP 재검증한다. 기존 splash 디코드 대기에 두 스토리 씬을 포함한다.
- `src/assets/story_cat_liquid_misfit_card_01.webp`~`08.webp`은 새 원화에서 분리한 744×290 프레임 에셋이며 1/2배로 표시한다. 새 경로로 이전 이미지 캐시와 분리했다. 원화/비프레임 컷을 중복 선로딩하지 않는다.
- 기존 사선 프레임, 상점 `common_bg_pt_3.png` 86px 타일/18초 스크롤, 하단 대사창, 누적 등장, 움직임 줄이기 설정은 유지한다. `sceneAnimations`는 비어 있어 자동 진행하지 않는다.
- 만화 레이아웃을 별도 HTML로 재구현하지 않았고, SceneRenderer/FlowDriver/기타 매니저나 Godot 본체는 수정하지 않았다.

## 그림과 독백

원화 두 장은 실제 게임의 고양이 얼굴·긴 몸·색과 숲을 참조해 Sunburst로 새로 만들었다. 괴짜 연구자는 회색 뻗친 머리·삐뚤어진 안경·구겨진 가운·짝짝이 양말·노트를 두고 오는 행동으로 표현한다. 대사는 1~6·8컷 연구자의 혼잣말, 7컷 고양이의 속말이며 상황 설명 서술자는 없다.

이는 게임의 3D 메시를 다시 렌더한 장면이 아니다. 생성 원화와 배치 시안을 확인했으나 실제 게임 화면의 시각적 동일성을 검증했다고 주장하지 않는다. 실제 논문의 정보는 이야기 JSON에 보존하며 등장 박사와 차원문은 창작이다. 원화·프롬프트·사용량·검증 기록은 `revision-07/`에 있다.

## 완료 저장과 다시보기

완료 키 `leonout_story_cat_liquid_seen_v1`은 기존 `GAME_STORAGE_KEYS` 및 로컬/Hub 저장 흐름에 포함된다. 마지막 next에서만 저장한다. 페이지 진입이나 페이지 넘기기에는 저장하지 않는다.

http://localhost:8080/web/?story=replay 는 완료 이력을 삭제하지 않고 스토리를 다시 볼 수 있는 주소다. 기존 URL에 쿼리가 있으면 `&story=replay`를 붙인다.

## 검증

- `node tests/story_intro_check.mjs`: 실제 publish FlowDriver와 렌더러/DOM 대역으로 next 전용 입력, 타이핑 중 즉시 다음 컷, 문서 엣지 2개, 대사창 무반응, 키보드, rAF 취소, 캐시 재입장, 마지막 연타 1회 저장, 재접속/다시보기, 분해된 한글 음절을 검사했고 통과했다.
- `node tests/splash_cache_check.mjs`, `node tests/ui_bare_asset_paths_check.mjs`: 기존 선로딩/에셋 경로 회귀 검사를 통과했다.
- 원화의 실제 흰 여백을 측정해 8개 컷을 분리하고 WebP 디코드·크기·해시·독백의 폭/높이를 확인했다. 오프라인 배치 이미지를 열어 프레임과 대사를 확인했다. 배치 PNG/JPG/GIF는 실제 게임 캡처가 아니다.
- 기존 publish 보고서는 2026-08-31 기록이며 errors 0개/warnings 8개다. 이번 검사 결과를 과거 보고서에 기록하지 않았다.
- 프로젝트 규칙에 따라 실제 게임의 브라우저·시각 확인은 사용자가 수행한다.

앞선 버전의 시안과 요청별 사용량은 `revision-03/`~`revision-06/`에 보존했다.
