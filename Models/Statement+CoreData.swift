import CoreData

@objc(Statement)
public class Statement: NSManagedObject {}

extension Statement {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Statement> {
        return NSFetchRequest<Statement>(entityName: "Statement")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var card: CreditCard?
    @NSManaged public var year: Int32
    @NSManaged public var month: Int32
    @NSManaged public var statementDate: Date?
    @NSManaged public var dueDate: Date?
    @NSManaged public var totalAmount: NSDecimalNumber?
    @NSManaged public var paidAmount: NSDecimalNumber?
    @NSManaged public var isPaidInFull: Bool
    @NSManaged public var statusRaw: Int32
    @NSManaged public var note: String?
    @NSManaged public var reminderOn: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?

    // MARK: - 金额便捷访问
    public var total: Decimal { totalAmount?.decimalValue ?? 0 }
    public var paid: Decimal { paidAmount?.decimalValue ?? 0 }
    public var remaining: Decimal { max(total - paid, Decimal(0)) }

    /// 实时状态（依据当前日期 + 已还金额推导）
    public var effectiveStatus: StatementStatus {
        if paid >= total { return .paid }
        guard let due = dueDate else { return .pending }
        if due < DateCycleHelper.startOfDay(Date()) { return .overdue }
        if paid > 0 { return .partial }
        return .pending
    }

    /// 持久化的状态（保存时刷新，便于图表/筛选）
    public var storedStatus: StatementStatus {
        StatementStatus(rawValue: Int(statusRaw)) ?? .pending
    }

    public var periodLabel: String {
        "\(year)年\(month)月"
    }

    public func refreshStatus() {
        isPaidInFull = paid >= total
        statusRaw = Int32(effectiveStatus.rawValue)
    }
}

// MARK: - SwiftUI ForEach 需要的 Identifiable
// NSManagedObject 在 iOS 16 SDK 不会自动 Identifiable，
// 这里基于 objectID 给一个稳定的 id（跨刷新不变），避免 ForEach 报 “doesn't conform to Identifiable”。
extension Statement: Identifiable {}
