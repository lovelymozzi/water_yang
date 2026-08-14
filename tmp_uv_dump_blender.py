import bpy, json
from pathlib import Path
src = Path(r'D:/Strategy/water_yang/water_yang/obstacle_tile_1x1.blend')
out = Path(r'D:/Strategy/water_yang/tmp_obstacle_uv.json')
bpy.ops.wm.open_mainfile(filepath=str(src))
obj = bpy.data.objects.get('ObstacleTile_1x1')
mesh = obj.data
uv_layer = mesh.uv_layers.active.data
polys = []
for poly in mesh.polygons:
    pts = []
    for li in poly.loop_indices:
        uv = uv_layer[li].uv
        pts.append([float(uv.x), float(uv.y)])
    polys.append(pts)
out.write_text(json.dumps(polys))
print(out)
