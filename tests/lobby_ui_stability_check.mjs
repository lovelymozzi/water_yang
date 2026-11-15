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
  lobbyBgmEnabled: false, ingameBgmEnabled: false, buttonSfxEnabled: false,
  hapticsEnabled: false, SETTINGS_MENU_GROUPS: [], lobbyRewardPlaybackRenderer: null,
  lobbyButterflyAnimations: [], LOBBY_BUTTERFLY_FLIGHTS: [],
  syncUnlimitedHearts() {}, clearLobbyItemRewardLayers() {}, playQueuedLobbyItemRewards() {},
  syncItemCounts() {}, renderLeaderboard: async () => {},
  sound: {}, console,
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
assert.equal(animations[0].cancelled, true, 'Idle brightness sweep is still looping');
assert.equal(animations[1].cancelled, false, 'Normal entrance animation was removed');
assert.equal(bodyClasses.has('instant-lobby-home-return'), true);
for (const timer of timers.filter(timer => timer.delay <= 10000)) timer.callback();
assert.equal(bodyClasses.has('instant-lobby-home-return'), true, 'Idle navigation compositing changed after ten seconds');
let work;
context.enter({ sceneName: 'Ranking', sceneUuid: 'ranking', renderer, waitUntil: promise => { work = promise; } });
await work;
assert.equal(host.parentElement, parking, 'Leaving the game view did not park the canvas');
assert.deepEqual(moves, ['parking'], 'Leaving the game view parked the canvas more than once');
console.log('LOBBY UI STABILITY CHECK: PASS (no repeated shine, no redundant canvas moves, nav host preserves child, popup preserves mount)');
