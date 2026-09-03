import Foundation
import LocalAuthentication

/// 应用锁：基于 LocalAuthentication（Face ID / Touch ID / 设备密码兜底）
final class SecurityService {
    static let shared = SecurityService()

    /// 设备是否支持生物识别
    func biometryAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// 弹出系统验证（成功或失败通过 completion 回调）
    func authenticate(reason: String = "解锁以查看账单",
                     completion: @escaping (Bool, String?) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(false, error?.localizedDescription ?? "设备不支持身份验证")
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: reason) { success, err in
            DispatchQueue.main.async {
                completion(success, err?.localizedDescription)
            }
        }
    }
}
