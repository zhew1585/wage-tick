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
- `selftest.py`、`fixtures/`：检查脚本自己的回归。
  每条静态规则配一处故意违规的改动，每条几何规则配一张当时真出过问题的图，都必须被抓到。
- `ui-checks-mac.sh`：Mac 上的渲染、真窗口与交互回归。

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
| REPO-LOCAL | `roles/`、`docs/spec/` 只放本机 | `git ls-files roles docs/spec` 必须为空 | 不在 git 仓库里时不查 |

成功路径：`python3 scripts/checks/ui_lint.py` 在当前源码上输出「ui_lint: 通过」，退出码 0。
故意违规：`selftest.py` 里的 20 处改动，每处都必须让 `ui_lint.py` 以退出码 1 报出对应规则。

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
| HDR-X | 标题比原版靠右 26 (`947880d`)；三处间距压在边界上 | 目标、目标空状态、历史月列表、设置 | 箭头左沿 85 ±1；箭头到标题 7.5 至 11；标题左沿不超过 105 | 85 是 `d107b63` 的设计值，Allen 看过真窗口图后若调整，要改 `ui-geometry.json` |
| HDR-X | 下一级页头要保持原版 | 月日历、单日详情 | 箭头左沿 90 ±1；箭头到标题 13 至 18；标题左沿不超过 114 | 原版实测值 |
| HDR-CONSISTENT | 目标、历史、设置的页头不一致 | 同一类的几页之间 | 箭头左沿相差不超过 0.5；墨迹中心 y 相差不超过 0.75 | 无 |
| HDR-LIGHTS | 标题栏方案被悄悄改掉 | 真窗口图 | 三个红绿灯右沿在 72 ±1.5，中心 y 在 26 ±1 | 系统换了红绿灯尺寸要重新量 |
| IMG-BLANK | 近景裁成了空白图还照样提交 (`3d73c4c`) | 所有图 | 与底色不同的像素不到 0.3% 就不过 | 只看图的上部 |
| IMG-KIND | 离屏预览不画红绿灯，不能冒充真窗口图 | 所有图 | 标成离屏的图里不能有红绿灯；标成真窗口的必须有三个；图宽要对得上 | 认的是红绿灯的位置与大小，不认颜色 |
| IMG-VERSION | 拿旧提交的图当新图 | 带清单的整套图 | `manifest.json` 里的提交必须是当前 `HEAD` | 清单要由出图的脚本写 |
| IMG-MANIFEST | 图没标明版本、时间、截法 | 同上 | 清单必须有 `commit`、`kind`、`capturedAt`、`method`、`files` | 无 |
| BLOCKED | 缺图、缺清单时当成通过 | 同上 | 整套检查不给清单、清单里的图不在、该有的图缺了，都退出码 2 | 真窗口图里月日历等几页可以没有，会记一行 MANUAL |

成功路径：`python3 scripts/checks/ui_geometry.py --kind offscreen --dir <页面预览目录> --manifest <清单>` 输出「ui_geometry: 通过」，退出码 0。
故意违规：`fixtures/` 里是从当时的渲染图上截下来的顶部一条，`selftest.py` 确认每张都被对应的规则抓到。

| 反例图 | 来自 | 必须被抓到 |
|---|---|---|
| `offscreen-extra-row-73f794d` | 页头排在多出的一行里 | HDR-FRAME |
| `offscreen-right-947880d` | 标题比原版靠右 26 | HDR-X |
| `offscreen-tight-84b2b71` | 箭头离红绿灯 6 | HDR-LIGHTS-GAP、HDR-X |
| `realwindow-tight-84b2b71` | 同上，真窗口图 | HDR-LIGHTS-GAP |
| `realwindow-blank` | 裁成空白的近景 | IMG-BLANK |
| 把真窗口图当离屏查，或反过来 | 标识与内容不符 | IMG-KIND |

`offscreen-original-9c69fd3` 是原版月日历的页头，必须放行。

### 关于美观

HDR-LIGHTS-GAP 只保证不退回被 Allen 否掉的 6 pt。
HDR-X 只保证和当前的设计值一致，不代表这个设计值已经被认可。
留白是否美观，要 Allen 看真窗口图确认；检查每次都会打印这一句。

## 交互回归 (`ui-checks-mac.sh`)

状态：这一部分还在 Mac 上接入。
接入之前 `scripts/checks/run.sh ui` 会报 blocked (退出码 2)，不会当作通过。

在 App 进程里合成按键与鼠标事件来驱动，数据目录指到临时目录，不碰 `/Applications` 与真实数据。
每一步读窗口状态并截窗口图作证据，不符合就以退出码 1 结束。

| 规则 | 对应的坑 | 步骤与判定 |
|---|---|---|
| ACT-PUSH | 目标、历史、设置要在同一个窗口里推进来 | ⌘2、⌘3、⌘, 之后窗口还是同一个，画面换成对应页面 |
| ACT-HOME | 停在页面上按 ⌘1 不回概览 | 停在目标页按 ⌘1，画面回到概览 |
| ACT-ESC | Esc 跳级或提前关窗 | 单日详情、月日历、月列表、概览，每按一次只退一级；概览上再按才关窗 |
| ACT-SHEET | 开着表单时快捷键把页面换掉 | 目标页开着「新目标」时按 ⌘1 ⌘2 ⌘3 ⌘,，窗口画面前后一致；Esc 只关表单 |
| ACT-GOALCARD | 概览目标卡点不了 | 点概览上累计中目标的卡片，进入目标页 |
| ACT-DOCK | 点 Dock 图标被踢回概览 | 停在设置页时触发重新打开，仍在设置页 |
| ACT-COVER | 页面盖着时点得到底下 | 页面盖着时在底下按钮的位置点一下，页面不变 |
| ACT-HISTORY | 历史页再进来不是月列表 | 从单日详情回概览后再进历史，是月列表 |

## 不能自动覆盖的，需要人工验收

下面这些自动检查替代不了，合并前要有人在真机上看一遍。

- Tab 切焦点时是否落到被盖住的概览上：合成事件驱动时 App 拿不到前台，没有键盘焦点环。
- 输入框里、中文输入法选词时按 Esc 的归属。
- 真人用鼠标键盘操作的手感：悬停、拖动排序、滑入滑出时的观感。
- App 在前台时红绿灯的颜色：自动截的图是非激活态，红绿灯是灰的。
- 窗口阴影与圆角：进程内截图不带。
- 1 倍屏上的像素取整。
- 留白是否美观。
- 与原版逐像素一致：基准图不在仓库里，每次重渲原版太慢，这一项靠出图时的像素比对报告。
