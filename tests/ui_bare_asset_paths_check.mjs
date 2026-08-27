import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root = fileURLToPath(new URL('..', import.meta.url));
const contractsDir = new URL('../web/ui/', import.meta.url);
const missing = [];

for (const name of readdirSync(contractsDir)) {
  if (!name.endsWith('.contract.json')) continue;
  const contract = JSON.parse(readFileSync(new URL(name, contractsDir), 'utf8'));
  for (const layer of contract.layers || []) {
    const exportPath = layer.image?.exportPath || layer.visual?.exportPath || '';
    if (!exportPath || exportPath.includes('/') || exportPath.startsWith('.')) continue;
    if (!existsSync(join(root, exportPath))) missing.push(`${name}: ${exportPath}`);
  }
}

assert.deepEqual(missing, []);
