# 悬浮小牛分层素材

悬浮小牛的每个姿势都是一套木偶：几层和原图同尺寸 (1086×1448) 的整幅透明图，按层序叠回去就是原图，各层绕自己的关节转动。
动作定义在 `WageTick/FloatingCow/CowRigs.swift`，画法见 `CowRig.swift` (静止与离屏预览) 与 `FloatingCowLiveLayers.swift` (实时播放，Core Animation)。
入库的是每层 240×320 (@2x) 与 120×160 两份缩小版，在 `WageTick/Assets.xcassets/FloatingCow/<姿势>Rig`，imageset 名为 `Cow<姿势><层>`。

## 来源

- 打工、兴奋、发薪三张原图在 Pencil 设计稿目录的 `images/` 里 (`cow-work.png`、`cow-excited.png`、`cow-payday.png`)。
- 打哈欠、干饭、躺平、晒太阳、冒汗、大哭六张由 Codex 参照前三张用图像生成画出，再统一裤子等深棕色、压平渐变；躺平放大到占画布宽约 94%，大哭手里的钱包重画过。生成提示词见 `crying/tools/imagegen-prompt.txt`。
- 拆层、补画被遮住的部分、挪回游离碎片、核对复原误差都由脚本完成 (各姿势目录下的 `tools/`，同一套做法)。

## 目录

每个姿势一个目录 (`paid`、`working` 用 `work`、`excited`、`yawning`、`eating`、`lyingFlat`、`sunbathing`、`sweating`、`crying`)：
- `rig.json`：各层文件名、层序 (从后到前)、关节的像素坐标与归一化坐标、拆图时测过的转动范围。代码里的关节坐标照抄这里的像素坐标。
- `README.md`：该套的做法与遗留问题 (有的话)。
- `tools/`：拆层脚本 (依赖 Python 3 + pillow、numpy、opencv-python-headless)。

`tools/import_rig.sh <scaled 目录> <姿势名>` 把一套缩小版装进素材库。

## 已知限制

各层转动超过约 ±15° 时，肩颈、尾根、飘带根部会露出裁切边或双描边，代码里的幅度都压在这以内。
打哈欠伸懒腰的手臂外伸到最大时，内侧有一小段描边偏淡；晒太阳拿饮料的肩部有很小的白色楔形。实际显示尺寸下基本看不出。
