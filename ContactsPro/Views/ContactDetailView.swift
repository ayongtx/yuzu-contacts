import SwiftUI
import SwiftData
import UIKit

struct ContactDetailView: View {

    @Bindable var contact: Contact

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    @State private var showingEdit = false
    @State private var showingQR = false
    @State private var showingDeleteConfirm = false
    @State private var toast: String?

    var body: some View {
        List {
            headerSection

            if !contact.phones.isEmpty { phoneSection }
            if !contact.emails.isEmpty { emailSection }
            if !contact.addresses.isEmpty { addressSection }
            if !contact.dates.isEmpty { dateSection }
            if !contact.tags.isEmpty { tagSection }
            if !contact.note.isEmpty { noteSection }

            metaSection
            dangerSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(contact.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            ContactEditView(mode: .edit(contact))
        }
        .sheet(isPresented: $showingQR) {
            ContactQRCodeView(contact: contact)
        }
        .confirmationDialog("确定删除这个联系人？", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteContact() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复。")
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.78), in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - 头部

    private var headerSection: some View {
        Section {
            VStack(spacing: 12) {
                AvatarView(contact: contact, size: 92)
                    .shadow(color: .black.opacity(0.10), radius: 10, y: 4)

                VStack(spacing: 4) {
                    Text(contact.displayName)
                        .font(.title2.weight(.semibold))

                    if !contact.subtitle.isEmpty {
                        Text(contact.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if !contact.nickname.isEmpty {
                        Text("昵称 · \(contact.nickname)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                // 快捷动作
                HStack(spacing: 10) {
                    if let phone = contact.primaryPhone {
                        quickAction("呼叫", "phone.fill", .green) {
                            dial(phone.digitsOnly)
                        }
                        quickAction("短信", "message.fill", .blue) {
                            sendSMS(to: phone.digitsOnly)
                        }
                    }
                    if let email = contact.emails.first?.address {
                        quickAction("邮件", "envelope.fill", .orange) {
                            sendEmail(to: email)
                        }
                    }
                    quickAction("二维码", "qrcode", .purple) {
                        showingQR = true
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private func quickAction(_ title: String, _ icon: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.13), in: Circle())

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 60)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 电话

    private var phoneSection: some View {
        Section("电话") {
            ForEach(contact.phones) { entry in
                Button {
                    dial(entry.digitsOnly)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: PhoneLabelSet.symbol(for: entry.label))
                            .font(.system(size: 15))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.number)
                                .font(.body)
                                .foregroundStyle(Color.accentColor)
                            Text(entry.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if entry.isPrimary {
                            Text("主号")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button {
                        UIPasteboard.general.string = entry.number
                        showToast("号码已复制")
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .tint(.gray)
                }
            }
        }
    }

    // MARK: - 邮箱

    private var emailSection: some View {
        Section("邮箱") {
            ForEach(contact.emails) { entry in
                Button {
                    sendEmail(to: entry.address)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "envelope")
                            .font(.system(size: 15))
                            .foregroundStyle(.orange)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.address)
                                .font(.subheadline)
                                .foregroundStyle(Color.accentColor)
                            Text(entry.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 地址

    private var addressSection: some View {
        Section("地址") {
            ForEach(contact.addresses) { entry in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 15))
                        .foregroundStyle(.red)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.text)
                            .font(.subheadline)
                        Text(entry.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = entry.text
                        showToast("地址已复制")
                    } label: {
                        Label("复制地址", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }

    // MARK: - 纪念日

    private var dateSection: some View {
        Section("纪念日") {
            ForEach(contact.dates) { entry in
                HStack(spacing: 12) {
                    Image(systemName: "gift")
                        .font(.system(size: 15))
                        .foregroundStyle(.pink)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.date.formatted(.dateTime.year().month().day()))
                            .font(.subheadline)
                        Text(entry.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if entry.label == "生日", let days = contact.daysUntilBirthday {
                        Text(days == 0 ? "今天" : "\(days) 天后")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(days <= 7 ? Color.pink : Color.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                (days <= 7 ? Color.pink : Color(.tertiarySystemFill)).opacity(0.14),
                                in: Capsule()
                            )
                    }
                }
            }
        }
    }

    // MARK: - 标签

    private var tagSection: some View {
        Section("标签") {
            FlowLayout(spacing: 8) {
                ForEach(contact.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 备注

    private var noteSection: some View {
        Section("备注") {
            Text(contact.note)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 元信息

    private var metaSection: some View {
        Section {
            HStack {
                Label("最近联系", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline)
                Spacer()
                Text(lastContactText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("创建时间", systemImage: "calendar")
                    .font(.subheadline)
                Spacer()
                Text(contact.createdAt.formatted(.dateTime.year().month().day()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                withAnimation {
                    contact.lastContactedAt = Date()
                    try? context.save()
                }
                showToast("已记录本次联系")
            } label: {
                Label("标记为「刚刚联系过」", systemImage: "checkmark.circle")
                    .font(.subheadline)
            }

            Button {
                withAnimation {
                    contact.isInVault.toggle()
                    try? context.save()
                }
                showToast(contact.isInVault ? "已移入保险箱" : "已移出保险箱")
                if contact.isInVault { DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { dismiss() } }
            } label: {
                Label(contact.isInVault ? "移出隐私保险箱" : "移入隐私保险箱",
                      systemImage: contact.isInVault ? "lock.open" : "lock.shield")
                    .font(.subheadline)
            }
        }
    }

    // MARK: - 危险操作

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("删除联系人", systemImage: "trash")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - 辅助

    private var lastContactText: String {
        guard let days = contact.daysSinceLastContact else { return "从未记录" }
        if days == 0 { return "今天" }
        if days == 1 { return "昨天" }
        return "\(days) 天前"
    }

    private func dial(_ number: String) {
        guard !number.isEmpty else { return }
        let cleaned = number.replacingOccurrences(of: " ", with: "")
        guard let url = URL(string: "tel://\(cleaned)") else { return }

        UIApplication.shared.open(url) { ok in
            if ok {
                contact.lastContactedAt = Date()
                try? context.save()
            }
        }
    }

    private func sendSMS(to number: String) {
        let cleaned = number.replacingOccurrences(of: " ", with: "")
        guard let url = URL(string: "sms://\(cleaned)") else { return }
        UIApplication.shared.open(url) { ok in
            if ok {
                contact.lastContactedAt = Date()
                try? context.save()
            }
        }
    }

    private func sendEmail(to address: String) {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "mailto:\(encoded)") else { return }
        UIApplication.shared.open(url)
    }

    private func deleteContact() {
        context.delete(contact)
        try? context.save()
        dismiss()
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { toast = nil }
        }
    }
}

// MARK: - 简易流式布局（标签用）

struct FlowLayout: Layout {

    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth == .infinity ? rowWidth : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
