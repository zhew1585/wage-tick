from pathlib import Path
from PIL import Image, ImageDraw
import numpy as np, cv2, aggdraw, json, hashlib
ROOT=Path(__file__).resolve().parents[1]; W,H=1086,1448
SRCROOT=Path('/Users/weizhe/.pencil/documents/5498c176-4755-4b2f-b351-c6533167e9f2/images')
DARK='#352214';WHITE='#fffdfb'
def shape(cmd,fill=WHITE,stroke=None,width=15):
 im=Image.new('RGBA',(W,H));d=aggdraw.Draw(im);p=aggdraw.Path()
 for op,pts in cmd:getattr(p,op)(*pts)
 d.path(p,aggdraw.Brush(fill) if fill else None,aggdraw.Pen(stroke,width) if stroke else None);d.flush();return im
def poly(pts):
 im=Image.new('L',(W,H));ImageDraw.Draw(im).polygon(pts,fill=255);return np.array(im)>0
def pathmask(cmd):return np.array(shape(cmd,'white'))[:,:,3]>127
def cc(mask):return cv2.connectedComponentsWithStats(mask.astype('uint8'),8)
def build(pose):
 srcpath=SRCROOT/f'cow-{pose}.png';src=Image.open(srcpath).convert('RGBA');a=np.array(src);visible=a[:,:,3]>0;yy,xx=np.indices((H,W))
 out=ROOT/'out'/pose;(out/'scaled').mkdir(parents=True,exist_ok=True)
 # Guide follows the lower EXTERIOR ink of the head, shared collar ink excluded.
 if pose=='work':
  guide=[(240,520),(245,550),(260,590),(280,621),(300,645),(325,666),(350,681),(375,691),(400,697),(450,705),(500,710),(550,711),(600,708),(650,700),(700,682),(750,650),(780,615),(800,570),(813,520)]
 else:
  guide=[(231,530),(234,570),(245,600),(270,645),(300,681),(350,719),(400,746),(430,756),(450,762),(480,775),(510,776),(540,766),(570,755),(600,750),(650,736),(700,718),(750,685),(800,637),(825,590),(841,530)]
 ink=(a[:,:,0]<105)&(a[:,:,1]<85)&(a[:,:,3]>200)
 edge=[]
 for x in range(guide[0][0],guide[-1][0]+1):
  expected=int(np.interp(x,*np.array(guide).T));lo=expected-15;hi=expected+16
  ys=np.where(ink[lo:hi,x])[0]+lo
  if len(ys):
   runs=np.split(ys,np.where(np.diff(ys)>1)[0]+1);run=min(runs,key=lambda r:abs(r[-1]-expected));y=int(run[-1])
  else:y=expected
  edge.append((x,y))
 # Fit the uninterrupted head silhouette through reliable, unshared contour samples.
 reliable=[]
 for x,y in edge:
  expected=int(np.interp(x,*np.array(guide).T));lo=expected-24;hi=expected+24
  ys=np.where(ink[lo:hi,x])[0]+lo
  if len(ys):
   runs=np.split(ys,np.where(np.diff(ys)>1)[0]+1);r=min(runs,key=lambda r:abs(r[-1]-expected))
   if len(r)<25 and abs(r[-1]-expected)<12:reliable.append((x,int(r[-1])))
 pts=np.array(reliable);coef=np.polyfit((pts[:,0]-540)/300,pts[:,1],8)
 edge=[(x,int(round(np.polyval(coef,(x-540)/300)))) for x,y in edge]
 hm=poly([(0,0),(W,0),(W,500),(guide[-1][0]+3,500)]+edge[::-1]+[(guide[0][0]-3,500),(0,500)])
 if pose=='work':
  lm=poly([(397,677),(460,730),(462,790),(452,856),(410,980),(416,1012),(414,1045),(402,1068),(380,1078),(356,1063),(333,1076),(306,1069),(285,1085),(280,850),(315,755)])&~hm
  rm=poly([(619,690),(700,730),(950,730),(950,970),(661,950),(636,865),(613,772)])&~hm
  tm=poly([(210,1020),(312,1035),(348,1080),(355,1075),(360,1179),(210,1190)])
  piv={'tail':(361,1127),'body':(535,1000),'armLeft':(413,746),'armRight':(639,749),'head':(542,690)}
  # Continuous torso behind the head and movable sleeves.
  torso=[('moveto',(402,671)),('curveto',(460,648,565,648,619,675)),('curveto',(649,744,645,860,666,984)),('curveto',(571,1029,461,1008,397,980)),('curveto',(420,871,425,761,402,671)),('close',())]
  caps={'armLeft':[('moveto',(391,679)),('curveto',(418,675,451,700,458,737)),('lineto',(451,801)),('lineto',(371,814)),('lineto',(345,747)),('close',())],
        'armRight':[('moveto',(613,678)),('curveto',(643,682,661,713,669,750)),('lineto',(683,801)),('lineto',(641,818)),('lineto',(610,748)),('close',())]}
 else:
  lm=poly([(400,735),(429,754),(430,798),(428,881),(408,941),(278,973),(270,727)])&~hm
  rm=pathmask([('moveto',(649,711)),('lineto',(709,705)),('lineto',(800,792)),('lineto',(800,888)),('curveto',(771,965,733,994,681,974)),('curveto',(624,956,580,900,554,855)),('lineto',(542,821)),('lineto',(555,772)),('lineto',(610,767)),('close',())])&~hm
  tm=poly([(749,1008),(796,1019),(830,965),(885,916),(948,1003),(925,1100),(797,1126),(757,1101)])
  piv={'tail':(771,1065),'body':(534,1023),'armLeft':(414,787),'armRight':(662,786),'head':(531,746)}
  torso=[('moveto',(425,718)),('curveto',(478,680,603,683,658,716)),('curveto',(688,790,701,922,761,1022)),('curveto',(691,1058,610,1079,550,1074)),('lineto',(534,1064)),('lineto',(521,1072)),('curveto',(468,1065,429,1046,402,1017)),('curveto',(432,915,437,803,425,718)),('close',())]
  caps={'armLeft':[('moveto',(412,734)),('curveto',(440,732,457,759,447,796)),('lineto',(427,861)),('lineto',(364,858)),('lineto',(348,781)),('close',())],
        'armRight':[('moveto',(643,715)),('curveto',(668,704,692,723,711,757)),('lineto',(740,827)),('lineto',(672,874)),('lineto',(613,809)),('close',())]}
 # Every visible source sample belongs to exactly one part.
 if pose=='work':
  tm &= xx < np.interp(yy,[1020,1080,1130,1190],[337,343,350,357])
 else:
  tm &= xx > np.interp(yy,[1008,1050,1100,1140],[752,768,788,806])
  lower=np.array([(542,849),(560,877),(570,884),(580,892),(590,907),(600,920),(610,931),(620,940),(630,948),(640,956),(650,962),(660,967),(670,971),(680,973),(690,975),(700,974),(710,972),(720,969),(730,964),(740,956),(750,943),(760,914),(770,856),(800,850)])
  cut=np.interp(xx,*lower.T)
  rm &= (yy <= cut) | ((yy<=cut+5)&(a[:,:,0]<140))
 masks={};remaining=visible.copy()
 for n,m in [('head',hm),('armLeft',lm),('armRight',rm),('tail',tm)]:masks[n]=remaining&m;remaining&=~m
 masks['body']=remaining
 # Rehome every disconnected sample to the nearest anatomically plausible main part.
 moves=[]
 # Use the main opaque anatomy for distances; intrinsic alpha-1 source dust stays with its nearest part.
 mains={}
 for n,m in masks.items():
  num,lab,st,_=cc(m&(a[:,:,3]>32));main=1+int(np.argmax(st[1:,4]));mains[n]=lab==main
 dist={n:cv2.distanceTransform((~m).astype('uint8'),cv2.DIST_L2,5) for n,m in mains.items()}
 # All non-main components are audited, including alpha-only noise, but may belong to their present layer.
 for n in list(masks):
  num,lab,st,_=cc(masks[n]);main=1+int(np.argmax(st[1:,4]))
  for i in range(1,num):
   if i==main:continue
   m=lab==i;target=min(masks,key=lambda k:float(dist[k][m].min()))
   if target!=n:
    masks[n][m]=False;masks[target][m]=True;moves.append({'from':n,'to':target,'pixels':int(m.sum()),'bbox':st[i,:4].tolist(),'max_alpha':int(a[:,:,3][m].max())})
 ownership=np.zeros((H,W),np.uint8)
 for i,n in enumerate(['tail','body','armLeft','armRight','head'],1):ownership[masks[n]]=i
 Image.fromarray(ownership).save(out/'ownership.png')
 layers={}
 for n,m in masks.items():b=a.copy();b[~m]=0;layers[n]=Image.fromarray(b)
 # Backfill only behind near-opaque foreground samples, preserving the original outer AA.
 order=['tail','body','armLeft','armRight','head']
 def hidden(n,paint):
  i=order.index(n);oc=np.zeros((H,W),bool)
  for above in order[i+1:]:oc|=masks[above]&(a[:,:,3]>=253)
  b=np.array(paint);b[~oc]=0;layers[n]=Image.alpha_composite(Image.fromarray(b),layers[n])
 hidden('body',shape(torso,WHITE,DARK,16))
 if pose=='work':
  pants=[('moveto',(354,980)),('curveto',(385,988,413,998,430,1003)),('lineto',(430,1099)),('lineto',(359,1100)),('curveto',(355,1065,350,1025,354,980)),('close',())]
  color=tuple(int(v) for v in a[1040,430,:3]);paint=shape(pants,color)
  paint.alpha_composite(shape([('moveto',(350,980)),('curveto',(348,1020,353,1070,358,1100))],None,DARK,16))
  hidden('body',paint)

 # Rounded roots underneath the head. Source pixels remain above all added paint.
 for n,cmd in caps.items():hidden(n,shape(cmd,WHITE,DARK,16))
 if pose=='work':root=[('moveto',(338,1111)),('curveto',(359,1093,386,1095,390,1121)),('curveto',(391,1143,367,1155,343,1150)),('close',())]
 else:root=[('moveto',(747,1036)),('curveto',(775,1034,796,1052,794,1074)),('lineto',(763,1098)),('lineto',(738,1072)),('close',())]
 hidden('tail',shape(root,WHITE,DARK,16))
 # Audit generated paint components separately from retained original samples.
 discarded_paint=[]
 for n in order:
  arr=np.array(layers[n]);num,lab,st,_=cc(arr[:,:,3]>0);main=1+int(np.argmax(st[1:,4]))
  for i in range(1,num):
   if i==main:continue
   m=lab==i
   if not np.any(m&masks[n]):
    discarded_paint.append({'layer':n,'pixels':int(m.sum())});arr[m]=0
  layers[n]=Image.fromarray(arr)
 # Blink: remove only eye ink on the pale face; reconstruct background using nearby original face samples.
 head=np.array(layers['head']);blink=head.copy()
 eyes=[(414,442,66,34),(670,445,66,34)] if pose=='work' else [(393,437,60,57),(620,440,58,59)]
 eye_mask=np.zeros((H,W),np.uint8)
 for x,y,rx,ry in eyes:cv2.ellipse(eye_mask,(x,y),(rx,ry),0,0,360,255,-1)
 # Fill from a smooth local plane fitted to original pale pixels around each eye, no blur of existing pixels.
 for x,y,rx,ry in eyes:
  region=(xx>x-rx-14)&(xx<x+rx+14)&(yy>y-ry-14)&(yy<y+ry+14)
  samples=region&(eye_mask==0)&(a[:,:,0]>210)&(a[:,:,1]>205)&(a[:,:,2]>200)
  coords=np.column_stack([np.ones(samples.sum()),xx[samples]-x,yy[samples]-y]);target=(eye_mask>0)&region
  pred=np.column_stack([np.ones(target.sum()),xx[target]-x,yy[target]-y])
  for c in range(3):coef=np.linalg.lstsq(coords,a[:,:,c][samples],rcond=None)[0];blink[:,:,c][target]=np.clip(np.round(pred@coef),0,255)
 blinkim=Image.fromarray(blink)
 for x,y,rx,ry in eyes:
  if pose=='work':cmd=[('moveto',(x-42,y-8)),('curveto',(x-18,y+8,x+17,y+9,x+40,y-5))]
  else:cmd=[('moveto',(x-35,y+10)),('curveto',(x-19,y-23,x+16,y-23,x+35,y+10))]
  line=shape(cmd,None,DARK,12);blinkim.alpha_composite(line)
  ends=Image.new('RGBA',(W,H));d=aggdraw.Draw(ends)
  for px,py in [(x-42,y-8),(x+40,y-5)] if pose=='work' else [(x-35,y+10),(x+35,y+10)]:d.ellipse((px-6,py-6,px+6,py+6),aggdraw.Brush(DARK))
  d.flush();blinkim.alpha_composite(ends)
 # Alpha stays exactly the same as head, including semitransparent face interior.
 b=np.array(blinkim);b[:,:,3]=head[:,:,3];layers['headBlink']=Image.fromarray(b)
 def composite(angles={},blink=False):
  pad=160;im=Image.new('RGBA',(W+2*pad,H+2*pad))
  for n in order:
   l=layers['headBlink' if n=='head' and blink else n];expanded=Image.new('RGBA',im.size);expanded.alpha_composite(l,(pad,pad))
   if angles.get(n):expanded=expanded.rotate(angles[n],Image.Resampling.BICUBIC,center=(piv[n][0]+pad,piv[n][1]+pad))
   im.alpha_composite(expanded)
  return im
 rest=composite().crop((160,160,W+160,H+160));rest.save(out/'check-composite.png')
 diff=np.abs(np.array(rest).astype(int)-a.astype(int));metrics={'rgba_max':int(diff.max()),'rgba_mean':float(diff.mean()),'differing_pixels':int(np.any(diff,axis=2).sum())}
 components={}
 for n,im in layers.items():
  num,lab,st,_=cc(np.array(im)[:,:,3]>0);opaque_num,opaque_lab,opaque_stats,_=cc(np.array(im)[:,:,3]>32);components[n]={'alpha_gt32_count':opaque_num-1,'alpha_gt32_areas':sorted(opaque_stats[1:,4].tolist(),reverse=True),'count':num-1,'areas':sorted(st[1:,4].tolist(),reverse=True),'small_components':[s.tolist() for s in st[1:] if s[4]<1000]}
  im.save(out/f'{n}.png')
  for size,suffix in [((240,320),'@2x'),((120,160),'')]:im.resize(size,Image.Resampling.LANCZOS).save(out/'scaled'/f'{n}{suffix}.png')
 ranges={'tail':20,'head':8,'armLeft':15,'armRight':15,'body':0}
 poses=[('Rest',{},False),('Blink',{},True)]
 for n in ['head','armLeft','armRight','tail']:
  for sign in [-1,1]:poses.append((f'{n} {sign*ranges[n]:+}',{n:sign*ranges[n]},False))
 poses += [('Mixed A',{'head':8,'armLeft':15,'armRight':-15,'tail':20},False),('Mixed B',{'head':-8,'armLeft':-15,'armRight':15,'tail':-20},True)]
 for bg,suffix in [('#ffffff','white'),('#202633','dark')]:
  sheet=Image.new('RGB',(4*352,3*475),bg);d=ImageDraw.Draw(sheet)
  for i,(label,angles,bl) in enumerate(poses):
   im=composite(angles,bl);tile=Image.new('RGBA',im.size,bg);tile.alpha_composite(im);tile=tile.resize((352,447),Image.Resampling.LANCZOS);x=i%4*352;y=i//4*475
   sheet.paste(tile.convert('RGB'),(x,y+28));d.text((x+10,y+8),label,fill='#abb4c3' if suffix=='dark' else '#302416')
  sheet.save(out/f'check-poses-{suffix}.png')
  if suffix=='white':sheet.save(out/'check-poses.png')
 # Source-resolution contact sheets expose seams hidden by downscaled montages.
 joints=Image.new('RGB',(1000,1800),'#202633')
 for i,angles in enumerate([{'head':-8},{'head':8},{'armLeft':-15},{'armLeft':15},{'armRight':-15},{'armRight':15},{'tail':-20},{'tail':20}]):
  comp=composite(angles);bg=Image.new('RGBA',comp.size,'#202633');bg.alpha_composite(comp)
  box=(270,650,770,1100) if 'tail' not in angles else (200,930,700,1380) if pose=='work' else (550,880,1050,1330)
  box=tuple(v+160 for v in box);joints.paste(bg.crop(box).convert('RGB'),((i%2)*500,(i//2)*450))
 joints.save(out/'check-joints.png')
 # Isolated-layer QA, full-canvas alignment retained in exports.
 sheet=Image.new('RGB',(6*270,362),'#9ca5aa')
 for i,n in enumerate(order+['headBlink']):
  tile=Image.new('RGBA',(W,H),'#9ca5aa');tile.alpha_composite(layers[n]);sheet.paste(tile.resize((270,360)).convert('RGB'),(i*270,0));ImageDraw.Draw(sheet).text((i*270+5,5),n,fill='black')
 sheet.save(out/'check-layers.png')
 rig={'source':str(srcpath),'source_sha256':hashlib.sha256(srcpath.read_bytes()).hexdigest(),'canvas':{'width':W,'height':H},'coordinate_system':'top-left; x right, y down; positive angle counterclockwise','layers':[{'name':n,'file':n+'.png','z':i,'pivot':{'pixels':list(piv[n]),'normalized':[piv[n][0]/W,piv[n][1]/H]},'rotation_degrees':[-ranges[n],ranges[n]]} for i,n in enumerate(order)],'variants':{'headBlink':{'file':'headBlink.png','replaces':'head','z':4,'pivot':{'pixels':list(piv['head']),'normalized':[piv['head'][0]/W,piv['head'][1]/H]}}},'composite_error':metrics,'connected_components':components,'fragment_transfers':moves,'discarded_detached_generated_paint':discarded_paint,'notes':['armRight includes mug for work.','All original nontransparent source samples assigned exactly once; small disconnected fragments reassigned, never deleted.','Added paint clipped behind alpha >=253 source samples. Interior alpha 253/254 yields small rest composite differences.','headBlink replaces head; do not stack both.']}
 (out/'rig.json').write_text(json.dumps(rig,indent=2,ensure_ascii=False));print(pose,json.dumps(metrics),'components',[(n,c['count']) for n,c in components.items()],'transfers',len(moves))
for pose in ['work','excited']:build(pose)
