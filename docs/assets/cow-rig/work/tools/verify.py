from pathlib import Path
from PIL import Image
import numpy as np,cv2,json,hashlib
R=Path(__file__).resolve().parents[1]
for pose in ['work','excited']:
 O=R/'out'/pose;rig=json.loads((O/'rig.json').read_text());srcpath=Path(rig['source']);assert hashlib.sha256(srcpath.read_bytes()).hexdigest()==rig['source_sha256'];a=np.array(Image.open(srcpath).convert('RGBA'));owner=np.array(Image.open(O/'ownership.png'));assert np.array_equal(owner>0,a[:,:,3]>0)
 report={'source_hash_unchanged':True,'source_samples_retained':True,'dimensions_pass':True,'layers':{}}
 for i,entry in enumerate(rig['layers'],1):
  n=entry['name'];im=Image.open(O/entry['file']);b=np.array(im);assert im.size==(1086,1448) and im.mode=='RGBA';assert np.array_equal(a[owner==i],b[owner==i]),n
  for suffix,size in [('@2x',(240,320)),('',(120,160))]:assert Image.open(O/'scaled'/f'{n}{suffix}.png').size==size
  count,labels,stats,_=cv2.connectedComponentsWithStats((b[:,:,3]>0).astype('uint8'),8);main=1+int(np.argmax(stats[1:,4]));frags=[]
  for j in range(1,count):
   if j==main:continue
   m=labels==j;frags.append({'area':int(m.sum()),'bbox':stats[j,:4].tolist(),'max_alpha':int(b[:,:,3][m].max()),'source_samples':int((m&(owner==i)).sum())})
  significant=[f for f in frags if f['area']>=20 and f['max_alpha']>32]
  report['layers'][n]={'all_alpha_components':count-1,'significant_detached_components':significant,'fragments':frags}
 for suffix,size in [('@2x',(240,320)),('',(120,160))]:assert Image.open(O/'scaled'/f'headBlink{suffix}.png').size==size
 assert np.array_equal(np.array(Image.open(O/'head.png'))[:,:,3],np.array(Image.open(O/'headBlink.png'))[:,:,3])
 report['blink_alpha_matches_head']=True
 comp=Image.new('RGBA',(1086,1448))
 for entry in rig['layers']:comp.alpha_composite(Image.open(O/entry['file']))
 diff=np.abs(np.array(comp).astype(int)-a.astype(int));report['composite_error']={'rgba_max':int(diff.max()),'rgba_mean':float(diff.mean()),'differing_pixels':int(np.any(diff,axis=2).sum())};assert int(diff.max())<=3
 report['significant_fragments_pass']=all(not d['significant_detached_components'] for d in report['layers'].values())
 (O/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
 rig['qa_status']='needs_joint_contour_cleanup';rig['verification_file']='verification.json';rig['known_issues']=['At extreme poses, small shoulder/neck clipping edges and local double contours remain.','Work: exposed flat trousers backfill behind left hand has a visible color boundary.','Tail root at +/-20 degrees retains small contour/AA seams.','Excited: right-arm lower border retains a thin curved seam at extreme rotation.'];(O/'rig.json').write_text(json.dumps(rig,ensure_ascii=False,indent=2))
 lines=[f'# {pose} 分层素材', '', '状态：待接缝精修，未通过全部极限姿势无缝验收。源文件与代码仓库未修改。', '', '每层 1086×1448 RGBA。z 从后到前：tail / body / armLeft / armRight / head。work 的杯子包含在 armRight。headBlink 替换 head，不能同时叠加。', '', '| z | 文件 | pivot 源像素 | 归一化 | 建议范围 |', '|---|---|---|---|---|']
 for e in rig['layers']:lines.append(f"| {e['z']} | {e['file']} | {e['pivot']['pixels']} | {e['pivot']['normalized']} | {e['rotation_degrees']}° |")
 lines += ['', '坐标原点左上，正角度逆时针。body 固定，头 ±8°，手臂 ±15°，尾巴 ±20°。', '', f"复原 RGBA 最大误差 {diff.max()}/255，平均 {diff.mean():.10f}/255。原图内部 alpha 多为 253/254，隐藏补画使复合 alpha 略变。原始可见样本逐点保留，ownership.png 与 verify.py 核对通过。", '', '## 连通域', '', f"源像素迁移 {len(rig['fragment_transfers'])} 次，完整 from/to/pixels/bbox 记录在 rig.json。没有删除源像素。原图自带 alpha=1 等极淡离散像素，仍归到最近的对应部件。", '', '导出后检查 alpha>0 全连通域，并检查面积≥20、最大 alpha>32 的游离域。结果见 verification.json。每层全 alpha 连通域数如下，不能把这些数字误读为纯净的单连通域：', '']
 for n,d in report['layers'].items():lines.append(f"- {n}: {d['all_alpha_components']} 个，显著游离域 {len(d['significant_detached_components'])} 个。")
 lines += ['', '## 姿势复查', '', '已查看白底、深色底：rest、blink、头/左右臂/尾巴各自双向极限、两组混合极限。另查看 check-joints.png 原分辨率接缝。', '', '已修：头下沿衣领短线归属、误入手臂的裤边/衣摆、手掌后裤子补画、右臂后衬衫补画、尾根分界；新绘补片中不含源样本的游离碎点移除。', '', '仍未解决：肩颈极限姿势局部裁切边/双描边，work 左手后裤子补片色差，尾根极限姿势接缝，excited 右臂下沿细弧线。现有结果不能作为无缝生产素材验收通过。', '', '## 文件', '', '- check-composite.png：静止叠回。', '- check-poses.png / check-poses-white.png / check-poses-dark.png：12 格姿势。', '- check-layers.png：独立层预览。', '- check-joints.png：原尺寸关节局部。', '- scaled/：各层及 headBlink 的 240×320 @2x、120×160 Lanczos 版本。', '- ownership.png：1 tail、2 body、3 armLeft、4 armRight、5 head，0 透明。仅用于验证。', '', '重建：tools/.venv/bin/python tools/build.py；随后 tools/.venv/bin/python tools/verify.py。依赖 pillow / numpy / opencv-python-headless / aggdraw。', '', 'headBlink 用邻域原始面部色彩拟合眼部底色并叠加深棕闭眼弧线，外部像素不变，alpha 与 head 完全一致。补画用 aggdraw 平涂曲线，不使用生成式改图。']
 (O/'README.md').write_text('\n'.join(lines)+'\n');print(pose,report['composite_error'],'source retained',report['source_samples_retained'],'significant fragments',report['significant_fragments_pass'])
