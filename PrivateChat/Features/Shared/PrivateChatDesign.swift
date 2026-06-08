import SwiftUI

enum PrivateChatDesign {
    static let cardCornerRadius: CGFloat = 22
    static let compactCornerRadius: CGFloat = 14
    static let capsuleCornerRadius: CGFloat = 999

    static var cardBackground: some ShapeStyle {
        .thinMaterial
    }

    static var elevatedCardBackground: some ShapeStyle {
        .regularMaterial
    }

    static var subtleBorder: Color {
        Color.secondary.opacity(0.16)
    }

    static var strongBorder: Color {
        Color.accentColor.opacity(0.22)
    }

    static var pageGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.10),
                Color.secondary.opacity(0.035),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func statusTint(isHealthy: Bool) -> Color {
        isHealthy ? Color.green : Color.orange
    }
}

struct PrivateChatGlassCard: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat
    let highlighted: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                highlighted ? AnyShapeStyle(PrivateChatDesign.elevatedCardBackground) : AnyShapeStyle(PrivateChatDesign.cardBackground),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(highlighted ? PrivateChatDesign.strongBorder : PrivateChatDesign.subtleBorder, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.05), radius: highlighted ? 16 : 8, x: 0, y: highlighted ? 8 : 4)
    }
}

extension View {
    func privateChatGlassCard(padding: CGFloat = 16, cornerRadius: CGFloat = PrivateChatDesign.cardCornerRadius, highlighted: Bool = false) -> some View {
        modifier(PrivateChatGlassCard(padding: padding, cornerRadius: cornerRadius, highlighted: highlighted))
    }
}

struct PrivateChatStatusCard: View {
    let title: String
    let value: String
    let systemImage: String
    let footnote: String?
    let tint: Color

    init(title: String, value: String, systemImage: String, footnote: String? = nil, tint: Color = .accentColor) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.footnote = footnote
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(tint.opacity(0.12), in: Circle())
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text(value)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .privateChatGlassCard(padding: 14, cornerRadius: 18)
    }
}

struct PrivateChatSectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PrivateChatStatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.11), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            }
    }
}

struct PrivateChatHeroCard: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let footer: String?

    init(eyebrow: String, title: String, subtitle: String, systemImage: String, tint: Color = .accentColor, footer: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(eyebrow.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                        .tracking(0.7)
                    Text(title)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 62, height: 62)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            if let footer {
                Text(footer)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .privateChatGlassCard(padding: 18, cornerRadius: 26, highlighted: true)
    }
}

struct PrivateChatActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }
}
