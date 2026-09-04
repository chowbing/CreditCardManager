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
    @State private var importMessage: String? = nil

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
            // 冷启动：openURL 可能在 RootView 挂载前就触发，补读缓存的导入结果
            if let m = ImportResultStore.shared.message {
                importMessage = m
                ImportResultStore.shared.message = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            if appLockEnabled { lockState.isLocked = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dataImportResult)) { note in
            if let msg = note.userInfo?["message"] as? String {
                importMessage = msg
                ImportResultStore.shared.message = nil
            }
        }
        .alert("导入结果", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("好", role: .cancel) { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }
}

/// 底部 Tab
enum AppTab: Hashable {
    case overview, cards, statistics, settings
}

struct MainTabView: View {
    @State private var selection: AppTab = .overview

    // 每个 Tab 各自的导航路径。交给外层统一持有，
    // 才能在「再次点击已选中的 Tab」时把它弹回根页面。
    @State private var overviewPath = NavigationPath()
    @State private var cardsPath = NavigationPath()
    @State private var statisticsPath = NavigationPath()
    @State private var settingsPath = NavigationPath()

    var body: some View {
        TabView(selection: tabBinding) {
            NavigationStack(path: $overviewPath) {
                OverviewView()
            }
            .tabItem { Label("概览", systemImage: "house.fill") }
            .tag(AppTab.overview)

            NavigationStack(path: $cardsPath) {
                CardsView()
            }
            .tabItem { Label("卡片", systemImage: "creditcard.fill") }
            .tag(AppTab.cards)

            NavigationStack(path: $statisticsPath) {
                StatisticsView()
            }
            .tabItem { Label("统计", systemImage: "chart.bar.fill") }
            .tag(AppTab.statistics)

            NavigationStack(path: $settingsPath) {
                SettingsView()
            }
            .tabItem { Label("设置", systemImage: "gearshape.fill") }
            .tag(AppTab.settings)
        }
    }

    /// 自定义 Binding：点击「当前已选中」的 Tab 时，TabView 仍会写入同一个值，
    /// 借此把该 Tab 的导航栈清空 —— 效果等同连点左上角 Back 回到主页。
    private var tabBinding: Binding<AppTab> {
        Binding(
            get: { selection },
            set: { newValue in
                if newValue == selection {
                    popToRoot(newValue)
                }
                selection = newValue
            }
        )
    }

    private func popToRoot(_ tab: AppTab) {
        switch tab {
        case .overview:   overviewPath = NavigationPath()
        case .cards:      cardsPath = NavigationPath()
        case .statistics: statisticsPath = NavigationPath()
        case .settings:   settingsPath = NavigationPath()
        }
    }
}
