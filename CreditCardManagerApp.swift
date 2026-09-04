import SwiftUI
import UIKit

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
}
