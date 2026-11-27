# 界面规则检查

把 2026-11-25 至 26 还原旧版界面这几轮踩过的坑，落成每次都跑的硬性检查。
入口只有一个：`scripts/checks/run.sh`。

| 命令 | 跑什么 | 在哪跑 |
|---|---|---|
| `scripts/checks/run.sh static` | 自测，再查当前源码 | 哪里都行；CI「核心测试」里每次跑 |
| `scripts/checks/run.sh ui` | 渲染、量页头、真窗口与交互回归 | 要 macOS 与 Xcode；CI「App 编译与启动」里跑 |
| `scripts/checks/run.sh all` | 两样都跑 | 本机 Mac |

退出码：0 通过，1 有规则不过，2 blocked。
blocked 表示缺图、缺清单、缺工具，没法判断，不算通过。

## 文件

- `ui_lint.py`、`ui-lint.json`：静态规则，只读源码。
- `ui_geometry.py`、`ui-geometry.json`：读渲染图的像素量页头、认红绿灯、查空白图与产物清单。
- `ui_home.py`、`ui-home.json`：读首页各状态的渲染图，查每个区域的位置是否一致。
- `ui_font.py`：FONT-BUNDLED 的判定，读 App 报出的字体报告 (离屏渲染与真窗口都用它)。
- `selftest.py`：检查脚本自己的回归。
  每条静态规则配一处故意违规的改动，每条几何规则配一张现画的反例图，都必须被抓到。
  仓库里不放图片：反例图只有色块，位置取自当时真实渲染图上量到的数值，自测时画进临时目录。
- `ui-checks-mac.sh`：Mac 上的一次完整运行：编 Debug、离屏渲染、真窗口截图、交互回归、真实数据目录校验。
- `ui_drive.py`：拉起 App、截真窗口图、跑交互回归，量该不滚动的页面放不放得下 (由 `ui-checks-mac.sh` 调用)。
- `harness/drive.m`：注入 Debug 版 App 的库，在 App 进程里合成按键、点击与输入，截窗口图，读窗口状态、滚动区域与辅助功能树，报出 App 实际用的字体文件。
- `harness/FakeState.swift`：和核心源码一起编成小程序，用核心的公开命令造假状态。
- `selftest-mac.sh`：`ui-checks-mac.sh` 自己的回归，逐条做故意违规的源码改动，慢，不进 CI。

## 静态规则 (`ui_lint.py`)

| 规则 | 对应的坑 | 判定 | 误报边界 |
|---|---|---|---|
| RESTORE-BOLD | 第 2 版只换了配色，头图、胶囊按钮、展示字体都还在，被否 | 外壳里出现 `HeroTheme`、`BoldHero`、`.pill(`、`AppFont.heavy` 等，或打包了 Archivo Black、站酷字体，就不过 | 只查 `WageTick/`、`WageTickWidgets/`；核心里的同名数据不查 |
| RESTORE-EARNED | 「已到手」页先保留后被否 | 外壳里出现 `GoalEarned`、`showsEarned`、「已到手」就不过 | 注释里写这三个字也会报，外壳里本来就不该再提 |
| RESTORE-WINDOWS | 第 1 版要恢复三个独立窗口，被否 | 外壳里出现三个窗口控制器或 `PageWindow` 就不过 | 无 |
| CORE-KEPT | 还原界面时不能把核心的数据与计算一起删 | 核心里必须还有 `ui-lint.json` 列的 18 个符号；`@Test` 不少于 618 | 核心里改名要同步改清单；测试数是下限，只增不减 |
| COPY-LEAVE | 请假扣薪文字被改成「−¥1000」，Allen 定按原版「= ¥1000」 | `LeaveForm.deductionText` 必须是 `"= \(Format.money(…"` | 单元测试也断言了同一件事，这条是双保险 |
| HDR-CALLER | 页头在各页不一致；新页面漏掉 | 每处 `PageHeader(` 都要传 `back:`；目标、历史月列表、设置传 `isRoot: true`，月日历、单日详情不传；没登记的页面用了页头就不过 | 只认一行写完的调用；换行写要调整规则 |
| HDR-TITLEBAR | 页头排在红绿灯下面多出的一行里，看着偏下 | 今日概览窗口用 `.tall` (52)；概览内容从 28 排起；页头高度取 `.tall`；页面预览上方不另留一行 | 标题栏方案变了要改规则；现方案 Allen 2026-11-26 00:38 已接受 |
| NAV-COVER | 页面盖着时底下的概览还能点、能聚焦；钉住按钮叠在滑动的页头上 | `TodayPanelView` 的 `body` 里必须有 `.disabled(content.page != nil)`、`.accessibilityHidden(…)`、`PinButton(`；控制器里不能有 `PinButton(` | 只看写法，真实效果由交互回归与人工确认 |
| NAV-ESC | Esc 兜底直接跳回概览或关窗；请假表单过零点后第一次 Esc 白按 | `handleCancel()` 里要先 `goBackInside(page)`、要处理 `content.route != .home`；`refresh()` 里请假表单没了要回概览 | 同上 |
| NAV-SHEET | 开着弹出表单时 ⌘1 ⌘2 ⌘3 ⌘, 会退页或换页，没填完的丢了 | `show()` 里 `push(page)` 与 `pop()` 都要受 `hasSheet` 保护 | 同上 |
| NAV-DOCK | 点 Dock 图标把人从页面踢回概览 | `applicationShouldHandleReopen` 里必须是 `show(returnsToOverview: false)` | 同上 |
| NAV-GOALCARD | 还原后概览上累计中目标的卡片点不了 | `GoalCardView` 的 `.active` 分支必须包 `Button(action: openGoals)` | 同上 |
| NAV-HISTORY | 历史页返回时内容先消失；进来不是月列表 | `disappear()` 里不能清空快照与选中项；`appear()` 里要重置；要有 `goBack()` | 同上 |
| NAV-TIMER | 页面退出去后发命令，把停掉的定时器又拉起来 | `HistoryPage`、`GoalsPage` 的 `refresh()` 里要有 `guard isActive else { return }` | 同上 |
| FONT-BUNDLED | 2026-11-26：开发机装了同名字体 (`~/Library/Fonts/NotoSansSC.ttf`)，App 按字族名取字取到的是装的那份，预览和检查量的不是用户看到的排版，引导页在用户机器上要滚动 | 外壳里不能按字族名或字体名建字体 (`.family:`、`kCTFontFamilyNameAttribute`、`NSFontFamilyAttribute`、`Font.custom(`、`.custom("…`、`CTFontCreateWithName(`、`NSFont(name:`、`withFamily:`)；`AppFont.swift` 里要有 `CTFontManagerCreateFontDescriptorsFromURL`，`makeFont` 里要用 `CTFontCreateWithFontDescriptor` | 只看写法；注释里写这些名字也会报。实际取到哪个文件由 `run.sh ui` 的同名规则量 |
| GOALS-ROW | 2026-11-26：目标管理页累计中一行带「累计中」标签，名称被挤得只剩两三个字；Allen 定去掉标签，名称放不下时悬停滚动 | `WageTick/Goals/` 里不能有 `Text("累计中")`，目标名称不能写成 `Text(row.name)`、`Text(card.name)`；攒钱队列两种行与已完成行都要用 `HoverMarqueeText` | 只看写法；滚动的节奏、移开后复原靠人工验收 |
| GOALS-ROW | 2026-11-27 实机验收：悬停时编辑、删除按钮把名称挤短一大截，滚动的名称右边还空着一段；Allen 定为三种行 (累计中、排队中、已完成) 同一个三行结构，按钮在第三行最右 | `GoalRowLayout` 的第一行只有名称和金额，按钮跟在第三行小字后面，行高 76；`GoalQueueList` 用它 2 处、`GoalsView` 用它 1 处；`HoverMarqueeText` 先占满一栏再量宽 | 只看写法；名称一栏悬停前后是否等宽、三种行是否对齐靠 Playtest 在渲染图上量 |
| GOALS-LIMIT | 2026-11-26：目标金额不设上限，预计完成日一天一天往后数，金额极大时 App 卡死；后来定为超过 1 年只说「大于 1 年」 | `Validation.goalAmountLimit` 是 999999；`finishDay` 开头要有 `guard days <= Decimal(ActiveGoalCard.estimateDayLimit)`，逐天数的截止日也按它算；核心里只有 `finishDay` 的函数体里能调逐天数的 `attendanceDay` (按行号判断) | 上限是否生效、超大金额是否立即返回由 `GoalAmountLimitTests` 测 |
| REPO-LOCAL | `roles/`、`docs/spec/` 只放本机 | `git ls-files roles docs/spec` 必须为空 | 不在 git 仓库里时不查 |

成功路径：`python3 scripts/checks/ui_lint.py` 在当前源码上输出「ui_lint: 通过」，退出码 0。
故意违规：`selftest.py` 里的 53 处改动，每处都必须让 `ui_lint.py` 以退出码 1 报出对应规则 (FONT-BUNDLED 两处：`AppFont.makeFont` 改回按字族名取字；视图里用 `Font.custom("Noto Sans SC", …)`)。

静态规则看的是源码的写法，能挡住「改回去」，挡不住「换一种写法写错」。
导航那几条的真实行为，靠下面的交互回归与人工验收。

## 几何与产物规则 (`ui_geometry.py`)

图是 2 倍。
离屏预览 816 px 宽，四周留 24 pt 白边；真窗口图 720 px 宽，没有白边。
坐标都换算成相对窗口左上角的 pt。
「墨迹」指亮度低于 110 的像素，也就是墨色的箭头与标题；灰色的说明文字不算。

| 规则 | 对应的坑 | 适用的图 | 判定与阈值 | 误报边界 |
|---|---|---|---|---|
| HDR-FRAME | 页头排在多出的一行里 (`73f794d`) | 目标、历史、设置、月日历、单日详情 | 页头分隔线在 52 pt ±1.5 | 页头下沿换了颜色要调亮度范围 |
| HDR-BACK | 推进来的页面没有返回 | 同上 | 页头里第一段墨迹宽不超过 9 pt，且后面还有标题 | 标题第一个字很窄 (如「一」) 时可能被当成箭头 |
| HDR-VCENTER | 返回与标题偏下 | 同上 | 墨迹中心偏离页头框中心不超过 1 pt；真窗口图上红绿灯中心与标题中心相差不超过 1 pt | 原版月日历是 +0.5 |
| HDR-LIGHTS-GAP | 箭头离红绿灯 6 pt，Allen 说太近 (`84b2b71`) | 同上 | 箭头墨迹左沿到红绿灯右沿 (72) 必须大于 6 | 6 是被否掉的值，不是合格线；合格看 HDR-X 与人工 |
| HDR-X | 标题比原版靠右 26 (`947880d`)；三处间距压在边界上 | 目标、目标空状态、历史月列表、设置 | 箭头左沿 85 ±1；箭头到标题 7.5 至 12 (各字左侧留白不同，「目」最宽)；标题左沿不超过 105 | 85 是 `d107b63` 的设计值，Allen 看过真窗口图后若调整，要改 `ui-geometry.json` |
| HDR-X | 下一级页头要保持原版 | 月日历、单日详情 | 箭头左沿 90 ±1；箭头到标题 13 至 18；标题左沿不超过 114 | 原版实测值 |
| HDR-CONSISTENT | 目标、历史、设置的页头不一致 | 同一类的几页之间 | 箭头左沿相差不超过 0.5；墨迹中心 y 相差不超过 0.75 | 无 |
| HDR-LIGHTS | 标题栏方案被悄悄改掉 | 真窗口图 | 三个红绿灯右沿在 72 ±1.5，中心 y 在 26 ±1 | 系统换了红绿灯尺寸要重新量；找圆的范围从左上 4pt 起，标题栏改回 28 高 (红绿灯在 8–60、中心 14) 时也能找到并报这一条 |
| IMG-BLANK | 近景裁成了空白图还照样提交 (`3d73c4c`) | 所有图 | 与底色不同的像素不到 0.3% 就不过 | 只看图的上部 |
| IMG-KIND | 离屏预览不画红绿灯，不能冒充真窗口图 | 所有图 | 标成离屏的图里不能有红绿灯；标成真窗口的必须有三个；页面图与真窗口图的图宽要对得上 | 认的是红绿灯的位置与大小，不认颜色；离屏预览里的弹出表单本来就比窗口窄，不查图宽，也不找红绿灯 (表单标题的字会被认成圆) |
| IMG-VERSION | 拿旧提交的图当新图 | 带清单的整套图 | `manifest.json` 里的提交必须是当前 `HEAD` | 清单要由出图的脚本写 |
| IMG-MANIFEST | 图没标明版本、时间、截法 | 同上 | 清单必须有 `commit`、`kind`、`capturedAt`、`method`、`files` | 无 |
| BLOCKED | 缺图、缺清单时当成通过 | 同上 | 整套检查不给清单、清单里的图不在、该有的图缺了，都退出码 2 | 真窗口图里月日历等几页可以没有，会记一行 MANUAL |

成功路径：`python3 scripts/checks/ui_geometry.py --kind offscreen --dir <页面预览目录> --manifest <清单>` 输出「ui_geometry: 通过」，退出码 0。
故意违规：`selftest.py` 按下表现画反例图，确认每张都被对应的规则抓到。

| 反例 | 位置数值来自 | 必须被抓到 |
|---|---|---|
| 页头排在多出的一行里：分隔线 79，没有箭头 | `73f794d` 的渲染图 | HDR-FRAME |
| 标题比原版靠右 26：箭头 90，标题 114 | `947880d` 的渲染图 | HDR-X |
| 箭头离红绿灯 6：箭头 78，离屏与真窗口各一 | `84b2b71` 的渲染图与真窗口图 | HDR-LIGHTS-GAP、HDR-X |
| 页头没有箭头 | 构造 | HDR-BACK |
| 返回与标题偏下 3 | 构造 | HDR-VCENTER |
| 目标与历史的箭头差 1 | 构造 | HDR-CONSISTENT |
| 红绿灯在 8 至 60、中心 14 | 28 高标题栏的系统位置 | HDR-LIGHTS |
| 只有底色的图 | `3d73c4c` 里裁成空白的近景 | IMG-BLANK |
| 图宽对不上；离屏宽的图里有红绿灯；真窗口宽的图里没有 | 构造 | IMG-KIND |
| 清单里的提交不是 `HEAD`，还缺 `method` | 构造 | IMG-VERSION、IMG-MANIFEST |
| 不给清单；缺图 | 构造 | BLOCKED (退出码 2) |

必须放行的：原版月日历页头 (`9c69fd3`：箭头 90 至 96.5，标题 112)；当前设计的首页页头 (`d107b63`：箭头 85 至 91.5，离红绿灯 13)，离屏与真窗口各一组。
还有比窗口窄的弹出表单图：表单标题的三个字正好在红绿灯的位置上，不能被认成红绿灯 (几何检查头一回在整套渲染图上跑时把它们误报成 IMG-KIND)。
反例图没有抗锯齿和真实字形，只验证规则的判定；对真实渲染的判定由 `run.sh ui` 在当前提交上跑、由 `selftest-mac.sh` 做故意违规。

### 1 倍屏

阈值是在 2 倍屏上定的。
GitHub 托管的 macOS runner 是 1 倍屏，PR #34 头一回在上面跑时全部误报：离屏预览出的是 1 倍图 (408 px 宽)，箭头左沿 86 与 91 (2 倍屏 85 与 90)，墨迹中心偏移 +1.5 至 +2.0 (当时 2 倍屏上 +0.75)。
现在的做法：离屏预览的倍数从图宽认；真窗口图总是存成 2 倍 (1 倍屏上是放大的)，倍数由注入库报出、写进清单的 `screenScale`。
1 倍屏上垂直容差放到 ±2.5 pt，箭头左沿容差多放 0.5 pt (`ui-geometry.json` 的 `oneX`)，其余规则不变，输出里会打一行 NOTE。
2 倍屏上的图不受影响；1 倍屏的真窗口图如果没标倍数，会按 2 倍屏的阈值报 HDR-VCENTER。

当时把垂直方向多出的约 1 pt 归因为「1 倍屏字按整像素对齐」。
2026-11-26 查出那台 2 倍屏开发机装了另一版 Noto Sans SC，量的一直是被顶替的字体，CI 上用的才是打包字体。
同一台 2 倍屏机器换成打包字体 (`AppFont` 修好之前) 量到的墨迹中心偏移是 +1.5 至 +1.75，和 CI 上 1 倍屏的 +1.5 至 +2.0 只差 0 至 0.25：多出的那 1 pt 主要是字体，1 倍屏本身最多占 0.25 左右。
页头标题按打包字体上提 1 pt 之后，2 倍屏上偏移是 +0.5 至 +0.75 (对红绿灯 0 至 +0.25)。
横向的箭头左沿 86 与 91 不是文字 (箭头是图标)，和字体无关，可能才是 1 倍屏取整。
`oneX` 先不动：要等 CI 在修好的字体下跑出 1 倍屏的实测值，再决定垂直容差能不能收回 ±1。

### 关于美观

HDR-LIGHTS-GAP 只保证不退回被 Allen 否掉的 6 pt。
HDR-X 只保证和当前的设计值一致，不代表这个设计值已经被认可。
留白是否美观，要 Allen 看真窗口图确认；检查每次都会打印这一句。

## 首页区域 (`ui_home.py`)

2026-11-26 首页改版时 Allen 定的：首页七个区域在所有状态下高度、位置都一样，换状态只换区域里的内容。
之前首页是按内容高度一段段叠起来的，目标数量、是否已下班、有没有提示条都会让下面的区域上下挪，留白时大时小 (1 个目标时空 125 pt)。

图是首页各状态的离屏渲染 (`wagetick_render_panel_previews`)，整窗 360×574，四周各留 24 pt 白边。
认区域靠底色，位置在 `ui-home.json`，与 `WageTick/Theme/Metrics.swift` 的 `HomeLayout` 是同一组数，改一处要改两处。

| 规则 | 对应的坑 | 判定与阈值 | 误报边界 |
|---|---|---|---|
| HOME-SIZE | 窗口高度被改掉，或预览没按整窗出图 | 图是 360×574 四周各加 24 的 1 倍或 2 倍图 | 窗口尺寸确实要改时，同步改 `ui-home.json` |
| HOME-BAND | 某个状态下区域被内容顶开、挪位或变高 | 进度条 238–248 (已下班是按钮 216–264；白干中是 loss 色的进度条)、统计卡 280–344、攒钱队列 356–460、情绪按钮 472–516、入口栏 528–574，各 ±1 | 认的是底色：换了卡片底色要改 `colors`；进度条的填充色按状态认 (白干中 loss，其余 money)，用错颜色会报「没找到进度条」；休息日没有进度区 (`noProgress`)；没有情绪按钮的状态登记到 `noActions` |
| HOME-UNPAID (像素) | 2026-11-27 实机验收：白干中「终于下班了」占着进度区，下面只剩一颗请假；Allen 定为进度区放白干进度条，「终于下班了」挪到情绪按钮区 | 登记在 `unpaidWork` 的状态：进度区不能是墨色按钮，情绪按钮区左边必须是墨色主按钮；登记在 `offWork` 的状态进度区必须是墨色按钮；其余状态情绪按钮区左边不能是墨色 | 认的是底色，不认字；加了新的白干中、已下班预览要登记 |
| BLOCKED | 缺图、缺清单时当成通过 | 清单里的提交必须是 `HEAD`，`states` 里列的图都要在 | 加了新的首页预览状态要登记到 `states`，不登记就查不到它 |

成功路径：`python3 scripts/checks/ui_home.py --dir <首页预览目录> --manifest <清单>` 输出「ui_home: 通过」，退出码 0。
故意违规：`selftest.py` 现画只有色块的首页图，逐个区域挪位置 (统计卡下移 4、目标卡变高、空状态卡变矮、按钮被推下去、入口栏不贴底、进度条挪位、白干按钮撑满进度区、窗口改回 760)，每个都必须被抓到。

同一批图里的扣钱、请假表单 (`F5-*`、`F6-*`) 另用 `ui_geometry.py --only` 量页头：它们在窗口里的页头要和目标页同一位置 (箭头 85、标题 100、分隔线 52)，名字登记在 `ui-geometry.json` 的 `formPages`。
静态规则 `HOME-LAYOUT` (首页按 `HomeLayout` 定位、窗口 360×574、不再用放不下就收紧的写法) 与 `HDR-FORM` (表单在窗口里用 `PageHeader`) 守着对应的代码写法。

| 规则 | 对应的坑 | 判定 |
|---|---|---|
| HOME-WIDTH (像素) | 预计日期带年份 (「2027年7月」) 时大目标卡被撑宽，整页变成 325 宽、左右边距只剩 17.5；预览里的日期都是短的，没暴露 | 每个状态的统计卡左右沿在 20 与 340，各 ±1；预览 `P2-working-far-finish` 专门放一个明年才完成的目标 |
| HOME-GOALDATE (像素) | 大目标卡里预计日期和进度条各自垂直居中，日期的字底比进度条下沿低 | 2 个及以上目标时，日期字底与进度条下沿相差不超过 0.5 pt (1 倍图 1 pt) |
| HOME-GOALDATE (像素) | 2026-11-27 实机验收：只有 1 个目标的整宽卡，金额那一行右边的日期按基线对齐，汉字的字底比金额低 1 pt | 整宽卡里日期的字底与累计额 (ink 色) 的字底相差不超过 0.5 pt (1 倍图 1 pt)；预览 `P2-working-one-goal` |
| HOME-COPY (静态) | 去「非必要的小字」时把信息也删了，Allen 看到后要求留着 | 首页必须显示：主数字上的小标题、说明行、「已工作 x / y 小时」、统计卡每格的小标题 |
| HOME-COPY (静态) | 已经去掉的前缀和小标题又回来 | 首页三个文件里不能再用带前缀的旧字段 (`startText`、`endText`、`shortEstimate`、`tagline`、`nextAttendanceText`、`currentText`)、「攒钱队列」标题与目标计数、单独的「修改」按钮；悬停提示 (`.help`) 里用不算 |
| HOME-COPY (静态) | 攒钱队列做成可滑动后看不出能滑；超过 3 个时加了「+N」 | 首页不出现 `ScrollView`；排队中只取前 2 个 |
| HOME-COPY (静态) | 上班类状态放了小牛主角，被否 | 首页只有休息日那一块用小牛头像 |
| HOME-COPY (静态) | 2026-11-27 实机验收：提示条前面的警告图标多余 | `PanelNoticeBanner` 里不能有图标 (`…Icon(`、`Image(`) |
| HOME-UNPAID (静态) | 同上面像素那条 | `TodayPanelView` 里白干中的进度区是 `PanelProgress(progress: unpaidWork.progress, tone: Palette.loss)`；`moodButtons` 的白干中分支只加「终于下班了」，不加扣钱；核心里有「最多白干 N 小时」 |

查不到的：区域里面的排版 (字号、对齐、截断)、日期行与主数字区的位置 (它们是文字，没有可认的底色)、提示条。
这些靠定稿图人工对照。

## 交互回归 (`ui-checks-mac.sh`、`ui_drive.py`)

### 一次运行做什么

1. 前置：不是 macOS，或缺 `xcodebuild`、`python3`、`clang`、`swiftc`、`shasum`，报 BLOCKED 退出 2。
2. 编一次 Debug (`ENABLE_HARDENED_RUNTIME=NO`，构建目录在 `mktemp -d` 里)，离屏渲染与真窗口都用这一份；编译失败记 `FAIL [BUILD]`，退出 1。
3. 编注入库 `harness/drive.m`，用 `harness/FakeState.swift` 造假状态。
   假状态：上个月 1 号完成引导，月薪 20000，10:00–18:00，饭点 12:00–13:00，双休；关掉桌面悬浮小牛与两种通知；一个累计中目标「换台 MacBook」加四个排队目标，金额远大于两个月工资，不会弹庆祝动画。
   今天设成上班日，周末、节假日、深夜跑，概览上都有「今天扣钱了」。
   今天的月日历格子因此是三行 (日号、「改班」、今日已赚)；上个月第一个周一至周五改成上班再请 2 小时假 (日号、「2h」、金额)，第一个周六改成上班再扣一笔钱 (日号、小圆点、「改班」、金额)，给 FIT-CELL 量挤的格子。
4. 离屏渲染：注入库调用 `wagetick_render_page_previews`，图放 `offscreen/`，写清单 (`kind: offscreen`，`decorations` 里窗框与红绿灯都是 false)，跑 `ui_geometry.py --kind offscreen`。
   再调用 `wagetick_render_panel_previews` 渲染首页各状态，图放 `panel/`，写清单 (`kind: panel`)，跑 `ui_home.py`。
   再调用 `wagetick_render_onboarding_previews` 渲染引导两步，图放 `onboarding/`，给 FIT-PREVIEW 对照。
   每次离屏渲染完，注入库把 App 实际取到的字体写进报告，查 FONT-BUNDLED (见下面「字体」)。
5. 真窗口与交互回归：`ui_drive.py` 用假主目录拉起 App (`CFFIXED_USER_HOME` 加注入库里拦截 `getpwuid`)，经 Unix 套接字给注入库发命令。
   截 `today`、`P3-goals`、`P4-history`、`P5-calendar`、`P5-day-detail`、`P6-settings` 六张真窗口图放 `realwindow/`，写清单 (`method: cacheDisplay`，`active` 按实际)，跑 `ui_geometry.py --kind realwindow`。
6. FIT-NOSCROLL：关掉上一步的 App，用同一个假主目录再起一次今日概览窗口 (不带上一步留下的页面状态)，量每个月的月日历 (同时查 FIT-CELL)、今天扣钱了、请假 (新增)、修改请假 (先新请一条全天的)。
   再关掉，用一个空的假主目录 (没有 state.json，App 打开引导窗口「牛马鼓励器」) 起第三次，量引导第 1 步 (月薪、空；日薪、填 200)，清空工资点「下一步」查校验提示 (FIT-HINT)，再填月薪 20000 进第 2 步 (饭点开、关)。
   每次拉起 App 都先查 FONT-BUNDLED。
   这一步的真窗口图放 `fit/`，不进 `realwindow/` 的清单。
   最后比较引导三个状态的离屏预览与真窗口图 (FIT-PREVIEW)。
7. 真实数据目录 `~/Library/Application Support/com.zhew1585.WageTick/` 在开始前、结束后各取一次校验和 (文件名加内容)，变了记 `FAIL [ENV-DATA]`。
8. 收尾：只关自己拉起的 App (先在进程内 `NSApp terminate:`，10 秒不退就杀它的 pid)，删临时目录。

输出目录默认 `build/ui-checks/`，可用第一个参数或环境变量 `UI_CHECKS_OUT` 改。
里面留离屏图、真窗口图、两份清单、`ui-checks.log`、`app.log`、编译日志，规则不过时还有 `fail-<规则>-<序号>.png`，是当时的整窗图。
本机一次完整运行约 130 秒 (含 Debug 编译与三次启动)。

### 怎么驱动

注入库在 App 进程里做这些事，不走系统的事件注入，不需要辅助功能、屏幕录制授权：

- 按键：合成 `NSEvent` 键盘事件，`NSApp postEvent:` 排进 App 自己的事件队列，和真按键一样先给 key 窗口、再给主菜单的快捷键。
- 点击：合成鼠标按下、抬起，同样排进事件队列。
  点哪里由辅助功能树决定：注入库在进程内打开 `AXEnhancedUserInterface`，SwiftUI 才会建树，再按按钮的文字 (如「新目标」「今天扣钱了」) 读出它在窗口里的位置。
- 截图：对窗框视图 (含系统红绿灯) 调 `cacheDisplay(in:to:)`，按 2 倍画，圆角外铺窗口底色。
- 窗口状态：`isVisible`、`attachedSheet`、窗口编号、可见的带标题窗口。
- 点 Dock 图标：直接调 `applicationShouldHandleReopen(_:hasVisibleWindows:)`，系统点 Dock 图标时调的就是它。
- 认哪个窗口：按标题，默认「今日概览」，环境变量 `WAGETICK_DRIVE_TITLE` 可换 (引导窗口是「牛马鼓励器」)。
- 滚动区域：`scrolls` 列出窗口里每个 `NSScrollView` (SwiftUI 的 `ScrollView` 背后就是它) 的位置、可见高度、文档高度。
- 输入：`text <文字>` 把文字插进当前输入焦点 (像输入法上屏)，`clear` 清空它。
- 字体：`font` 返回 App 里 Debug 才有的 `wagetick_font_report()` (`WageTick/Theme/AppFontReport.swift`) 的结果：界面字体、数字字体各字重实际用的字体文件、wght 轴上的值、子集外汉字回退到的字体、App 包的路径。

### 字体

2026-11-26 查出：`AppFont` 原来按字族名取「Noto Sans SC」，机器上另装了同名字体 (如 `~/Library/Fonts/NotoSansSC.ttf`) 时取到的是装的那份，不是 App 打包的 `NotoSansSC-GB2312.ttf`。
两份的行高差很多 (14 号字：装的那份 15pt，打包的 20pt)；装的那份还没有 wght 轴，各字重都是同一个 Regular。
这台机器上之前所有的离屏预览、真窗口截图与几何阈值，量的都是被顶替的字体；同一页在这里放得下，在用户的机器上要滚动。
现在 `AppFont.register()` 之后一律从打包的字体文件建字体 (`CTFontManagerCreateFontDescriptorsFromURL` 取文件自己的描述，再加 wght 轴)，检查里不再需要任何强制字体的办法。

FONT-BUNDLED 是硬性检查：每次离屏渲染 (页面预览、首页、引导) 与每次拉起 App (今日概览两次、引导一次) 都取 App 的字体报告，界面字体、数字字体 400 至 800 五个字重用的字体文件都要在 App 包内、wght 轴上的值等于要的字重、子集外的汉字回退到苹方，否则 `FAIL [FONT-BUNDLED]` 并打印实际路径。
小组件预览 (`wagetick_render_widget_previews`) 故意不注册打包字体，和小组件扩展一样用系统字体，不在这条检查里。

App 拿不到前台，红绿灯是灰的，窗口也不是 key 窗口；这对上面的判定没有影响。

### 怎么认页

- 页面：页头区域 (窗口顶部 4–44pt、x 76pt 往右) 的墨迹指纹与参照逐像素相同。
  墨迹指纹是亮度低于 160 的像素组成的形状的哈希，只看深色的字与图标；悬停、按下时浅色的圆角底与红绿灯的颜色不影响。
  参照是本次运行里截的：⌘2、⌘3、⌘, 截下目标、历史月列表、设置，第一次点进月日历、单日详情时截下这两页。
  概览的日期时钟从 46pt 起，滚动的金额更靠下，都不在这块区域里。
- 概览：底部入口栏 (最下面 46pt，历史、目标、设置那一条) 的墨迹指纹与启动时的参照相同。
  推进来的页面和扣钱、请假表单都会把它盖住或换掉。
- 每次动作后等画面停下：两块区域的指纹连续两次相同 (至少等 0.45 秒，最多 4 秒)。
- ACT-PUSH 另外核对辅助功能树里页头按钮的文字是「目标」「历史」「设置」，并用 `ui_geometry.measure_header` 确认页头里有返回箭头。

### 规则

| 规则 | 对应的坑 | 步骤 | 判定 | 误报边界 |
|---|---|---|---|---|
| ACT-PUSH | 目标、历史、设置要在同一个窗口里推进来 | 概览上依次按 ⌘2、⌘3、⌘, | 窗口编号不变、只有这一个带标题的窗口；页头指纹与之前的每一页都不同、底栏不见了；页头按钮文字对；有返回箭头 | 三页的参照就在这一步截；这一条不过时，后面靠参照认页的规则跟着不可信，以这一条为准 |
| ACT-DOCK | 点 Dock 图标被踢回概览 | ⌘1 回概览，⌘, 进设置，触发重新打开 | 仍是设置页 | 直接调代理方法，不经过 Dock 本身 |
| ACT-HOME | 停在页面上按 ⌘1 不回概览 | ⌘2 进目标页，按 ⌘1 | 是概览 | 其他规则都用 ⌘1 回概览作起点，这条坏了它们会跟着一起报 |
| ACT-GOALCARD | 概览目标卡点不了 | 在概览上点「换台 MacBook」(卡片是按钮时点整张卡的中心，不是按钮时点名字那一行字) | 进了目标页 | 只点累计中目标的卡片，空状态卡与排队行不点 |
| ACT-COVER | 页面盖着时点得到底下 | 先在概览上记下「今天扣钱了」的位置，⌘2 进目标页，在那个位置点一下，再按 ⌘1 | 点完仍是目标页、没有弹出表单；⌘1 后是概览 (底栏还在)，不是扣钱表单 | 页面整块铺了底色，点击被页面接住，去掉底层的 `.disabled` 时点不穿，这条抓不到 (见实测)；它只保证点击不会漏到底下，Tab 与辅助功能那一半靠静态规则 NAV-COVER |
| ACT-SHEET | 开着表单时快捷键把页面换掉 | 目标页点「新目标」，依次按 ⌘1、⌘2、⌘3、⌘,，再按 Esc | 每按一次 `attachedSheet` 仍在、页头指纹与刚弹出表单时相同 (挂着表单时窗口整体压暗，所以用这时截的参照)；Esc 后 `attachedSheet` 为空且是目标页 | 无 |
| ACT-ESC | Esc 跳级或提前关窗 | ⌘3 进月列表，点第一个月份行，点第一个有工资的日子，然后按 4 次 Esc | 依次是月日历、月列表、概览，窗口一直可见；第 4 次后窗口不可见 | 每一级的 Esc 都先被页头返回按钮的快捷键接走，窗口的 Esc 兜底 (`handleCancel`) 走不到；兜底改坏了这条抓不到 (见实测)，只有静态规则 NAV-ESC 能抓 |
| ACT-HISTORY | 历史页再进来不是月列表 | 同上进到单日详情，按 ⌘1，再按 ⌘3 | ⌘1 后是概览；⌘3 后是月列表 | 无 |
| FONT-BUNDLED | 2026-11-26：开发机装了同名字体，预览和检查量的不是用户看到的排版，引导页在用户机器上要滚动 | 每次离屏渲染完、每次拉起 App 后取字体报告 (见「字体」) | 界面字体、数字字体五个字重的字体文件都在 App 包内，wght 轴上的值与要的字重相差不超过 0.5，子集外的汉字回退到苹方 (PostScript 名以 PingFang 起头)；通过时打一行 ok 并写出字体文件名 | 只查 `AppFont` 给出的字体，视图里另外取的字体 (系统字体的图标按钮) 不查；没有报告是 BLOCKED |
| FIT-NOSCROLL | 2026-11-26 引导页在真窗口里要滚动，离屏预览量出来却放得下 (量的机器装了另一版 Noto Sans SC，行高小得多)；月日历六行的月份、扣钱、请假表单同样 | 今日概览窗口：⌘3 进月列表逐个点月份，⌘1 回概览点「今天扣钱了」、点「请假」，点「就这么请」后再点概览上的请假进修改请假；空主目录的引导窗口：第 1 步刚打开、点日薪填 200，改回月薪填 20000 点下一步，第 2 步饭点开、关。每个画面停下后读 `scrolls` 与辅助功能树 | 每个可见高度大于 40 的纵向滚动区域：文档高度不超过可见高度 (允许 0.5pt)；滚动区域里 (上沿在区域内) 最靠下的控件下沿不低于区域下沿 (即底部按钮栏上沿，允许 0.5pt)。数值每次都打出来 | 只量这几页的这些状态：出现校验提示、超日薪提醒时多一行，不在检查范围 (引导第 1 步的校验提示由 FIT-HINT 管)；月日历量假状态里的所有月份 (上个月与本月)，有没有六行的月份要看今天是几月，没有时打一行 note；修改请假只量全天请假；页面进不去是 BLOCKED |
| FIT-CELL | 2026-11-26 换成打包字体后，月日历里日号、小字 (「改班」「2h」)、金额三行的格子放不下：日号顶到格子上沿，金额下半截被格子下沿裁掉 (今天的格子是深底浅字，出了格子的字看不见，像被裁掉) | FIT-NOSCROLL 量每个月的月日历时，用同一张真窗口图 | 日子格子的框取自辅助功能树 (文字如「26、改班、¥952」，按「、」分开的段数是行数)；在图上量格子中间 x+8 至 x+w-8 里与格子底色 (取格子左边 2.5pt、半高处) 相差明显的像素，上下各去掉描边的 1.5pt：墨迹离格子上下沿都至少 2pt，墨迹分出的段数不少于行数 (少了是字叠在一起)。三行格子的墨迹每次都打出来 | 只量格子里面：字出了格子、但格子里那几行还离边 2pt 以上的情况量不到 (按现在的行高不会出现)；小圆点是额外的一段，段数只查下限；悬停描边 1.5pt 以内不算；假状态里有没有三行的格子靠上面造的数据，FakeState 改了要留着 |
| FIT-PREVIEW | 离屏预览与真窗口对不上，靠预览验证的排版不可信 | 引导三个状态 (P1-1-salary-empty、P1-1-salary-daily、P1-2-schedule) 的离屏预览与 FIT-NOSCROLL 截的同名真窗口图，从 30pt 起逐行看 x 24–336pt 里有没有非底色像素，连续的行并成一段 | 两边分段数相同，每段上下沿相差不超过 1pt | 只比引导两步 (其他页面的离屏预览与真窗口截法不同，页头那一段对不齐)；分段只看纵向，横向排版不比；两边用的是哪份字体由 FONT-BUNDLED 管 |
| FIT-HINT | 2026-11-26 窗口调短后，引导第 1 步出现校验提示时提示文字在滚动区域外，被「下一步」那一栏盖住下半截 | 引导第 1 步清空工资，点「下一步」，等「月薪得是个正数」出现 | 提示在辅助功能树里的框整个落在滚动区域的可见范围里 (允许 0.5pt)，即不低于底部按钮栏上沿 | 只查引导第 1 步的这一条提示；提示文案变了要改 `ui_drive.py` 的 `HINT_SALARY` |
| ENV-DATA | 检查碰了真实数据 | 开始前、结束后各取一次真实数据目录的校验和 | 前后一致 | 本机另开着一个 App 时它自己会写这个目录，这时记 BLOCKED，不记 FAIL |

规则不过时打印 `FAIL [规则] <现象> (当时的窗口图：…)`，整次运行退出 1。
窗口在 60 秒内没出现、驱动连不上、App 中途崩了、启动后不在概览、假状态下没有「今天扣钱了」、FIT-NOSCROLL 要量的页面进不去，都是 BLOCKED，退出 2。
全部通过时每条规则打一行 `ok [规则] …`，几何规则离屏、真窗口各一组。

### `selftest-mac.sh`：故意违规必须被抓到

`scripts/checks/selftest-mac.sh` 在临时 worktree 里 (检出当前提交，再盖上工作区的 `scripts/checks/`) 先跑一遍不改的，必须通过；然后逐条改源码、跑 `run.sh ui`、还原。
慢 (十几分钟)，不进 CI；改了检查脚本或页面结构后在本机跑。
`scripts/checks/selftest-mac.sh <文字>` 只跑名字里含这段文字的改动。
源码变了、找不到要改的原文时报 BLOCKED，要同步改脚本里的 `CASES`。

实测 (2026-11-26，提交 5810365 加本次的检查脚本，本机 Apple Silicon Mac，本机装着另一版 Noto Sans SC (`~/Library/Fonts/NotoSansSC.ttf`)、没有任何强制字体的开关；每条约 135 秒，整轮约 35 分钟)：

| 改动 | 改了什么 | 预期规则 | 退出码 | 实际报出 | 抓到 |
|---|---|---|---|---|---|
| 基线 | 不改 | 无 | 0 | 无 | — |
| 箭头离红绿灯 6pt | `PageHeader.rootLeading` 改回 `leadingInset - Spacing.s6` | HDR-LIGHTS-GAP 或 HDR-X | 1 | HDR-LIGHTS-GAP、HDR-X | 是 |
| 窗口改回标准标题栏 | 今日概览窗口 `titlebar: .standard` | HDR-LIGHTS 或 HDR-VCENTER | 1 | HDR-LIGHTS、HDR-VCENTER | 是 |
| 页面预览上方多留一行 | `PagePreviews.page()` 上方加 28 的 padding | HDR-FRAME | 1 | HDR-FRAME、HDR-VCENTER | 是 |
| 盖页后底层没停用 | `TodayPanelView` 去掉 `.disabled(content.page != nil)` | ACT-COVER | 1 | ACT-HISTORY (同一天前一轮是 ACT-ESC、ACT-HISTORY) | 否 |
| 开着表单也换页 | `show()` 里 `push` 不再受 `hasSheet` 保护 | ACT-SHEET | 1 | ACT-SHEET | 是 |
| Esc 兜底直接退回概览 | `handleCancel()` 里 `if !goBackInside(page) { pop() }` 改成 `pop()` | ACT-ESC | 0 | 无 | 否 |
| 概览目标卡不可点 | `GoalCardView` 的累计中大卡去掉 `tappable` (`Button`) 包裹 | ACT-GOALCARD | 1 | ACT-GOALCARD | 是 |
| 点 Dock 图标也退页 | `applicationShouldHandleReopen` 改回 `todayPanel.show()` | ACT-DOCK | 1 | ACT-DOCK | 是 |
| ⌘1 不回概览 | `show()` 里去掉 `pop()` 那个分支 | ACT-HOME | 2 | ACT-HOME，另有 ACT-COVER、ACT-DOCK、ACT-ESC、ACT-GOALCARD、ACT-HISTORY、ACT-SHEET 跟着报；之后 FIT-NOSCROLL 也回不到概览，记 BLOCKED，所以退出码是 2 | 否 (按脚本的判定：规则报出来了，但退出码不是 1) |
| 历史页再进来不是月列表 | `HistoryPage.appear()` 不重置 `selectedMonth`、`selectedDay` | ACT-HISTORY | 1 | ACT-HISTORY | 是 |
| 引导小牛放大 | 引导第 1 步小牛框 `mascotSize` 78 改成 120 | FIT-NOSCROLL | 1 | FIT-NOSCROLL | 是 |
| AppFont 退回系统字体 | `makeFont` 里 `if let base {` 改成 `if let base, false {` | FONT-BUNDLED | 1 | FONT-BUNDLED，另有 ACT-* 七条跟着报 (字体变了，认页的参照与 ⌘1 回概览的判定对不上) | 是 |
| 页头标题不上提 | 去掉 `PageHeader` 标题的 `.offset(y: -Self.titleLift)` | HDR-VCENTER | 1 | HDR-VCENTER | 是 |
| 入口栏又靠内边距撑高 | `PanelFooter` 的 `.frame(height: HomeLayout.footer.height)` 改回 `.padding(.vertical, Spacing.s10)` | HOME-BAND | 1 | HOME-BAND | 是 |
| 引导校验提示不滚过去 | `OnboardingView` 校验不过时不调 `scrollTo` | FIT-HINT | 1 | FIT-HINT | 是 |

15 条里抓到 12 条。
「AppFont 又按字族名取字」(改回原来的写法) 不在这里：只有装了同名字体的机器上才会报 FONT-BUNDLED，没装的机器上按字族名取到的就是注册进来的打包字体；这一条由静态规则 FONT-BUNDLED 管。
「⌘1 不回概览」规则是报出来了，只是后面的 FIT 步骤进不去页面记了 BLOCKED；脚本只认退出码 1，照实记「否」。

FIT-NOSCROLL 加进来时 (2026-11-26，提交 5634df7 加本次的检查脚本) 补测了一条；当时基线因为首页的 20 条 HOME-BAND (入口栏下沿 572.5pt，应 574pt) 不通过，`selftest-mac.sh` 会在基线处 BLOCKED，所以这条是在临时 worktree 里手工改源码直接跑 `run.sh ui` 测的：

| 改动 | 改了什么 | 预期规则 | 退出码 | 实际报出 | 抓到 |
|---|---|---|---|---|---|
| 引导小牛放大 | 引导第 1 步小牛框 `mascotSize` 78 改成 120 | FIT-NOSCROLL | 1 | FIT-NOSCROLL (引导第 1 步月薪空、日薪已填：内容高 483.5，可见高 450，超出 33.5)，另有基线就有的 HOME-BAND | 是 |

同一套检查脚本在修复前的提交 5a98eb6 上跑，报出 7 条 FIT-NOSCROLL：引导第 1 步两个状态各超出 35.5，第 2 步饭点打开超出 24，月日历 (2026年11月，6 行) 超出 9，今天扣钱了超出 24，请假 (新增)、修改请假各超出 28；FIT-PREVIEW 通过。
没抓到的两条，界面上确实看不出差别，不是检查漏看：

- 去掉 `.disabled`：推进来的页面整块铺了底色，点击落在页面上，点不到底下的概览；`.accessibilityHidden` 也还在。
  差别只在键盘 Tab 能不能聚焦到底下，交互回归不按 Tab (App 拿不到前台，没有焦点环)。
  这一处只有静态规则 NAV-COVER 能抓，Tab 的行为留给人工验收。
- Esc 兜底：每一级页面的 Esc 都先被页头返回按钮的快捷键 (`.keyboardShortcut(.cancelAction)`) 接走，正常操作走不到 `handleCancel()`。
  这条违规靠 ACT-ESC 抓不到，只有静态规则 NAV-ESC 能抓。

第一轮实测里「窗口改回标准标题栏」只报出 IMG-KIND：`measure_lights` 从左上 12pt 起找圆，28 高标题栏的第一个红绿灯 (8–20) 被切掉了。
找圆的范围改成从 4pt 起后，报的是 HDR-LIGHTS、HDR-VCENTER；阈值没有动。

## 不能自动覆盖的，需要人工验收

下面这些自动检查替代不了，合并前要有人在真机上看一遍。

- Tab 切焦点时是否落到被盖住的概览上：App 拿不到前台，没有键盘焦点环，交互回归不按 Tab。
- 输入框里、中文输入法选词时按 Esc 的归属：交互回归只在没有输入焦点时按 Esc。
- 真人用鼠标键盘操作的手感：悬停、拖动排序、滑入滑出的动画过程；检查只看动画停下后的画面。
- 从菜单栏小牛的菜单、悬浮小牛、系统通知打开页面：交互回归只走主菜单快捷键与概览上的按钮。
- 真的点 Dock 图标：交互回归直接调系统会调的代理方法，不经过 Dock。
- App 在前台时红绿灯的颜色：自动截的图是非激活态，红绿灯是灰的。
- 窗口阴影与圆角：进程内截图不带阴影，圆角外铺的是窗口底色。
- 1 倍屏上的像素取整：截图一律按 2 倍画。
- 目标空状态、单日详情的各种状态在真窗口里的样子：真窗口图只截六张 (另有 FIT-NOSCROLL 截的 `fit/`，只量放不放得下)，其余只有离屏预览，`ui_geometry.py` 会逐张打 MANUAL。
- 带校验提示、超日薪提醒的表单放不放得下：FIT-NOSCROLL 只量没有提示的状态，FIT-HINT 只管引导第 1 步的校验提示。
- 留白是否美观。
- 与原版逐像素一致：基准图不在仓库里，每次重渲原版太慢，这一项靠出图时的像素比对报告。
- GitHub 托管的 runner 上能不能拉起窗口还没验证过；拉不起来时这一步会报 BLOCKED (退出码 2)，不会当作通过。
