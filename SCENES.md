# publish된 씬

> 자동 생성 — publish마다 갱신됩니다. 직접 수정 금지.
> 금지 규칙은 [`./AGENTS.md`](./AGENTS.md), `SceneRenderer` API·통합 절차는 `.claude/skills/ui-editor-game/SKILL.md` 참조.
> **표기 규약(전 씬 공통 — 씬 섹션은 데이터만)**: 이벤트=`renderer.on(name, fn)` 구독(여기 있는 이름만 사용, 기본 트리거 click — 다르면 괄호 표기) · 바인딩=`renderer.update({...})` 주입 · sceneUuid=불변(씬 연결은 이 값 기준) · sceneType 표기 없음=일반 씬 · 위젯=visibility/toggle:boolean, slider:0~1 — 입력은 `widget:<key>` 이벤트로 오고 게임이 update 로 에코해야 UI가 움직임 · GameField=GameSession 인게임 카트리지 마운트 지점.

<!-- SCENE:BuyLives_1 BEGIN -->
#### `BuyLives_1`  ·  contract: `./web/ui/BuyLives_1.contract.json`
- sceneUuid: `f3ba1a4a-f763-458d-9e7a-2a54bfe0c1be`
- 이벤트: `button-green-png-309:click` · `button-yellow1-png-311:click` · `icon-close01-png-2233:click`
- 텍스트 바인딩: `heart.timer` · `heart.current` · `cost.refill`
<!-- SCENE:BuyLives_1 END -->

<!-- SCENE:Fail BEGIN -->
#### `Fail`  ·  contract: `./web/ui/Fail.contract.json`
- sceneUuid: `ab1ddf44-eda7-4e00-b5c8-98dc7d3040dd`
- 이벤트: `plain-text-515:click` · `shape-round-rect-520:click`
<!-- SCENE:Fail END -->

<!-- SCENE:Give_up BEGIN -->
#### `Give_up`  ·  contract: `./web/ui/Give_up.contract.json`
- sceneUuid: `afd468ee-25ac-4e8c-b452-dbf5a3548662`
- 이벤트: `plain-text-346:click` · `shape-round-rect-350:click`
<!-- SCENE:Give_up END -->

<!-- SCENE:Ingame BEGIN -->
#### `Ingame`  ·  contract: `./web/ui/Ingame.contract.json`
- sceneUuid: `321eb56d-18f3-4c27-baa9-8e48c6f38541`
- 이벤트: `bar1-png-2:click`
- 텍스트 바인딩: `stage.timer`
- GameField 레이어 있음
<!-- SCENE:Ingame END -->

<!-- SCENE:Lobby BEGIN -->
#### `Lobby`  ·  contract: `./web/ui/Lobby.contract.json`
- sceneUuid: `0ad51a82-1069-4948-ad6f-e97422300c6d`
- 이벤트: `home-btn-setting-png-87:click` · `home-btn-plus-png-94:click` · `home-btn-plus-png-95:click` · `home-btn-stage-normal-png-145:click`
- 텍스트 바인딩: `heart.timer` · `heart.current` · `coin.current` · `stage.current`
<!-- SCENE:Lobby END -->

<!-- SCENE:Ranking BEGIN -->
#### `Ranking`  ·  contract: `./web/ui/Ranking.contract.json`
- sceneUuid: `3db24195-9465-47f6-be12-e9aeeebf74e6`
- 이벤트: 없음
<!-- SCENE:Ranking END -->

<!-- SCENE:Settings_1 BEGIN -->
#### `Settings_1`  ·  contract: `./web/ui/Settings_1.contract.json`
- sceneUuid: `235b7eb7-c304-45b3-aa55-25f18050fd64`
- 이벤트: `ingame.setting.restart` · `ingame.setting.home` · `shape-round-rect-751:click`
- 위젯: `haptic.on`(toggle) · `sound.on`(toggle) — 입력 이벤트: `widget:haptic.on` · `widget:sound.on`
<!-- SCENE:Settings_1 END -->

<!-- SCENE:Splash BEGIN -->
#### `Splash`  ·  contract: `./web/ui/Splash.contract.json`
- sceneUuid: `c4e72c62-dadd-40ab-85f4-bd397f4ca7f9`
- 이벤트: `loading-out-png-11:click` · `loading-inner-png-12:click` · `loading-bar-png-13:click` · `text-loading-15:click`
- 텍스트 바인딩: `loadingMessage`
<!-- SCENE:Splash END -->

<!-- SCENE:home_bottom BEGIN -->
#### `home_bottom`  ·  contract: `./web/ui/home_bottom.contract.json`
- sceneType: `navigation`
- sceneUuid: `37f376d8-4e32-4340-9bbd-4ed17767e148`
- 이벤트: 없음
<!-- SCENE:home_bottom END -->

<!-- SCENE:pop_BuyCoins BEGIN -->
#### `pop_BuyCoins`  ·  contract: `./web/ui/pop_BuyCoins.contract.json`
- sceneUuid: `b11144cd-f2c6-4f82-a4a8-c76b3496cd70`
- 이벤트: `common-btn-top-x-blue-png-2186:click`
<!-- SCENE:pop_BuyCoins END -->

<!-- SCENE:pop_LevelFail BEGIN -->
#### `pop_LevelFail`  ·  contract: `./web/ui/pop_LevelFail.contract.json`
- sceneUuid: `2bce71e3-b626-4295-919d-e24cb07f1ae2`
- 이벤트: `plain-text-563:click` · `shape-round-rect-568:click`
<!-- SCENE:pop_LevelFail END -->

<!-- SCENE:pop_LevelWin BEGIN -->
#### `pop_LevelWin`  ·  contract: `./web/ui/pop_LevelWin.contract.json`
- sceneUuid: `af666955-071f-412b-832b-02370af5062f`
- 이벤트: `button-green-png-133:click` · `button-yellow1-png-132:click`
<!-- SCENE:pop_LevelWin END -->

<!-- SCENE:pop_OutOfMoves BEGIN -->
#### `pop_OutOfMoves`  ·  contract: `./web/ui/pop_OutOfMoves.contract.json`
- sceneUuid: `26578336-5751-476b-b24d-f144818b21ce`
- 이벤트: `shape-round-rect-1765:click` · `shape-round-rect-1769:click`
- 텍스트 바인딩: `continue.coin`
<!-- SCENE:pop_OutOfMoves END -->

<!-- SCENE:pop_Settings BEGIN -->
#### `pop_Settings`  ·  contract: `./web/ui/pop_Settings.contract.json`
- sceneUuid: `8fc00305-7288-4b2a-90df-9ff83554cb5b`
- 이벤트: `common-btn-top-x-blue-png-290:click`
<!-- SCENE:pop_Settings END -->

<!-- SCENE:popup_entry BEGIN -->
#### `popup_entry`  ·  contract: `./web/ui/popup_entry.contract.json`
- sceneUuid: `87eb9dd6-588c-4b1d-9c70-2cd2df0a04fa`
- 이벤트: 없음
<!-- SCENE:popup_entry END -->


