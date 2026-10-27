import SwiftUI
import SwiftData

struct HealthView: View {

    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<Contact> { $0.isInVault == false },
           sort: [SortDescriptor(\Contact.sortKey)])
    private var contacts: [Contact]

    @State private var toast: String?

    private var report: HealthReport {
        HealthChecker.examine(contacts)
    }

    var body: some View {
        List {
            scoreSection
            problemsSection

            if report.duplicates.isEmpty && report.withoutPhone.isEmpty && report.withoutName.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("没发现问题")
                                .font(.subheadline.weight(.medium))
                            Text("通讯录很干净，继续保持")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("通讯录体检")
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - 评分卡

    private var scoreSection: some View {
        Section {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color(.tertiarySystemFill), lineWidth: 12)
                        .frame(width: 132, height: 132)

                    Circle()
                        .trim(from: 0, to: CGFloat(report.score) / 100)
                        .stroke(report.gradeColor,
                                style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 132, height: 132)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: report.score)

                    VStack(spacing: 2) {
                        Text("\(report.score)")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(report.gradeColor)
                            .contentTransition(.numericText())
                        Text("健康分")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 3) {
                    Text(report.grade)
                        .font(.headline)
                    Text("共 \(report.total) 位联系人")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    // MARK: - 问题清单

    private var problemsSection: some View {
        Section {
            if !report.duplicates.isEmpty {
                NavigationLink {
                    DuplicateMergeView()
                } label: {
                    problemRow(
                        icon: "rectangle.on.rectangle",
                        tint: .purple,
                        title: "有 \(report.duplicates.count) 组疑似重复",
                        detail: "号码或姓名撞了，可以一键合并"
                    )
                }
            }

            if !report.withoutPhone.isEmpty {
                NavigationLink {
                    ProblemListSheet(title: "没有号码", contacts: report.withoutPhone, hint: "这些联系人没有可用电话，找起来只能靠名字")
                } label: {
                    problemRow(
                        icon: "phone.down",
                        tint: .orange,
                        title: "\(report.withoutPhone.count) 位没有号码",
                        detail: "补上号码才能真正联系到人"
                    )
                }
            }

            if !report.withoutName.isEmpty {
                NavigationLink {
                    ProblemListSheet(title: "没有姓名", contacts: report.withoutName, hint: "只有号码没有名字，时间久了就不知道是谁了")
                } label: {
                    problemRow(
                        icon: "questionmark.circle",
                        tint: .red,
                        title: "\(report.withoutName.count) 位没有姓名",
                        detail: "只有号码，认不出是谁"
                    )
                }
            }

            if !report.invalidPhones.isEmpty {
                NavigationLink {
                    InvalidPhoneList(items: report.invalidPhones)
                } label: {
                    problemRow(
                        icon: "exclamationmark.triangle",
                        tint: .yellow,
                        title: "\(report.invalidPhones.count) 个号码格式可疑",
                        detail: "位数不对，可能拨不通"
                    )
                }
            }

            if !report.lackingInfo.isEmpty {
                NavigationLink {
                    ProblemListSheet(title: "信息太单薄", contacts: report.lackingInfo, hint: "只有名字和号码，没有公司、标签或备注")
                } label: {
                    problemRow(
                        icon: "text.alignleft",
                        tint: .blue,
                        title: "\(report.lackingInfo.count) 位信息太少",
                        detail: "补个标签，以后更好找"
                    )
                }
            }

            NavigationLink {
                ProblemListSheet(title: "从未联系", contacts: report.neverContacted, hint: "这些联系人一次都没记录过联系时间")
            } label: {
                problemRow(
                    icon: "clock.badge.questionmark",
                    tint: .gray,
                    title: "\(report.neverContacted.count) 位从未联系",
                    detail: "存了号码却一次没打过"
                )
            }
        } header: {
            Text("需要处理的")
        } footer: {
            Text("点任意一项可以查看详情并逐个修复。体检只统计主通讯录，不含保险箱。")
        }
    }

    private func problemRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 重复联系人合并

struct DuplicateMergeView: View {

    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<Contact> { $0.isInVault == false },
           sort: [SortDescriptor(\Contact.sortKey)])
    private var contacts: [Contact]

    @State private var mergingGroup: DuplicateGroup?
    @State private var toast: String?

    private var groups: [DuplicateGroup] {
        DuplicateDetector.findDuplicates(in: contacts)
    }

    var body: some View {
        List {
            if groups.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        Text("没有重复联系人了")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.vertical, 6)
                }
            } else {
                Section {
                    ForEach(groups) { group in
                        groupCard(group)
                    }
                } header: {
                    Text("\(groups.count) 组")
                } footer: {
                    Text("合并时会保留信息最完整的那一位，其余联系人的电话、邮箱、地址、标签、备注会并进去。")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("合并重复")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.78), in: Capsule())
                    .padding(.bottom, 20)
            }
        }
    }

    private func groupCard(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(group.displayName)
                    .font(.subheadline.weight(.semibold))
                ForEach(group.reasons, id: \.self) { reason in
                    Text(reason)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text("\(group.contacts.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(group.contacts) { contact in
                HStack(spacing: 10) {
                    AvatarView(contact: contact, size: 30)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(contact.displayName)
                            .font(.caption)
                        Text(detailLine(contact))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if contact.id == group.keeper?.id {
                        Text("保留")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.13), in: Capsule())
                    } else {
                        Text("并入")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                mergingGroup = group
            } label: {
                Text("合并这 \(group.contacts.count) 条")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.accentColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .confirmationDialog(
            "确认合并？",
            isPresented: Binding(
                get: { mergingGroup?.id == group.id },
                set: { if !$0 { mergingGroup = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("合并", role: .destructive) {
                performMerge(group)
                mergingGroup = nil
            }
            Button("取消", role: .cancel) { mergingGroup = nil }
        } message: {
            Text("将保留「\(group.keeper?.displayName ?? "")」，其余 \(group.contacts.count - 1) 条会被删除。")
        }
    }

    private func detailLine(_ contact: Contact) -> String {
        var parts: [String] = []
        if let p = contact.phones.first?.number { parts.append(p) }
        if !contact.organization.isEmpty { parts.append(contact.organization) }
        if let d = contact.lastContactedAt {
            parts.append("联系过 \(d.formatted(.dateTime.month().day()))")
        }
        return parts.isEmpty ? "无更多信息" : parts.joined(separator: " · ")
    }

    private func performMerge(_ group: DuplicateGroup) {
        guard let keeper = group.keeper else { return }
        let removed = DuplicateDetector.merge(group, into: keeper)
        for c in removed {
            context.delete(c)
        }
        try? context.save()
        Haptics.success()
        withAnimation {
            toast = "已合并 \(removed.count + 1) 条为 1 条"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { toast = nil }
        }
    }
}

// MARK: - 问题联系人清单

struct ProblemListSheet: View {

    let title: String
    let contacts: [Contact]
    let hint: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(contacts) { contact in
                    NavigationLink {
                        ContactDetailView(contact: contact)
                    } label: {
                        ContactRow(contact: contact)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
    }
}

// MARK: - 可疑号码清单

struct InvalidPhoneList: View {

    let items: [(contact: Contact, number: String)]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    NavigationLink {
                        ContactDetailView(contact: item.contact)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.contact.displayName)
                                    .font(.subheadline)
                                Text(item.number)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            Text("\(item.number.filter(\.isNumber).count) 位")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("正常手机号 11 位，座机带区号一般 10~12 位。位数明显不对的，可能是录入时漏了或多打了。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("格式可疑的号码")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
    }
}
