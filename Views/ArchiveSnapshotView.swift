import SwiftUI
import UIKit

/// 月度存档截图。
///
/// 只吃值类型（MonthlyArchive），不碰 Core Data / @FetchRequest，
/// 这样 ImageRenderer 才能稳定地离屏渲染成图片。
struct ArchiveSnapshotView: View {

    let archive: MonthlyArchive

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            rows
            footer
        }
        .frame(width: 360)
        .background(Color(.systemBackground))
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("信用卡账单 · 月度存档")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Text(archive.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(archive.total)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("共 \(archive.rowCount) 张卡 · 已全部还清")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.98, green: 0.35, blue: 0.42),
                         Color(red: 0.92, green: 0.28, blue: 0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    // MARK: - 明细

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(archive.rows.enumerated()), id: \.element.id) { idx, row in
                HStack(spacing: 10) {
                    Image(systemName: row.paid ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15))
                        .foregroundStyle(row.paid ? .yellow : Color.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.cardName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if !row.lastFour.isEmpty {
                            Text("尾号 \(row.lastFour) · 还款日 \(row.dueDate)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("还款日 \(row.dueDate)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(row.amount)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 11)

                if idx < archive.rows.count - 1 {
                    Divider().padding(.leading, 20)
                }
            }
        }
    }

    // MARK: - 页脚

    private var footer: some View {
        HStack {
            Text("存档时间 \(archivedAtText)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text("信用卡账单管理")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
    }

    private var archivedAtText: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy/M/d HH:mm"
        return f.string(from: archive.archivedAt)
    }
}

// MARK: - 渲染并保存截图

@MainActor
enum SnapshotSaver {

    /// 把存档渲染成图片并存入系统相册。
    /// 返回值只表示「图片已成功渲染并提交保存」；相册写入本身是异步的，
    /// 首次会由系统弹一次「允许添加照片」授权。
    @discardableResult
    static func saveToAlbum(archive: MonthlyArchive) -> Bool {
        let renderer = ImageRenderer(content: ArchiveSnapshotView(archive: archive))
        renderer.scale = 3.0
        guard let image = renderer.uiImage else { return false }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        return true
    }
}
