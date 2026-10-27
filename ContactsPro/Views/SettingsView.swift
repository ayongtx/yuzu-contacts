import SwiftUI
import SwiftData

struct SettingsView: View {

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var security: SecurityService

    @Query private var allContacts: [Contact]

    @State private var showingPinSetup = false
    @State private var showingWipeConfirm = false
    @State private var wipeInput = ""

    var body: some View {
        Form {
            appearanceSection
            radarSection
            vaultSection
            dataSection
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPinSetup) {
            PinSetupSheet()
                .environmentObject(settings)
        }
        .alert("清空所有联系人？", isPresented: $showingWipeConfirm) {
            TextField("输入 DELETE 确认", text: $wipeInput)
            Button("取消", role: .cancel) { wipeInput = "" }
            Button("永久删除", role: .destructive) {
                guard wipeInput.uppercased() == "DELETE" else {
                    wipeInput = ""
                    return
                }
                wipeAll()
            }
        } message: {
            Text("这会删除本机所有 \(allContacts.count) 位联系人（含保险箱），无法撤销。建议先导出备份。")
        }
    }

    // MARK: - 外观

    private var appearanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("主题色")
                    .font(.subheadline)

                HStack(spacing: 14) {
                    ForEach(AccentTheme.allCases) { theme in
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                settings.accentKey = theme.rawValue
                            }
                            Haptics.tap()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(theme.color)
                                    .frame(width: 32, height: 32)

                                if settings.accent == theme {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(theme.name)
                    }
                    Spacer()
                }

                Text(settings.accent.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            Toggle("列表显示头像", isOn: $settings.showAvatars)
        } header: {
            Text("外观")
        } footer: {
            Text("关掉头像后，一屏能多看三四个人，找起来更快。")
        }
    }

    // MARK: - 雷达

    private var radarSection: some View {
        Section {
            HStack {
                Text("多久没联系算「冷落」")
                    .font(.subheadline)
                Spacer()
                Text("\(settings.neglectDays) 天")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(settings.neglectDays) },
                    set: { settings.neglectDays = Int($0) }
                ),
                in: 7...180,
                step: 1
            )
            .tint(Color.accentColor)
        } header: {
            Text("雷达")
        } footer: {
            Text("超过这个天数没联系的人，会出现在「雷达 → 待联系」里。默认 45 天。")
        }
    }

    // MARK: - 保险箱

    private var vaultSection: some View {
        Section {
            Toggle("启用隐私保险箱", isOn: $settings.vaultEnabled)

            Button {
                showingPinSetup = true
            } label: {
                HStack {
                    Text(settings.hasPIN ? "修改 PIN" : "设置 PIN")
                    Spacer()
                    Text(settings.hasPIN ? "已设置" : "未设置")
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!settings.vaultEnabled)

            Button {
                security.lock()
                Haptics.impact()
            } label: {
                Label("立即上锁", systemImage: "lock.fill")
            }
            .disabled(!settings.vaultEnabled)
        } header: {
            Text("隐私保险箱")
        } footer: {
            Text("保险箱优先用\(security.biometryName)解锁；PIN 是备选方案，万一系统权限没给到也能进得去。退出 App 时会自动上锁。")
        }
    }

    // MARK: - 数据

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                wipeInput = ""
                showingWipeConfirm = true
            } label: {
                Label("清空所有联系人", systemImage: "trash")
            }
        } header: {
            Text("数据")
        } footer: {
            Text("当前共有 \(allContacts.count) 位联系人。清空前请先在「更多 → 导出备份」里存一份。")
        }
    }

    private func wipeAll() {
        for contact in allContacts {
            context.delete(contact)
        }
        try? context.save()
        wipeInput = ""
        Haptics.success()
    }
}

// MARK: - 设置 PIN

struct PinSetupSheet: View {

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case first, confirm
    }

    @State private var stage: Stage = .first
    @State private var pin = ""
    @State private var firstPin = ""
    @State private var errorMessage: String?
    @State private var shake = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color.accentColor)

                    Text(stage == .first ? "设置 4 位 PIN" : "再输一次确认")
                        .font(.headline)

                    Text("忘记 PIN 时只能重置保险箱，请记牢")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                HStack(spacing: 20) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index < pin.count ? Color.accentColor : Color.secondary.opacity(0.22))
                            .frame(width: 14, height: 14)
                    }
                }
                .modifier(ShakeEffect(animatableData: CGFloat(shake)))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                PinPad(pin: $pin, length: 4) { code in
                    advance(code)
                }

                Spacer()
            }
            .padding(.horizontal, 28)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(settings.hasPIN ? "修改 PIN" : "设置 PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onChange(of: pin) { _, newValue in
                if newValue.count == 4 { advance(newValue) }
            }
        }
    }

    private func advance(_ code: String) {
        guard code.count == 4 else { return }

        if stage == .first {
            firstPin = code
            pin = ""
            stage = .confirm
            errorMessage = nil
        } else {
            if code == firstPin {
                settings.pinHash = SecurityService.hash(code)
                Haptics.success()
                dismiss()
            } else {
                errorMessage = "两次输入不一致，重新来过"
                withAnimation { shake += 1 }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                firstPin = ""
                pin = ""
                stage = .first
            }
        }
    }
}
