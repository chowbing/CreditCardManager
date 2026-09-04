import SwiftUI

/// 本 App 内直接列出「文件 App 共享目录」（UIFileSharingEnabled 开启后可见）里的
/// .json 备份文件，点选即导入。完全不依赖系统文档选择器 / 打开方式，
/// 是无签名 IPA 上可靠的导入方案。
struct LocalImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @State private var files: [URL] = []
    @State private var message: String? = nil
    @State private var showAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if files.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "tray")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("没有可导入的备份")
                            .font(.headline)
                        Text("请把备份文件（.json）通过「文件 App」放进本 App 的共享目录：\niPhone → 信用卡账单\n\n然后再回到此处即可看到并导入。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(.top, 40)
                } else {
                    List(files, id: \.self) { url in
                        Button {
                            importFile(url)
                        } label: {
                            Label(url.lastPathComponent, systemImage: "doc.fill")
                        }
                    }
                }
            }
            .navigationTitle("选择备份文件")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear(perform: reload)
            .alert("导入结果", isPresented: $showAlert) {
                Button("好") { showAlert = false }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func reload() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let all = (try? FileManager.default.contentsOfDirectory(at: docs,
                                                               includingPropertiesForKeys: nil)) ?? []
        files = all
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func importFile(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let (c, s) = try DataTransfer.importJSON(data, context: context)
            NotificationService.shared.rescheduleAll()
            message = "导入成功：共 \(c) 张卡、\(s) 笔账单"
        } catch {
            message = "导入失败：\(error.localizedDescription)"
        }
        showAlert = true
    }
}
