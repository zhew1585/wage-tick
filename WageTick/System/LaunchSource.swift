import AppKit
import ServiceManagement

/// 这次启动是不是开机自启拉起来的，在 `applicationDidFinishLaunching` 里判断。
/// 牛马自己打开时系统会发「打开应用」事件；登录项 (`SMAppService.mainApp`) 由 launchd 拉起，没有这个事件，
/// 旧式登录项的事件里则带「作为登录项启动」标记。两种都算开机自启。
@MainActor
enum LaunchSource {
    static var isLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            // 没有启动事件：只有被 launchd 按登录项拉起时才会这样，且登录项须已注册。
            return SMAppService.mainApp.status == .enabled
        }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
