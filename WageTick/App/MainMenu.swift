import AppKit

/// 屏幕顶部的主菜单 (普通 App 必备，见 ADR-0005)：「牛马鼓励器」「编辑」「窗口」三组。
/// 菜单栏小牛的左键菜单是另一份 (`StatusItemController`)，两边同一入口用同一个快捷键。
/// 编辑菜单的撤销、剪切、复制、粘贴、全选走响应链，输入框里的 ⌘V 等才有用。
/// 引导完成前今日概览、目标、历史、设置置灰 (还没有月薪与作息，打开也是空的)。
///
/// 用法 (启动时)：`MainMenu(actions: ...).install()`，之后由 AppKit 持有菜单，本对象需由调用方持有 (菜单项的 target)。
@MainActor
final class MainMenu: NSObject, NSMenuItemValidation {
    struct Actions {
        let isOnboarded: () -> Bool
        let openTodayPanel: () -> Void
        let openGoals: () -> Void
        let openHistory: () -> Void
        let openSettings: () -> Void
    }

    private static let appName = AppIdentity.displayName

    private let actions: Actions
    /// 只有引导完成后才可用的菜单项 (target 为 self 的那些)。
    private let onboardedOnly: Set<Selector> = [
        #selector(todayPanelClicked), #selector(goalsClicked), #selector(historyClicked), #selector(settingsClicked),
    ]

    init(actions: Actions) {
        self.actions = actions
    }

    func install() {
        let windowMenu = makeWindowMenu()
        let main = NSMenu()
        for menu in [makeAppMenu(), makeEditMenu(), windowMenu] {
            let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            item.submenu = menu
            main.addItem(item)
        }
        NSApp.mainMenu = main
        // 交给系统管理：自动列出打开的窗口、补上「前置全部窗口」。
        NSApp.windowsMenu = windowMenu
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action, onboardedOnly.contains(action) else { return true }
        return actions.isOnboarded()
    }

    // MARK: 各组菜单

    private func makeAppMenu() -> NSMenu {
        let menu = NSMenu(title: Self.appName)
        menu.addItem(item("关于\(Self.appName)", #selector(aboutClicked)))
        menu.addItem(.separator())
        menu.addItem(item("设置…", #selector(settingsClicked), key: ","))
        menu.addItem(.separator())
        menu.addItem(system("隐藏\(Self.appName)", #selector(NSApplication.hide(_:)), key: "h"))
        menu.addItem(system("隐藏其他", #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option]))
        menu.addItem(system("全部显示", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(system("退出\(Self.appName)", #selector(NSApplication.terminate(_:)), key: "q"))
        return menu
    }

    private func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: "编辑")
        menu.addItem(responder("撤销", Selector(("undo:")), key: "z"))
        menu.addItem(responder("重做", Selector(("redo:")), key: "z", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(responder("剪切", #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(responder("复制", #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(responder("粘贴", #selector(NSText.paste(_:)), key: "v"))
        menu.addItem(responder("全选", #selector(NSText.selectAll(_:)), key: "a"))
        return menu
    }

    private func makeWindowMenu() -> NSMenu {
        let menu = NSMenu(title: "窗口")
        menu.addItem(responder("最小化", #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        menu.addItem(responder("关闭窗口", #selector(NSWindow.performClose(_:)), key: "w"))
        menu.addItem(.separator())
        menu.addItem(item("今日概览", #selector(todayPanelClicked), key: "1"))
        menu.addItem(item("目标", #selector(goalsClicked), key: "2"))
        menu.addItem(item("历史", #selector(historyClicked), key: "3"))
        menu.addItem(.separator())
        return menu
    }

    // MARK: 菜单项

    /// 本 App 的入口，target 为 self。
    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// 发给 NSApp 的标准动作。
    private func system(_ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = NSApp
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    /// target 留空，沿响应链交给当前焦点 (输入框、key window)。
    private func responder(_ title: String, _ action: Selector, key: String, modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    // MARK: 动作

    @objc private func aboutClicked() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: Self.appName])
    }

    @objc private func settingsClicked() { actions.openSettings() }
    @objc private func todayPanelClicked() { actions.openTodayPanel() }
    @objc private func goalsClicked() { actions.openGoals() }
    @objc private func historyClicked() { actions.openHistory() }
}
