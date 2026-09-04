import SwiftUI
import Charts
import CoreData
import UIKit

struct StatisticsView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "dueDate", ascending: true)]
    )
    private var statements: FetchedResults<Statement>

    @StateObject private var vm = StatisticsViewModel()

    private var all: [Statement] { Array(statements) }
    private var points: [StatPoint] { vm.points(for: all) }
    private var totals: (total: Decimal, paid: Decimal, overdueCount: Int, overdueAmount: Decimal) {
        StatisticsEngine.totals(all)
    }

    // 注意：NavigationStack 由 MainTabView 统一提供（点 Tab 可弹回根页）
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 合计卡片
                HStack(spacing: 12) {
                    SummaryTile(title: "累计账单", value: totals.total.yuanString, color: .blue)
                    SummaryTile(title: "已还", value: totals.paid.yuanString, color: .green)
                }
                HStack(spacing: 12) {
                    SummaryTile(title: "逾期笔数", value: "\(totals.overdueCount)", color: .red)
                    SummaryTile(title: "逾期金额", value: totals.overdueAmount.yuanString, color: .red)
                }

                // 年度「月度账单总额」：按年切换，折线看波动，下方按月可查
                MonthlyTrendCard(
                    years: StatisticsEngine.availableYears(all),
                    year: $vm.historyYear,
                    data: StatisticsEngine.monthlyTotals(all, year: vm.historyYear)
                )

                // 维度切换
                Picker("统计维度", selection: $vm.dimension) {
                    ForEach(StatisticsDimension.allCases) { d in
                        Text(d.title).tag(d)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if points.isEmpty {
                    Text("暂无数据可统计")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ChartCard(title: "\(vm.dimension.title)总支出") {
                        Chart(points) { p in
                            BarMark(
                                x: .value("维度", p.label),
                                y: .value("金额", NSDecimalNumber(decimal: p.total).doubleValue)
                            )
                            .foregroundStyle(.blue)
                        }
                        .frame(height: 220)
                    }

                    ChartCard(title: "还款完成情况（已还 / 未还）") {
                        Chart(points) { p in
                            BarMark(
                                x: .value("维度", p.label),
                                y: .value("已还", NSDecimalNumber(decimal: p.paid).doubleValue)
                            )
                            .foregroundStyle(by: .value("类型", "已还"))
                            BarMark(
                                x: .value("维度", p.label),
                                y: .value("未还", NSDecimalNumber(decimal: p.remaining).doubleValue)
                            )
                            .foregroundStyle(by: .value("类型", "未还"))
                        }
                        .frame(height: 220)
                        .chartLegend(position: .bottom)
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("统计分析")
    }
}

private struct SummaryTile: View {
    let title: String
    let value: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - 年度「月度账单总额」
/// 数据来源 = 已保存的账单按年月汇总，与首页「信用卡账单 X月」金额口径一致。
/// 每录入/修改一笔账单，这里自动更新；切换年份可查历史，折线展示全年波动。
private struct MonthlyTrendCard: View {
    let years: [Int]
    @Binding var year: Int
    let data: [MonthlyTotal]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var yearTotal: Decimal {
        data.reduce(Decimal(0)) { $0 + $1.total }
    }

    /// 年内峰值，用于给明细里最高的月份高亮
    private var peakMonth: Int? {
        data.filter { $0.total > 0 }.max { $0.total < $1.total }?.month
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("月度账单总额").font(.headline)
                Spacer()
                Picker("年份", selection: $year) {
                    ForEach(years, id: \.self) { y in
                        Text("\(y) 年").tag(y)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(year) 年累计")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(yearTotal.yuanString)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }

            if data.isEmpty || data.allSatisfy({ $0.total == 0 }) {
                Text("\(year) 年还没有账单记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                Chart(data) { m in
                    LineMark(
                        x: .value("月份", m.month),
                        y: .value("金额", m.amount)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("月份", m.month),
                        y: .value("金额", m.amount)
                    )
                    .foregroundStyle(.blue)
                }
                .chartXAxis {
                    AxisMarks(values: data.map { $0.month }) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let m = value.as(Int.self) {
                                Text("\(m)月")
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 200)

                // 按月明细：可逐月查询金额
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(data) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(m.total.yuanString)
                                .font(.caption.bold())
                                .foregroundStyle(m.month == peakMonth ? .orange : .primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
