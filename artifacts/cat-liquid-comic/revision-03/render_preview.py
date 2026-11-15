"""Build the current comic cards and an offline stamp preview from unchanged Sunburst art."""
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageOps

source_dir = Path(__file__).resolve().parent
root = source_dir.parents[2]
story = json.loads((root / "resources/story/cat-liquid-intro.json").read_text())
output = source_dir.parent / f"revision-{story['revision']:02d}"
output.mkdir(exist_ok=True)
motion = story["motion"]
assert story["revision"] == 4 and story["textMode"] == "panel-captions"
assert len(motion["panelStartMs"]) == len(motion["layout"]) == 4
assert motion["panelStartMs"] == sorted(set(motion["panelStartMs"]))
assert motion["entryKeyframes"][-1]["scale"] == 1
assert motion["entryKeyframes"][-1]["translateY"] == 0
assert motion["keepPreviousPanels"] and not motion["loopEntrance"]

scale = 2
caption_font = ImageFont.truetype("/Library/Fonts/Managed/NanumGothicOTFBold_1589433817.otf", round(motion["captionFontSizePx"] * scale))
caption_height = motion["captionHeightPx"] * scale
caption_checks = []
width, height = story["canvas"]["width"], story["canvas"]["height"]
all_frames = []
boards = []
frame_records = []
for page_index, page in enumerate(story["pages"], 1):
    source = Image.open(source_dir / f"page-{page_index:02d}-generated.png").convert("RGB")
    assert source.size == (1024, 1536)
    source.save(root / page["art"], "WEBP", quality=94, method=6)
    cards = []
    settled = []
    for slot, panel in enumerate(page["panels"]):
        caption = panel["caption"]
        assert 2 <= len(caption.splitlines()) <= 3
        left, top = (0 if slot % 2 == 0 else 524), (0 if slot < 2 else 780)
        art = source.crop((left, top, left + 500, top + 756))
        art.save(root / panel["art"], "WEBP", quality=95, method=6)
        art = ImageOps.fit(art, (motion["imageWidth"] * scale, motion["imageHeight"] * scale), Image.Resampling.LANCZOS)
        padding = motion["framePaddingPx"] * scale
        paper_w, paper_h = art.width + padding * 2, art.height + padding * 2 + caption_height
        card = Image.new("RGBA", (paper_w + 6 * scale, paper_h + 7 * scale))
        draw = ImageDraw.Draw(card)
        draw.rectangle((3 * scale, 4 * scale, paper_w + 3 * scale, paper_h + 4 * scale), fill=(83, 44, 30, 42))
        draw.rectangle((0, 0, paper_w - 1, paper_h - 1), fill=motion["paperColor"])
        card.paste(art, (padding, padding))
        caption_top = padding + art.height
        draw.line((padding, caption_top, paper_w - padding, caption_top), fill=motion["frameInk"], width=scale)
        bbox = draw.multiline_textbbox((0, 0), caption, font=caption_font, spacing=3 * scale, align="center")
        assert bbox[2] - bbox[0] <= paper_w - 16 * scale, f"Caption too wide: {panel['number']}"
        assert bbox[3] - bbox[1] <= caption_height - 8 * scale, f"Caption too tall: {panel['number']}"
        text_x = (paper_w - bbox[2] - bbox[0]) / 2
        text_y = caption_top + (caption_height - bbox[3] - bbox[1]) / 2
        draw.multiline_text((text_x, text_y), caption, font=caption_font, spacing=3 * scale, align="center", fill=motion["frameInk"])
        caption_checks.append({"panel": panel["number"], "caption": caption, "textBoundsPx": list(bbox), "fits": True, "cardSize": list(card.size)})
        draw.rectangle((0, 0, paper_w - 1, paper_h - 1), outline=motion["frameInk"], width=motion["frameBorderPx"] * scale)
        card.save(root / panel["cardArt"], "WEBP", quality=95, method=6)
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
card_w, card_h = card.width / scale, card.height / scale
impact = Image.new("RGBA", (card.width + 24 * scale, card.height + 24 * scale))
impact_draw = ImageDraw.Draw(impact)
for degrees in range(0, 360, 45):
    theta = math.radians(degrees)
    impact_x = (card_w / 2 + 12 + math.cos(theta) * (card_w / 2 + 2)) * scale
    impact_y = (card_h / 2 + 12 + math.sin(theta) * (card_h / 2 + 2)) * scale
    impact_draw.line((impact_x, impact_y, impact_x + math.cos(theta) * 9 * scale, impact_y + math.sin(theta) * 9 * scale), fill=motion["frameInk"], width=2 * scale)
impact.save(root / story["integration"]["impactArt"])
palette = contact.resize((512, 512)).quantize(colors=192)
gif_frames = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in all_frames]
gif_frames[0].save(output / "stamp-preview.gif", save_all=True, append_images=gif_frames[1:], duration=motion["frameDurationMs"], loop=0, disposal=2, optimize=True)
gif = Image.open(output / "stamp-preview.gif")
duration_ms = 0
decoded_samples = {}
sample_times = [0, 1000, 2200, 3300, 4400, 6300]
for index in range(gif.n_frames):
    gif.seek(index)
    frame_end = duration_ms + gif.info["duration"]
    for page_index in range(len(story["pages"])):
        for sample_time in sample_times:
            if duration_ms <= page_index * motion["previewPageDurationMs"] + sample_time < frame_end:
                decoded_samples[(page_index, sample_time)] = gif.convert("RGB").copy()
    duration_ms = frame_end
assert duration_ms == len(story["pages"]) * motion["previewPageDurationMs"]
for page_index in range(len(story["pages"])):
    background = decoded_samples[(page_index, 0)].getpixel((0, 0))
    visible_counts = []
    for sample_time in sample_times:
        decoded = decoded_samples[(page_index, sample_time)]
        visible_count = 0
        for layout in motion["layout"]:
            crop = decoded.crop((layout["centerX"] - 20, layout["centerY"] - 20, layout["centerX"] + 20, layout["centerY"] + 20))
            visible_count += ImageChops.difference(crop, Image.new("RGB", crop.size, background)).getbbox() is not None
        visible_counts.append(visible_count)
    assert visible_counts == [0, 1, 2, 3, 4, 4], visible_counts
    first_layout = motion["layout"][0]
    first_box = (first_layout["centerX"] - 40, first_layout["centerY"] - 40, first_layout["centerX"] + 40, first_layout["centerY"] + 40)
    assert decoded_samples[(page_index, 1000)].crop(first_box).tobytes() == decoded_samples[(page_index, 6300)].crop(first_box).tobytes()
    assert decoded_samples[(page_index, 4400)].tobytes() == decoded_samples[(page_index, 6300)].tobytes()
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
for path in sorted([*(root / "src/assets").glob("story_cat_liquid_*.webp"), root / "src/assets/story_cat_liquid_impact.png", root / story["integration"]["impactArt"]]):
    with Image.open(path) as image:
        dimensions = list(image.size)
        image.verify()
    manifest.append({"path": str(path.relative_to(root)), "size": dimensions, "bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
(output.parent / "asset-manifest.json").write_text(json.dumps({"version": 1, "revision": story["revision"], "assets": manifest}, ensure_ascii=False, indent=2) + "\n")
(output / "motion-check.json").write_text(json.dumps({"kind": "offline-preview-only", "frameDurationMs": motion["frameDurationMs"], "previewDurationMs": duration_ms, "gifFrames": gif.n_frames, "records": frame_records, "encodedGifInspection": {"visibleCountsEachPage": visible_counts, "firstPanelUnchangedAfterSettle": True, "finalHoldPixelsUnchanged": True, "durationMs": duration_ms}}, ensure_ascii=False, indent=2) + "\n")
(output / "caption-check.json").write_text(json.dumps({"kind": "offline-asset-check", "font": "Nanum Gothic Bold (rasterized, no runtime font dependency)", "fontSizePx": motion["captionFontSizePx"], "panels": caption_checks}, ensure_ascii=False, indent=2) + "\n")
print(f"STAMP PREVIEW: PASS — {duration_ms}ms, {gif.n_frames} GIF frames, {len(caption_checks)} fitted Korean captions; {sum(item['bytes'] for item in manifest)} art bytes")
