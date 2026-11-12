from pathlib import Path
from PIL import Image,ImageDraw
import numpy as np, cv2, aggdraw,json,hashlib
R=Path(__file__).resolve().parents[1]; S=R.parent; W,H=1086,1448
DARK='#382215'; WHITE='#fdfbf7'; BROWN='#54372c';PINK='#ffb39f'
def shape(cmd,fill=WHITE,stroke=None,width=16):
 im=Image.new('RGBA',(W,H));d=aggdraw.Draw(im);p=aggdraw.Path()
 for op,pts in cmd:getattr(p,op)(*pts)
 d.path(p,aggdraw.Brush(fill) if fill else None,aggdraw.Pen(stroke,width) if stroke else None);d.flush();return im
def poly(pts):
 im=Image.new('L',(W,H));ImageDraw.Draw(im).polygon(pts,fill=255);return np.array(im)>0
def curve(pts):
 # Monotonic x guide including exact outer-ink lower edge.
 x=np.arange(pts[0][0],pts[-1][0]+1);y=np.interp(x,*np.array(pts).T)
 return list(zip(x,y))
def ellipse(box,fill,stroke=None,width=16):
 im=Image.new('RGBA',(W,H));d=aggdraw.Draw(im);d.ellipse(box,aggdraw.Brush(fill) if fill else None,aggdraw.Pen(stroke,width) if stroke else None);d.flush();return im
C={
'yawning':dict(order=['tail','body','armUp','head','armMouth','tear'],piv={'tail':(411,1090),'body':(560,1010),'armUp':(705,739),'head':(550,729),'armMouth':(416,782),'tear':(688,431)},rng={'tail':20,'armUp':15,'head':8,'armMouth':8,'tear':0},guide=[(264,520),(275,568),(300,613),(330,644),(370,678),(420,708),(470,734),(520,747),(560,752),(610,744),(660,727),(710,694),(750,654),(780,605),(804,550)],
 arms={'armUp':[(705,671),(730,641),(808,531),(839,481),(960,405),(1000,550),(783,826),(690,843),(672,781)],'armMouth':[(339,638),(386,611),(424,617),(436,636),(459,634),(477,660),(476,708),(455,747),(449,804),(450,848),(398,898),(310,891),(303,784)]},tail=[(270,963),(375,949),(401,1047),(412,1070),(423,1133),(287,1143)],
 torso=[('moveto',(418,690)),('curveto',(488,664,627,660,696,692)),('curveto',(707,768,713,892,727,970)),('curveto',(620,1030,460,1016,394,972)),('curveto',(420,861,426,766,418,690)),('close',())]),
'eating':dict(order=['tail','body','armBowl','head','armChopsticks','rice'],piv={'tail':(360,1105),'body':(512,1010),'armBowl':(635,782),'head':(516,705),'armChopsticks':(392,780),'rice':(474,639)},rng={'tail':20,'armBowl':8,'head':6,'armChopsticks':15,'rice':0},guide=[(225,520),(235,558),(255,600),(290,640),(330,671),(375,695),(420,714),(470,725),(520,728),(570,721),(620,707),(670,686),(715,657),(750,621),(778,574),(794,530)],
 arms={'armChopsticks':[(170,664),(222,649),(254,631),(301,633),(331,651),(437,633),(489,637),(494,667),(346,708),(324,735),(332,754),(367,785),(392,829),(381,861),(331,889),(274,886),(236,838),(217,754),(175,754)],'armBowl':[(634,723),(675,754),(702,820),(705,721),(920,690),(930,940),(741,956),(650,934),(622,844)]},tail=[(230,975),(325,981),(348,1067),(359,1070),(373,1141),(232,1144)],
 torso=[('moveto',(395,682)),('curveto',(453,659,570,659,627,692)),('curveto',(656,765,650,885,668,968)),('curveto',(565,1021,433,1004,357,969)),('curveto',(385,874,400,760,395,682)),('close',())]),
'sunbathing':dict(order=['tail','body','armWave','armDrink','head'],piv={'tail':(350,1105),'body':(503,1010),'armWave':(379,755),'armDrink':(630,804),'head':(514,741)},rng={'tail':20,'armWave':15,'armDrink':12,'head':6},guide=[(239,530),(249,573),(273,617),(310,658),(350,689),(400,721),(450,745),(500,764),(540,768),(590,756),(640,738),(690,715),(735,681),(772,638),(794,585)],
 arms={'armWave':[(92,538),(232,542),(265,669),(298,690),(352,692),(413,725),(410,765),(392,805),(366,845),(260,841),(140,736)],'armDrink':[(619,747),(665,777),(706,846),(713,703),(780,646),(787,603),(874,583),(915,971),(656,961),(620,883)]},tail=[(218,982),(323,981),(335,1071),(347,1081),(367,1144),(231,1146)],
 torso=[('moveto',(388,713)),('curveto',(464,689,558,690,615,723)),('curveto',(647,813,648,914,669,987)),('curveto',(551,1034,430,1014,321,978)),('curveto',(352,874,379,785,388,713)),('close',())])}

def fix(src,pose):
 a=np.array(src);rgb=a[:,:,:3].astype(float);r,g,b=rgb.transpose(2,0,1);v=a[:,:,3]>0
 # Semantic flat regions; preserve original 1-2 px colour transitions and AA alpha.
 cats=np.zeros((H,W),np.uint8)
 cats[v&(r>185)&(g>185)&(b>175)]=1
 cats[v&(r>190)&(g>110)&(g<200)&(b<190)&((g-b)<55)]=2
 cats[v&(r>200)&(g>175)&(b>130)&(b<220)&((r-g)>15)&((g-b)>15)&(np.indices((H,W))[0]<240)]=8
 cats[v&(r>230)&(g<150)&(b<85)]=3
 cats[v&(r>150)&(g>100)&(g<185)&(b<110)&(cats==0)]=4
 cats[v&(r<105)&(g<85)&(b<75)]=5
 cats[v&(r<22)&(g<22)&(b<22)]=9
 cats[v&(r>=85)&(r<185)&(g<130)&(b<115)&(cats==0)]=6
 cats[v&(b>130)&(r<180)&(g>130)]=7
 palette={1:(253,251,247),2:(255,178,158),3:(255,115,0),4:(255,199,84),5:(56,34,21),6:(84,55,44),7:(137,208,240),8:(248,207,157),9:(2,2,2)}
 # Flatten eroded interiors, then preserve AA line-transition coverage by local interpolation.
 for k,color in palette.items():
  m=(cats==k).astype('uint8');inter=cv2.erode(m,np.ones((3,3),np.uint8))>0
  a[inter,:3]=color
 # Remove gradients up to boundaries using neighbourhood original-vs-flat offset, no geometry/alpha changes.
 changed=np.any(a[:,:,:3]!=rgb,axis=2)
 for k in palette:
  boundary=(cats==k)&~changed
  # nearest interior correction rather than hard replacing mixed edge pixels
  if not boundary.any():continue
  m=(cats==k)&changed
  if not m.any():continue
  _,inds=cv2.distanceTransformWithLabels((~m).astype('uint8'),cv2.DIST_L2,5,labelType=cv2.DIST_LABEL_PIXEL)
  coords=np.argwhere(m);near=coords[inds[boundary]-1];delta=a[near[:,0],near[:,1],:3].astype(float)-rgb[near[:,0],near[:,1]]
  # Edge deltas at already dark/light line blends capped to prevent fringe colour shifts.
  a[boundary,:3]=np.clip(rgb[boundary]+delta,0,255).astype('uint8')
 a[a[:,:,3]==0]=0
 return a

def build(pose):
 cfg=C[pose];order=cfg['order'];piv=cfg['piv'];srcpath=S/'cow-poses/out'/f'{pose}.png';src=Image.open(srcpath).convert('RGBA');a=fix(src,pose);out=R/'out'/pose;(out/'scaled').mkdir(parents=True,exist_ok=True);Image.fromarray(a).save(out/'source-fixed.png')
 vis=a[:,:,3]>0;yy,xx=np.indices((H,W))
 guides={
 'yawning':[(264,520),(280,578),(320,637),(360,675),(400,710),(440,733),(480,737),(520,752),(560,756),(600,746),(640,723),(680,702),(720,683),(760,633),(800,570),(815,520)],
 'eating':[(225,520),(240,575),(280,636),(320,674),(360,696),(400,713),(440,725),(480,729),(520,731),(560,729),(600,722),(640,712),(680,695),(720,669),(760,628),(790,568),(802,510)],
 'sunbathing':[(238,530),(280,645),(320,685),(360,712),(400,731),(440,745),(480,760),(520,771),(560,764),(600,751),(640,739),(680,718),(720,690),(760,648),(800,558),(810,520)]}
 edge=curve(guides[pose]);ink=(a[:,:,0]<105)&(a[:,:,3]>100)
 snapped=[];reliable=[]
 for x,y in edge:
  x=int(x);y=int(y);lo=max(0,y-12);hi=min(H,y+13);ys=np.where(ink[lo:hi,x])[0]+lo
  if len(ys):
   runs=np.split(ys,np.where(np.diff(ys)>1)[0]+1);run=min(runs,key=lambda r:abs(r[-1]-y));y=int(run[-1])+1
   if len(run)<24 and abs(y-int(np.interp(x,*np.array(guides[pose]).T)))<10:reliable.append((x,y))
  snapped.append((x,y))
 pts=np.array(reliable);coef=np.polyfit((pts[:,0]-530)/300,pts[:,1],8);edge=[(x,int(round(np.polyval(coef,(x-530)/300)))) for x,y in snapped];hm=poly([(0,0),(W,0),(W,500),(edge[-1][0],500)]+edge[::-1]+[(edge[0][0],500),(0,500)])
 raw={n:poly(p) for n,p in cfg['arms'].items()};raw['head']=hm;raw['tail']=poly(cfg['tail'])
 if pose=='yawning':raw['armMouth']=poly([(347,676),(351,654),(369,632),(398,618),(418,621),(429,638),(450,638),(463,652),(468,676),(464,705),(452,730),(438,743),(423,750),(426,800),(415,831),(433,849),(411,866),(380,880),(350,874),(330,853),(318,824),(324,780),(340,743),(349,723)])
 if pose=='eating':raw['armChopsticks']=poly([(217,706),(227,670),(249,649),(278,640),(305,645),(323,657),(323,671),(337,686),(342,710),(328,736),(315,747),(342,770),(369,802),(384,828),(379,854),(343,878),(304,878),(273,867),(247,836),(234,799),(227,759)])|poly([(173,680),(188,667),(439,628),(451,651),(202,709),(181,709)])|poly([(186,716),(470,644),(488,648),(492,671),(209,752),(191,747)])
 # Tail / trouser cut runs along the outer trousers ink.
 raw['tail'] &= xx < np.interp(yy,[980,1050,1100,1150],[350 if pose!='yawning' else 400,350 if pose!='yawning' else 403,359 if pose!='yawning' else 410,367 if pose!='yawning' else 415])
 if pose=='yawning':
  raw['tear']=poly([(663,415),(686,411),(711,419),(724,440),(710,455),(690,454),(675,441)])
 if pose=='eating':raw['rice']=poly([(436,619),(450,614),(457,605),(477,605),(483,613),(498,613),(506,627),(513,637),(514,650),(503,659),(494,675),(480,671),(477,660),(451,661),(441,649)])
 if pose=='eating':
  raw['armBowl']=poly([(623,708),(950,680),(950,957),(650,940),(622,846),(611,780)])
  raw['armChopsticks'] |= poly([(315,747),(392,703),(440,771),(435,801),(422,832),(394,862),(367,802)])&~hm
 if pose=='yawning':raw['armMouth'] |= poly([(420,722),(466,746),(470,785),(452,832),(432,852),(410,827)])&~hm
 if pose=='eating':
  # Thin golden rods plus their surrounding dark contour; no face/tongue colour moves with rods.
  rodzone=poly([(173,680),(188,667),(439,628),(451,651),(202,709),(181,709)])|poly([(186,716),(470,644),(488,648),(492,671),(209,752),(191,747)])
  gold=rodzone&(a[:,:,0]>190)&(a[:,:,1]>125)&(a[:,:,2]<140)
  rods=cv2.dilate(gold.astype('uint8'),cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(15,15)))>0
  raw['armChopsticks'] &= ~rodzone
  raw['armChopsticks'] |= rods
  raw['armChopsticks'] |= poly([(217,706),(227,670),(249,649),(278,640),(305,645),(323,657),(323,671),(337,686),(342,710),(328,736),(315,747),(237,759)])&(a[:,:,0]<185)&(a[:,:,1]<130)
 remaining=vis.copy();masks={}
 # Frontmost elements claim pixels first; behind-head arms exclude the entire head silhouette.
 priority=list(reversed(order))
 for n in priority:
  if n=='body':continue
  m=raw[n].copy()
  if n in cfg['arms'] and order.index(n)<order.index('head'):m &= ~hm
  masks[n]=remaining&m;remaining &= ~m
 masks['body']=remaining
 # Reassign disconnected line shards to nearest actual main part, retaining every sample.
 moves=[];dist={}
 for n,m in masks.items():
  if n in ['rice','tear']:continue
  count,lab,st,_=cv2.connectedComponentsWithStats((m&(a[:,:,3]>32)).astype('uint8'),8);main=1+np.argmax(st[1:,4]);dist[n]=cv2.distanceTransform((lab!=main).astype('uint8'),cv2.DIST_L2,5)
 for n,m in masks.items():
  if n in ['rice','tear']:continue
  count,lab,st,_=cv2.connectedComponentsWithStats(m.astype('uint8'),8);main=1+np.argmax(st[1:,4])
  for i in range(1,count):
   if i==main:continue
   frag=lab==i;target=min(dist,key=lambda k:dist[k][frag].min())
   if target!=n:masks[n][frag]=False;masks[target][frag]=True;moves.append(dict(source=n,target=target,pixels=int(frag.sum()),bbox=st[i,:4].tolist()))
 layers={}
 for n in order:
  b=a.copy();b[~masks[n]]=0;layers[n]=Image.fromarray(b)
 def hidden(n,paint):
  occ=np.zeros((H,W),bool)
  for k in order[order.index(n)+1:]:occ|=masks[k]&(a[:,:,3]>=253)
  b=np.array(paint);b[~occ]=0;layers[n]=Image.alpha_composite(Image.fromarray(b),layers[n])
 hidden('body',shape(cfg['torso'],WHITE))
 # Rounded shoulder roots overlap torso, constrained to hidden pixels at rest.
 for n in cfg['arms']:
  x,y=piv[n];hidden(n,ellipse((x-55,y-63,x+55,y+63),WHITE))
 x,y=piv['tail'];hidden('tail',ellipse((x-33,y-21,x+23,y+21),WHITE))
 # Rebuild the occluded face as one paint, so mouth paint is above cheek paint.
 if pose in ['yawning','eating']:
  cmd=[('moveto',(edge[0][0],400)),('lineto',(edge[-1][0],400))]+[('lineto',(float(x),float(y-8))) for x,y in edge[::-1]]+[('close',())]
  face=shape(cmd,WHITE,DARK,16)
  if pose=='yawning':
   face.alpha_composite(shape([('moveto',(448,541)),('curveto',(419,558,425,633,452,675)),('curveto',(479,731,559,753,601,705)),('curveto',(641,655,654,572,622,541)),('close',())],DARK))
   face.alpha_composite(shape([('moveto',(474,674)),('curveto',(491,625,572,602,619,656)),('curveto',(607,699,580,719,543,721)),('curveto',(508,718,488,702,474,674)),('close',())],PINK))
  else:
   face.alpha_composite(shape([('moveto',(416,583)),('curveto',(411,630,438,685,476,704)),('curveto',(530,731,591,690,609,583)),('close',())],DARK))
   face.alpha_composite(shape([('moveto',(455,665)),('curveto',(478,629,542,617,584,645)),('curveto',(560,693,509,721,478,691)),('close',())],PINK))
  hidden('head',face)
 # Discard only newly painted disconnected specks without any retained source pixels.
 for n in order:
  b=np.array(layers[n]);count,lab,st,_=cv2.connectedComponentsWithStats((b[:,:,3]>0).astype('uint8'),8);main=1+np.argmax(st[1:,4])
  for i in range(1,count):
   m=lab==i
   if i!=main and not np.any(m&masks[n]):b[m]=0
  layers[n]=Image.fromarray(b)
 if pose=='eating':
  blink=np.array(layers['head']);original=blink.copy()
  for x in [400,636]:
   m=poly([(x-63,386),(x+63,386),(x+63,455),(x-63,455)]);blink[m,:3]=[253,251,247]
  im=Image.fromarray(blink)
  for x in [400,636]:im.alpha_composite(shape([('moveto',(x-42,414)),('curveto',(x-19,447,x+19,447,x+42,414))],None,DARK,17))
  b=np.array(im);eyearea=poly([(337,386),(463,386),(463,455),(337,455)])|poly([(573,386),(699,386),(699,455),(573,455)]);b[~eyearea]=original[~eyearea];b[:,:,3]=original[:,:,3];layers['headBlink']=Image.fromarray(b)
 def composite(angles={},blink=False,shift={}):
  pad=180;im=Image.new('RGBA',(W+pad*2,H+pad*2))
  for n in order:
   l=layers['headBlink' if blink and n=='head' else n];tile=Image.new('RGBA',im.size);tile.alpha_composite(l,(pad,pad+shift.get(n,0)))
   if angles.get(n):tile=tile.rotate(angles[n],Image.Resampling.BICUBIC,center=(pad+piv[n][0],pad+piv[n][1]))
   if n in ['tear','rice'] and angles.get('head'):tile=tile.rotate(angles['head'],Image.Resampling.BICUBIC,center=(pad+piv['head'][0],pad+piv['head'][1]))
   im.alpha_composite(tile)
  return im
 comp=composite().crop((180,180,W+180,H+180));comp.save(out/'check-composite.png');diff=np.abs(np.array(comp).astype(int)-a.astype(int));metrics=dict(rgba_max=int(diff.max()),rgba_mean=float(diff.mean()),differing_pixels=int(np.any(diff,axis=2).sum()))
 ownership=np.zeros((H,W),np.uint8)
 cc={}
 for n,im in layers.items():
  im.save(out/f'{n}.png')
  if n in order:ownership[masks[n]]=order.index(n)+1
  for size,suf in [((240,320),'@2x'),((120,160),'')]:im.resize(size,Image.Resampling.LANCZOS).save(out/'scaled'/f'{n}{suf}.png')
  b=np.array(im);count,lab,st,_=cv2.connectedComponentsWithStats((b[:,:,3]>0).astype('uint8'),8);main=1+np.argmax(st[1:,4]);frags=[]
  for i in range(1,count):
   if i!=main:frags.append(dict(area=int(st[i,4]),bbox=st[i,:4].tolist(),max_alpha=int(b[:,:,3][lab==i].max())))
  cc[n]=dict(count=count-1,significant_detached=[f for f in frags if f['area']>=20 and f['max_alpha']>32],fragments=frags)
 Image.fromarray(ownership).save(out/'ownership.png')
 poses=[('Rest',{},False,{})]
 if pose=='eating':poses.append(('Blink',{},True,{}))
 for n in order:
  if cfg['rng'].get(n,0):
   for sign in [-1,1]:poses.append((f'{n} {sign*cfg["rng"][n]:+}',{n:sign*cfg['rng'][n]},False,{}))
  elif n in ['rice','tear']:
   for sign in [-1,1]:poses.append((f'{n} dy {sign*(10 if n=="rice" else 3):+}',{},False,{n:sign*(10 if n=='rice' else 3)}))
 for sign in [-1,1]:poses.append((f'Mixed {sign:+}',{n:sign*v*(-1 if i%2 else 1) for i,(n,v) in enumerate(cfg['rng'].items())},pose=='eating' and sign==1,{}))
 rows=(len(poses)+3)//4
 for bg,suf in [('#ffffff','white'),('#202633','dark')]:
  sheet=Image.new('RGB',(4*350,rows*460),bg);d=ImageDraw.Draw(sheet)
  for i,(label,angles,bl,sh) in enumerate(poses):
   im=composite(angles,bl,sh);tile=Image.new('RGBA',im.size,bg);tile.alpha_composite(im);sheet.paste(tile.resize((350,432),Image.Resampling.LANCZOS).convert('RGB'),(i%4*350,i//4*460+28));d.text((i%4*350+8,i//4*460+8),label,fill='gray')
  sheet.save(out/f'check-poses-{suf}.png')
  if suf=='white':sheet.save(out/'check-poses.png')
 sheet=Image.new('RGB',(len(layers)*272,390),'#9aa3ab')
 for i,(n,im) in enumerate(layers.items()):
  tile=Image.new('RGBA',(W,H),'#9aa3ab');tile.alpha_composite(im);sheet.paste(tile.resize((272,363)).convert('RGB'),(i*272,27));ImageDraw.Draw(sheet).text((i*272+5,7),n,fill='black')
 sheet.save(out/'check-layers.png')
 jointposes=[p for p in poses if p[1]]
 joint=Image.new('RGB',(1000,450*((len(jointposes)+1)//2)),'#202633')
 for i,(label,angles,bl,sh) in enumerate(jointposes):
  im=composite(angles,bl,sh);bg=Image.new('RGBA',im.size,'#202633');bg.alpha_composite(im)
  box=(210,900,710,1320) if 'tail' in angles and len(angles)==1 else (280,570,780,990)
  joint.paste(bg.crop(tuple(v+180 for v in box)).convert('RGB'),(i%2*500,i//2*450+30));ImageDraw.Draw(joint).text((i%2*500+8,i//2*450+8),label,fill='white')
 joint.save(out/'check-joints.png')
 rig=dict(source=str(srcpath),source_sha256=hashlib.sha256(srcpath.read_bytes()).hexdigest(),fixed_source='source-fixed.png',canvas=dict(width=W,height=H),coordinate_system='top-left; x right y down; positive rotation counterclockwise',palette=dict(pants_and_hooves='#54372c',sample='cow-work.png trousers ROI mode RGB 84,55,44'),layers=[dict(name=n,file=f'{n}.png',z=i,parent='head' if n in ['tear','rice'] else None,pivot=dict(pixels=piv[n],normalized=[piv[n][0]/W,piv[n][1]/H]),rotation_degrees=[-cfg['rng'].get(n,0),cfg['rng'].get(n,0)],translation_y_pixels=[-10,10] if n=='rice' else [-3,3] if n=='tear' else [0,0],opacity_range=[0,1] if n in ['rice','tear'] else [1,1]) for i,n in enumerate(order)],fragment_transfers=moves,composite_error=metrics)
 if pose=='eating':rig['variants']={'headBlink':dict(file='headBlink.png',replaces='head',pivot=rig['layers'][3]['pivot'])}
 report=dict(source_unchanged=True,source_fixed_samples_retained=all(np.array_equal(np.array(layers[n])[masks[n]],a[masks[n]]) for n in order),dimensions_pass=all(im.size==(W,H) for im in layers.values()),composite_error=metrics,connected_components=cc,significant_fragments_pass=all(not v['significant_detached'] for v in cc.values()))
 (out/'rig.json').write_text(json.dumps(rig,indent=2,ensure_ascii=False));(out/'verification.json').write_text(json.dumps(report,indent=2,ensure_ascii=False));print(pose,metrics,'CC',[(n,v['count'],len(v['significant_detached'])) for n,v in cc.items()])
for p in C:build(p)
