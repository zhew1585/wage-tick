from pathlib import Path
import json
R=Path(__file__).resolve().parents[1]
issues={
'yawning':['armUp ±15° 时肩部仍有短裁切边、双描边；armMouth ±8° 时腋下仍有细接缝。','head ±8° 及混合极限时，捂嘴蹄子后方的脸部补画仍能看到局部轮廓接缝。','tail ±20° 时尾根保留一小段裤边形的描边突起。'],
'eating':['armChopsticks ±15° 时袖口与身体的交界仍有短双线，筷子与蹄子交界仍需手工修整。','head ±6° 及混合极限时，下颌和衣领交界仍有小尖角。','tail ±20° 时尾根保留一小段描边突起。'],
'sunbathing':['armWave ±15°、armDrink ±12° 时肩部仍有局部裁切边或双描边。','head ±6° 及混合极限时肩颈接缝仍可见。','尾根仍有细小描边接缝。']}
for pose in issues:
 out=R/'out'/pose;rig=json.loads((out/'rig.json').read_text());v=json.loads((out/'verification.json').read_text());rig['qa_status']='needs_joint_contour_cleanup';rig['known_issues']=issues[pose];rig['verification_file']='verification.json';rig['notes']=['All nonzero-alpha source-fixed pixels assigned once and retained. Added hidden paint only under source alpha >=253.','Full-canvas aligned layers. headBlink replaces head.','tear/rice inherit head rotation around the head pivot, then apply their local translation. Full-canvas pixel pivots remain in source coordinates.','Positive rotations counterclockwise. Body is stationary; optional sunbathing whole-character sway is a group transform.']
 (out/'rig.json').write_text(json.dumps(rig,ensure_ascii=False,indent=2));v['visual_qa_pass']=False;v['known_issues']=issues[pose];(out/'verification.json').write_text(json.dumps(v,ensure_ascii=False,indent=2))
 lines=[f'# {pose} 分层素材','','状态：已完成分层输出与数值校验，极限姿势接缝未全部通过。不能标为无缝生产素材。','','## 层与关节','','z 从后到前如下。坐标原点左上，正角度逆时针。每层都是 1086×1448 RGBA，在原位置导出。','','| z | 文件 | pivot 像素 | pivot 归一化 | 转动范围 |','|---|---|---|---|---|']
 for e in rig['layers']:lines.append(f"| {e['z']} | {e['file']} | {e['pivot']['pixels']} | {[round(x,6) for x in e['pivot']['normalized']]} | {e['rotation_degrees']}° |")
 if pose=='eating':lines+=['','headBlink.png 替换 head.png。仅眼区变化，alpha 与 head 相同；原图为向上拱的笑眼，变体改成向下收的闭眼弧线，便于看出眨动。rice 的局部上下移动为 ±10 px、透明度 0–1，跟随 head 转动。']
 if pose=='yawning':lines+=['','tear 的局部上下移动为 ±3 px、透明度 0–1，跟随 head 转动。head 不含泪滴。']
 lines+=['','## 源图修复与拆层','','原图和参考图只读，源文件 SHA256 见 rig.json。先输出 source-fixed.png，再分层。参考 cow-work.png 裤子 ROI [380,1020,650,1270] 的 RGB 众数为 [84,55,44]，用于裤子、蹄子、尾毛。按颜色语义分区压平渐变，保留原几何、描边位置和边缘 alpha。近边界使用原色到平涂色的邻域偏移，未对边缘做模糊。墨镜黑、粉色、角的浅黄色分别处理。','','采用可复现的像素所有权分区、深棕描边曲线补画。没有使用生成式重画。body 补齐被头和手臂挡住的衬衫，手臂补肩根，tail 补尾根；head 补脸前遮挡区域。补画限制在上层 alpha≥253 的原遮挡区域，避免静止时改变外轮廓。','','## 校验','',f"静止复原相对 source-fixed.png：RGBA 最大误差 {v['composite_error']['rgba_max']}/255，平均误差 {v['composite_error']['rgba_mean']:.10f}/255，非零差异像素 {v['composite_error']['differing_pixels']}。误差来自原图内部 alpha=253/254 与隐藏补画叠加。原 source-fixed 可见样本逐点保留，ownership.png 覆盖检查通过。",'',f"源像素碎片迁移 {len(rig['fragment_transfers'])} 次，from/to、面积和 bbox 见 rig.json；没有直接删除源样本。",'','连通域按 alpha>0 全部记录；显著游离域定义为非最大连通域、面积≥20 且最大 alpha>32。该筛查不等于关节轮廓通过。','']
 for n,c in v['connected_components'].items():lines.append(f"- {n}：全 alpha 连通域 {c['count']}，显著游离域 {len(c['significant_detached'])}。")
 lines+=['','原图本身有低 alpha 微小散点，完整保留，细项在 verification.json。','','## 视觉复查','','已查看白底与深色底双向极限、混合极限，以及原尺寸关节局部。已修正头部轮廓误归手臂、筷子区域夹带脸色、原渐变分色串色、泪滴与饭粒归属。肩颈等部位仍有以下问题：','']+[f'- {x}' for x in issues[pose]]
 lines+=['','## 文件','','source-fixed.png、全部图层、rig.json、verification.json、check-composite.png、check-poses.png、check-poses-white.png、check-poses-dark.png、check-layers.png、check-joints.png、ownership.png。scaled/ 包含每层 240×320 的 @2x.png 和 120×160 的 .png，使用 Lanczos。','','脚本在 ../../tools-a/，依赖见 requirements.txt。运行 build.py 生成，再运行 verify.py 从磁盘独立校验，最后运行 document.py 更新说明和未通过项。未触碰 tools-b/、lyingFlat、sweating、crying，未修改代码仓库。']
 (out/'README.md').write_text('\n'.join(lines)+'\n')
(R/'tools-a/requirements.txt').write_text('Pillow\nnumpy\nopencv-python-headless\naggdraw\n')
