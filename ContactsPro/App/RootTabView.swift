import SwiftUI
import SwiftData

struct RootTabView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var security: SecurityService

    @Query(filter: #Predicate<Contact> { $0.isInVault })
    private var vaultContacts: [Contact]

    @State private var didSeed = false

    var body: some View {
        TabView {
            ContactListView()
                .tabItem { Label("通讯录", systemImage: "person.2.fill") }

            T9KeypadView()
                .tabItem { Label("键盘", systemImage: "circle.grid.3x3.fill") }

            RadarView()
                .tabItem { Label("雷达", systemImage: "dot.radiowaves.left.and.right") }

            VaultGateView()
                .tabItem { Label("保险箱", systemImage: "lock.shield.fill") }
                .badge(vaultContacts.isEmpty ? 0 : vaultContacts.count)

            MoreView()
                .tabItem { Label("更多", systemImage: "ellipsis.circle.fill") }
        }
        .task {
            guard !didSeed else { return }
            didSeed = true
            SeedService.seedIfNeeded(context)
        }
        .onChange(of: scenePhase) { _, phase in
            // 退到后台就上锁，避免切 App 时被旁边的人看到保险箱内容
            if phase == .background {
                security.lock()
            }
        }
    }
}

// MARK: - 首次启动填充示例数据

enum SeedService {

    private static let flagKey = "cp.didSeedSampleData"

    static func seedIfNeeded(_ context: ModelContext) {
        // 用户主动删光后不要再塞回来
        if UserDefaults.standard.bool(forKey: flagKey) { return }

        let descriptor = FetchDescriptor<Contact>()
        let existing = (try? context.fetchCount(descriptor)) ?? 0
        guard existing == 0 else {
            UserDefaults.standard.set(true, forKey: flagKey)
            return
        }

        for contact in SampleData.makeSamples() {
            context.insert(contact)
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: flagKey)
    }
}
