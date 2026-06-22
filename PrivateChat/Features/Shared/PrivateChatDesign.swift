import SwiftUI

/// SecureChat design system.
///
/// The brand is dark-first with a securechat-cyan accent and a
/// deep-purple secondary. The system is built for trust, clarity
/// and a "venture-grade" feel. Every component used in the app is
/// defined here; feature views reference these constants instead
/// of hard-coding values.
enum SecureChatDesign {
    // MARK: - Brand palette

    /// Primary accent: securechat cyan. Used for primary actions,
    /// active states, encryption indicators, and the E2E badge.
    /// Calibrated for legibility on dark backgrounds (WCAG AA on
    /// #0B1220 at the 600 weight).
    static let brandCyan: Color = Color(red: 0.13, green: 0.83, blue: 0.93)        // #22D3EE
    static let brandCyanDeep: Color = Color(red: 0.02, green: 0.71, blue: 0.83)    // #06B6D4

    /// Secondary accent: deep purple. Used for highlights, paired
    /// with the cyan in gradients and on the Onboarding hero.
    static let brandPurple: Color = Color(red: 0.49, green: 0.23, blue: 0.93)     // #7C3AED
    static let brandPurpleSoft: Color = Color(red: 0.42, green: 0.36, blue: 0.92)  // #6C5CE7

    /// Semantic states. Tints are pulled to the cyan/purple family
    /// for consistency with the brand, not the default iOS greens
    /// and oranges.
    static let success: Color = Color(red: 0.13, green: 0.83, blue: 0.55)        // close to brand
    static let warning: Color = Color(red: 0.96, green: 0.62, blue: 0.20)        // amber
    static let danger: Color = Color(red: 0.97, green: 0.30, blue: 0.42)         // coral

    // MARK: - Surfaces (dark-first)

    /// Page background base. Slightly off-black so the gradient
    /// highlights have somewhere to glow into.
    static let canvasBase: Color = Color(red: 0.04, green: 0.07, blue: 0.13)      // #0B1220
    static let canvasElevated: Color = Color(red: 0.07, green: 0.11, blue: 0.18)  // #131B2E
    static let canvasHigh: Color = Color(red: 0.11, green: 0.16, blue: 0.25)      // #1C2940

    // MARK: - Foregrounds

    static let textPrimary: Color = .white
    static let textSecondary: Color = Color(white: 0.62)
    static let textTertiary: Color = Color(white: 0.42)

    // MARK: - Geometry

    static let cardCornerRadius: CGFloat = 24
    static let compactCornerRadius: CGFloat = 14
    static let tileCornerRadius: CGFloat = 18
    static let capsuleCornerRadius: CGFloat = 999

    /// 4-pt spacing scale. Use these instead of literal values.
    static let spaceXS: CGFloat = 4
    static let spaceS: CGFloat = 8
    static let spaceM: CGFloat = 12
    static let spaceL: CGFloat = 16
    static let spaceXL: CGFloat = 22
    static let space2XL: CGFloat = 28

    // MARK: - Card backgrounds

    /// Standard card: dark surface with cyan-tinted border and a
    /// very subtle internal gradient. Replaces the iOS
    /// `thinMaterial` look with something that has brand identity.
    static var cardBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                canvasElevated.opacity(0.96),
                canvasHigh.opacity(0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Elevated (hero) card: brighter gradient with a stronger cyan
    /// highlight at the top.
    static var elevatedCardBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                canvasHigh.opacity(0.98),
                canvasElevated.opacity(0.96)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var subtleBorder: Color {
        Color.white.opacity(0.08)
    }

    /// Brand-tinted border. Used on highlighted cards.
    static var strongBorder: Color {
        brandCyan.opacity(0.30)
    }

    // MARK: - Page background (aurora)

    /// Aurora gradient used as the page background. Cyan glow at
    /// the top, purple glow at the bottom-right, dark base in the
    /// middle. Calibrated to read as "SecureChat" on first open.
    static var pageGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: brandCyan.opacity(0.18), location: 0.0),
                .init(color: canvasBase, location: 0.32),
                .init(color: canvasBase, location: 0.68),
                .init(color: brandPurple.opacity(0.16), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Brand gradient (cyan -> purple). Used for primary buttons,
    /// the App-Icon-style mark, and Onboarding hero accents.
    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [brandCyan, brandPurpleSoft],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Top-bar/header gradient (vertical cyan glow fading to dark).
    static var headerGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: brandCyan.opacity(0.30), location: 0.0),
                .init(color: canvasBase.opacity(0.0), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Semantic helpers

    static func statusTint(isHealthy: Bool) -> Color {
        isHealthy ? success : warning
    }

    /// Translucent tint for an accent color, used behind icon
    /// badges and inside status pills.
    static func tinted(_ color: Color, opacity: Double = 0.14) -> Color {
        color.opacity(opacity)
    }
}

// MARK: - Card modifier

struct SecureChatGlassCard: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat
    let highlighted: Bool
    let glow: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(highlighted ? AnyShapeStyle(SecureChatDesign.elevatedCardBackground) : AnyShapeStyle(SecureChatDesign.cardBackground))
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        highlighted ? SecureChatDesign.strongBorder : SecureChatDesign.subtleBorder,
                        lineWidth: 1
                    )
            }
            .shadow(
                color: highlighted ? SecureChatDesign.brandCyan.opacity(0.12) : Color.black.opacity(0.35),
                radius: highlighted ? 22 : 12,
                x: 0,
                y: highlighted ? 12 : 6
            )
    }
}

extension View {
    /// Standard SecureChat card. Use for almost every container.
    func secureChatGlassCard(
        padding: CGFloat = SecureChatDesign.spaceL,
        cornerRadius: CGFloat = SecureChatDesign.cardCornerRadius,
        highlighted: Bool = false
    ) -> some View {
        modifier(SecureChatGlassCard(
            padding: padding,
            cornerRadius: cornerRadius,
            highlighted: highlighted,
            glow: highlighted
        ))
    }
}

// MARK: - Status pill (E2E / Relay / Hardening)

struct SecureChatStatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.30), lineWidth: 1)
            }
    }
}

// MARK: - Hero card (dashboard top section)

struct SecureChatHeroCard: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let footer: String?

    init(
        eyebrow: String,
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color = SecureChatDesign.brandCyan,
        footer: String? = nil
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(eyebrow.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                        .tracking(1.0)
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(SecureChatDesign.textPrimary)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(SecureChatDesign.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                ZStack {
                    Circle()
                        .fill(SecureChatDesign.brandGradient)
                        .frame(width: 56, height: 56)
                    Image(systemName: systemImage)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            if let footer {
                Text(footer)
                    .font(.caption.monospaced())
                    .foregroundStyle(SecureChatDesign.textSecondary)
                    .lineLimit(1)
            }
        }
        .secureChatGlassCard(padding: 20, cornerRadius: 26, highlighted: true)
    }
}

// MARK: - Section header

struct SecureChatSectionHeader: View {
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
                .foregroundStyle(SecureChatDesign.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(SecureChatDesign.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Primary CTA button

struct SecureChatPrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(SecureChatDesign.brandGradient, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status card (small tile)

/// A compact status tile: icon + title + value + optional
/// footnote. Used in the dashboard's health grid and in the
/// settings pages' "snapshot" sections.
struct SecureChatStatusCard: View {
    let title: String
    let value: String
    let systemImage: String
    let footnote: String?
    let tint: Color

    init(
        title: String,
        value: String,
        systemImage: String,
        footnote: String? = nil,
        tint: Color = SecureChatDesign.brandCyan
    ) {
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
                    .background(tint.opacity(0.14), in: Circle())
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SecureChatDesign.textSecondary)
                Spacer(minLength: 0)
            }

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(SecureChatDesign.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(SecureChatDesign.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .secureChatGlassCard(padding: 14, cornerRadius: SecureChatDesign.tileCornerRadius)
    }
}

// MARK: - Encryption pulse (animated E2E indicator)

/// A subtle pulse animation that loops forever. Used to mark the
/// "E2E active" state on the lock screen and dashboard hero.
struct SecureChatEncryptionPulse: View {
    let tint: Color
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(pulse ? 0.0 : 0.55), lineWidth: 2)
                .scaleEffect(pulse ? 1.8 : 1.0)
            Circle()
                .fill(tint.opacity(0.18))
                .scaleEffect(pulse ? 1.0 : 0.6)
            Image(systemName: "lock.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(width: 64, height: 64)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
        }
    }
}

// MARK: - Backwards-compat aliases
//
// The brand rename (PrivateChat -> SecureChat) and the design
// system refactor (privateChatGlassCard -> secureChatGlassCard)
// happened in Sprint 4. These aliases keep every old call site
// compiling until the refactor is finished. They will be removed
// in Sprint 5 once the views are migrated.

typealias PrivateChatDesign = SecureChatDesign
typealias PrivateChatGlassCard = SecureChatGlassCard
typealias PrivateChatStatusPill = SecureChatStatusPill
typealias PrivateChatSectionHeader = SecureChatSectionHeader
typealias PrivateChatHeroCard = SecureChatHeroCard
typealias PrivateChatStatusCard = SecureChatStatusCard

extension View {
    /// Backwards-compat alias for the old `privateChatGlassCard`
    /// modifier name. New code should use `secureChatGlassCard`.
    func privateChatGlassCard(
        padding: CGFloat = SecureChatDesign.spaceL,
        cornerRadius: CGFloat = SecureChatDesign.cardCornerRadius,
        highlighted: Bool = false
    ) -> some View {
        secureChatGlassCard(padding: padding, cornerRadius: cornerRadius, highlighted: highlighted)
    }
}

/// Old name for the primary button. New code should use
/// `SecureChatPrimaryButton`.
struct PrivateChatActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

