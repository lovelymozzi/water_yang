"""Compare captured Godot property values with the original Unity animation.

Run tests/hole_check.tscn -- --fx-stage1-capture first (Godot 4.7.2).
Ruby/Psych reads the original YAML; no third-party Python packages are used.
"""
import bisect
import hashlib
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
source = root / 'effect/fx_char_levelup_01_b328fc5d-bbc6-524f-9ba8-49d6d94338d4/source-resources'
animation = source / 'Assets/Art/Effect/animation/battle/common/fx_char_levelup_01.anim'
ruby = 's=File.read(ARGV[0]).lines.reject { |l| l.start_with?("%", "---") }.join; print JSON.generate(YAML.safe_load(s))'
clip = json.loads(subprocess.check_output(['ruby', '-ryaml', '-rjson', '-e', ruby, str(animation)]))['AnimationClip']
samples = json.loads(Path('/tmp/water-yang-fx-runtime-values.json').read_text())
curves = []
for group, prop in [('m_PositionCurves', 'position'), ('m_ScaleCurves', 'scale')]:
    for item in clip[group]:
        curves.append((item['path'] + ':' + prop, item['curve']['m_Curve'], 'xyz'))
for item in clip['m_FloatCurves']:
    prop = {'m_Color.a': 'opacity', 'm_Size.y': 'draw_height'}[item['attribute']]
    curves.append((item['path'] + '/Visual:material_override:shader_parameter/' + prop, item['curve']['m_Curve'], [None]))
assert len(curves) == 23 and len(samples) == 73
worst = 0.0
comparisons = 0
for sample in samples:
    assert len(sample['values']) == 24
    for path, keys, components in curves:
        time = sample['time'] % clip['m_AnimationClipSettings']['m_StopTime']
        index = max(0, bisect.bisect_right([k['time'] for k in keys], time) - 1)
        a, b = keys[index], keys[min(index + 1, len(keys) - 1)]
        actual = sample['values'][path]
        actual = actual if isinstance(actual, list) else [actual]
        for slot, component in enumerate(components):
            av = a['value'][component] if component else a['value']
            bv = b['value'][component] if component else b['value']
            expected = av
            if keys[0]['time'] < time < keys[-1]['time'] and a is not b:
                assert a.get('weightedMode', 0) == b.get('weightedMode', 0) == 0
                dt = b['time'] - a['time']
                u = (time - a['time']) / dt
                out_slope = a['outSlope'][component] if component else a['outSlope']
                in_slope = b['inSlope'][component] if component else b['inSlope']
                expected = (2*u**3 - 3*u*u + 1)*av + (u**3 - 2*u*u + u)*dt*out_slope + (-2*u**3 + 3*u*u)*bv + (u**3 - u*u)*dt*in_slope
            error = abs(expected - actual[slot])
            assert error < 0.00002, (path, time, expected, actual[slot], error)
            worst = max(worst, error)
            comparisons += 1

metas = {}
for meta_path in source.rglob('*.png.meta'):
    meta = json.loads(subprocess.check_output(['ruby', '-ryaml', '-rjson', '-e', ruby, str(meta_path)]))
    metas[meta['guid']] = meta
    image_path = meta_path.with_suffix('')
    assert hashlib.sha256(image_path.read_bytes()).digest() == hashlib.sha256((root / 'water_yang/portal_levelup' / image_path.name).read_bytes()).digest()
for item in clip['m_PPtrCurves']:
    for sample in samples:
        time = sample['time'] % clip['m_AnimationClipSettings']['m_StopTime']
        key = item['curve'][max(0, bisect.bisect_right([k['time'] for k in item['curve']], time + 0.00000001) - 1)]
        sprite = next(s for s in metas[key['value']['guid']]['TextureImporter']['spriteSheet']['sprites'] if s['internalID'] == key['value']['fileID'])
        r = sprite['rect']
        expected = [r['x']/256, (256-r['y']-r['height'])/256, r['width']/256, r['height']/256]
        actual = sample['values'][item['path'] + '/Visual:material_override:shader_parameter/source_rect']
        assert max(abs(a-b) for a,b in zip(actual, expected)) < 0.000001, (sample['time'], actual, expected)
        comparisons += 4
print(f'PASS: original 24 tracks × 73 times; {comparisons} scalar comparisons, max error {worst:.9f}; 7 original texture hashes match')
print('This checks source values, not Unity/Godot rendered equivalence or random particle equivalence.')
