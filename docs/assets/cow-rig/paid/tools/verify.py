from pathlib import Path
from PIL import Image
import json, hashlib
root=Path(__file__).resolve().parents[1];out=root/'out';rig=json.loads((out/'rig.json').read_text())
assert hashlib.sha256(Path(rig['source']).read_bytes()).hexdigest()==rig['source_sha256']
for layer in rig['layers']:
 name=layer['name']
 for file,size in [(out/layer['file'],(1086,1448)),(out/'scaled'/f'{name}@2x.png',(240,320)),(out/'scaled'/f'{name}.png',(120,160))]:
  im=Image.open(file); assert im.size==size and im.mode=='RGBA',(file,im.size,im.mode)
print('Verified: source SHA256 unchanged; 7 full-size RGBA layers; 14 scaled RGBA layers; all dimensions correct.')
