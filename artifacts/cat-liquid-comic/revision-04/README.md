# 고양이 액체설 이야기 — 설명 포함 버전

> 이 버전은 제작 기록이다. 현재 게임은 [가로 컷·하단 타이핑 버전](../revision-05/README.md)을 사용한다.

2026-11-15. 사용자의 요청에 따라 기존 2페이지/8컷에 한국어 설명과 짧은 대사를 넣었다. 새 이미지 생성 요청은 하지 않았으며 `revision-03/`의 Sunburst 원화와 전체 그림 영역을 유지했다.

각 컷 아래에 흰 설명칸 64px을 붙이고 기존 테두리와 같은 갈색으로 Nanum Gothic Bold 15.5px 텍스트를 합성했다. 결과는 2배 해상도의 384×698 WebP이며, 실행 중 폰트 로딩이 필요 없다. 컷이 찍히는 기존 240/1320/2480/3640ms 타이밍과 200ms 모션, 4040ms의 `next` 등장, 수동 페이지 넘김, 밑줄 친 `skip`을 유지했다. 늘어난 컷이 화면에 들어오도록 배치와 버튼의 세로 위치를 조정했다.

## 줄거리와 출처

1. ‘고양이 액체설’ 논문에 호기심을 가진 창작 속 박사.
2. 실험실에서 차원문에 빨려 들어가는 사고.
3. 컵고양이·박스고양이와 만나는 낯선 세계.
4. 용기에 몸을 맞추는 고양이들의 발견.
5. 초록 고양이와 초록 차원문의 반응.
6. 인간 세상으로 이어진 차원문.
7. 따뜻한 인간 세상을 동경하는 고양이들.
8. 자신과 같은 색 차원문을 찾는 모험.

모티브는 Marc-Antoine Fardin의 「On the Rheology of Cats」, Rheology Bulletin 83(2), July 2014, pp. 16–17, 30이다. [Ig Nobel 공식 2017 물리학상 기록](https://improbable.com/ig/winners/#ig2017)에서 저자·제목·출판 정보를 확인했다. 논문은 고양이의 유연한 모습에 유변학을 적용한 연구이며 실제 액체임을 증명했다고 서술하지 않는다. 등장 박사·차원문·고양이 모험은 창작 설정이다.

## 파일과 확인

- `page-01-board.png`, `page-02-board.png`, `two-page-board.jpg`: 설명을 포함한 오프라인 배치 이미지. 두 페이지의 실제 글자와 잘림 여부를 파일로 확인했다. UI 버튼은 이 이미지에 포함하지 않는다.
- `stamp-preview.gif`, `page-01-motion-frames.jpg`, `page-02-motion-frames.jpg`: 오프라인 모션 시안. 페이지당 6.4초 자동 넘김은 미리보기 전용이며 게임은 자동으로 넘기지 않는다.
- `caption-check.json`: 8컷 문구·텍스트 경계·설명칸 크기 검사 결과.
- `motion-check.json`: 누적 컷 수 0/1/2/3/4/4, 정착 후 픽셀 유지와 GIF 길이 12,800ms 검사.
- 문구와 배치의 기준은 `resources/story/cat-liquid-intro.json`이다. `python3 artifacts/cat-liquid-comic/revision-03/render_preview.py`로 현재 버전을 재생성한다. 글꼴은 로컬의 Nanum Gothic Bold 파일을 사용한다.

게임 연결은 `node tests/story_intro_check.mjs`로 검사한다. 실제 브라우저 표시의 최종 확인은 프로젝트 규칙에 따라 사용자에게 남긴다.
