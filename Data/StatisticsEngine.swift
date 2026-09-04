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

/// 某年某月的账单总额（年度折线图与按月明细用）
struct MonthlyTotal: Identifiable {
    let year: Int
    let month: Int
    let total: Decimal

    var id: String { "\(year)-\(month)" }
    var label: String { "\(month) 月" }
    /// Charts 需要 Double
    var amount: Double { NSDecimalNumber(decimal: total).doubleValue }
}

/// 统计分析引擎（纯函数，输入 Statement 数组，输出聚合结果）
struct StatisticsEngine {
    /// 指定年份每月的账单总额。
    /// 当前年份只统计到当月 —— 否则未来月份补 0 会让折线尾部掉到底部，看着像"账单骤降"。
    static func monthlyTotals(_ statements: [Statement],
                              year: Int,
                              asOf: Date = Date()) -> [MonthlyTotal] {
        let calendar = Calendar.current
        let nowYear = calendar.component(.year, from: asOf)
        let nowMonth = calendar.component(.month, from: asOf)
        let maxMonth = (year == nowYear) ? nowMonth : 12

        let inYear = statements.filter { Int($0.year) == year }
        return (1...maxMonth).map { m in
            let sum = inYear
                .filter { Int($0.month) == m }
                .reduce(Decimal(0)) { $0 + $1.total }
            return MonthlyTotal(year: year, month: m, total: sum)
        }
    }

    /// 可选年份：有账单的年份 + 当前年份，降序
    static func availableYears(_ statements: [Statement], asOf: Date = Date()) -> [Int] {
        let current = Calendar.current.component(.year, from: asOf)
        let years = Set(statements.map { Int($0.year) }).union([current])
        return years.sorted(by: >)
    }

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
