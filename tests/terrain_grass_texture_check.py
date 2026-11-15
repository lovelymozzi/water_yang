"""Check that recoloring keeps the grass pattern instead of filling it flat."""

import colorsys
import hashlib
import json
from pathlib import Path
import statistics

from PIL import Image

asset_dir = Path(__file__).resolve().parents[1] / "resources/terrain/jam3d"
metadata = json.loads((asset_dir / "wall1_lobby.source.json").read_text())
source = Image.open(asset_dir / metadata["source"]).convert("RGBA")
output = Image.open(asset_dir / metadata["output"]).convert("RGBA")
assert source.size == output.size
unchanged = 0
for original, recolored in zip(source.get_flattened_data(), output.get_flattened_data()):
    assert original[3] == recolored[3], "Recoloring changed alpha"
    if (original[1] - max(original[0], original[2])) / 255 <= 0.02:
        assert original == recolored, "Recoloring changed non-green cliff/rock pixels"
        unchanged += 1

x, y, width, height = metadata["reference_region_uv"]
region = (int(x * source.width), int(y * source.height),
          int((x + width) * source.width), int((y + height) * source.height))
original_hsv = [colorsys.rgb_to_hsv(*(value / 255 for value in pixel[:3]))
                for pixel in source.crop(region).get_flattened_data()]
recolored_hsv = [colorsys.rgb_to_hsv(*(value / 255 for value in pixel[:3]))
                 for pixel in output.crop(region).get_flattened_data()]
original_value = [pixel[2] for pixel in original_hsv]
recolored_value = [pixel[2] for pixel in recolored_hsv]
correlation = statistics.correlation(original_value, recolored_value)
assert correlation > 0.99, "Original texture pattern was lost"
assert statistics.pstdev(recolored_value) > statistics.pstdev(original_value) * 0.5
assert max(abs(new - old * metadata["value_ratio"])
           for old, new in zip(original_value, recolored_value)) <= 0.5 / 255 + 1e-8
for channel, target in enumerate(metadata["target_texture_hsv"]):
    assert abs(statistics.mean(pixel[channel] for pixel in recolored_hsv) - target) < 0.004
for file_key, hash_key in [("source", "source_sha256"), ("output", "output_sha256")]:
    assert hashlib.sha256((asset_dir / metadata[file_key]).read_bytes()).hexdigest() == metadata[hash_key]
print(f"GRASS TEXTURE CHECK: PASS pattern correlation={correlation:.6f}; brightness pattern retained within 8-bit rounding; {unchanged} non-green pixels and alpha unchanged")
