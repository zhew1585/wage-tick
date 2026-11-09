import AppKit

/// 隐藏 Dock 图标 (ADR-0005 补充)：切换 App 的激活策略。
/// 隐藏时是 `.accessory`：不进 Dock 和 ⌘Tab，屏幕顶部不显示主菜单，但主菜单的快捷键 (⌘V、⌘1 等) 照常可用；窗口仍从菜单栏小牛打开。
@MainActor
enum DockIcon {
    /// 启动时与设置页开关时调用。切换后把牛马拉回前台，免得正在看的设置窗口被换到别的 App 后面。
    static func apply(hidden: Bool) {
        let policy: NSApplication.ActivationPolicy = hidden ? .accessory : .regular
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        NSApp.activate()
    }
}
