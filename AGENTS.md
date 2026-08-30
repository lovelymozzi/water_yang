<!-- BEGIN: ui-editor scene-renderer guide (자동생성 — 이 마커 안쪽은 publish마다 갱신됩니다. 직접 수정 금지) -->

## UI 씬은 **ui-editor**로 제작됨 — 직접 재구현 금지

- 씬의 레이아웃·스타일·효과를 HTML/CSS로 다시 만들지 마세요. `*.contract.json` + `scene-renderer.js`에 이미 완성돼 있고, 상호작용은 오직 `SceneRenderer` 공개 API로만 합니다(내부 `_` 필드 접근 금지).
- **읽기 전용(publish마다 덮어써짐 — 변경은 ui-editor에서)**: `scene-renderer.js` · 매니저 8종(`popup/sound/game-session/economy/progress/promo-manager/flow-driver/godot-bridge.js`) · `vendor/` · `*.contract.json` · `scenes-index.json` · `scene-flow.json` · `promo-registry.json` · `SCENES.md`/`PROMO.md`/`DESIGN.md`/`prompt.md` · 이 마커 블록.
- **씬 흐름(버튼 이동·팝업·전환효과)은 `flow-driver.js`(FlowDriver)가 scene-flow.json 을 읽어 자동 실행** — 씬 전환 코드를 직접 작성하지 말고 훅(조건 술어·문서 엣지 fire·scene:enter)만 공급한다. 상세는 스킬 §6.
- **무거운 씬 로딩은 image-curtain 전환이 가려준다**: In 슬롯이 image-curtain 인 엣지는 커튼이 화면을 덮은 채 씬을 교체하고, `scene:enter` 핸들러에서 `e.waitUntil(로딩Promise)` 를 등록하면 그 로딩이 끝날 때까지 커튼이 걷히지 않는다(등록 없으면 렌더 리소스 준비까지만 대기).
- **이벤트 이름·바인딩 키는 임의로 만들지 않는다** — 씬별 목록은 [`./SCENES.md`](./SCENES.md), 거기 없는 값이 필요하면 사용자에게 ui-editor 추가를 요청.
- 씬 연결은 이름이 아니라 불변 `sceneUuid`로 보관하고 `./web/ui/scenes-index.json`으로 현재 contract 를 해석한다(이름은 rename 될 수 있음). contract 에 `hostedBy` 가 있는 씬은 단독 load 금지 — navigation contract 가 진입점.
- 팝업·사운드·인게임 연결·하트/코인·진행도·이벤트/상품은 publish 된 매니저가 전담 — 직접 구현 금지.
- **캐릭터(무기·악세서리 조립)**: `layerType:"character"` 레이어는 `./web/ui/characters/<id>.character.json` 정의로 조립된다. 무기 교체·동작 재생은 해당 엘리먼트의 `__uiCharacter` 핸들만 사용 — `equip(socketId, partId)` · `play(clipName, {loop})` · `stop()` · `getEquip()`. 소켓/파츠/클립을 코드로 새로 만들지 말고 ui-editor 캐릭터 메이커에 요청할 것.

### 통합 절차·매니저 API·씬 흐름 배선의 정본 = ui-editor-game 스킬

- **UI 통합·배선·매니저 사용 전에 반드시 `.claude/skills/ui-editor-game/SKILL.md` 를 읽는다.** 스킬 자동 인식이 없는 도구도 이 파일을 직접 읽을 것(Codex 는 `.codex/skills/` 동일본). 작업 절차·부트스트랩·SceneRenderer API·실전 함정·scene-flow 배선·미배선 수리 루프·역질문 규약이 §0~§6 에 있다.
- 흐름 구현 전에 `./web/ui/publish-report.json`(정합성 검진 — errors 는 코드로 우회하지 말고 사용자에게 보고)과 `./web/ui/scene-flow-changes.json`(있으면 최우선 반영 후 삭제)을 읽는다.
- 인게임 카트리지 제작은 `.claude/skills/ui-editor-ingame/SKILL.md`, 배포 전 보안 검수는 `.claude/skills/ui-editor-security/SKILL.md`.
- 씬 밖 UI(커스텀 팝업·HUD 등)를 직접 만들 때는 `./web/ui/DESIGN.md` 관례를 따른다 — 거기 없는 색·폰트를 새로 도입하지 말 것.

### 작업 규칙
- 시각적·브라우저 검증은 사용자가 직접 수행한다.
- 중복 함수 생성 금지 — 중복이 발견되면 공통 헬퍼 하나로 합친다. 신규 함수는 사용자의 허가를 받는다.
- 추정 금지 — 모호하면 사용자에게 질문하거나, 로그를 심어 오류를 직접 확인한다. 폴백·try/catch 로 오류를 삼키지 않는다.

<!-- END: ui-editor scene-renderer guide -->

## Godot 본체(인게임 3D) 작업

위 블록은 웹 UI 전용이다. Godot 쪽(보드·고양이·구멍·기믹·맵 생성)을 건드릴 때는 다음이 정본이다.

- **개발·에디터·임포트·내보내기·테스트는 Godot 4.7.2 stable만 사용한다.** 현재 `godot` PATH 별칭이 가리키는 4.5.1 및 그 밖의 버전은 사용 금지다. 실행 전 `--version`으로 `4.7.2.stable.official.ed1daf0bf`를 확인하고, 4.7.2 실행 파일을 직접 지정한다.
- **[`./DEVELOPMENT_RULES.md`](./DEVELOPMENT_RULES.md) 를 먼저 읽는다.** 그리드/조작, 구멍과 흡입 판정, 기믹 비주얼과 연출(셰이더 컴파일 렉·회전 상속 함정), 머티리얼·그림자, 검증 원칙이 들어 있다.
- 이동 스펙은 [`./1_움직임고찰.md`](./1_움직임고찰.md), 맵 자동생성은 [`./2_맵생성기.md`](./2_맵생성기.md) 가 단일 기준이다.
- **새 기믹을 붙이기 전에 `DEVELOPMENT_RULES.md` 의 "기믹 비주얼과 연출" 절을 확인한다.** 얼음 기믹에서 이미 밟은 함정이 정리돼 있어, 같은 렉·회전 문제를 되풀이하지 않는다.
- 헤드리스 검증은 `/Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/<check>.gd`. 렌더링이 필요한 확인(파티클, 회전, 폰트 모양)은 헤드리스로 불가능하므로 사용자에게 눈으로 확인을 요청한다.
