import Foundation
import SwiftUI

// MARK: - 重复联系人

struct DuplicateGroup: Identifiable {
    var contacts: [Contact]
    /// 为什么被判为重复
    var reasons: [String]

    /// 用第一个成员的 id 当组 id。
    /// 关键：每次重新扫描时会新建 DuplicateGroup 实例，
    /// 如果用 UUID() 随机 id，confirmationDialog 的绑定会对不上号导致弹窗一闪而过。
    /// 成员 id 是稳定的，这样重扫前后同一组人的组 id 保持一致。
    var id: UUID { contacts.first?.id ?? UUID() }

    var displayName: String {
        contacts.first?.displayName ?? "未知"
    }

    /// 合并后建议保留的那一位（信息最全的）
    var keeper: Contact? {
        contacts.max { score($0) < score($1) }
    }

    private func score(_ c: Contact) -> Int {
        var s = 0
        s += c.phones.count * 3
        s += c.emails.count * 2
        s += c.addresses.count
        s += c.dates.count
        if c.avatarData != nil { s += 4 }
        if !c.note.isEmpty { s += 1 }
        if !c.organization.isEmpty { s += 2 }
        s += c.tags.count
        return s
    }
}

enum DuplicateDetector {

    /// 把号码归一化成可比较的形式：只留数字，去掉 +86 / 86 前缀
    static func normalize(_ number: String) -> String {
        var digits = number.filter(\.isNumber)
        if digits.hasPrefix("0086") {
            digits.removeFirst(4)
        } else if digits.hasPrefix("86") && digits.count > 11 {
            digits.removeFirst(2)
        }
        return digits
    }

    /// 用并查集把「号码相同」或「姓名拼音相同」的联系人合并成组
    static func findDuplicates(in contacts: [Contact]) -> [DuplicateGroup] {
        guard contacts.count > 1 else { return [] }

        var parent: [UUID: UUID] = [:]
        for c in contacts { parent[c.id] = c.id }

        func find(_ x: UUID) -> UUID {
            var current = x
            while let p = parent[current], p != current {
                parent[current] = parent[p] ?? p
                current = p
            }
            return current
        }

        func union(_ a: UUID, _ b: UUID) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[rb] = ra }
        }

        var byPhone: [String: UUID] = [:]
        var byName: [String: UUID] = [:]
        var nameReason: [UUID: Bool] = [:]
        var phoneReason: [UUID: Bool] = [:]

        for c in contacts {
            for p in c.phones {
                let key = normalize(p.number)
                guard key.count >= 5 else { continue }
                if let other = byPhone[key] {
                    union(other, c.id)
                    phoneReason[c.id] = true
                    phoneReason[other] = true
                } else {
                    byPhone[key] = c.id
                }
            }

            let nameKey = PinyinService.fullPinyin(c.displayName)
                .replacingOccurrences(of: " ", with: "")
            guard nameKey.count >= 2, c.displayName != "未命名联系人" else { continue }
            if let other = byName[nameKey] {
                union(other, c.id)
                nameReason[c.id] = true
                nameReason[other] = true
            } else {
                byName[nameKey] = c.id
            }
        }

        var buckets: [UUID: [Contact]] = [:]
        for c in contacts {
            buckets[find(c.id), default: []].append(c)
        }

        return buckets.values
            .filter { $0.count > 1 }
            .map { group in
                var reasons: [String] = []
                if group.contains(where: { phoneReason[$0.id] == true }) {
                    reasons.append("号码重复")
                }
                if group.contains(where: { nameReason[$0.id] == true }) {
                    reasons.append("姓名相同")
                }
                return DuplicateGroup(
                    contacts: group.sorted { $0.sortKey < $1.sortKey },
                    reasons: reasons.isEmpty ? ["疑似重复"] : reasons
                )
            }
            .sorted { $0.contacts.count > $1.contacts.count }
    }

    /// 合并：把 others 的电话/邮箱/地址/日期/标签并入 keeper，然后删掉 others
    static func merge(_ group: DuplicateGroup, into keeper: Contact) -> [Contact] {
        var removed: [Contact] = []

        for other in group.contacts where other.id != keeper.id {
            // 号码去重后并入
            for phone in other.phones {
                let key = normalize(phone.number)
                let exists = keeper.phones.contains { normalize($0.number) == key }
                if !exists, !key.isEmpty {
                    keeper.phones.append(phone)
                }
            }
            for email in other.emails where !keeper.emails.contains(where: { $0.address.lowercased() == email.address.lowercased() }) {
                keeper.emails.append(email)
            }
            for addr in other.addresses where !keeper.addresses.contains(where: { $0.text == addr.text }) {
                keeper.addresses.append(addr)
            }
            for date in other.dates where !keeper.dates.contains(where: { $0.label == date.label }) {
                keeper.dates.append(date)
            }
            for tag in other.tags where !keeper.tags.contains(tag) {
                keeper.tags.append(tag)
            }

            if keeper.avatarData == nil { keeper.avatarData = other.avatarData }
            if keeper.note.isEmpty { keeper.note = other.note }
            if keeper.organization.isEmpty { keeper.organization = other.organization }
            if keeper.jobTitle.isEmpty { keeper.jobTitle = other.jobTitle }
            if keeper.nickname.isEmpty { keeper.nickname = other.nickname }
            if keeper.givenName.isEmpty { keeper.givenName = other.givenName }
            if keeper.familyName.isEmpty { keeper.familyName = other.familyName }

            // 最近联系时间取更近的那个
            if let a = other.lastContactedAt, let b = keeper.lastContactedAt {
                keeper.lastContactedAt = max(a, b)
            } else if let a = other.lastContactedAt {
                keeper.lastContactedAt = a
            }

            keeper.isFavorite = keeper.isFavorite || other.isFavorite

            removed.append(other)
        }

        keeper.refreshDerived()
        return removed
    }
}

// MARK: - 通讯录体检

struct HealthReport {

    var total: Int = 0
    var withoutPhone: [Contact] = []
    var withoutName: [Contact] = []
    var lackingInfo: [Contact] = []          // 有名字有号，但没有公司/标签/备注
    var invalidPhones: [(contact: Contact, number: String)] = []
    var duplicates: [DuplicateGroup] = []
    var neverContacted: [Contact] = []

    /// 0~100 的健康分。
    /// 每项问题按权重扣分，再用「人均可扣上限」归一化，避免联系人多就必然低分。
    var score: Int {
        guard total > 0 else { return 100 }

        let weighted = withoutPhone.count * 3
            + withoutName.count * 5
            + invalidPhones.count * 2
            + duplicates.count * 4
            + lackingInfo.count * 1

        let ceiling = max(total * 10, 10)
        let ratio = min(1.0, Double(weighted) / Double(ceiling))
        return max(0, min(100, Int((1.0 - ratio) * 100)))
    }

    var grade: String {
        switch score {
        case 90...: return "很干净"
        case 75..<90: return "还不错"
        case 55..<75: return "该整理了"
        default: return "有点乱"
        }
    }

    var gradeColor: Color {
        switch score {
        case 90...: return .green
        case 75..<90: return .blue
        case 55..<75: return .orange
        default: return .red
        }
    }
}

enum HealthChecker {

    static func examine(_ contacts: [Contact]) -> HealthReport {
        var report = HealthReport()
        report.total = contacts.count

        for c in contacts {
            // 没有可用号码
            let usablePhones = c.phones.filter { !DuplicateDetector.normalize($0.number).isEmpty }
            if usablePhones.isEmpty { report.withoutPhone.append(c) }

            // 没有姓名
            if c.displayName == "未命名联系人" { report.withoutName.append(c) }

            // 号码格式可疑
            for p in c.phones {
                let digits = DuplicateDetector.normalize(p.number)
                if !digits.isEmpty && (digits.count < 5 || digits.count > 15) {
                    report.invalidPhones.append((c, p.number))
                }
            }

            // 信息太单薄
            if c.displayName != "未命名联系人",
               !usablePhones.isEmpty,
               c.organization.isEmpty,
               c.tags.isEmpty,
               c.note.isEmpty {
                report.lackingInfo.append(c)
            }

            // 从没联系过
            if c.lastContactedAt == nil, !usablePhones.isEmpty {
                report.neverContacted.append(c)
            }
        }

        report.duplicates = DuplicateDetector.findDuplicates(in: contacts)
        return report
    }
}
