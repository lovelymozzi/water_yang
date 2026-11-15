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
}
