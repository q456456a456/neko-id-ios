//
//  LovablePersonaResultPage.swift
//  neko-id
//
//  Native mirror of the current Lovable/Web Screen6Result page.
//

import SwiftUI
import UIKit
import Photos

struct LovablePersonaResultPage: View {
    @EnvironmentObject private var appModel: NekoAppModel
    @State private var shareOpen = false
    @State private var shareImage: UIImage?
    @State private var shareActivityOpen = false
    @State private var isGeneratingShareImage = false
    @State private var loadedAvatarImage: UIImage?

    let catName: String
    let avatarImage: UIImage?
    let avatarURL: URL?
    let avatarObjectKey: String?
    let persona: CatPersonaResult
    var isSaving: Bool = false
    var saveDisabled: Bool = false
    let onBack: (() -> Void)?
    let onRestart: () -> Void
    let onSave: () -> Void

    private var displayName: String {
        let trimmed = catName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "猫咪" : trimmed
    }

    private var personaType: String {
        trimmed(persona.type, fallback: "人格仍待了解")
    }

    private var personaMbti: String {
        trimmed(persona.mbti, fallback: "待识别")
    }

    private var monologue: String {
        trimmed(persona.monologue, fallback: "不黏人，但永远会待在离你不远的地方。")
    }

    private var analysis: String {
        trimmed(persona.analysis, fallback: "我不一定每次都跑向你，但如果你在家，我会睡得更安心。")
    }

    private var coreDescription: String {
        trimmed(persona.corePersonality ?? "", fallback: analysis)
    }

    private var misunderstanding: String {
        trimmed(persona.misunderstanding ?? "", fallback: "现有资料还不足以判断你最容易误会它的哪种行为。多记录几次真实互动后，会得到更可靠的答案。")
    }

    private var loveLanguage: String {
        trimmed(
            persona.loveLanguageInsight ?? persona.loveLanguage ?? "",
            fallback: "目前还没有足够的行为答案判断它如何表达喜欢，暂时不对它的长期亲密模式下结论。"
        )
    }

    private var ownerRole: String {
        trimmed(persona.ownerRelationship ?? persona.ownerRole, fallback: "现有资料不足以确定你在它长期关系中的位置，继续相处和记录会比一次测试更可靠。")
    }

    private var personaKeywords: [String] {
        let tags = persona.tags.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return Array(tags.prefix(3))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                LovableResultBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ZStack(alignment: .top) {
                            LovableResultHero(
                                catName: displayName,
                                avatarImage: avatarImage,
                                avatarURL: avatarURL,
                                avatarObjectKey: avatarObjectKey,
                                personaType: personaType,
                                personaMbti: personaMbti,
                                coreDescription: coreDescription,
                                keywords: personaKeywords,
                                onAvatarImageLoaded: { loadedAvatarImage = $0 }
                            )

                            SafeAreaTopBar(onBack: onBack)
                            .padding(.horizontal, 20)
                            .padding(.top, proxy.safeAreaInsets.top + 10)
                        }
                        .frame(height: min(max(proxy.size.width * 1.25, 470), 570))

                        LovableCatInsightSection(
                            catName: displayName,
                            misunderstanding: misunderstanding,
                            loveLanguage: loveLanguage,
                            ownerRole: ownerRole
                        )

                        Color.clear
                            .frame(height: 112 + max(proxy.safeAreaInsets.bottom, 20))
                    }
                    .frame(width: proxy.size.width, alignment: .leading)
                }
                .frame(width: proxy.size.width)
                .ignoresSafeArea(edges: .top)

                LovableResultBottomActions(
                    isSaving: isSaving,
                    saveDisabled: saveDisabled,
                    bottomInset: max(proxy.safeAreaInsets.bottom, 20),
                    contentWidth: proxy.size.width,
                    onRestart: onRestart,
                    onSave: onSave
                )
                .zIndex(20)

            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $shareActivityOpen) {
            if let shareImage {
                LovableActivityView(activityItems: [shareImage])
                    .ignoresSafeArea()
            }
        }
    }

    private func closeShare() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.95)) {
            shareOpen = false
        }
    }

    private func trimmed(_ value: String, fallback: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? fallback : text
    }

    @MainActor
    private func presentSystemShare(width: CGFloat) {
        guard !isGeneratingShareImage else { return }
        closeShare()
        isGeneratingShareImage = true
        appModel.noticeMessage = "正在生成分享图…"

        Task { @MainActor in
            defer { isGeneratingShareImage = false }
            guard let image = renderShareImage(width: width) else {
                appModel.errorMessage = "分享图生成失败，请稍后再试。"
                return
            }
            shareImage = image
            shareActivityOpen = true
        }
    }

    @MainActor
    private func saveShareImage(width: CGFloat) {
        guard !isGeneratingShareImage else { return }
        closeShare()
        isGeneratingShareImage = true
        appModel.noticeMessage = "正在生成分享图…"

        Task { @MainActor in
            defer { isGeneratingShareImage = false }
            guard let image = renderShareImage(width: width) else {
                appModel.errorMessage = "分享图生成失败，请稍后再试。"
                return
            }

            do {
                try await LovablePhotoLibrarySaver.save(image)
                appModel.noticeMessage = "已保存到相册"
            } catch {
                appModel.errorMessage = NekoUserFacingError.message(
                    for: error,
                    fallback: "保存到相册失败，请检查相册权限。"
                )
            }
        }
    }

    @MainActor
    private func renderShareImage(width: CGFloat) -> UIImage? {
        let renderWidth = min(max(width, 320), 430)
        let image = avatarImage ?? loadedAvatarImage
        let content = LovableResultShareImage(
            catName: displayName,
            avatarImage: image,
            personaType: personaType,
            personaMbti: personaMbti,
            monologue: monologue,
            keywords: personaKeywords,
            misunderstanding: misunderstanding,
            loveLanguage: loveLanguage,
            ownerRole: ownerRole,
            width: renderWidth
        )
        .frame(width: renderWidth)
        .environmentObject(appModel)

        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

private enum LovableResultStyle {
    static let bgTop = Color(red: 0.998, green: 0.965, blue: 0.992)
    static let bgMid = Color(red: 0.988, green: 0.932, blue: 0.990)
    static let bgBottom = Color(red: 0.944, green: 0.922, blue: 1.000)
    static let ink = Color(red: 0.255, green: 0.215, blue: 0.325)
    static let inkSoft = Color(red: 0.420, green: 0.370, blue: 0.470)
    static let muted = Color(red: 0.570, green: 0.515, blue: 0.640)
    static let label = Color(red: 0.550, green: 0.410, blue: 0.610)
    static let topIcon = Color(red: 0.520, green: 0.315, blue: 0.620)
    static let primaryStart = Color(red: 0.714, green: 0.604, blue: 0.937) // #B69AEF
    static let primaryEnd = Color(red: 0.902, green: 0.722, blue: 0.812)   // #E6B8CF
    static let heroTitleStart = Color(red: 0.659, green: 0.545, blue: 0.918) // #A88BEA
    static let heroTitleMid = Color(red: 0.784, green: 0.588, blue: 0.878)   // #C896E0
    static let heroTitleEnd = Color(red: 0.937, green: 0.686, blue: 0.784)   // #EFAFC8

    static let resultBackground = LinearGradient(
        colors: [bgTop, bgMid, bgBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    static let primaryGradient = LinearGradient(
        colors: [primaryStart, primaryEnd],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let heroTitleGradient = LinearGradient(
        colors: [heroTitleStart, heroTitleMid, heroTitleEnd],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let keywords = ["温柔观察者", "慢热", "安静陪伴"]

}

private struct LovableResultInsight: Identifiable {
    var id: String { "\(number)-\(title)" }
    let number: String
    let title: String
    let text: String
}

private struct LovableResultScene: Identifiable {
    var id: String { title }
    let title: String
    let line: String
}

private struct LovableResultBackground: View {
    var body: some View {
        ZStack {
            LovableResultStyle.resultBackground
            NekoSparkles(count: 14)
        }
        .ignoresSafeArea()
    }
}

private struct SafeAreaTopBar: View {
    let onBack: (() -> Void)?

    var body: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    LovableChevronLeftIcon(color: LovableResultStyle.topIcon)
                        .frame(width: 18, height: 18)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.80), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LovableResultHero: View {
    let catName: String
    let avatarImage: UIImage?
    let avatarURL: URL?
    let avatarObjectKey: String?
    let personaType: String
    let personaMbti: String
    let coreDescription: String
    let keywords: [String]
    var onAvatarImageLoaded: (UIImage?) -> Void = { _ in }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LovableAvatarImage(
                image: avatarImage,
                remoteURL: avatarURL,
                objectKey: avatarObjectKey,
                contentMode: .fill,
                onImageLoaded: onAvatarImageLoaded
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            LinearGradient(
                colors: [.white.opacity(0.34), .clear, .clear],
                startPoint: .topLeading,
                endPoint: .center
            )

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: LovableResultStyle.bgMid.opacity(0.60), location: 0.50),
                    .init(color: LovableResultStyle.bgMid, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 300)
            .frame(maxWidth: .infinity, alignment: .bottom)

            VStack(alignment: .leading, spacing: 2) {
                Text("CAT")
                Text("PROFILE")
                Rectangle()
                    .frame(width: 26, height: 1)
                    .padding(.top, 5)
            }
            .font(.system(size: 16, weight: .regular, design: .serif))
            .tracking(0.8)
            .foregroundStyle(Color(red: 0.40, green: 0.36, blue: 0.58).opacity(0.72))
            .padding(.leading, 24)
            .padding(.top, 116)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(catName)
                        .font(.system(size: 21, weight: .semibold))
                    Text(personaMbti)
                        .font(.system(size: 17, weight: .medium))
                }
                .foregroundStyle(Color(red: 0.28, green: 0.23, blue: 0.49))
                .lineLimit(1)

                Text(personaType)
                    .font(.system(size: 40, weight: .regular, design: .serif))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .foregroundStyle(Color(red: 0.24, green: 0.19, blue: 0.46))
                    .padding(.top, 12)

                Text(coreDescription)
                    .font(.system(size: 15, weight: .medium))
                    .lineSpacing(4)
                    .foregroundStyle(Color(red: 0.34, green: 0.31, blue: 0.50))
                    .lineLimit(3)
                    .padding(.top, 10)

                HStack(spacing: 8) {
                    ForEach(keywords, id: \.self) { keyword in
                        Text(keyword)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(red: 0.500, green: 0.345, blue: 0.595))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.85), in: Capsule())
                            .shadow(color: LovableResultStyle.primaryStart.opacity(0.18), radius: 10, x: 0, y: 5)
                    }
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

private struct LovableLittleWorldSection: View {
    let catName: String
    let contentWidth: CGFloat
    let avatarImage: UIImage?
    let avatarURL: URL?
    let avatarObjectKey: String?

    private let scenes = [
        LovableResultScene(title: "靠窗发呆", line: "保留它真实的样子，换一种光线看看。"),
        LovableResultScene(title: "偷偷陪伴", line: "还是熟悉的它，只把这一刻重新构图。"),
        LovableResultScene(title: "心里的小王国", line: "猫咪本人不变，只添一点梦幻氛围。"),
    ]

    var body: some View {
        let safeWidth = max(contentWidth, 1)
        let cardWidth = min(safeWidth * 0.88, 340)

        VStack(alignment: .leading, spacing: 0) {
            LovableResultSectionHeader(title: "\(catName)的小世界", hint: "LITTLE · WORLD")
                .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(scenes.enumerated()), id: \.element.id) { index, scene in
                        LovableSceneCard(
                            scene: scene,
                            index: index,
                            total: scenes.count,
                            width: cardWidth,
                            avatarImage: avatarImage,
                            avatarURL: avatarURL,
                            avatarObjectKey: avatarObjectKey
                        )
                    }
                }
                .padding(.leading, 24)
                .padding(.trailing, max(safeWidth * 0.12, 24))
                .padding(.bottom, 8)
            }
            .padding(.top, 14)

            HStack(spacing: 6) {
                ForEach(Array(scenes.enumerated()), id: \.element.id) { index, _ in
                    Capsule()
                        .fill(index == 0 ? AnyShapeStyle(LovableResultStyle.primaryGradient) : AnyShapeStyle(Color(red: 0.890, green: 0.850, blue: 0.920)))
                        .frame(width: index == 0 ? 16 : 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
        .padding(.top, 28)
    }
}

private struct LovableResultSectionHeader: View {
    let title: String
    let hint: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: NekoTypography.web(16), weight: .semibold))
                .foregroundStyle(Color(red: 0.315, green: 0.270, blue: 0.375))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(hint)
                .font(.system(size: NekoTypography.web(10), weight: .regular))
                .tracking(2.2)
                .foregroundStyle(Color(red: 0.720, green: 0.660, blue: 0.760))
                .lineLimit(1)
        }
    }
}

private struct LovableSceneCard: View {
    let scene: LovableResultScene
    let index: Int
    let total: Int
    let width: CGFloat
    let avatarImage: UIImage?
    let avatarURL: URL?
    let avatarObjectKey: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            LovableAvatarImage(
                image: avatarImage,
                remoteURL: avatarURL,
                objectKey: avatarObjectKey,
                contentMode: .fill
            )
                .frame(width: width, height: width * 1.25)
                .clipped()

            sceneAtmosphere

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Color(red: 0.160, green: 0.110, blue: 0.190).opacity(0.55), location: 0.55),
                    .init(color: Color(red: 0.140, green: 0.100, blue: 0.170).opacity(0.72), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: width * 1.25 * 0.52)
            .frame(maxHeight: .infinity, alignment: .bottom)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scene.title)
                        .font(.system(size: NekoTypography.web(14), weight: .medium))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.95))
                        .shadow(color: Color(red: 0.160, green: 0.110, blue: 0.190).opacity(0.60), radius: 8, x: 0, y: 1)

                    Text(scene.line)
                        .font(.system(size: NekoTypography.web(12.5), weight: .regular))
                        .lineSpacing(4)
                        .foregroundStyle(.white.opacity(0.80))
                        .shadow(color: Color(red: 0.160, green: 0.110, blue: 0.190).opacity(0.60), radius: 8, x: 0, y: 1)
                }

                Spacer(minLength: 8)

                Text("\(String(format: "%02d", index + 1))/\(String(format: "%02d", total))")
                    .font(.system(size: NekoTypography.web(10), weight: .regular))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.70))
                    .padding(.bottom, 2)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: width, height: width * 1.25)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.85), lineWidth: 1)
        }
        .shadow(color: LovableResultStyle.primaryStart.opacity(0.14), radius: 18, x: 0, y: 10)
    }

    @ViewBuilder
    private var sceneAtmosphere: some View {
        switch index % 3 {
        case 0:
            LinearGradient(
                colors: [.white.opacity(0.08), Color(red: 0.78, green: 0.70, blue: 0.96).opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 1:
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.10, blue: 0.24).opacity(0.12), Color(red: 0.54, green: 0.42, blue: 0.76).opacity(0.26)],
                startPoint: .top,
                endPoint: .bottom
            )
        default:
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.96, green: 0.78, blue: 0.90).opacity(0.12), Color(red: 0.68, green: 0.58, blue: 0.92).opacity(0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(.white.opacity(0.20))
                    .frame(width: width * 0.42, height: width * 0.42)
                    .blur(radius: 20)
                    .offset(x: width * 0.28, y: -width * 0.38)
            }
        }
    }
}

private struct LovableCatInsightSection: View {
    let catName: String
    let misunderstanding: String
    let loveLanguage: String
    let ownerRole: String

    private var insights: [LovableResultInsight] {
        [
            LovableResultInsight(number: "01", title: "你可能一直误会它的一件事", text: misunderstanding),
            LovableResultInsight(number: "02", title: "它表达喜欢的方式", text: loveLanguage),
            LovableResultInsight(number: "03", title: "在\(catName)眼里，你的位置", text: ownerRole),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LovableResultSectionHeader(title: "原来\(catName)是这样的猫", hint: "CAT · INSIGHT")

            VStack(spacing: 10) {
                ForEach(insights) { insight in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(insight.number)
                                .font(.system(size: NekoTypography.web(11), weight: .medium))
                                .tracking(2)
                                .foregroundStyle(LovableResultStyle.primaryStart)

                            Text(insight.title)
                                .font(.system(size: NekoTypography.web(15), weight: .semibold))
                                .foregroundStyle(Color(red: 0.330, green: 0.285, blue: 0.385))
                        }

                        Text(insight.text)
                            .font(.system(size: NekoTypography.web(14), weight: .regular))
                            .lineSpacing(6)
                            .foregroundStyle(Color(red: 0.485, green: 0.440, blue: 0.540))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 17)
                    .background(
                        LinearGradient(
                            colors: insight.number == "03"
                                ? [Color(red: 0.992, green: 0.930, blue: 0.980).opacity(0.90), Color(red: 0.955, green: 0.910, blue: 0.995).opacity(0.90)]
                                : [.white.opacity(0.76), Color(red: 1.0, green: 0.970, blue: 0.995).opacity(0.54)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(.white.opacity(0.80), lineWidth: 1)
                    }
                    .shadow(color: LovableResultStyle.primaryStart.opacity(0.12), radius: 15, x: 0, y: 8)
                }
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
    }
}

private struct LovableResultBottomActions: View {
    let isSaving: Bool
    let saveDisabled: Bool
    let bottomInset: CGFloat
    let contentWidth: CGFloat
    let onRestart: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onRestart) {
                Text("重新识别")
                    .font(.system(size: NekoTypography.web(14), weight: .medium))
                    .foregroundStyle(Color(red: 0.500, green: 0.320, blue: 0.590))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color(red: 0.780, green: 0.702, blue: 0.949), lineWidth: 1.5)
                    }
                    .shadow(color: LovableResultStyle.primaryStart.opacity(0.10), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)

            Button(action: onSave) {
                Text(isSaving ? "保存中…" : "保存结果")
                    .font(.system(size: NekoTypography.web(14), weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LovableResultStyle.primaryGradient, in: Capsule())
                    .shadow(color: LovableResultStyle.primaryStart.opacity(0.26), radius: 14, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(saveDisabled || isSaving)
            .opacity(saveDisabled ? 0.58 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, bottomInset)
        .frame(width: contentWidth, alignment: .center)
        .background(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Color(red: 0.944, green: 0.912, blue: 1.000).opacity(0.92), location: 0.35),
                    .init(color: LovableResultStyle.bgBottom.opacity(0.98), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }
}

private struct LovableResultShareSheet: View {
    let onClose: () -> Void
    let onWeChat: () -> Void
    let onMoments: () -> Void
    let onSaveImage: () -> Void
    let busy: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.20)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color(red: 0.910, green: 0.875, blue: 0.930))
                    .frame(width: 40, height: 4)

                Text("分享我的猫人格")
                    .font(.system(size: NekoTypography.web(15), weight: .medium))
                    .foregroundStyle(LovableResultStyle.ink)
                    .padding(.top, 16)

                HStack(spacing: 0) {
                    LovableShareItem(label: "微信好友", emoji: "💬", colors: [Color(red: 0.420, green: 0.831, blue: 0.420), Color(red: 0.169, green: 0.722, blue: 0.361)], isDisabled: busy, action: onWeChat)
                    LovableShareItem(label: "朋友圈", emoji: "🌈", colors: [Color(red: 1.000, green: 0.702, blue: 0.420), Color(red: 1.000, green: 0.420, blue: 0.710)], isDisabled: busy, action: onMoments)
                    LovableShareItem(label: "保存图片", emoji: "⬇️", colors: [LovableResultStyle.primaryStart, LovableResultStyle.primaryEnd], isDisabled: busy, action: onSaveImage)
                }
                .padding(.top, 20)

                Button("取消", action: onClose)
                    .font(.system(size: NekoTypography.web(15), weight: .medium))
                    .foregroundStyle(Color(red: 0.450, green: 0.310, blue: 0.520))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.965, green: 0.935, blue: 0.975), in: Capsule())
                    .padding(.top, 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 28)
            .frame(maxWidth: 480)
            .background(.white.opacity(0.95), in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
            .shadow(color: Color.black.opacity(0.16), radius: 28, x: 0, y: -12)
        }
    }
}

private struct LovableShareItem: View {
    let label: String
    let emoji: String
    let colors: [Color]
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 22))
                    .frame(width: 48, height: 48)
                    .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)

                Text(label)
                    .font(.system(size: NekoTypography.web(13), weight: .regular))
                    .foregroundStyle(LovableResultStyle.ink.opacity(0.80))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

private struct LovableResultShareImage: View {
    let catName: String
    let avatarImage: UIImage?
    let personaType: String
    let personaMbti: String
    let monologue: String
    let keywords: [String]
    let misunderstanding: String
    let loveLanguage: String
    let ownerRole: String
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                LovableResultHero(
                    catName: catName,
                    avatarImage: avatarImage,
                    avatarURL: nil,
                    avatarObjectKey: nil,
                    personaType: personaType,
                    personaMbti: personaMbti,
                    coreDescription: monologue,
                    keywords: keywords
                )

                HStack {
                    Color.clear
                        .frame(width: 36, height: 36)

                    Spacer()

                    Text("喵一下")
                        .font(.system(size: NekoTypography.web(10), weight: .medium))
                        .tracking(5)
                        .foregroundStyle(Color(red: 0.545, green: 0.410, blue: 0.595))

                    Spacer()

                    Color.clear
                        .frame(width: 36, height: 36)
                }
                .padding(.horizontal, 20)
                .padding(.top, 50)
            }
            .frame(height: 520)

            LovableCatInsightSection(
                catName: catName,
                misunderstanding: misunderstanding,
                loveLanguage: loveLanguage,
                ownerRole: ownerRole
            )

            Text("喵一下 · 读懂它的小世界")
                .font(.system(size: NekoTypography.web(10), weight: .medium))
                .tracking(5)
                .foregroundStyle(LovableResultStyle.label.opacity(0.72))
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
                .padding(.bottom, 28)
        }
        .frame(width: width, alignment: .topLeading)
        .background(LovableResultStyle.resultBackground)
        .overlay {
            NekoSparkles(count: 14)
        }
    }
}

private struct LovableActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private enum LovableShareError: LocalizedError {
    case photoPermissionDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .photoPermissionDenied:
            return "没有相册写入权限，请在系统设置里允许添加照片。"
        case .saveFailed:
            return "保存到相册失败，请稍后再试。"
        }
    }
}

private enum LovablePhotoLibrarySaver {
    static func save(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw LovableShareError.photoPermissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: LovableShareError.saveFailed)
                }
            }
        }
    }
}

private struct LovableAvatarImage: View {
    let image: UIImage?
    let remoteURL: URL?
    let objectKey: String?
    let contentMode: ContentMode
    var onImageLoaded: (UIImage?) -> Void = { _ in }

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .onAppear {
                    onImageLoaded(image)
                }
        } else {
            NekoRemoteImageView(
                remoteURL: remoteURL,
                objectKey: objectKey,
                contentMode: contentMode,
                onImageLoaded: onImageLoaded
            ) {
                ZStack {
                    LovableResultStyle.resultBackground
                    VStack(spacing: 10) {
                        Image(systemName: "photo")
                            .font(.system(size: 26, weight: .light))
                        Text("照片暂时无法显示")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(LovableResultStyle.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct LovableChevronLeftIcon: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: size.width * 0.64, y: size.height * 0.20))
            path.addLine(to: CGPoint(x: size.width * 0.32, y: size.height * 0.50))
            path.addLine(to: CGPoint(x: size.width * 0.64, y: size.height * 0.80))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct LovableShare2Icon: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let points = [
                CGPoint(x: size.width * 0.30, y: size.height * 0.50),
                CGPoint(x: size.width * 0.72, y: size.height * 0.24),
                CGPoint(x: size.width * 0.72, y: size.height * 0.76),
            ]

            var line = Path()
            line.move(to: points[0])
            line.addLine(to: points[1])
            line.move(to: points[0])
            line.addLine(to: points[2])
            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            for point in points {
                let radius = size.width * 0.16
                let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 2)
            }
        }
    }
}
