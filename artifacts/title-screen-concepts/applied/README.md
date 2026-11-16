# Applied title artwork

The user approved revision 05 B and requested application to the game's title/loading screen.

## Runtime changes

- Replaced `title_bg.png` and `src/assets/title_bg.png` with identical 786×1704 artwork matching the existing 393×852 splash image geometry.
- Replaced `src/assets/title_text.png` with a transparent image at its existing 1186×1240 dimensions. The approved background already includes the new WATER MEOW logo, so the old separate logo must not overlap it.
- Set `SPLASH_CACHE_VERSION` to `title-lobby-model-v6` in the current web entry and its Godot export template, preserving all previously pending edits in both files. Before `flow.start()`, revalidate all three title image URLs with `cache: 'no-cache'` and consume their responses so native image/CSS requests use refreshed browser HTTP cache entries.

The published splash contract and editor scene remain byte-identical. Loading bar widgets, events, timeline and first-entry story/lobby branches were not changed. No renderer, manager or Godot runtime changes were needed. The previous three assets and exact pre-task host files are backed up under `before/`.

## Portrait adaptation

The approved 1024×1536 artwork is cropped only at the outer scenery (`x=85..970`) and uniformly resized into the taller canvas. The accepted scientist, all three cats and the logo are retained. Sunburst supplies quiet forest/grass extensions above and below; only extension strips and narrow environmental overlaps are used. The central accepted source artwork (`y=40..1488`) remains pixel-identical before uniform resizing. Extension alignment, overlaps and dimensions are recorded in `portrait-layout.json`.

`applied-layout-preview.jpg` is an **offline layout preview**, matching the published backdrop/image positions and loading art. It is not a screenshot of the running game.

## Verification

- `node tests/splash_cache_check.mjs`: passed.
- HTTP GETs from the existing localhost server for all three changed image URLs: 200, PNG content type, exact matching file hashes.
- The old logo is fully transparent while retaining its original dimensions.
- Published/editor splash JSON hashes are unchanged.
- Host changes are limited to the cache version and title image revalidation before scene startup.
- Offline asset/layout image inspected; actual browser visual verification is left to the user under the workspace instructions.
- The existing publish report has no errors; its pre-existing unrelated warnings were not changed.

Machine-readable checks: `checks.json`.

## Follow-up: old title after refresh

The user confirmed the active URL is `http://localhost:8080/web/?story=replay`. That exact page and all three image URLs serve current files. The first application changed the application's Cache API namespace but retained stable image URLs and omitted native browser HTTP-cache revalidation. Normal `<img>` and CSS requests do not pass through the application's `window.fetch` cache wrapper. The follow-up adds explicit HTTP revalidation before the first renderer is created, without changing the published contracts, renderer, image layout, or story-replay route.

The cache regression initially failed for missing title-image refresh and passed after the fix. It checks both host files with/without Cache API, response consumption before startup, and visible failure instead of proceeding with old art if refresh returns an error. Requests with the old image modification date receive 200 and bytes matching the current images. Actual browser visual confirmation remains the user's check.

## Additional image generation

Only environmental extensions were generated for this application step; approved character artwork was reused. `gpt-image-2.5-sunburst`, high quality, one request through the Sunburst skill's `scripts/generate_image.py` via Flava. Input text 565 tokens, input image 1,536 tokens, output image 1,372 tokens. Estimated USD 0.0281365 / KRW 39.39 at USD 1 = KRW 1,400. Raw response usage is in `generation.json`.
