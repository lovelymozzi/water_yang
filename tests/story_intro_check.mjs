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
  assert.deepEqual(contract.sceneAnimations.slice(0, 4).map(item => item.startTimeMs), story.motion.panelStartMs);
  assert.ok(contract.sceneAnimations.every(item => item.loop === false));
  assert.equal(contract.sceneAnimations.at(-1).targetStableId, `story-next-${page.sceneName.slice(-2)}`);
  assert.ok(contract.sceneAnimations.at(-1).startTimeMs > story.motion.panelStartMs.at(-1) + story.motion.entryDurationMs);
  assert.ok(contract.layers.every(layer => !layer.texts?.length));
  for (const layer of contract.layers) {
    assert.ok(existsSync(new URL(layer.visual.exportPath, root)), layer.visual.exportPath);
    assert.ok(source.layers.some(item => item.stableId === layer.stableId));
    for (const event of layer.events || []) {
      const edge = newEdges.find(item => item.fromSceneUuid === page.sceneUuid && item.trigger.eventName === event.eventName);
      assert.ok(edge, event.eventName);
      assert.equal(event.branches[0].targetSceneUuid, edge.toSceneUuid);
      if (edge.toSceneName === 'Lobby') {
        assert.equal(edge.toHostedBy[0].navScene, 'home_bottom');
        assert.equal(edge.toHostedBy[0].tabId, 't1');
      }
    }
  }
}

const css = read('web/story-intro.css');
assert.match(css, /animation-duration: var\(--animate-duration\)/);
assert.match(css, /prefers-reduced-motion: reduce/);
assert.ok(existsSync(new URL('src/assets/story_cat_liquid_impact.png', root)));
for (const path of ['godot-shell.html', 'web/index.html']) {
  const shell = read(path);
  assert.match(shell, /href="\.\/story-intro\.css\?v=cat-liquid-v3"/);
  assert.match(shell, /import \{ attachStoryIntro, STORY_INTRO_SCENES, STORY_INTRO_STORAGE_SUFFIX \}/);
  assert.match(shell, /const GAME_STORAGE_KEYS = \[[\s\S]*?STORY_INTRO_STORAGE_KEY,/);
  assert.match(shell, /localStorage\.getItem\(STORY_INTRO_STORAGE_KEY\) !== '1'\) \? STORY_INTRO_SCENES : \[\]/);
  assert.match(shell, /image\.decode \? image\.decode\(\)\.then\(resolve, reject\)/);
  assert.match(shell, /attachStoryIntro\(flow, \{[\s\S]*?isReady: \(\) => loadingReady,[\s\S]*?saveGame,/);
}

// Exercise the published FlowDriver with renderer/DOM substitutes, without a browser or Godot.
const rendererUrl = moduleUrl(`export class SceneRenderer {
  constructor() { this.handlers = new Map(); }
  loadSync(contract) { this.contract = contract; return this; }
  on(name, handler) {
    if (!this.handlers.has(name)) this.handlers.set(name, []);
    this.handlers.get(name).push(handler);
  }
  update() {}
  show() { this.elements = new Map(); }
  hide() {}
  playTransition() { return Promise.resolve(); }
  curtainCover() { return { covered: Promise.resolve(), adopt() {}, uncover() {} }; }
  _whenRenderResourcesReady() { return Promise.resolve(); }
  switchTab(id) { this.selectedTab = id; }
  getElement(id) {
    const layer = this.contract.layers.find(item => item.stableId === id);
    if (!layer) return null;
    if (!this.elements.has(id)) {
      const element = {
        attributes: {}, listeners: {},
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
  attachStoryIntro(flow, { storageKey: key, isReady: () => ready, saveGame: () => { saves += 1; }, replay });
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
  assert.equal(next.attributes['aria-label'], '다음 이야기');
  await press(first, 'story-next-01', 'StoryIntro02');
  assert.equal(storage.get(key), undefined, 'Turning a page must not mark it complete');
  await press(first, 'story-next-02', 'home_bottom');
  assert.equal(storage.get(key), '1');
  assert.equal(saves, 1);

  const returning = await boot();
  await press(returning, 'loading-out-png-11', 'home_bottom');
  assert.equal(saves, 1);
  const replay = await boot(true);
  await press(replay, 'loading-out-png-11', 'StoryIntro01');
  await press(replay, 'story-skip-01', 'home_bottom');
  assert.equal(saves, 2);

  storage.clear();
  const skipped = await boot();
  await press(skipped, 'loading-out-png-11', 'StoryIntro01');
  await press(skipped, 'story-next-01', 'StoryIntro02');
  const skip = skipped.current.renderer.getElement('story-skip-02');
  assert.equal(skip.attributes['aria-label'], '이야기 건너뛰기');
  let prevented = false;
  skip.listeners.keydown({ key: ' ', preventDefault() { prevented = true; } });
  for (let attempts = 0; attempts < 100 && skipped.current.name !== 'home_bottom'; attempts++) await delay(1);
  assert.ok(prevented);
  assert.equal(skipped.current.name, 'home_bottom');
  assert.equal(storage.get(key), '1');
  assert.equal(saves, 3);
  assert.deepEqual(errors, [], 'Story navigation must not emit FlowDriver errors');
} finally {
  globalThis.fetch = nativeFetch;
  if (nativeStorage === undefined) delete globalThis.localStorage;
  else globalThis.localStorage = nativeStorage;
  Object.assign(console, consoleMethods);
}
console.log('story intro: 5 edges, load gate, both pages, completion, skip, keyboard, replay and return visit passed');
