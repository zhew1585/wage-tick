from PIL import Image, ImageDraw, ImageFont
import numpy as np, cv2, aggdraw, json, hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; OUT=ROOT/'out'; (OUT/'scaled').mkdir(parents=True,exist_ok=True)
SRC=Path('/Users/weizhe/.pencil/documents/5498c176-4755-4b2f-b351-c6533167e9f2/images/cow-payday.png')
src=Image.open(SRC).convert('RGBA'); a=np.array(src); W,H=src.size
DARK='#392212'; WHITE='#fffdfb'; ORANGE='#ff6500'
def shape(commands, fill=WHITE, stroke=None, width=14):
 im=Image.new('RGBA',(W,H)); d=aggdraw.Draw(im); p=aggdraw.Path()
 for op,pts in commands:
  getattr(p,op)(*pts)
 d.path(p,aggdraw.Brush(fill) if fill else None,aggdraw.Pen(stroke,width) if stroke else None);d.flush();return im
def poly(pts):
 im=Image.new('L',(W,H));ImageDraw.Draw(im).polygon(pts,fill=255);return np.array(im)>0
def pathmask(commands):return np.array(shape(commands,'white'))[:,:,3]>127
def extract(mask):
 b=a.copy();b[~mask]=0;return Image.fromarray(b)
def hidden_patch(base,patch,occluder):
 # Source interior alpha is predominantly 253/254. Keep true edge AA, fill only under near-opaque samples.
 b=np.array(patch);b[(np.array(occluder)[:,:,3]<253)|(a[:,:,3]<253)]=0
 return Image.alpha_composite(Image.fromarray(b),base)
# Coins trace follows the outer dark contour where it intersects the ear and hand.
coin3=pathmask([('moveto',(919,302)),('curveto',(950,296,977,315,975,345)),('curveto',(975,374,950,399,923,401)),('curveto',(897,401,875,385,874,362)),('curveto',(872,336,893,311,919,302)),('close',())])
cm=poly([(830,0),(1086,0),(1086,305),(936,305),(921,281),(914,260),(871,261),(841,240),(830,216)])|coin3
# Locate the head's lower ink edge in each column. The curve is only a search guide.
guide=np.array([(235,550),(250,592),(270,626),(290,650),(310,668),(330,685),(350,696),(370,707),(390,716),(410,724),(430,730),(450,736),(470,745),(490,753),(510,757),(530,760),(550,759),(570,754),(590,747),(610,736),(630,729),(650,724),(670,717),(690,708),(710,697),(730,685),(750,667),(770,644),(790,612),(800,584),(810,549)])
dark=(a[:,:,0]<115)&(a[:,:,1]<86)&(a[:,:,2]<72)&(a[:,:,3]>250)
bottom=[]
for x in range(235,811):
 y=int(np.interp(x,guide[:,0],guide[:,1])); ys=np.where(dark[max(0,y-3):y+3,x])[0]+max(0,y-3)
 # first dark run nearest expected lower edge, avoid collar lines below.
 if len(ys):
  runs=np.split(ys,np.where(np.diff(ys)>1)[0]+1); run=min(runs,key=lambda r:abs(r[-1]-y));y=int(run[-1])
 bottom.append((x,y))
hm=poly([(0,0),(1086,0),(1086,380),(825,380),(825,470),(818,535),(810,558)]+bottom[::-1]+[(228,535),(220,500),(220,380),(0,380)])&~cm
# Follow the side ink edge at the sleeve overlap, rather than keeping sleeve white in head.
left=[]; right=[]
for y in range(380,566):
 for arr,g,out,side in [(left,[(380,258),(450,242),(480,240),(500,235),(520,235),(540,237),(565,242)],left,'left'),(right,[(380,788),(450,799),(480,807),(500,811),(520,814),(540,813),(565,808)],right,'right')]:
  ex=int(np.interp(y,*np.array(g).T));lo=max(0,ex-25);hi=min(W,ex+26)
  xx=np.where(dark[y,lo:hi])[0]+lo
  if len(xx):
   runs=np.split(xx,np.where(np.diff(xx)>1)[0]+1)
   run=min(runs,key=lambda r:min(abs(r-ex)))
   edge=ex
  else:edge=ex
  out.append((edge,y))
# At the left spot the run can merge with sleeve ink; smooth only isolated scan spikes.
for curve in [left,right]:
 xs=np.array([p[0] for p in curve],np.float32);xs=cv2.medianBlur(xs.reshape(-1,1),5).ravel()
 for i in range(len(curve)):curve[i]=(int(xs[i]),curve[i][1])
hm=poly([(0,0),(1086,0),(1086,379)]+right+bottom[::-1]+left[::-1]+[(0,379)])&~cm
gy,gx=np.indices((H,W))
shell=cv2.dilate(hm.astype(np.uint8),np.ones((7,7),np.uint8)).astype(bool)&~hm
hm|=shell&((a[:,:,0]<130)|(a[:,:,3]<200))&(gy>379)&(gy<620)&((gx<270)|(gx>785))&~cm
# Sleeve cuts run through the shared armpit stroke; the rounded sleeve roots are tucked behind body.
lm=poly([(0,380),(235,380),(250,570),(330,681),(399,778),(379,837),(240,795),(0,600)])&~hm&~cm
rm=poly([(810,381),(1086,381),(1086,680),(766,760),(671,832),(657,777),(719,684),(810,560)])&~hm&~cm
# Keep the armpit seam on the torso; truncate the sleeve tip inside the hidden round root.
gy,gx=np.indices((H,W))
lm&=~((gy>790)&(((gx-383)**2+(gy-755)**2)>65**2))
rm&=~((gy>790)&(((gx-669)**2+(gy-755)**2)>65**2))
# Floating tie ribbon follows its top and lower silhouette; its attachment is under the knot.
tm=pathmask([('moveto',(538,819)),('lineto',(577,811)),('curveto',(600,834,620,852,653,853)),('curveto',(706,853,740,813,788,805)),('curveto',(852,793,894,840,897,906)),('curveto',(900,938,875,945,847,929)),('curveto',(800,906,784,904,745,919)),('curveto',(701,936,656,943,610,920)),('curveto',(571,901,543,857,529,827)),('close',())])
yy,xx=np.indices((H,W))
ink_or_orange=~((a[:,:,0]>220)&(a[:,:,1]>220)&(a[:,:,2]>220))
tm=cv2.dilate(tm.astype(np.uint8),np.ones((17,17),np.uint8)).astype(bool)&ink_or_orange&(yy>=817)&~((xx<587)&(yy>912))
tm|=(xx>700)&(yy>790)&(yy<950)
tailm=poly([(160,900),(285,900),(355,1000),(345,1028),(330,1086),(310,1100),(180,1110)])
# Ownership partition: no original pixels duplicated, including antialiased boundaries.
remaining=a[:,:,3]>0; masks={}
for n,m in [('coins',cm),('head',hm),('armLeft',lm),('armRight',rm),('tieFlap',tm),('tail',tailm)]:
 masks[n]=m&remaining;remaining&=~m
masks['body']=remaining
# Static upper fragments are edge samples of head/sleeves, never torso.
upper=masks['body']&(gy<675)
near=cv2.dilate(hm.astype(np.uint8),np.ones((13,13),np.uint8)).astype(bool)
for n,m in [('head',upper&near),('armLeft',upper&~near&(gx<535)),('armRight',upper&~near&(gx>=535))]:masks[n]|=m
masks['body']&=~upper
layers={n:extract(m) for n,m in masks.items()}
# Neck and shoulders: a continuous shirt cap, hidden behind head at rest.
shirt=shape([('moveto',(382,708)),('curveto',(402,675,453,654,535,654)),('curveto',(614,654,654,681,678,713)),('lineto',(677,849)),('lineto',(644,899)),('lineto',(409,907)),('lineto',(376,833)),('close',())],WHITE,DARK,15)
# Remove top neck seam: the whole cap is under the head, its lower side merges into original shirt.
layers['body']=hidden_patch(layers['body'],shirt,layers['head'])
# Fill shirt under moving ribbon, using same white and ink at right silhouette.
shirtRibbon=shape([('moveto',(564,821)),('lineto',(664,823)),('curveto',(679,868,684,926,694,982)),('lineto',(599,1004)),('lineto',(569,894)),('close',())],WHITE)
shirtSide=shape([('moveto',(658,780)),('curveto',(672,839,682,918,695,1004))],None,DARK,16)
shirtRibbon.alpha_composite(shirtSide)
# Reconstruct the hanging tie where its floating ribbon covers it.
tieBase=shape([('moveto',(535,819)),('lineto',(568,814)),('curveto',(581,859,592,923,604,974)),('lineto',(551,1038)),('lineto',(504,975)),('curveto',(520,914,532,861,535,819)),('close',())],ORANGE,DARK,13)
shirtRibbon.alpha_composite(tieBase)
layers['body']=hidden_patch(layers['body'],shirtRibbon,layers['tieFlap'])
# Shoulder coverage behind arms. Shape starts inside the head and ends in the armpit.
for name,commands in [
 ('armLeft',[('moveto',(329,681)),('curveto',(361,692,396,722,413,764)),('curveto',(419,783,400,814,377,832)),('lineto',(350,795)),('close',())]),
 ('armRight',[('moveto',(720,682)),('curveto',(685,696,660,726,644,763)),('curveto',(638,785,653,812,675,832)),('lineto',(700,794)),('close',())])]:
 # body patch avoids a transparent wedge after sleeve rotation; ink contour follows the torso side.
 patch=shape(commands,WHITE)
 pass
# Rounded sleeve roots: white semicaps, ink only on their exterior, underneath body and head.
for name,commands in [
 ('armLeft',[('moveto',(324,679)),('curveto',(361,680,400,708,410,742)),('curveto',(425,786,405,812,376,827)),('lineto',(321,775)),('close',())]),
 ('armRight',[('moveto',(723,682)),('curveto',(686,681,653,709,642,744)),('curveto',(629,781,648,808,675,827)),('lineto',(729,776)),('close',())])]:
 cap=shape(commands,WHITE,DARK,14)
 oc=Image.alpha_composite(extract(masks['body']),extract(masks['head']));layers[name]=hidden_patch(layers[name],cap,oc)
# Tail root extends behind trousers, safely inside the silhouette.
root=shape([('moveto',(318,1048)),('curveto',(347,1035,363,1027,375,1038)),('curveto',(388,1051,377,1077,351,1087)),('lineto',(327,1090)),('close',())],WHITE,DARK,15)
layers['tail']=hidden_patch(layers['tail'],root,layers['body'])
# Ear and fist hidden by the bottom coin: paint missing material without changing visible source pixels.
ear=shape([('moveto',(868,292)),('curveto',(907,301,919,320,908,338)),('curveto',(899,356,870,366,848,366)),('close',())],'#ffb8a5',DARK,18)
layers['head']=hidden_patch(layers['head'],ear,layers['coins'])
fist=shape([('moveto',(862,413)),('curveto',(878,381,899,382,912,399)),('curveto',(933,384,957,408,958,435)),('lineto',(931,456)),('close',())],'#714937',DARK,18)
layers['armRight']=hidden_patch(layers['armRight'],fist,layers['coins'])
# ribbon root underneath the knot, same orange and contour.
flapRoot=shape([('moveto',(535,797)),('curveto',(548,790,565,797,575,817)),('lineto',(591,841)),('lineto',(554,858)),('close',())],ORANGE,DARK,12)
pass
# Complete long sleeve segments that are hidden by the giant head in the rest pose.
for n,commands in [
 ('armLeft',[('moveto',(193,467)),('curveto',(236,494,268,555,306,614)),('curveto',(335,653,370,688,395,724)),('curveto',(421,758,408,796,377,824)),('lineto',(292,738)),('curveto',(224,666,166,570,139,510)),('close',())]),
 ('armRight',[('moveto',(847,467)),('curveto',(807,501,780,560,743,618)),('curveto',(715,657,683,690,658,726)),('curveto',(631,762,646,797,676,824)),('lineto',(762,738)),('curveto',(829,664,881,568,910,510)),('close',())])]:
 patch=shape(commands,WHITE,DARK,17)
 oc=Image.alpha_composite(extract(masks['body']),extract(masks['head']))
 layers[n]=hidden_patch(layers[n],patch,oc)
# Torso side contours underneath sleeve and ribbon.
bodyCover=shape([('moveto',(410,707)),('curveto',(467,671,581,671,643,708)),('lineto',(658,779)),('curveto',(674,848,685,930,696,1006)),('lineto',(564,1065)),('lineto',(548,1048)),('lineto',(520,1067)),('curveto',(433,1054,371,1019,332,980)),('lineto',(398,780)),('close',())],WHITE,DARK,16)
# Include only hidden shoulder/ribbon/tail pixels, preserve collar and pants.
oc=Image.new('RGBA',(W,H))
for n in ['tieFlap','head']:oc.alpha_composite(extract(masks[n]))
layers['body']=hidden_patch(layers['body'],bodyCover,oc)
# Restore the tie as it lies over the new shirt fill.
layers['body']=hidden_patch(layers['body'],tieBase,extract(masks['tieFlap']))
pants=shape([('moveto',(355,1016)),('curveto',(341,1054,337,1094,330,1138)),('lineto',(378,1130)),('lineto',(390,1045)),('close',())],'#704835',DARK,17)
pass
ORDER=['tail','armLeft','armRight','body','tieFlap','head','coins']
PIV={'tail':(343,1053),'armLeft':(383,755),'armRight':(669,755),'body':(532,1001),'tieFlap':(551,823),'head':(535,733),'coins':(934,275)}
RANGES={'tail':[-20,20],'armLeft':[-25,25],'armRight':[-25,25],'body':[0,0],'tieFlap':[-15,15],'head':[-8,8],'coins':[0,0]}
def composite(angles={}):
 pad=100 if angles else 0
 im=Image.new('RGBA',(W+2*pad,H+2*pad))
 for n in ORDER:
  layer=layers[n]
  if pad:
   expanded=Image.new('RGBA',im.size);expanded.alpha_composite(layer,(pad,pad));layer=expanded
  if angles.get(n):layer=layer.rotate(angles[n],Image.Resampling.BICUBIC,center=(PIV[n][0]+pad,PIV[n][1]+pad))
  im.alpha_composite(layer)
 return im
for n,im in layers.items():
 im.save(OUT/f'{n}.png')
 im.resize((240,320),Image.Resampling.LANCZOS).save(OUT/'scaled'/f'{n}@2x.png')
 im.resize((120,160),Image.Resampling.LANCZOS).save(OUT/'scaled'/f'{n}.png')
rest=composite();rest.save(OUT/'check-composite.png');diff=np.abs(np.array(rest).astype(int)-a.astype(int));prem=lambda v:np.concatenate((v[:,:,:3]*v[:,:,3:4]/255,v[:,:,3:4]),axis=2)
pm=np.abs(prem(np.array(rest).astype(float))-prem(a.astype(float)))
metrics={'rgba_max':int(diff.max()),'rgba_mean':float(diff.mean()),'differing_pixels':int(np.any(diff,axis=2).sum()),'premultiplied_max':float(pm.max()),'premultiplied_mean':float(pm.mean())}
poses=[('Rest',{}),('Arms outward',{'armLeft':-25,'armRight':25}),('Arms inward',{'armLeft':25,'armRight':-25}),('Head +8 / tail +20 / flap +15',{'head':8,'tail':20,'tieFlap':15}),('Head -8 / tail -20 / flap -15',{'head':-8,'tail':-20,'tieFlap':-15}),('All mixed extremes',{'armLeft':-25,'armRight':-25,'head':8,'tail':-20,'tieFlap':15})]
for bg,suffix in [('#ffffff','white'),('#202633','dark')]:
 sheet=Image.new('RGB',(3*434,2*620),bg);d=ImageDraw.Draw(sheet)
 for i,(label,angles) in enumerate(poses):
  pose=composite(angles)
  if not angles:
   expanded=Image.new('RGBA',(W+200,H+200));expanded.alpha_composite(pose,(100,100));pose=expanded
  tile=Image.new('RGBA',pose.size,bg);tile.alpha_composite(pose);tile=tile.resize((434,556),Image.Resampling.LANCZOS)
  x=(i%3)*434;y=(i//3)*620;sheet.paste(tile.convert('RGB'),(x,y+30));d.text((x+12,y+10),label,fill='#aab3c3' if suffix=='dark' else '#302416')
 sheet.save(OUT/f'check-poses-{suffix}.png')
 if suffix=='white':sheet.save(OUT/'check-poses.png')
rig={'source':str(SRC),'source_sha256':hashlib.sha256(SRC.read_bytes()).hexdigest(),'canvas':{'width':W,'height':H},'coordinate_system':'top-left origin; positive angle is counterclockwise in Pillow','layers':[{'name':n,'file':f'{n}.png','z':z,'pivot':{'pixels':list(PIV[n]),'normalized':[PIV[n][0]/W,PIV[n][1]/H]},'rotation_degrees':RANGES[n]} for z,n in enumerate(ORDER)],'composite_error':metrics,'notes':['All source-visible samples retained; new hidden paint is clipped to opaque occluders at rest.','Full resolution layers are 1086x1448; scaled files are in scaled/.','coins contains all three coins.']}
(OUT/'rig.json').write_text(json.dumps(rig,ensure_ascii=False,indent=2));print(json.dumps(metrics))
