import Foundation
import SwiftUI

/// 当前展示的「账期」。
///
/// - 默认与真实自然月一致（9 月就是 9 月）。
/// - 当某月所有账单都还清后，App 会自动存档该月，并安排在 N 分钟后把账期
///   整体切换到下一月（还款日的「日号」保持不变，只把月份 +1），
///   这样就能提前录入下一期账单，而不用等到下个月 1 号。
/// - 用户也可以用标题上的箭头手动前后翻看任意账期。
final class CycleManager: ObservableObject {

    static let shared = CycleManager()

    private enum Key {
        static let year = "cm.cycle.year"
        static let month = "cm.cycle.month"
        static let rolloverAt = "cm.cycle.rolloverAt"
    }

    @Published private(set) var year: Int
    @Published private(set) var month: Int
    /// 计划自动切换到下一账期的时间点（nil = 没有待执行的切换）
    @Published private(set) var rolloverAt: Date?

    private let ud = UserDefaults.standard

    private init() {
        let now = Self.naturalCycle
        let savedYear = ud.object(forKey: Key.year) as? Int
        let savedMonth = ud.object(forKey: Key.month) as? Int

        if let y = savedYear, let m = savedMonth,
           Self.encode(year: y, month: m) >= Self.encode(year: now.year, month: now.month) {
            year = y
            month = m
        } else {
            // 首次启动，或已存账期落后于自然月（长期没打开 App）→ 追平自然月
            year = now.year
            month = now.month
        }
        rolloverAt = ud.object(forKey: Key.rolloverAt) as? Date
        persist()
    }

    // MARK: - 索引工具：把年月压成一个可比较的整数

    static func encode(year: Int, month: Int) -> Int { year * 12 + (month - 1) }
    static func decode(_ index: Int) -> (year: Int, month: Int) { (index / 12, index % 12 + 1) }

    var index: Int { Self.encode(year: year, month: month) }

    /// 真实今天所在的年月
    static var naturalCycle: (year: Int, month: Int) {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        return (c.year ?? 1970, c.month ?? 1)
    }

    /// 当前展示的账期是否就是自然月
    var isOnNaturalMonth: Bool {
        let n = Self.naturalCycle
        return index == Self.encode(year: n.year, month: n.month)
    }

    /// 账期锚点（该月 1 号），用于判断某个日期是否落在这个账期里
    var anchorDate: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month)) ?? Date()
    }

    // MARK: - 手动切换

    func goToPreviousMonth() { shift(-1) }
    func goToNextMonth() { shift(1) }

    func goToNaturalMonth() {
        let n = Self.naturalCycle
        set(year: n.year, month: n.month)
    }

    private func shift(_ delta: Int) {
        let target = Self.decode(index + delta)
        set(year: target.year, month: target.month)
    }

    private func set(year y: Int, month m: Int) {
        year = y
        month = m
        // 用户手动接管了账期，取消待执行的自动切换，避免下次打开时又跳一次
        cancelAutoRollover()
        persist()
    }

    private func persist() {
        ud.set(year, forKey: Key.year)
        ud.set(month, forKey: Key.month)
    }

    // MARK: - 自动切换到下一月

    /// 安排在 minutes 分钟后自动切换到下一月
    func scheduleAutoRollover(minutes: Int) {
        rolloverAt = Date().addingTimeInterval(Double(max(minutes, 1)) * 60)
        ud.set(rolloverAt, forKey: Key.rolloverAt)
    }

    func cancelAutoRollover() {
        rolloverAt = nil
        ud.removeObject(forKey: Key.rolloverAt)
    }

    /// 距自动切换还剩多少秒（没有待执行切换则为 nil）
    var pendingRolloverRemaining: TimeInterval? {
        guard let at = rolloverAt else { return nil }
        return max(at.timeIntervalSinceNow, 0)
    }

    /// 到点则切换到下一月。返回本次是否真的发生了切换。
    /// App 回到前台、以及倒计时计时器每跳一秒都会调用它。
    @discardableResult
    func performRolloverIfDue() -> Bool {
        guard let at = rolloverAt, Date() >= at else { return false }
        shift(1)
        let current = Self.decode(index)
        // 进位后重排提醒（会清掉旧的切换提醒，并按新账期补回到期提醒），
        // 最后再补一条「账期已切换」告知，避免被上面的 removeAllPending 误清。
        NotificationService.shared.rescheduleAll()
        NotificationService.shared.notifyCycleSwitched(year: current.year, month: current.month)
        return true
    }

    /// 通知被全量重排（rescheduleAll）后，补回尚未触发的切换提醒
    func rescheduleRolloverNoticeIfNeeded() {
        guard let at = rolloverAt else { return }
        let remaining = at.timeIntervalSinceNow
        guard remaining > 1 else { return }
        let next = Self.decode(index + 1)
        NotificationService.shared.scheduleRolloverNotice(year: next.year,
                                                          month: next.month,
                                                          seconds: remaining)
    }
}
