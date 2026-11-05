import Foundation

/// 通知相关的固定文案 (PRD 4.6.3)，外壳原样展示。
public enum NotificationCopy {
    /// 系统拒绝通知权限时设置页的提示 (AC-SET-05，PRD 4.3.5 #15)。
    public static let permissionDenied = "通知被关了，去系统设置里打开"

    /// 下班通知正文：老板路过模式下不含金额 (AC-BOSS-03)。
    /// 结算按滚动区域以外的格式截掉末尾 0，如「1000」「952.381」(PRD 4.7.1 第 5 条)。
    static func offWork(settlement: Decimal, bossMode: Bool) -> String {
        bossMode ? "今天的砖搬完了，可以走了" : "今日 \(Format.trimmed(settlement)) 元已到账，可以走了"
    }
}
