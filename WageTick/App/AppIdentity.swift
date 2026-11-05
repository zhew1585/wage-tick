import Foundation

/// App 自身的标识，日志子系统和存储目录共用。
enum AppIdentity {
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.zhew1585.WageTick"
    /// 给人看的 App 名 (Info.plist 的 CFBundleDisplayName)，主菜单、关于窗口用。
    static let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "牛马鼓励器"
}
