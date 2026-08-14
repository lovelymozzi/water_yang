---
name: ui-editor-game
description: ui-editor로 publish된 씬(*.contract.json, scene-renderer.js)을 게임에 연결하는 작업 시 사용. 게임 부트스트랩(title→lobby), 씬 전환·탭 네비게이션, 팝업 열기/닫기, BGM/SFX 사운드, 바인딩 데이터 주입, 씬 이벤트 구독, 인게임 카트리지 연결(GameSession)·게임 시작/클리어/실패 후 보상·하트 처리 요청이 오면 이 스킬을 따른다.
---

<!-- 자동생성: ui-editor publish가 이 파일을 게임 프로젝트에 복사·갱신한다. 직접 수정 금지(수정은 ui-editor 저장소 game-skill/에서). -->

# ui-editor 게임 통합 가이드

## 0. 작업 절차 — 읽는 순서·미배선 수리·역질문

**읽는 순서 (필요한 것만, 중복 로드 금지):**
1. `publish-report.json`(publish 폴더) — 정합성 검진 + 게임 배선 스캔. **errors 는 코드로 우회하지 말고 사용자에게 보고.**
2. `scene-flow-changes.json` — 있으면 최우선: 변경분 반영 후 파일 삭제(소비). (§6)
3. `scene-flow.json` + 루트 `SCENES.md` — 배선 대상 그래프와 씬별 이벤트/바인딩 키(여기 있는 값만 사용). 배선 방법은 §6.
4. `PROMO.md` — 있으면 이벤트/상품 배선 체크리스트. (§4 PromoManager)

**미배선 수리 루프 — 자가진단 되먹임 소비:**
- `publish-report.json` 의 `game-unwired-event`/`game-unwired-condition` = 해당 문자열이 게임 코드에 없다는 뜻 — 각 항목을 §6 절차로 배선한다. scene-flow.json 순회형 동적 배선이라 리터럴이 없는 것이면 그 사실만 사용자에게 보고.
- **FlowDriver 프로젝트(§2 표준)**: 버튼 배선은 자동이라 `game-unwired-event` 는 나오지 않는다. 남는 건 `game-unwired-condition`(→ `flow.defineCondition` 등록)과 `game-unfired-doc-edge`(→ 해당 사건 시점에 `flow.fire`) 2종 — 이것이 곧 "게임이 구현할 훅 목록"이다. 드라이버도 start() 시점에 콘솔 `[FlowDriver]` 경고와 `window.__uiWiringAudit.flow` 로 같은 목록을 보고한다.
- **런타임 자가진단**: 씬이 표시되면 scene-renderer 가 흐름 연결 이벤트의 미구독을 검사해 콘솔 `[SceneRenderer] 배선 자가진단` 경고 + `window.__uiWiringAudit` 에 씬별 목록을 쌓는다. 사용자가 이 JSON(또는 콘솔 경고)을 주면 각 `eventName` 을 §6 절차로 배선하고, **배선 후 해당 씬을 다시 열어 경고가 사라졌는지 확인을 요청**한다.
- 팝업 닫기 버튼이 죽어 있으면 대부분 `PopupManager.open` 의 `on:{}` 에 닫기 이벤트 누락 — `__close__` edge 의 `eventName` 을 `() => popups.close()` 로 배선한다.

**역질문 규약 — 추측 구현 금지.** 아래에 해당하면 구현을 멈추고 사용자에게 질문한다. 질문은 한 번에 모아서, 항목별로 `[번호] 대상 / 현상 / 제안 / 질문` 형식으로:
- **condition 키 의미 불명** — 판정식을 제안하고 확인받는다: "`hasHearts` 는 `economy.getHearts() > 0` 판정이 맞습니까?"
- **게임에 없는 시스템을 요구하는 키** — 조건·바인딩이 미구현 시스템(예: `vip.level` 인데 VIP 없음)을 가리키면 임시 스텁·하드코딩 금지, 구현 범위를 질문한다.
- **trigger 없는 문서 edge 에 label 없음** — 발생 조건(어떤 시스템 이벤트가 이 흐름을 일으키는지)을 질문한다.
- **SCENES.md 에 없는 이벤트/키가 필요** — 임의 생성 금지, ui-editor 에서 추가해 달라고 요청한다.
- **의도가 두 갈래로 읽히는 흐름** — 예: 같은 씬이 팝업으로도 전환으로도 해석될 때, 양쪽 해석과 권장안을 제시하고 고르게 한다.

**완료 보고:** 배선한 edge 수 / 의도적으로 뺀 edge 목록(사유) / 남은 질문 / publish-report errors 요약(있으면). 게임이 먼저 배선한 새 흐름은 `scene-flow-proposed.json` 으로 제안(§6).

## 1. 계층 규약 — 무엇을 수정할 수 있는가

**publish 산출물(읽기 전용, 재구현 금지)** — 아래 파일은 ui-editor가 publish마다 덮어쓴다. 절대 수정하지 말 것. 바꾸고 싶으면 사용자가 ui-editor에서 재편집·재publish한다.

- `scene-renderer.js` — 씬 렌더러. 씬과의 상호작용은 오직 이 API로만.
- `popup-manager.js` — 팝업 오버레이 매니저. 팝업을 직접 구현하지 말 것.
- `sound-manager.js` — BGM/SFX 매니저. 오디오 unlock·볼륨·뮤트를 직접 구현하지 말 것.
- `game-session.js` — 인게임 카트리지 세션 매니저. 인게임↔아웃게임 연결을 직접 구현하지 말 것.
- `economy-manager.js` — 하트·코인 매니저. 하트 재생 타이머·재화 증감·영속화를 직접 구현하지 말 것.
- `progress-manager.js` — 스테이지 진행도 매니저. 해금·클리어 기록·별점·최고점수 영속화를 직접 구현하지 말 것(localStorage 스키마 발명 금지).
- `promo-manager.js` — 이벤트/상품 프로모 매니저. 로비 도크 채우기·서프라이즈 상품 트리거를 직접 구현하지 말 것.
- `flow-driver.js` — 씬 흐름 드라이버. scene-flow.json 의 버튼 엣지·팝업·전환효과·nav 진입·이력(__back__)을 자동 실행한다. 씬 전환 코드를 직접 작성하지 말 것(§6).
- `*.contract.json` — 씬 데이터. 레이아웃·스타일·효과가 완성돼 있으므로 HTML/CSS로 다시 만들지 말 것.
- `scenes-index.json` — sceneUuid → 현재 contract 파일 해석표.
- `scene-flow.json` — 씬 연결 그래프(있는 경우).
- `promo-registry.json` — 이벤트/상품 레지스트리(있는 경우). 항목·스케줄·조건·상거래 속성의 단일 진실 — 게임 코드에 항목별 하드코딩을 만들지 말 것.
- `PROMO.md` — 이벤트/상품 운영 문서(자동 생성). 항목별 기간·조건·공급할 컨텍스트 키·배선 체크리스트 — 프로모 연동 전에 먼저 읽는다.
- `DESIGN.md` — 디자인 컨셉 가이드(팔레트·타이포·형태·효과 사용 현황 자동 집계). 게임 코드에서 씬 밖 UI(커스텀 팝업·HUD 등)를 직접 만들 때 이 관례를 따르고, 거기 없는 색·폰트를 새로 도입하지 말 것.
- `vendor/` — 웹폰트·animate.css·canvas-confetti 셀프호스팅 번들. scene-renderer 가 로컬 우선으로 로드한다(없을 때만 CDN 폴백). 지우거나 이동하지 말 것.

**게임 코드(자유 수정)** — main.js 등 게임 로직. 매니저가 이미 있으면 확장하지 말고 그대로 쓰고, 없는 기능은 게임 코드에서 조합한다.

**이벤트 이름·바인딩 키는 임의로 만들지 않는다** — 프로젝트 루트 `SCENES.md`에 씬별로 열거된 값만 사용. 거기 없는 이벤트가 필요하면 사용자에게 ui-editor에서 추가해 달라고 요청한다.

## 2. 부트스트랩 절차 — FlowDriver 우선

**표준 경로는 FlowDriver.** 씬 표시·버튼 전환·팝업·nav 진입을 직접 코딩하지 않는다 — 드라이버가 scene-flow.json 을 실행하고, 게임은 훅 3종(조건 술어·scene:enter·문서 엣지 fire)만 공급한다(§6).

```js
import { FlowDriver } from './flow-driver.js';
import { SoundManager } from './sound-manager.js';
import { EconomyManager } from './economy-manager.js';
import { ProgressManager } from './progress-manager.js';

const sound = new SoundManager({ storagePrefix: 'mygame_' });
const economy = new EconomyManager({ storagePrefix: 'mygame_' });   // 하트·코인 (수치는 게임 기획대로 옵션 지정)
const progress = new ProgressManager({ storagePrefix: 'mygame_' }); // 스테이지 진행도 (§4)

const flow = new FlowDriver({
  basePath: 'src/',                    // 엔트리 html 위치 기준 asset 경로 보정
  dataPath: './src/js/',               // scenes-index.json·scene-flow.json 위치 (기본: flow-driver.js 옆)
  managers: { economy, progress },     // renderer 생성마다 attachRenderer 자동 — 표준 바인딩 키가 코드 없이 표시된다
});

// 훅 ① 조건 술어 — 흐름도 조건 분기 키 전부 (publish-report 의 game-unwired-condition 이 누락을 알려준다)
flow.defineCondition('hasHearts', () => economy.getHearts() > 0);

// 훅 ② 씬 진입 통지 — 인게임 카트리지 마운트 등 씬별 게임 로직의 접점 (nav 탭 씬·팝업도 통지된다)
flow.on('scene:enter', ({ sceneName, renderer }) => {
  if (sceneName === 'Ingame') startCartridge(renderer);   // §5 GameSession
});

sound.playBgm('src/sound/bgm.mp3');    // BGM은 제스처 전 호출해도 안전 — 첫 제스처에서 자동 시작
sound.unlockOnFirstGesture();
await flow.start();                    // 시작 씬(흐름도에서 지정)부터 표시

// 훅 ③ 게임 사건 → 문서 엣지 발화 (label 우선, 도착 씬 이름도 허용) — 예: 인게임 종료 시
// await flow.fire('게임오버 시');
// 커스텀 바인딩 값 공급: flow.update({ score: { final: 1200 } })  — 살아있는 씬 전원 + 이후 씬에 자동 시드
```

- **시작 씬이 지정되지 않았으면 start() 가 throw 한다** — 코드로 우회하지 말고 사용자에게 "ui-editor UI 흐름도에서 씬 노드 우클릭 → 시작 씬으로 지정 후 재publish" 를 요청한다.
- `flow.back()`(이전 씬), `flow.goto(씬이름)`(직접 이동), `flow.current`(현재 씬) 를 게임 코드에서도 쓸 수 있다.
- 드라이버를 쓰지 않는 기존(수동 배선) 프로젝트를 유지보수할 때만 SceneRenderer/PopupManager 로 직접 부트스트랩한다 — 그 절차와 규약은 §6 끝의 "수동 배선(드라이버 미사용)" 참조. 아래 공개 API·해석 규약은 양쪽 공통이다.

- **SceneRenderer 공개 API**: `load`/`loadSync` · `show`/`hide`/`reload` · `on`/`off` · `update` · `playTransition` · `getElement`/`getElementByName`/`getGroup`/`getTextElement` · `getActiveTabRenderer` · 읽기 전용 getter `sceneId`/`sceneName`/`sceneUuid`. 내부 `_` 필드(`_navHostRenderer`, `_contract` 등) 직접 접근 금지.
- **씬 해석은 sceneUuid 우선** — 씬 이름(=contract 파일명)은 ui-editor에서 바뀔 수 있다. 연결은 불변 uuid로 보관하고 `scenes-index.json`(형식 `{ version, scenes: [{ uuid, name, contract, sceneType }] }`)으로 현재 파일을 해석한다 — uuid 우선, 없으면 이름 fallback:
  ```js
  const idx = await (await fetch('./src/js/scenes-index.json')).json();  // publish 폴더 경로에 맞출 것
  function resolveContract(ref) { // ref = { uuid?, name? }
    const hit = idx.scenes.find(s => (ref.uuid && s.uuid === ref.uuid))
              || idx.scenes.find(s => (ref.name && s.name === ref.name));
    return hit ? './src/js/' + hit.contract : null;
  }
  ```
- **`hostedBy`가 있는 씬은 단독 load 금지** — navigation 씬 안에서 표시되도록 설계된 것. `hostedBy[].navContract`를 진입점으로 load한다.
- **navigation 씬을 load하는 renderer에는 `sceneFetch` 해석기를 주입한다.** 탭은 씬 "이름"만 보관한다. 미주입 시 renderer가 자기 옆 `scenes-index.json`으로 자동 해석(폴백)하지만, 폴백까지 실패하면 화면에 `(no matched scene: 이름)` 이 뜨므로 명시 주입을 권장:
  ```js
  const nav = new SceneRenderer(document.body, {
    ...RENDERER_OPTS,
    sceneFetch: async (name) =>            // 탭 씬 이름 → contract 객체
      (await fetch(resolveContract({ name }))).json(),  // scenes-index.json 해석 (위 항목)
  });
  ```
  contract 객체를 미리 다 갖고 있다면 `sceneRegistry: { 씬이름: contract }` 옵션으로 대신해도 된다.

## 3. 실전 함정 체크리스트

- [ ] **`update()`는 `show()` 전에.** show() 후 update()는 디폴트 literal이 잠깐 보이는 플리커를 만든다.
- [ ] **navigation 씬의 탭 씬 해석 실패 신호를 확인.** 탭은 씬 이름만 보관 — nav renderer 생성 옵션에 `sceneFetch`(또는 `sceneRegistry`)를 넣어 scenes-index.json 기준으로 이름→contract를 해석해 준다(§2). 미주입 시 renderer가 scenes-index.json 폴백으로 해석하지만, 화면의 `(no matched scene: X)` 표시나 콘솔 `[SceneRenderer] sceneFetch failed`/`탭 씬 기본 해석 실패` 는 해석 실패(미publish 등) 신호다 — publish-report.json(§6)과 대조.
- [ ] **nav 탭 마운트마다 이벤트 재연결 — `nav:tabchange` 이벤트로.** navigation 씬은 탭을 마운트할 때마다 **새 sub-renderer**를 만든다. 이벤트 핸들러는 renderer 인스턴스에 종속되므로 재연결이 필요하다. 내부 `_` 필드(`_navHostRenderer`, `_contract` 등)는 직접 접근 금지:
  ```js
  nav.on('nav:tabchange', ({ tabId, renderer }) => {   // 최초 진입도 통지 — show() "전에" 구독
    if (renderer?.sceneId === 'lobby') wireLobby(renderer);  // 연결 함수는 재호출 가능하게 분리
  });
  nav.show();
  // 현재 활성 탭의 sub-renderer 가 즉시 필요하면: nav.getActiveTabRenderer()
  ```
- [ ] **show() 후 화면 공개는 렌더 리소스 준비까지 지연될 수 있다(최대 2초).** 폰트·이펙트 CSS·confetti 는 publish 산출물 `vendor/`(scene-renderer.js 옆)에서 로컬 우선 로드된다 — 오프라인·웹뷰에서도 동작하며, 로컬 파일이 없을 때만 CDN 폴백. 공개가 계속 2초씩 지연되면 `vendor/` 누락 신호 — 콘솔 `[SceneRenderer]` 경고로 판정.
- [ ] **곡선(arc) 텍스트는 바인딩 불가.** 글자별 분해 렌더라 `update()`가 적용되지 않는다 — 바인딩이 필요한 텍스트는 사용자에게 곡선 제거·재publish를 요청.
- [ ] **화면 맞춤 스케일은 `document.body` 마운트일 때만.** 다른 컨테이너에 마운트하면 디자인 px 그대로 배치된다.
- [ ] **씬 연결은 sceneUuid + scenes-index.json.** 이름 하드코딩은 rename 시 깨진다 (uuid 우선, 이름 fallback).
- [ ] **localStorage 키는 게임 프리픽스.** `cc_hearts`처럼 게임 고유 프리픽스를 붙인다. SoundManager의 `storagePrefix`에도 같은 프리픽스를 넣는다.
- [ ] **토글·별점·잠금·슬라이더 등 표시 상태는 위젯 바인딩으로.** 씬에 위젯 키(SCENES.md의 "위젯 바인딩" 목록)가 있으면 `update({ sound: { on: true } })`(visibility/toggle=boolean) 또는 `update({ bgm: { volume: 0.7 } })`(slider=0~1)로 제어한다. `getElementByName` 으로 DOM display/transform 을 직접 만지지 말 것. 필요한 키가 씬에 없으면 사용자에게 ui-editor에서 위젯 선언 추가를 요청. (구 visibleBindingKey 는 지원 종료 — 런타임이 warn 후 무시)
- [ ] **위젯 입력은 `widget:<key>` 이벤트 구독으로.** 토글 클릭·슬라이더 드래그는 `renderer.on('widget:<key>', ({value, phase}) => ...)` 로 들어온다(슬라이더: 드래그 중 `input`/놓으면 `change`). UI는 스스로 상태를 바꾸지 않으므로 **게임이 `update({...})` 로 에코해야 움직인다** — 이벤트만 받고 에코를 빼먹으면 위젯이 안 움직이는 것처럼 보인다.
- [ ] **bindingKey 없는 텍스트는 공개 API로 후처리.** contract 텍스트에 bindingKey가 비어 있으면 `update()`로 못 채운다. `getTextElement(stableId, slotIndex)`로 직접 채운다 (팝업이면 `PopupManager`의 `after` 훅에서).
- [ ] **오류를 폴백·try/catch로 삼키지 않는다.** 원인을 추정하지 말고 로그를 심어 판정한다. 모호하면 사용자에게 질문한다.
- [ ] **중복 함수 금지.** 같은 역할 함수가 이미 있으면 재사용하고, 신규 함수는 사용자 허가를 받는다.
- [ ] **시각적·브라우저 검증은 사용자가 수행한다.** 로직·로그 검증까지만 직접 한다.

## 4. 런타임 매니저 API

### PopupManager (`popup-manager.js`)

임의 씬 contract를 오버레이 팝업으로 띄운다. 백드롭 딤 + 스케일 등장/퇴장 + 이벤트 구독 해제 + 재진입 방지 내장. 동시에 1개만.

```js
const popups = new PopupManager(RENDERER_OPTS);
popups.open('src/js/popup_start_stage.contract.json', {
  data: { user: { stage: 3 } },                    // show 전에 update() 로 주입 (첫 페인트부터 실제값)
  on: {                                            // { 이벤트명: 핸들러 } — close 시 자동 구독해제
    close_popup: () => popups.close(),
    start_game: () => { popups.close(); enterGame(); },
  },
  after: (r) => {                                  // bindingKey 없는 텍스트 후처리 등
    const el = r.getTextElement('stat-box-88', 0);
    if (el) el.textContent = el.textContent.replace('{value}', '7');
  },
});
await popups.close();      // 스케일 다운 후 정리
popups.isOpen;             // boolean
```

### SoundManager (`sound-manager.js`)

```js
const sound = new SoundManager({ storagePrefix: 'mygame_' }); // 뮤트·볼륨 localStorage 영속화
sound.unlockOnFirstGesture(onFirst);   // 첫 pointerdown/keydown 에서 unlock (+선택 콜백)
sound.playBgm(src, { loop: true });    // unlock 전 호출은 pending → 첫 제스처에서 자동 시작
sound.stopBgm();
sound.playSfx(src);                    // 중첩 재생 허용. unlock 전·뮤트 중엔 무시
sound.setMuted(true); sound.toggleMuted(); sound.muted;
sound.setVolume('master'|'bgm'|'sfx', 0.5);  // 실효 볼륨 = master × 채널
sound.getVolume('bgm');
```

### EconomyManager (`economy-manager.js`)

하트(플레이 횟수)·코인(재화)의 증감·재생 타이머·localStorage 영속화를 담당한다. **하트/재화는 호스트 전유** — 카트리지는 이 매니저를 모른다. 하트 재생은 anchor 방식이라 앱을 껐다 켜도 오프라인 경과분이 일괄 지급된다.

**변이(소비·지급·지불)는 전부 async** — Authority 승인(아래 "Authority — 신뢰 모델" 참조)을 거친다. 판정이 필요한 호출(`consumeHeart`/`spendCoins`)은 반드시 `await` 할 것 — 미대기 Promise 는 항상 truthy 라 하트 0개여도 통과하는 버그가 된다. 읽기(`getHearts` 등)는 동기.

```js
const economy = new EconomyManager({
  storagePrefix: 'mygame_',   // SoundManager 와 같은 게임 프리픽스
  maxHearts: 5,               // 게임 기획 수치 — 코드에 별도 상수를 만들지 말고 여기서 지정
  heartRegenMs: 30 * 60 * 1000,
  initialCoins: 0,
  // legacyKey: 'cc_runtime_progress_v1',  // 구 저장 키에서 1회 마이그레이션(기존 게임 전환 시)
  // authority: myServerAuthority,         // 경쟁 표면(리더보드 등)이 있는 게임은 필수 — 아래 참조
});

await economy.consumeHeart();   // 게임 시작 시 — false 면 시작 차단 + refill 팝업 열기
await economy.grantHearts(1);   // 보상·광고 지급 (최대치 초과분은 버림)
await economy.refillHearts();   // 최대치로 충전 (refill 상품)
economy.getHearts(); economy.getHeartTimer();  // 하트 수 / "M:SS" 또는 "Max" (동기)
await economy.grantCoins(100, 'stage-clear');  // 클리어 보상 등 (reason 은 권위 감사용)
await economy.spendCoins(500, 'booster');      // 잔액 부족·권위 거부면 차감 없이 false → 상점 유도
economy.getCoins();

// 씬 표시: 텍스트 bindingKey 를 표준 어휘로 — heart.current / heart.timer / coin.current
const off = economy.attachRenderer(lobbyRenderer);  // 1초마다 자동 update() (타이머 갱신)
// nav 탭 전환으로 sub-renderer 가 교체되면(nav:tabchange 이벤트, §3): off() 후 새 renderer 로 다시 attach
```

- **표준 이벤트 어휘** — 씬 버튼 이벤트는 `heart.refill`(refill 팝업 열기), `coin.buy`(상점 이동)를 권장 이름으로 쓴다 (SCENES.md에 있는 값만 사용 원칙은 동일).
- 스테이지 진행도(stage)는 이 매니저에 넣지 말고 **ProgressManager(아래)** 를 사용한다.

### Authority — 신뢰 모델

기본(authority 미주입)은 클라이언트 신뢰 모델 — 싱글플레이 게임은 이대로 충분하며 이 절을 무시해도 된다. **리더보드·유저 경쟁 이벤트·실물 보상이 있는 게임만**: 게임 서버로 `{ approve(tx) }` 구현체를 만들어 Economy/Progress/GameSession 생성자 `authority` 옵션에 주입한다(클라이언트 저장값을 경쟁 표면에 그대로 쓰면 프로토콜 위반). **op 사전·응답 형식·거부/오류 의미는 `game-session.js` 상단 "Authority 계약" 주석이 정본** — 구현 전에 그것만 읽으면 된다. 리더보드 제출값은 서버가 검증한 결과만 사용한다(`getBestScore()` 등 클라이언트 값 제출 금지).

### ProgressManager (`progress-manager.js`)

스테이지 진행도(현재 스테이지·클리어 기록·별점·최고 점수)의 영속화를 담당한다. 해금은 선형(N 클리어 → N+1). **진행도도 호스트 전유** — 카트리지는 `end` 보고만 하고, 기록은 호스트가 여기서 한다.

```js
import { ProgressManager } from './progress-manager.js';

const progress = new ProgressManager({
  storagePrefix: 'mygame_',   // Economy/SoundManager 와 같은 게임 프리픽스
  initialStage: 1,
  maxStage: 50,               // 게임 기획 수치 — 코드에 별도 상수를 만들지 말고 여기서 지정 (null = 무제한)
  // authority: myServerAuthority,  // 경쟁 표면이 있는 게임은 필수 — §4 "Authority — 신뢰 모델" 참조
});

progress.getCurrentStage();          // 도전 가능한 최신 스테이지 (동기)
progress.isUnlocked(n);              // 스테이지 버튼 잠금 표시 판정 (동기)
await progress.recordClear(n, { stars: 3, score: 12000, ticket });  // 클리어 시 (async — 권위 거부 시 throw)
                                     // ticket = GameSession onEnd 결과에 동봉된 세션 티켓(로컬 권위면 생략 가능)
progress.getStars(n); progress.getBestScore(n); progress.getClears(n);

// 씬 표시: 텍스트 bindingKey 표준 어휘 — stage.current / stage.next+1 ~ stage.next+3
//   stage.next+N = 맵 고정 위치에 표시할 다음 스테이지 번호(current+N). maxStage 초과분은 빈 문자열로 push 된다.
const off = progress.attachRenderer(lobbyRenderer);   // 타이머 없음 — recordClear 시점에 push
```

- `stage.n1` 처럼 버튼 배치에 묶인 키는 표준이 아니다 — `getStars(n)`/`isUnlocked(n)` 값을 게임 코드가 해당 씬의 키로 매핑한다. (다음 스테이지 번호 표시는 표준 `stage.next+N` 을 쓴다.)
- 하트·코인은 EconomyManager 전담 — 진행도와 섞지 않는다.

### PromoManager (`promo-manager.js`)

이벤트/상품 레지스트리(`promo-registry.json`, ui-editor 어드민에서 편집)를 읽어
**(a)** 로비 도크 — `EventDock`(이벤트, 좌)·`ProductDock`(상품, 우) 예약 이름 오브젝트 — 를 아이콘으로 채우고,
**(b)** 서프라이즈 항목(연패 상품·이어하기 오퍼 등)을 `fire(triggerKey)` 한 줄로 연다.
**기간(스케줄)·노출 조건 판정은 매니저 소관** — 게임은 판정 재료(`setContext`)만 공급한다. 항목별 버튼 배치·씬 연결·기간 판정 코드를 직접 만들지 말 것. **연동 전에 publish 폴더 `PROMO.md` 를 먼저 읽는다** — 항목·기간·공급할 컨텍스트 키·배선 체크리스트가 거기 있다.

```js
import { PromoManager } from './promo-manager.js';

const promo = new PromoManager({
  basePath: 'src/',            // RENDERER_OPTS.basePath 와 같은 값 (아이콘 경로 보정)
  publishPath: './src/js/',    // promo-registry.json·scenes-index.json·contract 가 있는 publish 폴더
  popupManager: popups,        // pop_* 항목을 열 때 사용
  storagePrefix: 'mygame_',    // 구매제한 카운터 localStorage prefix (Economy/Sound 와 같은 값)
});
await promo.load();

// 로비 진입 — 컨텍스트를 attachDocks "전에" 공급(첫 렌더부터 조건 반영). 키 목록은 PROMO.md.
promo.setContext({ level: progress.getCurrentStage(), loseStreak });
promo.attachDocks(lobbyRenderer);   // show() 이후. 스케줄 경계에서 자동 재평가(내장 타이머)
promo.detachDocks();                // 로비 이탈 시

// 일반 씬(pop_ 아님) 진입은 게임이 표준 전환으로 수행 — 매니저는 직접 전환하지 않는다.
promo.on('promo:navigate', ({ entry, sceneName, sceneUuid, contractUrl }) => switchScene(sceneUuid));

// 서프라이즈 트리거 — 판정 지점에서 무조건 호출해도 안전(기간·조건·구매가능을 매니저가 재검증, 막히면 null).
if (loseStreak >= 3) await promo.fire('offer.losing_streak');
```

**구매 레시피(commerce 항목)** — 매니저는 구매를 실행하지 않는다(가격 표시는 레지스트리, 강제는 Authority):
1. `promo.on('promo:open', ({ entry }) => ...)` 구독 — 도크 클릭/fire 로 항목이 열릴 때마다 온다.
2. `entry.commerce`(가격·정가·할인율·번들)를 팝업 바인딩에 `update()` 로 주입.
3. 구매 버튼 이벤트에서 Authority/EconomyManager 로 지불(`await economy.spendCoins(...)` 등 — 판정 필수).
4. 성공 시 `promo.recordPurchase(entry.id)` — 구매제한 카운터 기록(once 소진 항목은 도크에서 자동 숨김).

- 도크 아이콘 클릭도 같은 규칙 — `pop_*` 씬이면 PopupManager 로 자동으로 열리고, 일반 씬이면 `promo:navigate` 가 온다.
- `setFlags({노출키:bool})` 는 수동 override 레인 — 노출키를 가진 항목만 해당(스케줄·조건과 AND 결합).
- `getEntries({kind, surface, visibleOnly})` / `getEntry(id)` — 항목+`runtime`(status/visible/remainingMs/purchasable) 조회. 남은 시간 표시 등은 `runtime.remainingMs` 를 게임이 원하는 곳에 바인딩.
- `promo:schedule-change`(`{entered, exited}`) — 스케줄 경계에서 노출 집합이 바뀔 때(토스트·배지 갱신용).

#### 프로모 서버 서빙 (라이브옵스 전환, 선택)

기본은 publish 시점 정적 데이터 — 대부분의 게임은 이 절을 무시해도 된다. **배포 없이 실시간으로 이벤트/상품을 켜고 끄려는 게임만**: 자기 게임 서버에서 레지스트리를 서빙하고 `PromoSource` 를 주입한다. **규약 정본은 `promo-manager.js` 상단 "PromoSource 규약" 주석** — 구현 전에 그것만 읽으면 된다.

```js
const source = {
  async fetchRegistry() {
    const r = await fetch('https://game.example.com/live/promo-registry.json');
    if (!r.ok) throw new Error('promo source HTTP ' + r.status);
    return { registry: await r.json(), serverNowMs: Date.parse(r.headers.get('Date')) || undefined };
  },
};
const promo = new PromoManager({ ...opts, source });
```

체크리스트: ① 서버는 publish 산출물 `promo-registry.json` 형식 그대로 서빙(변환 계층 금지) ② 서버 시각은 HTTP `Date` 헤더로 — 매니저가 시계 보정해 기기 시계 조작을 무력화 ③ 구매·한도의 실제 강제는 여전히 Authority 몫(레지스트리는 공개 데이터, 비밀 금지). 소스 실패 시 매니저가 번들 사본으로 자동 폴백한다(오프라인 내성).

## 5. 인게임 카트리지 연결 (GameSession, `game-session.js`)

인게임(실제 게임플레이)은 **카트리지** ES 모듈로 분리한다. 카트리지는 생명주기 인터페이스(`mount`/`initialize`/`startGame`/`pauseGame`/`resumeGame`/`forceQuit`/`unmount`)를 구현해야 하며, 작성 규약은 `ui-editor-ingame` 스킬 참조. 호스트(게임 코드)는 GameSession으로만 연결하고, 연결 로직을 직접 구현하지 말 것.

```js
import { GameSession } from './game-session.js';

// 하트 소비는 시작 시점에 (EconomyManager, §4) — 부족·권위 거부면 시작하지 않고 refill 팝업으로
if (!(await economy.consumeHeart())) { openRefillPopup(); return; }

// Ingame 씬(HUD 포함, 'GameField' 레이어 필수)을 먼저 show() 한 상태에서:
const stageN = progress.getCurrentStage();    // 도전할 스테이지 (ProgressManager, §4)
const game = new GameSession({ renderer: ingameRenderer });  // 경쟁 표면 게임은 authority 옵션도 주입(§4)
await game.start('./cartridge.js', {          // URL(dynamic import) 또는 팩토리 함수
  stage: stageN, seed: 12345, config: { moves: 20 },  // → initialize(stageData)로 전달 (맵·목표·제한 턴·기믹 등)
  onEnd: async (result) => {                  // { outcome:'clear'|'fail'|'quit', score, stats, ticket? }
    // ★ 경제·진행도 적용은 여기(호스트)에서만 — 카트리지는 재화·진행도를 모른다 (§4)
    if (result.outcome === 'clear') {
      await economy.grantCoins(result.score, 'stage-clear');
      await progress.recordClear(stageN, { stars: result.stats?.stars || 0, score: result.score, ticket: result.ticket });
    }
    popups.open(result.outcome === 'clear' ? WIN_POPUP : FAIL_POPUP, { data: { result } });
  },
  onError: () => { /* 씬은 이미 정리됨 — 로비로 복귀 등 */ },
});
// initialize 완료(ready) 후, 예: pop_LevelStart 닫힌 뒤 플레이 개시:
game.startGame();
```

- **일시정지**: Ingame 씬의 pause 버튼 이벤트 → `game.pause('user')` + `pop_Pause` 열기. 팝업 닫힘 → `game.resume()`. 팝업을 여는 동안은 `pause('popup')`.
- **HUD 갱신은 자동** — 카트리지의 `hud` 이벤트를 GameSession이 `hud.*` bindingKey로 `renderer.update()` 해준다. Ingame 씬 텍스트의 bindingKey를 표준 어휘(`hud.score`, `hud.moves`, `hud.goal`, `hud.time`, `hud.combo`, `hud.stage`)로 설정할 것.
- **재도전/다음 스테이지** = `game.start(...)` 재호출(새 카트리지 인스턴스). 저장·리셋 메서드는 없다.
- **유저 이탈·강제 종료** = `game.abort('quit')` — 카트리지의 `forceQuit(reason)` 으로 리소스 정리 기회를 준 뒤 강제 제거한다.
- **플레이 중 호스트→게임 통지**(설정 변경·구매 결과 등) = `game.message(topic, payload)` — 카트리지가 `onMessage`(선택 구현)를 가진 경우에만 전달, 미구현이면 경고 후 무시. 게임→호스트 자유 통지는 기존 `progress` 채널(`onProgress`).
- **카트리지가 죽어도 아웃게임은 산다** — 인터페이스 미구현·예외·initialize 타임아웃(10s) 시 GameSession이 강제 정리하고 `onError` 를 부른다. try/catch로 감싸서 오류를 삼키지 말 것(원인은 `[GameSession]` 로그로 판정).

### Godot 웹 익스포트 브리지 (선택)

기본은 JS 카트리지 — 대부분의 게임은 이 절을 무시해도 된다. **Godot 엔진으로 인게임을 만드는 게임만**: 카트리지 계약을 publish 산출물 `godot-bridge.js`(`makeGodotCartridge`)가 대신 구현하고, GDScript 와는 `window.UiBridge` 인터페이스로 통신한다. **프로토콜 정본은 `godot-bridge.js` 상단 주석.** 설치 자료는 publish 가 `.claude/skills/ui-editor-game/godot/` 에 심는 2파일(`ui_bridge.gd`, `godot-shell.html`).

**아키텍처와 폴더 규약** — UI 셸(JS, FlowDriver+매니저)이 호스트, Godot 웹 익스포트가 카트리지. Godot canvas 는 GameField 레이어 안에 브리지가 생성한다.

| 경로 | 역할 |
|---|---|
| `web/` | Godot 익스포트 대상 (`export_path="web/index.html"`) |
| `web/ui/` | ui-editor publish 출력(rendererPath) — 셸이 `./ui/` 로 참조 |
| `godot-shell.html` (프로젝트 루트) | 익스포트 프리셋 `html/custom_html_shell` 원본 — **`web/index.html`(산출물)을 직접 수정하지 말 것**, 재익스포트 때 소실된다 |

**설치 절차** ① `.claude/skills/ui-editor-game/godot/ui_bridge.gd` 를 게임 프로젝트에 복사 → 프로젝트 설정 > Autoload 에 이름 **"UiBridge"** 로 등록 ② `godot-shell.html` 을 프로젝트 루트에 복사 → 익스포트 프리셋(Web)의 `html/custom_html_shell` 로 지정 ③ 프리셋 `variant/thread_support=false` (COOP/COEP 헤더 없는 정적 서버 대응) ④ 셸의 "게임 설정/배선 블록"을 publish-report 목록대로 채운다(§0 수리 루프 동일).

GDScript 쪽은 시그널 5종을 받고 표준 메서드로 보고한다:

```gdscript
# main.gd 등에서 (UiBridge 는 autoload)
func _ready() -> void:
    UiBridge.host_initialize.connect(_on_initialize)   # {stage, seed, config}
    UiBridge.host_start.connect(_on_start)
    UiBridge.host_force_quit.connect(_on_force_quit)

func _on_initialize(stage_data: Dictionary) -> void:
    _load_stage(stage_data.get("stage", 1))
    UiBridge.notify_initialized()   # ★ 의무 — 안 부르면 initialize 타임아웃으로 세션 실패

func _on_score_changed(score: int) -> void:
    UiBridge.post_hud({"score": score})                # 표준 어휘만(§5 HUD)

func _on_game_over(cleared: bool, score: int) -> void:
    UiBridge.post_end("clear" if cleared else "fail", score)   # 플레이 1회에 1번만
```

양방향 자유 통지: 호스트 `game.message(topic, payload)` → `UiBridge.host_message(topic, payload)` 시그널(설정 변경·구매 결과 등), 게임 → 호스트는 `UiBridge.post_progress({...})` → 셸 `onProgress`(설정창·상점 열기 트리거 등). 인게임 중 아웃게임 팝업은 이 두 통로로 연결하고, 팝업 자체는 셸 씬(pop_*)으로 만든다.

**규약과 함정**:
- `GameSession` 은 `initTimeoutMs: 30000` 으로 생성한다 — Godot 엔진 부팅+pck 로드가 기본 10초 예산을 넘긴다(셸 템플릿에 반영돼 있음).
- `host_force_quit` 이후 `post_end` 금지 — 브리지가 드롭하지만 게임 쪽에서도 부르지 않는 것이 규약. pause 는 `auto_pause`(기본 true)가 `get_tree().paused` 를 자동 처리한다.
- `ui_bridge.gd` 는 비호스트 실행(에디터 F5·네이티브)에서 no-op 폴백 + `standalone_autostart` 로 게임 단독 구동을 보장한다 — 웹 결합 없이도 게임을 개발·실행할 수 있다.
- **금지 규칙 예외(ingame 스킬 §4 대비)**: 전역은 `window.Engine`(Godot 산출물)과 `window.UiBridge`(브리지가 unmount 때 정리) 2개만 허용. Godot `user://` 저장(웹에서 IndexedDB)은 엔진 내장 경로라 허용 — 단 재화·진행도의 정본은 여전히 Economy/ProgressManager 다(§4 Authority 경계 불변). 이 2가지 외의 금지 규칙은 그대로 적용된다.
- 배선 스캔은 `.gd` 도 읽는다 — `UiBridge` 사용이 통합 신호로 인정되고, 조건 키·문서 엣지 누락은 여전히 publish-report 가 알려준다.

## 6. scene-flow.json — 씬 연결 그래프

publish 출력 폴더의 `scene-flow.json`은 씬 사이의 의도된 흐름(어떤 이벤트가 어느 씬으로 이어지는지)을 uuid 기반 edge로 기록한 **데이터 문서**이자, **FlowDriver(`flow-driver.js`)의 실행 사양**이다. 드라이버가 버튼 엣지 구독·조건 분기·팝업(pop_*/`__close__`)·이력(`__back__`)·nav 진입(toHostedBy)·전환효과를 전부 자동 실행하므로 **씬 전환 코드를 작성하지 않는다.** 게임 몫은 훅 3종뿐:

1. **조건 술어** — edge 의 `condition` 키마다 `flow.defineCondition(키, 술어)` 를 start() 전에 등록 (예: `hasHearts` → `economy.getHearts() > 0`). 누락은 publish-report `game-unwired-condition` 과 콘솔 `[FlowDriver] 미등록 조건 키` 가 알려준다.
2. **문서 엣지 발화** — trigger 없는 edge(시스템 트리거)는 해당 사건 시점에 `flow.fire(label)`(label 우선) 또는 `flow.fire(도착 씬 이름)` 을 호출한다. 누락은 publish-report `game-unfired-doc-edge` 가 알려준다.
3. **scene:enter** — 씬 진입 통지에서 인게임 마운트·커스텀 바인딩 공급(`flow.update`) 등 씬별 게임 로직을 건다.

```jsonc
{ "version": 1,
  "entrySceneUuid": "...", "entrySceneName": "Splash",  // FlowDriver 시작 씬 — 에디터 흐름도 우클릭으로 지정
  "edges": [ {
    "fromSceneUuid": "...", "toSceneUuid": "...",       // scenes-index.json 으로 contract 해석
    "fromSceneName": "lobby", "toSceneName": "shop",    // 표시용 캐시 — 연결은 uuid 기준 (publish 가 이름 재생성)
    "trigger": { "stableId": "btn-3", "eventName": "btn-3:click", "condition": "hasHearts" } | null,
    "label": "게임오버 시",                              // 문서 엣지(trigger 없음)의 시스템 트리거 설명 — 선택
    "toHostedBy": [{ "navScene": "nav_New", "navSceneUuid": "...", "navContract": "nav_New.contract.json", "tabId": "t0" }] | 없음,
    "transitionOut": { "type": "screen-transition", ... } | null,   // 출발 씬에서 재생
    "transitionIn":  { "type": "image-curtain", ... } | null        // 도착 씬에서 재생
} ] }
```

- **흐름도 변경 통지 `scene-flow-changes.json`(같은 폴더) — 있으면 최우선 처리.** 에디터가 흐름도를 바꿔 publish하면 게임이 마지막으로 반영한 기준본 대비 변경분이 기록된다. 각 항목(`type`: `added`/`removed`/`retargeted`/`condition-renamed`/`event-renamed`/`transition-changed`/`label-changed`)을 기존 배선 코드와 대조해 수정하고 — `removed`는 해당 구독·전환 코드도 **제거** — **반영 완료 후 파일을 삭제(소비)한다**(scene-flow-proposed 와 대칭 규약). 소비하지 않으면 변경분이 계속 누적 표시된다. 파일 안의 `baseline`은 비교 기준 스냅샷이라 직접 읽을 필요 없다.
- **`publish-report.json`(같은 폴더)을 먼저 읽는다.** publish마다 에디터가 산출물 정합성(미publish 씬 참조·전환효과 In/Out 방향·흐름도에 없는 이벤트 연결·조건 키 혼용 등)을 검사해 `{ errors, warnings, infos }` 로 기록한 리포트다. **errors 항목은 코드로 우회 구현하지 말고 사용자에게 보고**하고, warnings/infos 는 §6 셀프체크 때 대조 근거로 쓴다. `game-unwired-event`/`game-unwired-condition` 코드는 게임 코드 배선 스캔 결과(미배선 의심) — 수리 절차는 §0.
- **`toHostedBy`가 있는 edge = 도착 씬이 navigation 호스팅.** FlowDriver 가 자동으로 navContract 진입 + `switchTab()` 처리한다. (수동 배선 시: 도착 contract를 직접 load하지 말고 `toHostedBy[].navContract`를 load한 뒤 해당 `tabId`로 `switchTab()` — §2 hostedBy 규칙과 동일.)

### 수동 배선 — 드라이버 미사용(기존 프로젝트 유지보수) 시에만

FlowDriver 를 쓰는 프로젝트는 이 절이 필요 없다(전부 자동). 드라이버 없이 직접 배선된 기존 게임을 유지보수할 때만 따른다:

- **trigger가 있는 edge = 버튼 연결.** `eventName`을 `renderer.on()`으로 구독해 이동을 구현한다. 그룹으로 묶인 버튼(이미지+아이콘+라벨)은 어느 멤버를 클릭해도 **같은 eventName**(대표 멤버 기준 — publish가 통일)으로 발화하므로 구독은 edge 의 eventName 하나면 충분하다 — 멤버별 stableId 이름을 따로 구독하지 말 것. 같은 버튼의 조건 분기는 `condition`별로 edge가 여러 개다 — contract 레이어의 `events[].branches`(위에서부터 평가, `else`=기본)와 같은 데이터이며, **condition 키의 판정은 게임 몫**이다(예: `hasHearts` → `economy.getHearts() > 0`). trigger가 없는 edge는 문서용 씬-씬 연결로, `label`이 있으면 그 흐름을 일으키는 시스템 이벤트 설명이다(예: "게임오버 시" → `GameSession onEnd(fail)` 시 이 흐름을 실행).
- **대상이 `pop_*` 씬이면 씬 전환이 아니라 팝업 열기.** 전체 씬을 교체하지 말고 `PopupManager.open()`(§4)으로 오버레이로 연다. 팝업은 동시에 1개 — 팝업→팝업 흐름은 `close()` 후 `open()`.
- **`toSceneUuid` 예약 센티널 2종.** 실제 씬이 아니므로 `scenes-index.json`으로 해석하려 하지 말 것.
  - `"__back__"` = 이전 씬으로 — 게임이 **씬 이력 스택**을 유지하다가(이동할 때 push) 이 대상을 만나면 pop 해서 직전 씬으로 돌아간다.
  - `"__close__"` = 씬 이동 없이 팝업만 닫기 — `popups.close()` 로 처리한다.
- **전환효과는 `renderer.playTransition(spec)`으로 재생한다** (재구현 금지). 표준 절차:
  ```js
  renderer.on(edge.trigger.eventName, async () => {
    await fromRenderer.playTransition(edge.transitionOut);  // null이면 즉시 resolve — 분기 불필요
    fromRenderer.hide();
    toRenderer.show();
    toRenderer.playTransition(edge.transitionIn);
  });
  ```
- **셀프체크(필수).** 흐름 구현을 마치면 `scene-flow.json`의 모든 edge에 대해 ① `trigger.eventName`마다 `renderer.on(...)` 구독이 있는지 ② 모든 `condition` 키를 게임 코드가 실제로 판정하는지 ③ `__back__`/`__close__` 대상이 이력 pop/팝업 닫기로 처리되는지 ④ `pop_*` 대상이 PopupManager 로 열리는지 ⑤ 도착 씬 contract에 `hostedBy`가 있으면 navigation contract 진입 + `sceneFetch` 주입(§2)으로 마운트되는지 대조한다. 빠진 edge는 구현하거나, 의도적으로 뺐으면 사용자에게 보고한다. 런타임 자가진단이 배선 누락을 이중으로 잡아준다: 씬이 표시되면 흐름 연결 이벤트의 미구독을 일괄 검사해 콘솔 `[SceneRenderer] 배선 자가진단` 경고 + `window.__uiWiringAudit` 에 씬별 목록을 쌓고, 클릭 시점에도 `구독자가 없습니다` 경고가 뜬다. 사용자가 이 경고/JSON 을 주면 각 eventName 을 배선한다(절차는 §0).

### 역방향 제안 — 게임에서 먼저 연결한 흐름을 에디터에 알리기

흐름도에 없는 씬 이동을 게임 코드에 새로 배선했다면(또는 필요하다고 판단했다면), **publish 출력 폴더에 `scene-flow-proposed.json`을 작성**해 에디터에 제안한다. 에디터 사용자가 "UI 흐름도 → 게임 제안 가져오기"로 검토·승인하면 흐름도와 씬 이벤트에 병합되고 파일은 소비(삭제)된다. `scene-flow.json`을 직접 수정하지 말 것(다음 publish에 덮어써짐).

```jsonc
{ "version": 1, "proposals": [ {
    "fromSceneUuid": "...",            // 또는 fromSceneName (uuid 우선)
    "stableId": "btn-3",               // 버튼 연결일 때만 — 없으면 씬-씬 문서 연결
    "toSceneUuid": "...",              // 또는 toSceneName. 센티널 "__back__"/"__close__" 허용
    "condition": "hasHearts",          // 조건 분기일 때만
    "note": "상점 버튼 — 하트 부족 시 refill 팝업"   // 선택 — 검토자가 볼 한 줄 설명
} ] }
```

## 7. 참고 문서

- `prompt.md` (프로젝트 루트) — 통합 작업 진입점(사용자가 게임 AI에게 지시할 때 사용 — 절차 본문은 이 스킬 §0이 정본, publish마다 갱신)
- `AGENTS.md` (프로젝트 루트) — 항상 로드되는 금지 규칙 + 문서 포인터 (publish마다 갱신)
- `SCENES.md` (프로젝트 루트) — 씬별 이벤트·바인딩 키 목록 (여기 있는 값만 사용)
- `.claude/skills/ui-editor-ingame/SKILL.md` — 인게임 카트리지 제작 규약 (프로토콜 전체 스펙)
