import Foundation
import CoreData

// MARK: - 数据迁移（导入 / 导出）
// 用途：在不同手机之间迁移全部信用卡与账单数据。
// 导出为 JSON 文件，可经 AirDrop / 文件 App / 微信等任意方式传到另一台手机后导入。
// 导入按 id 做 upsert：已存在则覆盖，不存在则新建；账单按 cardId 关联卡片。

private struct CardDTO: Codable {
    let id: UUID
    let bankName: String?
    let nickname: String?
    let lastFour: String?
    let statementDay: Int
    let dueDay: Int
    let creditLimit: Double?
    let colorHex: String?
    let order: Int
    let isArchived: Bool
    let createdAt: Date?
    let updatedAt: Date?
}

private struct StatementDTO: Codable {
    let id: UUID
    let cardId: UUID
    let year: Int
    let month: Int
    let statementDate: Date?
    let dueDate: Date?
    let totalAmount: Double
    let paidAmount: Double
    let isPaidInFull: Bool
    let statusRaw: Int
    let note: String?
    let reminderOn: Bool
    let createdAt: Date?
    let updatedAt: Date?
}

private struct BackupPayload: Codable {
    let app: String
    let version: Int
    let exportedAt: Date
    let cards: [CardDTO]
    let statements: [StatementDTO]
}

enum DataTransfer {
    /// 收集全部数据为可编码的载荷
    /// 注：BackupPayload 为文件私有类型，故本方法必须声明为 fileprivate，
    /// 否则 internal 方法返回 private 类型会触发 "method must be declared fileprivate" 编译错误。
    fileprivate static func exportPayload(context: NSManagedObjectContext) -> BackupPayload {
        let cardReq = CreditCard.fetchRequest()
        let cards = (try? context.fetch(cardReq)) ?? []
        let stmtReq = Statement.fetchRequest()
        let stmts = (try? context.fetch(stmtReq)) ?? []

        let cardDTOs = cards.map { c in
            CardDTO(
                id: c.id ?? UUID(),
                bankName: c.bankName,
                nickname: c.nickname,
                lastFour: c.lastFour,
                statementDay: Int(c.statementDay),
                dueDay: Int(c.dueDay),
                creditLimit: c.creditLimit?.doubleValue,
                colorHex: c.colorHex,
                order: Int(c.order),
                isArchived: c.isArchived,
                createdAt: c.createdAt,
                updatedAt: c.updatedAt
            )
        }

        let stmtDTOs = stmts.compactMap { s -> StatementDTO? in
            guard let card = s.card, let cardId = card.id, let id = s.id else { return nil }
            return StatementDTO(
                id: id,
                cardId: cardId,
                year: Int(s.year),
                month: Int(s.month),
                statementDate: s.statementDate,
                dueDate: s.dueDate,
                totalAmount: s.totalAmount?.doubleValue ?? 0,
                paidAmount: s.paidAmount?.doubleValue ?? 0,
                isPaidInFull: s.isPaidInFull,
                statusRaw: Int(s.statusRaw),
                note: s.note,
                reminderOn: s.reminderOn,
                createdAt: s.createdAt,
                updatedAt: s.updatedAt
            )
        }

        return BackupPayload(
            app: "CreditCardManager",
            version: 1,
            exportedAt: Date(),
            cards: cardDTOs,
            statements: stmtDTOs
        )
    }

    /// 导出为格式化的 JSON Data
    static func exportJSON(context: NSManagedObjectContext) throws -> Data {
        let payload = exportPayload(context: context)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    /// 写入临时目录并返回文件 URL（供系统分享面板使用）
    static func writeExportFile(context: NSManagedObjectContext) throws -> URL {
        let data = try exportJSON(context: context)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let name = "信用卡账单备份-\(fmt.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 写入 App 的 Documents 目录（开启 UIFileSharingEnabled 后在「文件 App →
    /// 本 App 目录」可见）。既可供分享面板 AirDrop/微信传出，也会留在本地，
    /// 便于另一台设备把备份文件放进该目录后由 App 内列表直接导入。
    /// 这是无签名 IPA 上唯一可靠的导入通道（系统选文件框 / 打开方式均不可用）。
    static func writeExportToDocuments(context: NSManagedObjectContext) throws -> URL {
        let data = try exportJSON(context: context)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let name = "信用卡账单备份-\(fmt.string(from: Date())).json"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 导入（按 id upsert）。已存在覆盖、不存在新建；账单按 cardId 关联卡片。
    /// 导入后自动刷新状态（paid/total → status）并保存。
    @discardableResult
    static func importJSON(_ data: Data, context: NSManagedObjectContext) throws -> (cards: Int, statements: Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)

        // 卡片 upsert
        let cardReq = CreditCard.fetchRequest()
        let existingCards = (try? context.fetch(cardReq)) ?? []
        var cardById = [UUID: CreditCard]()
        for c in existingCards where c.id != nil { cardById[c.id!] = c }

        for dto in payload.cards {
            let card = cardById[dto.id] ?? CreditCard(context: context)
            card.id = dto.id
            card.bankName = dto.bankName
            card.nickname = dto.nickname
            card.lastFour = dto.lastFour
            card.statementDay = Int32(dto.statementDay)
            card.dueDay = Int32(dto.dueDay)
            if let cl = dto.creditLimit {
                card.creditLimit = NSDecimalNumber(value: cl)
            }
            card.colorHex = dto.colorHex
            card.order = Int32(dto.order)
            card.isArchived = dto.isArchived
            card.createdAt = dto.createdAt
            card.updatedAt = dto.updatedAt
            cardById[dto.id] = card
        }

        // 账单 upsert
        let stmtReq = Statement.fetchRequest()
        let existingStmts = (try? context.fetch(stmtReq)) ?? []
        var stmtById = [UUID: Statement]()
        for s in existingStmts where s.id != nil { stmtById[s.id!] = s }

        for dto in payload.statements {
            guard let card = cardById[dto.cardId] else { continue }
            let stmt = stmtById[dto.id] ?? Statement(context: context)
            stmt.id = dto.id
            stmt.card = card
            stmt.year = Int32(dto.year)
            stmt.month = Int32(dto.month)
            stmt.statementDate = dto.statementDate
            stmt.dueDate = dto.dueDate
            stmt.totalAmount = NSDecimalNumber(value: dto.totalAmount)
            stmt.paidAmount = NSDecimalNumber(value: dto.paidAmount)
            stmt.isPaidInFull = dto.isPaidInFull
            stmt.statusRaw = Int32(dto.statusRaw)
            stmt.note = dto.note
            stmt.reminderOn = dto.reminderOn
            stmt.createdAt = dto.createdAt
            stmt.updatedAt = dto.updatedAt
            stmt.refreshStatus()
            stmtById[dto.id] = stmt
        }

        let cardCount = payload.cards.count
        let stmtCount = payload.statements.count
        if context.hasChanges {
            try context.save()
        }
        return (cardCount, stmtCount)
    }
}
