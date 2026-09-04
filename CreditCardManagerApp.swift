import SwiftUI
import UIKit

extension Notification.Name {
    /// 由 AppDelegate(application:open:) 导入备份文件后广播结果，供 RootView 弹提示
    static let dataImportResult = Notification.Name("com.creditcardmanager.dataImportResult")
}

/// 缓存最近一次导入结果。
/// 冷启动时被 openURL 触发、RootView 尚未挂载时，通知会错过订阅者，
/// 故同时落一份到本单例，由 RootView.onAppear 补读。
final class ImportResultStore: ObservableObject {
    static let shared = ImportResultStore()
    @Published var message: String? = nil
}

@main
struct CreditCardManagerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationService.shared.requestAuthorization()
        // 启动即检查一次：若 App 被 kill 期间账期已到期，直接进位，避免下次才跳月
        CycleManager.shared.performRolloverIfDue()
        return true
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // 先重排提醒（会清掉旧的账期切换提醒再按仍需的补回），
        // 再执行到期进位，这样「账期已切换」通知不会被 rescheduleAll 误清。
        NotificationService.shared.rescheduleAll()
        CycleManager.shared.performRolloverIfDue()
    }

    /// 由「文件 App / 微信 等」用「拷贝到 CreditCardManager / 打开方式」传入的备份文件。
    /// 走这条通道可彻底绕开系统文档选择器的 UTI/位置限制（无签名 IPA 常见选不中）。
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        Task { @MainActor in
            let message: String
            do {
                let data = try Data(contentsOf: url)
                let (c, s) = try DataTransfer.importJSON(data,
                                                         context: PersistenceController.shared.container.viewContext)
                NotificationService.shared.rescheduleAll()
                message = "导入成功：共 \(c) 张卡、\(s) 笔账单"
            } catch {
                message = "导入失败：\(error.localizedDescription)"
            }
            ImportResultStore.shared.message = message
            NotificationCenter.default.post(name: .dataImportResult,
                                            object: nil,
                                            userInfo: ["message": message])
        }
        return true
    }
}
