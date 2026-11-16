# 고글 연구자, 고양이 발과 바닥 차원문 수정

2026-11-15. 사용자 첨부 이미지의 큰 고글·흰 머리·둥근 안경을 참고해 작은 체형의 괴짜 여성 발명가로 다시 그렸다. 주황 스카프·아이보리 코트·짙은 하의·부츠와 공구 가방을 유지한다. 종전 노년 남성 박사는 교체했다. 대사 없는 8컷, 네 컷 누적 등장, 하단 skip/next와 화면 면적·게임플레이·카메라는 유지한다.

## 실행 중단 원인과 수정

이야기 요청은 `cache:no-cache`였으나, 부트스트랩의 `window.fetch` 래퍼가 이를 무시하고 splash Cache API의 옛 대사형 JSON(`textMode:bottom-typewriter`)을 먼저 반환했다. 새로운 `attachStoryIntro`는 `textMode:none`을 검증해 예외를 내므로 최초 UI 표시 전에 실행이 중단되는 경로다.

`tests/splash_cache_check.mjs`에 옛 데이터를 반환하는 저장 캐시를 넣어 수정 전 실패를 재현했다. `godot-shell.html`과 `web/index.html`의 동일한 래퍼에서 `no-cache`/`reload`/`no-store` 요청은 Cache API 조회 전에 원래 fetch로 전달하도록 고쳤다. 세 요청 모드와 두 HTML에서 수정 후 통과한다. 게임 저장/완료 이력은 지우지 않고, published renderer/managers는 수정하지 않았다.

사용자 브라우저의 실제 캐시·콘솔을 읽거나 게임을 직접 실행해 확인한 결과는 아니다. 코드의 시작 중단 경로를 재현해 수정했으며, 실제 브라우저·시각 검증은 AGENTS.md에 따라 사용자가 수행한다. localhost 서버가 실행 중이고 최신 HTML/JS/JSON/만화 카드가 작업 폴더와 일치하는 것도 HTTP로 확인했다. Godot JS/wasm/pck도 200 응답과 파일 크기를 확인했다. 실제 화면에서 다른 오류가 남는지는 [다시보기](http://localhost:8080/web/?story=replay&v=cat-liquid-v10)로 확인한다.

## 그림 검토와 추가 수정

모든 컷에서 차원문은 바닥 타일과 평행한 원형 구멍, 화면에서는 눌린 타원으로 표현한다. 연구실 장치도 바닥형으로 바꿨고, 박사와 고양이는 아래로 빠져들도록 했다. 인간 세계는 바닥 구멍 안쪽을 위에서 내려다보는 구도다. 서 있는 고리/문은 없다.

고양이의 몸 하나·머리 하나·꼬리 하나와 어깨/골반 아래의 네 다리 구조를 지시하고 컷마다 원화를 열어 연결/가림을 확인했다. `art-review.json`에 포즈별 관찰을 기록했다. 가려진 다리를 억지로 전부 노출하지 않았으며, 컵 고양이는 앞발 두 개와 엉덩이 아래 뒷발, 상자 고양이는 뒷다리를 상자 안에 가린다. 마지막 컷의 최초 원화는 발 끝이 원통/절단면처럼 보여 채택하지 않고, 두 뒷발의 굽힘·둥근 발끝·발바닥 패드를 추가 편집했다. 최종 원화와 8컷 배치 시안 모두 확인했다.

원화는 첫 네 요청(2컷씩 4장)과 마지막 발 보정 1회로 구성된다. 최초 마지막 원화는 `pair-04-initial-generated.png`에 보존했다. 해당 원본 응답의 image 경로는 생성 당시 경로이며, 최종 같은 이름 파일은 보정 응답으로 새로 만든 그림이다. 그 외 재시도/실패 없음. `pair-04-correction-generation.json`이 최종 보정 사용량이다.

## 연결과 검사

- `resources/story/cat-liquid-intro.json`: revision 9, 무대사, 바닥형 제약 기록.
- `.ui-editor/scenes/StoryIntro*.scene.json`과 `web/ui/StoryIntro*.contract.json`: 새 `story_cat_liquid_floor_card_01`~`08` 연결. 옛 이미지 캐시와 URL 구분.
- CSS/JS 버전 `cat-liquid-v10`. 기존 5개 흐름 엣지 유지, 추가/제외 엣지 없음. 버튼 위치·동작·완료 저장 키 유지.
- `render_preview.py`: 실제 흰 gutter 측정 후 컷 분리, 사선 프레임/배치 시안 생성. 두 페이지 JPG/PNG와 GIF는 오프라인 시안이며 게임 캡처가 아니다.
- `story_intro_check.mjs`: next/skip, 초기 대기, 두 페이지, 재입장/다시보기/키보드/연타 정리 통과.
- `splash_cache_check.mjs`: 이전 대사 데이터 캐시 재현 후 명시적 재요청 3종/두 HTML, UI HTTP 재검증 통과.
- `ui_bare_asset_paths_check.mjs`, `git diff --check` 통과.
- 기존 publish-report는 errors 0/warnings 8이며 이번 검사 결과로 덮어쓰지 않았다.

## 사용량

스킬 기본 `scripts/generate_image.py`, Flava, `gpt-image-2.5-sunburst`, 1024×1024/high 편집 5회. 실제 응답 합계: 입력 텍스트 4,542, 입력 이미지 6,912, 출력 이미지 8,780 토큰. 추정 비용 **$0.1707030 / ₩238.98** ($1=₩1,400). 각 요청은 `generation-summary.json` 및 원본 응답 JSON에 보존했다.
