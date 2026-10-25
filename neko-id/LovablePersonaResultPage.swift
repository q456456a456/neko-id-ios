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
        LovablePersonaCopy.title(persona.persona.personaTitle)
    }

    private var personaMbti: String {
        persona.persona.mbti
    }

    private var coreDescription: String {
        LovablePersonaCopy.description(
            persona.persona.summary,
            fallback: persona.persona.summary
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    LovableResultHero(
                        catName: displayName,
                        avatarImage: avatarImage,
                        avatarURL: avatarURL,
                        avatarObjectKey: avatarObjectKey,
                        personaType: personaType,
                        personaMbti: personaMbti,
                        coreDescription: coreDescription,
                        contentWidth: proxy.size.width,
                        onAvatarImageLoaded: { loadedAvatarImage = $0 }
                    )
                    .overlay(alignment: .top) {
                        SafeAreaTopBar(onBack: onBack)
                            .padding(.horizontal, 20)
                            .padding(.top, proxy.safeAreaInsets.top + 10)
                    }

                    LovablePersonaDimensionsSection(
                        catName: displayName,
                        dimensions: persona.dimensions
                    )

                    LovableCatInsightSection(
                        catName: displayName,
                        insights: persona.insights
                    )

                    LovableBondSummarySection(
                        catName: displayName,
                        quote: persona.bondSummary.quote
                    )

                    Color.clear.frame(height: proxy.safeAreaInsets.bottom + 108)
                }
                .frame(width: proxy.size.width, alignment: .leading)
            }
            .frame(width: proxy.size.width)
            .background(LovableResultBackground())
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                LovableResultBottomActions(
                    isSaving: isSaving,
                    saveDisabled: saveDisabled,
                    bottomInset: max(proxy.safeAreaInsets.bottom, 10),
                    contentWidth: proxy.size.width,
                    onRestart: onRestart,
                    onSave: onSave
                )
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
            coreDescription: coreDescription,
            dimensions: persona.dimensions,
            insights: persona.insights,
            bondSummary: persona.bondSummary,
            width: renderWidth
        )
        .frame(width: renderWidth)
        .environmentObject(appModel)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: renderWidth, height: nil)
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

    static func chineseEditorial(_ size: CGFloat) -> Font {
        if UIFont(name: "SongtiSC-Semibold", size: size) != nil {
            return .custom("SongtiSC-Semibold", fixedSize: size)
        }
        if UIFont(name: "Songti SC", size: size) != nil {
            return .custom("Songti SC", fixedSize: size).weight(.semibold)
        }
        if UIFont(name: "STSong", size: size) != nil {
            return .custom("STSong", fixedSize: size).weight(.semibold)
        }
        return .system(size: size, weight: .semibold, design: .serif)
    }

    static func englishEditorial(_ size: CGFloat) -> Font {
        if UIFont(name: "Didot", size: size) != nil {
            return .custom("Didot", fixedSize: size)
        }
        if UIFont(name: "Bodoni 72", size: size) != nil {
            return .custom("Bodoni 72", fixedSize: size)
        }
        if UIFont(name: "Baskerville", size: size) != nil {
            return .custom("Baskerville", fixedSize: size)
        }
        if UIFont(name: "Times New Roman", size: size) != nil {
            return .custom("Times New Roman", fixedSize: size)
        }
        return .system(size: size, design: .serif)
    }

    static func chineseUI(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if UIFont(name: "PingFangSC-Regular", size: size) != nil {
            return .custom("PingFang SC", fixedSize: size).weight(weight)
        }
        return .system(size: size, weight: weight)
    }

}

private struct EditorialPersonaTitle {
    let text: String
    let fontSize: CGFloat

    init(_ rawValue: String) {
        let normalized = rawValue
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let characters = Array(normalized)

        switch characters.count {
        case ...6:
            text = normalized
            fontSize = 44
        case 7...10:
            text = Self.balancedTwoLines(characters)
            fontSize = 39
        case 11...14:
            text = Self.balancedTwoLines(characters)
            fontSize = 34
        default:
            // The generation layer is expected to keep titles within 14 Chinese
            // characters. This visual guard prevents legacy data producing an
            // orphaned third line while preserving the full stored value.
            text = Self.balancedTwoLines(Array(characters.prefix(14)))
            fontSize = 32
        }
    }

    private static func balancedTwoLines(_ characters: [Character]) -> String {
        guard characters.count > 6 else { return String(characters) }
        var split = Int(ceil(Double(characters.count) / 2.0))
        split = min(max(split, 3), characters.count - 3)
        return String(characters[..<split]) + "\n" + String(characters[split...])
    }
}

private enum LovablePersonaCopy {
    private static let fallbackTitle = "安静观察型"
    private static let bannedTokens = [
        "营业", "控场", "发令", "施压", "稳态", "高质", "策略性", "仪式感极强",
        "端庄定点", "克制讨关注", "精准互动", "节奏掌控", "掌控节奏", "眼神催促"
    ]
    private static let titleReplacements: [(String, String)] = [
        ("亲近有边界", "边界感亲近派"),
        ("好奇但谨慎", "好奇谨慎型"),
        ("热情有分寸", "热情有分寸型"),
        ("不黏但在旁", "不黏人陪伴型"),
        ("先观察再靠近", "慢热观察型"),
        ("会先看清楚", "先看再行动"),
        ("先看再动", "先看再行动")
    ]

    static func title(_ value: String) -> String {
        var clean = compact(value)
        for (source, replacement) in titleReplacements where clean == source {
            clean = replacement
        }
        clean = clean.filter { !$0.isWhitespace }
        let count = charCount(clean)
        if count < 4 || count > 14 || hasBannedToken(clean) || endsWithJargonSuffix(clean) {
            return fallbackTitle
        }
        return clean
    }

    static func description(_ value: String, fallback: String) -> String {
        boundedSentence(value, fallback: fallback, max: 50)
    }

    static func insight(_ value: String, fallback: String) -> String {
        boundedSentence(value, fallback: fallback, max: 60)
    }

    private static func boundedSentence(_ value: String, fallback: String, max: Int) -> String {
        let normalized = compact(value).trimmingCharacters(in: CharacterSet(charactersIn: "“”\"'「」『』"))
        let selected = charCount(normalized) >= 8 ? normalized : compact(fallback)
        let chars = Array(selected)
        guard chars.count > max else { return selected }
        let punctuation = Set(["。", "！", "？", "；", "，", ",", ";", "!", "?"])
        let minIndex = max / 2
        var cutIndex = max
        for index in stride(from: max - 1, through: minIndex, by: -1) where punctuation.contains(String(chars[index])) {
            cutIndex = index + 1
            break
        }
        var sliced = String(chars.prefix(cutIndex))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "，,；;：:"))
        if !sliced.hasSuffix("。") && !sliced.hasSuffix("！") && !sliced.hasSuffix("？") {
            sliced.append("。")
        }
        return sliced
    }

    private static func compact(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func charCount(_ value: String) -> Int {
        Array(value).count
    }

    private static func hasBannedToken(_ value: String) -> Bool {
        bannedTokens.contains { value.contains($0) }
    }

    private static func endsWithJargonSuffix(_ value: String) -> Bool {
        value.range(of: #"[一-龥A-Za-z0-9]{1,8}[控王机]$"#, options: .regularExpression) != nil
    }
}

private enum LovablePersonaTitleLayout {
    static func lines(for title: String) -> [String] {
        let chars = Array(title)
        let count = chars.count
        guard count > 6 else { return [title] }
        let splitIndex = bestSplitIndex(chars)
        return [String(chars[..<splitIndex]), String(chars[splitIndex...])]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func bestSplitIndex(_ chars: [Character]) -> Int {
        let count = chars.count
        let validRange = 3...max(3, count - 3)
        if let possessive = chars.firstIndex(of: "的"),
           validRange.contains(possessive + 1) {
            return possessive + 1
        }
        let middle = Double(count) / 2
        return validRange.min { left, right in
            abs(Double(left) - middle) < abs(Double(right) - middle)
        } ?? max(3, count - 3)
    }
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

struct LovableResultHero: View {
    let catName: String
    let avatarImage: UIImage?
    let avatarURL: URL?
    let avatarObjectKey: String?
    let personaType: String
    let personaMbti: String
    let coreDescription: String
    let contentWidth: CGFloat
    var onAvatarImageLoaded: (UIImage?) -> Void = { _ in }
    @State private var resolvedImage: UIImage?

    private var photoHeight: CGFloat {
        min(max(contentWidth * 0.82, 260), 380)
    }

    /// Until the API supplies a face focal point, use the source aspect ratio to
    /// keep portrait ears high and reserve a quiet column for cover copy.
    private var photoOffset: CGSize {
        guard let image = avatarImage ?? resolvedImage, image.size.width > 0, image.size.height > 0 else {
            return CGSize(width: 7, height: -2)
        }
        let ratio = image.size.width / image.size.height
        if ratio > 1.15 { return CGSize(width: 10, height: -4) }
        if ratio < 0.82 { return CGSize(width: 5, height: 4) }
        return CGSize(width: 7, height: -2)
    }

    var body: some View {
        // Only the copy participates in vertical measurement. A fill-mode photo
        // in the sizing ZStack can exceed its proposal and overlap the next section.
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: photoHeight)
            coverCopy
        }
        .frame(width: contentWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { proxy in
                photograph
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
        }
        .clipped()
    }

    private var photograph: some View {
        ZStack(alignment: .bottomLeading) {
            LovableAvatarImage(
                image: avatarImage,
                remoteURL: avatarURL,
                objectKey: avatarObjectKey,
                contentMode: .fill,
                onImageLoaded: { image in
                    resolvedImage = image
                    onAvatarImageLoaded(image)
                }
            )
            .scaleEffect(1.012, anchor: .topTrailing)
            .offset(photoOffset)

            LinearGradient(
                stops: [
                    .init(color: Color(red: 1.0, green: 0.982, blue: 0.965).opacity(0.42), location: 0),
                    .init(color: Color(red: 1.0, green: 0.982, blue: 0.965).opacity(0.22), location: 0.28),
                    .init(color: .clear, location: 0.52),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Color(red: 1.0, green: 0.978, blue: 0.956).opacity(0.34), location: 0.42),
                    .init(color: LovableResultStyle.bgMid.opacity(0.78), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 310)
        }
    }

    private var coverCopy: some View {
        let titleLines = LovablePersonaTitleLayout.lines(for: personaType)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(catName)
                    .nekoText(.button)
                Text(personaMbti)
                    .nekoText(.button)
            }
            .foregroundStyle(Color(red: 0.28, green: 0.23, blue: 0.49))
            .lineLimit(1)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(titleLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .nekoText(.display)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(Color(red: 0.24, green: 0.19, blue: 0.46))
            .padding(.top, 12)

            Text(coreDescription)
                .nekoText(.body)
                .lineSpacing(5)
                .foregroundStyle(Color(red: 0.34, green: 0.31, blue: 0.50))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .nekoText(.cardTitle)
                .foregroundStyle(Color(red: 0.315, green: 0.270, blue: 0.375))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(hint)
                .nekoText(.personaEditorialSmall)
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
                        .nekoText(.badge)
                        .foregroundStyle(.white.opacity(0.95))
                        .shadow(color: Color(red: 0.160, green: 0.110, blue: 0.190).opacity(0.60), radius: 8, x: 0, y: 1)

                    Text(scene.line)
                        .nekoText(.micro)
                        .foregroundStyle(.white.opacity(0.80))
                        .shadow(color: Color(red: 0.160, green: 0.110, blue: 0.190).opacity(0.60), radius: 8, x: 0, y: 1)
                }

                Spacer(minLength: 8)

                Text("\(String(format: "%02d", index + 1))/\(String(format: "%02d", total))")
                    .nekoText(.tiny)
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

private struct LovablePersonaDimensionsSection: View {
    let catName: String
    let dimensions: [PersonaDimension]

    private var orderedDimensions: [PersonaDimension] {
        PersonaDimensionKey.allCases.compactMap { key in
            dimensions.first(where: { $0.key == key })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(catName)的四个行为维度")
                .nekoText(.moduleTitle)
                .foregroundStyle(LovableResultStyle.ink)

            VStack(spacing: 0) {
                ForEach(Array(orderedDimensions.enumerated()), id: \.element.id) { index, dimension in
                    LovablePersonaDimensionRow(dimension: dimension)

                    if index < orderedDimensions.count - 1 {
                        Divider()
                            .overlay(LovableResultStyle.primaryStart.opacity(0.10))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.86), lineWidth: 1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
    }
}

private struct LovablePersonaDimensionRow: View {
    let dimension: PersonaDimension

    private var position: CGFloat {
        switch dimension.direction {
        case .left: 0
        case .centerLeft: 0.25
        case .center: 0.5
        case .centerRight: 0.75
        case .right: 1
        }
    }

    private var emphasis: (size: CGFloat, opacity: Double) {
        switch dimension.strength {
        case .weak: (8, 0.56)
        case .medium: (10, 0.72)
        case .strong: (12, 0.90)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dimension.name)
                .nekoText(.body)
                .fontWeight(.semibold)
                .foregroundStyle(LovableResultStyle.ink)

            HStack(spacing: 10) {
                Text(dimension.leftLabel)
                    .nekoText(.support)
                    .foregroundStyle(LovableResultStyle.muted)
                    .lineLimit(1)
                    .frame(width: 64, alignment: .leading)

                GeometryReader { proxy in
                    let markerSize = emphasis.size
                    let travel = max(0, proxy.size.width - markerSize)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(LovableResultStyle.primaryStart.opacity(0.14))
                            .frame(height: 6)

                        Circle()
                            .fill(LovableResultStyle.primaryStart.opacity(emphasis.opacity))
                            .frame(width: markerSize, height: markerSize)
                            .offset(x: travel * position)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 14)

                Text(dimension.rightLabel)
                    .nekoText(.support)
                    .foregroundStyle(LovableResultStyle.muted)
                    .lineLimit(1)
                    .frame(width: 64, alignment: .trailing)
            }
        }
        .frame(height: 72, alignment: .center)
    }
}

private struct LovableCatInsightSection: View {
    let catName: String
    let insights: PersonaInsights

    private var items: [LovableResultInsight] {
        [
            LovableResultInsight(number: "01", title: insights.misunderstanding.title, text: insights.misunderstanding.conclusion),
            LovableResultInsight(number: "02", title: insights.affection.title, text: insights.affection.conclusion),
            LovableResultInsight(number: "03", title: insights.relationship.title, text: insights.relationship.conclusion),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("原来\(catName)是这样的猫")
                .nekoText(.moduleTitle)
                .foregroundStyle(LovableResultStyle.ink)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, insight in
                    HStack(alignment: .top, spacing: 12) {
                        Text(insight.number)
                            .nekoText(.badge)
                            .foregroundStyle(LovableResultStyle.primaryStart.opacity(0.78))
                            .frame(width: 24, alignment: .leading)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(insight.title)
                                .nekoText(.button)
                                .foregroundStyle(LovableResultStyle.ink)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(insight.text)
                                .nekoText(.body)
                                .foregroundStyle(LovableResultStyle.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)

                    if index < items.count - 1 {
                        Divider()
                            .overlay(LovableResultStyle.primaryStart.opacity(0.10))
                    }
                }
            }
            .padding(.horizontal, 20)
            .background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.86), lineWidth: 1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
    }
}

private struct LovableBondSummarySection: View {
    let catName: String
    let quote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(catName)和你的关系")
                .nekoText(.moduleTitle)
                .foregroundStyle(LovableResultStyle.ink)

            Text(quote)
                .nekoText(.cardTitle)
                .foregroundStyle(LovableResultStyle.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.86), lineWidth: 1)
                }
        }
        .padding(.horizontal, 24)
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
                    .nekoText(.button)
                    .foregroundStyle(Color(red: 0.500, green: 0.320, blue: 0.590))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
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
                    .nekoText(.button)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
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
                    .nekoText(.badge)
                    .foregroundStyle(LovableResultStyle.ink)
                    .padding(.top, 16)

                HStack(spacing: 0) {
                    LovableShareItem(label: "微信好友", emoji: "💬", colors: [Color(red: 0.420, green: 0.831, blue: 0.420), Color(red: 0.169, green: 0.722, blue: 0.361)], isDisabled: busy, action: onWeChat)
                    LovableShareItem(label: "朋友圈", emoji: "🌈", colors: [Color(red: 1.000, green: 0.702, blue: 0.420), Color(red: 1.000, green: 0.420, blue: 0.710)], isDisabled: busy, action: onMoments)
                    LovableShareItem(label: "保存图片", emoji: "⬇️", colors: [LovableResultStyle.primaryStart, LovableResultStyle.primaryEnd], isDisabled: busy, action: onSaveImage)
                }
                .padding(.top, 20)

                Button("取消", action: onClose)
                    .nekoText(.button)
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
                    .nekoText(.moduleTitle)
                    .frame(width: 48, height: 48)
                    .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)

                Text(label)
                    .nekoText(.button)
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

struct LovableResultShareImage: View {
    let catName: String
    let avatarImage: UIImage?
    let personaType: String
    let personaMbti: String
    let coreDescription: String
    let dimensions: [PersonaDimension]
    let insights: PersonaInsights
    let bondSummary: BondSummary
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LovableResultHero(
                catName: catName,
                avatarImage: avatarImage,
                avatarURL: nil,
                avatarObjectKey: nil,
                personaType: personaType,
                personaMbti: personaMbti,
                coreDescription: coreDescription,
                contentWidth: width
            )
            .overlay(alignment: .top) {
                HStack {
                    Color.clear
                        .frame(width: 36, height: 36)

                    Spacer()

                    Text("喵一下")
                        .nekoText(.tiny)
                        .foregroundStyle(Color(red: 0.545, green: 0.410, blue: 0.595))

                    Spacer()

                    Color.clear
                        .frame(width: 36, height: 36)
                }
                .padding(.horizontal, 20)
                .padding(.top, 50)
            }

            LovablePersonaDimensionsSection(
                catName: catName,
                dimensions: dimensions
            )

            LovableCatInsightSection(
                catName: catName,
                insights: insights
            )

            LovableBondSummarySection(
                catName: catName,
                quote: bondSummary.quote
            )

            Text("喵一下 · 读懂它的小世界")
                .nekoText(.tiny)
                .foregroundStyle(LovableResultStyle.label.opacity(0.72))
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
                .padding(.bottom, 28)
        }
        .frame(width: width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
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
                            .nekoText(.pageTitle)
                        Text("照片暂时无法显示")
                            .nekoText(.caption)
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
