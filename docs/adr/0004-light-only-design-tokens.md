# 界面只用设计稿的一套浅色 token，字体随 App 打包

设计稿 (Pencil「牛马鼓励器」) 只定义了一套浅色变量，外壳把它们集中成 token (`WageTick/Theme`：`Palette`、`AppFont`、`Radius`、`Spacing`)，视图只引用 token，不写死颜色。
为了不在深色模式下出现浅色控件配深色窗口的混搭，App 的窗口固定为浅色外观 (`NSApp.appearance = .aqua`)。
菜单不在此列：菜单栏小牛是模板图，跟随系统菜单栏深浅；小牛的左键菜单与屏幕顶部的主菜单 (ADR-0005) 都是 macOS 原生菜单，不做定制，跟随系统深浅色。
字体 Noto Sans SC 与 JetBrains Mono 随 App 打包 (SIL OFL 1.1)；Noto Sans SC 只保留 GB2312 汉字与常用符号 (约 4 MB，完整版约 17 MB)，子集外的字由系统回退到苹方。
大胆版 (2026-11) 起头图另用两种展示字体，同样随 App 打包 (SIL OFL 1.1)：大数字用 Archivo Black，头图标题与小牛气泡用站酷庆科黄油体；后者只保留 GB2312 一级汉字与常用符号 (约 2.7 MB)，其余字回退到苹方。
大胆版每个状态一种头图主色，集中在 `HeroTheme`，视图同样只引用 token。
桌面小组件扩展不打包字体，仍用系统字体。
如果以后要支持深色模式，先在设计稿里补深色变量，再给 `Palette` 加深色取值并去掉固定外观。
