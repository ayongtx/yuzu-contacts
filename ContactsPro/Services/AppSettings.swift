import SwiftUI
import Combine

// MARK: - 主题色

enum AccentTheme: String, CaseIterable, Identifiable {
    case ocean, violet, teal, sunset, rose, graphite

    var id: String { rawValue }

    var name: String {
        switch self {
        case .ocean: return "海蓝"
        case .violet: return "雾紫"
        case .teal: return "青碧"
        case .sunset: return "落日"
        case .rose: return "玫瑰"
        case .graphite: return "石墨"
        }
    }

    var color: Color {
        switch self {
        case .ocean: return Color(red: 0.11, green: 0.45, blue: 0.92)
        case .violet: return Color(red: 0.45, green: 0.35, blue: 0.85)
        case .teal: return Color(red: 0.10, green: 0.62, blue: 0.60)
        case .sunset: return Color(red: 0.93, green: 0.45, blue: 0.20)
        case .rose: return Color(red: 0.88, green: 0.28, blue: 0.45)
        case .graphite: return Color(red: 0.35, green: 0.38, blue: 0.44)
        }
    }
}

// MARK: - 全局设置

/// 用 UserDefaults 落盘的小配置集合。改完即时生效，重装前一直保留。
final class AppSettings: ObservableObject {

    private let store = UserDefaults.standard

    @Published var accentKey: String {
        didSet { store.set(accentKey, forKey: Keys.accent) }
    }

    /// 保险箱功能总开关
    @Published var vaultEnabled: Bool {
        didSet { store.set(vaultEnabled, forKey: Keys.vaultEnabled) }
    }

    /// 退到后台多久后自动上锁（秒），0 表示立即
    @Published var autoLockSeconds: Int {
        didSet { store.set(autoLockSeconds, forKey: Keys.autoLock) }
    }

    /// 「冷落提醒」阈值：超过多少天没联系就提醒
    @Published var neglectDays: Int {
        didSet { store.set(neglectDays, forKey: Keys.neglectDays) }
    }

    /// 列表是否显示联系人头像
    @Published var showAvatars: Bool {
        didSet { store.set(showAvatars, forKey: Keys.showAvatars) }
    }

    /// 列表按「姓」还是按「名」排序
    @Published var sortByFamilyName: Bool {
        didSet { store.set(sortByFamilyName, forKey: Keys.sortByFamily) }
    }

    /// 保险箱 PIN 的 SHA256（空表示尚未设置）
    @Published var pinHash: String {
        didSet { store.set(pinHash, forKey: Keys.pinHash) }
    }

    var hasPIN: Bool { !pinHash.isEmpty }

    var accent: AccentTheme {
        AccentTheme(rawValue: accentKey) ?? .ocean
    }

    var accentColor: Color { accent.color }

    private enum Keys {
        static let accent = "cp.accent"
        static let vaultEnabled = "cp.vaultEnabled"
        static let autoLock = "cp.autoLockSeconds"
        static let neglectDays = "cp.neglectDays"
        static let showAvatars = "cp.showAvatars"
        static let sortByFamily = "cp.sortByFamily"
        static let pinHash = "cp.pinHash"
    }

    init() {
        accentKey = store.string(forKey: Keys.accent) ?? AccentTheme.ocean.rawValue

        // UserDefaults 没有值时会返回 false，这里需要区分「没设过」和「设成 false」
        if store.object(forKey: Keys.vaultEnabled) == nil {
            vaultEnabled = true
        } else {
            vaultEnabled = store.bool(forKey: Keys.vaultEnabled)
        }

        autoLockSeconds = store.object(forKey: Keys.autoLock) as? Int ?? 0
        neglectDays = store.object(forKey: Keys.neglectDays) as? Int ?? 45

        if store.object(forKey: Keys.showAvatars) == nil {
            showAvatars = true
        } else {
            showAvatars = store.bool(forKey: Keys.showAvatars)
        }

        if store.object(forKey: Keys.sortByFamily) == nil {
            sortByFamilyName = true
        } else {
            sortByFamilyName = store.bool(forKey: Keys.sortByFamily)
        }

        pinHash = store.string(forKey: Keys.pinHash) ?? ""
    }
}
