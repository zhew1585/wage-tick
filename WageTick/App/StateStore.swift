import Foundation
import OSLog
import WageCore

/// 本地存储适配器：把核心状态存成本机 JSON 文件 (ADR-0002)，带版本号便于以后迁移。
/// 位置：~/Library/Application Support/<bundle id>/state.json。
@MainActor
final class StateStore {
    /// 当前文件格式版本。改动 `AppState` 的编码结构时 +1 并补迁移。
    private static let currentVersion = 1
    private let fileURL: URL
    private let logger = Logger(subsystem: "com.zhew1585.WageTick", category: "StateStore")

    init(directory: URL = StateStore.defaultDirectory) {
        fileURL = directory.appending(path: "state.json")
    }

    /// 读出状态。没有文件视为首次打开；文件损坏或版本不认识时移到旁边留底，从头开始。
    func load() -> AppState {
        guard FileManager.default.fileExists(atPath: fileURL.path()) else { return AppState() }
        do {
            let file = try JSONDecoder().decode(StateFile.self, from: Data(contentsOf: fileURL))
            guard file.version == Self.currentVersion else {
                throw StoreError.unsupportedVersion(file.version)
            }
            return file.state
        } catch {
            logger.error("状态文件读取失败，已移到旁边留底后从头开始：\(error.localizedDescription, privacy: .public)")
            quarantineUnreadableFile()
            return AppState()
        }
    }

    /// 原子写入状态。失败只记日志：内存里的状态仍然有效，下一次命令会再写。
    func save(_ state: AppState) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(StateFile(version: Self.currentVersion, state: state))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("状态文件写入失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    private func quarantineUnreadableFile() {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: backup)
        } catch {
            logger.error("无法移走损坏的状态文件：\(error.localizedDescription, privacy: .public)")
        }
    }

    private static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: Bundle.main.bundleIdentifier ?? "com.zhew1585.WageTick")
    }
}

private struct StateFile: Codable {
    let version: Int
    let state: AppState
}

private enum StoreError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "不认识的状态文件版本 \(version)"
        }
    }
}
