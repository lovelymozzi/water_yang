import bpy
import bmesh
from pathlib import Path

src = Path(r'D:/Strategy/water_yang/water_yang/obstacle_tile_1x1.blend')
out = Path(r'D:/Strategy/water_yang/tmp_uv_dump.txt')

bpy.ops.wm.open_mainfile(filepath=str(src))
obj = bpy.data.objects.get('ObstacleTile_1x1')
if obj is None:
    print('object missing')
else:
    mesh = obj.data
    uv = mesh.uv_layers.active
    print('mesh', mesh.name)
    print('polygons', len(mesh.polygons), 'loops', len(mesh.loops), 'uv layer', uv.name if uv else None)
    if uv:
        for poly in mesh.polygons[:20]:
            vals = []
            for li in poly.loop_indices:
                u, v = uv.data[li].uv
                vals.append((round(u,4), round(v,4)))
            print('poly', poly.index, vals)
