import CoreData
import SwiftUI

@objc(CreditCard)
public class CreditCard: NSManagedObject {}

extension CreditCard {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CreditCard> {
        return NSFetchRequest<CreditCard>(entityName: "CreditCard")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var bankName: String?
    @NSManaged public var nickname: String?
    @NSManaged public var lastFour: String?
    @NSManaged public var statementDay: Int32
    @NSManaged public var dueDay: Int32
    @NSManaged public var creditLimit: NSDecimalNumber?
    @NSManaged public var colorHex: String?
    @NSManaged public var order: Int32
    @NSManaged public var isArchived: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var statements: NSSet?

    // MARK: - 便捷访问
    public var statementsArray: [Statement] {
        let set = statements as? Set<Statement> ?? []
        return set.sorted { ($0.year, $0.month) > ($1.year, $1.month) }
    }

    public var displayName: String {
        if let nickname, !nickname.isEmpty { return nickname }
        return bankName ?? "未命名卡片"
    }

    public var themeColor: Color {
        Color(hex: colorHex ?? CardPalette.colors[0])
    }

    public var creditLimitDecimal: Decimal {
        creditLimit?.decimalValue ?? 0
    }
}


// MARK: - SwiftUI ForEach 需要的 Identifiable
extension CreditCard: Identifiable {}
