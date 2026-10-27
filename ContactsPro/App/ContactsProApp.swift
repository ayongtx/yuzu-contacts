import SwiftUI
import SwiftData

@main
struct ContactsProApp: App {

    @StateObject private var settings = AppSettings()
    @StateObject private var security = SecurityService()

    private let container: ModelContainer

    init() {
        let schema = Schema([Contact.self])
        let config = ModelConfiguration("ContactsPro", schema: schema)

        if let ok = try? ModelContainer(for: schema, configurations: [config]) {
            container = ok
        } else {
            // 模型迁移失败等极端情况：退回内存库，至少保证 App 能打开而不是闪退
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: [fallback])
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(settings)
                .environmentObject(security)
                .tint(settings.accentColor)
        }
        .modelContainer(container)
    }
}
