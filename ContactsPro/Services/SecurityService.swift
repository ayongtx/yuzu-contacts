import Foundation
import LocalAuthentication
import CryptoKit
import Combine

/// 保险箱的解锁状态管理。
///
/// 设计上优先用 Face ID / Touch ID / 设备密码；
/// 但自签证书（个人免费证书）偶尔拿不到生物识别权限，
/// 所以额外准备了一个应用内 PIN 兜底，保证任何情况下都进得去。
final class SecurityService: ObservableObject {

    @Published var isUnlocked = false
    /// 连续失败次数，达标后强制改用 PIN
    @Published var failedAttempts = 0

    private var context = LAContext()

    /// 系统生物识别是否可用
    var biometryAvailable: Bool {
        let ctx = LAContext()
        var error: NSError?
        return ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// "面容 ID" / "触控 ID" / "密码"
    var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch ctx.biometryType {
        case .faceID: return "面容 ID"
        case .touchID: return "触控 ID"
        case .opticID: return "光学 ID"
        default: return "设备密码"
        }
    }

    var biometrySymbol: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch ctx.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.open"
        }
    }

    /// 弹系统验证。成功返回 true 并置为已解锁。
    @MainActor
    func authenticate(reason: String = "解锁隐私保险箱") async -> Bool {
        context = LAContext()
        context.localizedFallbackTitle = "使用设备密码"
        context.localizedCancelTitle = "取消"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            failedAttempts += 1
            return false
        }

        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            if ok {
                isUnlocked = true
                failedAttempts = 0
            }
            return ok
        } catch {
            failedAttempts += 1
            return false
        }
    }

    func lock() {
        isUnlocked = false
        failedAttempts = 0
    }

    // MARK: - PIN 兜底

    static func hash(_ pin: String) -> String {
        let data = Data(pin.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func verify(pin: String, against hash: String) -> Bool {
        guard !hash.isEmpty else { return true }
        return Self.hash(pin) == hash
    }
}
