import Foundation

/// 账期 / 还款日计算工具
enum DateCycleHelper {
    private static let calendar = Calendar.current

    /// 当天 00:00
    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// 账单所属年月的「账单日」对应的 Date（账单日超过当月天数则取月末）
    static func statementDate(year: Int, month: Int, statementDay: Int) -> Date {
        let base = calendar.date(from: DateComponents(year: year, month: month)) ?? Date()
        let range = calendar.range(of: .day, in: .month, for: base) ?? 1...28
        let day = min(max(statementDay, 1), range.upperBound)
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    /// 「还款日」对应的 Date。
    /// 规则：若还款日 <= 账单日，则视为次月还款日；否则为同月。
    static func dueDate(year: Int, month: Int, statementDay: Int, dueDay: Int) -> Date {
        let base = statementDate(year: year, month: month, statementDay: statementDay)
        let dueMonthOffset = (dueDay <= statementDay) ? 1 : 0
        var comps = calendar.dateComponents([.year, .month], from: base)
        comps.month = (comps.month ?? month) + dueMonthOffset
        let monthDate = calendar.date(from: DateComponents(year: comps.year, month: comps.month)) ?? base
        let range = calendar.range(of: .day, in: .month, for: monthDate) ?? 1...31
        let day = min(max(dueDay, 1), range.upperBound)
        return calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: day)) ?? base
    }

    /// 是否逾期（已过期且未全额还清）
    static func isOverdue(statement: Statement, asOf: Date = Date()) -> Bool {
        guard let due = statement.dueDate else { return false }
        return due < startOfDay(asOf) && statement.paid < statement.total
    }

    static func isSameMonth(_ date: Date?, as other: Date) -> Bool {
        guard let date else { return false }
        return calendar.isDate(date, equalTo: other, toGranularity: .month)
    }

    static func isWithinDays(_ date: Date?, days: Int, from base: Date = Date()) -> Bool {
        guard let date else { return false }
        guard let target = calendar.date(byAdding: .day, value: days, to: startOfDay(base)) else { return false }
        return date >= startOfDay(base) && date <= target
    }
}

extension Date {
    var monthDayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f.string(from: self)
    }

    var shortLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy/M/d"
        return f.string(from: self)
    }
}
