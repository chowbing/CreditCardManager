import Foundation
import SwiftUI

/// 一次月度结算的产物，用于给用户弹提示
struct SettlementResult {
    let archive: MonthlyArchive
    let imageSaved: Bool
    let nextYear: Int
    let nextMonth: Int
}

/// 月度结算：当月所有卡片都还清后执行
/// 存档 → 截图到相册 → 安排自动切换到下一月账期
@MainActor
enum MonthlySettlement {

    /// 默认延迟多少分钟切换到下一账期
    /// nonisolated：默认参数表达式在调用方上下文求值，需非隔离常量
    nonisolated static let defaultRolloverMinutes = 5

    /// 执行结算。已经存档过的月份会直接返回 nil，防止重复触发。
    static func run(cards: [CreditCard],
                    year: Int,
                    month: Int,
                    rolloverMinutes: Int = defaultRolloverMinutes) -> SettlementResult? {
        let store = MonthlyArchiveStore.shared
        guard !store.isArchived(year: year, month: month) else { return nil }

        // 只统计「填了金额」的账单；没填金额的卡不算未还清，不阻塞结算
        var rows: [MonthlyArchiveRow] = []
        var total: Decimal = 0
        for card in cards {
            guard let s = card.statement(year: year, month: month), s.total > 0 else { continue }
            total += s.total
            rows.append(MonthlyArchiveRow(
                id: UUID().uuidString,
                cardName: card.displayName,
                lastFour: card.lastFour ?? "",
                amount: s.total.yuanString,
                dueDate: s.dueDate?.monthDayLabel ?? "-",
                paid: s.paid >= s.total
            ))
        }

        // 一张卡都没填金额 → 不结算（避免刚切到新月就立刻又存档）
        guard !rows.isEmpty else { return nil }

        let archive = MonthlyArchive(
            id: String(format: "%04d-%02d", year, month),
            year: year,
            month: month,
            total: total.yuanString,
            rowCount: rows.count,
            archivedAt: Date(),
            rows: rows
        )
        store.save(archive)

        let imageSaved = SnapshotSaver.saveToAlbum(archive: archive)

        let next = CycleManager.decode(CycleManager.encode(year: year, month: month) + 1)
        CycleManager.shared.scheduleAutoRollover(minutes: rolloverMinutes)
        NotificationService.shared.scheduleRolloverNotice(year: next.year,
                                                          month: next.month,
                                                          seconds: Double(rolloverMinutes) * 60)

        return SettlementResult(archive: archive,
                                imageSaved: imageSaved,
                                nextYear: next.year,
                                nextMonth: next.month)
    }
}
