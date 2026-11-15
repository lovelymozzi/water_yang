# 흡입 추가 이펙트 제거

2026-11-15. `fx_char_levelup_01`의 게임 중 생성·사전 재생을 제거하고, 고양이 네 재질의 `absorb_light_portal`을 0으로 고정했다. 차원문의 기존 상시 이펙트와 흡입 경로·흔들림·클리핑·소리·완료 처리는 유지한다. 원본 이펙트 파일은 보관한다.

`absorption.gif`는 Godot `4.7.2.stable.official.ed1daf0bf` Compatibility/OpenGL에서 실제 1레벨 해법으로 첫 고양이를 흡입시킨 13개 캡처다. 표본은 0.05초 간격이며 GIF는 관찰을 위해 프레임당 0.1초로 재생한다. 마지막→첫 프레임의 점프는 반복 재생이다. 큰 빛줄기나 몸을 덮는 발광 없이 고양이가 입구로 들어가 사라지는 것을 확인했다. 배경은 기존 미커밋 지형 작업을 포함한다.

실행: `Godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 tests/hole_check.tscn -- --absorb-capture`. 수치 검사는 `--headless --path . tests/hole_check.tscn`에서 `HOLE CHECK: PASS`. 추가 이펙트/사전 재생 부재, 네 재질의 발광 비활성, 기존 흡입/색 짝/완료/상시 차원문 동작을 검사했다. 웹 release 내보내기 성공.

네이티브에는 텍스처 초기화 로그와 종료 시 shader RID 해제 경고가, 헤드리스에는 Dummy material 조회 오류 한 건과 종료 시 RID 해제 경고가 남는다. 검사 실패·스크립트 오류는 최종 실행에 없었으며, 이를 모든 엔진 로그가 깨끗하다는 뜻으로 해석하지 않는다.
