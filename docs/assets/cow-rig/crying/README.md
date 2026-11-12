# crying 分层素材

状态：已导出，数值校验通过；仍需关节轮廓精修，未通过全部极限姿势无缝验收。

源图与代码仓库均未修改。源图修正版为 source-fixed.png。各层为 1086×1448 RGBA，保持原位置。缩小版为 Lanczos 240×320 与 120×160。

z 从后到前：tail / body / wallet / head / tearLeft / tearRight。

| 层 | pivot 像素 | pivot 归一化 | 转动 |
|---|---|---|---|
| tail | [350, 1158] | [0.322284, 0.799724] | [-15, 15]° |
| body | [520, 1050] | [0.478821, 0.725138] | [0, 0]° |
| wallet | [519, 950] | [0.477901, 0.656077] | [0, 0]° |
| head | [520, 745] | [0.478821, 0.514503] | [-6, 6]° |
| tearLeft | [413, 469] | [0.380295, 0.323895] | [0, 0]° |
| tearRight | [630, 469] | [0.58011, 0.323895] | [0, 0]° |

复原 RGBA 最大误差 0/255，平均误差 0，不同像素数 0。此误差相对 source-fixed.png；lyingFlat 在分层后统一变换并合成，以避免各层插值与整图插值不交换造成的边界误差。

裤子、蹄子、尾巴毛统一为参考 cow-work.png 裤子取样众数 RGB (84,55,44)。颜色区域按近似原色归类后用常量平涂，保留色块边缘、原描边和真实轮廓 alpha。

钱包用内置 imagegen 精确对象编辑生成，只采用局部补片；为棕色对折打开空钱包，左内侧空卡槽、右内侧拉链袋。wallet 包含两手和前臂。钱包后方补画衬衫、领带和裤子。钱包上下 ±4px；泪流以眼角为 pivot 缩放 0.8~1.15，跟随头运动，并以 head alpha 裁切。

已修：躯干大块被误分给头层、头轮廓游离长弧、脸内汗珠矩形底、钱包局部补片透明角、裤子与蹄子色差、下层遮挡区缺色。

连通域检查：所有层 alpha>32 的面积≥20像素的主体外游离域均为 0。原始极淡 alpha 微尘按最近主体归属保留，未直接删除。完整连通域数和像素转移见 verification.json。

已查看白底、深底的各层双向极限及混合极限。遗留问题：

- 头部 ±6° 时颈部共用描边仍有局部小尖角。
- 泪流伸缩必须跟随 head 旋转并以 head alpha 裁切，rig.json 已注明 clip_to；否则下端会越过脸轮廓。

文件：rig.json、verification.json、check-composite.png、check-layers.png、check-poses.png、check-poses-white.png、check-poses-dark.png、scaled/。

重建：使用安装 pillow、numpy、opencv-python-headless、aggdraw 的 Python 运行 tools-b/build.py，再运行 tools-b/verify.py。build.py 可传单个姿势名。不需要重新运行 imagegen，钱包补片保存在 tools-b/wallet-patch.png。
