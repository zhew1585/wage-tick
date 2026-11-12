# eating 分层素材

状态：已完成分层输出与数值校验，极限姿势接缝未全部通过。不能标为无缝生产素材。

## 层与关节

z 从后到前如下。坐标原点左上，正角度逆时针。每层都是 1086×1448 RGBA，在原位置导出。

| z | 文件 | pivot 像素 | pivot 归一化 | 转动范围 |
|---|---|---|---|---|
| 0 | tail.png | [360, 1105] | [0.331492, 0.763122] | [-20, 20]° |
| 1 | body.png | [512, 1010] | [0.471455, 0.697514] | [0, 0]° |
| 2 | armBowl.png | [635, 782] | [0.584715, 0.540055] | [-8, 8]° |
| 3 | head.png | [516, 705] | [0.475138, 0.486878] | [-6, 6]° |
| 4 | armChopsticks.png | [392, 780] | [0.360958, 0.538674] | [-15, 15]° |
| 5 | rice.png | [474, 639] | [0.436464, 0.441298] | [0, 0]° |

headBlink.png 替换 head.png。仅眼区变化，alpha 与 head 相同；原图为向上拱的笑眼，变体改成向下收的闭眼弧线，便于看出眨动。rice 的局部上下移动为 ±10 px、透明度 0–1，跟随 head 转动。

## 源图修复与拆层

原图和参考图只读，源文件 SHA256 见 rig.json。先输出 source-fixed.png，再分层。参考 cow-work.png 裤子 ROI [380,1020,650,1270] 的 RGB 众数为 [84,55,44]，用于裤子、蹄子、尾毛。按颜色语义分区压平渐变，保留原几何、描边位置和边缘 alpha。近边界使用原色到平涂色的邻域偏移，未对边缘做模糊。墨镜黑、粉色、角的浅黄色分别处理。

采用可复现的像素所有权分区、深棕描边曲线补画。没有使用生成式重画。body 补齐被头和手臂挡住的衬衫，手臂补肩根，tail 补尾根；head 补脸前遮挡区域。补画限制在上层 alpha≥253 的原遮挡区域，避免静止时改变外轮廓。

## 校验

静止复原相对 source-fixed.png：RGBA 最大误差 2/255，平均误差 0.0163812663/255，非零差异像素 33098。误差来自原图内部 alpha=253/254 与隐藏补画叠加。原 source-fixed 可见样本逐点保留，ownership.png 覆盖检查通过。

源像素碎片迁移 57 次，from/to、面积和 bbox 见 rig.json；没有直接删除源样本。

连通域按 alpha>0 全部记录；显著游离域定义为非最大连通域、面积≥20 且最大 alpha>32。该筛查不等于关节轮廓通过。

- tail：全 alpha 连通域 12，显著游离域 0。
- body：全 alpha 连通域 80，显著游离域 0。
- armBowl：全 alpha 连通域 14，显著游离域 0。
- head：全 alpha 连通域 79，显著游离域 0。
- armChopsticks：全 alpha 连通域 7，显著游离域 0。
- rice：全 alpha 连通域 1，显著游离域 0。
- headBlink：全 alpha 连通域 79，显著游离域 0。

原图本身有低 alpha 微小散点，完整保留，细项在 verification.json。

## 视觉复查

已查看白底与深色底双向极限、混合极限，以及原尺寸关节局部。已修正头部轮廓误归手臂、筷子区域夹带脸色、原渐变分色串色、泪滴与饭粒归属。肩颈等部位仍有以下问题：

- armChopsticks ±15° 时袖口与身体的交界仍有短双线，筷子与蹄子交界仍需手工修整。
- head ±6° 及混合极限时，下颌和衣领交界仍有小尖角。
- tail ±20° 时尾根保留一小段描边突起。

## 文件

source-fixed.png、全部图层、rig.json、verification.json、check-composite.png、check-poses.png、check-poses-white.png、check-poses-dark.png、check-layers.png、check-joints.png、ownership.png。scaled/ 包含每层 240×320 的 @2x.png 和 120×160 的 .png，使用 Lanczos。

脚本在 ../../tools-a/，依赖见 requirements.txt。运行 build.py 生成，再运行 verify.py 从磁盘独立校验，最后运行 document.py 更新说明和未通过项。未触碰 tools-b/、lyingFlat、sweating、crying，未修改代码仓库。
