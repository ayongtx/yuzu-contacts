import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MoreView: View {

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var security: SecurityService

    @Query(filter: #Predicate<Contact> { $0.isInVault == false })
    private var contacts: [Contact]

    @Query(filter: #Predicate<Contact> { $0.isInVault == true })
    private var vaultContacts: [Contact]

    @State private var showingImporter = false
    @State private var showingSystemImportConfirm = false
    @State private var isImporting = false
    @State private var importResult: String?
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        MyCardView()
                    } label: {
                        Label("我的名片", systemImage: "person.text.rectangle")
                    }

                    NavigationLink {
                        HealthView()
                    } label: {
                        Label("通讯录体检", systemImage: "stethoscope")
                    }

                    NavigationLink {
                        DuplicateMergeView()
                    } label: {
                        Label("合并重复联系人", systemImage: "rectangle.on.rectangle")
                    }
                } header: {
                    Text("工具")
                }

                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("导出备份（.vcf）", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            prepareExport()
                        } label: {
                            Label("导出备份（.vcf）", systemImage: "square.and.arrow.up")
                        }
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        Label("从 .vcf 文件导入", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        showingSystemImportConfirm = true
                    } label: {
                        HStack {
                            Label("从系统通讯录导入", systemImage: "person.crop.circle.badge.plus")
                            Spacer()
                            if isImporting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isImporting)
                } header: {
                    Text("备份与导入")
                } footer: {
                    Text("导出的 .vcf 可以用 iOS 自带的「通讯录」、电脑上的 Outlook 或 Google 通讯录直接打开。")
                }

                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }

                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("关于", systemImage: "info.circle")
                    }
                }

                Section {
                    HStack {
                        Text("主通讯录")
                        Spacer()
                        Text("\(contacts.count) 位")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("保险箱")
                        Spacer()
                        Text("\(vaultContacts.count) 位")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("统计")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("更多")
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [UTType(filenameExtension: "vcf") ?? .data, .text],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .confirmationDialog("从系统通讯录导入？", isPresented: $showingSystemImportConfirm, titleVisibility: .visible) {
                Button("开始导入") { importFromSystem() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("会请求访问系统通讯录的权限。导入后数据只存在本机，不会上传。重复的联系人不会自动合并，导入后可以到「合并重复联系人」里处理。")
            }
            .alert("导入结果", isPresented: Binding(
                get: { importResult != nil },
                set: { if !$0 { importResult = nil } }
            )) {
                Button("好") { importResult = nil }
            } message: {
                Text(importResult ?? "")
            }
        }
    }

    // MARK: - 导出

    private func prepareExport() {
        let all = contacts
        guard !all.isEmpty else {
            importResult = "通讯录是空的，没有可导出的内容。"
            return
        }

        let text = VCardService.make(contacts: all)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let name = "ContactsBackup-\(formatter.string(from: Date())).vcf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            Haptics.success()
        } catch {
            importResult = "导出失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 从 vcf 导入

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importResult = "读取文件失败：\(error.localizedDescription)"

        case .success(let urls):
            guard let url = urls.first else { return }

            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
                    importResult = "这个文件的编码读不出来，试试另存为 UTF-8 再导入。"
                    return
                }

                let parsed = VCardService.parse(text)
                guard !parsed.isEmpty else {
                    importResult = "文件里没有找到可识别的联系人。"
                    return
                }

                for p in parsed {
                    context.insert(p.toContact())
                }
                try? context.save()
                Haptics.success()
                importResult = "成功导入 \(parsed.count) 位联系人。"

            } catch {
                importResult = "导入失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - 从系统通讯录导入

    private func importFromSystem() {
        isImporting = true

        Task {
            let granted = await SystemContactsImporter.requestAccess()

            guard granted else {
                await MainActor.run {
                    isImporting = false
                    importResult = "没有拿到通讯录权限。请到「设置 → 隐私与安全性 → 通讯录」里打开本应用的开关后重试。"
                }
                return
            }

            let fetched = await SystemContactsImporter.fetchAll()

            await MainActor.run {
                guard !fetched.isEmpty else {
                    isImporting = false
                    importResult = "系统通讯录里没有读到联系人。"
                    return
                }

                for p in fetched {
                    context.insert(p.toContact())
                }
                try? context.save()
                isImporting = false
                Haptics.success()
                importResult = "成功导入 \(fetched.count) 位联系人。建议接着去「合并重复联系人」检查一下。"
            }
        }
    }
}

// MARK: - 关于

struct AboutView: View {

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.62)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 92, height: 92)

                        Image(systemName: "person.2.crop.square.stack.fill")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(.white)
                    }

                    Text("柚柚通讯录")
                        .font(.title2.weight(.semibold))

                    Text("版本 \(version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 14) {
                    infoRow("数据存放", "全部保存在本机沙盒内，不上传服务器，不需要登录，不联网也能用。")
                    infoRow("隐私", "保险箱中的联系人不会出现在主列表、搜索结果、九宫格和雷达里；退出 App 自动上锁。")
                    infoRow("自签说明", "这是个人自签应用，证书有效期通常 7 天，到期需要重新签名，但数据不会丢。")
                    infoRow("导入导出", "支持标准 vCard（.vcf），可以和 iOS 通讯录、Outlook、Google 通讯录互通。")
                }
                .padding(18)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 20)

                Text("层楼工作室 · Cenglou Studio")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoRow(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
