import SwiftUI
import CoreData
import UIKit

struct OverviewView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "dueDate", ascending: true)]
    )
    private var statements: FetchedResults<Statement>

    private var all: [Statement] { Array(statements) }

    private var thisMonthDue: [Statement] {
        all.filter { $0.effectiveStatus != .paid && DateCycleHelper.isSameMonth($0.dueDate, as: Date()) }
    }
    private var overdue: [Statement] {
        all.filter { $0.effectiveStatus == .overdue }
    }
    private var upcoming: [Statement] {
        all.filter {
            $0.effectiveStatus != .paid && !($0.effectiveStatus == .overdue) &&
            DateCycleHelper.isWithinDays($0.dueDate, days: 7)
        }
    }

    private var monthRemaining: Decimal {
        thisMonthDue.reduce(Decimal(0)) { $0 + $1.remaining }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 本月待还
                    VStack(spacing: 6) {
                        Text("本月待还").font(.subheadline).foregroundStyle(.secondary)
                        Text(monthRemaining.yuanString)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(monthRemaining > 0 ? .red : .green)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // 信用卡还款概览（按卡展示本月账单 + 合计）
                    RepaymentOverviewView()

                    if !overdue.isEmpty {
                        SectionCard(title: "⚠️ 逾期账单", color: .red) {
                            ForEach(overdue) { s in
                                OverviewRow(statement: s)
                            }
                        }
                    }

                    if !upcoming.isEmpty {
                        SectionCard(title: "未来 7 天待还", color: .orange) {
                            ForEach(upcoming) { s in
                                OverviewRow(statement: s)
                            }
                        }
                    }

                    if overdue.isEmpty && upcoming.isEmpty {
                        Text("暂无临近或逾期的账单，状态良好 🎉")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
            .padding()
        }
    }
}
}

private struct SectionCard<Content: View>: View {
    let title: String
    let color: Color
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(color)
            VStack(spacing: 0) {
                content()
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct OverviewRow: View {
    let statement: Statement
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(statement.periodLabel).font(.subheadline.bold())
                Text(statement.card?.displayName ?? "")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(statement.remaining.yuanString)
                    .font(.subheadline)
                    .foregroundStyle(statement.effectiveStatus == .overdue ? .red : .primary)
                if let due = statement.dueDate {
                    Text(due.monthDayLabel).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}

// MARK: - 信用卡还款概览（首页新模块）
/// 列出全部关联卡片：有本月账单的展示金额/状态/剩余天数；无账单的显示 ¥0.00，
/// 还款日按卡片自身 dueDay 推算。顶部汇总所有卡本月账单总金额（无账单计 0）。
struct RepaymentOverviewView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "order", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ]
    )
    private var cards: FetchedResults<CreditCard>

    private var yearMonth: (year: Int, month: Int) {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        return (comps.year ?? 0, comps.month ?? 0)
    }

    /// 取卡片当前年月的账单（可能没有）
    private func statement(for card: CreditCard) -> Statement? {
        card.statementsArray.first {
            $0.year == yearMonth.year && $0.month == yearMonth.month
        }
    }

    private var monthTitle: String {
        "信用卡账单 \(yearMonth.month)月"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(monthTitle)
                .font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            if cards.isEmpty {
                Text("尚未添加任何卡片")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(cards.enumerated()), id: \.element.objectID) { idx, card in
                        let stmt = statement(for: card)
                        RepaymentRow(card: card, statement: stmt, onToggle: {
                            if let s = stmt { togglePaid(s) }
                        })
                        .disabled(stmt == nil)
                        if idx < cards.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    /// 切换单张账单的还款状态：未还 → 设为已还；已还 → 设为未还
    private func togglePaid(_ s: Statement) {
        let willPay = s.paid < s.total
        s.paidAmount = NSDecimalNumber(decimal: willPay ? s.total : Decimal(0))
        s.refreshStatus()
        s.updatedAt = Date()
        try? context.save()
        NotificationService.shared.rescheduleAll()
    }
}

private struct RepaymentRow: View {
    let card: CreditCard
    let statement: Statement?
    let onToggle: () -> Void

    private var hasStatement: Bool { statement != nil }

    private var isPaid: Bool {
        guard let s = statement else { return false }
        return s.paid >= s.total
    }

    /// 账单金额：无账单显示 ¥0.00
    private var amount: Decimal { statement?.total ?? 0 }

    /// 还款日：优先用账单的，否则按卡片 dueDay 推算
    private var dueDateValue: Date {
        if let d = statement?.dueDate { return d }
        let (y, m) = (Calendar.current.component(.year, from: Date()),
                      Calendar.current.component(.month, from: Date()))
        return DateCycleHelper.dueDate(year: y, month: m,
                                       statementDay: Int(card.statementDay),
                                       dueDay: Int(card.dueDay))
    }

    private var daysLeft: Int {
        let start = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.startOfDay(for: dueDateValue)
        return Calendar.current.dateComponents([.day], from: start, to: target).day ?? 0
    }

    /// 中间列顶部：账单日（卡的 statementDay），避免与末尾还款日重复显示
    private var statementDayText: String {
        "\(card.statementDay) 日"
    }

    private var dueDateShort: String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: dueDateValue)
    }

    private var daysLeftText: String {
        if !hasStatement { return "未填账单" }
        if isPaid { return "已还清" }
        let d = daysLeft
        if d < 0 { return "逾期 \(abs(d)) 天" }
        if d == 0 { return "今天到期" }
        return "剩 \(d) 天"
    }

    private var daysLeftColor: Color {
        if !hasStatement { return .secondary }
        if isPaid { return .green }
        let d = daysLeft
        if d < 0 { return .red }
        if d <= 3 { return .orange }
        return .secondary
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // 状态勾 / 方框
                Image(systemName: isPaid ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isPaid ? Color.yellow : Color.secondary)

                // 卡名 + 尾号
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.displayName)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    if let last = card.lastFour, !last.isEmpty {
                        Text(last)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 60, alignment: .leading)

                Spacer(minLength: 8)

                // 账单日 + 剩余天数
                VStack(spacing: 2) {
                    Text(statementDayText).font(.subheadline)
                    Text(daysLeftText)
                        .font(.caption)
                        .foregroundStyle(daysLeftColor)
                }
                .frame(width: 70)

                // 账单金额（无账单显示 ¥0.00）
                Text(amount.yuanString)
                    .font(.subheadline.bold())
                    .frame(width: 80, alignment: .trailing)

                // 还款日期（M/d）
                Text(dueDateShort)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .underline()
                    .frame(width: 48, alignment: .trailing)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
