import Foundation
import SwiftData

// MARK: - 附属条目：一条联系人可以挂多个电话 / 邮箱 / 地址 / 纪念日

/// 电话号码条目
struct PhoneEntry: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var label: String = "手机"
    var number: String = ""
    /// 是否为主号（详情页顶部大按钮拨的就是它）
    var isPrimary: Bool = false

    var digitsOnly: String {
        number.filter { $0.isNumber || $0 == "+" }
    }
}

/// 邮箱条目
struct EmailEntry: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var label: String = "个人"
    var address: String = ""
}

/// 地址条目
struct AddressEntry: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var label: String = "住宅"
    var text: String = ""
}

/// 纪念日条目（生日、结婚纪念日、认识的日子……）
struct DateEntry: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var label: String = "生日"
    var date: Date = Date()
    /// 农历每年重复（这里只做标记，用于提示）
    var repeatsYearly: Bool = true
}

// MARK: - 电话 / 邮箱的预设标签

enum PhoneLabelSet {
    static let all = ["手机", "住宅", "工作", "学校", "传真", "主要", "其他"]

    /// 根据标签给一个 SF Symbol，让列表看起来更有层次
    static func symbol(for label: String) -> String {
        switch label {
        case "手机": return "iphone"
        case "住宅": return "house"
        case "工作": return "briefcase"
        case "学校": return "graduationcap"
        case "传真": return "printer"
        case "主要": return "star"
        default: return "phone"
        }
    }
}

enum EmailLabelSet {
    static let all = ["个人", "工作", "学校", "其他"]
}

enum AddressLabelSet {
    static let all = ["住宅", "工作", "学校", "其他"]
}

enum DateLabelSet {
    static let all = ["生日", "结婚纪念日", "相识纪念日", "其他"]
}

// MARK: - 主模型

@Model
final class Contact {

    // —— 身份 ——
    @Attribute(.unique) var id: UUID = UUID()

    var givenName: String = ""
    var familyName: String = ""
    var nickname: String = ""

    // —— 组织信息 ——
    var organization: String = ""
    var department: String = ""
    var jobTitle: String = ""

    // —— 多值字段 ——
    var phones: [PhoneEntry] = []
    var emails: [EmailEntry] = []
    var addresses: [AddressEntry] = []
    var dates: [DateEntry] = []

    // —— 自由字段 ——
    var note: String = ""
    /// 自定义标签，用于分组、关系图谱、批量筛选
    var tags: [String] = []

    // —— 视觉 ——
    /// 头像二进制（PNG / JPEG）。为空时用姓名首字生成文字头像
    @Attribute(.externalStorage) var avatarData: Data?

    // —— 状态 ——
    var isFavorite: Bool = false
    /// 是否被锁进「隐私保险箱」
    var isInVault: Bool = false
    /// 最近一次联系时间（拨号 / 发短信 / 手动标记都会更新）
    var lastContactedAt: Date?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // —— 派生缓存（保存时刷新，避免每次列表渲染都算拼音） ——
    /// 排序键：拼音全拼（小写），用于 A-Z 分组
    var sortKey: String = ""
    /// 索引字母：A-Z 或 #
    var indexLetter: String = "#"
    /// 全文搜索用小写拼接串
    var searchBlob: String = ""
    /// T9 数字键序列，用于九宫格匹配
    var t9Keys: [String] = []

    init(
        givenName: String = "",
        familyName: String = "",
        nickname: String = "",
        organization: String = "",
        phones: [PhoneEntry] = [],
        emails: [EmailEntry] = [],
        note: String = ""
    ) {
        self.id = UUID()
        self.givenName = givenName
        self.familyName = familyName
        self.nickname = nickname
        self.organization = organization
        self.phones = phones
        self.emails = emails
        self.note = note
        self.createdAt = Date()
        self.updatedAt = Date()
        refreshDerived()
    }
}

// MARK: - 计算属性

extension Contact {

    /// 展示名：中文习惯「姓 + 名」，全空时显示占位
    var displayName: String {
        let composed = (familyName + givenName).trimmingCharacters(in: .whitespaces)
        if !composed.isEmpty { return composed }
        if !nickname.isEmpty { return nickname }
        if !organization.isEmpty { return organization }
        if let first = phones.first, !first.number.isEmpty { return first.number }
        return "未命名联系人"
    }

    /// 是不是「空壳」联系人（没名没号）
    var isBlank: Bool {
        displayName == "未命名联系人"
    }

    /// 主号码
    var primaryPhone: PhoneEntry? {
        phones.first(where: { $0.isPrimary }) ?? phones.first(where: { !$0.number.isEmpty })
    }

    /// 头像上显示的字（中文取最后一个字更自然，英文取首字母）
    var monogram: String {
        let name = displayName
        guard let firstChar = name.first else { return "?" }
        // 中文名取姓（第一个字符）更符合直觉
        if firstChar.isASCII {
            return String(firstChar).uppercased()
        }
        return String(firstChar)
    }

    /// 组织 + 职位的一行摘要
    var subtitle: String {
        var parts: [String] = []
        if !organization.isEmpty { parts.append(organization) }
        if !department.isEmpty { parts.append(department) }
        if !jobTitle.isEmpty { parts.append(jobTitle) }
        return parts.joined(separator: " · ")
    }

    /// 距离上次联系过了多少天（没有记录返回 nil）
    var daysSinceLastContact: Int? {
        guard let last = lastContactedAt else { return nil }
        let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        return max(0, days)
    }

    /// 下一个生日（跨年自动滚到明年）
    var nextBirthday: Date? {
        guard let birthday = dates.first(where: { $0.label == "生日" })?.date else { return nil }
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.month, .day], from: birthday)
        comps.year = cal.component(.year, from: now)
        guard var candidate = cal.date(from: comps) else { return nil }
        // 今天已经过了，就滚到明年
        if cal.startOfDay(for: candidate) < cal.startOfDay(for: now) {
            comps.year = (comps.year ?? 0) + 1
            guard let next = cal.date(from: comps) else { return nil }
            candidate = next
        }
        return candidate
    }

    /// 距离生日还有几天
    var daysUntilBirthday: Int? {
        guard let next = nextBirthday else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                               to: Calendar.current.startOfDay(for: next)).day
    }
}

// MARK: - 派生数据刷新

extension Contact {

    /// 重新计算排序键、索引字母、搜索串、T9 键。
    /// 每次编辑保存后调用一次，列表渲染就只读不算了。
    func refreshDerived() {
        let nameForSort = displayName
        let fullPinyin = PinyinService.fullPinyin(nameForSort)

        sortKey = fullPinyin.lowercased()
        indexLetter = PinyinService.indexLetter(for: nameForSort)

        // 搜索串：姓名 + 昵称 + 公司 + 标签 + 号码 + 邮箱
        var blobParts: [String] = [nameForSort, nickname, organization, department, jobTitle]
        blobParts.append(contentsOf: tags)
        blobParts.append(contentsOf: phones.map(\.number))
        blobParts.append(contentsOf: emails.map(\.address))
        blobParts.append(note)
        searchBlob = blobParts
            .joined(separator: " ")
            .lowercased()

        t9Keys = T9Engine.buildKeys(
            name: nameForSort,
            organization: organization,
            phones: phones.map(\.number)
        )

        updatedAt = Date()
    }
}

// MARK: - 示例数据（首次安装时用，让空白界面不至于太寂寞）

enum SampleData {

    static func makeSamples() -> [Contact] {
        let contacts: [Contact] = [
            {
                let c = Contact(givenName: "小明", familyName: "张",
                                organization: "层楼工作室", phones: [
                                    PhoneEntry(label: "手机", number: "138 0013 8000", isPrimary: true)
                                ])
                c.jobTitle = "产品经理"
                c.emails = [EmailEntry(label: "工作", address: "xiaoming@example.com")]
                c.tags = ["同事"]
                c.isFavorite = true
                var d = DateEntry(); d.label = "生日"
                d.date = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
                c.dates = [d]
                c.lastContactedAt = Calendar.current.date(byAdding: .day, value: -2, to: Date())
                c.refreshDerived()
                return c
            }(),
            {
                let c = Contact(givenName: "芳", familyName: "李",
                                organization: "资阳市人民医院", phones: [
                                    PhoneEntry(label: "手机", number: "139 0013 9000", isPrimary: true),
                                    PhoneEntry(label: "工作", number: "028-2600 0000")
                                ])
                c.jobTitle = "骨科医生"
                c.tags = ["客户", "医疗"]
                var d = DateEntry(); d.label = "生日"
                d.date = Calendar.current.date(byAdding: .day, value: 12, to: Date()) ?? Date()
                c.dates = [d]
                c.lastContactedAt = Calendar.current.date(byAdding: .day, value: -46, to: Date())
                c.refreshDerived()
                return c
            }(),
            {
                let c = Contact(givenName: "建国", familyName: "王",
                                phones: [PhoneEntry(label: "手机", number: "137 0013 7000", isPrimary: true)])
                c.nickname = "老王"
                c.tags = ["家人"]
                c.lastContactedAt = Calendar.current.date(byAdding: .day, value: -9, to: Date())
                c.refreshDerived()
                return c
            }(),
            {
                // 故意造一个重复的，用来演示「智能去重」
                let c = Contact(givenName: "小明", familyName: "张",
                                phones: [PhoneEntry(label: "手机", number: "13800138000", isPrimary: true)])
                c.tags = ["同事"]
                c.refreshDerived()
                return c
            }()
        ]
        return contacts
    }
}
