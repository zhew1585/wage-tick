# lyingFlat 分层素材

状态：已导出，数值校验通过；仍需关节轮廓精修，未通过全部极限姿势无缝验收。

源图与代码仓库均未修改。源图修正版为 source-fixed.png。各层为 1086×1448 RGBA，保持原位置。缩小版为 Lanczos 240×320 与 120×160。

z 从后到前：tail / body / legUp / head。

| 层 | pivot 像素 | pivot 归一化 | 转动 |
|---|---|---|---|
| tail | [380, 1347] | [0.349908, 0.930249] | [-15, 15]° |
| body | [573, 1296] | [0.527624, 0.895028] | [0, 0]° |
| legUp | [619, 1349] | [0.569982, 0.93163] | [-10, 10]° |
| head | [379, 1191] | [0.348987, 0.822514] | [-4, 4]° |

复原 RGBA 最大误差 0/255，平均误差 0，不同像素数 0。此误差相对 source-fixed.png；lyingFlat 在分层后统一变换并合成，以避免各层插值与整图插值不交换造成的边界误差。

裤子、蹄子、尾巴毛统一为参考 cow-work.png 裤子取样众数 RGB (84,55,44)。颜色区域按近似原色归类后用常量平涂，保留色块边缘、原描边和真实轮廓 alpha。

整体等比放大 1.049168 倍，按 alpha>32 包围盒宽度占画布 94% 计算，水平居中，底边保留原位。head 包含枕在脑后的双臂，headBlink 替换 head，不能同时叠加。legUp 按胯部旋转。

已修：躯干大块被误分给头层、头轮廓游离长弧、脸内汗珠矩形底、钱包局部补片透明角、裤子与蹄子色差、下层遮挡区缺色。

连通域检查：所有层 alpha>32 的面积≥20像素的主体外游离域均为 0。原始极淡 alpha 微尘按最近主体归属保留，未直接删除。完整连通域数和像素转移见 verification.json。

已查看白底、深底的各层双向极限及混合极限。遗留问题：

- 抬腿 ±10° 时，抬腿与下方静止腿交叠处仍有局部裁切边和补画接缝；未通过无缝生产验收。
- 头部 ±4° 时衣领附近仍有细小共用描边接缝。

文件：rig.json、verification.json、check-composite.png、check-layers.png、check-poses.png、check-poses-white.png、check-poses-dark.png、scaled/。

重建：使用安装 pillow、numpy、opencv-python-headless、aggdraw 的 Python 运行 tools-b/build.py，再运行 tools-b/verify.py。build.py 可传单个姿势名。不需要重新运行 imagegen，钱包补片保存在 tools-b/wallet-patch.png。
