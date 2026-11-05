import Foundation

/// 核心计算的状态：只保存牛马手动产生的内容与配置，推导内容一律不存 (PRD 4.3.1)。
/// 由外壳持久化到本机 (ADR-0002)，通过 `apply` 演进，通过 `snapshot` 读出。
public struct AppState: Sendable, Equatable, Codable {
    /// 引导完成后才有；nil 即"未完成引导"。
    public internal(set) var profile: Profile?
    /// 界面设置 (老板路过等)，引导前也有默认值。
    public internal(set) var settings: InterfaceSettings
    /// 日记录 (PRD 4.3.1)：一天最多一条，只存牛马手动产生的内容，按日期升序。
    public internal(set) var dayRecords: [DayRecord]
    /// 目标，按新建顺序 (PRD 4.5)。
    public internal(set) var goals: [Goal]

    /// 下班事件的进度 (见 `OffWorkWatch`)。不是牛马产生的内容，但重启后要记得今天发没发过，所以要存。
    var offWorkWatch: OffWorkWatch?
    /// 已达成、庆祝动画还没在面板上播放的目标编号，按达成先后 (见 `completeReachedGoal`)。
    var pendingCelebrations: [Int]

    private enum CodingKeys: String, CodingKey { case profile, settings, dayRecords, goals, offWorkWatch, pendingCelebrations }

    public init() {
        profile = nil
        settings = InterfaceSettings()
        dayRecords = []
        goals = []
        offWorkWatch = nil
        pendingCelebrations = []
    }

    /// #2 写出的旧文件没有 `settings`，读入时取默认值，不当作损坏文件。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decodeIfPresent(Profile.self, forKey: .profile)
        settings = try container.decodeIfPresent(InterfaceSettings.self, forKey: .settings) ?? InterfaceSettings()
        // #7 之前的旧文件没有日记录。
        let records = try container.decodeIfPresent([DayRecord].self, forKey: .dayRecords) ?? []
        let ids = records.flatMap(\.deductions).map(\.id)
        guard Set(records.map(\.date)).count == records.count, Set(ids).count == ids.count else {
            throw DecodingError.dataCorruptedError(forKey: .dayRecords, in: container, debugDescription: "同一天有多条日记录，或扣钱记录标识重复")
        }
        dayRecords = records.sorted { $0.date < $1.date }
        // #11 之前的旧文件没有目标，读入时为空队列。
        goals = try container.decodeIfPresent([Goal].self, forKey: .goals) ?? []
        // #10 之前的旧文件没有下班事件进度，读入时当作今天还没看到过上班。
        offWorkWatch = try container.decodeIfPresent(OffWorkWatch.self, forKey: .offWorkWatch)
        // #13 之前的旧文件没有待播放的动画，已完成的目标不补播。
        pendingCelebrations = try container.decodeIfPresent([Int].self, forKey: .pendingCelebrations) ?? []
    }
}

/// 完成引导后的牛马配置。
public struct Profile: Sendable, Equatable, Codable {
    /// 安装日期，即完成引导那天；历史从这个月开始 (PRD 4.1.1)。
    public let installDate: LocalDate
    /// 按月份记录的月薪，按月份升序，至少一条。未来月份沿用最近一次设置 (PRD 4.2.1)。
    public internal(set) var salaries: [MonthlySalary]
    /// 当前作息：最近一次修改的版本。某一天实际采用的作息用 `schedule(on:)`。
    public var schedule: WorkSchedule { schedules[schedules.count - 1].schedule }
    public internal(set) var launchAtLogin: Bool
    /// 作息版本，按生效日期升序，至少一条 (issue #1 状态清单)。
    /// 修改作息从今天起生效，过去的日子保留当时的作息 (PRD 4.2.3 #2)；最早一条也覆盖它之前的日子。
    public internal(set) var schedules: [ScheduleVersion]

    private enum CodingKeys: String, CodingKey { case installDate, salaries, launchAtLogin, schedules }
    /// #2 至 #5 写出的旧文件只有一份作息，没有版本。
    private enum LegacyCodingKeys: String, CodingKey { case schedule }

    /// 引导时的配置：作息只有一个版本，从安装日起生效。
    init(installDate: LocalDate, salaries: [MonthlySalary], schedule: WorkSchedule, launchAtLogin: Bool) {
        self.init(
            installDate: installDate,
            salaries: salaries,
            schedules: [ScheduleVersion(effectiveFrom: installDate, schedule: schedule)],
            launchAtLogin: launchAtLogin
        )
    }

    init(installDate: LocalDate, salaries: [MonthlySalary], schedules: [ScheduleVersion], launchAtLogin: Bool) {
        self.installDate = installDate
        self.salaries = salaries
        self.schedules = schedules
        self.launchAtLogin = launchAtLogin
    }

    /// 从文件读入时至少要有一条月薪、一个作息版本，并按月份、生效日期排好序，供 `salary(for:)`、`schedule(on:)` 查找。
    /// 旧文件没有作息版本时，把那一份作息当作从安装日起生效。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let installDate = try container.decode(LocalDate.self, forKey: .installDate)
        let salaries = try container.decode([MonthlySalary].self, forKey: .salaries)
        guard !salaries.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .salaries, in: container, debugDescription: "没有任何月薪记录")
        }
        let schedules = try container.decodeIfPresent([ScheduleVersion].self, forKey: .schedules) ?? [
            ScheduleVersion(
                effectiveFrom: installDate,
                schedule: try decoder.container(keyedBy: LegacyCodingKeys.self).decode(WorkSchedule.self, forKey: .schedule)
            ),
        ]
        guard !schedules.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .schedules, in: container, debugDescription: "没有任何作息")
        }
        self.init(
            installDate: installDate,
            salaries: salaries.sorted { $0.month < $1.month },
            schedules: schedules.sorted { $0.effectiveFrom < $1.effectiveFrom },
            launchAtLogin: try container.decode(Bool.self, forKey: .launchAtLogin)
        )
    }

    /// 某天采用的作息：该天及之前最近一次生效的版本；早于最早版本的日子 (如安装前) 按最早版本。
    func schedule(on day: LocalDate) -> WorkSchedule {
        (schedules.last { $0.effectiveFrom <= day } ?? schedules[0]).schedule
    }

    /// 某月适用的月薪：该月及之前最近一次设置的月薪。
    /// 系统时间被拨回到安装月之前时 (PRD 4.3.5 #11)，退回最早一条。
    func salary(for month: YearMonth) -> Decimal {
        let entry = salaries.last { $0.month <= month } ?? salaries[0]
        return entry.amount
    }
}

/// 某个月的月薪。
/// 金额编码为字符串，避免 JSON 数字经二进制浮点往返丢精度。
public struct MonthlySalary: Sendable, Equatable, Codable {
    public let month: YearMonth
    public let amount: Decimal

    private enum CodingKeys: String, CodingKey { case month, amount }

    init(month: YearMonth, amount: Decimal) {
        self.month = month
        self.amount = amount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        month = try container.decode(YearMonth.self, forKey: .month)
        let text = try container.decode(String.self, forKey: .amount)
        guard let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              Validation.monthlySalary(amount) == nil else {
            throw DecodingError.dataCorruptedError(forKey: .amount, in: container, debugDescription: "月薪不是正数：\(text)")
        }
        self.amount = amount
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(month, forKey: .month)
        try container.encode(NSDecimalNumber(decimal: amount).stringValue, forKey: .amount)
    }
}

/// 一个作息版本：从 `effectiveFrom` 这天起采用 `schedule`，直到下一个版本生效。
public struct ScheduleVersion: Sendable, Equatable, Codable {
    public let effectiveFrom: LocalDate
    public let schedule: WorkSchedule

    init(effectiveFrom: LocalDate, schedule: WorkSchedule) {
        self.effectiveFrom = effectiveFrom
        self.schedule = schedule
    }
}
