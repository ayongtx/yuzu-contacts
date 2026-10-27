import SwiftUI
import SwiftData
import UIKit

/// T9 拨号盘。
/// 输入数字即可按拼音定位联系人：726 → san（三），94264 → zhang（张），97 → zs（张三首字母）。
struct T9KeypadView: View {

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var settings: AppSettings

    @Query(filter: #Predicate<Contact> { $0.isInVault == false })
    private var contacts: [Contact]

    @State private var input = ""
    @State private var toast: String?

    private let maxDigits = 20

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                resultArea
                    .frame(maxHeight: .infinity)

                inputBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                keypad
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("九宫格")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !input.isEmpty {
                        Button("清空") { clearInput() }
                    }
                }
            }
            .overlay(alignment: .top) {
                if let toast {
                    Text(toast)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.78), in: Capsule())
                        .padding(.top, 8)
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: - 候选区

    private var resultArea: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if input.isEmpty {
                    emptyHint
                    recentSection
                } else if matches.isEmpty {
                    noMatchSection
                } else {
                    matchList
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
        .scrollDismissesKeyboard(.never)
    }

    private var emptyHint: some View {
        VStack(spacing: 5) {
            Text("按数字找联系人")
                .font(.subheadline.weight(.medium))
            Text("94264 → 张　·　726 → 三　·　97 → 张三首字母")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !quickContacts.isEmpty {
                Text("常用与最近")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)

                VStack(spacing: 0) {
                    ForEach(quickContacts) { contact in
                        resultRow(contact)
                        if contact.id != quickContacts.last?.id {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.bottom, 20)
    }

    private var matchList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(matches.count) 个匹配")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(matches) { contact in
                    resultRow(contact)
                    if contact.id != matches.last?.id {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var noMatchSection: some View {
        VStack(spacing: 12) {
            Text("没有匹配的联系人")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 20)

            if input.count >= 3 {
                Button {
                    dialDirect(input)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "phone.fill")
                        Text("直接拨打 \(input)")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func resultRow(_ contact: Contact) -> some View {
        Button {
            if let phone = bestPhone(for: contact) {
                dial(phone, contact: contact)
            }
        } label: {
            HStack(spacing: 12) {
                AvatarView(contact: contact, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let phone = bestPhone(for: contact) {
                        Text(phone)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "phone.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                    .frame(width: 32, height: 32)
                    .background(Color.green.opacity(0.12), in: Circle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                if let phone = bestPhone(for: contact) {
                    UIPasteboard.general.string = phone
                    showToast("号码已复制")
                }
            } label: {
                Label("复制号码", systemImage: "doc.on.doc")
            }
            Button {
                if let phone = bestPhone(for: contact) {
                    sendSMS(to: phone, contact: contact)
                }
            } label: {
                Label("发短信", systemImage: "message")
            }
        }
    }

    // MARK: - 输入显示条

    private var inputBar: some View {
        HStack(spacing: 12) {
            Text(input.isEmpty ? "输入数字" : input)
                .font(.system(size: 30, weight: .light, design: .rounded))
                .foregroundStyle(input.isEmpty ? Color.secondary.opacity(0.4) : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !input.isEmpty {
                Button {
                    Haptics.tap()
                    input.removeLast()
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.6).onEnded { _ in clearInput() }
                )
            }

            Button {
                Haptics.impact()
                if let first = matches.first, let phone = bestPhone(for: first) {
                    dial(phone, contact: first)
                } else if input.count >= 3 {
                    dialDirect(input)
                }
            } label: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        (input.isEmpty && matches.isEmpty) ? Color.green.opacity(0.35) : Color.green,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .disabled(input.isEmpty && matches.isEmpty)
        }
        .padding(.horizontal, 6)
    }

    // MARK: - 键盘

    private var keypad: some View {
        VStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 18) {
                    ForEach(keys(for: row), id: \.digit) { key in
                        keyButton(key)
                    }
                }
            }
        }
    }

    private func keys(for row: Int) -> [(digit: String, letters: String)] {
        switch row {
        case 0:
            return [("1", ""), T9Engine.keyHints[0], T9Engine.keyHints[1]]
        case 1:
            return [T9Engine.keyHints[2], T9Engine.keyHints[3], T9Engine.keyHints[4]]
        case 2:
            return [T9Engine.keyHints[5], T9Engine.keyHints[6], T9Engine.keyHints[7]]
        default:
            return [("*", ""), ("0", "+"), ("#", "")]
        }
    }

    private func keyButton(_ key: (digit: String, letters: String)) -> some View {
        Button {
            Haptics.tap()
            guard input.count < maxDigits else { return }
            input.append(key.digit)
        } label: {
            VStack(spacing: 1) {
                Text(key.digit)
                    .font(.system(size: 27, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary)
                if !key.letters.isEmpty {
                    Text(key.letters)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)
                }
            }
            .frame(width: 72, height: 58)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(KeyButtonStyle())
    }

    // MARK: - 数据

    private var matches: [Contact] {
        guard !input.isEmpty else { return [] }
        return contacts
            .filter { T9Engine.matches(keys: $0.t9Keys, input: input) }
            .sorted { a, b in
                let sa = T9Engine.score(keys: a.t9Keys, input: input)
                let sb = T9Engine.score(keys: b.t9Keys, input: input)
                if sa != sb { return sa < sb }
                return a.sortKey < b.sortKey
            }
    }

    private var quickContacts: [Contact] {
        contacts
            .sorted { a, b in
                if a.isFavorite != b.isFavorite { return a.isFavorite }
                let da = a.lastContactedAt ?? .distantPast
                let db = b.lastContactedAt ?? .distantPast
                return da > db
            }
            .prefix(6)
            .map { $0 }
    }

    private func bestPhone(for contact: Contact) -> String? {
        contact.primaryPhone?.number
    }

    // MARK: - 动作

    private func clearInput() {
        Haptics.impact()
        input = ""
    }

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

    private func dialDirect(_ digits: String) {
        guard let url = URL(string: "tel://\(digits)") else { return }
        UIApplication.shared.open(url)
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

// MARK: - 触感与按键样式

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func impact() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

struct KeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
