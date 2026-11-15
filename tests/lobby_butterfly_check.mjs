import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const shell = readFileSync(new URL('../godot-shell.html', import.meta.url), 'utf8');
const lobby = JSON.parse(readFileSync(new URL('../web/ui/Lobby.contract.json', import.meta.url), 'utf8'));
const config = shell.match(/const LOBBY_BUTTERFLY_FLIGHTS = (\[[\s\S]*?\n\]);/)[1];
const source = shell.slice(shell.indexOf('  // Ambient butterfly flight:'), shell.indexOf("  if (sceneName === INGAME_UI_SCENE) {", shell.indexOf('  // Ambient butterfly flight:')));
const enter = Function('renderer', 'sceneName', 'sceneUuid', 'popup', `
  const LOBBY_UI_SCENE = 'Lobby';
  const LOBBY_NAV_SCENE_UUID = 'nav';
  const LOBBY_BUTTERFLY_FLIGHTS = ${config};
  ${source}
`);
const elements = new Map();
const animations = [];
for (const layer of lobby.layers.filter(layer => layer.displayName === 'butterfly_sequence')) {
  elements.set(layer.stableId, {
    style: { left: `${layer.x}px`, top: `${layer.y}px` },
    animate(frames, timing) {
      const positions = frames.map(frame => frame.translate.split(' ').map(parseFloat));
      assert.deepEqual(positions[0], [0, 0]);
      assert.deepEqual(positions.at(-1), [0, 0]);
      assert.equal(frames[0].offset, 0);
      assert.equal(frames.at(-1).offset, 1);
      const xs = positions.map(point => point[0] + layer.x);
      const ys = positions.map(point => point[1] + layer.y);
      assert.ok(Math.max(...xs) - Math.min(...xs) > 250, 'Butterfly still hovers in one spot');
      assert.ok(Math.max(...ys) - Math.min(...ys) > 140, 'Flight has no vertical travel');
      assert.ok(Math.min(...xs) > 25 && Math.max(...xs) < 360, 'Flight leaves the visible background');
      assert.ok(Math.min(...ys) > 190 && Math.max(...ys) < 415, 'Flight overlaps the lobby controls');
      for (let index = 1; index < frames.length; index += 1) {
        const distance = Math.hypot(positions[index][0] - positions[index - 1][0], positions[index][1] - positions[index - 1][1]);
        const seconds = (frames[index].offset - frames[index - 1].offset) * timing.duration / 1000;
        assert.ok(distance / seconds > 8 && distance / seconds < 22, 'Flight stops or rushes between waypoints');
      }
      const first = positions[1];
      const last = positions.at(-2);
      assert.ok((first[0] * -last[0] + first[1] * -last[1]) / (Math.hypot(...first) * Math.hypot(...last)) > 0.98, 'Loop changes direction abruptly');
      const animation = { cancelled: false, cancel() { this.cancelled = true; } };
      animations.push(animation);
      return animation;
    },
  });
}
const renderer = {
  getElement: id => elements.get(id),
  setSpriteRate: (id, rate) => assert.ok(elements.has(id) && rate >= 0.7 && rate <= 0.8),
};
globalThis.lobbyButterflyAnimations = [];
enter(renderer, 'Lobby', 'lobby', false);
assert.equal(animations.length, 3);
enter(renderer, 'nav', 'nav', false);
enter(renderer, 'Popup', 'popup', true);
assert.ok(animations.every(animation => !animation.cancelled), 'Host entry or popup interrupts the flight');
enter(renderer, 'Lobby', 'lobby', false);
assert.ok(animations.slice(0, 3).every(animation => animation.cancelled), 'Returning to the lobby duplicates flight loops');
enter(renderer, 'Ingame', 'ingame', false);
assert.ok(animations.every(animation => animation.cancelled), 'Leaving the lobby retains background animations');
delete globalThis.lobbyButterflyAnimations;
console.log('LOBBY BUTTERFLY CHECK: PASS (three calm paths, bounds, steady speed, continuous loops, navigation cleanup)');
