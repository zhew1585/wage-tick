import Foundation
import OSLog
import WageCore

/// 节假日数据源适配器：对核心只提供"节假日表" (`table`)，内置、缓存、联网、重试都藏在这里。
///
/// 数据来源优先级：安装包内置 > 本机缓存 > 联网获取。
/// 某年内置或缓存已有时不联网；没有时 `ensure(year:)` 联网获取 (只下载不上传)，成功后写入缓存，
/// 之后离线重启也能用；失败时该年记为缺失 (核心据此按双休计算并提示)，下次调用 `ensure` 再试。
/// 外壳负责在启动、唤醒和定时器里调用 `ensure`，决定重试节奏。
@MainActor
public final class HolidaySource {
    /// 当前的节假日表：所有已知年份的数据，加上最近一次获取失败的年份。
    public private(set) var table: HolidayTable = .empty

    private let cacheDirectory: URL
    private let fetcher: any HolidayFetching
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HolidaySource", category: "HolidaySource")
    /// 已有数据的年份文件，按年份索引。
    private var files: [Int: HolidayCNFile] = [:]
    private var missingYears: Set<Int> = []
    /// 正在联网获取的年份，避免启动和唤醒同时触发时重复下载。
    private var fetching: Set<Int> = []

    /// 文件名约定：内置与缓存目录里都是 `holiday-cn-<年份>.json`，内容为 holiday-cn 原始格式。
    private static let filePrefix = "holiday-cn-"

    /// 同步读入内置与缓存数据，构造好就能给出节假日表，不等联网。
    /// - Parameters:
    ///   - bundledDirectory: 安装包内置数据所在目录 (App 里是资源目录)；没有内置数据时为 nil。
    ///   - cacheDirectory: 联网获取结果的缓存目录，不存在时首次写入时创建。
    public init(bundledDirectory: URL?, cacheDirectory: URL, fetcher: any HolidayFetching) {
        self.cacheDirectory = cacheDirectory
        self.fetcher = fetcher
        // 先读缓存再读内置，同一年份内置覆盖缓存。
        files = loadFiles(in: cacheDirectory)
        if let bundledDirectory {
            files.merge(loadFiles(in: bundledDirectory)) { _, bundled in bundled }
        }
        rebuildTable()
    }

    /// 保证 `year` 有数据。已有时直接返回；否则联网获取一次，成功则并入并缓存，失败则记为缺失。
    public func ensure(year: Int) async {
        guard files[year] == nil, !fetching.contains(year) else { return }
        fetching.insert(year)
        defer { fetching.remove(year) }
        do {
            let data = try await fetcher.fetch(year: year)
            let file = try HolidayCNFile(data: data)
            guard file.year == year else { throw HolidayCNFileError.wrongYear(expected: year, actual: file.year) }
            files[year] = file
            missingYears.remove(year)
            save(data, year: year)
        } catch {
            logger.error("\(year, privacy: .public) 年节假日数据获取失败，按双休计算，稍后重试：\(String(describing: error), privacy: .public)")
            missingYears.insert(year)
        }
        rebuildTable()
    }

    /// 按年份从小到大合并，跨年的日子以较晚年份的文件为准。
    private func rebuildTable() {
        var days: [LocalDate: HolidayKind] = [:]
        for year in files.keys.sorted() {
            days.merge(files[year]!.days) { _, later in later }
        }
        table = HolidayTable(days: days, missingYears: missingYears)
    }

    /// 读目录里所有 `holiday-cn-*.json`；读不了或格式不对的跳过并记日志，相当于没有该年数据。
    private func loadFiles(in directory: URL) -> [Int: HolidayCNFile] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path())) ?? []
        var result: [Int: HolidayCNFile] = [:]
        for name in names where name.hasPrefix(Self.filePrefix) && name.hasSuffix(".json") {
            let url = directory.appending(path: name)
            do {
                let file = try HolidayCNFile(data: Data(contentsOf: url))
                result[file.year] = file
            } catch {
                logger.error("跳过无法使用的节假日文件 \(url.path(), privacy: .public)：\(String(describing: error), privacy: .public)")
            }
        }
        return result
    }

    /// 写缓存失败只记日志：本次运行内存里的数据照用，下次启动会重新获取。
    private func save(_ data: Data, year: Int) {
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: cacheDirectory.appending(path: "\(Self.filePrefix)\(year).json"), options: .atomic)
        } catch {
            logger.error("\(year, privacy: .public) 年节假日数据缓存失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
