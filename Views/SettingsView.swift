import SwiftUI
import CloudKit
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @StateObject private var lockState = LockState.shared

    @State private var leadDays: Int = {
        let v = UserDefaults.standard.integer(forKey: "reminderLeadDays")
        return v > 0 ? v : ReminderLeadTime.default
    }()
    @State private var icloudStatus: String = "检测中…"
    @State private var showClearConfirm = false

    @Environment(\.managedObjectContext) private var context
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var showImporter = false
    @State private var resultMessage: String?
    @State private var showResultAlert = false

    // 注意：NavigationStack 由 MainTabView 统一提供（点 Tab 可弹回根页）
    var body: some View {
        Form {
                Section {
                    Toggle("应用锁（Face ID / 密码）", isOn: $appLockEnabled)
                        .onChange(of: appLockEnabled) { newValue in
                            if newValue {
                                lockState.isLocked = true
                            }
                        }
                    if appLockEnabled {
                        Text("开启后，每次从后台返回都需要验证身份。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("安全") }

                Section {
                    Picker("提前提醒天数", selection: $leadDays) {
                        ForEach(ReminderLeadTime.options, id: \.self) { d in
                            Text("提前 \(d) 天").tag(d)
                        }
                    }
                    .onChange(of: leadDays) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "reminderLeadDays")
                        NotificationService.shared.rescheduleAll()
                    }
                    Text("将在还款日前与当天发送本地通知。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("还款提醒") }

                Section {
                    HStack {
                        Text("iCloud 同步")
                        Spacer()
                        Text(icloudStatus).foregroundStyle(.secondary)
                    }
                    Text("数据存入你的 iCloud 私有库，加密同步至多设备。需在“签名与能力”中开启 iCloud/CloudKit。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("数据同步") }

                Section {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Text("清空所有数据")
                    }
                } header: { Text("数据管理") }

                Section {
                    Button {
                        do {
                            let url = try DataTransfer.writeExportFile(context: context)
                            shareItems = [url]
                            showShare = true
                        } catch {
                            resultMessage = "导出失败：\(error.localizedDescription)"
                            showResultAlert = true
                        }
                    } label: { Label("导出数据", systemImage: "square.and.arrow.up") }

                    Button {
                        showImporter = true
                    } label: { Label("导入数据", systemImage: "square.and.arrow.down") }
                    Text("导出为 JSON 备份文件，可经 AirDrop / 文件 App / 微信等传到另一台手机后导入；导入按卡片与账单的唯一 ID 合并，不会重复。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("数据备份（跨设备迁移）") }

                Section {
                    LabeledContent("应用名称", value: "信用卡账单管理")
                    LabeledContent("最低系统", value: "iOS 16.0")
                    if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        LabeledContent("版本", value: v)
                    }
                } header: { Text("关于") }
            }
            .navigationTitle("设置")
            .onAppear(perform: checkCloudKit)
            .alert("确认清空？", isPresented: $showClearConfirm) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) {
                    PersistenceController.shared.clearAll()
                }
            } message: {
                Text("将删除全部信用卡与账单数据，且无法恢复。")
            }
            .sheet(isPresented: $showShare) {
                ActivityView(activityItems: shareItems)
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.json, .data],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    guard url.startAccessingSecurityScopedResource() else {
                        resultMessage = "无法访问所选文件"
                        showResultAlert = true
                        return
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        let data = try Data(contentsOf: url)
                        let (c, s) = try DataTransfer.importJSON(data, context: context)
                        NotificationService.shared.rescheduleAll()
                        resultMessage = "导入成功：共 \(c) 张卡、\(s) 笔账单"
                    } catch {
                        resultMessage = "导入失败：\(error.localizedDescription)"
                    }
                    showResultAlert = true
                case .failure(let error):
                    resultMessage = "选择文件失败：\(error.localizedDescription)"
                    showResultAlert = true
                }
            }
            .alert("提示", isPresented: $showResultAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text(resultMessage ?? "")
            }
    }

    private func checkCloudKit() {
        // 越狱无签名 IPA 未配置 iCloud entitlements，调用 CloudKit API 会直接崩溃。
        // 仅在明确开启 CloudKit 时才探测；否则跳过并显示本地存储状态。
        guard PersistenceController.enableCloudKit else {
            icloudStatus = "未开启（本地存储）"
            return
        }
        CKContainer(identifier: PersistenceController.cloudKitContainerID)
            .accountStatus { status, _ in
                DispatchQueue.main.async {
                    switch status {
                    case .available:
                        icloudStatus = "已开启"
                    case .noAccount:
                        icloudStatus = "未登录 iCloud"
                    case .restricted:
                        icloudStatus = "受限制"
                    case .couldNotDetermine:
                        icloudStatus = "未知"
                    case .temporarilyUnavailable:
                        icloudStatus = "iCloud 暂时不可用"
                    @unknown default:
                        icloudStatus = "未知"
                    }
                }
            }
    }
}

// MARK: - 系统分享面板（导出备份文件用）
private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
