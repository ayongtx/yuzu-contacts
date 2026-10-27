import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct ContactEditView: View {

    enum Mode {
        case create
        case edit(Contact)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    // —— 草稿字段 ——
    @State private var givenName = ""
    @State private var familyName = ""
    @State private var nickname = ""
    @State private var organization = ""
    @State private var department = ""
    @State private var jobTitle = ""

    @State private var phones: [PhoneEntry] = [PhoneEntry()]
    @State private var emails: [EmailEntry] = []
    @State private var addresses: [AddressEntry] = []
    @State private var dates: [DateEntry] = []

    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var note = ""

    @State private var avatarData: Data?
    @State private var pickedPhoto: PhotosPickerItem?

    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                avatarSection
                nameSection
                orgSection
                phoneSection
                emailSection
                addressSection
                dateSection
                tagSection
                noteSection
            }
            .navigationTitle(isEditing ? "编辑联系人" : "新建联系人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    // MARK: - 各区块

    private var avatarSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        ZStack {
                            if let data = avatarData, let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 84, height: 84)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.12))
                                    .frame(width: 84, height: 84)
                                    .overlay {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 22))
                                            .foregroundStyle(Color.accentColor)
                                    }
                            }
                        }
                    }

                    if avatarData != nil {
                        Button("移除照片", role: .destructive) {
                            avatarData = nil
                            pickedPhoto = nil
                        }
                        .font(.caption)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let raw = try? await item.loadTransferable(type: Data.self) {
                    avatarData = Self.downscale(raw)
                }
            }
        }
    }

    private var nameSection: some View {
        Section("姓名") {
            HStack {
                Text("姓").foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                TextField("张", text: $familyName)
            }
            HStack {
                Text("名").foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                TextField("小明", text: $givenName)
            }
            HStack {
                Text("昵称").foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                TextField("选填", text: $nickname)
            }
        }
    }

    private var orgSection: some View {
        Section("公司") {
            TextField("公司 / 组织", text: $organization)
            TextField("部门", text: $department)
            TextField("职位", text: $jobTitle)
        }
    }

    private var phoneSection: some View {
        Section {
            ForEach($phones) { $entry in
                HStack(spacing: 8) {
                    Button {
                        setPrimary(entry.id)
                    } label: {
                        Image(systemName: entry.isPrimary ? "star.fill" : "star")
                            .font(.system(size: 14))
                            .foregroundStyle(entry.isPrimary ? Color.yellow : Color.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)

                    TextField("号码", text: $entry.number)
                        .keyboardType(.phonePad)

                    Picker("", selection: $entry.label) {
                        ForEach(PhoneLabelSet.all, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            .onDelete { offsets in
                phones.remove(atOffsets: offsets)
                ensurePrimary()
            }

            Button {
                phones.append(PhoneEntry(label: "其他"))
            } label: {
                Label("添加电话", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("电话")
        } footer: {
            Text("点左侧星标可设为主号，详情页顶部的「呼叫」按钮会拨这个号。")
        }
    }

    private var emailSection: some View {
        Section {
            ForEach($emails) { $entry in
                HStack(spacing: 8) {
                    TextField("邮箱地址", text: $entry.address)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Picker("", selection: $entry.label) {
                        ForEach(EmailLabelSet.all, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            .onDelete { emails.remove(atOffsets: $0) }

            Button {
                emails.append(EmailEntry())
            } label: {
                Label("添加邮箱", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("邮箱")
        }
    }

    private var addressSection: some View {
        Section {
            ForEach($addresses) { $entry in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("详细地址", text: $entry.text, axis: .vertical)
                        .lineLimit(1...3)

                    Picker("类型", selection: $entry.label) {
                        ForEach(AddressLabelSet.all, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 2)
            }
            .onDelete { addresses.remove(atOffsets: $0) }

            Button {
                addresses.append(AddressEntry())
            } label: {
                Label("添加地址", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("地址")
        }
    }

    private var dateSection: some View {
        Section {
            ForEach($dates) { $entry in
                VStack(alignment: .leading, spacing: 6) {
                    Picker("类型", selection: $entry.label) {
                        ForEach(DateLabelSet.all, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)

                    DatePicker("日期", selection: $entry.date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                }
                .padding(.vertical, 2)
            }
            .onDelete { dates.remove(atOffsets: $0) }

            Button {
                var entry = DateEntry()
                if !dates.contains(where: { $0.label == "生日" }) {
                    entry.label = "生日"
                }
                dates.append(entry)
            } label: {
                Label("添加纪念日", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("纪念日")
        } footer: {
            Text("填了生日，这个联系人就会出现在「雷达 → 生日」里，自动倒计时。")
        }
    }

    private var tagSection: some View {
        Section {
            if !tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag).font(.caption)
                            Button {
                                tags.removeAll { $0 == tag }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.vertical, 2)
            }

            HStack {
                TextField("新增标签，如 家人 / 同事", text: $newTag)
                    .submitLabel(.done)
                    .onSubmit(addTag)
                Button("添加", action: addTag)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("标签")
        } footer: {
            Text("标签可以用来分组、在「更多」里批量筛选，也会进入搜索范围。")
        }
    }

    private var noteSection: some View {
        Section("备注") {
            TextField("随便记点什么", text: $note, axis: .vertical)
                .lineLimit(3...8)
        }
    }

    // MARK: - 逻辑

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        let hasName = !givenName.trimmingCharacters(in: .whitespaces).isEmpty
            || !familyName.trimmingCharacters(in: .whitespaces).isEmpty
            || !nickname.trimmingCharacters(in: .whitespaces).isEmpty
            || !organization.trimmingCharacters(in: .whitespaces).isEmpty
        let hasPhone = phones.contains { !$0.number.trimmingCharacters(in: .whitespaces).isEmpty }
        return hasName || hasPhone
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true

        guard case .edit(let contact) = mode else { return }

        givenName = contact.givenName
        familyName = contact.familyName
        nickname = contact.nickname
        organization = contact.organization
        department = contact.department
        jobTitle = contact.jobTitle
        phones = contact.phones.isEmpty ? [PhoneEntry()] : contact.phones
        emails = contact.emails
        addresses = contact.addresses
        dates = contact.dates
        tags = contact.tags
        note = contact.note
        avatarData = contact.avatarData
    }

    private func setPrimary(_ id: UUID) {
        for i in phones.indices {
            phones[i].isPrimary = (phones[i].id == id)
        }
    }

    private func ensurePrimary() {
        guard !phones.isEmpty else { return }
        if !phones.contains(where: { $0.isPrimary }) {
            phones[0].isPrimary = true
        }
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else {
            newTag = ""
            return
        }
        withAnimation { tags.append(trimmed) }
        newTag = ""
    }

    private func save() {
        // 清掉空号码行
        let cleanedPhones = phones.filter { !$0.number.trimmingCharacters(in: .whitespaces).isEmpty }
        let cleanedEmails = emails.filter { !$0.address.trimmingCharacters(in: .whitespaces).isEmpty }
        let cleanedAddresses = addresses.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }

        let target: Contact
        switch mode {
        case .create:
            target = Contact()
            context.insert(target)
        case .edit(let contact):
            target = contact
        }

        target.givenName = givenName.trimmingCharacters(in: .whitespaces)
        target.familyName = familyName.trimmingCharacters(in: .whitespaces)
        target.nickname = nickname.trimmingCharacters(in: .whitespaces)
        target.organization = organization.trimmingCharacters(in: .whitespaces)
        target.department = department.trimmingCharacters(in: .whitespaces)
        target.jobTitle = jobTitle.trimmingCharacters(in: .whitespaces)
        target.phones = cleanedPhones
        target.emails = cleanedEmails
        target.addresses = cleanedAddresses
        target.dates = dates
        target.tags = tags
        target.note = note
        target.avatarData = avatarData

        if !target.phones.contains(where: { $0.isPrimary }), !target.phones.isEmpty {
            target.phones[0].isPrimary = true
        }

        target.refreshDerived()
        try? context.save()
        dismiss()
    }

    // MARK: - 图片压缩

    static func downscale(_ data: Data, maxEdge: CGFloat = 600) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge else {
            return image.jpegData(compressionQuality: 0.85)
        }
        let ratio = maxEdge / longest
        let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return scaled.jpegData(compressionQuality: 0.82)
    }
}
