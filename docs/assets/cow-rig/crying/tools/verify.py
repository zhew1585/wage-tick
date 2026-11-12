from pathlib import Path
from PIL import Image
import numpy as np,cv2,json,hashlib
R=Path(__file__).resolve().parents[1]
issues={
 'lyingFlat':['抬腿 ±10° 时，抬腿与下方静止腿交叠处仍有局部裁切边和补画接缝；未通过无缝生产验收。','头部 ±4° 时衣领附近仍有细小共用描边接缝。'],
 'sweating':['头部 ±4° 时颈部共用描边可见小尖角，需要继续手工修轮廓。','脸内汗珠边缘仍保留少量原始抗锯齿面色，应在最终动画合成背景上再审。'],
 'crying':['头部 ±6° 时颈部共用描边仍有局部小尖角。','泪流伸缩必须跟随 head 旋转并以 head alpha 裁切，rig.json 已注明 clip_to；否则下端会越过脸轮廓。']}
for pose in issues:
 out=R/'out'/pose;rig=json.loads((out/'rig.json').read_text());v=json.loads((out/'verification.json').read_text())
 src=Image.open(out/'source-fixed.png').convert('RGBA');comp=Image.new('RGBA',src.size)
 for item in rig['layers']:
  im=Image.open(out/item['file']).convert('RGBA');assert im.size==(1086,1448);comp.alpha_composite(im)
  n=item['name']
  assert Image.open(out/'scaled'/f'{n}.png').size==(120,160)
  assert Image.open(out/'scaled'/f'{n}@2x.png').size==(240,320)
 diff=np.abs(np.array(comp).astype(int)-np.array(src).astype(int))
 assert int(diff.max())==0
 assert hashlib.sha256(Path(rig['source']).read_bytes()).hexdigest()==rig['source_sha256']
 assert all(x['detached_ge20']==0 for x in v['connected_components'].values())
 v['independent_verification']={'rgba_max':int(diff.max()),'rgba_mean':float(diff.mean()),'all_dimensions_pass':True,'scaled_dimensions_pass':True,'source_hash_pass':True,'significant_detached_components':0}
 v['visual_qa']='needs_contour_cleanup';v['known_issues']=issues[pose]
 rig['qa_status']=v['visual_qa'];rig['known_issues']=issues[pose]
 v['visual_reviewed']=['check-layers.png','check-poses-white.png','check-poses-dark.png']
 (out/'verification.json').write_text(json.dumps(v,indent=2,ensure_ascii=False));(out/'rig.json').write_text(json.dumps(rig,indent=2,ensure_ascii=False))
 text=f'# {pose} 分层素材\n\n状态：已导出，数值校验通过；仍需关节轮廓精修，未通过全部极限姿势无缝验收。\n\n源图与代码仓库均未修改。源图修正版为 source-fixed.png。各层为 1086×1448 RGBA，保持原位置。缩小版为 Lanczos 240×320 与 120×160。\n\n'
 text+='z 从后到前：'+' / '.join(x['name'] for x in rig['layers'])+'。\n\n'
 text+='| 层 | pivot 像素 | pivot 归一化 | 转动 |\n|---|---|---|---|\n'
 for x in rig['layers']:
  text+=f"| {x['name']} | {x['pivot']['pixels']} | {[round(v,6) for v in x['pivot']['normalized']]} | {x['rotation_degrees']}° |\n"
 text+='\n复原 RGBA 最大误差 0/255，平均误差 0，不同像素数 0。此误差相对 source-fixed.png；lyingFlat 在分层后统一变换并合成，以避免各层插值与整图插值不交换造成的边界误差。\n\n'
 text+='裤子、蹄子、尾巴毛统一为参考 cow-work.png 裤子取样众数 RGB (84,55,44)。颜色区域按近似原色归类后用常量平涂，保留色块边缘、原描边和真实轮廓 alpha。\n\n'
 if pose=='lyingFlat':
  text+=f"整体等比放大 {rig['source_scale']['scale']:.6f} 倍，按 alpha>32 包围盒宽度占画布 94% 计算，水平居中，底边保留原位。head 包含枕在脑后的双臂，headBlink 替换 head，不能同时叠加。legUp 按胯部旋转。\n\n"
 elif pose=='sweating':
  text+='laptop 包含两手及可分离前臂；衬衫袖口仍在 body。8 颗汗珠按横坐标从左到右命名，脸内 4 颗也拆出。电脑后方补画平涂衬衫和领带。电脑上下抖动 ±3px，汗珠外飞位移向量长度应限制 ≤15px，并自行淡出循环。\n\n'
 else:
  text+='钱包用内置 imagegen 精确对象编辑生成，只采用局部补片；为棕色对折打开空钱包，左内侧空卡槽、右内侧拉链袋。wallet 包含两手和前臂。钱包后方补画衬衫、领带和裤子。钱包上下 ±4px；泪流以眼角为 pivot 缩放 0.8~1.15，跟随头运动，并以 head alpha 裁切。\n\n'
 text+='已修：躯干大块被误分给头层、头轮廓游离长弧、脸内汗珠矩形底、钱包局部补片透明角、裤子与蹄子色差、下层遮挡区缺色。\n\n连通域检查：所有层 alpha>32 的面积≥20像素的主体外游离域均为 0。原始极淡 alpha 微尘按最近主体归属保留，未直接删除。完整连通域数和像素转移见 verification.json。\n\n已查看白底、深底的各层双向极限及混合极限。遗留问题：\n\n'
 for issue in issues[pose]:text+='- '+issue+'\n'
 text+='\n文件：rig.json、verification.json、check-composite.png、check-layers.png、check-poses.png、check-poses-white.png、check-poses-dark.png、scaled/。\n\n重建：使用安装 pillow、numpy、opencv-python-headless、aggdraw 的 Python 运行 tools-b/build.py，再运行 tools-b/verify.py。build.py 可传单个姿势名。不需要重新运行 imagegen，钱包补片保存在 tools-b/wallet-patch.png。\n'
 (out/'README.md').write_text(text)
 print(pose,'PASS numeric;',v['visual_qa'],[(n,c['alpha_gt0_components'],c['alpha_gt32_components']) for n,c in v['connected_components'].items()])
