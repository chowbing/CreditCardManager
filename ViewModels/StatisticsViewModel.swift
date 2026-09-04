import Foundation

/// 统计视图的状态与聚合选择
final class StatisticsViewModel: ObservableObject {
    @Published var dimension: StatisticsDimension = .byMonth
    /// 年度「月度账单总额」当前查看的年份
    @Published var historyYear: Int = Calendar.current.component(.year, from: Date())

    func points(for statements: [Statement]) -> [StatPoint] {
        switch dimension {
        case .byMonth: return StatisticsEngine.monthly(statements)
        case .byYear:  return StatisticsEngine.yearly(statements)
        case .byCard:  return StatisticsEngine.byCard(statements)
        }
    }
}
