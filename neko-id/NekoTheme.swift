//
//  NekoTheme.swift
//  neko-id
//
//  Shared NEKO.ID visual system, mirrored from the web app.
//

import SwiftUI

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
            .font(.system(size: 15, weight: .semibold))
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
            .font(.system(size: 15, weight: .semibold))
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
            .font(.system(size: 10, weight: .semibold))
            .tracking(3.2)
            .foregroundStyle(NekoTheme.muted)
    }
}
