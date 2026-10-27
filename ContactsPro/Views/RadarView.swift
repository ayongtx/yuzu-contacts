import SwiftUI
import SwiftData
import UIKit

/// 雷达页：把「关系维护」这件事变成可看的数字。
/// 左边告诉你谁快过生日了，右边告诉你谁快要被忘记了。
struct RadarView: View {

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var settings: AppSettings

    @Query(filter: #Predicate<Contact> { $0.isInVault == false },
           sort: [SortDescriptor(\Contact.sortKey)])
    private var contacts: [Contact]

    @State private var wishTarget: Contact?
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            List {
                statsSection

                if !upcomingBirthdays.isEmpty {
                    birthdaySection
                }

                if !neglected.isEmpty {
                    neglectSection
                }

                if upcomingBirthdays.isEmpty && neglected.isEmpty {
                    Section {
                        EmptyStateView(
                            symbol: "sparkles",
                            title: "暂时没有要提醒的",
                            message: "给联系人填上生日、或者等一段时间没联系，这里就会出现提醒"
                        )
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("雷达")
            .sheet(item: $wishTarget) { contact in
                WishSheet(contact: contact)
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.78), in: Capsule())
                        .padding(.bottom, 20)
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: - 概览

    private var statsSection: some View {
        Section {
            HStack(spacing: 10) {
                StatTile(value: "\(contacts.count)", label: "联系人", tint: .blue, symbol: "person.2.fill")
                StatTile(value: "\(upcomingBirthdays.count)", label: "近期生日", tint: .pink, symbol: "gift.fill")
                StatTile(value: "\(neglected.count)", label: "待联系", tint: .orange, symbol: "clock.badge.exclamationmark")
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 10, trailing: 12))
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - 生日

    private var birthdaySection: some View {
        Section {
            ForEach(upcomingBirthdays) { contact in
                Button {
                    wishTarget = contact
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(contact: contact, size: 42)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(contact.displayName)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(birthdaySubtitle(contact))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text(daysText(contact))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(badgeColor(contact))
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button {
                        if let phone = contact.primaryPhone?.number {
                            sendSMS(to: phone, contact: contact)
                        }
                    } label: {
                        Label("发祝福", systemImage: "message.fill")
                    }
                    .tint(.green)
                }
            }
        } header: {
            Label("最近 60 天生日", systemImage: "gift")
        } footer: {
            Text("点一位，就能生成一段可以直接发出去的祝福文案。")
        }
    }

    private func birthdaySubtitle(_ contact: Contact) -> String {
        guard let next = contact.nextBirthday else { return "" }
        let md = next.formatted(.dateTime.month(.abbreviated).day())
        if !contact.subtitle.isEmpty {
            return "\(md) · \(contact.subtitle)"
        }
        return md
    }

    private func daysText(_ contact: Contact) -> String {
        guard let days = contact.daysUntilBirthday else { return "" }
        if days == 0 { return "今天生日" }
        if days == 1 { return "明天" }
        return "\(days) 天后"
    }

    private func badgeColor(_ contact: Contact) -> Color {
        guard let days = contact.daysUntilBirthday else { return .secondary }
        if days <= 3 { return .pink }
        if days <= 14 { return .orange }
        return .secondary
    }

    // MARK: - 冷落提醒

    private var neglectSection: some View {
        Section {
            ForEach(neglected) { contact in
                HStack(spacing: 12) {
                    AvatarView(contact: contact, size: 42)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(contact.displayName)
                            .font(.body)
                        Text(neglectText(contact))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Spacer()

                    Button {
                        if let phone = contact.primaryPhone?.number {
                            dial(phone, contact: contact)
                        }
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.green)
                            .frame(width: 34, height: 34)
                            .background(Color.green.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation {
                            contact.lastContactedAt = Date()
                            try? context.save()
                        }
                        showToast("已标记为今天联系过")
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.blue)
                            .frame(width: 34, height: 34)
                            .background(Color.blue.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Label("超过 \(settings.neglectDays) 天没联系", systemImage: "clock.badge.exclamationmark")
        } footer: {
            Text("在「更多 → 设置」里可以调这个天数。点 ✓ 表示你刚聊过，它就会暂时消失。")
        }
    }

    private func neglectText(_ contact: Contact) -> String {
        guard let days = contact.daysSinceLastContact else {
            return "从没记录过联系时间"
        }
        return "已经 \(days) 天没联系了"
    }

    // MARK: - 数据

    private var upcomingBirthdays: [Contact] {
        contacts
            .filter { ($0.daysUntilBirthday ?? 999) <= 60 }
            .sorted { ($0.daysUntilBirthday ?? 999) < ($1.daysUntilBirthday ?? 999) }
    }

    private var neglected: [Contact] {
        contacts
            .filter { contact in
                // 有生日且马上要到的，归到生日区，不重复提醒
                if let d = contact.daysUntilBirthday, d <= 7 { return false }
                guard let days = contact.daysSinceLastContact else { return false }
                return days >= settings.neglectDays
            }
            .sorted { ($0.daysSinceLastContact ?? 0) > ($1.daysSinceLastContact ?? 0) }
    }

    // MARK: - 动作

    private func dial(_ number: String, contact: Contact) {
        let cleaned = number.replacingOccurrences(of: " ", with: "")
        guard let url = URL(string: "tel://\(cleaned)") else { return }
        UIApplication.shared.open(url) { ok in
            if ok {
                contact.lastContactedAt = Date()
                try? context.save()
            }
        }
    }

    private func sendSMS(to number: String, contact: Contact) {
        let cleaned = number.replacingOccurrences(of: " ", with: "")
        guard let url = URL(string: "sms://\(cleaned)") else { return }
        UIApplication.shared.open(url) { ok in
            if ok {
                contact.lastContactedAt = Date()
                try? context.save()
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { toast = nil }
        }
    }
}

// MARK: - 祝福文案

enum WishStyle: String, CaseIterable, Identifiable {
    case warm = "温暖"
    case playful = "俏皮"
    case brief = "简短"
    case literary = "文艺"

    var id: String { rawValue }
}

enum WishGenerator {

    static func wish(for contact: Contact, style: WishStyle) -> String {
        let name = contact.nickname.isEmpty ? contact.displayName : contact.nickname

        switch style {
        case .warm:
            return """
            \(name)，生日快乐！

            又长一岁，愿你今年的日子比去年松快一点，想做的事都赶得上好时候。
            蛋糕记得吃，别光顾着许愿。
            """
        case .playful:
            return """
            \(name)！生日快乐 🎂

            祝你：钱包更鼓、头发更多、烦恼更少、体重更轻（最后一条我也没做到）。
            今天你是主角，随便任性。
            """
        case .brief:
            return "\(name)，生日快乐！愿你今年顺顺利利，想要的都如期而至。"
        case .literary:
            return """
            \(name)，生日快乐。

            愿你往后每一岁，都能被生活温柔相待；
            愿你走过的路，都算数。
            """
        }
    }
}

struct WishSheet: View {

    let contact: Contact

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var style: WishStyle = .warm
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        AvatarView(contact: contact, size: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(contact.displayName)
                                .font(.headline)
                            if let days = contact.daysUntilBirthday {
                                Text(days == 0 ? "今天生日" : "还有 \(days) 天")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    Picker("风格", selection: $style) {
                        ForEach(WishStyle.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(WishGenerator.wish(for: contact, style: style))
                        .font(.body)
                        .lineSpacing(5)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .animation(.easeInOut(duration: 0.15), value: style)

                    VStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = WishGenerator.wish(for: contact, style: style)
                            Haptics.success()
                            withAnimation { copied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { copied = false }
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                                Text(copied ? "已复制" : "复制文案")
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.white)
                        }

                        if let phone = contact.primaryPhone?.number {
                            Button {
                                let body = WishGenerator.wish(for: contact, style: style)
                                let cleaned = phone.replacingOccurrences(of: " ", with: "")
                                let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                if let url = URL(string: "sms://\(cleaned)&body=\(encoded)") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "message.fill")
                                    Text("直接发短信")
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color.green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(.white)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("生成祝福")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
