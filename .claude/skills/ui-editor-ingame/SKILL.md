---
name: ui-editor-ingame
description: 인게임 카트리지(실제 게임플레이 모듈)를 새로 만들거나 수정할 때 사용. 게임플레이 로직 구현, GameField 마운트, 게임 초기화·시작·일시정지·강제종료 생명주기(Initialize/StartGame/PauseGame/ResumeGame/ForceQuit), HUD(점수·이동수) 갱신, GameSession 프로토콜 관련 요청이 오면 이 스킬을 따른다. 아웃게임(로비·샵·팝업) 연결은 ui-editor-game 스킬 참조.
---

<!-- 자동생성: ui-editor publish가 이 파일을 게임 프로젝트에 복사·갱신한다. 직접 수정 금지(수정은 ui-editor 저장소 game-skill/에서). -->

# 인게임 카트리지 제작 가이드

인게임(실제 게임플레이)은 **카트리지**로 만든다. 카트리지는 아웃게임의 내부를 전혀 모르고, 아웃게임도 카트리지의 내부를 모른다. 아웃게임이 인게임의 로드·시작·종료 시점을 통제할 수 있도록, 카트리지는 아래 **생명주기 인터페이스를 반드시 구현**한다 — 이 규약만 지키면 카트리지를 통째로 교체해도 게임이 동작한다.

> **Godot 게임**: 이 계약은 publish 산출물 `godot-bridge.js` 가 대신 구현한다 — 카트리지를 직접 만들지 말고, GDScript 측 규약(`ui_bridge.gd`)과 §4 금지 규칙(전역·저장소)의 예외 조항은 `ui-editor-game` 스킬 §5 "Godot 웹 익스포트 브리지" 를 따른다.

## 1. 생명주기 인터페이스 — 카트리지가 구현해야 하는 메서드

`export default function createCartridge()` 가 아래 7개 메서드를 가진 객체를 반환한다. **하나라도 없으면 GameSession이 장착 시점에 즉시 실패**시킨다 (`validateCartridgeInterface`).

| 메서드 | 호출 시점·책임 |
|---|---|
| `mount(el, session)` | 게임필드 div 장착. `el` 내부에만 그린다. `session` 은 보관해서 post 에 사용 |
| `initialize(stageData)` | 아웃게임이 준 스테이지 정보(맵 구조·목표·제한 턴 수·기믹 데이터 등)로 초기화. **완료(반환/resolve) = 시작 준비됨.** 비동기 준비(에셋 로드 등)는 Promise 반환 — 10초 내 미완료 시 강제 종료됨 |
| `startGame()` | 플레이 시작 — 터치 활성화, 타이머 시작 등. **이 호출 전에는 입력을 받지 말 것** |
| `pauseGame(reason)` | 아웃게임 팝업(설정·일시정지 등)이 뜰 때 연출·타이머·입력 정지. reason: `'user'\|'popup'\|'hidden'` |
| `resumeGame()` | 재개 |
| `forceQuit(reason)` | 유저 강제 종료·이탈 시 인게임 리소스 정리(타이머·rAF·진행 중 연출). 이후 unmount 가 온다. **end 를 보내지 말 것** |
| `unmount()` | DOM 분리 정리(멱등 — 두 번 불려도 안전). 리스너 해제, 컨테이너 비우기 |
| `onMessage(topic, payload)` | **선택 구현** — 호스트 자유 메시지(설정 변경·구매 결과 등, `GameSession.message()`). 미구현이면 호스트가 경고 후 무시하므로 계약 위반이 아니다 |

**session facade** — 카트리지에게 주어지는 전부: `{ v, post(type, payload) }`. 이 외의 어떤 것도 받지 않고, 요구하지도 않는다.

```
호스트: mount → initialize(stageData)     ★ 완료가 곧 준비 신호 (별도 ready 메시지 없음)
호스트: (팝업 등 연출 후) → startGame()
카트리지: 플레이 진행, 수시로 post('hud', {...})
호스트: pauseGame(reason) ⇄ resumeGame()
카트리지: 종료 조건 충족 → post('end', { outcome, score, stats })
호스트: unmount() 후 게임필드 제거 — 카트리지 생애 끝  (이탈 시엔 forceQuit → unmount)
```

- 플레이 1회 = 인스턴스 1개. 재도전/다음 스테이지 = 새 `createCartridge()` (reset 메서드 없음).
- **클리어/실패 판정은 카트리지의 책임**, 그 **결과에 따른 보상·차감(코인·하트)은 호스트의 책임**. 카트리지는 재화를 계산하거나 저장하지 않는다.

## 2. 카트리지 → 호스트 이벤트 (`session.post(type, payload)`, protocolVersion: 1)

| type | payload | 의미 |
|---|---|---|
| `hud` | `{ score?, movesLeft?, goal?, timeLeft?, combo?, stage? }` | 부분 갱신 허용. 필드명은 이 표의 것만 |
| `progress` | 자유 정의 직렬화 객체 | 도메인 진행 이벤트 |
| `end` | `{ outcome: 'clear'\|'fail'\|'quit', score, stats? }` | 종료 보고 (outcome·score 필수) |
| `error` | `{ message }` | 복구 불가 오류 자진 보고 → 호스트가 강제 종료 |

**payload·인자는 전부 JSON 직렬화 가능해야 한다** — DOM 노드·함수·클래스 인스턴스·NaN 금지. 위반 시 GameSession이 즉시 에러를 던진다(iframe/postMessage 전환 대비 상시 검사). `initialize` 가 받는 stageData 도 마찬가지다.

## 3. HUD — 카트리지는 그리지 않는다

점수·이동수·일시정지 버튼 등 HUD는 **ui-editor Ingame 씬이 그린다**. 카트리지는 `post('hud', {...})` 로 값만 보고하면 호스트가 씬의 bindingKey(`hud.score`, `hud.moves`, `hud.goal`, `hud.time`, `hud.combo`, `hud.stage`)로 반영한다. hud 표준 필드 외의 키가 필요하면 임의로 만들지 말고 사용자에게 요청한다. **장르 특화 어휘(예: RPG의 hp/mp)는 보류 상태** — `game-skill/README.md` 의 보류 규칙에 따라 사용자 승인 전에는 도입하지 않는다.

## 4. 금지 체크리스트 — 교체 가능성을 지키는 규칙

- [ ] **컨테이너 밖 DOM 접근 금지.** mount 로 받은 el 내부만 사용. `document.body` 등에 아무것도 추가하지 않는다.
- [ ] **localStorage·sessionStorage·쿠키 금지.** 저장이 필요한 값은 `end.stats` 나 `progress` 로 호스트에 보고한다.
- [ ] **window 전역 오염 금지.** 전역 변수·전역 이벤트 리스너를 만들지 않는다. (필요한 리스너는 el 에 걸고 unmount 에서 해제.)
- [ ] **scene-renderer.js·popup-manager.js·sound-manager.js·game-session.js·economy-manager.js·progress-manager.js 를 import 하지 않는다.** 카트리지의 import 는 자기 하위 모듈만. 특히 하트·재화·스테이지 진행도는 호스트 전유 — 카트리지는 `end` 보고만 한다(별점·점수는 `end.stats`/`score` 로).
- [ ] **통신은 생명주기 메서드 인자와 post payload 의 직렬화 가능 값만.** 콜백·객체 참조를 호스트와 공유하지 않는다.
- [ ] **unmount·forceQuit 는 멱등으로.** 타이머·rAF·리스너를 전부 해제한다.
- [ ] **오류를 폴백·try/catch로 삼키지 않는다.** 원인을 추정하지 말고 로그로 판정한다. 모호하면 사용자에게 질문한다.
- [ ] **중복 함수 금지.** 같은 역할 함수가 이미 있으면 재사용하고, 신규 함수는 사용자 허가를 받는다.
- [ ] **시각적·브라우저 검증은 사용자가 수행한다.** 로직·로그 검증까지만 직접 한다.

## 5. 최소 동작 예제 — 탭 카운터 카트리지

```js
export default function createCartridge() {
  let el, session, running = false, score = 0, movesLeft = 0;
  const onTap = () => {
    if (!running) return;
    score += 1; movesLeft -= 1;
    session.post('hud', { score, movesLeft });
    if (movesLeft <= 0) { running = false; session.post('end', { outcome: 'clear', score, stats: {} }); }
  };
  return {
    mount(container, s) {
      el = container; session = s;
      el.addEventListener('pointerdown', onTap);
    },
    initialize(stageData) {              // 완료(반환) = 시작 준비됨. 비동기면 Promise 반환
      movesLeft = stageData.config.moves ?? 10;
      session.post('hud', { score, movesLeft });
    },
    startGame() { running = true; },
    pauseGame(reason) { running = false; },
    resumeGame() { running = true; },
    forceQuit(reason) { running = false; },
    unmount() { el.removeEventListener('pointerdown', onTap); el.replaceChildren(); },
  };
}
```

## 6. 참고

- 호스트 측(세션 생성·씬 연결·경제 적용)은 `.claude/skills/ui-editor-game/SKILL.md` 참조.
- Ingame 씬에는 이름이 `GameField` 인 레이어가 있어야 한다(호스트가 그 안에 게임필드 div를 만들어 mount 에 넘겨준다). 없으면 사용자에게 ui-editor에서 추가·재publish를 요청한다.
- 특정 장르를 가정한 규약·스킬(RPG 스탯, 매치3 보드 규칙 등)은 **보류** — 사용자 승인 없이 만들지 않는다.
