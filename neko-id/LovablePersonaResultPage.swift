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
        LovablePersonaCopy.title(trimmed(persona.type, fallback: "安静观察型"))
    }

    private var personaMbti: String {
        trimmed(persona.mbti, fallback: "待识别")
    }

    private var monologue: String {
        LovablePersonaCopy.description(
            trimmed(persona.monologue, fallback: "不黏人，但永远会待在离你不远的地方。"),
            fallback: "不黏人，但永远会待在离你不远的地方。"
        )
    }

    private var analysis: String {
        LovablePersonaCopy.description(
            trimmed(persona.analysis, fallback: "我不一定每次都跑向你，但如果你在家，我会睡得更安心。"),
            fallback: "我不一定每次都跑向你，但如果你在家，我会睡得更安心。"
        )
    }

    private var coreDescription: String {
        LovablePersonaCopy.description(
            trimmed(persona.corePersonality ?? "", fallback: analysis),
            fallback: analysis
        )
    }

    private var misunderstanding: String {
        LovablePersonaCopy.insight(
            trimmed(persona.misunderstanding ?? "", fallback: "现有资料还不足以判断你最容易误会它的哪种行为。多记录几次真实互动后，会得到更可靠的答案。"),
            fallback: "现有资料还不足以判断你最容易误会它的哪种行为。多记录几次真实互动后，会得到更可靠的答案。"
        )
    }

    private var loveLanguage: String {
        LovablePersonaCopy.insight(
            trimmed(
                persona.loveLanguageInsight ?? persona.loveLanguage ?? "",
                fallback: "目前还没有足够的行为答案判断它如何表达喜欢，暂时不对它的长期亲密模式下结论。"
            ),
            fallback: "目前还没有足够的行为答案判断它如何表达喜欢，暂时不对它的长期亲密模式下结论。"
        )
    }

    private var ownerRole: String {
        LovablePersonaCopy.insight(
            trimmed(persona.ownerRelationship ?? persona.ownerRole, fallback: "现有资料不足以确定你在它长期关系中的位置，继续相处和记录会比一次测试更可靠。"),
            fallback: "现有资料不足以确定你在它长期关系中的位置，继续相处和记录会比一次测试更可靠。"
        )
    }

    private var personaKeywords: [String] {
        LovablePersonaCopy.tags(persona.tags)
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
                        keywords: personaKeywords,
                        onAvatarImageLoaded: { loadedAvatarImage = $0 }
                    )
                    .frame(height: heroHeight(for: proxy))
                    .overlay(alignment: .top) {
                        SafeAreaTopBar(onBack: onBack)
                            .padding(.horizontal, 20)
                            .padding(.top, proxy.safeAreaInsets.top + 10)
                    }

                    LovableCatInsightSection(
                        catName: displayName,
                        misunderstanding: misunderstanding,
                        loveLanguage: loveLanguage,
                        ownerRole: ownerRole
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

    private func heroHeight(for proxy: GeometryProxy) -> CGFloat {
        min(max(proxy.size.width * 1.38, 548), 650)
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
    private static let labelReplacements: [(String, String)] = [
        ("观察优先", "先观察再靠近"),
        ("保留距离", "不急着靠近"),
        ("心动不动", "想靠近又犹豫"),
        ("小小探长", "会先看清楚"),
        ("小探长", "会先看清楚"),
        ("互动控场王", "喜欢互动"),
        ("眼神发令机", "会用眼神表达"),
        ("眼神施压", "会用眼神表达"),
        ("克制讨关注", "安静等你发现"),
        ("稳态陪伴", "喜欢待在附近"),
        ("精准互动", "表达得很清楚")
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

    static func tags(_ values: [String]) -> [String] {
        var output: [String] = []
        for value in values {
            guard let tag = naturalTag(value), !output.contains(tag) else { continue }
            output.append(tag)
            if output.count == 4 { break }
        }
        for fallback in ["先观察再靠近", "喜欢待在附近", "边界感强", "会用眼神表达"] {
            guard output.count < 4, !output.contains(fallback) else { continue }
            output.append(fallback)
        }
        return output
    }

    private static func naturalTag(_ value: String) -> String? {
        var clean = compact(value)
        for (source, replacement) in labelReplacements where clean.contains(source) {
            clean = clean.replacingOccurrences(of: source, with: replacement)
        }
        clean = clean.replacingOccurrences(of: #"[^一-龥A-Za-z0-9]"#, with: "", options: .regularExpression)
        let count = charCount(clean)
        guard count >= 2, count <= 8, !hasBannedToken(clean), !endsWithJargonSuffix(clean) else {
            return nil
        }
        return clean
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
    @State private var resolvedImage: UIImage?

    private var editorialTitle: EditorialPersonaTitle {
        EditorialPersonaTitle(personaType)
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
        let titleLines = LovablePersonaTitleLayout.lines(for: personaType)

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(1.012, anchor: .topTrailing)
            .offset(photoOffset)
            .clipped()

            // Keep the real photograph dominant while reserving a quiet editorial
            // column for the cover copy. The fade disappears before the cat's face.
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
            .frame(maxWidth: .infinity, alignment: .bottom)

            VStack(alignment: .leading, spacing: 1) {
                Text("CAT\nPROFILE")
                Rectangle()
                    .frame(width: 26, height: 1)
                    .padding(.vertical, 7)
                Text("A Kinder\nWorld\nWith Cats")
                    .nekoText(.tiny)
                    .lineSpacing(1)
            }
            .nekoText(.personaEditorial)
            .tracking(0.8)
            .foregroundStyle(Color(red: 0.40, green: 0.36, blue: 0.58).opacity(0.72))
            .padding(.leading, 24)
            .padding(.top, 108)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(catName)
                        .nekoText(.moduleTitle)
                    Text(personaMbti)
                        .nekoText(.button)
                }
                .foregroundStyle(Color(red: 0.28, green: 0.23, blue: 0.49))
                .lineLimit(1)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(titleLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .nekoText(NekoTypography.personaTitleStyle(for: personaType.count))
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

                LovableHeroTagFlowLayout(horizontalSpacing: 11, verticalSpacing: 10) {
                    ForEach(keywords, id: \.self) { keyword in
                        Text(keyword)
                            .nekoText(.badge)
                            .foregroundStyle(Color(red: 0.500, green: 0.345, blue: 0.595))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.78), in: Capsule())
                            .overlay {
                                Capsule().stroke(.white.opacity(0.72), lineWidth: 0.7)
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

private struct LovableHeroTagFlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = max(proposal.width ?? 0, 1)
        let rows = arrangedRows(maxWidth: maxWidth, subviews: subviews)
        let height = rows.reduce(CGFloat.zero) { partial, row in
            partial + row.height + (partial > 0 ? verticalSpacing : 0)
        }
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrangedRows(maxWidth: max(bounds.width, 1), subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func arrangedRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row(indices: [], width: 0, height: 0)

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let spacing = current.indices.isEmpty ? 0 : horizontalSpacing
            if !current.indices.isEmpty && current.width + spacing + size.width > maxWidth {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width += spacing + size.width
                current.height = max(current.height, size.height)
            }
        }

        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }

    private struct Row {
        var indices: [Subviews.Index]
        var width: CGFloat
        var height: CGFloat
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

private struct LovableCatInsightSection: View {
    let catName: String
    let misunderstanding: String
    let loveLanguage: String
    let ownerRole: String

    private var insights: [LovableResultInsight] {
        [
            LovableResultInsight(number: "01", title: "你可能一直误会它的一件事", text: concise(misunderstanding)),
            LovableResultInsight(number: "02", title: "它表达喜欢的方式", text: concise(loveLanguage)),
            LovableResultInsight(number: "03", title: "在\(catName)眼里，你的位置", text: concise(ownerRole)),
        ]
    }

    private func concise(_ source: String) -> String {
        let normalized = source
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > 58 else { return normalized }

        if let boundary = normalized.prefix(60).lastIndex(where: { "。！？".contains($0) }) {
            let distance = normalized.distance(from: normalized.startIndex, to: boundary)
            if distance >= 34 {
                return String(normalized[...boundary])
            }
        }
        return String(normalized.prefix(56)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LovableResultSectionHeader(title: "原来\(catName)是这样的猫", hint: "CAT · INSIGHT")

            VStack(spacing: 14) {
                ForEach(insights) { insight in
                    VStack(alignment: .leading, spacing: 11) {
                        HStack(alignment: .firstTextBaseline, spacing: 11) {
                            Text(insight.number)
                                .nekoText(.badge)
                                .foregroundStyle(LovableResultStyle.primaryStart.opacity(0.78))

                            Text(insight.title)
                                .nekoText(.cardTitle)
                                .foregroundStyle(Color(red: 0.330, green: 0.285, blue: 0.385))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(insight.text)
                            .nekoText(.body)
                            .foregroundStyle(Color(red: 0.485, green: 0.440, blue: 0.540))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 21)
                    .padding(.vertical, 21)
                    .background(
                        LinearGradient(
                            colors: insight.number == "03"
                                ? [Color(red: 0.992, green: 0.930, blue: 0.980).opacity(0.90), Color(red: 0.955, green: 0.910, blue: 0.995).opacity(0.90)]
                                : [.white.opacity(0.76), Color(red: 1.0, green: 0.970, blue: 0.995).opacity(0.54)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(.white.opacity(0.80), lineWidth: 1)
                    }
                    .shadow(color: LovableResultStyle.primaryStart.opacity(0.07), radius: 12, x: 0, y: 6)
                }
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
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
                        .nekoText(.tiny)
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
                .nekoText(.tiny)
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
