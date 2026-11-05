import Foundation
import HolidaySource
import Testing
import WageCore

// 节假日数据源适配器：用固定的 holiday-cn 样例文件测解析、内置优先、缓存命中、获取失败报告缺失。
// 网络一律用替身，不真联网。
//
// Fixtures/holiday-cn-2026.json   holiday-cn 2026 年真实数据，充当安装包内置数据
// Fixtures/published-2027.json    虚构的 2027 年数据 (元旦 1 月 1 日放假、1 月 9 日周六上班)，充当联网获取结果
// Fixtures/unpublished-2027.json  holiday-cn 在国务院发布前的 2027.json：文件存在但 days 为空
// Fixtures/malformed-2027.json    日期格式不对的坏数据

private let fixtures = Bundle.module.resourceURL!.appending(path: "Fixtures")

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: fixtures.appending(path: name))
}

private func date(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
    LocalDate(year: year, month: month, day: day)
}

/// 每个测试一个空的缓存目录。
private func emptyCacheDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "HolidaySourceTests-\(UUID().uuidString)")
}

/// 联网替身：按年份返回预设结果，并记下被请求过哪些年份。
private actor FakeFetcher: HolidayFetching {
    private var responses: [Int: Result<Data, any Error>]
    private(set) var requestedYears: [Int] = []

    init(_ responses: [Int: Result<Data, any Error>] = [:]) {
        self.responses = responses
    }

    func respond(to year: Int, with response: Result<Data, any Error>) {
        responses[year] = response
    }

    func fetch(year: Int) async throws -> Data {
        requestedYears.append(year)
        guard let response = responses[year] else { throw URLError(.notConnectedToInternet) }
        return try response.get()
    }
}

@MainActor
@Suite("节假日数据源：内置数据")
struct BundledHolidayTests {
    @Test("解析 holiday-cn 格式：国庆 10 月 1 日至 7 日为法定节假日，10 月 10 日、春节前 2 月 14 日为调休上班日")
    func parsesBundledFile() {
        let source = HolidaySource(bundledDirectory: fixtures, cacheDirectory: emptyCacheDirectory(), fetcher: FakeFetcher())

        #expect((1...7).allSatisfy { source.table.kind(on: date(2026, 10, $0)) == .holiday })
        #expect(source.table.kind(on: date(2026, 10, 10)) == .makeupDay)
        #expect(source.table.kind(on: date(2026, 2, 14)) == .makeupDay)
        #expect(source.table.kind(on: date(2026, 10, 8)) == nil)
        // 2026 年共 33 个放假日、6 个调休上班日。
        #expect(source.table.days.values.filter { $0 == .holiday }.count == 33)
        #expect(source.table.days.values.filter { $0 == .makeupDay }.count == 6)
        #expect(source.table.missingYears.isEmpty)
    }

    @Test("内置优先：内置已有当年数据时不联网，联网结果也不会覆盖内置数据")
    func bundledYearSkipsNetwork() async throws {
        let fetcher = FakeFetcher([2026: .success(try fixture("published-2027.json"))])
        let source = HolidaySource(bundledDirectory: fixtures, cacheDirectory: emptyCacheDirectory(), fetcher: fetcher)

        await source.update(today: date(2026, 3, 2))

        #expect(await fetcher.requestedYears.isEmpty)
        #expect(source.table.kind(on: date(2026, 10, 1)) == .holiday)
    }
}

@MainActor
@Suite("节假日数据源：联网获取与缓存")
struct FetchedHolidayTests {
    @Test("没有内置数据的年份联网获取，成功后并入节假日表")
    func fetchesMissingYear() async throws {
        let fetcher = FakeFetcher([2027: .success(try fixture("published-2027.json"))])
        let source = HolidaySource(bundledDirectory: fixtures, cacheDirectory: emptyCacheDirectory(), fetcher: fetcher)

        await source.update(today: date(2027, 3, 2))

        #expect(await fetcher.requestedYears == [2027])
        #expect(source.table.kind(on: date(2027, 1, 1)) == .holiday)
        #expect(source.table.kind(on: date(2027, 1, 9)) == .makeupDay)
        #expect(source.table.kind(on: date(2026, 10, 1)) == .holiday)
        #expect(source.table.missingYears.isEmpty)
    }

    @Test("缓存命中：获取成功后缓存到本机，离线重启后不联网仍可用")
    func cachedYearSurvivesRestartOffline() async throws {
        let cache = emptyCacheDirectory()
        let online = HolidaySource(bundledDirectory: fixtures, cacheDirectory: cache, fetcher: FakeFetcher([2027: .success(try fixture("published-2027.json"))]))
        await online.update(today: date(2027, 3, 2))

        let offlineFetcher = FakeFetcher()
        let restarted = HolidaySource(bundledDirectory: fixtures, cacheDirectory: cache, fetcher: offlineFetcher)
        #expect(restarted.table.kind(on: date(2027, 1, 1)) == .holiday)

        await restarted.update(today: date(2027, 3, 2))
        #expect(await offlineFetcher.requestedYears.isEmpty)
        #expect(restarted.table.missingYears.isEmpty)
    }

    @Test("没有内置数据也能只靠缓存：内置目录为 nil")
    func worksWithoutBundledDirectory() async throws {
        let cache = emptyCacheDirectory()
        let online = HolidaySource(bundledDirectory: nil, cacheDirectory: cache, fetcher: FakeFetcher([2027: .success(try fixture("published-2027.json"))]))
        await online.update(today: date(2027, 3, 2))

        let restarted = HolidaySource(bundledDirectory: nil, cacheDirectory: cache, fetcher: FakeFetcher())
        #expect(restarted.table.kind(on: date(2027, 1, 9)) == .makeupDay)
        #expect(restarted.table.kind(on: date(2026, 10, 1)) == nil)
    }
}

@MainActor
@Suite("节假日数据源：获取失败")
struct FailedHolidayTests {
    @Test("4.3.5 #10 联网失败：该年报告为缺失，没有该年数据")
    func networkFailureReportsMissing() async {
        let source = HolidaySource(bundledDirectory: fixtures, cacheDirectory: emptyCacheDirectory(), fetcher: FakeFetcher())

        await source.update(today: date(2027, 3, 2))

        #expect(source.table.missingYears == [2027])
        #expect(source.table.kind(on: date(2027, 1, 1)) == nil)
        #expect(source.table.kind(on: date(2026, 10, 1)) == .holiday)
    }

    @Test("4.3.5 #10 之后自动重试：再次调用时重新联网，成功后不再缺失")
    func retriesAfterFailure() async throws {
        let fetcher = FakeFetcher()
        let source = HolidaySource(bundledDirectory: fixtures, cacheDirectory: emptyCacheDirectory(), fetcher: fetcher)
        await source.update(today: date(2027, 3, 2))

        await fetcher.respond(to: 2027, with: .success(try fixture("published-2027.json")))
        await source.update(today: date(2027, 3, 2))

        #expect(await fetcher.requestedYears == [2027, 2027])
        #expect(source.table.missingYears.isEmpty)
        #expect(source.table.kind(on: date(2027, 1, 1)) == .holiday)
    }

    @Test("国务院还没发布 (days 为空) 当作获取失败：报告缺失，不缓存，之后重试")
    func unpublishedYearCountsAsMissing() async throws {
        let cache = emptyCacheDirectory()
        let fetcher = FakeFetcher([2027: .success(try fixture("unpublished-2027.json"))])
        let source = HolidaySource(bundledDirectory: fixtures, cacheDirectory: cache, fetcher: fetcher)
        await source.update(today: date(2027, 3, 2))

        #expect(source.table.missingYears == [2027])

        let restartedFetcher = FakeFetcher()
        let restarted = HolidaySource(bundledDirectory: fixtures, cacheDirectory: cache, fetcher: restartedFetcher)
        await restarted.update(today: date(2027, 3, 2))
        #expect(await restartedFetcher.requestedYears == [2027])
    }

    @Test("格式不对的数据当作获取失败：报告缺失，一条也不并入")
    func malformedDataCountsAsMissing() async throws {
        let fetcher = FakeFetcher([2027: .success(try fixture("malformed-2027.json"))])
        let source = HolidaySource(bundledDirectory: fixtures, cacheDirectory: emptyCacheDirectory(), fetcher: fetcher)

        await source.update(today: date(2027, 3, 2))

        #expect(source.table.missingYears == [2027])
        #expect(source.table.kind(on: date(2027, 1, 1)) == nil)
    }

    @Test("拿到的是别的年份的文件：当作获取失败")
    func wrongYearCountsAsMissing() async throws {
        let fetcher = FakeFetcher([2028: .success(try fixture("published-2027.json"))])
        let source = HolidaySource(bundledDirectory: fixtures, cacheDirectory: emptyCacheDirectory(), fetcher: fetcher)

        await source.update(today: date(2028, 3, 2))

        #expect(source.table.missingYears == [2028])
        #expect(source.table.kind(on: date(2027, 1, 1)) == nil)
    }

    @Test("缓存文件损坏时忽略它，重新联网获取")
    func corruptCacheIsRefetched() async throws {
        let cache = emptyCacheDirectory()
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: cache.appending(path: "holiday-cn-2027.json"))
        let fetcher = FakeFetcher([2027: .success(try fixture("published-2027.json"))])
        let source = HolidaySource(bundledDirectory: fixtures, cacheDirectory: cache, fetcher: fetcher)

        await source.update(today: date(2027, 3, 2))

        #expect(await fetcher.requestedYears == [2027])
        #expect(source.table.kind(on: date(2027, 1, 1)) == .holiday)
    }
}

@MainActor
@Suite("节假日数据源：提前获取新一年")
struct NextYearHolidayTests {
    @Test("11 月起顺带获取下一年，跨年前就备好，12 月底的下一个应出勤日也算得准")
    func prefetchesNextYearFromNovember() async throws {
        let fetcher = FakeFetcher([2027: .success(try fixture("published-2027.json"))])
        let source = HolidaySource(bundledDirectory: fixtures, cacheDirectory: emptyCacheDirectory(), fetcher: fetcher)

        await source.update(today: date(2026, 11, 5))

        #expect(await fetcher.requestedYears == [2027])
        #expect(source.table.kind(on: date(2027, 1, 1)) == .holiday)
    }

    @Test("11 月之前不获取下一年：国务院还没发布，不白白联网")
    func noPrefetchBeforeNovember() async {
        let fetcher = FakeFetcher()
        let source = HolidaySource(bundledDirectory: fixtures, cacheDirectory: emptyCacheDirectory(), fetcher: fetcher)

        await source.update(today: date(2026, 10, 31))

        #expect(await fetcher.requestedYears.isEmpty)
    }

    @Test("下一年还没发布时记为缺失、之后重试，今年的数据不受影响")
    func unpublishedNextYearIsRetried() async throws {
        let fetcher = FakeFetcher([2027: .success(try fixture("unpublished-2027.json"))])
        let source = HolidaySource(bundledDirectory: fixtures, cacheDirectory: emptyCacheDirectory(), fetcher: fetcher)

        await source.update(today: date(2026, 12, 1))
        await fetcher.respond(to: 2027, with: .success(try fixture("published-2027.json")))
        await source.update(today: date(2026, 12, 1))

        #expect(await fetcher.requestedYears == [2027, 2027])
        #expect(source.table.missingYears.isEmpty)
        #expect(source.table.kind(on: date(2026, 10, 1)) == .holiday)
    }
}

@MainActor
@Suite("节假日数据源：外部数据校验")
struct HolidayDataValidationTests {
    @Test("日期不在该年前后一年之内的数据当作坏数据：报告缺失，一条也不并入")
    func outOfRangeDatesAreRejected() async {
        let data = Data(#"{"year": 2027, "days": [{"name": "元旦", "date": "2027-01-01", "isOffDay": true}, {"name": "?", "date": "2031-05-01", "isOffDay": true}]}"#.utf8)
        let source = HolidaySource(bundledDirectory: fixtures, cacheDirectory: emptyCacheDirectory(), fetcher: FakeFetcher([2027: .success(data)]))

        await source.update(today: date(2027, 3, 2))

        #expect(source.table.missingYears == [2027])
        #expect(source.table.kind(on: date(2027, 1, 1)) == nil)
    }

    @Test("缓存文件名的年份与内容不符时不用它，重新联网获取")
    func cacheFileWithWrongYearIsIgnored() async throws {
        let cache = emptyCacheDirectory()
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try fixture("published-2027.json").write(to: cache.appending(path: "holiday-cn-2028.json"))
        let fetcher = FakeFetcher()
        let source = HolidaySource(bundledDirectory: nil, cacheDirectory: cache, fetcher: fetcher)

        #expect(source.table.kind(on: date(2027, 1, 1)) == nil)
        await source.update(today: date(2027, 3, 2))
        #expect(await fetcher.requestedYears == [2027])
    }
}

/// 网络替身：按 URL 返回预设的状态码，并记下请求过的 URL。
private actor FakeTransport {
    private let statusByHost: [String: Int]
    private(set) var requested: [URL] = []

    init(statusByHost: [String: Int]) {
        self.statusByHost = statusByHost
    }

    func get(_ url: URL) throws -> (Data, URLResponse) {
        requested.append(url)
        guard let status = statusByHost[url.host() ?? ""] else { throw URLError(.cannotFindHost) }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data("\(url.host() ?? "")".utf8), response)
    }
}

@Suite("节假日数据源：holiday-cn 下载")
struct HolidayCNFetcherTests {
    @Test("先走 jsDelivr 镜像，成功即返回，只下载不上传 (GET)")
    func usesFirstMirror() async throws {
        let transport = FakeTransport(statusByHost: ["cdn.jsdelivr.net": 200, "raw.githubusercontent.com": 200])
        let fetcher = HolidayCNFetcher { try await transport.get($0) }

        let data = try await fetcher.fetch(year: 2027)

        #expect(String(decoding: data, as: UTF8.self) == "cdn.jsdelivr.net")
        #expect(await transport.requested.map(\.absoluteString) == [
            "https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/2027.json",
        ])
    }

    @Test("镜像返回非 200 或连不上时换下一个")
    func fallsBackToNextMirror() async throws {
        let transport = FakeTransport(statusByHost: ["cdn.jsdelivr.net": 404, "raw.githubusercontent.com": 200])
        let fetcher = HolidayCNFetcher { try await transport.get($0) }

        let data = try await fetcher.fetch(year: 2027)

        #expect(String(decoding: data, as: UTF8.self) == "raw.githubusercontent.com")
        #expect(await transport.requested.map(\.absoluteString) == [
            "https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/2027.json",
            "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/2027.json",
        ])
    }

    @Test("所有镜像都失败时抛错")
    func throwsWhenAllMirrorsFail() async {
        let transport = FakeTransport(statusByHost: ["cdn.jsdelivr.net": 500])
        let fetcher = HolidayCNFetcher { try await transport.get($0) }

        await #expect(throws: (any Error).self) { try await fetcher.fetch(year: 2027) }
    }
}
