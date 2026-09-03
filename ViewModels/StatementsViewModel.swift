import CoreData
import Foundation

/// 每月账单的增删改
final class StatementsViewModel: ObservableObject {
    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    @discardableResult
    func addStatement(card: CreditCard, year: Int, month: Int,
                      statementDate: Date, dueDate: Date,
                      total: Decimal, paid: Decimal,
                      note: String?, reminderOn: Bool) -> Statement {
        let s = Statement(context: context)
        s.id = UUID()
        s.card = card
        s.year = Int32(year)
        s.month = Int32(month)
        s.statementDate = statementDate
        s.dueDate = dueDate
        s.totalAmount = NSDecimalNumber(decimal: total)
        s.paidAmount = NSDecimalNumber(decimal: paid)
        s.note = note
        s.reminderOn = reminderOn
        s.refreshStatus()
        s.createdAt = Date()
        s.updatedAt = Date()
        save()
        NotificationService.shared.rescheduleAll()
        return s
    }

    func update(_ s: Statement, statementDate: Date, dueDate: Date,
                total: Decimal, paid: Decimal, note: String?, reminderOn: Bool) {
        s.statementDate = statementDate
        s.dueDate = dueDate
        s.totalAmount = NSDecimalNumber(decimal: total)
        s.paidAmount = NSDecimalNumber(decimal: paid)
        s.note = note
        s.reminderOn = reminderOn
        s.refreshStatus()
        s.updatedAt = Date()
        save()
        NotificationService.shared.rescheduleAll()
    }

    func delete(_ s: Statement) {
        context.delete(s)
        save()
        NotificationService.shared.rescheduleAll()
    }

    /// 标记一笔还款（在原有已还基础上累加）
    func addPayment(_ s: Statement, amount: Decimal) {
        let newPaid = min(s.paid + amount, s.total)
        s.paidAmount = NSDecimalNumber(decimal: newPaid)
        s.refreshStatus()
        s.updatedAt = Date()
        save()
        NotificationService.shared.rescheduleAll()
    }

    private func save() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
