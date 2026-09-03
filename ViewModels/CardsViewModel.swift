import CoreData
import Foundation

/// 信用卡账户的增删改
final class CardsViewModel: ObservableObject {
    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    @discardableResult
    func addCard(bank: String, nickname: String, lastFour: String?,
                 statementDay: Int, dueDay: Int,
                 creditLimit: Decimal?, colorHex: String) -> CreditCard {
        let card = CreditCard(context: context)
        card.id = UUID()
        card.bankName = bank
        card.nickname = nickname
        card.lastFour = lastFour
        card.statementDay = Int32(statementDay)
        card.dueDay = Int32(dueDay)
        card.creditLimit = creditLimit.map { NSDecimalNumber(decimal: $0) }
        card.colorHex = colorHex
        card.order = Int32((try? context.count(for: CreditCard.fetchRequest())) ?? 0)
        card.isArchived = false
        card.createdAt = Date()
        card.updatedAt = Date()
        save()
        return card
    }

    func update(_ card: CreditCard, bank: String, nickname: String, lastFour: String?,
                statementDay: Int, dueDay: Int, creditLimit: Decimal?, colorHex: String) {
        card.bankName = bank
        card.nickname = nickname
        card.lastFour = lastFour
        card.statementDay = Int32(statementDay)
        card.dueDay = Int32(dueDay)
        card.creditLimit = creditLimit.map { NSDecimalNumber(decimal: $0) }
        card.colorHex = colorHex
        card.updatedAt = Date()
        save()
    }

    func delete(_ card: CreditCard) {
        context.delete(card)
        save()
    }

    func setArchived(_ card: CreditCard, archived: Bool) {
        card.isArchived = archived
        card.updatedAt = Date()
        save()
    }

    private func save() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
