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
    public let work: WorkdayFigures?
}

/// 应出勤日当天的收入相关数字 (PRD 4.3.4)。
public struct WorkdayFigures: Sendable, Equatable {
    /// 今日上限 = 日薪 - 当日扣款，最低为 0。
    public let cap: Decimal
    /// 工作进度：已过有效工时 ÷ 应有有效工时，0 至 1。
    public let progress: Decimal
    /// 今日已赚 = 今日上限 × 工作进度。
    public let earned: Decimal
    /// 上班中今日已赚每秒的增量 = 今日上限 ÷ 应有有效工时 (秒)。
    public let perSecond: Decimal
}

extension Today {
    init(profile: Profile, now: Moment) {
        let day = now.localDate
        let month = day.yearMonth
        // 当月至少有 20 个工作日 (只按双休时)，除数不会为 0；单日覆盖引入后见 PRD 4.3.5 #19。
        let wage = profile.salary(for: month) / Decimal(WorkdayRule.workdayCount(in: month))
        date = day
        dailyWage = wage
        guard WorkdayRule.isWorkday(day) else {
            status = .restDay
            work = nil
            return
        }
        let plan = DayPlan(schedule: profile.schedule, on: day, now: now)
        status = plan.status(at: now.date)
        work = WorkdayFigures(cap: wage, plan: plan, now: now.date)
    }
}

extension WorkdayFigures {
    /// 本期没有扣款，今日上限 = 日薪。
    init(cap: Decimal, plan: DayPlan, now: Date) {
        let total = Decimal(plan.effectiveMilliseconds)
        let elapsed = Decimal(plan.elapsedMilliseconds(at: now))
        self.cap = cap
        progress = elapsed / total
        // 先乘后除，减少中间舍入。
        earned = cap * elapsed / total
        perSecond = cap * 1000 / total
    }
}

extension MenuBarDisplay {
    /// 金额模式 (PRD 4.7.1 第 2 条)：休息日只显示小牛，其余显示 4 位小数的今日已赚。
    init(today: Today) {
        let pose: CowPose = switch today.status {
        case .restDay: .sunbathing
        case .notStarted: .yawning
        case .working: .grinding
        case .lunchBreak: .sleeping
        case .offWork: .lyingFlat
        }
        self.init(pose: pose, text: today.work.map { Format.rolling($0.earned) })
    }
}
