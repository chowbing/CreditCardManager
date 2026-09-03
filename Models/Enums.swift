import Foundation
import SwiftUI

// MARK: - 账单状态
enum StatementStatus: Int, CaseIterable, Identifiable {
    case pending = 0   // 未还
    case partial = 1   // 部分还
    case paid = 2      // 已还清
    case overdue = 3   // 逾期

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .pending:  return "未还"
        case .partial:  return "部分还"
        case .paid:     return "已还清"
        case .overdue:  return "逾期"
        }
    }

    // 用于图表/标签的颜色（SwiftUI Color）
    var color: Color {
        switch self {
        case .pending:  return .orange
        case .partial:  return .yellow
        case .paid:     return .green
        case .overdue:  return .red
        }
    }
}

// MARK: - 统计维度
enum StatisticsDimension: Int, CaseIterable, Identifiable {
    case byMonth = 0
    case byYear = 1
    case byCard = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .byMonth: return "按月"
        case .byYear:  return "按年"
        case .byCard:  return "按卡"
        }
    }
}

// MARK: - 提醒提前天数
enum ReminderLeadTime {
    static let `default` = 3
    static let options = [1, 3, 5, 7]
}

// MARK: - 常用预设卡色
enum CardPalette {
    static let colors: [String] = [
        "007AFF", "34C759", "FF3B30", "FF9500",
        "AF52DE", "5856D6", "FF2D55", "00C7BE",
        "FFCC00", "FF6482"
    ]
}

// MARK: - Hex -> Color 工具
extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - Decimal 格式化（人民币）
extension Decimal {
    var yuanString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "¥" + (formatter.string(from: NSDecimalNumber(decimal: self)) ?? "0.00")
    }
}

// MARK: - 状态标签
struct StatusBadge: View {
    let status: StatementStatus
    var body: some View {
        Text(status.title)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.color.opacity(0.15))
            .foregroundStyle(status.color)
            .clipShape(Capsule())
    }
}
