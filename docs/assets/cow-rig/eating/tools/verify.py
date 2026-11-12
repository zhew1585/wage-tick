from pathlib import Path
from PIL import Image
import numpy as np,cv2,json,hashlib
R=Path(__file__).resolve().parents[1]
for pose in ['yawning','eating','sunbathing']:
 out=R/'out'/pose;rig=json.loads((out/'rig.json').read_text());report=json.loads((out/'verification.json').read_text());a=np.array(Image.open(out/'source-fixed.png'));owner=np.array(Image.open(out/'ownership.png'));comp=Image.new('RGBA',(1086,1448))
 assert hashlib.sha256(Path(rig['source']).read_bytes()).hexdigest()==rig['source_sha256']
 assert np.array_equal(owner>0,a[:,:,3]>0)
 for i,e in enumerate(rig['layers'],1):
  im=Image.open(out/e['file']);b=np.array(im);assert im.mode=='RGBA' and im.size==(1086,1448);assert np.array_equal(b[owner==i],a[owner==i]);comp.alpha_composite(im)
  for suffix,size in [('@2x',(240,320)),('',(120,160))]:assert Image.open(out/'scaled'/f'{e["name"]}{suffix}.png').size==size
 diff=np.abs(np.array(comp).astype(int)-a.astype(int));metrics=dict(rgba_max=int(diff.max()),rgba_mean=float(diff.mean()),differing_pixels=int(np.any(diff,axis=2).sum()));assert metrics==rig['composite_error'];assert diff.max()<=2
 if pose=='eating':
  head=np.array(Image.open(out/'head.png'));blink=np.array(Image.open(out/'headBlink.png'));assert np.array_equal(head[:,:,3],blink[:,:,3]);changed=np.any(head!=blink,axis=2);yy,xx=np.where(changed);assert yy.min()>=386 and yy.max()<=455;report['blink_changed_pixels']=int(changed.sum());report['blink_alpha_matches']=True
 report['independent_disk_verification_pass']=True;report['composite_error']=metrics
 (out/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(pose,metrics)
