# fx_char_levelup_01 comparison

`tall-fan-comparison.png` shows the subsequent requested silhouette change: before above, tall fan below at 0.10/0.20/0.30 seconds. Only the two additive cylinder layers are stretched to 1.9× height and flared continuously from 1× base width to 2.25× top width, with a soft top fade. The original animation tracks and textures are retained; this intentionally changes the source cylinder silhouette.

`layer-order-comparison.png` shows the corrected overlap at 0.10/0.20/0.30 seconds: before above, after below. The entering cat retains its opaque surface and depth while its color turns to pale yellow light. This hides the rear vortex beneath the cat; the foreground cylinder and particles remain above it. Only the normal below-floor sink clip removes the cat surface.

`lowered-position-comparison.png` shows the following position adjustment: the cylinder's lower edge is aligned with the actual aperture surface's projected bottom edge. Size and depth are preserved. Before above, lowered below.

`absorb-cover-comparison.png` shows the later user-requested entry cover: before above, after below. Only the part entering the aperture is concealed; the body outside remains visible. This cover is a game adaptation separate from the unchanged source animation tracks.

- Reference: the existing authenticated UI Editor tab's Unity preview, black background, 4× zoom, paused at 0.10/0.20/0.30 seconds. Reference crops omit surrounding account/UI information.
- Game: Godot 4.7.2 stable, actual OpenGL Compatibility rendering on Apple M3 Pro, 520×912. The stage-1 solution triggers normal cat absorption. Animation and cat absorption advance to the indicated times; CPU particles are separately sought using preprocess/restart. Game crops are enlarged for inspection.
- `comparison.png`: Unity above, actual stage-1 render below. Backgrounds and crop magnifications differ; this is a shape/timing review, not a pixel-equality or size measurement.
- `isolated-comparison.png`: source and isolated Godot renders. The isolated test instance is enlarged 4×; this test option does not change gameplay scale.
- Source comparison: 24 tracks × 73 timestamps; 3,431 scalar comparisons, maximum error 0.000000299. All seven original texture hashes match. This does not establish rendered pixel equality.
- Native Unity bundles identify the missing raw-YAML sprite material as Sprite-Unlit-Default with SrcAlpha/OneMinusSrcAlpha. Only the two cylinder sprites use additive glow_01. Bundle hashes are recorded in `resources/cat_absorb_levelup_effect.source.json`.
- Remaining variation: native CPU random-particle sampling and engine compositing/pixel sampling. Exact pixel equality is not claimed.

Reproduce from the project root:

```sh
/Users/al02501031/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . tests/hole_check.tscn
/Users/al02501031/Downloads/Godot.app/Contents/MacOS/Godot --path . --rendering-method gl_compatibility --resolution 520x912 tests/hole_check.tscn -- --fx-stage1-capture
python3 tests/absorb_levelup_source_check.py
```
