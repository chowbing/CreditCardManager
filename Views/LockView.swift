import SwiftUI
import UIKit

/// 应用锁界面：Face ID / Touch ID / 设备密码 解锁
struct LockView: View {
    @StateObject private var lockState = LockState.shared
    @State private var message: String?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 52))
                .foregroundStyle(.accentColor)
            Text("已锁定")
                .font(.title2.bold())
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button {
                SecurityService.shared.authenticate { success, err in
                    if success {
                        lockState.isLocked = false
                    } else {
                        message = err ?? "验证失败，请重试"
                    }
                }
            } label: {
                Label("使用 Face ID / 密码解锁", systemImage: "faceid")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}
