import Foundation
import UserNotifications
import CoreData

/// 本地通知：临近还款提醒 + 每日逾期汇总
final class NotificationService {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()

    /// 首次启动请求授权
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// 重新排程所有提醒（在 App 进入前台 / 数据变更后调用）
    func rescheduleAll() {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<Statement> = Statement.fetchRequest()
        guard let statements = try? context.fetch(request) else { return }

        center.removeAllPendingNotificationRequests()

        let lead = UserDefaults.standard.integer(forKey: "reminderLeadDays")
        let leadDays = lead > 0 ? lead : ReminderLeadTime.default
        let now = Date()

        for s in statements where s.reminderOn && s.effectiveStatus != .paid {
            guard let due = s.dueDate else { continue }
            let reminderDate = Calendar.current.date(byAdding: .day, value: -leadDays, to: due) ?? due
            if reminderDate > now {
                let body = "\(s.card?.displayName ?? "信用卡") 账单将于 \(due.monthDayLabel) 到期，待还 \(s.remaining.yuanString)"
                schedule(title: "还款提醒", body: body, at: reminderDate,
                         id: "due-\(s.id?.uuidString ?? UUID().uuidString)")
            }
        }

        // 每日 08:00 逾期汇总（仅当当前存在逾期账单）
        if statements.contains(where: { $0.effectiveStatus == .overdue }) {
            scheduleDailyOverdueSummary()
        }

        // rescheduleAll 会清空所有待发通知，这里补回尚未触发的「账期切换」提醒
        CycleManager.shared.rescheduleRolloverNoticeIfNeeded()
    }

    // MARK: - 账期自动切换

    /// 预约一条「账期将切换到 X 年 X 月」的提醒
    func scheduleRolloverNotice(year: Int, month: Int, seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "账期已切换到 \(month) 月"
        content.body = "上月账单已结清并存档。现在可以点卡片录入 \(year) 年 \(month) 月的新一期账单金额了。"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
        center.add(UNNotificationRequest(identifier: "cycle-rollover",
                                         content: content,
                                         trigger: trigger))
    }

    /// 切换已经发生，立刻发一条告知
    func notifyCycleSwitched(year: Int, month: Int) {
        scheduleRolloverNotice(year: year, month: month, seconds: 1)
    }

    private func schedule(title: String, body: String, at date: Date, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func scheduleDailyOverdueSummary() {
        let content = UNMutableNotificationContent()
        content.title = "逾期账单提醒"
        content.body = "您有账单已逾期，请尽快处理以免产生利息与影响征信。"
        content.sound = .default
        var comps = DateComponents()
        comps.hour = 8
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: "daily-overdue", content: content, trigger: trigger))
    }
}
