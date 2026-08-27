import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

for (const file of ['../godot-shell.html', '../web/index.html']) {
  const shell = readFileSync(new URL(file, import.meta.url), 'utf8');
  assert.match(shell, /const uiPublishPath = new URL\(UI_DIR, location\.href\)\.pathname;/);
  assert.match(shell, /url\.pathname\.startsWith\(uiPublishPath\)/);
  assert.match(shell, /url\.pathname\.includes\('\/src\/assets\/'\)/);
}
