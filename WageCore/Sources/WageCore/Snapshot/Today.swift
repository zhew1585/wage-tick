import Foundation

/// 日状态 (GLOSSARY)：只由当前时刻、是否应出勤和当日计划推导。
public enum DayStatus: Sendable, Equatable {
    case restDay     // 休息日
    case notStarted  // 未上班
    case working     // 上班中
    case lunchBreak  // 午休中
    case offWork     // 已下班
}

/// 今天的推导结果。
public struct Today: Sendable, Equatable {
    public let date: LocalDate
    public let status: DayStatus
    /// 当月日薪 = 当月月薪 ÷ 当月应出勤日数，保留完整精度 (PRD 4.2.4)。
    public let dailyWage: Decimal
    /// 应出勤日的收入数字；休息日为 nil。
    public let earnings: Earnings?
    /// 本月累计 = 本月今天之前各应出勤日的结算之和 + 今日已赚 (PRD 4.3.4)。
    /// 安装日之前已过的应出勤日没有日记录，天然按满勤结算 (PRD 4.1.1)。
    public let monthToDate: Decimal
    /// 本月今天之前已过的应出勤日数。
    public let attendedDays: Int
    /// 明天起第一个应出勤日。
    public let nextAttendanceDay: LocalDate?
    /// 当日计划；休息日为 nil。面板据此推导进度与倒计时。
    let plan: DayPlan?
    /// 今天的结算推导 (当日扣款明细、今日上限)；休息日为 nil。
    let settlement: DaySettlement?

    /// 今日已赚是否正在增长：只在上班中增长 (PRD 4.3.3 不变量 3)。外壳据此决定刷新频率。
    public var isEarning: Bool { status == .working }
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
    /// 当日扣款 = 扣钱记录合计 (PRD 4.3.1)。
    public let deduction: Decimal
}

extension Today {
    init(profile: Profile, dayRecords: [DayRecord], now: Moment) {
        let day = now.localDate
        let month = day.yearMonth
        // 当月至少有 20 个应出勤日 (只按双休时)，除数不会为 0；单日覆盖引入后见 PRD 4.3.5 #19。
        let wage = profile.salary(for: month) / Decimal(AttendanceRule.attendanceDayCount(in: month))
        let settle = { (date: LocalDate) in
            DaySettlement(dailyWage: wage, record: dayRecords.first { $0.date == date })
        }
        let pastDays = month.days.filter { $0 < day && AttendanceRule.isAttendanceDay($0) }
        let settledSum = pastDays.map { settle($0).cap }.reduce(0, +)
        date = day
        dailyWage = wage
        attendedDays = pastDays.count
        nextAttendanceDay = AttendanceRule.nextAttendanceDay(after: day)
        guard AttendanceRule.isAttendanceDay(day) else {
            status = .restDay
            earnings = nil
            plan = nil
            settlement = nil
            monthToDate = settledSum
            return
        }
        let todaySettlement = settle(day)
        let todayPlan = DayPlan(schedule: profile.schedule, on: day, now: now)
        let todayEarnings = Earnings(settlement: todaySettlement, plan: todayPlan, now: now.date)
        status = todayPlan.status(at: now.date)
        earnings = todayEarnings
        plan = todayPlan
        settlement = todaySettlement
        monthToDate = settledSum + todayEarnings.earned
    }
}

extension Earnings {
    /// 今日上限取自当天的结算推导，已扣掉当日扣款。
    init(settlement: DaySettlement, plan: DayPlan, now: Date) {
        let cap = settlement.cap
        let total = Decimal(plan.effectiveMilliseconds)
        let elapsed = Decimal(plan.elapsedMilliseconds(at: now))
        self.cap = cap
        progress = elapsed / total
        // 先乘后除，减少中间舍入。
        earned = cap * elapsed / total
        perSecond = cap * 1000 / total
        deduction = settlement.deductionTotal
    }
}

extension MenuBarDisplay {
    /// 金额模式 (PRD 4.7.1 第 2 条)：休息日只显示小牛，其余显示 4 位小数的今日已赚。
    /// 老板路过模式下 (第 3 条) 只隐藏数字，小牛姿势照常随日状态变化。
    init(today: Today, settings: InterfaceSettings) {
        let pose: CowPose = switch today.status {
        case .restDay: .sunbathing
        case .notStarted: .yawning
        case .working: .grinding
        case .lunchBreak: .sleeping
        case .offWork: .lyingFlat
        }
        let text = settings.bossMode ? nil : today.earnings.map { Format.rolling($0.earned) }
        self.init(pose: pose, text: text)
    }
}
