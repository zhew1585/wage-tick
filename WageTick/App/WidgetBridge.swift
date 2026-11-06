import AppKit
import OSLog
import WageCore
import WidgetKit

/// 把状态交给桌面小组件 (PRD F14)：状态或节假日表变了就重写 widget.json (见 `WidgetPayload`) 并让系统重新要时间线；
/// 跨过零点、睡眠恢复、改系统时间或时区时也让系统重新要一次。内容没变时不写也不刷新，免得耗掉系统给的刷新额度。
@MainActor
final class WidgetBridge {
    private let logger = Logger(subsystem: AppIdentity.bundleID, category: "WidgetBridge")
    /// 上次写入的内容，没变就跳过。
    private var written: Data?

    init() {
        let center = NotificationCenter.default
        for name: Notification.Name in [.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            center.addObserver(self, selector: #selector(clockChanged), name: name, object: nil)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(clockChanged), name: NSWorkspace.didWakeNotification, object: nil)
    }

    /// 状态落盘或换了节假日表后调用。
    func publish(state: AppState, holidays: HolidayTable) {
        do {
            let data = try WidgetPayload(state: state, holidays: holidays).encoded()
            guard data != written else { return }
            let url = WidgetPayload.fileURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            written = data
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            logger.error("小组件数据写入失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// 清空数据时删掉小组件数据，重启后由新状态重写。
    func reset() {
        try? FileManager.default.removeItem(at: WidgetPayload.fileURL)
        written = nil
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 跨过零点的通知可能不在主线程发出；刷新时间线不碰本类的状态，不必回到主线程。
    @objc nonisolated private func clockChanged() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
