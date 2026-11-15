# 고양이 액체 이야기 — 게임 연결 기록

2026-11-15. `revision-03/`의 무문자 만화 2페이지/8컷을 기존 웹 게임의 첫 입장에 연결했다. 이번 만화에 한해 사용자가 새 UI 씬 2개·다음/건너뛰기 이벤트·진입 분기·필요한 연결 코드의 직접 추가를 명시적으로 승인했다. 이 예외는 다른 UI 작업에 적용하지 않는다.

같은 날 사용자가 설명을 요청해 `revision-04/`에서 한글 설명칸을 붙였고, `revision-05/`에서 가로 네 컷과 하단 타이핑 대사·상점 배경을 연결했다. 현재 `revision-06/`은 같은 그림에 사선 만화 프레임을 적용하고, 동화식 설명 어미를 짧은 상황 서술과 대화로 바꾼 버전이다. 744×290 WebP를 1/2배로 표시한다. 글자는 이미지에 굽지 않고 SceneRenderer의 `story.dialogue`·`story.hint` 바인딩으로 표시한다.

## 실제 흐름

1. 기존 splash에서 로딩을 완료하고 화면을 터치한다.
2. 완료 이력이 없으면 `StoryIntro01`로 들어간다. 240ms 뒤 첫 가로 컷이 찍히고 하단 대사를 38ms마다 한 글자씩 출력한다.
3. 타이핑 중 터치하면 현재 대사를 완성하고, 완료 후 별도의 터치로 다음 컷이 추가된다. 네 번째 대사까지 완료되면 `next`가 나타난다. 누르면 `StoryIntro02`가 같은 방식으로 진행된다.
4. 2페이지의 `next` 또는 어느 페이지의 밑줄 친 `skip`을 누르면 완료를 기록하고 기존 navigation의 로비 홈 탭으로 이동한다.
5. 이후 입장에서는 기존 splash → 로비로 간다. 진행 중 새로고침하면 1페이지부터 다시 볼 수 있다.

하단 창에는 장면별 2줄의 설명·대사가 있고 컷이나 페이지를 자동으로 넘기지 않는다. 이동 버튼은 `skip`(밑줄)·`next` 텍스트다. `revision-05/typewriter-preview.gif`의 자동 진행은 오프라인 시안 확인용이다.

## 파일과 배선

| 씬 | UUID | 이벤트 |
| --- | --- | --- |
| StoryIntro01 | 91b7f29b-8b6d-41b7-a08a-99a0a1dfb401 | story-next-01:click, story-skip-01:click |
| StoryIntro02 | 91b7f29b-8b6d-41b7-a08a-99a0a1dfb402 | story-next-02:click, story-skip-02:click |

- UI Editor 원본: `.ui-editor/scenes/StoryIntro01.scene.json`, `StoryIntro02.scene.json`, `.ui-editor/scene-flow.json`, 프로젝트 씬 목록.
- 실행용 UI: `web/ui/StoryIntro01.contract.json`, `StoryIntro02.contract.json`, `scenes-index.json`, `scene-flow.json`, splash의 첫 입장 분기, 루트 `SCENES.md`.
- 런타임 훅: `web/story-intro.js`. `attachStoryIntro`가 첫 입장·건너뛰기·페이지 완료 조건, 공개 visibility/text 바인딩과 터치·타이핑을 공급한다. 페이지 전환은 FlowDriver에 맡긴다. `Intl.Segmenter`로 분해된 한글 자모도 한 음절씩 출력한다. 건너뛰기·씬 이탈 때 rAF와 이벤트 구독을 해제한다.
- 호스트: `godot-shell.html`과 `web/index.html`에서 모듈/모션 CSS를 읽고 기존 splash 디코드 대기에 두 이야기 씬을 포함한다.
- 현재 컷은 `story_cat_liquid_ink_card_01.webp`~`_08.webp` 8개다. 기존 원화를 비틀지 않고 사선 마스크와 검은 테두리·흰 테두리를 Pillow로 합성한다. 두 번째 사고 장면에만 짧은 집중선을 덧붙인다. 원화/개별 컷을 중복 선로딩하지 않는다. 새 에셋 경로와 CSS `cat-liquid-v7`로 이전 이미지 캐시와 분리하고, 이야기 데이터는 HTTP 재검증한다. JS 모듈은 `cat-liquid-v7` 그대로다.
- 레이아웃·상점과 같은 배경·버튼·대사창·표시 위젯은 계약에 있다. 자동 `sceneAnimations`를 제거하고 터치 단계마다 `.story-panel-enter`를 붙여 기존 200ms 스탬프 모션을 재생한다. `web/story-intro.css`는 타격선과 `skip` 밑줄도 지정한다.
- 배율은 1.16 → 0.96 → 1.015 → 1.0, 길이는 200ms다. 정적 회전은 이미지 안쪽 래퍼, 동적 회전은 바깥 타임라인 대상에 합성한다. Pillow와 CSS의 양의 회전 방향 차이를 반영한다.
- OS의 움직임 줄이기 설정에서는 같은 등장 순서로 카드가 즉시 나타나고 타격선을 생략한다.

새로 연결한 흐름은 5개다. splash → 이야기 1개, 두 페이지의 다음/건너뛰기 4개다. 기존 흐름은 유지하고 UI Editor 원본과 실행용 데이터를 함께 추가했다. 이번 직접 추가에 대한 중복 `scene-flow-proposed.json` 제안은 만들지 않았다. 기존의 다른 제안들은 보존했다.

## 완료 저장과 다시보기

완료 키는 `leonout_story_cat_liquid_seen_v1`이며 값은 `1`이다. 기존 `GAME_STORAGE_KEYS`에 포함해 같은 로컬/Hub 저장 스냅샷으로 복원한다. 페이지를 여는 것만으로 완료 처리하지 않으며, 마지막 진행 또는 건너뛰기에서 기록한다.

`http://localhost:8080/web/?story=replay`는 완료 이력을 삭제하지 않고 첫 입장 분기를 다시 실행한다. 기존 URL에 쿼리가 있으면 `&story=replay`를 덧붙인다.

## 검증

- 현재 `revision-05`: 공개 위젯/텍스트 바인딩과 두 페이지 next 조건을 대조했다. 한글 음절·터치 완성/다음 컷 분리·자동 진행 금지·페이지 완료 전 이동 차단·skip/이탈 시 rAF와 구독 정리·캐시된 renderer 재입장을 실제 FlowDriver 대역 검사로 확인했다. 상점 배경은 원본과 같은 바이트 및 스크롤 설정이며, localhost의 HTML/JS/CSS/스토리/계약/흐름/이미지 17개 응답이 작업 폴더와 일치했다. 두 HTML 모듈 문법도 통과했다. 실제 브라우저의 시각 확인과 구분한다.
- `node tests/story_intro_check.mjs`: 실제 publish FlowDriver와 렌더러/DOM 대역으로 첫 입장, 로딩 전 진입 차단, 두 페이지, 완료 저장, 1·2페이지 건너뛰기, 재접속, 다시보기, 키보드 동작 검사.
- `node tests/splash_cache_check.mjs`, `node tests/ui_bare_asset_paths_check.mjs`: 기존 선로딩/에셋 경로 회귀 검사.
- 2026-11-15 로딩 정지 수정: 열린 게임 탭의 로그에서 `[Splash preload] 네비게이션 탭 contract 누락: StoryIntro01`을 확인했다. Cache API 제외만으로는 이전 HTTP 캐시가 반환될 수 있어, 호스트의 UI JSON 요청을 `cache: 'no-cache'`로 재검증한다. `splash_cache_check.mjs`에 오래된 HTTP 응답 재현을 추가했고 수정 전 실패/수정 후 통과했다. 서버 파일 존재 검사와 씬 전환 대역 검사만으로 이 캐시 문제를 검증했다고 보지 않는다.
- 두 HTML의 module 스크립트 문법과 `git diff --check`.
- Pillow로 모든 WebP/타격선 PNG를 디코드하고 크기·SHA-256 검증. 인코딩한 GIF에서 페이지별 누적 컷 0/1/2/3/4/4와 정착 후 픽셀 유지, 길이 12,800ms 확인.
- localhost:8080의 HTML·연결 모듈·모션 CSS·흐름·새 계약·이미지가 실제 작업 폴더의 내용과 일치하는지 검사.
- 기존 `web/ui/publish-report.json`에는 errors 0개, warnings 8개다. 이 파일은 2026-08-31 publish 기록이며 새 통합 검사를 실행했다고 표시하거나 수정하지 않았다.

프로젝트 규칙에 따라 실제 브라우저의 시각 확인은 사용자에게 남긴다. 자동 검사 통과를 실제 화면의 시각적 일치 판정으로 보고하지 않는다.
