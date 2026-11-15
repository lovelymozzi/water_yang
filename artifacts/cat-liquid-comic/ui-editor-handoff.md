# 고양이 액체 이야기 — 게임 연결 기록

2026-11-15. `revision-03/`의 무문자 만화 2페이지/8컷을 기존 웹 게임의 첫 입장에 연결했다. 이번 만화에 한해 사용자가 새 UI 씬 2개·다음/건너뛰기 이벤트·진입 분기·필요한 연결 코드의 직접 추가를 명시적으로 승인했다. 이 예외는 다른 UI 작업에 적용하지 않는다.

## 실제 흐름

1. 기존 splash에서 로딩을 완료하고 화면을 터치한다.
2. 완료 이력이 없으면 `StoryIntro01`로 들어간다. 네 컷이 240/1320/2480/3640ms에 하나씩 추가된다.
3. 마지막 컷 정착 후 4040ms에 `next` 글자 버튼이 나타난다. 누르면 `StoryIntro02`가 같은 방식으로 재생된다.
4. 2페이지의 `next` 또는 어느 페이지의 밑줄 친 `skip`을 누르면 완료를 기록하고 기존 navigation의 로비 홈 탭으로 이동한다.
5. 이후 입장에서는 기존 splash → 로비로 간다. 진행 중 새로고침하면 1페이지부터 다시 볼 수 있다.

만화에는 글자를 표시하지 않으며 페이지를 자동으로 넘기지 않는다. 이동 버튼은 사용자 요청으로 X·화살표 대신 `skip`(밑줄)·`next` 텍스트로 변경했다. `revision-03/stamp-preview.gif`의 페이지당 6.4초 자동 전환/반복은 시안 확인용이다.

## 파일과 배선

| 씬 | UUID | 이벤트 |
| --- | --- | --- |
| StoryIntro01 | 91b7f29b-8b6d-41b7-a08a-99a0a1dfb401 | story-next-01:click, story-skip-01:click |
| StoryIntro02 | 91b7f29b-8b6d-41b7-a08a-99a0a1dfb402 | story-next-02:click, story-skip-02:click |

- UI Editor 원본: `.ui-editor/scenes/StoryIntro01.scene.json`, `StoryIntro02.scene.json`, `.ui-editor/scene-flow.json`, 프로젝트 씬 목록.
- 실행용 UI: `web/ui/StoryIntro01.contract.json`, `StoryIntro02.contract.json`, `scenes-index.json`, `scene-flow.json`, splash의 첫 입장 분기, 루트 `SCENES.md`.
- 런타임 훅: `web/story-intro.js`. `attachStoryIntro`가 `story.firstEntry`/`story.complete` 조건과 버튼의 키보드·접근성 레이블만 공급한다. 버튼 전환은 FlowDriver에 맡긴다.
- 호스트: `godot-shell.html`과 `web/index.html`에서 모듈/모션 CSS를 읽고 기존 splash 디코드 대기에 두 이야기 씬을 포함한다.
- 컷은 원화에서 추출한 `story_cat_liquid_card_01.webp`~`_08.webp` 8개를 사용한다. 테두리·그림자는 GIF와 같은 Pillow 코드로 합성한다. 프레임용 WebP와 원화/개별 컷을 중복 선로딩하지 않는다.
- 레이아웃과 글자 버튼은 계약에 있고, 등장 타이밍은 SceneRenderer의 기본 `sceneAnimations`로 실행한다. `web/story-intro.css`는 카드 등장 키프레임·짧은 타격선과 `skip` 텍스트의 밑줄을 지정한다.
- 배율은 1.16 → 0.96 → 1.015 → 1.0, 길이는 200ms다. 정적 회전은 이미지 안쪽 래퍼, 동적 회전은 바깥 타임라인 대상에 합성한다. Pillow와 CSS의 양의 회전 방향 차이를 반영한다.
- OS의 움직임 줄이기 설정에서는 같은 등장 순서로 카드가 즉시 나타나고 타격선을 생략한다.

새로 연결한 흐름은 5개다. splash → 이야기 1개, 두 페이지의 다음/건너뛰기 4개다. 기존 흐름은 유지하고 UI Editor 원본과 실행용 데이터를 함께 추가했다. 이번 직접 추가에 대한 중복 `scene-flow-proposed.json` 제안은 만들지 않았다. 기존의 다른 제안들은 보존했다.

## 완료 저장과 다시보기

완료 키는 `leonout_story_cat_liquid_seen_v1`이며 값은 `1`이다. 기존 `GAME_STORAGE_KEYS`에 포함해 같은 로컬/Hub 저장 스냅샷으로 복원한다. 페이지를 여는 것만으로 완료 처리하지 않으며, 마지막 진행 또는 건너뛰기에서 기록한다.

`http://localhost:8080/web/?story=replay`는 완료 이력을 삭제하지 않고 첫 입장 분기를 다시 실행한다. 기존 URL에 쿼리가 있으면 `&story=replay`를 덧붙인다.

## 검증

- `node tests/story_intro_check.mjs`: 실제 publish FlowDriver와 렌더러/DOM 대역으로 첫 입장, 로딩 전 진입 차단, 두 페이지, 완료 저장, 1·2페이지 건너뛰기, 재접속, 다시보기, 키보드 동작 검사.
- `node tests/splash_cache_check.mjs`, `node tests/ui_bare_asset_paths_check.mjs`: 기존 선로딩/에셋 경로 회귀 검사.
- 2026-11-15 로딩 정지 수정: 열린 게임 탭의 로그에서 `[Splash preload] 네비게이션 탭 contract 누락: StoryIntro01`을 확인했다. Cache API 제외만으로는 이전 HTTP 캐시가 반환될 수 있어, 호스트의 UI JSON 요청을 `cache: 'no-cache'`로 재검증한다. `splash_cache_check.mjs`에 오래된 HTTP 응답 재현을 추가했고 수정 전 실패/수정 후 통과했다. 서버 파일 존재 검사와 씬 전환 대역 검사만으로 이 캐시 문제를 검증했다고 보지 않는다.
- 두 HTML의 module 스크립트 문법과 `git diff --check`.
- Pillow로 모든 WebP/타격선 PNG를 디코드하고 크기·SHA-256 검증. 인코딩한 GIF에서 페이지별 누적 컷 0/1/2/3/4/4와 정착 후 픽셀 유지, 길이 12,800ms 확인.
- localhost:8080의 HTML·연결 모듈·모션 CSS·흐름·새 계약·이미지가 실제 작업 폴더의 내용과 일치하는지 검사.
- 기존 `web/ui/publish-report.json`에는 errors 0개, warnings 8개다. 이 파일은 2026-08-31 publish 기록이며 새 통합 검사를 실행했다고 표시하거나 수정하지 않았다.

프로젝트 규칙에 따라 실제 브라우저의 시각 확인은 사용자에게 남긴다. 자동 검사 통과를 실제 화면의 시각적 일치 판정으로 보고하지 않는다.
