import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

// Execute the real host scene-entry handler. No browser or copied mount logic.
const shell = readFileSync(process.argv[2] || new URL('../godot-shell.html', import.meta.url), 'utf8');
const handler = shell.slice(shell.indexOf("flow.on('scene:enter',"), shell.lastIndexOf('\nawait flow.start();'));
const moves = [];
const field = {
  appendChild(node) { moves.push('field'); node.parentElement = this; },
};
const parking = {
  appendChild(node) { moves.push('parking'); node.parentElement = this; },
};
const host = { parentElement: field, style: {} };
const canvas = { parentElement: host };
const animations = ['ui-shine-31_right', 'animate__bounceIn'].map(animationName => ({
  animationName, cancelled: false, cancel() { this.cancelled = true; },
}));
const button = { getAnimations: () => animations };
const bodyClasses = new Set();
const timers = [];
const game = {
  state: 'running', pause() { this.state = 'paused'; }, resume() { this.state = 'running'; },
};
const context = {
  LOBBY_UI_SCENE: 'Lobby', INGAME_UI_SCENE: 'Ingame',
  LOBBY_NAV_SCENE_UUID: 'nav', SPLASH_UI_SCENE_UUID: 'splash',
  activeGame: game, activeGodotScene: 'lobby', activeSceneName: '', activeSceneUuid: '',
  retryStagePending: false, timeoutRecoveryPending: false, continueWithoutHeart: false,
  currentMapStage: 1, endedGame: null, instantLobbyHomeReturnTimeoutId: null,
  pendingSceneReady: null, progress: { getCurrentStage: () => 1 },
  STAGE_TIME_LIMIT_SECONDS: 60,
  lobbyBgmEnabled: false, ingameBgmEnabled: false, buttonSfxEnabled: false,
  hapticsEnabled: false, SETTINGS_MENU_GROUPS: [], lobbyRewardPlaybackRenderer: null,
  lobbyButterflyAnimations: [], LOBBY_BUTTERFLY_FLIGHTS: [],
  syncUnlimitedHearts() {}, clearLobbyItemRewardLayers() {}, playQueuedLobbyItemRewards() {},
  syncItemCounts() {}, renderLeaderboard: async () => {},
  sound: { stopBgm() {} }, console,
  requestAnimationFrame() {},
  setTimeout: (callback, delay) => timers.push({ callback, delay }), clearTimeout() {},
  document: {
    getElementById: id => id === 'godot-bridge-canvas' ? canvas : parking,
    body: { classList: { add: value => bodyClasses.add(value), remove: value => bodyClasses.delete(value) } },
    addEventListener() {},
  },
  flow: { on: (_event, callback) => { context.enter = callback; } },
};
const renderer = {
  update() {}, on() {}, getGroup: () => null,
  getElement: id => id === 'home-btn-stage-normal-png-145' ? button : null,
  getElementByName: name => name === 'GameField' ? field : null,
};
runInNewContext(handler, context);
for (const entry of [
  { sceneName: 'Lobby', sceneUuid: 'lobby' },
  // Navigation host can notify after its Lobby child has already mounted.
  { sceneName: 'home_bottom', sceneUuid: 'nav' },
  { sceneName: 'Lobby', sceneUuid: 'lobby' },
  { sceneName: 'pop_Settings_1', sceneUuid: 'settings', popup: true },
]) {
  let work;
  context.enter({ ...entry, renderer, waitUntil: promise => { work = promise; } });
  await work;
  assert.equal(host.parentElement, field, `${entry.sceneName} detached the live canvas`);
}
assert.deepEqual(moves, [], 'Already mounted canvas was removed/reinserted');
assert.equal(animations[0].cancelled, false, 'Start button repeating shine must be preserved');
assert.equal(animations[1].cancelled, false, 'Normal entrance animation was removed');
assert.equal(bodyClasses.has('instant-lobby-home-return'), true);
for (const timer of timers.filter(timer => timer.delay <= 10000)) timer.callback();
assert.equal(bodyClasses.has('instant-lobby-home-return'), true, 'Idle navigation compositing changed after ten seconds');
let work;
context.enter({ sceneName: 'Ranking', sceneUuid: 'ranking', renderer, waitUntil: promise => { work = promise; } });
await work;
assert.equal(host.parentElement, parking, 'Leaving the game view did not park the canvas');
assert.deepEqual(moves, ['parking'], 'Leaving the game view parked the canvas more than once');

// Execute the actual splash parking block and the published bridge's resize code.
// A display:none parent reports zero layout size and used to reset WebGL to 1x1.
const parkedCanvas = { width: 1560, height: 3424 };
const parkedHost = {
  parentElement: { clientWidth: 780, clientHeight: 1712 },
  get clientWidth() { return this.parentElement.clientWidth; },
  get clientHeight() { return this.parentElement.clientHeight; },
};
const offscreen = {
  isConnected: true, style: {},
  get clientWidth() { return this.style.cssText.includes('display:none') ? 0 : Number(this.style.cssText.match(/width:(\d+)px/)?.[1] || 0); },
  get clientHeight() { return this.style.cssText.includes('display:none') ? 0 : Number(this.style.cssText.match(/height:(\d+)px/)?.[1] || 0); },
  appendChild(node) { node.parentElement = this; },
};
const parkingStart = shell.indexOf("    const gameHost = document.getElementById('godot-bridge-canvas')", shell.indexOf('const navigationTabPreload'));
const parkingEnd = shell.indexOf('\n    loadingReady = true;', parkingStart);
assert.ok(parkingStart > 0 && parkingEnd > parkingStart);
const parkContext = {
  document: { getElementById: id => id === 'godot-bridge-canvas' ? { parentElement: parkedHost } : offscreen },
  canvas: parkedCanvas, window: { devicePixelRatio: 2 },
};
runInNewContext(shell.slice(parkingStart, parkingEnd), parkContext);
const bridge = readFileSync(new URL('../web/ui/godot-bridge.js', import.meta.url), 'utf8');
const fitStart = bridge.indexOf('        function fitCanvas(el)');
const fitEnd = bridge.indexOf('\n        return {', fitStart);
runInNewContext(bridge.slice(fitStart, fitEnd) + '\nfitCanvas(gameHost);', parkContext);
assert.deepEqual(parkedCanvas, { width: 1560, height: 3424 }, 'Parking reset the WebGL drawing buffer');
assert.ok(offscreen.style.cssText.includes('visibility:hidden'), 'Parked game remains visible');

// The curtain must wait for sceneReady on first entry AND a later scene switch/Retry.
for (const state of ['ready', 'running', 'paused']) {
  for (const retry of [false, true]) {
    game.state = state;
    context.activeGodotScene = retry ? 'main' : 'lobby';
    context.retryStagePending = retry;
    context.timeoutRecoveryPending = retry;
    context.endedGame = retry ? game : null;
    context.hasUnlimitedHearts = () => true;
    const messages = [];
    game.message = (topic, payload) => messages.push({ topic, payload });
    game.startGame = () => { game.state = 'running'; };
    let complete = false;
    let entryWork;
    context.enter({ sceneName: 'Ingame', sceneUuid: 'main', renderer, waitUntil: promise => { entryWork = promise; } });
    entryWork.then(() => { complete = true; });
    await Promise.resolve();
    assert.equal(messages.length, 1, `${state}/${retry}: load_scene was not sent`);
    assert.equal(messages[0].topic, 'load_scene');
    assert.equal(complete, false, `${state}/${retry}: curtain released before sceneReady`);
    assert.equal(context.pendingSceneReady?.scene, 'main', `${state}/${retry}: missing readiness gate`);
    context.pendingSceneReady.resolve();
    await entryWork;
    assert.equal(complete, true);
    assert.equal(context.pendingSceneReady, null);
  }
}
console.log('LOBBY UI STABILITY CHECK: PASS (shine preserved, parked WebGL size stable, all scene switches await sceneReady)');
