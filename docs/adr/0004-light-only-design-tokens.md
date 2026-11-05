# 界面只用设计稿的一套浅色 token，字体随 App 打包

设计稿 (Pencil「牛马鼓励器」) 只定义了一套浅色变量，外壳把它们集中成 token (`WageTick/Theme`：`Palette`、`AppFont`、`Radius`、`Spacing`)，视图只引用 token，不写死颜色。
为了不在深色模式下出现浅色控件配深色窗口的混搭，App 的窗口与菜单固定为浅色外观 (`NSApp.appearance = .aqua`)。
菜单栏小牛是模板图，仍跟随系统菜单栏深浅。
字体 Noto Sans SC 与 JetBrains Mono 随 App 打包 (SIL OFL 1.1)；Noto Sans SC 只保留 GB2312 汉字与常用符号 (约 4 MB，完整版约 17 MB)，子集外的字由系统回退到苹方。
如果以后要支持深色模式，先在设计稿里补深色变量，再给 `Palette` 加深色取值并去掉固定外观。
