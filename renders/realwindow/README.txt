真窗口图：牛马鼓励器 今日概览 / 目标 / 历史月列表 / 历史月日历 / 设置 (含 macOS 系统红绿灯与窗框)
这是真窗口图，不是离屏预览；仅供看图，不是验收图。

对应提交：318ded7 (feat/restore-original-ui，首页页头红绿灯、返回箭头、标题之间都空 6)。
构建：Debug (ENABLE_HARDENED_RUNTIME=NO)，构建到临时目录，从构建目录直接启动，未装进 /Applications，未运行 scripts/run-debug.sh。
机器 homemac，macOS 15 (Darwin 24.4.0)，屏幕缩放 2x。
截取时间 (+0800)：
  today-full     2026-11-26 00:45:35 +0800
  goals-full     2026-11-26 00:45:37 +0800
  history-full   2026-11-26 00:45:44 +0800
  calendar-full  2026-11-26 00:47:24 +0800
  settings-full  2026-11-26 00:47:26 +0800

截取方式 (全部图相同)：进程内 cacheDisplay。
  经 DYLD_INSERT_LIBRARIES 注入的小工具在 App 进程里对今日概览窗口的窗框视图 (window.contentView.superview，即 NSThemeFrame，
  含标题栏里的系统红绿灯按钮) 调 bitmapImageRepForCachingDisplay(in:) + cacheDisplay(in:to:)，原样存 PNG。
  没有拼接、没有绘制或后期添加任何东西。
  - 换页：进程内对主菜单项调 performActionForItemAtIndex (目标 ⌘2、历史 ⌘3、设置… ⌘,)，等约 1.5s (动画结束) 再截。
  - 历史月日历：在历史月列表上进程内合成一次鼠标点击 (窗口内 180,95pt，即「2026年11月」那一行)，等约 1.5s 再截；之后从日历页按 ⌘, 进设置。
  - 非激活态：红绿灯是灰色圆。进程内调 NSApp.activateIgnoringOtherApps / NSApp.activate / NSRunningApplication.activate 都没让 App 成为激活态
    (isActive 仍为 0、窗口非 key)，所以没有彩色激活态。
  - 不含窗口阴影；也不含窗口圆角遮罩 (cacheDisplay 只画视图内容，四角是直角)。
  - 系统 screencapture -x -o -l <windowid> 再试一次仍失败：「could not create image from window」，退出码 1 (本机没有屏幕录制授权，按要求未去开)。

文件 (2x 像素，1pt = 2px)：
  today-full.png        720x1520  今日概览整窗 (360x760pt)
  goals-full.png        720x1520  「目标 ⌘2」推入后的目标页整窗
  history-full.png      720x1520  「历史 ⌘3」推入后的历史月列表整窗
  calendar-full.png     720x1520  点 11 月那一行后的历史月日历整窗
  settings-full.png     720x1520  「设置… ⌘,」推入后的设置页整窗
  *-titlebar.png        720x160   对应整窗图顶部 80pt 整宽的一条，不缩放。
                                  用 sips 裁 (sips 的 --cropOffset 0 0 会当成居中裁，所以先 sips -p 上下各补 1 行，再 --cropOffset 1 0 裁 160 行)；
                                  已逐像素核对与整窗图顶部 160 行完全一致，且逐张看过含红绿灯与标题。

量度 (pt，相对窗口左上角，按像素墨迹 / 2；右沿 = 最后一个墨迹像素 +1)：
  红绿灯三个圆：x 20–32、40–52、60–72，直径 12，中心 y = 26 (五张图相同；按钮视图 frame 为 x19/39/59、y18、14x16)
  页头框：窗口上沿到分隔线 0–51，中心 25.5
  目标页：箭头墨迹 x 78–85、中心 y 26；标题「目标」墨迹 x 93.5–124.5、中心 y 26
  历史页：箭头墨迹 x 78–85、中心 y 26；标题「历史」墨迹 x 91–124.5、中心 y 26；「按月倒序」x 292–339.5
  设置页：箭头墨迹 x 78–85、中心 y 26；标题「设置」墨迹 x 91.5–124.5、中心 y 26.25
  月日历：箭头墨迹 x 90–97、标题 x 111.5–196.5，中心 y 26 (同原版)
  间隙：红绿灯右沿 72 → 箭头 78 为 6；箭头右沿 85 → 标题：目标 8.5、历史 6、设置 6.5
  与离屏预览 (renders/branch/page) 同名页的页头量度完全相同。

假数据 (只在临时目录，经 CFFIXED_USER_HOME 与拦截 getpwuid 重定向，未读写真实数据目录；启动前后对真实数据目录做 shasum 与 diff -r，未变)：
  2026-10-09 完成引导：月薪 ¥20000，10:00–18:00，饭点 12:00–13:00，双休，不开机自启；关闭桌面悬浮小牛；
  2026-11-12 一笔迟到扣钱 ¥50 (备注「地铁故障」)；
  目标：累计中「Switch 2」¥10000，排队「AirPods Pro」¥1899、「周末去杭州」¥3000、「机械键盘」¥899。
  截图时为凌晨 (未上班)。
