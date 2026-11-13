import SwiftUI
import WageCore
import WidgetKit

/// 桌面小组件扩展入口 (PRD F14)。只有一个小组件「今日概览」，小号、中号、大号三种尺寸。
/// 数据来自 App 写的 widget.json (`WidgetPayload`)，时间线由核心的 `widgetTimeline` 推导，与 App 用同一套算法。
/// 扩展必须开沙盒，读 widget.json 靠 entitlements 里的只读临时例外，见 `WageTickWidgets.entitlements`。
/// 小组件用系统字体 (扩展不打包、不注册 Noto Sans SC 与 JetBrains Mono，`AppFont` 自动退回 SF、苹方、SF Mono)：
/// 桌面上的画面由系统的小组件服务按扩展排好的位置另画，它用不上扩展里的字体，会换成更宽的系统字体，
/// 刚好放满的文字 (如顶部日期) 就被截成省略号。两边都用系统字体，量的和画的才一致。
@main
struct WageTickWidgets: WidgetBundle {
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

    /// 底色随状态与尺寸变 (`WidgetBackground`)：小号、中号铺满状态色，大号米白底。
    var body: some View {
        WidgetContentView(snapshot: entry.snapshot, size: size, clock: WidgetClock(now: entry.date))
            .containerBackground(for: .widget) { WidgetBackground(snapshot: entry.snapshot, size: size) }
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
