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

    var body: some View {
        NavigationStack {
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
