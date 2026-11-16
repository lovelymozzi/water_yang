import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
const { getDevStage, mountDevTools } = await import(`data:text/javascript;base64,${Buffer.from(read('web/dev-tools.js')).toString('base64')}`);
for (const hostname of ['localhost', '127.0.0.1', '[::1]']) {
  for (const stage of [1, 17, 187]) assert.equal(getDevStage(new URL(`http://${hostname}:8080/web/?devStage=${stage}`), 187), stage);
  for (const value of ['', '0', '-1', '188', '1.5', 'NaN', '1e2', ' 1']) {
    assert.throws(() => getDevStage(new URL(`http://${hostname}/?devStage=${encodeURIComponent(value)}`), 187), /DEV/);
  }
}
assert.equal(getDevStage(new URL('https://example.com/?devStage=70'), 187), null);
assert.equal(getDevStage(new URL('http://localhost:8080/web/?story=replay'), 187), null);

// Exercise the external controls without rendering or navigating a browser.
const assigned = [];
globalThis.location = { hostname: 'localhost', href: 'http://localhost:8080/web/?foam=short&story=replay&resetStage=1', assign: href => assigned.push(new URL(href)) };
const nodes = new Map(['details', 'form', 'input', 'p', '[data-story-replay]'].map(selector => [selector, {
  listeners: {}, addEventListener(event, listener) { this.listeners[event] = listener; }, value: '19',
}]));
let mounted = null;
globalThis.document = {
  createElement: tag => ({ tag, dataset: {}, querySelector: selector => nodes.get(selector) }),
  body: { appendChild: node => { mounted = node; } },
};
let currentStage = 12;
let seen = true;
mountDevTools({ maxStage: 187, getCurrentStage: () => currentStage, isStorySeen: () => seen });
assert.equal(mounted.tag, 'aside');
assert.equal(mounted.dataset.devTools, '');
nodes.get('details').listeners.toggle();
assert.equal(nodes.get('input').value, 12);
assert.match(nodes.get('p').textContent, /시청 완료/);
seen = false;
currentStage = 21;
nodes.get('details').listeners.toggle();
assert.equal(nodes.get('input').value, 21);
assert.match(nodes.get('p').textContent, /미시청/);
nodes.get('input').value = '19';
let prevented = false;
nodes.get('form').listeners.submit({ preventDefault: () => { prevented = true; } });
assert.ok(prevented);
assert.equal(assigned[0].searchParams.get('devStage'), '19');
assert.equal(assigned[0].searchParams.get('foam'), 'short');
assert.equal(assigned[0].searchParams.has('story'), false);
assert.equal(assigned[0].searchParams.has('resetStage'), false);
nodes.get('input').value = '188';
assert.throws(() => nodes.get('form').listeners.submit({ preventDefault() {} }), /DEV/);
assert.equal(assigned.length, 1, 'Invalid input must not navigate');
location.href = 'http://localhost:8080/web/?devStage=19&resetStage=1&foam=short';
nodes.get('[data-story-replay]').listeners.click();
assert.equal(assigned[1].searchParams.get('story'), 'replay');
assert.equal(assigned[1].searchParams.has('devStage'), false);
assert.equal(assigned[1].searchParams.has('resetStage'), false);
assert.equal(assigned[1].searchParams.get('foam'), 'short');
mounted = null;
location.hostname = 'example.com';
mountDevTools({});
assert.equal(mounted, null, 'Published sites must not mount DEV controls');

for (const path of ['godot-shell.html', 'web/index.html']) {
  const shell = read(path);
  // Execute the real startup reset against saved progress, not a copy of its logic.
  const reset = shell.slice(shell.indexOf('const startupUrl ='), shell.indexOf('\nlet leaderboardSubmissionTail'));
  for (const query of ['?devStage=1', '?devStage=187', '?resetStage=1', '', '?story=replay']) {
    const original = { current: 8, records: { 7: { stars: 3, bestScore: 120, clears: 1 } } };
    const storage = new Map([
      ['leonout_progress_v1', JSON.stringify(original)],
      ['leonout_economy_v1', '{"hearts":3,"coins":500}'],
      ['leonout_story_cat_liquid_seen_v1', '1'],
    ]);
    let saved = 0;
    let replaced;
    const context = {
      URL, getDevStage, STORAGE_PREFIX: 'leonout_',
      location: new URL('http://localhost:8080/web/' + query),
      devStartupStage: getDevStage(new URL('http://localhost:8080/web/' + query), 187),
      localStorage: { getItem: key => storage.get(key), setItem: (key, value) => storage.set(key, value) },
      saveGame: async () => { saved++; },
      history: { replaceState: (_state, _title, href) => { replaced = new URL(href); } }, console: { info() {} },
    };
    await runInNewContext(`(async () => { ${reset} })()`, context);
    const progress = JSON.parse(storage.get('leonout_progress_v1'));
    assert.equal(progress.current, query.includes('devStage=187') ? 187 : query.includes('Stage=1') ? 1 : 8);
    assert.deepEqual(progress.records, original.records);
    assert.equal(storage.get('leonout_economy_v1'), '{"hearts":3,"coins":500}');
    assert.equal(storage.get('leonout_story_cat_liquid_seen_v1'), '1');
    assert.equal(saved, query.includes('Stage=') ? 1 : 0);
    if (replaced) assert.equal(replaced.search, '', 'Stage override must be consumed once');
  }

  // Actual post-start route must wait for preload; regular entry stays with FlowDriver.
  const startup = shell.slice(shell.indexOf('\nmountDevTools({'), shell.indexOf('\n</script>', shell.indexOf('\nmountDevTools({')));
  for (const selected of [null, 1, 187]) {
    let resolvePreload;
    const calls = [];
    const context = { devStartupStage: selected, currentMapStage: selected ?? 8,
      STORY_INTRO_SCENE_UUIDS: ['91b7f29b-8b6d-41b7-a08a-99a0a1dfb401'],
      progress: { maxStage: 187 }, mountDevTools: options => calls.push(['mount', options.getCurrentStage()]),
      localStorage: { getItem: () => '1' }, STORY_INTRO_STORAGE_KEY: 'seen', continueWithoutHeart: false,
      splashReadyPromise: new Promise(resolve => { resolvePreload = resolve; }),
      flow: { goto: async ref => calls.push(['goto', ref.uuid]) },
    };
    const boot = runInNewContext(`(async () => { ${startup} })()`, context);
    await Promise.resolve();
    assert.deepEqual(calls, [['mount', selected ?? 8]], 'Must not enter while Godot is preloading');
    resolvePreload();
    await boot;
    assert.equal(context.continueWithoutHeart, selected !== null && selected !== 1,
      'Starting the cartoon must not enable the gameplay continue flag');
    assert.equal(calls.length, selected === null ? 1 : 2);
    if (selected !== null) assert.deepEqual(calls[1], ['goto', selected === 1
      ? '91b7f29b-8b6d-41b7-a08a-99a0a1dfb401' : 'c0356bcc-a972-4ff9-b115-d91b31c3e8be']);
  }

  // A seen first-level DEV entry still preloads and plays the cartoon.
  const replay = shell.match(/const STORY_INTRO_REPLAY = [^\n]+;/)[0];
  for (const [stage, query, expected] of [[1, '', true], [2, '', false], [null, '', false], [null, '?story=replay', true]]) {
    const context = { URLSearchParams, devStartupStage: stage, location: { search: query } };
    runInNewContext(replay + '\nglobalThis.replay = STORY_INTRO_REPLAY;', context);
    assert.equal(context.replay, expected);
  }

  // Run both real document handlers with a DEV target and no gameplay dependencies.
  for (const event of ['click', 'pointerdown']) {
    const source = shell.match(new RegExp(`document\\.addEventListener\\('${event}', event => \\{[\\s\\S]*?\\n\\}, \\{ capture: true \\}\\);`))[0];
    class Element { closest(selector) { return selector === '[data-dev-tools]' ? this : null; } }
    let handler;
    runInNewContext(source, { Element, document: { addEventListener: (_name, callback) => { handler = callback; } } });
    handler({ target: new Element(), button: 0 });
  }
}
console.log('DEV tools: local-only panel, stage bounds, saved records/economy/story preserved, preload gating, replay URL and input isolation passed');
