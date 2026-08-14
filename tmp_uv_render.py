import bpy
from pathlib import Path
from PIL import Image, ImageDraw

src = Path(r'D:/Strategy/water_yang/water_yang/obstacle_tile_1x1.blend')
out = Path(r'D:/Strategy/water_yang/water_yang/obstacle_uv_layout.png')
size = 1024

bpy.ops.wm.open_mainfile(filepath=str(src))
obj = bpy.data.objects.get('ObstacleTile_1x1')
mesh = obj.data
uv_layer = mesh.uv_layers.active.data
img = Image.new('RGBA', (size, size), (0, 0, 0, 255))
draw = ImageDraw.Draw(img)
for poly in mesh.polygons:
    pts = []
    for li in poly.loop_indices:
        uv = uv_layer[li].uv
        x = uv.x * (size - 1)
        y = (1.0 - uv.y) * (size - 1)
        pts.append((x, y))
    if len(pts) >= 2:
        draw.line(pts + [pts[0]], fill=(255, 255, 255, 255), width=1)
img.save(out)
print(out)
