import SwiftUI

// MARK: - 头像

/// 有照片用照片，没照片就用姓名首字生成一个稳定的渐变文字头像。
/// 颜色由名字哈希决定，同一个人每次打开都是同一个颜色，不会闪。
struct AvatarView: View {

    let contact: Contact
    var size: CGFloat = 46

    var body: some View {
        Group {
            if let data = contact.avatarData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(contact.monogram)
                    .font(.system(size: size * 0.40, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(gradient)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
        }
    }

    private var gradient: LinearGradient {
        let palette: [(Color, Color)] = [
            (Color(red: 0.42, green: 0.60, blue: 0.92), Color(red: 0.24, green: 0.38, blue: 0.80)),
            (Color(red: 0.90, green: 0.55, blue: 0.50), Color(red: 0.78, green: 0.33, blue: 0.36)),
            (Color(red: 0.55, green: 0.80, blue: 0.68), Color(red: 0.24, green: 0.60, blue: 0.52)),
            (Color(red: 0.76, green: 0.62, blue: 0.90), Color(red: 0.52, green: 0.38, blue: 0.76)),
            (Color(red: 0.95, green: 0.75, blue: 0.45), Color(red: 0.86, green: 0.55, blue: 0.25)),
            (Color(red: 0.50, green: 0.72, blue: 0.88), Color(red: 0.30, green: 0.50, blue: 0.72))
        ]
        // 稳定的哈希：逐字符累加，避免 hashValue 每次启动都变
        var seed = 0
        for scalar in contact.displayName.unicodeScalars {
            seed = (seed &* 31 &+ Int(scalar.value)) % 100000
        }
        let pair = palette[abs(seed) % palette.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - 列表行

struct ContactRow: View {

    let contact: Contact
    var showAvatar: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            if showAvatar {
                AvatarView(contact: contact, size: 44)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(contact.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if contact.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                    }

                    if contact.isInVault {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }

                if let sub = rowSubtitle {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var rowSubtitle: String? {
        if !contact.subtitle.isEmpty { return contact.subtitle }
        return contact.primaryPhone?.number
    }
}

// MARK: - 卡片容器

/// 详情页里那种「一组信息、圆角、白底」的容器
struct SectionCard<Content: View>: View {

    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
            }

            VStack(spacing: 0) {
                content
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

/// 卡片里的一行：左边图标 + 主副标题 + 右侧内容
struct CardRow<Trailing: View>: View {

    var icon: String?
    var title: String
    var subtitle: String?
    var tint: Color = .accentColor
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/// 行之间的分隔线（左边留白，模仿 iOS 原生表格）
struct CardDivider: View {
    var body: some View {
        Divider().padding(.leading, 52)
    }
}

// MARK: - 空状态

struct EmptyStateView: View {

    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 统计数字块

struct StatTile: View {

    var value: String
    var label: String
    var tint: Color
    var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
