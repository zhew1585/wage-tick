# excited 分层素材

状态：待接缝精修，未通过全部极限姿势无缝验收。源文件与代码仓库未修改。

每层 1086×1448 RGBA。z 从后到前：tail / body / armLeft / armRight / head。work 的杯子包含在 armRight。headBlink 替换 head，不能同时叠加。

| z | 文件 | pivot 源像素 | 归一化 | 建议范围 |
|---|---|---|---|---|
| 0 | tail.png | [771, 1065] | [0.7099447513812155, 0.7354972375690608] | [-20, 20]° |
| 1 | body.png | [534, 1023] | [0.49171270718232046, 0.7064917127071824] | [0, 0]° |
| 2 | armLeft.png | [414, 787] | [0.3812154696132597, 0.5435082872928176] | [-15, 15]° |
| 3 | armRight.png | [662, 786] | [0.6095764272559853, 0.5428176795580111] | [-15, 15]° |
| 4 | head.png | [531, 746] | [0.4889502762430939, 0.5151933701657458] | [-8, 8]° |

坐标原点左上，正角度逆时针。body 固定，头 ±8°，手臂 ±15°，尾巴 ±20°。

复原 RGBA 最大误差 2/255，平均 0.0277444980/255。原图内部 alpha 多为 253/254，隐藏补画使复合 alpha 略变。原始可见样本逐点保留，ownership.png 与 verify.py 核对通过。

## 连通域

源像素迁移 105 次，完整 from/to/pixels/bbox 记录在 rig.json。没有删除源像素。原图自带 alpha=1 等极淡离散像素，仍归到最近的对应部件。

导出后检查 alpha>0 全连通域，并检查面积≥20、最大 alpha>32 的游离域。结果见 verification.json。每层全 alpha 连通域数如下，不能把这些数字误读为纯净的单连通域：

- tail: 53 个，显著游离域 0 个。
- body: 75 个，显著游离域 0 个。
- armLeft: 17 个，显著游离域 0 个。
- armRight: 11 个，显著游离域 0 个。
- head: 77 个，显著游离域 0 个。

## 姿势复查

已查看白底、深色底：rest、blink、头/左右臂/尾巴各自双向极限、两组混合极限。另查看 check-joints.png 原分辨率接缝。

已修：头下沿衣领短线归属、误入手臂的裤边/衣摆、手掌后裤子补画、右臂后衬衫补画、尾根分界；新绘补片中不含源样本的游离碎点移除。

仍未解决：肩颈极限姿势局部裁切边/双描边，work 左手后裤子补片色差，尾根极限姿势接缝，excited 右臂下沿细弧线。现有结果不能作为无缝生产素材验收通过。

## 文件

- check-composite.png：静止叠回。
- check-poses.png / check-poses-white.png / check-poses-dark.png：12 格姿势。
- check-layers.png：独立层预览。
- check-joints.png：原尺寸关节局部。
- scaled/：各层及 headBlink 的 240×320 @2x、120×160 Lanczos 版本。
- ownership.png：1 tail、2 body、3 armLeft、4 armRight、5 head，0 透明。仅用于验证。

重建：tools/.venv/bin/python tools/build.py；随后 tools/.venv/bin/python tools/verify.py。依赖 pillow / numpy / opencv-python-headless / aggdraw。

headBlink 用邻域原始面部色彩拟合眼部底色并叠加深棕闭眼弧线，外部像素不变，alpha 与 head 完全一致。补画用 aggdraw 平涂曲线，不使用生成式改图。
