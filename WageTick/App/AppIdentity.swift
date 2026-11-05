import Foundation

/// App 自身的标识，日志子系统和存储目录共用。
enum AppIdentity {
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.zhew1585.WageTick"
}
