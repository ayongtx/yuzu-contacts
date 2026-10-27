import SwiftUI
import SwiftData

struct ContactListView: View {

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var settings: AppSettings

    // 保险箱里的联系人不进主列表
    @Query(
        filter: #Predicate<Contact> { $0.isInVault == false },
        sort: [SortDescriptor(\Contact.sortKey)]
    )
    private var contacts: [Contact]

    @State private var searchText = ""
    @State private var showingCreate = false
    @State private var pendingDelete: Contact?

    var body: some View {
        NavigationStack {
            Group {
                if contacts.isEmpty {
                    EmptyStateView(
                        symbol: "person.crop.circle.badge.plus",
                        title: "通讯录还是空的",
                        message: "点右上角的 + 添加第一位联系人\n或者到「更多 → 导入」从系统通讯录搬过来",
                        actionTitle: "添加联系人",
                        action: { showingCreate = true }
                    )
                } else if filtered.isEmpty {
                    EmptyStateView(
                        symbol: "magnifyingglass",
                        title: "没有匹配的联系人",
                        message: "换个关键词试试，支持拼音首字母搜索"
                    )
                } else {
                    contactList
                }
            }
            .navigationTitle("通讯录")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索姓名、公司或号码")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加联系人")
                }
            }
            .sheet(isPresented: $showingCreate) {
                ContactEditView(mode: .create)
            }
            .confirmationDialog(
                "确定删除「\(pendingDelete?.displayName ?? "")」？",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let target = pendingDelete {
                        withAnimation { context.delete(target) }
                        try? context.save()
                    }
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("删除后无法恢复，建议先在「更多 → 备份」里导出一次。")
            }
        }
    }

    // MARK: - 列表主体

    private var contactList: some View {
        ScrollViewReader { proxy in
            List {
                // 收藏区置顶
                if searchText.isEmpty, !favorites.isEmpty {
                    Section {
                        ForEach(favorites) { contact in
                            row(for: contact)
                        }
                    } header: {
                        Label("常用", systemImage: "star.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(grouped, id: \.letter) { group in
                    Section {
                        ForEach(group.items) { contact in
                            row(for: contact)
                                .id(rowID(for: contact, letter: group.letter, first: group.items.first?.id == contact.id))
                        }
                    } header: {
                        Text(group.letter)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }

                // 底部留一点空间，避免最后一行被索引条压住
                Color.clear.frame(height: 40)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .overlay(alignment: .trailing) {
                if searchText.isEmpty, grouped.count > 1 {
                    IndexBar(letters: grouped.map(\.letter)) { letter in
                        withAnimation(.easeOut(duration: 0.22)) {
                            proxy.scrollTo("idx-\(letter)", anchor: .top)
                        }
                    }
                    .padding(.trailing, 2)
                }
            }
        }
    }

    /// 给每个分组的首行打上锚点 id，索引条跳转才准
    private func rowID(for contact: Contact, letter: String, first: Bool) -> String {
        first ? "idx-\(letter)" : contact.id.uuidString
    }

    private func row(for contact: Contact) -> some View {
        NavigationLink(value: contact) {
            ContactRow(contact: contact, showAvatar: settings.showAvatars)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                withAnimation {
                    contact.isFavorite.toggle()
                    contact.updatedAt = Date()
                    try? context.save()
                }
            } label: {
                Label(contact.isFavorite ? "取消常用" : "常用",
                      systemImage: contact.isFavorite ? "star.slash" : "star")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = contact
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .navigationDestination(for: Contact.self) { item in
            ContactDetailView(contact: item)
        }
    }

    // MARK: - 数据加工

    private var favorites: [Contact] {
        filtered.filter(\.isFavorite)
    }

    private var filtered: [Contact] {
        guard !searchText.isEmpty else { return contacts }
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)

        return contacts.filter { c in
            if c.searchBlob.contains(q) { return true }
            // 纯数字：按号码匹配
            let digits = q.filter(\.isNumber)
            if !digits.isEmpty {
                if c.phones.contains(where: { $0.number.filter(\.isNumber).contains(digits) }) {
                    return true
                }
            }
            return false
        }
    }

    private var grouped: [(letter: String, items: [Contact])] {
        var bucket: [String: [Contact]] = [:]
        for c in filtered {
            bucket[c.indexLetter, default: []].append(c)
        }
        // A-Z 在前，# 兜底放最后
        let letters = bucket.keys.sorted { a, b in
            if a == "#" { return false }
            if b == "#" { return true }
            return a < b
        }
        return letters.map { ($0, bucket[$0] ?? []) }
    }
}

// MARK: - 右侧 A-Z 索引条

/// 支持点按和上下滑动快速定位，手感对齐系统通讯录。
struct IndexBar: View {

    let letters: [String]
    var onSelect: (String) -> Void

    @State private var activeLetter: String?

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { letter in
                    Text(letter)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(activeLetter == letter ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onSelect(letter)
                        }
                }
            }
            .frame(width: 22)
            .background(.ultraThinMaterial, in: Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let step = geo.size.height / CGFloat(max(letters.count, 1))
                        let idx = Int(value.location.y / step)
                        guard idx >= 0, idx < letters.count else { return }
                        let letter = letters[idx]
                        guard letter != activeLetter else { return }
                        activeLetter = letter
                        UISelectionFeedbackGenerator().selectionChanged()
                        onSelect(letter)
                    }
                    .onEnded { _ in
                        activeLetter = nil
                    }
            )
        }
        .frame(width: 22)
        .padding(.vertical, 40)
    }
}
