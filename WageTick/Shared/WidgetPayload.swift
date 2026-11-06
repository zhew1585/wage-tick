import Foundation
import WageCore

/// App 交给桌面小组件 (PRD F14) 的数据：当前状态与节假日表，小组件据此调核心的 `widgetTimeline` 自己推导，与 App 用同一套算法。
/// App 与小组件扩展两个 target 都编译这个文件：App 写 (`WidgetBridge`)，扩展读。
///
/// 位置：~/Library/Application Support/com.zhew1585.WageTick/widget.json，与 state.json 同一目录。
/// 扩展必须开沙盒，靠 `WageTickWidgets.entitlements` 里对这个目录的只读临时例外读它 (App 是 ad-hoc 签名，没有 Team ID，用不了 App Group)。
/// 目录名写死 App 的 bundle id：扩展里 `Bundle.main` 是扩展自己的，沙盒里的 `NSHomeDirectory()` 也是容器目录，都不能用。
struct WidgetPayload: Codable {
    /// 文件格式版本。改了编码结构、旧文件读不回时 +1；读到不认识的版本按没有数据处理，等 App 重写。
    static let currentVersion = 1

    let version: Int
    let state: AppState
    let holidays: HolidayTable

    init(state: AppState, holidays: HolidayTable) {
        version = Self.currentVersion
        self.state = state
        self.holidays = holidays
    }

    /// App 的 bundle id，也是 Application Support 下的目录名，须与扩展 entitlements 里的路径一致。
    static let appFolder = "com.zhew1585.WageTick"

    /// widget.json 的位置，按真实的用户主目录 (不是沙盒容器) 算。
    static var fileURL: URL {
        URL(fileURLWithPath: realHomeDirectory, isDirectory: true)
            .appending(path: "Library/Application Support")
            .appending(path: appFolder)
            .appending(path: "widget.json")
    }

    /// 读出数据；没有文件、读不了或版本不认识时为 nil (小组件按未完成引导提示打开 App)。
    static func load() -> WidgetPayload? {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(WidgetPayload.self, from: data),
              payload.version == currentVersion else { return nil }
        return payload
    }

    /// 编码成要写入的内容，键排好序，内容不变时字节也不变 (App 据此判断要不要重写、刷新小组件)。
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// 真实的用户主目录：沙盒里 `NSHomeDirectory()` 指向容器，这里按账户信息取。
    private static var realHomeDirectory: String {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else { return NSHomeDirectory() }
        return String(cString: directory)
    }
}
