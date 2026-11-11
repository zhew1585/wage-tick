import Foundation

/// 核心计算的状态：只保存牛马手动产生的内容与配置，推导内容一律不存 (PRD 4.3.1)。
/// 由外壳持久化到本机 (ADR-0002)，通过 `apply` 演进，通过 `snapshot` 读出。
public struct AppState: Sendable, Equatable, Codable {
    /// 引导完成后才有；nil 即"未完成引导"。
    public internal(set) var profile: Profile?
    /// 界面设置 (显示模式、通知开关等)，引导前也有默认值。
    public internal(set) var settings: InterfaceSettings
    /// 日记录 (PRD 4.3.1)：一天最多一条，只存牛马手动产生的内容，按日期升序。
    public internal(set) var dayRecords: [DayRecord]
    /// 目标，按新建顺序 (PRD 4.5)。
    public internal(set) var goals: [Goal]

    /// 下班事件的进度 (见 `OffWorkWatch`)。不是牛马产生的内容，但重启后要记得今天发没发过，所以要存。
    var offWorkWatch: OffWorkWatch?
    /// 已达成、庆祝动画还没在面板上播放的目标编号，按达成先后 (见 `completingReachedGoals`)。
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
        // #7 之前的旧文件没有日记录。旧格式的请假按那天生效的作息换算成时段 (PRD V1.8)。
        let records = try Self.decodeDayRecords(from: container, schedule: profile.map { profile in { profile.schedule(on: $0) } })
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

    /// 逐条读日记录，好把作息交给旧格式请假的换算；没有引导配置 (`schedule` 为 nil) 时旧格式请假拒绝读入。
    private static func decodeDayRecords(
        from container: KeyedDecodingContainer<CodingKeys>, schedule: ((LocalDate) -> WorkSchedule)?
    ) throws -> [DayRecord] {
        guard container.contains(.dayRecords), try !container.decodeNil(forKey: .dayRecords) else { return [] }
        var list = try container.nestedUnkeyedContainer(forKey: .dayRecords)
        var records: [DayRecord] = []
        while !list.isAtEnd {
            records.append(try DayRecord(from: list.superDecoder(), legacySchedule: { date in schedule?(date) }))
        }
        return records
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
    /// 按月份记录的休息模式，按月份升序，至少一条 (PRD 4.2.2)。与月薪一样：修改对当月整月生效，
    /// 未来月份沿用最近一次设置，过去的月份保留当时的模式。某月实际采用的模式用 `restMode(for:)`。
    public internal(set) var restModes: [MonthlyRestMode]
    /// 发薪日 (issue #20)，全局一份；没设时为 nil，不显示距发薪。
    public internal(set) var payday: Payday?

    private enum CodingKeys: String, CodingKey { case installDate, salaries, launchAtLogin, schedules, restModes, payday }
    /// #2 至 #5 写出的旧文件只有一份作息，没有版本。
    private enum LegacyCodingKeys: String, CodingKey { case schedule }

    /// 引导时的配置：作息只有一个版本，从安装日起生效；休息模式只有安装当月一条。
    init(installDate: LocalDate, salaries: [MonthlySalary], schedule: WorkSchedule, restMode: RestMode, launchAtLogin: Bool) {
        self.init(
            installDate: installDate,
            salaries: salaries,
            schedules: [ScheduleVersion(effectiveFrom: installDate, schedule: schedule)],
            restModes: [MonthlyRestMode(month: installDate.yearMonth, mode: restMode)],
            launchAtLogin: launchAtLogin
        )
    }

    init(
        installDate: LocalDate, salaries: [MonthlySalary], schedules: [ScheduleVersion], restModes: [MonthlyRestMode],
        launchAtLogin: Bool, payday: Payday? = nil
    ) {
        self.installDate = installDate
        self.salaries = salaries
        self.schedules = schedules
        self.restModes = restModes
        self.launchAtLogin = launchAtLogin
        self.payday = payday
    }

    /// 从文件读入时至少要有一条月薪、一个作息版本、一条休息模式，并按月份、生效日期排好序，
    /// 供 `salary(for:)`、`schedule(on:)`、`restMode(for:)` 查找。
    /// 旧文件没有作息版本时，把那一份作息当作从安装日起生效；没有休息模式时 (V1.9 之前) 当作安装当月起双休。
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
        let restModes = try container.decodeIfPresent([MonthlyRestMode].self, forKey: .restModes)
            ?? [MonthlyRestMode(month: installDate.yearMonth, mode: .twoDaysOff)]
        guard !restModes.isEmpty, Set(restModes.map(\.month)).count == restModes.count else {
            throw DecodingError.dataCorruptedError(forKey: .restModes, in: container, debugDescription: "休息模式为空或同一个月有多条")
        }
        self.init(
            installDate: installDate,
            salaries: salaries.sorted { $0.month < $1.month },
            schedules: schedules.sorted { $0.effectiveFrom < $1.effectiveFrom },
            restModes: restModes.sorted { $0.month < $1.month },
            launchAtLogin: try container.decode(Bool.self, forKey: .launchAtLogin),
            // #20 之前的旧文件没有发薪日，读入为未设置。
            payday: try container.decodeIfPresent(Payday.self, forKey: .payday)
        )
    }

    /// 某天采用的作息：该天及之前最近一次生效的版本；早于最早版本的日子 (如安装前) 按最早版本。
    func schedule(on day: LocalDate) -> WorkSchedule {
        (schedules.last { $0.effectiveFrom <= day } ?? schedules[0]).schedule
    }

    /// 某月适用的工资记录 (金额与算法)：该月及之前最近一次设置的那条。
    /// 系统时间被拨回到安装月之前时 (PRD 4.3.5 #11)，退回最早一条。
    func pay(for month: YearMonth) -> MonthlySalary {
        salaries.last { $0.month <= month } ?? salaries[0]
    }

    /// 某月适用的工资金额 (月薪或日薪，看 `pay(for:).basis`)。
    func salary(for month: YearMonth) -> Decimal {
        pay(for: month).amount
    }

    /// 某月采用的休息模式，查找规则同 `salary(for:)`。
    func restMode(for month: YearMonth) -> RestMode {
        (restModes.last { $0.month <= month } ?? restModes[0]).mode
    }
}

/// 某个月的工资：金额与算法 (按月的月薪或按天的日薪，`PayBasis`)。
/// 金额编码为字符串，避免 JSON 数字经二进制浮点往返丢精度；V1.16 之前的记录没有 `basis`，读回为按月。
public struct MonthlySalary: Sendable, Equatable, Codable {
    public let month: YearMonth
    public let amount: Decimal
    public let basis: PayBasis

    private enum CodingKeys: String, CodingKey { case month, amount, basis }

    init(month: YearMonth, amount: Decimal, basis: PayBasis = .monthly) {
        self.month = month
        self.amount = amount
        self.basis = basis
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        month = try container.decode(YearMonth.self, forKey: .month)
        let text = try container.decode(String.self, forKey: .amount)
        basis = try container.decodeIfPresent(PayBasis.self, forKey: .basis) ?? .monthly
        guard let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              Validation.salary(amount, basis: basis) == nil else {
            throw DecodingError.dataCorruptedError(forKey: .amount, in: container, debugDescription: "工资不是正数：\(text)")
        }
        self.amount = amount
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(month, forKey: .month)
        try container.encode(NSDecimalNumber(decimal: amount).stringValue, forKey: .amount)
        try container.encode(basis, forKey: .basis)
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
