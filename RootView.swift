import SwiftUI
import UIKit

/// 应用锁状态（全局单例）
final class LockState: ObservableObject {
    static let shared = LockState()
    @Published var isLocked = false
}

/// 根视图：Tab 导航 + 应用锁覆盖层
struct RootView: View {
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @StateObject private var lockState = LockState.shared

    var body: some View {
        ZStack {
            MainTabView()
                .opacity(appLockEnabled && lockState.isLocked ? 0 : 1)
            if appLockEnabled && lockState.isLocked {
                LockView()
            }
        }
        .onAppear {
            if appLockEnabled { lockState.isLocked = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            if appLockEnabled { lockState.isLocked = true }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            OverviewView()
                .tabItem { Label("概览", systemImage: "house.fill") }
            CardsView()
                .tabItem { Label("卡片", systemImage: "creditcard.fill") }
            StatisticsView()
                .tabItem { Label("统计", systemImage: "chart.bar.fill") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
    }
}
