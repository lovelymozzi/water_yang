"""Build wordless phone-filling comic cards and offline previews from the generated pairs."""
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

artifact_dir = Path(__file__).resolve().parent
root = artifact_dir.parents[1]
story = json.loads((root / 'resources/story/cat-liquid-intro.json').read_text())
assert story['revision'] >= 8 and story['textMode'] == 'none'
output = artifact_dir / f'revision-{story["revision"]:02d}'
output.mkdir(exist_ok=True)
motion = story['motion']
frame_style = story['frame']
scale = 2
font = ImageFont.truetype('/Library/Fonts/Managed/NanumGothicOTFBold_1589433817.otf', 28 * scale)
background = Image.open(root / story['background']['imagePath']).convert('RGB').resize((172, 172), Image.Resampling.LANCZOS)
base = Image.new('RGB', (story['canvas']['width'] * scale, story['canvas']['height'] * scale))
for y in range(0, base.height, background.height):
    for x in range(0, base.width, background.width):
        base.paste(background, (x, y))
boards = []
frames = []
checks = []
for page_index, page in enumerate(story['pages'], 1):
    sources = []
    for pair_number in range((page_index - 1) * 2 + 1, page_index * 2 + 1):
        source_path = output / f'pair-{pair_number:02d}-generated.png'
        source = Image.open(source_path).convert('RGB')
        assert source.size == (1024, 1024)
        rows = [y for y in range(source.height)
                if all(low >= 240 for low, high in source.crop((0, y, source.width, y + 1)).getextrema())]
        runs = []
        for y in rows:
            if not runs or y != runs[-1][-1] + 1:
                runs.append([y])
            else:
                runs[-1].append(y)
        runs = [run for run in runs if len(run) >= 4]
        assert len(runs) == 1, f'Expected one white gutter in {source_path.name}, found {runs}'
        gutter = runs[0]
        assert 450 < gutter[0] < gutter[-1] < 574
        for crop in [(0, 0, source.width, gutter[0]), (0, gutter[-1] + 1, source.width, source.height)]:
            sources.append((source.crop(crop), source_path.name, crop))
    raw_page = Image.new('RGB', (1024, sum(art.height for art, _, _ in sources) + 72), 'white')
    raw_y = 0
    cards = []
    for slot, (panel, (raw, source_name, crop)) in enumerate(zip(page['panels'], sources)):
        assert 'caption' not in panel
        raw.save(root / panel['art'], 'WEBP', quality=95, method=6)
        raw_page.paste(raw, (0, raw_y))
        raw_y += raw.height + 24
        raster = 4
        size = (frame_style['cardWidth'] * raster, frame_style['cardHeight'] * raster)
        art = ImageOps.fit(raw.convert('RGBA'), size, Image.Resampling.LANCZOS,
                           centering=(0 if panel['number'] == 2 else 0.5, 0.5))
        outer = [(x * raster, y * raster) for x, y in frame_style['outlines'][slot]]
        rim = frame_style['rimPx'] * raster
        inner = [(x + (rim if x < size[0] / 2 else -rim),
                  y + (rim if y < size[1] / 2 else -rim)) for x, y in outer]
        mask = Image.new('L', size)
        ImageDraw.Draw(mask).polygon(inner, fill=255)
        if panel['number'] in frame_style['speedLinePanels']:
            lines = Image.new('RGBA', size)
            line_draw = ImageDraw.Draw(lines)
            for index, angle in enumerate(range(0, 360, 13)):
                theta = math.radians(angle)
                dx, dy = math.cos(theta), math.sin(theta)
                distance = min(size[0] / 2 / max(abs(dx), 0.001), size[1] / 2 / max(abs(dy), 0.001))
                x, y = size[0] / 2 + dx * distance, size[1] / 2 + dy * distance
                length = (9 + index % 4 * 3) * raster
                width = (0.4 + index % 3 * 0.15) * raster
                line_draw.polygon([(x - dy * width, y + dx * width), (x + dy * width, y - dx * width),
                                   (x - dx * length, y - dy * length)], fill=(0, 0, 0, 110))
            art = Image.alpha_composite(art, lines)
        card = Image.new('RGBA', size)
        draw = ImageDraw.Draw(card)
        draw.polygon(outer, fill=motion['paperColor'])
        card.paste(art, (0, 0), mask)
        draw.line(inner + inner[:1], fill=motion['frameInk'], width=round(frame_style['inkPx'] * raster), joint='curve')
        card = card.resize((frame_style['cardWidth'] * scale, frame_style['cardHeight'] * scale), Image.Resampling.LANCZOS)
        card.save(root / panel['cardArt'], 'WEBP', quality=95, method=6)
        cards.append(card)
        checks.append({'panel': panel['number'], 'sourcePair': source_name, 'sourceCrop': list(crop),
                       'sourceArt': panel['art'], 'sourceSha256': hashlib.sha256((root / panel['art']).read_bytes()).hexdigest(),
                       'outline': frame_style['outlines'][slot], 'captionField': False})
    raw_page.save(root / page['art'], 'WEBP', quality=95, method=6)
    # Offline layout demonstration; the game also supports anywhere taps and idle progression.
    for index in range(4):
        board = base.convert('RGBA')
        for slot in range(index + 1):
            layout = motion['layout'][slot]
            board.alpha_composite(cards[slot], (round((layout['centerX'] - frame_style['cardWidth'] / 2) * scale),
                                               round((layout['centerY'] - frame_style['cardHeight'] / 2) * scale)))
        draw = ImageDraw.Draw(board)
        for action, box in story['controlLayout'].items():
            x, y = (box['x'] + box['width'] / 2) * scale, (box['y'] + box['height'] / 2) * scale
            label_x = x + (box['labelOffsetX'] * scale if action == 'next' else 0)
            draw.text((label_x, y), action, font=font, anchor='mm', fill='white', stroke_width=2, stroke_fill='#225D93')
            if action == 'next':
                icon = box['icon']
                cx, cy = x + icon['offsetX'] * scale, y + icon['offsetY'] * scale
                half = icon['size'] * scale / 2
                draw.polygon([(cx - half * 0.6, cy - half), (cx + half * 0.7, cy),
                              (cx - half * 0.6, cy + half)], fill='white', outline='#225D93', width=scale)
            if action == 'skip':
                half = draw.textlength(action, font=font) / 2
                draw.line((x - half, y + 28, x + half, y + 28), fill='white', width=2)
        frames.append(board.convert('RGB').resize((393, 852), Image.Resampling.LANCZOS))
    board.convert('RGB').save(output / f'page-{page_index:02d}-board.png')
    boards.append(board.convert('RGB'))

contact = Image.new('RGB', (1596, 1704), '#225D93')
for index, board in enumerate(boards):
    contact.paste(board, (index * 810, 0))
contact.save(output / 'two-page-board.jpg', quality=94)
palette = contact.resize((512, 512)).quantize(colors=192)
gif_frames = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
gif_frames[0].save(output / 'panel-preview.gif', save_all=True, append_images=gif_frames[1:], duration=800, loop=0, disposal=2, optimize=True)
assets = [root / panel['cardArt'] for page in story['pages'] for panel in page['panels']]
assets += [root / story['integration']['impactArt']]
manifest = []
for path in assets:
    with Image.open(path) as asset:
        dimensions = list(asset.size)
        asset.verify()
    manifest.append({'path': str(path.relative_to(root)), 'size': dimensions, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
(output / 'asset-check.json').write_text(json.dumps({'kind': 'offline-assets-only', 'panels': checks, 'assets': manifest,
    'artAreaRatio': round(4 * frame_style['cardWidth'] * frame_style['cardHeight'] / (393 * 852), 4)}, ensure_ascii=False, indent=2) + '\n')
all_assets = []
for path in sorted((root / 'src/assets').glob('story_cat_liquid_*')):
    if path.suffix not in ('.webp', '.png'):
        continue
    with Image.open(path) as asset:
        dimensions = list(asset.size)
        asset.verify()
    all_assets.append({'path': str(path.relative_to(root)), 'size': dimensions, 'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
(artifact_dir / 'asset-manifest.json').write_text(json.dumps({'version': 1, 'revision': story['revision'], 'assets': all_assets}, ensure_ascii=False, indent=2) + '\n')
print(f'WORDLESS COMIC: PASS — {len(checks)} measured cuts, larger phone panels, no caption fields, skip/next preview')
