"""Offline title proposals with newly generated WATER MEOW lettering."""
from pathlib import Path
from decimal import Decimal
import hashlib
import json
from PIL import Image,ImageDraw,ImageFont

out=Path(__file__).resolve().parent
root=out.parents[2]
brief=json.loads((out/'brief.json').read_text())
contract=json.loads((root/'web/ui/splash.contract.json').read_text())
font='/Library/Fonts/Managed/NanumGothicOTFBold_1589433817.otf'
heading=ImageFont.truetype(font,29)
small=ImageFont.truetype(font,20)
loading=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Bold.ttf',36)
contact=Image.new('RGB',(1236,775),'#e5eeec')
d=ImageDraw.Draw(contact)
d.text((24,18),'WATER MEOW · MORE TITLE SCENES',font=heading,fill='#173d41')
d.text((24,59),'마음에 드신 그림체 유지 · 박사가 등장하는 새 장면',font=small,fill='#496668')
usage=[]
manifest=[]
for i,concept in enumerate(brief['concepts']):
    slug=concept['slug']
    raw=Image.open(out/(slug+'-generated.png')).convert('RGB')
    assert raw.size==(1024,1536)
    # Preserve the generated 2:3 composition without stretching or clipping subjects.
    background=raw.resize((786,1179),Image.Resampling.LANCZOS)
    background.save(out/(slug+'-title.webp'),'WEBP',quality=95,method=6)
    preview=background.convert('RGBA')
    for layer in contract['layers']:
        if not layer['stableId'].startswith(('loading-out-','loading-inner-','loading-bar-')):
            continue
        v=layer['visual']
        art=Image.open(root/v['exportPath']).convert('RGBA').resize((round(v['width']*2),round(v['height']*2)),Image.Resampling.LANCZOS)
        if layer['stableId'].startswith('loading-bar-'):
            art=art.crop((0,0,round(art.width*.72),art.height))
        preview.alpha_composite(art,(round(layer['x']*2),round(layer['y']/852*1179)))
    ImageDraw.Draw(preview).text((393,round(758/852*1179)),'Loading... 72%',font=loading,anchor='mm',fill='white',stroke_width=4,stroke_fill='#30302f')
    preview.convert('RGB').save(out/(slug+'-preview.png'))
    x=24+i*404
    contact.paste(preview.convert('RGB').resize((393,590),Image.Resampling.LANCZOS),(x,110))
    d.text((x,720),chr(65+i)+'  '+concept['name'],font=heading,fill='#173d41')
    result=json.loads((out/(slug+'-generation.json')).read_text())
    usage.append({'slug':slug,**result})
    for suffix in ('-generated.png','-title.webp','-preview.png'):
        p=out/(slug+suffix)
        with Image.open(p) as im:
            dimensions=list(im.size);im.verify()
        manifest.append({'path':p.name,'dimensions':dimensions,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
contact.save(out/'comparison.jpg',quality=95)
total={k:sum(r['usage'][k] for r in usage) for k in ['input_text_tokens','input_image_tokens','output_image_tokens']}
total['estimated_cost_usd']=str(sum(Decimal(r['usage']['estimated_cost_usd']) for r in usage))
total['estimated_cost_krw']=str((Decimal(total['estimated_cost_usd'])*1400).quantize(Decimal('.01')))
(out/'usage-summary.json').write_text(json.dumps({'model':brief['model'],'route':'Sunburst skill scripts/generate_image.py via Flava','quality':brief['quality'],'requestCount':3,'requests':usage,'total':total},ensure_ascii=False,indent=2)+'\n')
(out/'asset-manifest.json').write_text(json.dumps({'scope':'offline title proposals only','assets':manifest},ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'comparison':str(out/'comparison.jpg'),'totalUsage':total},ensure_ascii=False))
