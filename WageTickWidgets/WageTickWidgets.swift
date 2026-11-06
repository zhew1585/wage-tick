import SwiftUI
import WageCore
import WidgetKit

/// 桌面小组件扩展入口 (PRD F14)。只有一个小组件「今日概览」，小号、中号、大号三种尺寸。
/// 数据来自 App 写的 widget.json (`WidgetPayload`)，时间线由核心的 `widgetTimeline` 推导，与 App 用同一套算法。
/// 扩展必须开沙盒，读 widget.json 靠 entitlements 里的只读临时例外，见 `WageTickWidgets.entitlements`。
@main
struct WageTickWidgets: WidgetBundle {
    init() {
        // 先注册打包的字体 (同 App 的 `Main`)，视图才取得到 Noto Sans SC 与 JetBrains Mono；失败时退回系统字体。
        AppFont.register()
    }

    var body: some Widget {
        TodayWidget()
    }
}

/// 今日概览小组件。关掉系统的内容边距，内边距按设计稿在 `WidgetContentView` 里给。
struct TodayWidget: Widget {
    static let kind = "TodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TodayTimelineProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
                .containerBackground(Palette.bg, for: .widget)
        }
        .configurationDisplayName("今日概览")
        .description("今天赚了多少、离下班还有多久，还有攒钱目标的进度。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

extension WidgetEntry: @retroactive TimelineEntry {}

/// 按尺寸摆放一条时间线的内容；计时文字由系统实时走。
struct TodayWidgetEntryView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetContentView(snapshot: entry.snapshot, size: size, clock: WidgetClock(now: entry.date))
    }

    private var size: WidgetSize {
        switch family {
        case .systemMedium: .medium
        case .systemLarge, .systemExtraLarge: .large
        default: .small
        }
    }
}

/// 时间线：每次被要时读一遍 widget.json，从此刻起排 60 分钟 (每分钟一条，日状态切换处各一条)，排完再要 (`.atEnd`)。
/// App 改了状态会主动让系统重新要 (`WidgetBridge`)。读不到数据 (App 还没打开过) 时按未完成引导提示打开 App。
struct TodayTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), snapshot: .setup(.standard))
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(Self.entries(horizon: 0).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        completion(Timeline(entries: Self.entries(horizon: widgetTimelineHorizon), policy: .atEnd))
    }

    private static func entries(horizon: TimeInterval) -> [WidgetEntry] {
        let now = Moment(date: Date(), timeZone: TimeZone.current)
        guard let payload = WidgetPayload.load() else {
            return [WidgetEntry(date: now.date, snapshot: .setup(.standard))]
        }
        return widgetTimeline(of: payload.state, from: now, holidays: payload.holidays, horizon: horizon)
    }
}
