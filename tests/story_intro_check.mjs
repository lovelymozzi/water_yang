import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { setTimeout as delay } from 'node:timers/promises';

const root = new URL('../', import.meta.url);
const read = path => readFileSync(new URL(path, root), 'utf8');
const json = path => JSON.parse(read(path));
const story = json('resources/story/cat-liquid-intro.json');
const graph = json('web/ui/scene-flow.json');
const index = json('web/ui/scenes-index.json');
const moduleUrl = code => `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
const { attachStoryIntro, STORY_INTRO_SCENES, STORY_INTRO_SCENE_UUIDS, STORY_INTRO_STORAGE_SUFFIX } =
  await import(moduleUrl(read('web/story-intro.js')));
const key = 'leonout_' + STORY_INTRO_STORAGE_SUFFIX;

assert.deepEqual(story.pages.map(page => page.sceneUuid), [...STORY_INTRO_SCENE_UUIDS]);
assert.deepEqual(story.pages.map(page => page.sceneName), [...STORY_INTRO_SCENES]);
assert.equal(story.textMode, 'none');
assert.equal(story.display.autoAdvance, false);
assert.equal(story.display.startStageAutomatically, false);
const firstEntryEdges = graph.edges.filter(edge => edge.fromSceneName === 'splash');
assert.equal(firstEntryEdges[0].trigger.condition, 'story.firstEntry');
assert.equal(firstEntryEdges[1].trigger.condition, '로딩');
const newEdges = graph.edges.filter(edge => edge.id.startsWith('edge-story-') || edge.id === 'edge-splash-story-first-entry');
assert.equal(newEdges.length, 5);
assert.ok(newEdges.every(edge => edge.toSceneName !== 'Ingame'));
assert.equal(story.display.advanceMode, 'next-click-next-panel');
assert.equal(story.display.allowSkip, true);
assert.deepEqual(story.controls, { skip: 'skip', next: 'next' });
assert.equal(story.dialogue, undefined);
assert.deepEqual(newEdges.filter(edge => !edge.trigger).map(edge => edge.label), ['story.pageComplete', 'story.finish']);
const sourceGraph = json('.ui-editor/scene-flow.json');
for (const edge of newEdges) assert.deepEqual(sourceGraph.edges.find(item => item.id === edge.id), edge);

for (const page of story.pages) {
  const entry = index.scenes.find(scene => scene.uuid === page.sceneUuid);
  assert.ok(entry);
  const contract = json('web/ui/' + entry.contract);
  const source = json(`.ui-editor/scenes/${page.sceneName}.scene.json`);
  assert.equal(contract.sceneUuid, source.uuid);
  assert.deepEqual(contract.sceneAnimations, source.sceneAnimations);
  const cards = contract.layers.filter(layer => layer.stableId.startsWith('story-card-'));
  assert.equal(cards.length, 4);
  for (const [slot, card] of cards.entries()) {
    assert.equal(card.visual.exportPath, page.panels[slot].cardArt);
    assert.equal(card.visual.height * card.scale, story.frame.cardHeight);
    assert.equal(card.visual.width * card.scale, story.frame.cardWidth);
    assert.equal(card.x + card.visual.width * card.scale / 2, story.motion.layout[slot].centerX);
    assert.equal(card.y + card.visual.height * card.scale / 2, story.motion.layout[slot].centerY);
    assert.equal(page.panels[slot].caption, undefined);
    const angle = Math.abs(card.rotation) * Math.PI / 180;
    const halfWidth = card.visual.width * card.scale / 2;
    const halfHeight = card.visual.height * card.scale / 2;
    const extentX = halfWidth * Math.cos(angle) + halfHeight * Math.sin(angle);
    const extentY = halfHeight * Math.cos(angle) + halfWidth * Math.sin(angle);
    const { centerX, centerY } = story.motion.layout[slot];
    assert.ok(centerX >= extentX && centerX + extentX <= story.canvas.width, 'Settled card clips horizontally');
    assert.ok(centerY >= extentY && centerY + extentY <= story.canvas.height, 'Settled card clips vertically');
  }
  assert.deepEqual(contract.sceneAnimations, [], 'Touch progression must have no automatic scene timeline');
  assert.deepEqual(contract.background, story.background);
  const shopBackground = json('web/ui/pop_BuyCoins.contract.json').background;
  assert.deepEqual({ ...contract.background, imagePath: shopBackground.imagePath }, shopBackground);
  assert.equal(contract.background.scrollEnabled, true);
  assert.equal(contract.background.imagePath, 'src/assets/common_bg_pt_3.png');
  assert.ok(cards.every(layer => !layer.texts?.length));
  assert.ok(contract.layers.every(layer => !layer.stableId.startsWith('story-dialogue-') && !layer.stableId.startsWith('story-advance-')));
  assert.deepEqual(contract.layers.flatMap(layer => layer.texts || []).map(text => text.staticContent).sort(), ['next', 'skip']);
  assert.ok(contract.layers.flatMap(layer => layer.texts || []).every(text => !text.bindingKey));
  for (const layer of contract.layers) {
    if (layer.visual.exportPath) assert.ok(existsSync(new URL(layer.visual.exportPath, root)), layer.visual.exportPath);
    const sourceLayer = source.layers.find(item => item.stableId === layer.stableId);
    assert.ok(sourceLayer);
    if (layer.stableId.startsWith('story-next-') || layer.stableId.startsWith('story-skip-')) {
      const action = layer.stableId.startsWith('story-next-') ? 'next' : 'skip';
      assert.equal(layer.texts[0].staticContent, action);
      assert.equal(sourceLayer.componentState.texts[0].content, action);
      assert.equal(layer.rotation, 0);
      assert.equal(layer.x, story.controlLayout[action].x);
      assert.equal(layer.y, story.controlLayout[action].y);
      assert.ok(layer.y >= Math.max(...cards.map(card => card.y + card.visual.height * card.scale)));
    }
    assert.deepEqual(layer.events || [], sourceLayer.events || []);
    for (const event of layer.events || []) {
      const n = page.sceneName.slice(-2);
      if (layer.stableId.startsWith('story-next-')) assert.equal(event.eventName, `story-advance-${n}:click`);
      else {
        assert.equal(event.eventName, `story-skip-${n}:click`);
        const edge = newEdges.find(edge => edge.id === `edge-story-skip-${n}`);
        assert.equal(edge.trigger.condition, 'story.complete');
        assert.equal(edge.toHostedBy[0].tabId, 't1');
      }
    }
  }
}

const css = read('web/story-intro.css');
assert.match(css, /animation-duration: 200ms/);
assert.match(css, /prefers-reduced-motion: reduce/);
assert.ok(existsSync(new URL(story.integration.impactArt, root)));
for (const path of ['godot-shell.html', 'web/index.html']) {
  const shell = read(path);
  assert.match(shell, /href="\.\/story-intro\.css\?v=cat-liquid-v9"/);
  assert.match(shell, /import \{ attachStoryIntro, STORY_INTRO_SCENES, STORY_INTRO_STORAGE_SUFFIX \}/);
  assert.match(shell, /const GAME_STORAGE_KEYS = \[[\s\S]*?STORY_INTRO_STORAGE_KEY,/);
  assert.match(shell, /localStorage\.getItem\(STORY_INTRO_STORAGE_KEY\) !== '1'\) \? STORY_INTRO_SCENES : \[\]/);
  assert.match(shell, /image\.decode \? image\.decode\(\)\.then\(resolve, reject\)/);
  assert.match(shell, /attachStoryIntro\(flow, \{[\s\S]*?isReady: \(\) => loadingReady,[\s\S]*?saveGame,/);
  assert.match(shell, /storyIntroResponse = await fetch\(`\$\{ASSET_BASE\}resources\/story\/cat-liquid-intro\.json`, \{ cache: 'no-cache' \}\)/);
}

// Exercise the published FlowDriver with renderer/DOM substitutes, without a browser or Godot.
const rendererUrl = moduleUrl(`export class SceneRenderer {
  constructor() { this.handlers = new Map(); this.data = {}; }
  loadSync(contract) { this.contract = contract; return this; }
  on(name, handler) {
    if (!this.handlers.has(name)) this.handlers.set(name, []);
    this.handlers.get(name).push(handler);
    return () => this.handlers.set(name, this.handlers.get(name).filter(item => item !== handler));
  }
  update(data) { this.data = { ...this.data, ...data, story: { ...this.data.story, ...data.story } }; }
  show() { this.elements = new Map(); }
  hide() { for (const element of this.elements.values()) element.isConnected = false; }
  playTransition() { return Promise.resolve(); }
  curtainCover() { return { covered: Promise.resolve(), adopt() {}, uncover() {} }; }
  _whenRenderResourcesReady() { return Promise.resolve(); }
  switchTab(id) { this.selectedTab = id; }
  getElement(id) {
    const layer = this.contract.layers.find(item => item.stableId === id);
    if (!layer) return null;
    if (!this.elements.has(id)) {
      const element = {
        attributes: {}, listeners: {}, isConnected: true, classes: new Set(),
        classList: { add: name => element.classes.add(name) },
        setAttribute(name, value) { this.attributes[name] = value; },
        addEventListener(name, handler) { this.listeners[name] = handler; },
        click: () => {
          for (const event of layer.events || []) {
            for (const handler of this.handlers.get(event.eventName) || []) handler();
          }
        },
      };
      this.elements.set(id, element);
    }
    return this.elements.get(id);
  }
}`);
const popupUrl = moduleUrl('export class PopupManager { isOpen = false; }');
const driverCode = read('web/ui/flow-driver.js')
  .replace("'./scene-renderer.js'", JSON.stringify(rendererUrl))
  .replace("'./popup-manager.js'", JSON.stringify(popupUrl));
const { FlowDriver } = await import(moduleUrl(driverCode));
const nativeFetch = globalThis.fetch;
const nativeStorage = globalThis.localStorage;
const nativePerformance = globalThis.performance;
const nativeRequestAnimationFrame = globalThis.requestAnimationFrame;
const nativeCancelAnimationFrame = globalThis.cancelAnimationFrame;
let now = 0;
let frameId = 0;
const pendingFrames = new Map();
globalThis.performance = { now: () => now };
globalThis.requestAnimationFrame = fn => { pendingFrames.set(++frameId, fn); return frameId; };
globalThis.cancelAnimationFrame = id => pendingFrames.delete(id);
function step(milliseconds) {
  now += milliseconds;
  const callbacks = [...pendingFrames.values()];
  pendingFrames.clear();
  for (const callback of callbacks) callback(now);
}
const consoleMethods = { ...console };
const errors = [];
console.error = (...args) => errors.push(args);
console.info = () => {};
console.warn = () => {};
globalThis.fetch = async url => ({ ok: true, json: async () => json(String(url).replace(/^\.\//, '')) });

const storage = new Map();
globalThis.localStorage = {
  getItem: id => storage.get(id) ?? null,
  setItem: (id, value) => storage.set(id, value),
};
let saves = 0;
let ready = false;
async function boot(replay = false) {
  const flow = new FlowDriver({ dataPath: './web/ui/' });
  for (const edge of graph.edges) {
    const condition = edge.trigger?.condition;
    if (condition && condition !== 'else') flow.defineCondition(condition, () => false);
  }
  flow.defineCondition('로딩', () => ready);
  attachStoryIntro(flow, { story, storageKey: key, isReady: () => ready, saveGame: () => { saves += 1; }, replay });
  await flow.start();
  return flow;
}
async function press(flow, id, expected) {
  flow.current.renderer.getElement(id).click();
  for (let attempts = 0; attempts < 100; attempts++) {
    await delay(1);
    if (flow.current.name === expected && (expected !== 'home_bottom' || flow.current.renderer.selectedTab === 't1')) return;
  }
  assert.equal(flow.current.name, expected, id);
  assert.fail('Hosted Lobby tab did not mount');
}
function readPage(flow, pageIndex) {
  const renderer = flow.current.renderer;
  const pageNumber = String(pageIndex + 1).padStart(2, '0');
  step(story.motion.initialDelayMs);
  for (const [index, panel] of story.pages[pageIndex].panels.entries()) {
    const cardKey = `panel${String(panel.number).padStart(2, '0')}`;
    assert.equal(renderer.data.story[cardKey], true);
    assert.equal(renderer.data.story.dialogue, undefined);
    assert.equal(renderer.data.story.nextReady, true);
    assert.equal(renderer.data.story.hint, undefined);
    assert.equal(renderer.getElement(`story-dialogue-${pageNumber}`), null);
    assert.equal(pendingFrames.size, 0, 'A wordless panel must not keep a typing animation loop');
    step(10000);
    if (index < 3) {
      const nextKey = `panel${String(panel.number + 1).padStart(2, '0')}`;
      assert.equal(renderer.data.story[nextKey], false, 'Waiting must not reveal the next cut');
      const next = renderer.getElement(`story-next-${pageNumber}`);
      if (index === 1) {
        let prevented = false;
        next.listeners.keydown({ key: ' ', preventDefault() { prevented = true; } });
        assert.ok(prevented);
      } else next.click();
      assert.equal(renderer.data.story[cardKey], true, 'Earlier cuts stay visible');
      assert.equal(renderer.data.story[nextKey], true, 'One next click advances immediately');
      assert.equal(pendingFrames.size, 0);
    }
  }
}

try {
  const first = await boot();
  first.current.renderer.getElement('loading-out-png-11').click();
  await delay(5);
  assert.equal(first.current.name, 'splash', 'Loading must finish before entering the story');
  ready = true;
  await press(first, 'loading-out-png-11', 'StoryIntro01');
  assert.equal(storage.get(key), undefined, 'Opening the story must not mark it complete');
  const next = first.current.renderer.getElement('story-next-01');
  assert.equal(next.attributes.role, 'button');
  assert.equal(next.attributes['aria-label'], 'next');
  assert.equal(first.current.renderer.data.story.panel01, false);
  next.click();
  await delay(5);
  assert.equal(first.current.name, 'StoryIntro01', 'The initial entrance must finish before next can advance');
  step(story.motion.initialDelayMs - 1);
  assert.equal(first.current.renderer.data.story.panel01, false);
  step(1);
  assert.equal(first.current.renderer.data.story.panel01, true);
  // Wordless panels stay visible until next is clicked.
  step(10000);
  assert.equal(first.current.renderer.data.story.dialogue, undefined);
  assert.equal(first.current.renderer.data.story.panel02, false);
  // Re-enter the same cached renderer: state and event subscriptions must reset.
  await first.goto('splash');
  assert.equal(pendingFrames.size, 0);
  await press(first, 'loading-out-png-11', 'StoryIntro01');
  readPage(first, 0);
  await press(first, 'story-next-01', 'StoryIntro02');
  assert.equal(storage.get(key), undefined, 'Turning a page must not mark it complete');
  first.current.renderer.getElement('story-next-02').click();
  await delay(5);
  assert.equal(first.current.name, 'StoryIntro02', 'The second page also starts with its first entrance');
  assert.equal(storage.get(key), undefined);
  readPage(first, 1);
  await press(first, 'story-next-02', 'home_bottom');
  assert.equal(storage.get(key), '1');
  assert.equal(saves, 1);

  const returning = await boot();
  await press(returning, 'loading-out-png-11', 'home_bottom');
  assert.equal(saves, 1);
  const replay = await boot(true);
  await press(replay, 'loading-out-png-11', 'StoryIntro01');
  readPage(replay, 0);
  await press(replay, 'story-next-01', 'StoryIntro02');
  readPage(replay, 1);
  const exit = replay.current.renderer.getElement('story-next-02');
  exit.click();
  exit.click();
  await delay(10);
  assert.equal(replay.current.name, 'home_bottom');
  assert.equal(saves, 2);
  assert.equal(pendingFrames.size, 0);
  const skipped = await boot(true);
  await press(skipped, 'loading-out-png-11', 'StoryIntro01');
  assert.equal(pendingFrames.size, 1);
  const skip = skipped.current.renderer.getElement('story-skip-01');
  assert.equal(skip.attributes['aria-label'], 'skip');
  skip.click();
  skip.click();
  await delay(10);
  assert.equal(skipped.current.name, 'home_bottom');
  assert.equal(saves, 3, 'Double skip saves once, even before the first cut');
  assert.equal(pendingFrames.size, 0);
  const skippedSecond = await boot(true);
  await press(skippedSecond, 'loading-out-png-11', 'StoryIntro01');
  readPage(skippedSecond, 0);
  await press(skippedSecond, 'story-next-01', 'StoryIntro02');
  step(story.motion.initialDelayMs);
  let prevented = false;
  skippedSecond.current.renderer.getElement('story-skip-02').listeners.keydown({ key: 'Enter', preventDefault() { prevented = true; } });
  await delay(10);
  assert.ok(prevented);
  assert.equal(skippedSecond.current.name, 'home_bottom');
  assert.equal(saves, 4);
  const interrupted = await boot(true);
  await press(interrupted, 'loading-out-png-11', 'StoryIntro01');
  assert.equal(pendingFrames.size, 1);
  await interrupted.goto('splash');
  assert.equal(pendingFrames.size, 0, 'Scene exit cancels the entrance wait');
  assert.deepEqual(errors, [], 'Story navigation must not emit FlowDriver errors');
} finally {
  globalThis.fetch = nativeFetch;
  globalThis.performance = nativePerformance;
  if (nativeRequestAnimationFrame === undefined) delete globalThis.requestAnimationFrame;
  else globalThis.requestAnimationFrame = nativeRequestAnimationFrame;
  if (nativeCancelAnimationFrame === undefined) delete globalThis.cancelAnimationFrame;
  else globalThis.cancelAnimationFrame = nativeCancelAnimationFrame;
  if (nativeStorage === undefined) delete globalThis.localStorage;
  else globalThis.localStorage = nativeStorage;
  Object.assign(console, consoleMethods);
}
console.log('story intro: wordless tall panels, bottom skip/next, immediate advance, document edges, early skip, keyboard, cached reentry, double-click cleanup, replay and save passed');
