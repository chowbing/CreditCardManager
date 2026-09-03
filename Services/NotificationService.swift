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
