import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import SwiftData

// MARK: - 二维码生成

enum QRCodeGenerator {

    /// 把文本渲染成二维码图片。scale 越大越清晰，打印用 12~15，屏幕用 8~10。
    static func image(from text: String, scale: CGFloat = 10) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// 生成供扫码保存的 vCard 文本。
    /// 刻意做得精简：二维码容量有限，字段太多会扫不出来。
    static func vCardText(for contact: Contact) -> String {
        var lines = ["BEGIN:VCARD", "VERSION:3.0"]
        lines.append("N:\(contact.familyName);\(contact.givenName);;;")
        lines.append("FN:\(contact.displayName)")
        if !contact.organization.isEmpty {
            lines.append("ORG:\(contact.organization)")
        }
        if !contact.jobTitle.isEmpty {
            lines.append("TITLE:\(contact.jobTitle)")
        }
        // 最多带两个号码，控制体积
        for p in contact.phones.prefix(2) where !p.number.isEmpty {
            lines.append("TEL;TYPE=CELL:\(p.number)")
        }
        if let email = contact.emails.first?.address, !email.isEmpty {
            lines.append("EMAIL:\(email)")
        }
        lines.append("END:VCARD")
        return lines.joined(separator: "\n")
    }
}

// MARK: - 二维码展示组件

struct QRCodeCard: View {

    let contact: Contact
    var scale: CGFloat = 10

    @Environment(\.colorScheme) private var colorScheme

    private var payload: String {
        QRCodeGenerator.vCardText(for: contact)
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white)
                    .frame(width: 240, height: 240)

                if let image = QRCodeGenerator.image(from: payload, scale: scale) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 208, height: 208)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                        Text("信息太多，装不进二维码")
                            .font(.caption)
                        Text("试着删掉几个电话号码")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.gray)
                }
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.10), radius: 16, y: 6)

            VStack(spacing: 3) {
                Text(contact.displayName)
                    .font(.headline)
                if !contact.subtitle.isEmpty {
                    Text(contact.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("让对方用相机扫一下，就能把名片存进通讯录")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - 联系人二维码弹窗

struct ContactQRCodeView: View {

    let contact: Contact

    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    QRCodeCard(contact: contact)
                        .padding(.top, 16)

                    HStack(spacing: 12) {
                        Button {
                            if let image = QRCodeGenerator.image(from: QRCodeGenerator.vCardText(for: contact), scale: 12) {
                                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                                Haptics.success()
                            }
                        } label: {
                            Label("保存到相册", systemImage: "square.and.arrow.down")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        ShareLink(item: QRCodeGenerator.vCardText(for: contact)) {
                            Label("分享名片", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.accentColor,
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(20)
            }
            .navigationTitle("名片二维码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - 我的名片

struct MyCardView: View {

    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<Contact> { $0.isInVault == false },
           sort: [SortDescriptor(\Contact.sortKey)])
    private var contacts: [Contact]

    @AppStorage("cp.myContactID") private var myContactID: String = ""

    @State private var showingPicker = false

    private var myContact: Contact? {
        guard !myContactID.isEmpty,
              let uuid = UUID(uuidString: myContactID) else { return nil }
        return contacts.first { $0.id == uuid }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let contact = myContact {
                    QRCodeCard(contact: contact, scale: 11)
                        .padding(.top, 16)

                    HStack(spacing: 12) {
                        Button {
                            if let image = QRCodeGenerator.image(from: QRCodeGenerator.vCardText(for: contact), scale: 12) {
                                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                                Haptics.success()
                            }
                        } label: {
                            Label("存到相册", systemImage: "square.and.arrow.down")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Button {
                            showingPicker = true
                        } label: {
                            Label("换一个", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.accentColor,
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 4)
                } else {
                    EmptyStateView(
                        symbol: "person.crop.square.badge.camera",
                        title: "还没选「自己」",
                        message: "从通讯录里挑一位作为你的名片，\n之后就能把自己的二维码递出去了",
                        actionTitle: "选择联系人",
                        action: { showingPicker = true }
                    )
                    .padding(.top, 40)
                }
            }
            .padding(20)
        }
        .navigationTitle("我的名片")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPicker) {
            NavigationStack {
                List(contacts) { contact in
                    Button {
                        myContactID = contact.id.uuidString
                        showingPicker = false
                    } label: {
                        HStack {
                            ContactRow(contact: contact)
                            if contact.id.uuidString == myContactID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .navigationTitle("选你自己")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showingPicker = false }
                    }
                }
            }
        }
    }
}
