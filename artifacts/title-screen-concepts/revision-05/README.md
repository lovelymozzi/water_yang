# Title concept B — actual lobby cat form

The user requested another cat-shape correction after revision 04 still looked unlike the lobby.

## References and method

The saved real game screenshot `.tools/water-verification/physical-coherent-coupled-stable-final-early-dense/60.png` supplies the cat reference. The orange cat was segmented within crop `[222, 427, 439, 512]`, retaining its silhouette, face, shoulder/foreleg transition and separated hindlegs. The resulting upright sprite is 62×194 pixels. Its length/width ratio, 3.129, is a measurement of this saved 2D projection, not a model-space measurement.

The actual sprite was uniformly scaled/rotated and placed at each of the title illustration's three cat locations. This produced a structural input with actual lobby contours, rather than relying on verbal descriptions of a long cat. The green/blue placeholders are hue variations of that same sprite. Their temporary flat cyan surroundings are input guides only.

Runtime source inspection confirms the lobby uses `CatEntity.load_model_with_texture()` from `water_yang/cat1.fbx`, with a floating orientation; the model identifies head `Bone002` and front-paw/chest transition `Bone006`. No engine execution, new game capture, runtime code or published UI changes form part of this artwork task.

## Generation

Sunburst skill `scripts/generate_image.py` via Flava, `gpt-image-2.5-sunburst`, high quality. The first edit redraws the sprite-guided cats in the title's illustration style. A second edit corrects the first result's unexpectedly fluorescent green fur and busy water caustics, while retaining the corrected cat anatomy. Exact gateway response metadata accompanies both requests.

Final image selection, comparison crops, usage totals and asset hashes are recorded in `review.json` after output inspection. All images here are offline concepts, not screenshots of the running game.
