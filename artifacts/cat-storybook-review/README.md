# 고양이 동화풍 외곽선

2026-11-15. 고양이의 기존 툰 표면에 몸 굽힘을 따르는 색상 외곽선을 강화했다. 나무 전용 셰이더를 복사하지 않고, 실제 고양이 스킨 메시의 두 서피스에 기존 외곽선 next_pass를 사용한다.

- 고양이에만 `storybook_outline_enabled=true`: 폭 1.65배, 잉크 RGB 0.82배, 추가 외곽선 emission 제거. 위·아래 선 굵기 차이는 기존 설정을 사용한다.
- Compatibility의 깊이 역투영·기록 범위를 수정하고, 깊이 바이어스를 선 굵기와 함께 조절한다. 깊이 범위 수정은 이 셰이더를 공유하는 재질에도 적용된다. 스타일 플래그의 기본값은 false다.
- 이동 규칙, 점유, 몸 곡선, 메시 비율, 카메라와 맵 배치는 변경하지 않았다. 기존 흡입 빛/클리핑과 수면 거품 분기를 보존했다.

## 실제 렌더

Godot `4.7.2.stable.official.ed1daf0bf`, Compatibility/OpenGL, Apple M3 Pro. `tests/capture_length.tscn`에서 현재 메인 카메라·조명과 실제 고양이 템플릿을 사용했다. 테스트 중 스테이지 자동 로드를 끄고 보드의 테스트 고양이만 바꿨다.

- `comparison.png`: 동일한 좁은 U자·짧은 L자 자세의 수정 전/후를 2배 최근접 확대. `before/2_tight_bends.png`, `after/2_tight_bends.png`가 전체 화면 원본이다.
- `after/0_straight.png`, `after/1_bent.png`: 직선 길이 3/6/9, S자 길이 12와 L자 길이 7.
- `after/bend-motion.gif`: 좁은 U자 고양이가 실제 이동 API로 한 칸 전진하는 17프레임. 위 비교와 같은 영역을 확대했다. 재생 끝에서 시작으로 돌아가는 점프는 GIF 반복이다. 각 표본은 이동 길이의 1/16 간격이며 실시간 성능 측정 영상이 아니다.
- `after/web-lobby.png`: 기존 Codex 브라우저 탭에서 로컬 웹 내보내기를 새로고침하고 로비를 연 실제 화면. 이 확인 시 warn/error 브라우저 로그는 빈 배열이었다.

검사한 자세에서는 선이 몸 변형을 따라가고, 좁은 U자 안쪽에 외곽선이 몸을 가로질러 나타나지 않았다. 모든 가능한 몸 겹침이나 모바일 GPU까지 보장하는 결과는 아니다.

## 자동 검사

같은 Godot 실행 파일로 `--headless --path . tests/length_check.tscn`과 `tests/hole_check.tscn` 실행: 각각 `LENGTH CHECK: PASS`, `HOLE CHECK: PASS`. 두 스킨 서피스의 외곽선 연결·스타일 플래그와 열쇠의 기본 스타일 유지, 기존 길이·굽힘·흡입 검사를 확인했다.

웹 내보내기 `--export-release Web web/index.html` 성공. 네이티브 캡처와 헤드리스 종료에는 이전 기준 실행에도 있던 shader RID 해제 경고가 남아 있으며 이번 변경에서 수정하지 않았다. 헤드리스 검사는 렌더 모양 검증을 대신하지 않는다.
