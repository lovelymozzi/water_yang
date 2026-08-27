import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root = fileURLToPath(new URL('..', import.meta.url));
const uiDir = new URL('../web/ui/', import.meta.url);
const checkedJsonFiles = new Set(['effects.json', 'promo-registry.json', 'scene-flow.json']);
const assetKeys = new Set(['exportPath', 'imagePath', 'iconPath', 'icon', 'src']);
const assetExt = /\.(png|jpe?g|webp|gif|svg)(\?.*)?$/i;
const missing = [];

for (const name of readdirSync(uiDir)) {
  if (!name.endsWith('.contract.json') && !checkedJsonFiles.has(name)) continue;
  const data = JSON.parse(readFileSync(new URL(name, uiDir), 'utf8'));
  const stack = [{ path: name, value: data }];

  while (stack.length) {
    const { path: jsonPath, value } = stack.pop();
    if (Array.isArray(value)) {
      value.forEach((child, index) => stack.push({ path: `${jsonPath}[${index}]`, value: child }));
      continue;
    }
    if (!value || typeof value !== 'object') continue;

    for (const [key, child] of Object.entries(value)) {
      const childPath = `${jsonPath}.${key}`;
      if (typeof child === 'string' && assetKeys.has(key) && assetExt.test(child) && !/^(data:|https?:|blob:)/i.test(child)) {
        const assetPath = child.split('?')[0].replace(/\\/g, '/');
        if (!existsSync(join(root, assetPath)) && !existsSync(join(root, 'web', assetPath)) && !existsSync(join(root, 'web', 'ui', assetPath))) {
          missing.push(`${childPath}: ${child}`);
        }
      }
      stack.push({ path: childPath, value: child });
    }
  }
}

assert.deepEqual(missing.sort(), []);
