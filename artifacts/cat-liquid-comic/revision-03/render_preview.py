"""Render the wordless stamp concept as assets and a GIF; no game UI is changed."""
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

output = Path(__file__).resolve().parent
root = output.parents[2]
story = json.loads((root / "resources/story/cat-liquid-intro.json").read_text())
motion = story["motion"]
assert story["revision"] == 3 and story["textMode"] == "none"
assert len(motion["panelStartMs"]) == len(motion["layout"]) == 4
assert motion["panelStartMs"] == sorted(set(motion["panelStartMs"]))
assert motion["entryKeyframes"][-1]["scale"] == 1
assert motion["entryKeyframes"][-1]["translateY"] == 0
assert motion["keepPreviousPanels"] and not motion["loopEntrance"]

scale = 2
width, height = story["canvas"]["width"], story["canvas"]["height"]
all_frames = []
boards = []
frame_records = []
for page_index, page in enumerate(story["pages"], 1):
    source = Image.open(output / f"page-{page_index:02d}-generated.png").convert("RGB")
    assert source.size == (1024, 1536)
    source.save(root / page["art"], "WEBP", quality=94, method=6)
    cards = []
    settled = []
    for slot, panel in enumerate(page["panels"]):
        assert "caption" not in panel
        left, top = (0 if slot % 2 == 0 else 524), (0 if slot < 2 else 780)
        art = source.crop((left, top, left + 500, top + 756))
        art.save(root / panel["art"], "WEBP", quality=95, method=6)
        art = ImageOps.fit(art, (motion["imageWidth"] * scale, motion["imageHeight"] * scale), Image.Resampling.LANCZOS)
        padding = motion["framePaddingPx"] * scale
        paper_w, paper_h = art.width + padding * 2, art.height + padding * 2
        card = Image.new("RGBA", (paper_w + 6 * scale, paper_h + 7 * scale))
        draw = ImageDraw.Draw(card)
        draw.rectangle((3 * scale, 4 * scale, paper_w + 3 * scale, paper_h + 4 * scale), fill=(83, 44, 30, 42))
        draw.rectangle((0, 0, paper_w - 1, paper_h - 1), fill=motion["paperColor"])
        card.paste(art, (padding, padding))
        draw.rectangle((0, 0, paper_w - 1, paper_h - 1), outline=motion["frameInk"], width=motion["frameBorderPx"] * scale)
        cards.append(card)
        settled.append(card.rotate(motion["layout"][slot]["rotationDeg"], Image.Resampling.BICUBIC, expand=True))
    for time_ms in range(0, motion["previewPageDurationMs"], motion["frameDurationMs"]):
        canvas = Image.new("RGBA", (width * scale, height * scale), motion["paperColor"])
        visible = []
        for slot, card in enumerate(cards):
            elapsed = time_ms - motion["panelStartMs"][slot]
            if elapsed < 0:
                continue
            visible.append(slot + 1)
            layout = motion["layout"][slot]
            delta_y = 0
            if elapsed >= motion["entryDurationMs"]:
                shown = settled[slot]
            else:
                progress = elapsed / motion["entryDurationMs"]
                keys = motion["entryKeyframes"]
                a, b = next((a, b) for a, b in zip(keys, keys[1:]) if a["offset"] <= progress <= b["offset"])
                t = (progress - a["offset"]) / (b["offset"] - a["offset"])
                zoom = a["scale"] + (b["scale"] - a["scale"]) * t
                rotation = a["rotationOffsetDeg"] + (b["rotationOffsetDeg"] - a["rotationOffsetDeg"]) * t
                delta_y = a["translateY"] + (b["translateY"] - a["translateY"]) * t
                shown = card.resize((round(card.width * zoom), round(card.height * zoom)), Image.Resampling.LANCZOS)
                shown = shown.rotate(layout["rotationDeg"] + rotation, Image.Resampling.BICUBIC, expand=True)
            center_x, center_y = layout["centerX"] * scale, (layout["centerY"] + delta_y) * scale
            canvas.alpha_composite(shown, (round(center_x - shown.width / 2), round(center_y - shown.height / 2)))
            if elapsed < motion["impactLineDurationMs"]:
                draw = ImageDraw.Draw(canvas)
                for degrees in range(0, 360, 45):
                    theta = math.radians(degrees)
                    x = center_x + math.cos(theta) * (shown.width / 2 + 2 * scale)
                    y = center_y + math.sin(theta) * (shown.height / 2 + 2 * scale)
                    draw.line((x, y, x + math.cos(theta) * 9 * scale, y + math.sin(theta) * 9 * scale), fill=motion["frameInk"], width=2 * scale)
        assert visible == [index + 1 for index, start in enumerate(motion["panelStartMs"]) if start <= time_ms]
        frame_records.append({"page": page_index, "timeMs": time_ms, "visiblePanels": visible})
        all_frames.append(canvas.convert("RGB").resize((width, height), Image.Resampling.LANCZOS))
    assert visible == [1, 2, 3, 4]
    board = canvas.convert("RGB")
    board.save(output / f"page-{page_index:02d}-board.png")
    boards.append(board)

contact = Image.new("RGB", (width * scale * 2 + 24, height * scale), motion["paperColor"])
for index, board in enumerate(boards):
    contact.paste(board, (index * (width * scale + 24), 0))
contact.save(output / "two-page-board.jpg", quality=94)
palette = contact.resize((512, 512)).quantize(colors=192)
gif_frames = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in all_frames]
gif_frames[0].save(output / "stamp-preview.gif", save_all=True, append_images=gif_frames[1:], duration=motion["frameDurationMs"], loop=0, disposal=2, optimize=True)
gif = Image.open(output / "stamp-preview.gif")
duration_ms = 0
for index in range(gif.n_frames):
    gif.seek(index)
    duration_ms += gif.info["duration"]
assert duration_ms == len(story["pages"]) * motion["previewPageDurationMs"]
frames_per_page = motion["previewPageDurationMs"] // motion["frameDurationMs"]
for page_index in range(len(story["pages"])):
    sample_indices = [start // motion["frameDurationMs"] + 2 for start in motion["panelStartMs"]]
    sample_indices += [(motion["panelStartMs"][-1] + motion["entryDurationMs"]) // motion["frameDurationMs"] + 1, frames_per_page - 1]
    samples = [all_frames[page_index * frames_per_page + index] for index in sample_indices]
    assert samples[-1].tobytes() == samples[-2].tobytes(), "Settled panels continue moving"
    sheet = Image.new("RGB", (width * 3, height * 2), motion["paperColor"])
    for index, sample in enumerate(samples):
        sheet.paste(sample, ((index % 3) * width, (index // 3) * height))
    sheet.save(output / f"page-{page_index+1:02d}-motion-frames.jpg", quality=92)
manifest = []
for path in sorted((root / "src/assets").glob("story_cat_liquid_*.webp")):
    with Image.open(path) as image:
        dimensions = list(image.size)
        image.verify()
    manifest.append({"path": str(path.relative_to(root)), "size": dimensions, "bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
(output.parent / "asset-manifest.json").write_text(json.dumps({"version": 1, "revision": 3, "assets": manifest}, ensure_ascii=False, indent=2) + "\n")
(output / "motion-check.json").write_text(json.dumps({"kind": "offline-preview-only", "frameDurationMs": motion["frameDurationMs"], "previewDurationMs": duration_ms, "gifFrames": gif.n_frames, "records": frame_records}, ensure_ascii=False, indent=2) + "\n")
print(f"STAMP PREVIEW: PASS — {duration_ms}ms, {gif.n_frames} GIF frames, no rendered text; {sum(item['bytes'] for item in manifest)} art bytes")
