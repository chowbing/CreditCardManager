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

    // MARK: - 账期查询

    /// 指定年月的账单（没有则返回 nil）
    public func statement(year: Int, month: Int) -> Statement? {
        statementsArray.first { Int($0.year) == year && Int($0.month) == month }
    }

    /// 指定年月下的「还款日」
    /// - 有账单：以账单上记录的还款日为准（用户可在账单里单独调整）
    /// - 无账单：按卡片的「还款日几号」推算，落在账期所在月（固定还款日模型，不跨月）
    public func dueDate(year: Int, month: Int) -> Date {
        if let d = statement(year: year, month: month)?.dueDate { return d }
        return DateCycleHelper.dueDate(year: year, month: month,
                                       dueDay: Int(dueDay))
    }
}


// MARK: - SwiftUI ForEach 需要的 Identifiable
extension CreditCard: Identifiable {}
