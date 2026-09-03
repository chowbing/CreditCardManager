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
