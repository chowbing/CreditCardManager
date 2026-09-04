import SwiftUI
import CoreData
import UIKit

struct OverviewView: View {
    @Environment(\.managedObjectContext) private var context
    /// 当前展示的账期（可能在全部还清后自动前移到下一月）
    @ObservedObject private var cycle = CycleManager.shared
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "dueDate", ascending: true)]
    )
    private var statements: FetchedResults<Statement>

    private var all: [Statement] { Array(statements) }

    private var thisMonthDue: [Statement] {
        all.filter { $0.effectiveStatus != .paid && DateCycleHelper.isSameMonth($0.dueDate, as: cycle.anchorDate) }
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

    // 注意：不再自带 NavigationStack —— 由 MainTabView 统一提供，
    // 这样再次点击底部「概览」Tab 才能把导航栈弹回本页。
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                    // 顶部汇总（左右两栏）：左=信用卡账单 X月 / 月总账单金额，右=本月待还
                    RepaymentOverviewView(monthRemaining: monthRemaining)

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
/// 还款日优先取账单记录、无账单时按卡片的账单日/还款日推算（可能落在次月，会标「次月」）。
/// 排序固定按「还款日」日号升序，即每月从月初的还款日开始。
/// 顶部汇总：左=月总账单金额，右=本月待还。点整行进入该卡账单，点左侧方框切换已还。
struct RepaymentOverviewView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "order", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ]
    )
    private var cards: FetchedResults<CreditCard>

    /// 当前展示的账期（全部还清后会自动前移到下一月）
    @ObservedObject private var cycle = CycleManager.shared

    /// 本月待还（由首页传入，口径与原来顶部红色大字一致：当月到期且未还清的剩余之和）
    let monthRemaining: Decimal

    /// 结算弹窗
    @State private var settlementResult: SettlementResult?
    @State private var showSettlementAlert = false

    private var yearMonth: (year: Int, month: Int) { (cycle.year, cycle.month) }

    /// 当前月 1 号（用于判断还款日是否落在次月）
    private var monthAnchor: Date { cycle.anchorDate }

    /// 取卡片当前年月的账单（可能没有）
    private func statement(for card: CreditCard) -> Statement? {
        card.statement(year: yearMonth.year, month: yearMonth.month)
    }

    /// 按「还款日」升序排列：每月从月初的还款日开始，同日则按卡名兜底，保证顺序稳定
    private var sortedCards: [CreditCard] {
        cards.sorted { lhs, rhs in
            let l = Calendar.current.component(.day, from: lhs.dueDate(year: yearMonth.year, month: yearMonth.month))
            let r = Calendar.current.component(.day, from: rhs.dueDate(year: yearMonth.year, month: yearMonth.month))
            return l == r ? lhs.displayName < rhs.displayName : l < r
        }
    }

    private var monthTitle: String {
        let n = CycleManager.naturalCycle
        // 跨年时把年份带上，避免只看月份产生歧义
        if yearMonth.year != n.year {
            return "信用卡账单 \(yearMonth.year)年\(yearMonth.month)月"
        }
        return "信用卡账单 \(yearMonth.month)月"
    }

    /// 月总账单金额：所有卡片本月账单金额之和（无账单计 0）
    private var monthTotal: Decimal {
        cards.reduce(Decimal(0)) { $0 + (statement(for: $1)?.total ?? 0) }
    }

    // MARK: - 月度结算（全部还清 → 自动存档）

    /// 本期填了金额的账单（金额 0 / 没填的卡不算，不阻塞结算）
    private var filledStatements: [Statement] {
        sortedCards.compactMap { card in
            guard let s = card.statement(year: cycle.year, month: cycle.month), s.total > 0 else {
                return nil
            }
            return s
        }
    }

    /// 本期所有填了金额的账单是否都已还清
    private var allCleared: Bool {
        guard !filledStatements.isEmpty else { return false }
        return filledStatements.allSatisfy { $0.paid >= $0.total }
    }

    /// 尝试结算。内部有多重防重，重复调用是安全的。
    @MainActor
    private func trySettle() {
        guard allCleared else { return }
        let result = MonthlySettlement.run(cards: sortedCards,
                                           year: cycle.year,
                                           month: cycle.month)
        guard let result else { return }
        settlementResult = result
        showSettlementAlert = true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 账期自动切换倒计时（全部还清、安排了切换后才出现）
            if cycle.rolloverAt != nil {
                RolloverBanner(cycle: cycle)
            }

            // 顶部汇总：标题与月总账单金额在左，本月待还在右
            SummaryHeaderView(monthTitle: monthTitle,
                              monthTotal: monthTotal,
                              monthRemaining: monthRemaining,
                              isOnNaturalMonth: cycle.isOnNaturalMonth,
                              onPrevious: { cycle.goToPreviousMonth() },
                              onNext: { cycle.goToNextMonth() },
                              onReset: { cycle.goToNaturalMonth() })

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
                    ForEach(Array(sortedCards.enumerated()), id: \.element.objectID) { idx, card in
                        let stmt = statement(for: card)
                        let due = card.dueDate(year: yearMonth.year, month: yearMonth.month)
                        RepaymentRow(
                            card: card,
                            statement: stmt,
                            dueDate: due,
                            isNextMonth: !DateCycleHelper.isSameMonth(due, as: monthAnchor),
                            onToggle: {
                                if let s = stmt { togglePaid(s) }
                            }
                        )
                        if idx < sortedCards.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        // 勾完最后一笔、本期全部还清时触发结算
        .onChange(of: allCleared) { cleared in
            if cleared { trySettle() }
        }
        // 进页面时也查一次：覆盖「通过账单编辑页把金额改成已还清」的情况
        .task { trySettle() }
        .alert("本月账单已结清", isPresented: $showSettlementAlert, presenting: settlementResult) { result in
            Button("好") {}
            Button("立即切到 \(result.nextMonth) 月") {
                CycleManager.shared.goToNextMonth()
            }
        } message: { result in
            Text(settlementMessage(result))
        }
    }

    private func settlementMessage(_ r: SettlementResult) -> String {
        var text = "\(r.archive.title)账单已存档：共 \(r.archive.rowCount) 张卡，合计 \(r.archive.total)。\n"
        text += r.imageSaved
            ? "账单截图已保存到相册。\n"
            : "截图保存失败，请检查相册权限。\n"
        text += "账期将在 5 分钟后自动切换到 \(r.nextYear) 年 \(r.nextMonth) 月，还款日的日期不变、仅月份 +1。之后点卡片即可录入下一期金额。"
        return text
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

// MARK: - 顶部汇总：左「信用卡账单 X月 / 月总账单金额」，右「本月待还」
private struct SummaryHeaderView: View {
    let monthTitle: String
    let monthTotal: Decimal
    let monthRemaining: Decimal
    let isOnNaturalMonth: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                // 标题两侧加了前后翻月的箭头，方便回看历史账期 / 提前进入下一期
                HStack(spacing: 6) {
                    Button(action: onPrevious) {
                        Image(systemName: "chevron.left")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Text(monthTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(action: onNext) {
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    if !isOnNaturalMonth {
                        Button("回本月", action: onReset)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                Text(monthTotal.yuanString)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: 40)
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("本月待还")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(monthRemaining.yuanString)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(monthRemaining > 0 ? .red : .green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct RepaymentRow: View {
    let card: CreditCard
    let statement: Statement?
    /// 该卡本月的还款日（有账单用账单的，无账单按卡设置推算，可能是次月）
    let dueDate: Date
    /// 还款日是否落在次月（如 9 月账单实际 10/23 到期）
    let isNextMonth: Bool
    let onToggle: () -> Void

    private var hasStatement: Bool { statement != nil }

    private var isPaid: Bool {
        guard let s = statement else { return false }
        return s.paid >= s.total
    }

    /// 账单金额：无账单显示 ¥0.00
    private var amount: Decimal { statement?.total ?? 0 }

    private var daysLeft: Int {
        let start = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.startOfDay(for: dueDate)
        return Calendar.current.dateComponents([.day], from: start, to: target).day ?? 0
    }

    /// 中间列顶部：账单日（卡的 statementDay），避免与末尾还款日重复显示
    private var statementDayText: String {
        "\(card.statementDay) 日"
    }

    private var dueDateShort: String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: dueDate)
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
        HStack(spacing: 10) {
            // 左侧勾：切换还款状态（无账单时禁用）
            Button(action: onToggle) {
                Image(systemName: isPaid ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isPaid ? Color.yellow : Color.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!hasStatement)

            // 右侧整行点击进入该卡片的账单列表。
            // 与勾选按钮同级而非嵌套，避免二者争抢点击。
            NavigationLink {
                StatementsView(card: card)
            } label: {
                rowContent
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
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
            .frame(minWidth: 54, alignment: .leading)

            Spacer(minLength: 4)

            // 账单日 + 剩余天数
            VStack(spacing: 2) {
                Text(statementDayText).font(.subheadline)
                Text(daysLeftText)
                    .font(.caption)
                    .foregroundStyle(daysLeftColor)
            }
            .frame(width: 66)

            // 账单金额（无账单显示 ¥0.00）
            Text(amount.yuanString)
                .font(.subheadline.bold())
                .frame(width: 76, alignment: .trailing)

            // 还款日期（M/d）+ 次月标记
            VStack(spacing: 2) {
                Text(dueDateShort)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .underline()
                if isNextMonth {
                    Text("次月")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: 42, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(Color.secondary.opacity(0.6))
        }
        // NavigationLink 会把标签文字渲染成强调色，这里显式还原为主文本色
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
    }
}

// MARK: - 账期切换倒计时横幅
/// 全部还清并安排切换后才出现；每秒刷新倒计时，
/// 到点自动调用 CycleManager 进位（还款日日号不变、月份 +1），进位后外层 if 会让横幅自动消失。
private struct RolloverBanner: View {
    @ObservedObject var cycle: CycleManager
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var countdownText: String {
        guard let remain = cycle.pendingRolloverRemaining, remain > 0 else {
            return "即将切换…"
        }
        let total = Int(remain)
        let m = total / 60
        let s = total % 60
        return m > 0 ? "\(m) 分 \(s) 秒" : "\(s) 秒"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("本月账单已结清，账期切换倒计时")
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Text("将于 \(countdownText)后自动切换到下一月，还款日日期不变、仅月份 +1")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onReceive(timer) { _ in
            // 到点自动进位；进位后 rolloverAt 变 nil，外层 if 会让本横幅消失
            _ = cycle.performRolloverIfDue()
        }
    }
}
