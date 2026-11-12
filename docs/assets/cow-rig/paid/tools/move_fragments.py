# 把拆图时误留在头层、飘带层的游离碎片挪回所属的层 (头层 → 金币层，飘带层 → 身体层)，
# 这样转动时不会有一截描边跟着飞。读 out/，写 clean/。
import json, sys
import numpy as np, cv2
from PIL import Image
from pathlib import Path
root = Path(sys.argv[1]); out = root / 'out'; clean = root / 'clean'
(clean / 'scaled').mkdir(parents=True, exist_ok=True)
rig = json.loads((out / 'rig.json').read_text())
layers = {l['name']: np.array(Image.open(out / l['file']).convert('RGBA')) for l in rig['layers']}

def over(dst, frag):
    """premultiplied alpha 叠加 frag 到 dst 上 (frag 在上)。"""
    fa = frag[..., 3:4] / 255.0; da = dst[..., 3:4] / 255.0
    oa = fa + da * (1 - fa)
    rgb = (frag[..., :3] * fa + dst[..., :3] * da * (1 - fa)) / np.maximum(oa, 1e-6)
    return np.concatenate([rgb, oa * 255], axis=2).round().clip(0, 255).astype(np.uint8)

for source, target in [('head', 'coins'), ('tieFlap', 'body')]:
    a = layers[source]
    n, lab, st, _ = cv2.connectedComponentsWithStats((a[..., 3] > 0).astype(np.uint8), 8)
    main = 1 + np.argmax(st[1:, 4])
    mask = (lab != main) & (lab != 0)
    frag = np.where(mask[..., None], a, 0).astype(np.uint8)
    layers[source] = np.where(mask[..., None], 0, a).astype(np.uint8)
    # 源层在目标层之上时碎片盖在上面，反之垫在下面，保证静止时叠出来不变。
    z = {l['name']: l['z'] for l in rig['layers']}
    layers[target] = over(layers[target], frag) if z[source] > z[target] else over(frag, layers[target])
    print(source, '->', target, int(mask.sum()), 'px')

for name, a in layers.items():
    im = Image.fromarray(a); im.save(clean / f'{name}.png')
    im.resize((240, 320), Image.LANCZOS).save(clean / 'scaled' / f'{name}@2x.png')
    im.resize((120, 160), Image.LANCZOS).save(clean / 'scaled' / f'{name}.png')

src = np.array(Image.open(rig['source']).convert('RGBA')).astype(int)
base = Image.new('RGBA', src.shape[1::-1], (0, 0, 0, 0))
for l in sorted(rig['layers'], key=lambda l: l['z']):
    base = Image.alpha_composite(base, Image.open(clean / f"{l['name']}.png"))
d = np.abs(np.array(base).astype(int) - src)
print('composite max', d.max(), 'mean', round(d.mean(), 4), 'pixels>16', int((d.max(axis=2) > 16).sum()))
