# 가로 네 컷과 하단 타이핑 대사

2026-11-15. 사용자가 승인한 구성: 가로로 긴 네 컷을 한 줄에 한 장씩 세로로 쌓고, 가장 아래 고정 창에서 대사를 한 글자씩 출력한다. 추가 요청으로 상점의 `common_bg_pt_3.png`와 86px 타일·오른쪽 위 18초 스크롤 설정을 그대로 사용한다. 버튼은 배경과 구분되도록 흰 글자와 기존 파란 외곽선으로 표시한다.

## 진행

첫 컷은 입장 240ms 후 200ms 동안 찍히고, 정착 후 38ms마다 한 글자씩 대사가 출력된다. 한글은 `Intl.Segmenter('ko', {granularity:'grapheme'})`로 자모를 묶어 출력한다. 타이핑 중 터치는 현재 문장을 즉시 완성한다. 완료 후 다시 터치해야 다음 컷이 추가되고, 이전 컷은 남는다. 네 번째 대사가 끝난 뒤에만 `next`가 보이며 조건 판정도 잠금 상태를 확인한다. `skip`은 언제든 완료 이력을 저장하고 로비로 간다. 페이지를 여는 것만으로 완료 처리하지 않는다.

레이아웃은 두 StoryIntro 계약과 `.ui-editor` 원본에 함께 반영했다. `story.panel01`~`panel08`·`nextReady` visibility 위젯과 `story.dialogue`·`hint` 텍스트 바인딩을 공개 API로 갱신한다. 페이지 이동은 기존 FlowDriver가 담당한다. 씬 이탈·건너뛰기는 타이핑 rAF와 진행 이벤트 구독을 해제하며, 재입장 때는 첫 컷부터 초기화한다. 스타일시트는 `cat-liquid-v6`, 모듈은 `cat-liquid-v7`, 이야기 데이터는 HTTP `no-cache`로 읽는다.

사용자의 후속 요청으로 중간 컷의 대사 완료 안내를 `next`로 바꾸고, 안내 영역을 오른쪽 정렬·안쪽 여백 16px로 맞췄다. 마지막 컷의 페이지 이동 안내와 버튼 동작은 유지한다.

## 그림과 파일

기존 세로 그림을 눌러 늘리지 않고, `revision-03`의 두 원화를 각각 참조해 Sunburst로 가로 장면을 다시 구성했다. 네 행의 실제 흰 여백을 측정해 분리한 뒤 컷을 만들었다. 게임용 파일은 `story_cat_liquid_wide_card_01.webp`~`08.webp`이며 744×290을 1/2배로 표시한다. 대사는 이미지에 포함하지 않는다.

- `page-01-generated.png`, `page-02-generated.png`, 프롬프트와 generation JSON: 실제 모델 입력·출력과 사용량.
- `page-01-board.png`, `page-02-board.png`, `two-page-board.jpg`: 상점 배경·마지막 대사를 포함한 오프라인 배치 이미지. 미리보기 버튼/한글 폰트는 Pillow용 근사이며 실제 게임 캡처가 아니다.
- `typewriter-preview.gif`: 동작 시안. 시안은 반복 재생을 위해 컷을 자동 진행한다. 게임은 매번 터치를 기다린다.
- `asset-check.json`: 생성 이미지에서 측정한 분리 좌표, 대사 경계, 게임 에셋 크기와 SHA-256.
- `render_preview.py`: 위 에셋과 오프라인 배치를 재생성한다.

줄거리의 모티브는 Fardin의 「On the Rheology of Cats」(2014)이며 박사와 차원문 모험은 창작이다. 출처와 전체 문구는 `resources/story/cat-liquid-intro.json`에 있다.

## 검증 범위

`node tests/story_intro_check.mjs`는 실제 FlowDriver와 렌더러/DOM 대역으로 초기 가림·한글 글자 출력·터치 완성/다음 컷 분리·자동 진행 금지·두 페이지의 next 잠금·완료 저장·재입장 중복 구독 방지·타이핑 도중 skip과 rAF 해제·키보드·다시보기를 검사한다. 분해된 한글 자모가 한 음절로 표시되는 사례도 검사한다. `splash_cache_check.mjs`와 `ui_bare_asset_paths_check.mjs`도 통과했다. 생성 원화와 두 페이지의 배치 이미지는 파일로 확인한다. 실제 브라우저 표시 확인은 프로젝트 규칙에 따라 사용자에게 남긴다.

## Sunburst 사용량

모델 `gpt-image-2.5-sunburst`, Flava 스킬의 `generate_image.py`, high, 1024×1536 편집 요청 2회. 재시도 없음. 입력 텍스트 1,633토큰, 입력 이미지 3,072토큰, 출력 이미지 2,744토큰. 추정 합계 $0.0575305 / ₩80.54 (미반올림 USD 합계에서 $1=₩1,400으로 환산).
