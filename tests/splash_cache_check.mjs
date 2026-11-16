import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const baseUrl = 'http://localhost:8080/web/';
class BrowserRequest extends Request {
  constructor(input, init) {
    super(typeof input === 'string' ? new URL(input, baseUrl) : input, init);
  }
}

for (const file of ['../godot-shell.html', '../web/index.html']) {
  const shell = readFileSync(new URL(file, import.meta.url), 'utf8');
  assert.match(shell, /const uiPublishPath = new URL\(UI_DIR, location\.href\)\.pathname;/);
  assert.match(shell, /url\.pathname\.startsWith\(uiPublishPath\)/);
  assert.match(shell, /url\.pathname\.includes\('\/src\/assets\/'\)/);

  // A native fetch can return an old, still-fresh HTTP response even when Cache API is bypassed.
  const wrapper = shell.match(/window\.fetch = async \(input, init\) => \{[\s\S]*?\n\};/)[0];
  for (const cacheAvailable of [true, false]) {
    const context = {
      window: {}, Request: BrowserRequest, URL,
      location: new URL(baseUrl),
      splashCache: cacheAvailable ? { match() { assert.fail('UI JSON must bypass Cache API'); } } : null,
      uiPublishPath: '/web/ui/',
      godotEnginePath: '/web/index.js', godotPackPath: '/web/index.pck',
      splashCacheablePath: /\.(json|webp)$/,
      nativeFetch: async input => {
        const request = new BrowserRequest(input);
        return { json: async () => ({ scenes: request.cache === 'default' ? ['Lobby'] : ['Lobby', 'StoryIntro01', 'StoryIntro02'] }) };
      },
    };
    runInNewContext(wrapper, context);
    for (const path of ['scenes-index.json', 'scene-flow.json', 'StoryIntro01.contract.json']) {
      const response = await context.window.fetch('./ui/' + path);
      assert.ok((await response.json()).scenes.includes('StoryIntro01'), `${file}: stale HTTP cache used for ${path}`);
    }
  }

  // Old splash caches contain the narrated story schema from before textMode:none.
  // The caller's explicit refresh must reach the network instead of that old JSON.
  for (const cache of ['no-cache', 'reload', 'no-store']) {
    let networkCalls = 0;
    const context = {
      window: {}, Request: BrowserRequest, URL,
      location: new URL(baseUrl),
      splashCache: {
        match: async () => ({ json: async () => ({ revision: 7, textMode: 'bottom-typewriter' }) }),
        put: async () => {},
      },
      uiPublishPath: '/web/ui/',
      godotEnginePath: '/web/index.js', godotPackPath: '/web/index.pck',
      splashCacheablePath: /\.(json|webp)$/,
      nativeFetch: async (input, init) => {
        networkCalls++;
        assert.equal(new BrowserRequest(input, init).cache, cache);
        return { json: async () => ({ revision: 8, textMode: 'none' }) };
      },
    };
    runInNewContext(wrapper, context);
    const response = await context.window.fetch('../resources/story/cat-liquid-intro.json', { cache });
    assert.equal((await response.json()).textMode, 'none', `${file}: old narrated story blocked startup (${cache})`);
    assert.equal(networkCalls, 1);
  }

  // Images use native <img>/CSS requests, so changing the Cache API name does not
  // refresh their HTTP cache entries. Revalidate them before the first renderer.
  const titleStartup = shell.match(/\/\/ Revalidate title images[\s\S]*?await flow\.start\(\);/)?.[0];
  assert.ok(titleStartup, `${file}: title images can still use stale browser HTTP cache`);
  for (const cacheAvailable of [true, false]) {
    const refreshed = new Set();
    let flowStarted = false;
    const expected = ['/title_bg.png', '/src/assets/title_bg.png', '/src/assets/title_text.png'];
    const context = {
      window: {}, Request: BrowserRequest, URL, ASSET_BASE: '../',
      SPLASH_CACHE_VERSION: shell.match(/const SPLASH_CACHE_VERSION = '([^']+)'/)[1],
      location: new URL(baseUrl),
      splashCache: cacheAvailable ? { match() { assert.fail('title refresh must bypass Cache API'); } } : null,
      uiPublishPath: '/web/ui/', godotEnginePath: '/web/index.js', godotPackPath: '/web/index.pck',
      splashCacheablePath: /\.png$/,
      nativeFetch: async (input, init) => {
        const request = new BrowserRequest(input, init);
        assert.equal(request.cache, 'no-cache', `${file}: stale title HTTP cache reused`);
        return {
          ok: true,
          arrayBuffer: async () => { refreshed.add(new URL(request.url).pathname); },
        };
      },
      flow: { start: async () => {
        assert.deepEqual([...refreshed].sort(), expected.sort(), `${file}: title shown before refresh completed`);
        flowStarted = true;
      } },
    };
    runInNewContext(wrapper, context);
    context.fetch = context.window.fetch;
    await runInNewContext(`(async () => { ${titleStartup} })()`, context);
    assert.equal(flowStarted, true);

    // A failed title refresh must surface the error instead of showing old art.
    context.nativeFetch = async () => ({ ok: false, status: 404 });
    context.flow.start = () => assert.fail('failed title refresh must block stale startup');
    await assert.rejects(runInNewContext(`(async () => { ${titleStartup} })()`, context), /Title assets.*404/);
  }
}
console.log('splash cache: UI/story cache bypass and title image revalidation before startup');
