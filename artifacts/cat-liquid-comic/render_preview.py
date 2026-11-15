"""Extract generated comic rows, frame them, and render an offline SceneRenderer layout preview."""
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

artifact_dir = Path(__file__).resolve().parent
root = artifact_dir.parents[1]
story = json.loads((root / 'resources/story/cat-liquid-intro.json').read_text())
assert story['revision'] == 7 and story['textMode'] == 'bottom-typewriter'
output = artifact_dir / f'revision-{story["revision"]:02d}'
output.mkdir(exist_ok=True)
motion = story['motion']
frame_style = story['frame']
scale = 2
font_path = '/Library/Fonts/Managed/NanumGothicOTFBold_1589433817.otf'
body_font = ImageFont.truetype(font_path, story['dialogue']['fontSize'] * scale)
control_font = ImageFont.truetype(font_path, 24 * scale)
background = Image.open(root / story['background']['imagePath']).convert('RGB').resize((172, 172), Image.Resampling.LANCZOS)
base = Image.new('RGB', (786, 1704))
for y in range(0, base.height, background.height):
    for x in range(0, base.width, background.width):
        base.paste(background, (x, y))
boards = []
frames = []
checks = []
for page_index, page in enumerate(story['pages'], 1):
    source = Image.open(output / f'page-{page_index:02d}-generated.png').convert('RGB')
    assert source.size == (1024, 1536)
    source.save(root / page['art'], 'WEBP', quality=95, method=6)
    gutter_rows = [y for y in range(source.height)
                   if all(low >= 240 for low, high in source.crop((0, y, source.width, y + 1)).getextrema())]
    runs = []
    for y in gutter_rows:
        if not runs or y != runs[-1][-1] + 1:
            runs.append([y])
        else:
            runs[-1].append(y)
    runs = [run for run in runs if len(run) >= 4]
    assert len(runs) == 3, f'Expected 3 white gutters, found {runs}'
    crops = [(0, top, source.width, bottom) for top, bottom in
             zip([0] + [run[-1] + 1 for run in runs], [run[0] for run in runs] + [source.height])]
    cards = []
    for slot, panel in enumerate(page['panels']):
        source.crop(crops[slot]).save(root / panel['art'], 'WEBP', quality=95, method=6)
        # Work at four times display size; clip edges rather than skewing faces or bodies.
        raster = 4
        size = (frame_style['cardWidth'] * raster, frame_style['cardHeight'] * raster)
        picture = ImageOps.fit(Image.open(root / panel['art']).convert('RGBA'),
                               (size[0], motion['imageHeight'] * raster), Image.Resampling.LANCZOS,
                               centering=(0 if panel['number'] == 2 else 0.5, 0.5))
        art = Image.new('RGBA', size)
        art.paste(picture, (0, (size[1] - picture.height) // 2))
        outer = [(x * raster, y * raster) for x, y in frame_style['outlines'][slot]]
        rim = frame_style['rimPx'] * raster
        inner = [(x + (rim if x < size[0] / 2 else -rim),
                  y + (rim if y < size[1] / 2 else -rim)) for x, y in outer]
        mask = Image.new('L', size)
        ImageDraw.Draw(mask).polygon(inner, fill=255)
        if panel['number'] in frame_style['speedLinePanels']:
            # Short tapered lines stay at the edges; the professor and portal remain readable.
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
        card = card.resize((744, 290), Image.Resampling.LANCZOS)
        card.save(root / panel['cardArt'], 'WEBP', quality=95, method=6)
        cards.append(card)
        box = draw.multiline_textbbox((0, 0), panel['caption'], font=body_font, spacing=7, align='center')
        assert box[2] - box[0] <= (story['dialogue']['width'] - 16) * scale, f'Caption width: {panel["number"]}'
        assert box[3] - box[1] < (story['dialogue']['height'] - 16) * scale
        checks.append({'panel': panel['number'], 'sourceArt': panel['art'],
                       'sourceCrop': list(crops[slot]),
                       'sourceSha256': hashlib.sha256((root / panel['art']).read_bytes()).hexdigest(),
                       'outline': frame_style['outlines'][slot], 'caption': panel['caption'], 'fits': True})
    # The offline GIF demonstrates typing; the game advances only when next is clicked.
    for index, panel in enumerate(page['panels']):
        samples = [0, len(panel['caption']) // 3, len(panel['caption']) * 2 // 3, len(panel['caption']), len(panel['caption'])]
        for sample in samples:
            board = base.convert('RGBA')
            for slot in range(index + 1):
                layout = motion['layout'][slot]
                board.alpha_composite(cards[slot], (21, round((layout['centerY'] - 72.5) * scale)))
            draw = ImageDraw.Draw(board)
            draw.rectangle((32, 1400, 754, 1600), fill='white', outline=motion['frameInk'], width=4)
            text = panel['caption'][:sample]
            box = draw.multiline_textbbox((0, 0), text, font=body_font, spacing=7, align='center')
            draw.multiline_text(((786 - box[2] - box[0]) / 2, 1500 - (box[3] + box[1]) / 2), text,
                                font=body_font, spacing=7, align='center', fill=motion['frameInk'])
            draw.text((664, 1652), 'next', font=control_font, anchor='mm', fill='white', stroke_width=2, stroke_fill='#225D93')
            frames.append(board.convert('RGB').resize((393, 852), Image.Resampling.LANCZOS))
    board.convert('RGB').save(output / f'page-{page_index:02d}-board.png')
    boards.append(board.convert('RGB'))

contact = Image.new('RGB', (1596, 1704), '#225D93')
for index, board in enumerate(boards):
    contact.paste(board, (index * 810, 0))
contact.save(output / 'two-page-board.jpg', quality=94)
palette = contact.resize((512, 512)).quantize(colors=192)
gif_frames = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
gif_frames[0].save(output / 'typewriter-preview.gif', save_all=True, append_images=gif_frames[1:], duration=300, loop=0, disposal=2, optimize=True)
impact = Image.new('RGBA', (792, 338))
draw = ImageDraw.Draw(impact)
for degrees in range(0, 360, 45):
    theta = math.radians(degrees)
    x = (198 + math.cos(theta) * 188) * scale
    y = (84.5 + math.sin(theta) * 74.5) * scale
    draw.line((x, y, x + math.cos(theta) * 18, y + math.sin(theta) * 18), fill=motion['frameInk'], width=4)
impact.save(root / story['integration']['impactArt'])
assets = [root / panel['cardArt'] for page in story['pages'] for panel in page['panels']]
assets += [root / story['integration']['impactArt']]
manifest = []
for path in assets:
    with Image.open(path) as asset:
        dimensions = list(asset.size)
        asset.verify()
    manifest.append({'path': str(path.relative_to(root)), 'size': dimensions, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
(output / 'asset-check.json').write_text(json.dumps({'kind': 'offline-assets-only', 'panels': checks, 'assets': manifest}, ensure_ascii=False, indent=2) + '\n')
all_assets = []
for path in sorted((root / 'src/assets').glob('story_cat_liquid_*')):
    if path.suffix not in ('.webp', '.png'):
        continue
    with Image.open(path) as asset:
        dimensions = list(asset.size)
        asset.verify()
    all_assets.append({'path': str(path.relative_to(root)), 'size': dimensions, 'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
(artifact_dir / 'asset-manifest.json').write_text(json.dumps({'version': 1, 'revision': story['revision'], 'assets': all_assets}, ensure_ascii=False, indent=2) + '\n')
print(f'COMIC FRAMES: PASS — {len(checks)} measured landscape cuts, clipped ink frames, monologue bounds, offline typing preview')
