import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

// Exercise the renderer's actual image swap with a deliberately delayed decoder.
const source = readFileSync(process.argv[2] || new URL('../web/ui/scene-renderer.js', import.meta.url), 'utf8');
const geometry = source.slice(source.indexOf('function sliceGeometry('), source.indexOf('// 9-slice 렌더용 CSS'));
const compose = source.slice(source.indexOf('function composeSliceBitmap('), source.indexOf('// slice 붕괴(모서리만 남고 중앙이 사라짐) 사유'));
const ready = source.slice(source.indexOf('    _whenRenderResourcesReady() {'), source.indexOf('\n    hide() {'));
let finishDecode;
const context = {
  Image: class { decode() { return new Promise(resolve => { finishDecode = resolve; }); } },
  window: { devicePixelRatio: 1 },
  document: {
    querySelectorAll: () => [],
    createElement: () => ({
      getContext: () => ({ scale() {}, drawImage() {} }),
      toBlob: callback => callback({}),
    }),
  },
  URL: { createObjectURL: () => 'blob:composed-button' },
  _loadSliceImage: async () => ({ naturalWidth: 30, naturalHeight: 30 }),
  _sliceBitmapCache: new Map(), SLICE_BITMAP_CACHE_MAX: 60,
  RENDER_RESOURCE_TIMEOUT_MS: 2000,
  setTimeout, clearTimeout,
  console: { info() {}, warn: (...args) => { throw new Error(args.join(' ')); } },
  style: { slice: { enabled: true, left: 2, right: 2, top: 2, bottom: 2, scale: 1 } },
  element: { style: { borderImage: 'url(original.png)' } },
};
runInNewContext(`${geometry}\n${compose}\nclass RenderGate { ${ready} }
var bitmap = composeSliceBitmap(style, 'original.png', 1, 1, 100, 50);
applySliceBitmapUpgrade(element, style, 'original.png', 1, 1, 100, 50);
var gateFinished = false;
var gate = new RenderGate()._whenRenderResourcesReady().then(() => { gateFinished = true; });
`, context);
await new Promise(setImmediate);
assert.equal(context.element.style.borderImage, 'url(original.png)', 'Existing image removed before the replacement was decoded');
assert.equal(context.gateFinished, false, 'Scene revealed before its composed images were decoded');
assert.equal(typeof finishDecode, 'function', 'Composed image was never passed to the decoder');
finishDecode();
await Promise.all([context.bitmap, context.gate]);
assert.equal(context.element.style.borderImage, 'none');
assert.ok(context.element.style.background.includes('blob:composed-button'));
assert.equal(context.gateFinished, true);
assert.equal(context._sliceBitmapCache.size, 1, 'Identical images did not share composition');
console.log('UI SLICE DECODE CHECK: PASS (original kept until decode, reveal waits, shared bitmap promise)');
