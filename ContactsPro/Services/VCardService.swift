import Foundation
import Contacts
import UIKit

// MARK: - vCard 生成与解析

enum VCardService {

    // —— 转义 ——
    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func unescape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static let phoneTypeMap: [String: String] = [
        "手机": "CELL", "住宅": "HOME", "工作": "WORK",
        "学校": "WORK", "传真": "FAX", "主要": "CELL", "其他": "VOICE"
    ]

    private static let emailTypeMap: [String: String] = [
        "个人": "INTERNET", "工作": "INTERNET", "学校": "INTERNET", "其他": "INTERNET"
    ]

    private static let addrTypeMap: [String: String] = [
        "住宅": "HOME", "工作": "WORK", "学校": "OTHER", "其他": "OTHER"
    ]

    /// 单个联系人 → vCard 3.0
    static func make(contact: Contact) -> String {
        var lines: [String] = ["BEGIN:VCARD", "VERSION:3.0"]

        let family = escape(contact.familyName)
        let given = escape(contact.givenName)
        lines.append("N:\(family);\(given);;;")
        lines.append("FN:\(escape(contact.displayName))")

        if !contact.nickname.isEmpty {
            lines.append("NICKNAME:\(escape(contact.nickname))")
        }
        if !contact.organization.isEmpty || !contact.department.isEmpty {
            lines.append("ORG:\(escape(contact.organization));\(escape(contact.department))")
        }
        if !contact.jobTitle.isEmpty {
            lines.append("TITLE:\(escape(contact.jobTitle))")
        }
        for p in contact.phones where !p.number.isEmpty {
            let type = phoneTypeMap[p.label] ?? "VOICE"
            lines.append("TEL;TYPE=\(type):\(escape(p.number))")
        }
        for e in contact.emails where !e.address.isEmpty {
            let type = emailTypeMap[e.label] ?? "INTERNET"
            lines.append("EMAIL;TYPE=\(type):\(escape(e.address))")
        }
        for a in contact.addresses where !a.text.isEmpty {
            let type = addrTypeMap[a.label] ?? "HOME"
            lines.append("ADR;TYPE=\(type):;;\(escape(a.text));;;;")
        }
        for d in contact.dates where d.label == "生日" {
            let comps = Calendar.current.dateComponents([.year, .month, .day], from: d.date)
            if let y = comps.year, let m = comps.month, let day = comps.day {
                lines.append(String(format: "BDAY:%04d-%02d-%02d", y, m, day))
            }
        }
        if !contact.note.isEmpty {
            lines.append("NOTE:\(escape(contact.note))")
        }
        if !contact.tags.isEmpty {
            lines.append("CATEGORIES:\(contact.tags.map(escape).joined(separator: ","))")
        }
        lines.append("REV:\(ISO8601DateFormatter().string(from: contact.updatedAt))")
        lines.append("END:VCARD")

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// 多个联系人 → 一个 .vcf 文件内容
    static func make(contacts: [Contact]) -> String {
        contacts.map { make(contact: $0) }.joined()
    }

    /// 把 vCard 文本解析成可导入的草稿
    static func parse(_ text: String) -> [ParsedContact] {
        // 处理折行：以空格/制表符开头的续行要拼回上一行
        var unfolded: [String] = []
        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix(" ") || line.hasPrefix("\t"), !unfolded.isEmpty {
                unfolded[unfolded.count - 1] += line.dropFirst()
            } else {
                unfolded.append(line)
            }
        }

        var results: [ParsedContact] = []
        var current: ParsedContact?

        for line in unfolded {
            let upper = line.uppercased()

            if upper.hasPrefix("BEGIN:VCARD") {
                current = ParsedContact()
                continue
            }
            if upper.hasPrefix("END:VCARD") {
                if let c = current, c.hasContent { results.append(c) }
                current = nil
                continue
            }
            guard current != nil else { continue }

            // 拆出 key 和 value（value 里可能有冒号，只拆第一个）
            guard let colon = line.firstIndex(of: ":") else { continue }
            let keyPart = String(line[line.startIndex..<colon])
            let value = unescape(String(line[line.index(after: colon)...]))
            let keyName = keyPart.split(separator: ";").first.map(String.init)?.uppercased() ?? ""

            switch keyName {
            case "N":
                let parts = value.components(separatedBy: ";")
                if parts.count > 0 { current?.familyName = parts[0] }
                if parts.count > 1 { current?.givenName = parts[1] }

            case "FN":
                if current?.familyName.isEmpty == true && current?.givenName.isEmpty == true {
                    // 没有 N 字段时退而用 FN
                    current?.givenName = value
                }

            case "NICKNAME":
                current?.nickname = value

            case "ORG":
                let parts = value.components(separatedBy: ";")
                current?.organization = parts.first ?? ""
                if parts.count > 1 { current?.department = parts[1] }

            case "TITLE":
                current?.jobTitle = value

            case "TEL":
                let label = labelFromType(keyPart, fallback: "手机")
                current?.phones.append(PhoneEntry(label: label, number: value))

            case "EMAIL":
                current?.emails.append(EmailEntry(label: "个人", address: value))

            case "ADR":
                let parts = value.components(separatedBy: ";")
                let joined = parts.filter { !$0.isEmpty }.joined(separator: " ")
                if !joined.isEmpty {
                    current?.addresses.append(AddressEntry(label: "住宅", text: joined))
                }

            case "BDAY":
                if let date = parseDate(value) {
                    var entry = DateEntry()
                    entry.label = "生日"
                    entry.date = date
                    current?.dates.append(entry)
                }

            case "NOTE":
                current?.note = value

            case "CATEGORIES":
                current?.tags = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

            default:
                break
            }
        }

        return results
    }

    private static func labelFromType(_ keyPart: String, fallback: String) -> String {
        let upper = keyPart.uppercased()
        if upper.contains("FAX") { return "传真" }
        if upper.contains("CELL") { return "手机" }
        if upper.contains("WORK") { return "工作" }
        if upper.contains("HOME") { return "住宅" }
        return fallback
    }

    private static func parseDate(_ text: String) -> Date? {
        let formats = ["yyyy-MM-dd", "yyyyMMdd", "yyyy-MM", "--MM-dd", "MM-dd"]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for f in formats {
            df.dateFormat = f
            if let d = df.date(from: text) { return d }
        }
        // 处理 --MM-dd 这种只有月日的
        if text.hasPrefix("--"), text.count >= 6 {
            let md = String(text.dropFirst(2))
            let parts = md.split(separator: "-")
            if parts.count == 2, let m = Int(parts[0]), let d = Int(parts[1]) {
                var comps = DateComponents()
                comps.year = 2000
                comps.month = m
                comps.day = d
                return Calendar.current.date(from: comps)
            }
        }
        return nil
    }
}

/// vCard 解析出来的中间产物
struct ParsedContact {
    var givenName = ""
    var familyName = ""
    var nickname = ""
    var organization = ""
    var department = ""
    var jobTitle = ""
    var phones: [PhoneEntry] = []
    var emails: [EmailEntry] = []
    var addresses: [AddressEntry] = []
    var dates: [DateEntry] = []
    var note = ""
    var tags: [String] = []

    var hasContent: Bool {
        !givenName.isEmpty || !familyName.isEmpty || !phones.isEmpty
    }

    func toContact() -> Contact {
        let c = Contact()
        c.givenName = givenName
        c.familyName = familyName
        c.nickname = nickname
        c.organization = organization
        c.department = department
        c.jobTitle = jobTitle
        c.phones = phones
        c.emails = emails
        c.addresses = addresses
        c.dates = dates
        c.note = note
        c.tags = tags.filter { !$0.isEmpty }
        if !c.phones.isEmpty { c.phones[0].isPrimary = true }
        c.refreshDerived()
        return c
    }
}

// MARK: - 从系统通讯录读取

enum SystemContactsImporter {

    /// 请求通讯录权限
    static func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            CNContactStore().requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    /// 拉取全部联系人（在后台线程完成，避免卡界面）
    static func fetchAll() async -> [ParsedContact] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let store = CNContactStore()
                let keys: [CNKeyDescriptor] = [
                    CNContactGivenNameKey as CNKeyDescriptor,
                    CNContactFamilyNameKey as CNKeyDescriptor,
                    CNContactNicknameKey as CNKeyDescriptor,
                    CNContactOrganizationNameKey as CNKeyDescriptor,
                    CNContactDepartmentNameKey as CNKeyDescriptor,
                    CNContactJobTitleKey as CNKeyDescriptor,
                    CNContactPhoneNumbersKey as CNKeyDescriptor,
                    CNContactEmailAddressesKey as CNKeyDescriptor,
                    CNContactPostalAddressesKey as CNKeyDescriptor,
                    CNContactBirthdayKey as CNKeyDescriptor,
                    CNContactNoteKey as CNKeyDescriptor
                ]

                var results: [ParsedContact] = []
                let request = CNContactFetchRequest(keysToFetch: keys)
                request.sortOrder = .givenName

                do {
                    try store.enumerateContacts(with: request) { cn, _ in
                        var p = ParsedContact()
                        p.givenName = cn.givenName
                        p.familyName = cn.familyName
                        p.nickname = cn.nickname
                        p.organization = cn.organizationName
                        p.department = cn.departmentName
                        p.jobTitle = cn.jobTitle
                        p.note = cn.note

                        p.phones = cn.phoneNumbers.map { item in
                            let raw = item.value.stringValue
                            let label = cnLabel(item.label)
                            return PhoneEntry(label: label, number: raw)
                        }

                        p.emails = cn.emailAddresses.map { item in
                            EmailEntry(label: cnLabel(item.label) == "工作" ? "工作" : "个人",
                                       address: item.value as String)
                        }

                        p.addresses = cn.postalAddresses.map { item in
                            let a = item.value
                            // CNPostalAddress 的省/州字段是 state（没有 province）
                            let text = [a.state, a.city, a.subLocality, a.street, a.postalCode]
                                .filter { !$0.isEmpty }
                                .joined(separator: " ")
                            return AddressEntry(label: cnLabel(item.label), text: text)
                        }

                        if let bday = cn.birthday,
                           let date = Calendar.current.date(from: bday) {
                            var entry = DateEntry()
                            entry.label = "生日"
                            entry.date = date
                            p.dates.append(entry)
                        }

                        if p.hasContent { results.append(p) }
                    }
                } catch {
                    // 解析失败就返回已拿到的
                }

                continuation.resume(returning: results)
            }
        }
    }

    private static func cnLabel(_ label: String?) -> String {
        guard let label else { return "其他" }
        switch label {
        case CNLabelPhoneNumberMobile: return "手机"
        case CNLabelPhoneNumberMain: return "主要"
        case CNLabelPhoneNumberWorkFax, CNLabelPhoneNumberHomeFax, CNLabelPhoneNumberOtherFax: return "传真"
        case CNLabelHome: return "住宅"
        case CNLabelWork: return "工作"
        case CNLabelSchool: return "学校"
        default: return "其他"
        }
    }
}
