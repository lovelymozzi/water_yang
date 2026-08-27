import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const shell = readFileSync(new URL('../godot-shell.html', import.meta.url), 'utf8');
const productConfig = shell.match(/const SHOP_PRODUCTS = ([\s\S]*?\n};)\nconst DEFAULT_HEART_ICON/)?.[1];
const formatter = shell.match(/function formatShopCooldown\(ms\) \{[\s\S]*?\n\}/)?.[0];
assert.ok(productConfig, 'godot-shell.html must define SHOP_PRODUCTS');
assert.ok(formatter, 'godot-shell.html must define formatShopCooldown');

const { SHOP_PRODUCTS, formatShopCooldown } = Function(
  `const SHOP_PRODUCTS = ${productConfig}\n${formatter}\nreturn { SHOP_PRODUCTS, formatShopCooldown };`,
)();

assert.equal(SHOP_PRODUCTS[860].cooldownMs, 24 * 60 * 60 * 1000);
assert.equal(SHOP_PRODUCTS[480].cooldownMs, 24 * 60 * 60 * 1000);
assert.equal(SHOP_PRODUCTS[320].cooldownMs, 60 * 60 * 1000);
assert.equal(SHOP_PRODUCTS[320].timerText, 'plain-text-2504');

assert.equal(formatShopCooldown(24 * 60 * 60 * 1000), '24:00:00');
assert.equal(formatShopCooldown(60 * 60 * 1000), '01:00:00');
assert.equal(formatShopCooldown(999), '00:00:01');
assert.equal(formatShopCooldown(0), '00:00:00');
