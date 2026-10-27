import SwiftUI
import SwiftData

// MARK: - 入口：决定显示锁屏还是内容

struct VaultGateView: View {

    @EnvironmentObject private var security: SecurityService

    var body: some View {
        NavigationStack {
            Group {
                if security.isUnlocked {
                    VaultListView()
                } else {
                    VaultLockView()
                }
            }
            .navigationTitle("保险箱")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 锁屏

struct VaultLockView: View {

    @EnvironmentObject private var security: SecurityService
    @EnvironmentObject private var settings: AppSettings

    @Query(filter: #Predicate<Contact> { $0.isInVault })
    private var vaultContacts: [Contact]

    private enum Stage {
        case locked          // 展示解锁方式
        case enteringPIN     // 输入 PIN
        case settingPIN      // 首次设置 PIN
        case confirmingPIN   // 再输一次确认
    }

    @State private var stage: Stage = .locked
    @State private var pinInput = ""
    @State private var firstPin = ""
    @State private var errorMessage: String?
    @State private var isBusy = false
    @State private var shakeTrigger = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            header

            Spacer(minLength: 16)

            switch stage {
            case .locked:
                lockedActions
            case .enteringPIN, .settingPIN, .confirmingPIN:
                pinEntry
            }

            Spacer(minLength: 30)
        }
        .padding(.horizontal, 28)
        .background(Color(.systemGroupedBackground))
        .task {
            // 支持生物识别就直接弹一次，少点一下
            if security.biometryAvailable, settings.vaultEnabled {
                _ = await security.authenticate()
            }
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 96, height: 96)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 6) {
                Text("隐私保险箱")
                    .font(.title2.weight(.semibold))

                Text(vaultContacts.isEmpty
                     ? "把不想被旁人看到的联系人锁进来"
                     : "已锁住 \(vaultContacts.count) 位联系人")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: 解锁方式

    private var lockedActions: some View {
        VStack(spacing: 12) {
            if security.biometryAvailable {
                Button {
                    Task {
                        isBusy = true
                        defer { isBusy = false }
                        let ok = await security.authenticate()
                        if !ok { errorMessage = "验证未通过，可改用 PIN 解锁" }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: security.biometrySymbol)
                        Text(isBusy ? "验证中…" : "用\(security.biometryName)解锁")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .foregroundStyle(.white)
                }
                .disabled(isBusy)
            }

            if settings.hasPIN {
                Button {
                    errorMessage = nil
                    pinInput = ""
                    stage = .enteringPIN
                } label: {
                    Text(settings.hasPIN ? "使用 PIN 解锁" : "设置 PIN")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
            } else if !security.biometryAvailable {
                // 两种方式都没有，引导设 PIN
                Button {
                    firstPin = ""
                    pinInput = ""
                    stage = .settingPIN
                } label: {
                    Text("设置 4 位 PIN 保护保险箱")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .foregroundStyle(.white)
                }
            } else {
                Button("改用 PIN 解锁", action: startSetPINIfNeeded)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Text("内容仅保存在这台手机上，不上传任何服务器。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
    }

    private func startSetPINIfNeeded() {
        if settings.hasPIN {
            errorMessage = nil
            pinInput = ""
            stage = .enteringPIN
        } else {
            firstPin = ""
            pinInput = ""
            stage = .settingPIN
        }
    }

    // MARK: PIN 输入

    private var pinEntry: some View {
        VStack(spacing: 22) {
            Text(promptText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // 四个圆点
            HStack(spacing: 20) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(index < pinInput.count ? Color.accentColor : Color.secondary.opacity(0.22))
                        .frame(width: 14, height: 14)
                }
            }
            .modifier(ShakeEffect(animatableData: CGFloat(shakeTrigger)))

            PinPad(pin: $pinInput, length: 4) { code in
                handle(code)
            }

            Button("返回") {
                stage = .locked
                pinInput = ""
                errorMessage = nil
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .onChange(of: pinInput) { _, newValue in
            if newValue.count == 4 {
                handle(newValue)
            }
        }
    }

    private var promptText: String {
        switch stage {
        case .enteringPIN: return "输入 4 位 PIN"
        case .settingPIN: return "设置一个 4 位 PIN"
        case .confirmingPIN: return "再输一次确认"
        case .locked: return ""
        }
    }

    private func handle(_ code: String) {
        guard code.count == 4 else { return }

        switch stage {
        case .enteringPIN:
            if SecurityService.verify(pin: code, against: settings.pinHash) {
                Haptics.success()
                security.isUnlocked = true
            } else {
                fail("PIN 不正确")
            }

        case .settingPIN:
            firstPin = code
            pinInput = ""
            stage = .confirmingPIN

        case .confirmingPIN:
            if code == firstPin {
                settings.pinHash = SecurityService.hash(code)
                Haptics.success()
                security.isUnlocked = true
            } else {
                fail("两次输入不一致，请重新设置")
                firstPin = ""
                stage = .settingPIN
            }

        case .locked:
            break
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        withAnimation(.default) { shakeTrigger += 1 }
        UINotificationFeedbackGenerator().notificationOccurred(.error)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            pinInput = ""
        }
    }
}

// MARK: - 数字键盘

struct PinPad: View {

    @Binding var pin: String
    var length: Int = 4
    var onComplete: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 22) {
                    ForEach(digits(for: row), id: \.self) { d in
                        button(d)
                    }
                }
            }
        }
    }

    private func digits(for row: Int) -> [String] {
        switch row {
        case 0: return ["1", "2", "3"]
        case 1: return ["4", "5", "6"]
        case 2: return ["7", "8", "9"]
        default: return ["", "0", "⌫"]
        }
    }

    private func button(_ d: String) -> some View {
        Button {
            guard !d.isEmpty else { return }
            if d == "⌫" {
                Haptics.tap()
                if !pin.isEmpty { pin.removeLast() }
                return
            }
            Haptics.tap()
            guard pin.count < length else { return }
            pin.append(d)
        } label: {
            Text(d)
                .font(.system(size: 24, weight: .regular, design: .rounded))
                .frame(width: 68, height: 58)
                .background(
                    d.isEmpty ? Color.clear : Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
                .foregroundStyle(.primary)
        }
        .buttonStyle(KeyButtonStyle())
        .disabled(d.isEmpty)
    }
}

// MARK: - 抖动效果

struct ShakeEffect: GeometryEffect {

    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = sin(animatableData * .pi * 6) * 7
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

// MARK: - 保险箱内列表

struct VaultListView: View {

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var security: SecurityService

    @Query(filter: #Predicate<Contact> { $0.isInVault },
           sort: [SortDescriptor(\Contact.sortKey)])
    private var vaultContacts: [Contact]

    @State private var revealDetail = false

    var body: some View {
        Group {
            if vaultContacts.isEmpty {
                EmptyStateView(
                    symbol: "lock.open",
                    title: "保险箱是空的",
                    message: "去联系人详情页底部，点「移入隐私保险箱」\n那个人就会从这里之外的任何地方消失"
                )
            } else {
                List {
                    Section {
                        ForEach(vaultContacts) { contact in
                            NavigationLink(value: contact) {
                                ContactRow(contact: contact)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    withAnimation {
                                        contact.isInVault = false
                                        try? context.save()
                                    }
                                } label: {
                                    Label("移出", systemImage: "lock.open")
                                }
                                .tint(.orange)
                            }
                        }
                    } footer: {
                        Text("这些联系人在主列表、搜索和九宫格里都不会出现。")
                    }
                }
                .listStyle(.insetGrouped)
                .navigationDestination(for: Contact.self) { contact in
                    ContactDetailView(contact: contact)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    security.lock()
                } label: {
                    Label("上锁", systemImage: "lock.fill")
                }
            }
        }
    }
}
