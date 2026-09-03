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
            .navigationTitle("概览")
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
/// 按卡展示本月所有账单：勾选切换还款状态，未还显示距还款日剩余天数，底部汇总本月账单总金额。
struct RepaymentOverviewView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest private var statements: FetchedResults<Statement>

    init() {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        let predicate = NSPredicate(format: "year == %d AND month == %d",
                                     comps.year ?? 0, comps.month ?? 0)
        _statements = FetchRequest<Statement>(
            sortDescriptors: [NSSortDescriptor(key: "dueDate", ascending: true)],
            predicate: predicate
        )
    }

    private var monthTitle: String {
        let comps = Calendar.current.dateComponents([.month], from: Date())
        return "信用卡账单 \(comps.month ?? 0)月"
    }

    private var totalAmount: Decimal {
        statements.reduce(Decimal(0)) { $0 + $1.total }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(monthTitle)
                .font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            if statements.isEmpty {
                Text("本月暂无账单")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(statements.enumerated()), id: \.element.objectID) { idx, s in
                        RepaymentRow(statement: s, onToggle: { togglePaid(s) })
                        if idx < statements.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack {
                    Text("合计").font(.subheadline.bold())
                    Spacer()
                    Text(totalAmount.yuanString)
                        .font(.title3.bold())
                }
                .padding(.horizontal, 4)
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
    let statement: Statement
    let onToggle: () -> Void

    private var isPaid: Bool { statement.paid >= statement.total }

    private var daysLeft: Int {
        guard let due = statement.dueDate else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.startOfDay(for: due)
        return Calendar.current.dateComponents([.day], from: start, to: target).day ?? 0
    }

    private var dueDayText: String {
        if let due = statement.dueDate {
            return "\(Calendar.current.component(.day, from: due)) 日"
        }
        return "\(statement.card?.dueDay ?? 0) 日"
    }

    private var dueDateShort: String {
        guard let due = statement.dueDate else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: due)
    }

    private var daysLeftText: String {
        if isPaid { return "已还清" }
        let d = daysLeft
        if d < 0 { return "逾期 \(abs(d)) 天" }
        if d == 0 { return "今天到期" }
        return "剩 \(d) 天"
    }

    private var daysLeftColor: Color {
        if isPaid { return .green }
        let d = daysLeft
        if d < 0 { return .red }
        if d <= 3 { return .orange }
        return .secondary
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // 状态勾 / 圆
                Image(systemName: isPaid ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isPaid ? Color.yellow : Color.secondary)

                // 卡名 + 尾号
                VStack(alignment: .leading, spacing: 2) {
                    Text(statement.card?.displayName ?? "未命名")
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    if let last = statement.card?.lastFour, !last.isEmpty {
                        Text(last)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 60, alignment: .leading)

                Spacer(minLength: 8)

                // 还款日 + 剩余天数
                VStack(spacing: 2) {
                    Text(dueDayText).font(.subheadline)
                    Text(daysLeftText)
                        .font(.caption)
                        .foregroundStyle(daysLeftColor)
                }
                .frame(width: 70)

                // 账单金额
                Text(statement.total.yuanString)
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
