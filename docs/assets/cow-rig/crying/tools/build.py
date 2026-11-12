from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import numpy as np,cv2,aggdraw,json,hashlib,math,shutil
R=Path(__file__).resolve().parents[1];S=R.parent;W,H=1086,1448
DARK='#392413';WHITE='#fdf7f1';SHIRT='#fdfdfd';BROWN='#54372c';BLUE='#36c0e6'
def shape(cmd,fill=None,stroke=None,width=14):
 im=Image.new('RGBA',(W,H));d=aggdraw.Draw(im);p=aggdraw.Path()
 for op,pts in cmd:getattr(p,op)(*pts)
 d.path(p,aggdraw.Brush(fill) if fill else None,aggdraw.Pen(stroke,width) if stroke else None);d.flush();return im
def polygon(pts,fill=None,stroke=None,width=14):
 return shape([('moveto',pts[0])]+[('lineto',p) for p in pts[1:]]+[('close',())],fill,stroke,width)
def pm(pts):return np.array(polygon(pts,'white'))[:,:,3]>127
def ellipse(box,fill,stroke=None,width=14):
 im=Image.new('RGBA',(W,H));d=aggdraw.Draw(im);d.ellipse(box,aggdraw.Brush(fill),aggdraw.Pen(stroke,width) if stroke else None);d.flush();return im
def flat(im,pose):
 a=np.array(im);rgb=a[:,:,:3].astype(float);r,g,b=rgb.transpose(2,0,1);alpha=a[:,:,3]
 # Flat areas are colour classified, with a 2px transition band retained around ink/AA.
 seeds=np.array([(251,248,245),(251,182,161),(244,205,162),(250,100,0),(54,192,230),(116,81,66),(153,154,159),(58,35,21)],float)
 palette=np.array([(253,247,241),(251,183,161),(244,205,161),(255,101,0),(54,192,230),(84,55,44),(153,154,159),(58,35,21)],np.uint8)
 ds=np.stack([np.sum((rgb-col)**2,axis=2) for col in seeds])
 cats=np.argmin(ds,axis=0)
 for k,col in enumerate(palette):
  mask=(cats==k)&(alpha>240);inner=cv2.erode(mask.astype('uint8'),np.ones((3,3),np.uint8))>0
  if k!=7:a[:,:,:3][inner]=col
 a[:,:,3][alpha>=250]=255
 a[alpha==0]=0
 return Image.fromarray(a)
def lower_mask(a,guide):
 # Trace bottom of the head ink nearest the hand-authored exterior silhouette.
 ink=(a[:,:,0]<105)&(a[:,:,1]<90)&(a[:,:,3]>200);pts=[]
 for x in range(guide[0][0],guide[-1][0]+1):
  expected=int(np.interp(x,*np.array(guide).T));lo=max(0,expected-10);hi=min(H,expected+11)
  ys=np.where(ink[lo:hi,x])[0]+lo
  if len(ys):
   runs=np.split(ys,np.where(np.diff(ys)>1)[0]+1);expected=int(min(runs,key=lambda q:abs(q[-1]-expected))[-1])
  pts.append((x,expected))
 m=pm([(0,0),(W,0),(W,guide[-1][1]-50),(guide[-1][0]+1,guide[-1][1]-50)]+pts[::-1]+[(guide[0][0]-1,guide[0][1]-50),(0,guide[0][1]-50)])
 shell=cv2.dilate(m.astype('uint8'),np.ones((31,31),np.uint8))>0
 return m | (shell & (a[:,:,0]<135) & (a[:,:,1]<110) & ((np.indices((H,W))[1]<guide[0][0]+140)|(np.indices((H,W))[1]>guide[-1][0]-140)))
def build(pose):
 out=R/'out'/pose;(out/'scaled').mkdir(parents=True,exist_ok=True)
 src=S/'cow-poses/out'/f'{pose}.png';orig=Image.open(src).convert('RGBA');im=orig.copy()
 if pose=='crying' and (R/'tools-b/wallet-patch.png').exists():
  patch=Image.open(R/'tools-b/wallet-patch.png'); im.alpha_composite(patch)
 im=flat(im,pose)
 a=np.array(im);yy,xx=np.indices((H,W));visible=a[:,:,3]>0
 if pose=='lyingFlat':
  head=lower_mask(a,[(85,1190),(110,1228),(150,1260),(190,1285),(215,1294),(250,1233),(300,1230),(350,1228),(400,1220),(450,1200),(485,1170),(510,1130),(530,1105),(560,1123),(585,1148),(604,1100)])
  # Head includes rear bent arms, following their lower outer edge.
  head=pm([(0,0),(W,0),(W,1038),(532,1038),(565,1050),(593,1075),(604,1100),(588,1143),(557,1186),(544,1199),(500,1200),(493,1215),(447,1225),(360,1238),(290,1242),(242,1234),(217,1289),(190,1290),(145,1270),(110,1244),(88,1204),(0,1204)])
  leg=pm([(592,1360),(590,1300),(607,1235),(638,1157),(675,1090),(714,1065),(754,1067),(795,1096),(823,1143),(845,1197),(882,1210),(905,1244),(888,1277),(850,1290),(813,1284),(789,1255),(744,1214),(722,1177),(707,1207),(693,1242),(688,1280),(682,1359)])
  # Only raised leg above the long resting-leg seam.
  line=np.interp(xx,[590,650,700,750,790,830,910],[1241,1242,1244,1248,1255,1288,1292])
  leg&=(yy<line)|(xx<681)|(xx>780)
  shell=cv2.dilate(leg.astype('uint8'),np.ones((23,23),np.uint8))>0
  leg |= shell & (a[:,:,0]<135)&(a[:,:,1]<110)&(yy<1240)&(xx>650)
  tail=pm([(210,1316),(305,1318),(337,1334),(392,1332),(399,1386),(210,1386)])
  shell=cv2.dilate(head.astype('uint8'),np.ones((27,27),np.uint8))>0
  head |= shell & (a[:,:,0]<135)&(a[:,:,1]<110)&(xx<610)&(yy<1310)
  initial=[('head',head),('legUp',leg),('tail',tail)]
  order=['tail','body','legUp','head'];piv={'tail':(376,1348),'body':(560,1300),'legUp':(603,1350),'head':(375,1200)};ranges={'tail':15,'body':0,'legUp':10,'head':4}
 elif pose=='sweating':
  head=lower_mask(a,[(299,555),(315,600),(343,645),(380,676),(420,696),(460,710),(510,721),(560,728),(610,727),(660,723),(710,710),(760,685),(800,650),(833,610),(854,555)])
  sweatboxes=[(207,405,301,475),(230,470,295,540),(375,520,429,600),(433,239,486,322),(663,310,709,378),(761,519,814,602),(876,511,931,580),(878,442,968,513)]
  sweats=[pm([(x0,y0),(x1,y0),(x1,y1),(x0,y1)]) & ((a[:,:,0]<245) if i in [2,3,4,5] else True) for i,(x0,y0,x1,y1) in enumerate(sweatboxes)]
  laptop=pm([(352,833),(388,816),(469,826),(493,862),(550,872),(582,860),(637,873),(659,907),(704,907),(746,803),(767,755),(971,724),(985,778),(915,971),(856,1000),(828,1032),(780,1039),(732,1005),(470,1014),(442,991),(444,956),(390,937),(368,899)])
  tail=pm([(280,1018),(385,1024),(419,1100),(419,1168),(277,1184)])
  initial=[(f'sweat{i+1}',m) for i,m in enumerate(sweats)]+[('head',head),('laptop',laptop),('tail',tail)]
  order=['tail','body','laptop','head']+[f'sweat{i+1}' for i in range(8)]
  piv={'tail':(412,1131),'body':(575,1050),'laptop':(610,900),'head':(580,716)};ranges={'tail':15,'body':0,'laptop':0,'head':4}
  for i,(x0,y0,x1,y1) in enumerate(sweatboxes):piv[f'sweat{i+1}']=((x0+x1)//2,(y0+y1)//2);ranges[f'sweat{i+1}']=0
 else:
  head=lower_mask(a,[(238,560),(254,609),(285,656),(325,698),(365,725),(410,742),(460,754),(510,759),(560,756),(610,748),(660,731),(710,706),(750,669),(778,621),(794,560)])
  wallet=pm([(285,812),(333,810),(384,828),(384,898),(413,930),(470,940),(520,956),(575,940),(621,930),(650,899),(647,830),(690,809),(743,813),(770,900),(731,969),(718,1020),(678,1101),(519,1112),(367,1077),(333,1009),(295,960),(270,896)])
  tail=pm([(227,1040),(328,1043),(361,1128),(362,1198),(226,1200)])
  # Tears use alpha colour matting below; their original visible samples are assigned once.
  blue=(a[:,:,2]>145)&(a[:,:,0]<155)&(a[:,:,1]>120)&(yy>455)&(yy<713)
  initial=[('tearLeft',blue&(xx<520)),('tearRight',blue&(xx>520)),('head',head),('wallet',wallet),('tail',tail)]
  order=['tail','body','wallet','head','tearLeft','tearRight'];piv={'tail':(350,1158),'body':(520,1050),'wallet':(519,950),'head':(520,745),'tearLeft':(413,469),'tearRight':(630,469)};ranges={n:0 for n in order};ranges.update(tail=15,head=6)
 remaining=visible.copy();masks={}
 for n,m in initial:masks[n]=remaining&m;remaining&=~m
 masks['body']=remaining
 # Reassign detached source fragments to nearest substantial part, never delete source samples.
 moves=[];mains={}
 for n,m in masks.items():
  num,lab,st,_=cv2.connectedComponentsWithStats((m&(a[:,:,3]>32)).astype('uint8'),8)
  mains[n]=lab==(1+np.argmax(st[1:,4])) if num>1 else m
 dist={n:cv2.distanceTransform((~m).astype('uint8'),cv2.DIST_L2,5) for n,m in mains.items()}
 for n in list(masks):
  num,lab,st,_=cv2.connectedComponentsWithStats(masks[n].astype('uint8'),8)
  if num<=2:continue
  main=1+np.argmax(st[1:,4])
  for i in range(1,num):
   if i==main or st[i,4]>1000:continue
   m=lab==i;target=min(masks,key=lambda k:float(dist[k][m].min()))
   if target!=n:
    masks[n][m]=False;masks[target][m]=True;moves.append(dict(source=n,target=target,pixels=int(m.sum()),bbox=st[i,:4].tolist()))
 layers={}
 for n,m in masks.items():
  b=a.copy();b[~m]=0;layers[n]=Image.fromarray(b)
 def hidden(n,paint):
  occ=np.zeros((H,W),bool)
  for above in order[order.index(n)+1:]:occ|=masks[above]&(a[:,:,3]==255)
  b=np.array(paint);b[~occ]=0;layers[n]=Image.alpha_composite(Image.fromarray(b),layers[n])
 # Anatomical replacement fills beneath moving layers; original visible samples stay on top.
 if pose=='lyingFlat':
  hidden('body',polygon([(210,1190),(380,1165),(523,1167),(635,1210),(685,1265),(686,1357),(395,1360),(272,1305),(203,1307)],SHIRT,DARK,15))
  hidden('body',polygon([(570,1243),(680,1243),(800,1254),(950,1266),(953,1359),(570,1359)],BROWN,DARK,14))
  hidden('tail',ellipse((350,1329,408,1363),SHIRT,DARK,12))
 else:
  if pose=='sweating':cap=[(430,675),(672,681),(730,771),(761,986),(720,1047),(590,1050),(400,1000),(365,849)];tie=[(559,772),(608,779),(593,853),(548,918),(510,957),(478,933),(525,859)]
  else:cap=[(365,696),(672,697),(731,812),(696,1039),(521,1073),(335,1042),(304,825)];tie=[(503,804),(545,804),(583,975),(520,1020),(461,978)]
  hidden('body',polygon(cap,SHIRT,DARK,16));hidden('body',polygon(tie,'#ff6500',DARK,13))
  if pose=='crying':
   hidden('body',polygon([(342,1040),(695,1040),(695,1140),(342,1140)],BROWN))
  hidden('tail',ellipse((325 if pose=='crying' else 393,1112,385 if pose=='crying' else 449,1176),SHIRT,DARK,13))
  if pose=='sweating':
   for n in ['sweat3','sweat4','sweat5','sweat6']:
    x0,y0,x1,y1=sweatboxes[int(n[5:])-1]
    hidden('head',polygon([(x0,y0),(x1,y0),(x1,y1),(x0,y1)],WHITE))
  else:
   for n in ['tearLeft','tearRight']:hidden('head',Image.new('RGBA',(W,H),WHITE))
 # Blink is exact same head except two eye regions.
 if pose=='lyingFlat':
  blink=layers['head'].copy()
  for box in [(211,1045,297,1110),(377,1008,463,1074)]:
   x0,y0,x1,y1=box
   blink.alpha_composite(ellipse(box,WHITE))
   blink.alpha_composite(shape([('moveto',(x0+13,(y0+y1)//2+4)),('curveto',(x0+30,y1-7,x1-24,y1-14,x1-10,(y0+y1)//2-8))],None,DARK,10))
  b=np.array(blink);b[:,:,3]=np.array(layers['head'])[:,:,3];layers['headBlink']=Image.fromarray(b)
 # Scale lying character about its bottom anchor, maintaining full canvas exports.
 scale=1.;tx=ty=0
 if pose=='lyingFlat':
  ys,xs=np.where(a[:,:,3]>32);scale=(W*.94)/(xs.max()-xs.min()+1);tx=W/2-scale*(xs.min()+xs.max())/2;ty=ys.max()*(1-scale)
  def trans(im):return im.transform((W,H),Image.Transform.AFFINE,(1/scale,0,-tx/scale,0,1/scale,-ty/scale),Image.Resampling.BICUBIC)
  layers={n:trans(l) for n,l in layers.items()};im=trans(im)
  piv={n:(round(x*scale+tx),round(y*scale+ty)) for n,(x,y) in piv.items()}
 if pose=='lyingFlat':
  im=Image.new('RGBA',(W,H))
  for n in order:im.alpha_composite(layers[n])
 im.save(out/'source-fixed.png')
 def comp(changes={},blink=False):
  result=Image.new('RGBA',(W,H))
  for n in order:
   l=layers['headBlink' if n=='head' and blink else n];c=changes.get(n,{})
   if c.get('scaleY'):
    sy=c['scaleY'];px,py=piv[n];l=l.transform((W,H),Image.Transform.AFFINE,(1,0,0,0,1/sy,py-py/sy),Image.Resampling.BICUBIC)
   if n.startswith('tear'):
    ha=changes.get('head',{}).get('angle',0)
    if ha:l=l.rotate(ha,Image.Resampling.BICUBIC,center=piv['head'])
    hmask=layers['head']
    if ha:hmask=hmask.rotate(ha,Image.Resampling.BICUBIC,center=piv['head'])
    ar=np.array(l);ar[:,:,3]=np.minimum(ar[:,:,3],np.array(hmask)[:,:,3]);l=Image.fromarray(ar)
   if c.get('angle'):l=l.rotate(c['angle'],Image.Resampling.BICUBIC,center=piv[n])
   if c.get('dy') or c.get('dx'):l=l.transform((W,H),Image.Transform.AFFINE,(1,0,-c.get('dx',0),0,1,-c.get('dy',0)),Image.Resampling.BICUBIC)
   result.alpha_composite(l)
  return result
 rest=comp();rest.save(out/'check-composite.png')
 diff=np.abs(np.array(rest).astype(int)-np.array(im).astype(int));opaque=np.array(im)[:,:,3]>0
 metrics={'rgba_max':int(diff.max()),'rgba_mean':float(diff.mean()),'different_pixels':int(np.any(diff,2).sum())}
 components={}
 for n,l in layers.items():
  l.save(out/f'{n}.png')
  for size,suf in [((240,320),'@2x'),((120,160),'')]:l.resize(size,Image.Resampling.LANCZOS).save(out/'scaled'/f'{n}{suf}.png')
  al=np.array(l)[:,:,3];num,lab,st,_=cv2.connectedComponentsWithStats((al>32).astype('uint8'),8)
  sig=sorted(st[1:,4].tolist(),reverse=True)
  num0,_,_,_=cv2.connectedComponentsWithStats((al>0).astype('uint8'),8)
  components[n]={'alpha_gt0_components':num0-1,'alpha_gt32_components':num-1,'areas_gt32':sig,'detached_ge20':sum(v>=20 for v in sig[1:])}
 poses=[('Rest',{},False)]
 if 'headBlink' in layers:poses.append(('Blink',{},True))
 for n in order:
  if n=='body':continue
  for sign in [-1,1]:
   change={}
   if ranges[n]:change={'angle':ranges[n]*sign}
   elif n in ['wallet','laptop']:change={'dy':sign*(4 if n=='wallet' else 3)}
   elif n.startswith('sweat'):change={'dx':sign*15,'dy':-10}
   elif n.startswith('tear'):change={'scaleY':.8 if sign<0 else 1.15}
   poses.append((f'{n} {sign:+}',{n:change},False))
 for sign in [-1,1]:
  c={n:({'angle':ranges[n]*sign} if ranges[n] else {'dy':sign*(4 if n=='wallet' else 3)} if n in ['wallet','laptop'] else {'scaleY':.8 if sign<0 else 1.15} if n.startswith('tear') else {'dx':sign*15,'dy':-10} if n.startswith('sweat') else {}) for n in order}
  poses.append((f'Mixed {sign:+}',c,sign<0 and 'headBlink' in layers))
 for bg,name in [('#ffffff','white'),('#202633','dark')]:
  rows=math.ceil(len(poses)/4);sheet=Image.new('RGB',(1200,rows*425),bg);d=ImageDraw.Draw(sheet)
  for i,(title,ch,bl) in enumerate(poses):
   tile=Image.new('RGBA',(W,H),bg);tile.alpha_composite(comp(ch,bl));sheet.paste(tile.resize((300,400),Image.Resampling.LANCZOS).convert('RGB'),((i%4)*300,(i//4)*425+25));d.text(((i%4)*300+8,(i//4)*425+6),title,fill='#b8c4d4' if name=='dark' else DARK)
  sheet.save(out/f'check-poses-{name}.png')
  if name=='white':sheet.save(out/'check-poses.png')
 sheet=Image.new('RGB',(len(layers)*240,345),'#8998a4')
 for i,n in enumerate(order+(['headBlink'] if 'headBlink' in layers else [])):
  tile=Image.new('RGBA',(W,H),'#8998a4');tile.alpha_composite(layers[n]);sheet.paste(tile.resize((240,320)).convert('RGB'),(i*240,25));ImageDraw.Draw(sheet).text((i*240+5,5),n,fill='black')
 sheet.save(out/'check-layers.png')
 rig={'canvas':{'width':W,'height':H},'source':str(src),'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'fixed_source':'source-fixed.png','coordinate_system':'top-left; positive rotation CCW; normalized x/1086,y/1448','layers':[],'variants':{},'source_scale':{'scale':scale,'translation':[tx,ty]},'fragment_transfers':moves,'composite_error':metrics}
 for i,n in enumerate(order):
  x,y=piv[n];rig['layers'].append({'name':n,'file':n+'.png','z':i,'pivot':{'pixels':[x,y],'normalized':[x/W,y/H]},'rotation_degrees':[-ranges[n],ranges[n]],'translation_pixels':{'x':[-15,15] if n.startswith('sweat') else [0,0],'y':[-4,4] if n=='wallet' else [-3,3] if n=='laptop' else [-15,0] if n.startswith('sweat') else [0,0]},'scale_y':[.8,1.15] if n.startswith('tear') else [1,1],'parent':'head' if n.startswith('tear') else 'root','clip_to':'head' if n.startswith('tear') else None})
 if 'headBlink' in layers:rig['variants']['headBlink']={'file':'headBlink.png','replaces':'head','pivot':rig['layers'][-1]['pivot']}
 (out/'rig.json').write_text(json.dumps(rig,indent=2))
 verify={'dimensions':[W,H],'source_sha256_unchanged':hashlib.sha256(src.read_bytes()).hexdigest()==rig['source_sha256'],'composite_error':metrics,'connected_components':components,'fragment_transfers':moves,'visual_qa':'pending'}
 (out/'verification.json').write_text(json.dumps(verify,indent=2))
 print(pose,metrics,'components',[(n,v['detached_ge20']) for n,v in components.items()])
if __name__=='__main__':
 import sys
 for p in (sys.argv[1:] or ['lyingFlat','sweating','crying']):build(p)
