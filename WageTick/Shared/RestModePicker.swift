import SwiftUI
import WageCore

/// 休息模式四选一 (设计稿 P1 引导 · 1「怎么休」、P6 设置「休息模式」表单 · 760)：
/// 双休、大小周 (这周休两天)、大小周 (这周休一天)、单休，标题与小字来自核心的 `RestModeChoice`。
struct RestModePicker: View {
    let selection: RestModeChoice
    let select: (RestModeChoice) -> Void

    var body: some View {
        ThemeSegmented(
            options: RestModeChoice.allCases.map { .init(id: $0, title: $0.title, subtitle: $0.subtitle) },
            selection: selection,
            size: .choice,
            select: select
        )
    }
}
