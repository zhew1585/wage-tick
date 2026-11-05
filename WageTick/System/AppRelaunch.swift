import AppKit

/// 退出后重新打开自己：起一个 shell 等当前进程退出，再用 `open` 打开同一个 App 包，然后退出。
@MainActor
enum AppRelaunch {
    static func relaunch() {
        let script = "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \"$0\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script, Bundle.main.bundleURL.path, String(ProcessInfo.processInfo.processIdentifier)]
        do {
            try task.run()
        } catch {
            // 起不来就只退出，牛马自己再打开一次即可。
            NSLog("重启失败：%@", error.localizedDescription)
        }
        NSApp.terminate(nil)
    }
}
