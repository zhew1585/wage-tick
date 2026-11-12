# yawning 分层素材

状态：已完成分层输出与数值校验，极限姿势接缝未全部通过。不能标为无缝生产素材。

## 层与关节

z 从后到前如下。坐标原点左上，正角度逆时针。每层都是 1086×1448 RGBA，在原位置导出。

| z | 文件 | pivot 像素 | pivot 归一化 | 转动范围 |
|---|---|---|---|---|
| 0 | tail.png | [411, 1090] | [0.378453, 0.752762] | [-20, 20]° |
| 1 | body.png | [560, 1010] | [0.515654, 0.697514] | [0, 0]° |
| 2 | armUp.png | [705, 739] | [0.649171, 0.510359] | [-15, 15]° |
| 3 | head.png | [550, 729] | [0.506446, 0.503453] | [-8, 8]° |
| 4 | armMouth.png | [416, 782] | [0.383057, 0.540055] | [-8, 8]° |
| 5 | tear.png | [688, 431] | [0.633517, 0.297652] | [0, 0]° |

tear 的局部上下移动为 ±3 px、透明度 0–1，跟随 head 转动。head 不含泪滴。

## 源图修复与拆层

原图和参考图只读，源文件 SHA256 见 rig.json。先输出 source-fixed.png，再分层。参考 cow-work.png 裤子 ROI [380,1020,650,1270] 的 RGB 众数为 [84,55,44]，用于裤子、蹄子、尾毛。按颜色语义分区压平渐变，保留原几何、描边位置和边缘 alpha。近边界使用原色到平涂色的邻域偏移，未对边缘做模糊。墨镜黑、粉色、角的浅黄色分别处理。

采用可复现的像素所有权分区、深棕描边曲线补画。没有使用生成式重画。body 补齐被头和手臂挡住的衬衫，手臂补肩根，tail 补尾根；head 补脸前遮挡区域。补画限制在上层 alpha≥253 的原遮挡区域，避免静止时改变外轮廓。

## 校验

静止复原相对 source-fixed.png：RGBA 最大误差 2/255，平均误差 0.0157733280/255，非零差异像素 34302。误差来自原图内部 alpha=253/254 与隐藏补画叠加。原 source-fixed 可见样本逐点保留，ownership.png 覆盖检查通过。

源像素碎片迁移 33 次，from/to、面积和 bbox 见 rig.json；没有直接删除源样本。

连通域按 alpha>0 全部记录；显著游离域定义为非最大连通域、面积≥20 且最大 alpha>32。该筛查不等于关节轮廓通过。

- tail：全 alpha 连通域 6，显著游离域 0。
- body：全 alpha 连通域 83，显著游离域 0。
- armUp：全 alpha 连通域 12，显著游离域 0。
- head：全 alpha 连通域 12，显著游离域 0。
- armMouth：全 alpha 连通域 4，显著游离域 0。
- tear：全 alpha 连通域 1，显著游离域 0。

原图本身有低 alpha 微小散点，完整保留，细项在 verification.json。

## 视觉复查

已查看白底与深色底双向极限、混合极限，以及原尺寸关节局部。已修正头部轮廓误归手臂、筷子区域夹带脸色、原渐变分色串色、泪滴与饭粒归属。肩颈等部位仍有以下问题：

- armUp ±15° 时肩部仍有短裁切边、双描边；armMouth ±8° 时腋下仍有细接缝。
- head ±8° 及混合极限时，捂嘴蹄子后方的脸部补画仍能看到局部轮廓接缝。
- tail ±20° 时尾根保留一小段裤边形的描边突起。

## 文件

source-fixed.png、全部图层、rig.json、verification.json、check-composite.png、check-poses.png、check-poses-white.png、check-poses-dark.png、check-layers.png、check-joints.png、ownership.png。scaled/ 包含每层 240×320 的 @2x.png 和 120×160 的 .png，使用 Lanczos。

脚本在 ../../tools-a/，依赖见 requirements.txt。运行 build.py 生成，再运行 verify.py 从磁盘独立校验，最后运行 document.py 更新说明和未通过项。未触碰 tools-b/、lyingFlat、sweating、crying，未修改代码仓库。
