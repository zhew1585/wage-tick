import Foundation

/// 日状态 (GLOSSARY)：只由当前时刻、是否应出勤和当日计划推导。
public enum DayStatus: Sendable, Equatable {
    case restDay     // 休息日
    case notStarted  // 未上班
    case working     // 上班中
    case lunchBreak  // 干饭中
    case onLeave     // 请假中：落在两段上班中间的请假 (PRD 4.4.2)
    case offWork     // 已下班
}

/// 今天的推导结果。
public struct Today: Sendable, Equatable {
    public let date: LocalDate
    public let status: DayStatus
    /// 当月日薪：按月为当月月薪 ÷ 当月应出勤日数，保留完整精度 (PRD 4.2.4)；按天就是填的日薪。
    public let dailyWage: Decimal
    /// 当月工资按月还是按天：按天时面板小字不说「满勤」。
    public let payBasis: PayBasis
    /// 应出勤日的收入数字；不应出勤的休息日为 nil。全天请假也有 (按休息日呈现，但收入为今日上限)。
    public let earnings: Earnings?
    /// 本月累计 = 本月今天之前各应出勤日的结算之和 + 今日已赚 (PRD 4.3.4)。
    /// 安装日之前已过的应出勤日没有日记录，天然按满勤结算 (PRD 4.1.1)。
    public let monthToDate: Decimal
    /// 本月今天之前已过的应出勤日数。
    public let attendedDays: Int
    /// 明天起第一个应出勤日。
    public let nextAttendanceDay: LocalDate?
    /// 距离周末：到下一个休息日还有几天；一年内都没有休息日时为 nil。
    let restCountdown: RestCountdown?
    /// 当日计划；休息日 (含全天请假) 为 nil。面板据此推导进度与倒计时。
    let plan: DayPlan?
    /// 今天的结算推导 (当日扣款明细、今日上限)；不应出勤的休息日为 nil。
    let settlement: DaySettlement?
    /// 今天的请假 (PRD 4.4.2)；没请假或今天不是应出勤日时为 nil。
    public let leave: Leave?
    /// 今天的白干时长、已倒贴与计时状态 (PRD 4.4.3)；计时中的那段可能是前一天开始、跨过零点的。
    public let unpaidWork: UnpaidWorkToday
    /// 今天生效的作息 (未经请假调整)：面板的时薪、请假表单的时间条据此推导。
    let schedule: WorkSchedule

    /// 时薪 = 日薪 ÷ 标准工时 (PRD 4.2.4)，不受请假影响。
    var hourlyWage: Decimal {
        schedule.owed(dailyWage: dailyWage, milliseconds: 3_600_000)
    }

    /// 今日已赚是否正在增长：只在上班中增长 (PRD 4.3.3 不变量 3)。外壳据此决定刷新频率。
    public var isEarning: Bool { status == .working }

    /// 面板主数字是否在滚动：上班中的今日已赚，或白干计时中的今日已倒贴。外壳据此决定刷新频率。
    public var isRolling: Bool { isEarning || unpaidWork.isRunning }
}

/// 应出勤日当天的收入相关数字 (PRD 4.3.4)。
public struct Earnings: Sendable, Equatable {
    /// 今日上限 = 日薪 - 当日扣款，最低为 0。
    public let cap: Decimal
    /// 工作进度：已过有效工时 ÷ 应有有效工时，0 至 1。
    public let progress: Decimal
    /// 今日已赚 = 今日上限 × 工作进度。
    public let earned: Decimal
    /// 上班中今日已赚每秒的增量 = 今日上限 ÷ 应有有效工时 (秒)。
    public let perSecond: Decimal
    /// 当日扣款 = 扣钱记录合计 + 请假扣薪 (PRD 4.3.1)。
    public let deductionTotal: Decimal
}

extension Today {
    init(profile: Profile, dayRecords: [DayRecord], now: Moment, holidays: HolidayTable) {
        let rule = AttendanceRule(holidays: holidays)
        let day = now.localDate
        let month = day.yearMonth
        // 单日覆盖可能让当月应出勤日数为 0：日薪记 0，本月累计为 0 (PRD 4.3.5 #19)。
        let wage = DaySettlement.dailyWage(profile: profile, month: month, rule: rule)
        let settle = { (date: LocalDate) in
            DaySettlement(dailyWage: wage, record: dayRecords.first { $0.date == date })
        }
        let pastDays = month.days.filter { $0 < day && rule.isAttendanceDay($0) }
        let settledSum = pastDays.map { settle($0).cap }.reduce(0, +)
        // 时薪按该日生效作息的标准工时，不受请假影响 (PRD 4.4.3 #4)。
        let clock = UnpaidWorkClock(profile: profile, rule: rule, dayRecords: dayRecords, now: now)
        let unpaidWorkToday = { (status: DayStatus) in
            UnpaidWorkToday(dayRecords: dayRecords, status: status, clock: clock)
        }
        date = day
        dailyWage = wage
        payBasis = profile.pay(for: month).basis
        schedule = profile.schedule(on: day)
        attendedDays = pastDays.count
        nextAttendanceDay = rule.nextAttendanceDay(after: day)
        restCountdown = rule.restCountdown(from: day)
        guard rule.isAttendanceDay(day) else {
            status = .restDay
            earnings = nil
            plan = nil
            settlement = nil
            leave = nil
            monthToDate = settledSum
            unpaidWork = unpaidWorkToday(.restDay)
            return
        }
        let todaySettlement = settle(day)
        let todayLeave = dayRecords.first { $0.date == day }?.leave
        let todayPlan = DayPlan(schedule: schedule, leave: todayLeave?.range, on: day, now: now)
        let todayEarnings = todayPlan.map { Earnings(settlement: todaySettlement, plan: $0, now: now.date) }
            ?? Earnings(fullDayLeave: todaySettlement)
        // 全天请假按休息日呈现【D2】。
        status = todayPlan?.status(at: now.date) ?? .restDay
        earnings = todayEarnings
        plan = todayPlan
        settlement = todaySettlement
        leave = todayLeave
        monthToDate = settledSum + todayEarnings.earned
        unpaidWork = unpaidWorkToday(status)
    }
}

extension Earnings {
    /// 今日上限取自当天的结算推导，已扣掉当日扣款。
    init(settlement: DaySettlement, plan: DayPlan, now: Date) {
        let cap = settlement.cap
        let total = Decimal(plan.effectiveMilliseconds)
        let elapsed = Decimal(plan.elapsedMilliseconds(at: now))
        self.cap = cap
        deductionTotal = settlement.deductionTotal
        guard total > 0 else {
            // 计划里没有有效工时 (理论上不会：请掉全部工时即全天请假)：到计划下班即拿满今日上限。
            progress = now >= plan.end ? 1 : 0
            earned = cap * progress
            perSecond = 0
            return
        }
        progress = elapsed / total
        // 先乘后除，减少中间舍入。
        earned = cap * elapsed / total
        perSecond = cap * 1000 / total
    }

    /// 全天请假：不滚动，今日已赚直接为今日上限 (PRD 4.3.2 #3)。
    init(fullDayLeave settlement: DaySettlement) {
        cap = settlement.cap
        progress = 1
        earned = settlement.cap
        perSecond = 0
        deductionTotal = settlement.deductionTotal
    }
}

extension MenuBarDisplay {
    /// 按显示模式 (PRD 4.7.1 第 2 条) 决定数字：金额模式为 4 位小数的今日已赚，进度模式为 2 位小数的工作进度，
    /// 仅图标模式不显示数字；休息日 (含全天请假，AC-HOME-07) 一律只显示小牛。
    /// 白干计时中 (含前一天开始、跨过零点还在计时) 小牛边拉磨边冒汗 (AC-BAR-09)，数字不变 (白干不改变收入)。
    init(today: Today, settings: InterfaceSettings) {
        let statusPose: CowPose = switch today.status {
        case .restDay: .sunbathing
        case .notStarted: .yawning
        case .working: .grinding
        case .lunchBreak: .sleeping
        case .onLeave: .sunbathing
        case .offWork: .lyingFlat
        }
        let pose = today.unpaidWork.isRunning ? .sweating : statusPose
        let text: String? = if today.status == .restDay {
            nil
        } else {
            switch settings.menuBarMode {
            case .amount: today.earnings.map { Format.rolling($0.earned) }
            case .progress: today.earnings.map { Format.percent($0.progress) }
            case .iconOnly: nil
            }
        }
        self.init(pose: pose, text: text)
    }
}
