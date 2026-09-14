//
//  NekoTheme.swift
//  neko-id
//
//  Shared NEKO.ID visual system, mirrored from the web app.
//

import SwiftUI
import UIKit

enum NekoTheme {
    static let creamTop = Color(red: 1.00, green: 0.985, blue: 0.935)
    static let creamMid = Color(red: 0.988, green: 0.938, blue: 0.980)
    static let lilacBottom = Color(red: 0.947, green: 0.914, blue: 1.000)

    static let ink = Color(red: 0.245, green: 0.192, blue: 0.369)
    static let inkSoft = Color(red: 0.482, green: 0.447, blue: 0.565)
    static let muted = Color(red: 0.565, green: 0.517, blue: 0.650)
    static let mutedLight = Color(red: 0.710, green: 0.672, blue: 0.770)

    static let soulViolet = Color(red: 0.714, green: 0.604, blue: 0.937)
    static let soulPink = Color(red: 0.898, green: 0.667, blue: 0.800)
    static let softPink = Color(red: 0.964, green: 0.862, blue: 0.910)
    static let softLilac = Color(red: 0.914, green: 0.843, blue: 0.984)
    static let accent = Color(red: 0.749, green: 0.639, blue: 0.949)
    static let tabActive = Color(red: 0.714, green: 0.604, blue: 0.937)
    static let tabInactive = Color(red: 0.482, green: 0.447, blue: 0.565)
    static let menuIcon = Color(red: 0.545, green: 0.345, blue: 0.615)

    static let cardWhite = Color.white.opacity(0.84)
    static let cardTint = Color(red: 0.988, green: 0.940, blue: 0.976).opacity(0.82)
    static let field = Color(red: 0.985, green: 0.965, blue: 0.992).opacity(0.92)

    static let primaryGradient = LinearGradient(
        colors: [Color(red: 0.682, green: 0.561, blue: 0.906), Color(red: 0.898, green: 0.667, blue: 0.800)],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let selectedGradient = LinearGradient(
        colors: [Color(red: 0.780, green: 0.702, blue: 0.949), Color(red: 0.922, green: 0.776, blue: 0.851)],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let cardGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.88),
            Color(red: 0.975, green: 0.928, blue: 0.972).opacity(0.70),
        ],
        startPoint: .top,
        endPoint: .bottomTrailing
    )

    static let tintGradient = LinearGradient(
        colors: [
            Color(red: 0.976, green: 0.910, blue: 0.965).opacity(0.94),
            Color(red: 0.952, green: 0.914, blue: 0.996).opacity(0.86),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let menuIconGradient = LinearGradient(
        colors: [
            Color(red: 0.982, green: 0.902, blue: 0.980),
            Color(red: 0.946, green: 0.906, blue: 1.000),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [creamTop, creamMid, lilacBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    static let photoPlaceholderGradient = LinearGradient(
        colors: [
            Color(red: 0.976, green: 0.925, blue: 1.000),
            Color(red: 0.992, green: 0.914, blue: 0.938),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

enum NekoTypography {
    enum RelativeTextStyle {
        case avatarSymbol
        case mediaPlaceholderIcon

        var ratio: CGFloat {
            switch self {
            case .avatarSymbol: 0.36
            case .mediaPlaceholderIcon: 0.18
            }
        }

        var weight: Font.Weight {
            switch self {
            case .avatarSymbol: .semibold
            case .mediaPlaceholderIcon: .regular
            }
        }
    }

    enum TextStyle {
        case pageTitle
        case mainTitle
        case moduleTitle
        case cardTitle
        case body
        case support
        case button
        case tabBarLabel
        case badge
        case eyebrow
        case caption
        case micro
        case tiny
        case display
        case iconSmall
        case iconMedium
        case iconLarge
        case personaTitleLarge
        case personaTitleMedium
        case personaTitleSmall
        case personaEditorial
        case personaEditorialSmall
        case monospacedCaption

        var size: CGFloat {
            switch self {
            case .pageTitle: 28
            case .mainTitle: 30
            case .moduleTitle: 21
            case .cardTitle: 18
            case .body: 16
            case .support: 14
            case .button: 17
            case .tabBarLabel: 13
            case .badge: 15
            case .eyebrow: 14
            case .caption: 13
            case .micro: 12
            case .tiny: 11
            case .display: 34
            case .iconSmall: 14
            case .iconMedium: 20
            case .iconLarge: 28
            case .personaTitleLarge: 42
            case .personaTitleMedium: 38
            case .personaTitleSmall: 34
            case .personaEditorial: 16
            case .personaEditorialSmall: 11
            case .monospacedCaption: 12
            }
        }

        var lineHeight: CGFloat {
            switch self {
            case .pageTitle: 34
            case .mainTitle: 38
            case .moduleTitle: 28
            case .cardTitle: 24
            case .body: 24
            case .support: 20
            case .button: 22
            case .tabBarLabel: 18
            case .badge: 20
            case .eyebrow: 20
            case .caption: 18
            case .micro: 16
            case .tiny: 15
            case .display: 40
            case .iconSmall: 14
            case .iconMedium: 20
            case .iconLarge: 28
            case .personaTitleLarge: 46
            case .personaTitleMedium: 42
            case .personaTitleSmall: 38
            case .personaEditorial: 18
            case .personaEditorialSmall: 15
            case .monospacedCaption: 16
            }
        }

        var weight: Font.Weight {
            switch self {
            case .pageTitle, .mainTitle, .moduleTitle, .cardTitle, .button, .iconLarge, .personaTitleLarge, .personaTitleMedium, .personaTitleSmall:
                .semibold
            case .tabBarLabel, .badge, .eyebrow, .caption, .iconSmall, .iconMedium:
                .medium
            case .monospacedCaption:
                .medium
            default:
                .regular
            }
        }

        var letterSpacing: CGFloat { 0 }

        var lineSpacing: CGFloat {
            max(0, lineHeight - size)
        }
    }

    static func font(_ style: TextStyle) -> Font {
        switch style {
        case .personaTitleLarge, .personaTitleMedium, .personaTitleSmall:
            return named(
                ["Songti SC Semibold", "SongtiSC-Semibold", "Songti SC Bold", "SongtiSC-Bold", "STSong"],
                size: style.size,
                fallback: .system(size: style.size, weight: .semibold, design: .serif)
            )
        case .personaEditorial, .personaEditorialSmall:
            return named(
                ["Didot", "Bodoni 72", "BodoniSvtyTwoITCTT-Book", "Baskerville", "TimesNewRomanPSMT"],
                size: style.size,
                fallback: .system(size: style.size, weight: .regular, design: .serif)
            )
        case .monospacedCaption:
            return .system(size: style.size, weight: style.weight, design: .monospaced)
        default:
            return .system(size: style.size, weight: style.weight)
        }
    }

    static func personaTitleStyle(for characterCount: Int) -> TextStyle {
        if characterCount <= 6 { return .personaTitleLarge }
        if characterCount <= 10 { return .personaTitleMedium }
        return .personaTitleSmall
    }

    static func relativeFont(_ style: RelativeTextStyle, for size: CGFloat) -> Font {
        .system(size: size * style.ratio, weight: style.weight)
    }

    /// Legacy visual-equivalent scale kept only for old layout constants while views migrate to semantic tokens.
    static func web(_ px: CGFloat) -> CGFloat {
        switch px {
        case ..<10:
            return px + 1.5
        case ..<18:
            return px + 1
        default:
            return px
        }
    }

    private static func named(_ names: [String], size: CGFloat, fallback: Font) -> Font {
        for name in names where UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return fallback
    }
}

private struct NekoTextStyleModifier: ViewModifier {
    let style: NekoTypography.TextStyle

    func body(content: Content) -> some View {
        content
            .font(NekoTypography.font(style))
            .lineSpacing(style.lineSpacing)
            .tracking(style.letterSpacing)
    }
}

extension View {
    func nekoText(_ style: NekoTypography.TextStyle) -> some View {
        modifier(NekoTextStyleModifier(style: style))
    }

    func nekoRelativeText(_ style: NekoTypography.RelativeTextStyle, size: CGFloat) -> some View {
        font(NekoTypography.relativeFont(style, for: size))
            .tracking(0)
    }
}

struct NekoBackground: View {
    var body: some View {
        ZStack {
            NekoTheme.backgroundGradient

            Circle()
                .fill(NekoTheme.soulPink.opacity(0.26))
                .frame(width: 250, height: 250)
                .blur(radius: 58)
                .offset(x: -150, y: -250)

            Circle()
                .fill(NekoTheme.soulViolet.opacity(0.24))
                .frame(width: 300, height: 300)
                .blur(radius: 68)
                .offset(x: 160, y: 180)

            Circle()
                .fill(Color.white.opacity(0.34))
                .frame(width: 210, height: 210)
                .blur(radius: 56)
                .offset(x: 120, y: -120)

            NekoSparkles(count: 18)
        }
        .ignoresSafeArea()
    }
}

struct NekoSparkles: View {
    let count: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<count, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(0.48 + Double(index % 4) * 0.08))
                        .frame(width: CGFloat((index * 13) % 5 + 2), height: CGFloat((index * 13) % 5 + 2))
                        .shadow(color: NekoTheme.soulPink.opacity(0.45), radius: 6)
                        .position(
                            x: proxy.size.width * CGFloat((index * 47) % 100) / 100,
                            y: proxy.size.height * CGFloat((index * 71) % 100) / 100
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct NekoGlassCard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let tint: Bool
    @ViewBuilder private let content: Content

    init(cornerRadius: CGFloat = 24, tint: Bool = false, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .background(tint ? AnyShapeStyle(NekoTheme.tintGradient) : AnyShapeStyle(NekoTheme.cardGradient))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
            }
            .shadow(color: NekoTheme.soulViolet.opacity(0.16), radius: 28, x: 0, y: 14)
    }
}

struct NekoPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .nekoText(.button)
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .background(NekoTheme.primaryGradient, in: Capsule())
            .shadow(color: NekoTheme.soulViolet.opacity(configuration.isPressed ? 0.10 : 0.20), radius: 20, x: 0, y: 10)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct NekoSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .nekoText(.button)
            .foregroundStyle(NekoTheme.ink)
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .background(Color.white.opacity(configuration.isPressed ? 0.68 : 0.86), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.74), lineWidth: 1)
            }
            .shadow(color: NekoTheme.soulViolet.opacity(0.10), radius: 18, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct NekoSectionLabel: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .nekoText(.eyebrow)
            .foregroundStyle(NekoTheme.muted)
    }
}
