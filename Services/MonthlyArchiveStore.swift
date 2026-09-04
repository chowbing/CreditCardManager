import Foundation

/// 月度存档中的一行（一张卡）
struct MonthlyArchiveRow: Codable, Identifiable {
    let id: String
    let cardName: String
    let lastFour: String
    /// 已格式化好的金额字符串（避免 Decimal 在 JSON 里的精度/兼容问题）
    let amount: String
    let dueDate: String
    let paid: Bool
}

/// 一个月度存档快照。
///
/// 刻意**不写进 Core Data**：程序化建模的 Core Data 一旦加实体就要处理模型版本兼容，
/// 越狱包没有迁移失败的容错。存档是「只读历史」，用 JSON 文件存最稳妥，
/// 也方便以后随导出功能一起打包带走。
struct MonthlyArchive: Codable, Identifiable {
    /// "2026-09"
    let id: String
    let year: Int
    let month: Int
    let total: String
    let rowCount: Int
    let archivedAt: Date
    let rows: [MonthlyArchiveRow]

    var title: String { "\(year)年\(month)月" }
}

/// 月度存档仓库：Application Support/MonthlyArchives/YYYY-MM.json
final class MonthlyArchiveStore {

    static let shared = MonthlyArchiveStore()

    private let fm = FileManager.default
    private let dir: URL

    private init() {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        dir = base.appendingPathComponent("MonthlyArchives", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func isArchived(year: Int, month: Int) -> Bool {
        fm.fileExists(atPath: fileURL(year: year, month: month).path)
    }

    /// 全部存档，按账期倒序（最近的在前）
    func all() -> [MonthlyArchive] {
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> MonthlyArchive? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(MonthlyArchive.self, from: data)
            }
            .sorted {
                CycleManager.encode(year: $0.year, month: $0.month)
                    > CycleManager.encode(year: $1.year, month: $1.month)
            }
    }

    @discardableResult
    func save(_ archive: MonthlyArchive) -> Bool {
        guard let data = try? JSONEncoder().encode(archive) else { return false }
        do {
            try data.write(to: fileURL(year: archive.year, month: archive.month), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func fileURL(year: Int, month: Int) -> URL {
        dir.appendingPathComponent(String(format: "%04d-%02d.json", year, month))
    }
}
