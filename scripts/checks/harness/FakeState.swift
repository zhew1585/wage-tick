// 交互回归用的假状态：和 WageCore 的源码一起编成一个小程序 (见 ui-checks-mac.sh)，把 state.json 写到给定路径。
// 只用核心的公开命令造状态，状态文件的格式变了也跟着变，不手写 JSON。
// 内容：上个月 1 号 09:00 完成引导 (月薪 20000，10:00–18:00，饭点 12:00–13:00，双休)，关掉桌面悬浮小牛与两种通知；
// 一个累计中目标、四个排队目标 (金额远大于两个月的工资，检查期间攒不满，不会弹庆祝动画挡住概览)；
// 今天设成上班日，周末、节假日跑也有「今天扣钱了」与进度区，概览的布局每天一样。
import Foundation

let output = CommandLine.arguments.dropFirst().first ?? "state.json"
let zone = TimeZone.current
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = zone
let nowDate = Date()
let today = calendar.dateComponents([.year, .month, .day], from: nowDate)
let lastMonth = calendar.date(byAdding: .month, value: -1, to: nowDate)!
var start = calendar.dateComponents([.year, .month], from: lastMonth)
start.day = 1
start.hour = 9
let onboardedAt = Moment(date: calendar.date(from: start)!, timeZone: zone)
let now = Moment(date: nowDate, timeZone: zone)

let schedule = WorkSchedule(
    start: TimeOfDay(hour: 10, minute: 0),
    end: TimeOfDay(hour: 18, minute: 0),
    lunch: LunchBreak(start: TimeOfDay(hour: 12, minute: 0), end: TimeOfDay(hour: 13, minute: 0))
)

var state = AppState()
@MainActor func send(_ command: Command, at moment: Moment) {
    do {
        state = try apply(command, to: state, at: moment).state
    } catch {
        FileHandle.standardError.write("造假状态失败：\(command) \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

send(.completeOnboarding(OnboardingInput(salary: 20000, schedule: schedule, restMode: .twoDaysOff, launchAtLogin: false)), at: onboardedAt)
send(.setShowsFloatingCow(false), at: onboardedAt)
send(.setOffWorkNotification(false), at: onboardedAt)
send(.setGoalReachedNotification(false), at: onboardedAt)
for (name, amount) in [("换台 MacBook", 200_000), ("去趟大理", 80_000), ("人体工学椅", 90_000), ("Switch 2", 100_000), ("跑路基金", 300_000)] {
    send(.createGoal(name: name, amount: Decimal(amount)), at: onboardedAt)
}
send(.advance, at: now)
send(.editDay(LocalDate(year: today.year!, month: today.month!, day: today.day!), .setOverride(.attendanceDay)), at: now)

// 与 App 的 StateStore 一样包一层版本号 (StateFile，当前版本 1)。
struct StateFile: Encodable {
    let version: Int
    let state: AppState
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let url = URL(fileURLWithPath: output)
try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
try encoder.encode(StateFile(version: 1, state: state)).write(to: url, options: .atomic)
print(url.path)
