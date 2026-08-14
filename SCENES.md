# publish된 씬

> 자동 생성 — publish마다 갱신됩니다. 직접 수정 금지.
> 금지 규칙은 [`./AGENTS.md`](./AGENTS.md), `SceneRenderer` API·통합 절차는 `.claude/skills/ui-editor-game/SKILL.md` 참조.
> **표기 규약(전 씬 공통 — 씬 섹션은 데이터만)**: 이벤트=`renderer.on(name, fn)` 구독(여기 있는 이름만 사용, 기본 트리거 click — 다르면 괄호 표기) · 바인딩=`renderer.update({...})` 주입 · sceneUuid=불변(씬 연결은 이 값 기준) · sceneType 표기 없음=일반 씬 · 위젯=visibility/toggle:boolean, slider:0~1 — 입력은 `widget:<key>` 이벤트로 오고 게임이 update 로 에코해야 UI가 움직임 · GameField=GameSession 인게임 카트리지 마운트 지점.

<!-- SCENE:home_bottom BEGIN -->
#### `home_bottom`  ·  contract: `./web/ui/home_bottom.contract.json`
- sceneType: `navigation`
- sceneUuid: `37f376d8-4e32-4340-9bbd-4ed17767e148`
- 이벤트: 없음
<!-- SCENE:home_bottom END -->

<!-- SCENE:ingame BEGIN -->
#### `ingame`  ·  contract: `./web/ui/ingame.contract.json`
- sceneUuid: `321eb56d-18f3-4c27-baa9-8e48c6f38541`
- 이벤트: 없음
<!-- SCENE:ingame END -->


