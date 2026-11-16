# 만화 컷 등장 효과음

2026-11-15. 사용자가 열어 둔 인증된 UI Editor Asset Store의 Sounds 탭에서 고유 사운드420개를 확인했다. 검색은 제목·설명·태그 대상이며 paper/종이/넘기/flip은 해당 결과가 없었다. page/book/turn 검색으로 책/카드 후보를 좁혔다. 인기 Top20은 검색과 무관하게 남으므로 검색 결과에 포함하지 않았다.

선택: `ui_card_turn_optimized.mp3` (`d8ce9978-c63f-496e-b3dd-8a0918e05ff6`, magiccoin). 종이 넘김 전용 명칭의 리소스를 찾지 못해 카드 넘김 리소스를 선택했다. 책 열기/닫기도 내려받아 길이·레벨을 측정했다. 어시스턴트의 오디오 입력은 지원되지 않아 직접 청음했다고 주장하지 않는다.

| 후보 | 디코드 길이 | 평균 RMS | 피크 |
| --- | ---: | ---: | ---: |
| ui_card_turn_optimized.mp3 | 0.5897초 | -25.6 dBFS | -3.5 dBFS |
| ui_book_open_optimized.mp3 | 0.6224초 | -24.0 dBFS | -0.4 dBFS |
| ui_book_close_optimized.mp3 | 0.6313초 | -21.8 dBFS | 약 0 dBFS |

스토어의 다운로드는 브라우저 파일 저장이 아니라 이미 열린 프로젝트 에디터로 전달하는 기능이다. 원본3개는 `src/assets/sounds/`에 저장되었고 선택한 파일만 `src/sound/`, `web/sound/`로 바이트 그대로 복사했다. 잘라내기/음량 정규화/합성 없이 두 셸의 기존 SoundManager 콜백에 gain0.8로 연결하고 AUDIO_ASSETS 미리 로드에 추가했다. 일반 팝업 소리는 ui_pop.mp3를 계속 사용한다.

Node 스토리/에셋/캐시 검사 통과. 두 셸의 새 경로/사전 로드/단발 호출/음소거 토글 연결을 검사하고 로컬 HTTP 응답과 파일 해시를 대조했다. 스토리 비교 검사에서는 에디터가 추가하는 빈 curtainLayersContract 배열만 publish 생략과 동등하게 취급하며 나머지 필드를 계속 비교한다. 흐름 엣지 추가/삭제0, publish errors0/warnings8. 실제 게임 청음은 사용자 확인 대상이다.

[다시보기](http://localhost:8080/web/?story=replay&sfx=card-turn) · [선택 원본](../../src/sound/ui_card_turn_optimized.mp3)

`catalog-sound.json`은 화면 DOM에서 수집한 이름/ID/태그, `selection.json`은 선택·측정·검사 기록이다. 로그인 토큰이나 사용자 계정 정보는 저장하지 않았다.
