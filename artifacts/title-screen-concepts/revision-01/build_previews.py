"""Offline art comparison using the current published logo/loading art; changes no game files."""
from pathlib import Path
from decimal import Decimal
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont, ImageOps

out=Path(__file__).resolve().parent
root=out.parents[2]
brief=json.loads((out/'brief.json').read_text())
contract=json.loads((root/'web/ui/splash.contract.json').read_text())
scale=2
canvas=(393*scale,852*scale)
font_path='/Library/Fonts/Managed/NanumGothicOTFBold_1589433817.otf'
label_font=ImageFont.truetype(font_path,29)
desc_font=ImageFont.truetype(font_path,19)
loading_font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Bold.ttf',18*scale)
contact=Image.new('RGB',(1236,1040),'#e5eeec')
draw=ImageDraw.Draw(contact)
draw.text((24,18),'WATER MEOW · TITLE CONCEPTS',font=label_font,fill='#173d41')
draw.text((24,59),'현재 로고·로딩바를 얹은 배경 시안 / 게임 반영 전',font=desc_font,fill='#496668')
all_usage=[]
manifest=[]
for i,concept in enumerate(brief['concepts']):
    slug=concept['slug']
    generated=Image.open(out/(slug+'-generated.png')).convert('RGB')
    assert generated.size==(1024,1536)
    # Keep every character's full width and undistorted middle band.
    # Extend only the quiet environmental bands to the phone's tall aspect ratio.
    phone_art=Image.new('RGB',(1024,2220))
    phone_art.paste(generated.crop((0,0,1024,450)).resize((1024,850),Image.Resampling.LANCZOS),(0,0))
    phone_art.paste(generated.crop((0,450,1024,1250)),(0,850))
    phone_art.paste(generated.crop((0,1250,1024,1536)).resize((1024,570),Image.Resampling.LANCZOS),(0,1650))
    assert phone_art.crop((0,850,1024,1650)).tobytes()==generated.crop((0,450,1024,1250)).tobytes()
    background=phone_art.resize(canvas,Image.Resampling.LANCZOS)
    background.save(out/(slug+'-background.webp'),'WEBP',quality=95,method=6)
    preview=Image.new('RGBA',canvas)
    for layer in sorted(contract['layers'],key=lambda layer:layer.get('zIndex',0)):
        sid=layer['stableId']
        if sid=='title-bg-png-2287':
            visual=layer['visual']; s=layer.get('scale') or 1
            art=background.convert('RGBA').resize((round(visual['width']*s*scale),round(visual['height']*s*scale)),Image.Resampling.LANCZOS)
        elif sid=='title-text-png-2286' or sid.startswith(('loading-out-','loading-inner-','loading-bar-')):
            visual=layer['visual']; s=layer.get('scale') or 1
            art=Image.open(root/visual['exportPath']).convert('RGBA').resize((round(visual['width']*s*scale),round(visual['height']*s*scale)),Image.Resampling.LANCZOS)
            if sid.startswith('loading-bar-'):
                art=art.crop((0,0,round(art.width*0.72),art.height))
        else:
            continue
        preview.alpha_composite(art,(round(layer['x']*scale),round(layer['y']*scale)))
    # Static illustration of the existing loadingMessage; not a live renderer capture.
    d=ImageDraw.Draw(preview)
    d.text((196.5*scale,758*scale),'Loading... 72%',font=loading_font,anchor='mm',fill='white',stroke_width=2*scale,stroke_fill='#30302f')
    preview.convert('RGB').save(out/(slug+'-preview.png'))
    x=24+i*404
    draw.rounded_rectangle((x-3,108,x+396,963),radius=17,fill='#253f42')
    contact.paste(preview.convert('RGB').resize((393,852),Image.Resampling.LANCZOS),(x,110))
    draw.text((x,980),chr(65+i)+'  '+concept['name'],font=label_font,fill='#173d41')
    generation=json.loads((out/(slug+'-generation.json')).read_text())
    all_usage.append({'slug':slug,**generation})
    for suffix in ('-generated.png','-background.webp','-preview.png'):
        p=out/(slug+suffix)
        with Image.open(p) as im:
            dimensions=list(im.size); im.verify()
        manifest.append({'path':p.name,'dimensions':dimensions,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
contact.save(out/'comparison.jpg',quality=95)
usage={'input_text_tokens':sum(item['usage']['input_text_tokens'] for item in all_usage),'input_image_tokens':sum(item['usage']['input_image_tokens'] for item in all_usage),'output_image_tokens':sum(item['usage']['output_image_tokens'] for item in all_usage),'estimated_cost_usd':str(sum(Decimal(item['usage']['estimated_cost_usd']) for item in all_usage))}
usage['estimated_cost_krw']=str((Decimal(usage['estimated_cost_usd'])*1400).quantize(Decimal('0.01')))
(out/'usage-summary.json').write_text(json.dumps({'model':brief['model'],'route':'Sunburst skill scripts/generate_image.py via Flava','quality':brief['quality'],'requestCount':3,'requests':all_usage,'total':usage},ensure_ascii=False,indent=2)+'\n')
(out/'asset-manifest.json').write_text(json.dumps({'scope':'offline concepts only','assets':manifest},ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'comparison':str(out/'comparison.jpg'),'totalUsage':usage},ensure_ascii=False))
