# 사선 만화 프레임과 간결한 대사

2026-11-15. 사용자의 Pinterest 만화 프레임 검색 링크에서 실제 검색 결과를 열어 검은 컷 선·흰 여백·사선 경계·집중선을 확인했다. 로그인 안내가 검색 결과를 가렸지만 검색 결과 DOM에 표시된 공개 이미지 주소를 직접 열어 프레임을 관찰했다. 특정 핀 전체를 복제하지 않고 기존 가로 네 컷에 이 요소를 적용했다.

- 검색: https://kr.pinterest.com/search/pins/?q=%EB%A7%8C%ED%99%94%20%ED%94%84%EB%A0%88%EC%9E%84&rs=typed
- 관찰한 예시: https://i.pinimg.com/474x/03/dc/df/03dcdf244f5f83c44d4038dcb2e43a6a.jpg
- 관찰 화면: `reference-frame.jpg`. 게임 화면 캡처가 아니다.

컷은 2.5px 검은 선과 3px 흰 가장자리, 네 가지 사선 외곽을 사용한다. 그림의 얼굴이나 몸에 원근 변형을 가하지 않고 가장자리만 마스킹했다. 집중선은 차원문 사고 장면에만 추가했다. 하단 대사창도 각진 검은 테두리로 맞췄다. 기존 Sunburst 그림을 재사용했으며 이번에는 이미지 생성 요청이나 추가 생성 비용이 없다.

8개 대사는 ‘들어갔어요’, ‘반짝였죠’, ‘찾아가렴’ 같은 동화식 서술을 줄이고 짧은 관찰·대화로 바꿨다. 예: “잠깐, 좌표 설정 안 했는데?!” / “컵이든 상자든 몸을 맞춘다고? 논문보다 더한데.” 연구·차원문 사고·컵/박스 고양이·같은 색 차원문·인간 세계라는 줄거리는 유지한다.

상점 배경, 네 컷 누적 등장, 하단 한글 타이핑, 오른쪽 `next`, 밑줄 친 `skip`, 첫 입장/다시보기 흐름은 유지한다. UI Editor 원본과 실행용 StoryIntro 계약에 같은 이미지 경로와 대사창 스타일을 반영했다. 에셋은 `story_cat_liquid_ink_card_01.webp`~`08.webp`와 `story_cat_liquid_impact_ink.png`다.

`python3 artifacts/cat-liquid-comic/render_preview.py`는 원화 재생성 없이 프레임과 오프라인 시안을 만든다. `asset-check.json`에 원화 해시·외곽 좌표·대사 경계·새 에셋 해시를 기록한다. `two-page-board.jpg`, `page-01-board.png`, `page-02-board.png`, `typewriter-preview.gif`는 Pillow 배치 시안이며 실제 게임 캡처가 아니다. GIF는 미리보기용 자동 진행이고 게임은 터치를 기다린다.

검증: 기존 `story_intro_check.mjs`·`splash_cache_check.mjs`·`ui_bare_asset_paths_check.mjs`의 흐름/캐시/경로 검사가 통과했다. 대사 폭과 에셋 디코드를 검사하고, 프레임의 양옆 잘림을 줄인 뒤 오프라인 배치 이미지를 다시 확인했다. localhost의 HTML·CSS·데이터·계약·프레임·타격선 14개 응답이 작업 폴더와 일치한다. 기존 publish 보고서는 errors 0개/warnings 8개이며 재생성하지 않았다. 실제 게임의 시각·브라우저 확인은 프로젝트 규칙에 따라 사용자가 수행한다. 다시보기: http://localhost:8080/web/?story=replay
