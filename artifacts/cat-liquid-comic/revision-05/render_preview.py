"""Extract wide comic strips and render an offline preview; the game uses SceneRenderer."""
import hashlib
import json
import math
from decimal import Decimal
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageOps

output = Path(__file__).resolve().parent
root = output.parents[2]
story = json.loads((root / 'resources/story/cat-liquid-intro.json').read_text())
assert story['revision'] == 5 and story['textMode'] == 'bottom-typewriter'
motion = story['motion']
scale = 2
font_path = '/Library/Fonts/Managed/NanumGothicOTFBold_1589433817.otf'
body_font = ImageFont.truetype(font_path, story['dialogue']['fontSize'] * scale)
hint_font = ImageFont.truetype(font_path, story['dialogue']['hintFontSize'] * scale)
control_font = ImageFont.truetype(font_path, 24 * scale)
background = Image.open(root / story['background']['imagePath']).convert('RGB').resize((172, 172), Image.Resampling.LANCZOS)
base = Image.new('RGB', (786, 1704))
for y in range(0, base.height, background.height):
    for x in range(0, base.width, background.width):
        base.paste(background, (x, y))
boards = []
frames = []
checks = []
generation = []
for page_index, page in enumerate(story['pages'], 1):
    source = Image.open(output / f'page-{page_index:02d}-generated.png').convert('RGB')
    assert source.size == (1024, 1536)
    source.save(root / page['art'], 'WEBP', quality=95, method=6)
    # Measure generated white gutters instead of assuming the model obeyed their exact coordinates.
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
    for slot, (panel, crop) in enumerate(zip(page['panels'], crops)):
        art = source.crop(crop)
        art.save(root / panel['art'], 'WEBP', quality=95, method=6)
        art = ImageOps.fit(art, (720, 264), Image.Resampling.LANCZOS)
        card = Image.new('RGBA', (744, 290))
        draw = ImageDraw.Draw(card)
        draw.rectangle((6, 8, 738, 284), fill=(83, 44, 30, 42))
        draw.rectangle((0, 0, 731, 275), fill='white')
        card.paste(art, (6, 6))
        draw.rectangle((0, 0, 731, 275), outline=motion['frameInk'], width=4)
        card.save(root / panel['cardArt'], 'WEBP', quality=95, method=6)
        cards.append(card)
        box = draw.multiline_textbbox((0, 0), panel['caption'], font=body_font, spacing=7, align='center')
        assert box[2] - box[0] <= (story['dialogue']['width'] - 16) * scale, f'Caption width: {panel["number"]}'
        assert box[3] - box[1] < 70 * scale
        checks.append({'panel': panel['number'], 'sourceCrop': list(crop), 'caption': panel['caption'], 'fits': True})
    # Auto advances below only demonstrate typing. The game waits for a touch after every line.
    for index, panel in enumerate(page['panels']):
        samples = list(range(0, len(panel['caption']), 4)) + [len(panel['caption'])] * 3
        for sample in samples:
            board = base.convert('RGBA')
            for slot in range(index + 1):
                layout = motion['layout'][slot]
                board.alpha_composite(cards[slot], (21, round((layout['centerY'] - 72.5) * scale)))
            draw = ImageDraw.Draw(board)
            draw.rounded_rectangle((32, 1400, 754, 1600), radius=20, fill='white', outline=motion['frameInk'], width=4)
            text = panel['caption'][:sample]
            box = draw.multiline_textbbox((0, 0), text, font=body_font, spacing=7, align='center')
            draw.multiline_text(((786 - box[2] - box[0]) / 2, 1490 - (box[3] + box[1]) / 2), text,
                                font=body_font, spacing=7, align='center', fill=motion['frameInk'])
            done = sample == len(panel['caption'])
            hint = ('next를 눌러 계속' if index == 3 else '터치해서 다음 장면') if done else '터치하면 대사가 모두 표시됩니다'
            draw.text((393, 1572), hint, font=hint_font, anchor='mm', fill='#396FA9')
            draw.text((688, 84), 'skip', font=control_font, anchor='mm', fill='white', stroke_width=2, stroke_fill='#225D93')
            draw.line((650, 110, 726, 110), fill='white', width=2)
            if index == 3 and done:
                draw.text((664, 1652), 'next', font=control_font, anchor='mm', fill='white', stroke_width=2, stroke_fill='#225D93')
            frames.append(board.convert('RGB').resize((393, 852), Image.Resampling.LANCZOS))
    board.convert('RGB').save(output / f'page-{page_index:02d}-board.png')
    boards.append(board.convert('RGB'))
    generation.append(json.loads((output / f'page-{page_index:02d}-generation.json').read_text()))

contact = Image.new('RGB', (1596, 1704), '#225D93')
for index, board in enumerate(boards):
    contact.paste(board, (index * 810, 0))
contact.save(output / 'two-page-board.jpg', quality=94)
palette = contact.resize((512, 512)).quantize(colors=192)
gif_frames = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
gif_frames[0].save(output / 'typewriter-preview.gif', save_all=True, append_images=gif_frames[1:], duration=152, loop=0, disposal=2, optimize=True)
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
usd = sum(Decimal(item['usage']['estimated_cost_usd']) for item in generation)
(output / 'generation.json').write_text(json.dumps({'model': 'gpt-image-2.5-sunburst', 'route': 'Sunburst skill generate_image.py through Flava', 'pages': generation,
    'total': {'input_text_tokens': sum(item['usage']['input_text_tokens'] for item in generation), 'input_image_tokens': sum(item['usage']['input_image_tokens'] for item in generation), 'output_image_tokens': sum(item['usage']['output_image_tokens'] for item in generation),
              'estimated_cost_usd': str(usd), 'estimated_cost_krw': str((usd * 1400).quantize(Decimal('0.01')))}}, ensure_ascii=False, indent=2) + '\n')
(output / 'asset-check.json').write_text(json.dumps({'kind': 'offline-assets-only', 'panels': checks, 'assets': manifest}, ensure_ascii=False, indent=2) + '\n')
all_assets = []
for path in sorted((root / 'src/assets').glob('story_cat_liquid_*')):
    if path.suffix not in ('.webp', '.png'):
        continue
    with Image.open(path) as asset:
        dimensions = list(asset.size)
        asset.verify()
    all_assets.append({'path': str(path.relative_to(root)), 'size': dimensions, 'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
(output.parent / 'asset-manifest.json').write_text(json.dumps({'version': 1, 'revision': 5, 'assets': all_assets}, ensure_ascii=False, indent=2) + '\n')
print(f'WIDE COMIC: PASS — {len(checks)} landscape cuts and dialogues, measured gutters, shop background, offline typing preview')
