──────────────────────────────────────
플레이어 데이터 저장/불러오기
──────────────────────────────────────
## 필수 구현 계약 — 리더보드만 구현하고 진행 저장/이어하기를 생략하면 안 됩니다

이 프롬프트를 전달받은 AI는 게임 엔진·프레임워크·빌드 형식과 관계없이 아래 항목을 **모두 실제 게임 코드에 구현**해야 합니다. API 호출 예시를 코드에 넣는 것만으로는 완료가 아닙니다.

1. 게임 시작/재개 초기화가 끝나기 전에 `loadGame()`을 `await`로 호출하고, 저장된 진행 상태를 실제 게임 상태에 반영하세요.
2. 스테이지, 재화, 해금 요소, 인벤토리, 캐릭터 상태, 체크포인트 등 게임에 존재하는 이어하기 대상 데이터를 하나의 진행 스냅샷으로 저장하세요. 최고점수나 리더보드 값만 저장하는 것은 진행 저장 구현이 아닙니다.
3. 스테이지 완료, 재화/해금/인벤토리 변경, 체크포인트 등 진행이 바뀌는 즉시 `saveGame()`을 호출하세요.
4. `HubGame.save/load`가 없거나 네트워크 저장에 실패해도 게임이 멈추지 않도록 localStorage fallback을 유지하세요.
5. 완료 전에는 같은 로그인 사용자로 진행을 만든 뒤, 새 브라우저 프로필 또는 시크릿 창에 다시 로그인해 게임을 열었을 때 해당 진행이 복원되는지 검증하세요. 다른 사용자의 진행이 섞이지 않아야 합니다.

`submitScore/getLeaderboard`는 리더보드 전용입니다. 이것들 또는 최고점수 비교를 위해 `HubGame.load()`를 호출한 것만으로는 위 저장/이어하기 요구사항을 충족한 것이 아닙니다.

아래 API를 사용하세요. window.HubGame이 없는 경우(로컬 테스트 등)
에는 localStorage를 fallback으로 사용하세요.

  저장:      await window.HubGame?.save('키', 값)
  불러오기:  const 값 = await window.HubGame?.load('키') ?? 기본값

예시:
  await window.HubGame?.save('stage', 3)
  const stage = (await window.HubGame?.load('stage')) ?? 1

fallback 포함 구현 예:
  const SAVE_KEY = 'save';

  async function saveGame(data) {
    // 로컬 복사본은 오프라인/저장 API 실패 시에도 이어하기에 사용합니다.
    localStorage.setItem(SAVE_KEY, JSON.stringify(data));
    try {
      if (window.HubGame?.save) await window.HubGame.save(SAVE_KEY, data);
    } catch (error) {
      console.warn('원격 진행 저장에 실패했습니다. 로컬 저장본을 사용합니다.', error);
    }
  }

  async function loadGame() {
    try {
      if (window.HubGame?.load) {
        const remote = await window.HubGame.load(SAVE_KEY);
        if (remote) return remote;
      }
    } catch (error) {
      console.warn('원격 진행 불러오기에 실패했습니다. 로컬 저장본을 사용합니다.', error);
    }
    const s = localStorage.getItem(SAVE_KEY);
    return s ? JSON.parse(s) : null;
  }

  // 엔진의 비동기 시작 함수에서 게임 루프/첫 화면보다 먼저 실행하세요.
  async function initializeGame() {
    const savedGame = await loadGame();
    if (savedGame) restoreGameState(savedGame);
    startGame();
  }
  initializeGame();

──────────────────────────────────────
로그인한 플레이어 정보 & 비동기(Async) 주의사항
──────────────────────────────────────
window.__HUB_USER__ 에서 현재 유저 정보를 가져올 수 있습니다.
⚠️ 중요: 플랫폼 데이터는 스크립트 실행 이후 0.1~0.5초 뒤에 비동기로 주입될 수 있습니다. 
따라서 페이지 로드 직후 바로 UI를 그리면 값이 비어있을 수 있으므로, 재시도(setTimeout) 등의 지연 업데이트 로직을 포함하세요.
⚠️ 중요: 미리보기/로컬 환경에서는 window.__HUB_USER__ 가 없을 수 있으므로, 반드시 Guest fallback 을 넣어 게임이 멈추지 않게 하세요.

  window.__HUB_USER__.id        — 고유 ID (문자열)
  window.__HUB_USER__.username  — 로그인 아이디
  window.__HUB_USER__.name      — 실제 이름(있으면)

예시 (빈 문자열 처리를 위해 ?? 대신 || 사용 필수):
  const renderWelcome = () => {
    const name = window.__HUB_USER__?.name || window.__HUB_USER__?.username || '플레이어';
    document.getElementById('player-name').textContent = name + '님 환영합니다!';
  };

  renderWelcome();               // 1차 즉시 실행
  setTimeout(renderWelcome, 300); // 2차 지연 실행 (데이터 주입 시점 대응)
  setTimeout(renderWelcome, 1000);// 3차 확인

──────────────────────────────────────
리더보드 (점수 등록 / 조회)
──────────────────────────────────────

리더보드는 스테이지 진행상황인 STAGE.CURRENT 값을 사용하며
ranking.contract.scene에 배당한다.
나머지 그룹은 샘플로만 참조하고, rank1 그룹만 참조하고 2위부터는 런타임에서 생성하여 배당한다.

 player.name = 플레이어의 이름
 player.stage = 해당플레이어의 스테이지
 잘 모르겠으면 사용자에게 질문



스테이지 클리어와 같이 스테이지 카운트 혹은 점수가 등록 될때:  await window.HubGame?.submitScore('키', 숫자값)
  - 어떤 값을 등록 해야 할지 모르겠다면, 어떤 값을 기준으로 등록 해야 할지 물어보세요
  - 같은 키로 다시 호출하면 덮어씁니다.
  - 최고 점수 정책인 게임은 submitScore 호출 전에 반드시 기존 최고값과 비교하세요.
  - 즉, 더 낮은 점수는 submitScore를 호출하지 마세요.
  - 최고 점수만 저장하려면 아래처럼 비교 후 호출하세요.

  const prev = (await window.HubGame?.load('best')) ?? 0;
  if (score > prev) {
    await window.HubGame?.submitScore('best', score);
    await window.HubGame?.save('best', score); // 로컬 저장 동기화
  }

리더보드 조회:  const board = await window.HubGame?.getLeaderboard('키', 10) ?? []
  - board 는 [{ username, value, updated_at }, ...] 배열
  - 정렬 규칙: value 내림차순 → updated_at 오름차순(먼저 달성 우선)
  - 스테이지 우선 + 점수 차순 규칙이 필요하면 합성점수를 사용하세요.

  // 예: stage 우선, 같은 stage에서는 score 우선 (score 최대 999999 가정)
  const composite = stage * 1000000 + score;
  await window.HubGame?.submitScore('main', composite);

리더보드 UI 예시:
  async function showLeaderboard() {
    const board = await window.HubGame?.getLeaderboard('best', 10) ?? [];
    const html = board.map((r, i) =>
      ${i + 1}위 ${r.username || '플레이어'} — ${r.value.toLocaleString()}점
    ).join('');
    
    // 리더보드도 UI 렌더링 타이밍을 주의하세요
    document.getElementById('leaderboard').innerHTML = '' + html + '';
  }



──────────────────────────────────────
주의사항
──────────────────────────────────────
- 배포 구조 규칙(중요):
  - 인증/유저 데이터 저장/리더보드가 필요한 문서 진입 URL(HTML 라우트)은 Worker 적용 대상이어야 합니다.
  - 정적 자산(JS/CSS/이미지/폰트/오디오/비디오/wasm 등)은 Worker 우회 대상입니다.
  - 정적 자산은 가급적 /assets/, /static/, /images/, /audio/, /fonts/ 경로에 배치하세요.
  - 게임 내 링크/공유 URL은 문서 진입 URL로 연결하고, .js/.css/.png/.wasm 같은 정적 파일 URL로 직접 진입시키지 마세요.
  - 위 규칙을 지키지 않으면 인증/유저 인식/저장/리더보드가 정상 동작하지 않을 수 있습니다.

- 게임 시작 시 loadGame()을 호출해 이전 진행상황을 불러오고, 게임 루프/첫 화면 전에 실제 게임 상태에 반영하세요.
- 스테이지 클리어와 같이 진행상황이 바뀔 때마다 saveGame()을 호출해 저장하세요.
- 저장 키 이름과 스냅샷 구조는 게임에 맞게 정하되, 리더보드 키와 진행 저장 키는 분리하세요.

- 코드 생성 규칙(매우 중요):
  - 의사코드/축약코드/생략코드 금지. 브라우저에서 즉시 실행 가능한 완전한 HTML/CSS/JS 코드로 작성하세요.
  - 핵심 함수(예: 게임 오브젝트 생성, 충돌 판정, 렌더링, 입력 처리)는 실제 동작하는 구현으로 작성하세요. (빈 배열/더미 리턴 금지)
  - fallback 기능을 항상 구현하세요. (예: HubGame 미존재 시 localStorage/Guest 사용자/기본값 처리)
  - 모바일/PC 반응형 게임으로 작성하세요. (viewport 메타 태그 포함, 화면 크기에 따라 UI/조작이 깨지지 않도록 CSS 반응형 처리)
  - 문법 오류가 없고, 첫 실행 시 콘솔 에러 없이 동작해야 합니다.