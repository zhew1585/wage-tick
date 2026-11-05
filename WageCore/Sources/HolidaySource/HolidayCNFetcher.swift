import Foundation

/// 联网获取某一年的节假日原始数据 (holiday-cn 格式)。测试里用替身，不真联网。
public protocol HolidayFetching: Sendable {
    func fetch(year: Int) async throws -> Data
}

/// 从公开的 holiday-cn 项目下载年份文件，只发 GET，不上传任何数据 (ADR-0002)。
/// 依次尝试各镜像：jsDelivr 在国内通常更稳，失败再走 GitHub 原站。
public struct HolidayCNFetcher: HolidayFetching {
    /// 发一个 GET 请求，返回响应体与响应头。
    public typealias Transport = @Sendable (URL) async throws -> (Data, URLResponse)

    private static let mirrors = [
        "https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/%d.json",
        "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/%d.json",
    ]

    /// 单次请求超时 (秒)，放短一些，失败交给之后的重试。
    private static let requestTimeout: TimeInterval = 15

    /// 不带 cookie、不落 URL 缓存的会话。
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        return URLSession(configuration: configuration)
    }()

    private let transport: Transport

    /// 真联网。
    public init() {
        self.init { try await Self.session.data(from: $0) }
    }

    /// 测试用：换掉网络层。
    public init(transport: @escaping Transport) {
        self.transport = transport
    }

    /// 返回第一个以 200 响应的镜像的内容；全部失败时抛出最后一个错误。内容是否有效由调用方校验。
    public func fetch(year: Int) async throws -> Data {
        var lastError: any Error = HolidayFetchError.noMirror
        for mirror in Self.mirrors {
            let url = URL(string: String(format: mirror, year))!
            do {
                let (data, response) = try await transport(url)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else { throw HolidayFetchError.badStatus(status, url) }
                return data
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

enum HolidayFetchError: Error, CustomStringConvertible {
    case noMirror
    case badStatus(Int, URL)

    var description: String {
        switch self {
        case .noMirror: "没有可用的镜像"
        case .badStatus(let status, let url): "\(url) 返回 \(status)"
        }
    }
}
