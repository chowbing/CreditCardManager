import Foundation

/// 单条聚合点（用于图表与列表）
struct StatPoint: Identifiable {
    let id = UUID()
    let label: String
    let total: Decimal
    let paid: Decimal

    var remaining: Decimal { max(total - paid, Decimal(0)) }

    var completion: Double {
        guard total > 0 else { return 0 }
        return NSDecimalNumber(decimal: paid).doubleValue / NSDecimalNumber(decimal: total).doubleValue
    }
}

/// 统计分析引擎（纯函数，输入 Statement 数组，输出聚合结果）
struct StatisticsEngine {
    static func monthly(_ statements: [Statement]) -> [StatPoint] {
        group(statements) { "\($0.year)-\($0.month)" }
            .sorted { $0.label < $1.label }
    }

    static func yearly(_ statements: [Statement]) -> [StatPoint] {
        group(statements) { "\($0.year)" }
            .sorted { $0.label < $1.label }
    }

    static func byCard(_ statements: [Statement]) -> [StatPoint] {
        group(statements) { $0.card?.displayName ?? "未知卡片" }
            .sorted { $0.total > $1.total }
    }

    static func totals(_ statements: [Statement]) -> (total: Decimal,
                                                      paid: Decimal,
                                                      overdueCount: Int,
                                                      overdueAmount: Decimal) {
        let total = statements.reduce(Decimal(0)) { $0 + $1.total }
        let paid = statements.reduce(Decimal(0)) { $0 + $1.paid }
        let overdue = statements.filter { $0.effectiveStatus == .overdue }
        let overdueAmount = overdue.reduce(Decimal(0)) { $0 + $1.remaining }
        return (total, paid, overdue.count, overdueAmount)
    }

    // MARK: - 内部
    private static func group(_ statements: [Statement],
                              _ key: (Statement) -> String) -> [StatPoint] {
        let dict = Dictionary(grouping: statements, by: key)
        return dict.map { (label, stmts) in
            let total = stmts.reduce(Decimal(0)) { $0 + $1.total }
            let paid = stmts.reduce(Decimal(0)) { $0 + $1.paid }
            return StatPoint(label: label, total: total, paid: paid)
        }
    }
}
