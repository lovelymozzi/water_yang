import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

// Run the whole scene-entry handler, including the published Retry button events.
// No browser, renderer implementation or copied restart logic is used.
const shell = readFileSync(process.argv[2] || new URL('../godot-shell.html', import.meta.url), 'utf8');
const start = shell.indexOf("flow.on('scene:enter',");
const end = shell.lastIndexOf('\nawait flow.start();');
assert.ok(start >= 0 && end > start);
const sceneFlow = JSON.parse(readFileSync(new URL('../web/ui/scene-flow.json', import.meta.url)));

for (const scenario of [
  { name: 'settings Retry before timeout', popup: 'pop_LevelFail', retry: true, topic: 'load_scene', immediate: true },
  { name: 'settings Retry through heart popup', popup: 'pop_LevelFail', retry: true, heartPopup: true, topic: 'load_scene', immediate: true },
  { name: 'timeout Retry button', popup: 'pop_Fail', retry: true, failed: true, topic: 'load_scene', immediate: true },
  { name: 'timeout recovery', failed: true, topic: 'load_scene', immediate: true },
  { name: 'first entry from lobby', previous: 'lobby', topic: 'load_scene', immediate: false },
  { name: 'cancel Retry confirmation', popup: 'pop_LevelFail' },
  { name: 'close settings', popup: 'pop_Settings_1' },
  { name: 'paid continue', failed: true, continue: true, topic: 'continue_stage' },
  { name: 'leave Retry for lobby', popup: 'pop_LevelFail', retry: true, lobby: true, topic: 'load_scene', immediate: false },
]) {
  const messages = [];
  const handlers = new Map();
  const game = {
    state: 'paused',
    message: (topic, payload) => {
      messages.push({ topic, payload });
      if (topic === 'load_scene') queueMicrotask(() => context.pendingSceneReady?.resolve());
    },
    resume: () => { game.state = 'running'; },
    pause: () => { game.state = 'paused'; },
  };
  const context = {
    activeGame: game,
    activeGodotScene: scenario.previous || 'main',
    activeSceneName: 'Ingame',
    activeSceneUuid: 'ingame',
    retryStagePending: false,
    timeoutRecoveryPending: !!scenario.failed,
    endedGame: scenario.failed ? game : null,
    pendingSceneReady: null,
    continueWithoutHeart: !!scenario.continue,
    currentMapStage: 7,
    progress: { getCurrentStage: () => 7 },
    STAGE_TIME_LIMIT_SECONDS: 60,
    TIMEOUT_CONTINUE_SECONDS: Number(shell.match(/const TIMEOUT_CONTINUE_SECONDS = (\d+);/)[1]),
    LOBBY_UI_SCENE: 'Lobby',
    INGAME_UI_SCENE: 'Ingame',
    SPLASH_UI_SCENE_UUID: 'splash',
    LOBBY_NAV_SCENE_UUID: 'lobby-nav',
    buttonSfxEnabled: false,
    lobbyBgmEnabled: false,
    ingameBgmEnabled: false,
    hapticsEnabled: false,
    lobbyButterflyAnimations: [],
    LOBBY_BUTTERFLY_FLIGHTS: [],
    SETTINGS_MENU_GROUPS: [],
    lobbyRewardPlaybackRenderer: null,
    syncItemCounts() {},
    syncUnlimitedHearts() {},
    clearLobbyItemRewardLayers() {},
    playQueuedLobbyItemRewards() {},
    sound: { stopBgm() {} },
    document: { getElementById: () => null },
    console: { info() {}, error() {} },
    setTimeout: () => 1, clearTimeout() {},
    flow: { on: (_event, handler) => { context.enter = handler; } },
  };
  const renderer = {
    on: (event, handler) => handlers.set(event, handler),
    update() {},
    getElement: () => null,
    getElementByName: () => null,
    getGroup: () => null,
  };
  runInNewContext(shell.slice(start, end), context);
  const entries = [];
  if (scenario.popup) entries.push({ name: scenario.popup, popup: true });
  if (scenario.heartPopup) entries.push({ name: 'pop_BuyLives_1', popup: true });
  if (scenario.lobby) entries.push({ name: 'Lobby' });
  entries.push({ name: 'Ingame' });
  for (const entry of entries) {
    let work;
    context.enter({ sceneName: entry.name, sceneUuid: entry.name, popup: !!entry.popup, renderer, waitUntil: promise => { work = promise; } });
    await work;
    if (entry.name === scenario.popup && scenario.retry) {
      const edge = sceneFlow.edges.find(edge => edge.fromSceneName === entry.name
        && edge.toSceneName === 'Ingame' && edge.trigger?.condition === 'else');
      assert.ok(edge, `${scenario.name}: published Retry edge`);
      // Old code registers no Retry handler here and merely resumes the waiting timer.
      handlers.get(edge.trigger.eventName)?.();
    }
    if (entry.name === 'Lobby') messages.length = 0;
  }
  assert.equal(game.state, 'running', scenario.name);
  assert.equal(messages.length, scenario.topic ? 1 : 0, scenario.name);
  if (!scenario.topic) continue;
  assert.equal(messages[0].topic, scenario.topic, scenario.name);
  if (scenario.topic === 'load_scene') {
    assert.equal(messages[0].payload.stage, 7, scenario.name);
    assert.equal(messages[0].payload.config.startTimerImmediately, scenario.immediate, scenario.name);
    assert.equal(context.retryStagePending, false, `${scenario.name}: consumed Retry intent`);
  } else {
    assert.equal(messages[0].payload.timeLimitSeconds, 20, scenario.name);
  }
}
const pointerStart = shell.indexOf("document.addEventListener('pointerdown', event => {");
const pointerEnd = shell.indexOf("\nconst itemCounts =", pointerStart);
assert.ok(pointerStart >= 0 && pointerEnd > pointerStart);
for (const [scene, state, button, count] of [
  ['Ingame', 'running', 0, 1],
  ['Ingame', 'paused', 0, 0],
  ['Ingame', 'running', 2, 0],
  ['Lobby', 'running', 0, 0],
  ['pop_Settings_1', 'running', 0, 0],
]) {
  const messages = [];
  let pointerDown;
  runInNewContext(shell.slice(pointerStart, pointerEnd), {
    document: { addEventListener: (_name, handler) => { pointerDown = handler; } },
    activeSceneName: scene,
    INGAME_UI_SCENE: 'Ingame',
    activeGame: { state, message: (topic, payload) => messages.push({ topic, payload }) },
  });
  pointerDown({ button });
  assert.equal(messages.length, count, `${scene}/${state}/${button}: first touch`);
  if (count) assert.equal(messages[0].topic, 'stage_touch');
}
console.log('RETRY TIMER HOST CHECK: PASS (settings Retry / timeout Retry / heart popup / cancel / first touch / continue / lobby)');
