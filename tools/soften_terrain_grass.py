"""Recolor grass while preserving its texture variation and non-green pixels."""

import argparse
import colorsys
import hashlib
import json
from pathlib import Path
import re

from PIL import Image

asset_dir = Path(__file__).resolve().parents[1] / "resources/terrain/jam3d"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--lobby", action="store_true", help="Use the lobby lawn palette")
args = parser.parse_args()
source = asset_dir / "wall1.png"
target = asset_dir / ("wall1_lobby.png" if args.lobby else "wall1_soft.png")
if args.lobby:
    # Original lobby tint, before it adopted this atlas. Do not read the atlas
    # multiplier back as a target palette and create recoloring feedback.
    lobby_color = (0.46, 0.62, 0.32)
    terrain_color = tuple(float(value) for value in re.search(
        r"albedo_color = Color\(([^)]+)\)", (asset_dir / "wall_material.tres").read_text()
    )[1].split(","))[:3]
original = Image.open(source).convert("RGBA")
if args.lobby:
    grass_region = (0.135461, 0.135866, 0.452677, 0.452678)
    x, y, width, height = grass_region
    reference = original.crop((int(x * original.width), int(y * original.height),
                               int((x + width) * original.width), int((y + height) * original.height)))
    reference_hsv = [colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
                     for red, green, blue, _ in reference.get_flattened_data()]
    reference_mean = tuple(sum(pixel[channel] for pixel in reference_hsv) / len(reference_hsv) for channel in range(3))
    # Match the average palette; constant H shift and S/V ratios retain texture contrast.
    target_hsv = colorsys.rgb_to_hsv(*(value / tint for value, tint in zip(lobby_color, terrain_color)))
    hue_shift = target_hsv[0] - reference_mean[0]
    saturation_ratio = target_hsv[1] / reference_mean[1]
    value_ratio = target_hsv[2] / reference_mean[2]
pixels = []
changed = 0
for red, green, blue, alpha in original.get_flattened_data():
    r, g, b = red / 255, green / 255, blue / 255
    # Smooth green dominance mask leaves the brown cliff/rock palette alone.
    weight = max(0.0, min(1.0, (g - max(r, b) - 0.02) / 0.08))
    hue, saturation, value = colorsys.rgb_to_hsv(r, g, b)
    if args.lobby:
        matched = colorsys.hsv_to_rgb((hue + hue_shift) % 1.0,
                                     min(saturation * saturation_ratio, 1.0), min(value * value_ratio, 1.0))
        softened = tuple(source_value * (1 - weight) + target_value * weight
                         for source_value, target_value in zip((r, g, b), matched))
    else:
        softened = colorsys.hsv_to_rgb(
            hue, saturation * (1 - 0.18 * weight), value * (1 - 0.03 * weight)
        )
    result = tuple(round(channel * 255) for channel in softened) + (alpha,)
    pixels.append(result)
    changed += result != (red, green, blue, alpha)
output = Image.new("RGBA", original.size)
output.putdata(pixels)
output.save(target)
metadata = {
    "source": "wall1.png",
    "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
    "output": target.name,
    "output_sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
    "operation": "HSV saturation and value reduction, preserving hue and alpha",
    "green_mask": "clamp((G - max(R, B) - 0.02) / 0.08, 0, 1), sRGB channels 0-1",
    "saturation_multiplier_at_full_mask": 0.82,
    "value_multiplier_at_full_mask": 0.97,
    "changed_pixels": changed,
    "generator": "tools/soften_terrain_grass.py",
    "verification": "Texture pixel measurements only; rendered appearance requires user review.",
}
if args.lobby:
    metadata.pop("saturation_multiplier_at_full_mask")
    metadata.pop("value_multiplier_at_full_mask")
    metadata.update({
        "operation": "Match mean grass palette to lobby with constant HSV hue shift and saturation/value ratios; preserve spatial texture contrast, non-green pixels and alpha",
        "palette_origin": "Original lobby ground albedo_tint before shared terrain texturing; fixed to avoid recoloring feedback",
        "lobby_albedo_srgb": lobby_color,
        "terrain_tint_srgb": terrain_color,
        "reference_region_uv": grass_region,
        "reference_mean_hsv": reference_mean,
        "target_texture_hsv": target_hsv,
        "hue_shift": hue_shift,
        "saturation_ratio": saturation_ratio,
        "value_ratio": value_ratio,
        "generator_arguments": ["--lobby"],
    })
target.with_suffix(".source.json").write_text(
    json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
)
print(f"GRASS ATLAS {target.name}: {changed}/{len(pixels)} pixels adjusted; source unchanged")
