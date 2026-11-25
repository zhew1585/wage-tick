真窗口图：牛马鼓励器 今日概览 / 目标页 (含 macOS 系统红绿灯与窗框)
这是真窗口图，不是离屏预览；仅供看图，不是验收图。

对应提交：84b2b71 (feat/restore-original-ui)，Debug 构建 (ENABLE_HARDENED_RUNTIME=NO)，从构建目录直接启动，未装进 /Applications。
截取时间：today-full 2026-11-26 00:24:28 +0800；goals-full 2026-11-26 00:24:47 +0800。机器 homemac，macOS 15 (Darwin 24.4.0)，屏幕缩放 2x。

截取方式 (全部图)：进程内 cacheDisplay。
  注入的小工具在 App 进程里对今日概览窗口的窗框视图 (window.contentView.superview，即 NSThemeFrame，含标题栏里的系统红绿灯按钮) 调
  bitmapImageRepForCachingDisplay(in:) + cacheDisplay(in:to:)，原样存 PNG。没有拼接、没有后期添加任何东西。
  - 非激活态：红绿灯是灰色圆。进程内调 NSApp.activate / activateIgnoringOtherApps / NSRunningApplication.activate 都被系统拒绝 (返回 0，isActive 仍为 0)，所以取不到彩色激活态。
  - 不含窗口阴影；也不含窗口圆角遮罩 (cacheDisplay 只画视图内容，四角是直角)。
  - 系统 screencapture -l <windowid> [-o] 失败：「could not create image from window」，退出码 1 (本机未给截屏权限，按要求未去开)，故无 -screencapture 图。

文件 (2x 像素，1pt = 2px)：
  today-full.png      720x1520  今日概览整窗 (360x760pt)
  today-titlebar.png  720x160   今日概览顶部 80pt 整宽，从 today-full.png 裁出，不缩放
  goals-full.png      720x1520  主菜单「目标 ⌘2」推入后的目标页整窗 (进程内触发菜单项动作，等约 1.5s 后截)
  goals-titlebar.png  720x160   目标页顶部 80pt 整宽，从 goals-full.png 裁出，不缩放

量度 (pt，相对窗口左上角，按像素墨迹 / 2)：
  红绿灯三个圆：x 20–32、40–52、60–72，直径 12，中心 y = 26 (概览与目标页相同；按钮视图 frame 为 x19/39/59、y18、14x16)
  概览日期行文字墨迹：上沿 y = 48，下沿 y = 58.5
  目标页返回箭头墨迹：x 78–84.5，中心 y = 26
  目标页标题「目标」墨迹：x 92.5–123，中心 y = 26.25
  红绿灯中心 y − 标题墨迹中心 y = −0.25pt (半像素)

假数据 (只在临时目录，经 CFFIXED_USER_HOME 与拦截 getpwuid 重定向，未读写真实数据目录)：
  完成引导：月薪 ¥20000，10:00–18:00，饭点 12:00–13:00，双休，不开机自启；关闭桌面悬浮小牛；
  一个累计中目标「Switch 2」¥10000。截图时为凌晨 (未上班)。
