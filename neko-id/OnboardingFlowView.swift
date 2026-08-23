//
//  OnboardingFlowView.swift
//  neko-id
//
//  Created by Codex on 2026/8/15.
//

import PhotosUI
import SwiftUI
import UIKit

private enum NativeOnboardingStep: Int, CaseIterable {
    case welcome
    case profile
    case video
    case quiz
    case analyzing
    case result
}

struct NativeOnboardingFlowView: View {
    @EnvironmentObject private var appModel: NekoAppModel
    @State private var step: NativeOnboardingStep = .welcome
    @State private var draft = CatProfileDraft()
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var avatarImageData: Data?
    @State private var avatarPreviewImage: UIImage?
    @State private var selectedVideoItems: [PhotosPickerItem] = []
    @State private var videoClips: [OnboardingVideoClip] = []
    @State private var quizAnswers: [Int: QuizChoice] = [:]
    @State private var personaPreview: CatPersonaResult?
    @State private var analysisProgress = 0.0
    @State private var isAnalyzing = false
    @State private var isValidatingProfile = false
    @State private var isValidatingVideo = false
    @State private var didHydrateExistingProfile = false
    @State private var pendingSaveAfterLogin = false

    var body: some View {
        ZStack {
            NekoOnboardingBackground()

            Group {
                switch step {
                case .welcome:
                    OnboardingWelcomeScreen(
                        onExit: appModel.catProfile == nil ? nil : {
                            appModel.cancelOnboardingIfPossible()
                        },
                        onStart: {
                            goForward()
                        }
                    )
                case .profile:
                    OnboardingProfileScreen(
                        draft: $draft,
                        selectedAvatarItem: $selectedAvatarItem,
                        avatarPreviewImage: avatarPreviewImage,
                        avatarRemoteURL: appModel.catProfile?.avatarURL,
                        avatarRemoteObjectKey: appModel.catProfile?.avatarObjectKey,
                        isValidating: isValidatingProfile,
                        onNext: validateProfileAndContinue,
                        onBack: goBack
                    )
                case .video:
                    OnboardingVideoScreen(
                        selectedVideoItems: $selectedVideoItems,
                        videoClips: $videoClips,
                        isValidating: isValidatingVideo,
                        onNext: validateVideoAndContinue,
                        onBack: goBack
                    )
                case .quiz:
                    OnboardingQuizScreen(
                        answers: $quizAnswers,
                        onNext: startAnalyzing,
                        onSkip: startAnalyzing,
                        onBack: goBack
                    )
                case .analyzing:
                    OnboardingAnalyzingScreen(
                        progress: analysisProgress,
                        avatarImage: avatarPreviewImage,
                        onBack: goBack
                    )
                case .result:
                    OnboardingResultScreen(
                        draft: draft,
                        avatarImage: avatarPreviewImage,
                        videoCount: videoClips.count,
                        persona: personaPreview,
                        isSaving: appModel.isBusy,
                        onSave: saveResult,
                        onRestartAnalysis: startAnalyzing,
                        onBack: goBack
                    )
                }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 0)

            if appModel.isBusy {
                ProgressView()
                    .tint(NekoTheme.soulViolet)
                    .padding(18)
                    .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .nekoEdgeSwipeBack(isEnabled: canEdgeSwipeBack) {
            handleEdgeSwipeBack()
        }
        .onAppear {
            hydrateExistingProfileForRetest()
        }
        .onChange(of: selectedAvatarItem) { _, item in
            Task { await loadAvatar(from: item) }
        }
        .onChange(of: selectedVideoItems) { _, items in
            Task { await loadVideos(from: items) }
        }
        .onChange(of: step) { _, newStep in
            guard newStep == .analyzing else { return }
            Task { await runAnalysis() }
        }
        .onChange(of: appModel.session?.accessToken) { _, accessToken in
            guard accessToken != nil, pendingSaveAfterLogin else { return }
            pendingSaveAfterLogin = false
            saveResult()
        }
    }

    private var canEdgeSwipeBack: Bool {
        guard !appModel.isBusy, !isAnalyzing, !isValidatingProfile, !isValidatingVideo else {
            return false
        }
        return step.rawValue > NativeOnboardingStep.welcome.rawValue || appModel.catProfile != nil
    }

    private func handleEdgeSwipeBack() {
        if step.rawValue > NativeOnboardingStep.welcome.rawValue {
            goBack()
        } else if appModel.catProfile != nil {
            appModel.cancelOnboardingIfPossible()
        }
    }

    private func goForward() {
        guard let next = NativeOnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func goBack() {
        if step == .result {
            step = .quiz
            return
        }

        guard step.rawValue > 0, let previous = NativeOnboardingStep(rawValue: step.rawValue - 1) else {
            return
        }
        step = previous == .analyzing ? .quiz : previous
    }

    private func validateProfileAndContinue() {
        guard !isValidatingProfile else { return }

        guard let avatarImageData else {
            if appModel.catProfile?.avatarURL != nil || appModel.catProfile?.avatarObjectKey != nil {
                step = .video
                return
            }
            appModel.errorMessage = "先选择一张猫咪正脸照片吧。"
            return
        }

        guard draft.isValid else {
            appModel.errorMessage = "先填一个猫咪名字吧，最多 40 个字。"
            return
        }

        Task {
            await validateProfileImage(avatarImageData)
        }
    }

    private func validateVideoAndContinue() {
        guard !isValidatingVideo else { return }

        guard !videoClips.isEmpty else {
            appModel.errorMessage = "需要选择至少 1 段猫咪日常视频，才能继续分析。"
            return
        }

        guard let thumbnailData = videoClips.compactMap(\.thumbnailData).first else {
            appModel.noticeMessage = "这段视频无法提取封面，先继续完成问答。"
            step = .quiz
            return
        }

        Task {
            await validateVideoThumbnail(thumbnailData)
        }
    }

    private func startAnalyzing() {
        personaPreview = nil
        analysisProgress = 0
        step = .analyzing
    }

    private func saveResult() {
        guard let personaPreview else {
            appModel.errorMessage = "人格结果还没生成完成，请稍等一下。"
            return
        }

        guard appModel.session != nil else {
            pendingSaveAfterLogin = true
            appModel.requestLogin(message: "保存猫咪人格档案前需要先登录。登录后，这份测试结果会绑定到你的账号。")
            return
        }

        Task {
            await appModel.completeOnboarding(
                draft: draft,
                avatarImageData: avatarImageData,
                quizAnswers: quizAnswers,
                persona: personaPreview,
                videoCount: videoClips.count
            )
        }
    }

    private func hydrateExistingProfileForRetest() {
        guard !didHydrateExistingProfile, let profile = appModel.catProfile else { return }
        didHydrateExistingProfile = true
        draft = CatProfileDraft(profile: profile)

        guard avatarImageData == nil, let url = profile.avatarURL else { return }
        Task { await loadExistingAvatar(from: url) }
    }

    @MainActor
    private func loadExistingAvatar(from url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let prepared = try MediaUploadProcessor.prepareAvatarImage(from: data)
            avatarImageData = prepared.data
            avatarPreviewImage = UIImage(data: prepared.data)
        } catch {
            avatarImageData = nil
        }
    }

    @MainActor
    private func loadAvatar(from item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw NekoMediaError.unsupportedImage
            }

            let prepared = try MediaUploadProcessor.prepareAvatarImage(from: data)
            avatarImageData = prepared.data
            avatarPreviewImage = UIImage(data: prepared.data)
        } catch {
            appModel.errorMessage = userFacingMediaMessage(error)
        }
    }

    @MainActor
    private func loadVideos(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        defer { selectedVideoItems = [] }

        for item in items {
            guard videoClips.count < 3 else {
                appModel.errorMessage = "最多只能选择 3 段视频。"
                break
            }

            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw NekoMediaError.unsupportedVideo
                }

                let clip = try await MediaUploadProcessor.prepareOnboardingVideo(
                    from: data,
                    preferredLabel: "视频 \(videoClips.count + 1)",
                    currentCount: videoClips.count
                )
                videoClips.append(clip)
            } catch {
                appModel.errorMessage = userFacingMediaMessage(error)
            }
        }
    }

    @MainActor
    private func validateProfileImage(_ imageData: Data) async {
        isValidatingProfile = true
        defer { isValidatingProfile = false }

        do {
            let result = try await appModel.detectCatFace(imageData: imageData, mode: .face)
            guard result.isCat else {
                appModel.errorMessage = result.reason ?? "这张照片里没有识别到清晰猫咪正脸，请换一张再试。"
                return
            }

            step = .video
        } catch {
            appModel.errorMessage = userFacingServerMessage(
                error,
                fallback: "猫脸识别失败，请稍后再试或换一张照片。"
            )
        }
    }

    @MainActor
    private func validateVideoThumbnail(_ imageData: Data) async {
        isValidatingVideo = true
        defer { isValidatingVideo = false }

        do {
            let result = try await appModel.detectCatFace(imageData: imageData, mode: .presence)
            guard result.isCat else {
                appModel.errorMessage = result.reason ?? "这段视频封面里没有识别到猫咪，请换一段猫咪日常视频。"
                return
            }

            step = .quiz
        } catch {
            appModel.errorMessage = userFacingServerMessage(
                error,
                fallback: "视频校验失败，请稍后再试或换一段视频。"
            )
        }
    }

    @MainActor
    private func runAnalysis() async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        analysisProgress = 0

        let personaTask = Task {
            try await appModel.generateOnboardingPersona(
                draft: draft,
                quizAnswers: quizAnswers,
                avatarImageData: avatarImageData,
                videoCount: videoClips.count
            )
        }

        for tick in 1...82 {
            try? await Task.sleep(nanoseconds: 36_000_000)
            guard step == .analyzing else {
                personaTask.cancel()
                isAnalyzing = false
                return
            }
            analysisProgress = Double(tick) / 100
        }

        do {
            let generated = try await personaTask.value
            for tick in 83...100 {
                try? await Task.sleep(nanoseconds: 16_000_000)
                analysisProgress = Double(tick) / 100
            }

            personaPreview = generated
            isAnalyzing = false
            try? await Task.sleep(nanoseconds: 260_000_000)
            if step == .analyzing {
                step = .result
            }
        } catch {
            isAnalyzing = false
            appModel.errorMessage = userFacingServerMessage(
                error,
                fallback: "AI 分析暂时失败，请稍后再试。"
            )
            if step == .analyzing {
                step = .quiz
            }
        }
    }

    private func userFacingMediaMessage(_ error: Error) -> String {
        if let description = (error as? LocalizedError)?.errorDescription {
            return description
        }
        return "媒体读取失败，请换一个文件再试。"
    }

    private func userFacingServerMessage(_ error: Error, fallback: String) -> String {
        if let description = (error as? LocalizedError)?.errorDescription, !description.isEmpty {
            return description
        }
        return fallback
    }
}

private enum OnboardingWeb {
    static let ink = Color(red: 0.1975, green: 0.1897, blue: 0.2562)           // oklch(0.32 0.03 290)
    static let muted = Color(red: 0.4928, green: 0.4600, blue: 0.5608)         // oklch(0.58 0.04 300)
    static let label = Color(red: 0.4656, green: 0.4149, blue: 0.5641)         // oklch(0.55 0.06 300)
    static let labelPink = Color(red: 0.5272, green: 0.3845, blue: 0.5598)     // oklch(0.55 0.08 320)
    static let border = Color(red: 0.8863, green: 0.8572, blue: 0.9106)        // oklch(0.9 0.02 310)
    static let creamTop = Color(red: 0.9986, green: 0.9854, blue: 0.9642)      // oklch(0.99 0.008 80)
    static let creamBottom = Color(red: 0.9703, green: 0.9338, blue: 0.9785)   // oklch(0.96 0.018 320)
    static let welcomeMid = Color(red: 0.9913, green: 0.9204, blue: 1.0000)    // oklch(0.96 0.035 320)
    static let welcomeBottom = Color(red: 0.9120, green: 0.9264, blue: 1.0000) // oklch(0.95 0.04 280)
    static let soulViolet = Color(red: 0.7829, green: 0.6484, blue: 0.9415)    // oklch(0.78 0.11 305)
    static let soulPink = Color(red: 0.9892, green: 0.6991, blue: 0.7843)      // oklch(0.84 0.09 0)
    static let soulOpal = Color(red: 0.7160, green: 0.8254, blue: 1.0000)      // oklch(0.86 0.07 260)
    static let activeBar = Color(red: 0.8834, green: 0.6872, blue: 0.9282)     // oklch(0.82 0.1 320)
    static let videoPink = Color(red: 0.9694, green: 0.7106, blue: 0.7853)     // oklch(0.84 0.08 0)
    static let plusStart = Color(red: 0.7011, green: 0.5265, blue: 0.8931)     // oklch(0.70 0.14 305)
    static let plusEnd = Color(red: 0.9195, green: 0.5763, blue: 0.6828)       // oklch(0.76 0.11 0)
    static let questionNumber = Color(red: 0.4870, green: 0.3103, blue: 0.5273)
    static let whitePink = Color(red: 1.0000, green: 0.9665, blue: 1.0000)

    static let creamGradient = LinearGradient(
        colors: [creamTop, creamBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    static let welcomeGradient = LinearGradient(
        colors: [Color(red: 0.999, green: 0.983, blue: 0.954), welcomeMid, welcomeBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    static let ctaGradient = LinearGradient(
        colors: [Color(red: 0.682, green: 0.561, blue: 0.906), Color(red: 0.898, green: 0.667, blue: 0.800)], // #AE8FE7 → #E5AACC
        startPoint: .leading,
        endPoint: .trailing
    )

    static let selectedGradient = LinearGradient(
        colors: [Color(red: 0.780, green: 0.702, blue: 0.949), Color(red: 0.922, green: 0.776, blue: 0.851)], // #C7B3F2 → #EBC6D9
        startPoint: .leading,
        endPoint: .trailing
    )

    static let soulGradient = LinearGradient(
        colors: [Color(red: 0.78, green: 0.67, blue: 0.94), Color(red: 0.99, green: 0.70, blue: 0.78), Color(red: 0.72, green: 0.83, blue: 1.0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct NekoOnboardingBackground: View {
    var body: some View {
        ZStack {
            OnboardingWeb.creamGradient
            Circle()
                .fill(OnboardingWeb.soulPink.opacity(0.32))
                .frame(width: 330, height: 330)
                .blur(radius: 92)
                .position(x: 80, y: 90)
            Circle()
                .fill(OnboardingWeb.soulViolet.opacity(0.30))
                .frame(width: 360, height: 360)
                .blur(radius: 96)
                .position(x: 340, y: 190)
            Circle()
                .fill(OnboardingWeb.soulOpal.opacity(0.28))
                .frame(width: 380, height: 380)
                .blur(radius: 104)
                .position(x: 210, y: 780)
            NekoSparkles(count: 22)
        }
        .ignoresSafeArea()
    }
}

private struct OnboardingWelcomeScreen: View {
    let onExit: (() -> Void)?
    let onStart: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            OnboardingWeb.welcomeGradient.ignoresSafeArea()
            NekoSparkles(count: 36)
            if let onExit {
                WebBackButton(onBack: onExit)
            }

            VStack(spacing: 0) {
                OnboardingHeroImage()
                    .padding(.top, 104)

                VStack(spacing: 0) {
                    Text("N E K O . I D")
                        .font(.system(size: NekoTypography.web(11), weight: .regular))
                        .tracking(6.1)
                        .foregroundStyle(OnboardingWeb.labelPink)

                    (
                        Text("读懂它的")
                            .foregroundColor(OnboardingWeb.ink)
                        +
                        Text("小世界")
                            .foregroundColor(OnboardingWeb.soulPink)
                            .italic()
                    )
                    .font(.system(size: 28, weight: .light))
                    .padding(.top, 12)

                    Text("AI 将通过照片、视频和行为分析\n生成专属于它的人格档案")
                        .font(.system(size: NekoTypography.web(12), weight: .regular))
                        .foregroundStyle(OnboardingWeb.muted)
                        .lineSpacing(6)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 28)
                .padding(.top, 40)

                Spacer(minLength: 24)

                VStack(spacing: 0) {
                    Button {
                        onStart()
                    } label: {
                        HStack(spacing: 8) {
                            Text("开始创建猫咪人格档案")
                                .tracking(1)
                            Text("✨")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 10)
            }
        }
    }
}

private struct OnboardingHeroImage: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [OnboardingWeb.soulPink.opacity(0.68), OnboardingWeb.soulViolet.opacity(0.34), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 115
                    )
                )
                .blur(radius: 28)
                .frame(width: 230, height: 230)

            Circle()
                .stroke(OnboardingWeb.soulPink.opacity(0.55), lineWidth: 1)
                .frame(width: 178, height: 178)
            Circle()
                .stroke(OnboardingWeb.soulOpal.opacity(0.45), lineWidth: 1)
                .frame(width: 134, height: 134)

            Image("neko-hero")
                .resizable()
                .scaledToFill()
                .frame(width: 150, height: 150)
                .clipShape(Circle())
                .padding(6)
                .background(.white, in: Circle())
                .shadow(color: OnboardingWeb.soulViolet.opacity(0.32), radius: 30, x: 0, y: 18)

            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)
                    .shadow(color: OnboardingWeb.soulPink.opacity(0.75), radius: 6)
                    .offset(x: CGFloat(cos(Double(index) * 2.094)) * 118, y: CGFloat(sin(Double(index) * 2.094)) * 118)
            }
        }
        .frame(width: 230, height: 230)
    }
}

private struct OnboardingProfileScreen: View {
    @Binding var draft: CatProfileDraft
    @Binding var selectedAvatarItem: PhotosPickerItem?
    let avatarPreviewImage: UIImage?
    let avatarRemoteURL: URL?
    let avatarRemoteObjectKey: String?
    let isValidating: Bool
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScrollableStep(
            step: 1,
            title: "上传猫咪正脸照片",
            subtitle: "头像会用于生成人格档案 · 图片不超过 10MB",
            onBack: onBack
        ) {
            VStack(spacing: 0) {
                PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [OnboardingWeb.soulPink.opacity(0.55), .clear],
                                    center: .center,
                                    startRadius: 12,
                                    endRadius: 88
                                )
                            )
                            .blur(radius: 22)
                            .frame(width: 170, height: 170)

                        Circle()
                            .stroke(OnboardingWeb.activeBar.opacity(0.60), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                            .frame(width: 170, height: 170)

                        FlowAvatarView(
                            image: avatarPreviewImage,
                            size: 144,
                            remoteURL: avatarRemoteURL,
                            remoteObjectKey: avatarRemoteObjectKey,
                            placeholderTitle: "上传正脸",
                            placeholderSubtitle: "JPG / PNG",
                            placeholderIcon: "photo.badge.plus"
                        )
                        .padding(13)

                        Text("＋")
                            .font(.system(size: NekoTypography.web(17), weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                LinearGradient(colors: [OnboardingWeb.plusStart, OnboardingWeb.plusEnd], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: Circle()
                            )
                            .shadow(color: OnboardingWeb.soulViolet.opacity(0.42), radius: 10, x: 0, y: 5)
                            .offset(x: 4, y: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 178)
                }
                .buttonStyle(.plain)

                Text("点击上传 · JPG / PNG")
                    .font(.system(size: NekoTypography.web(10), weight: .regular))
                    .tracking(3.0)
                    .foregroundStyle(OnboardingWeb.label)
                    .padding(.top, 12)

                OnboardingCard(cornerRadius: 24, topPadding: 20) {
                    OnboardingFieldTitle("猫咪名称")
                    HStack(spacing: 8) {
                        TextField("它叫什么名字呀～", text: $draft.name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: NekoTypography.web(14), weight: .medium))
                            .foregroundStyle(OnboardingWeb.ink)
                            .onChange(of: draft.name) { _, value in
                                draft.name = String(value.prefix(12))
                            }
                        Text("\(draft.trimmedName.count) / 12")
                            .font(.system(size: NekoTypography.web(11), weight: .regular))
                            .foregroundStyle(OnboardingWeb.label)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(.white.opacity(0.70), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                OnboardingCard(cornerRadius: 24, topPadding: 12) {
                    OnboardingFieldTitle("性别")
                    HStack(spacing: 10) {
                        ChoiceChip(title: "小公猫", subtitle: nil, isSelected: draft.gender == .male) {
                            draft.gender = .male
                        }
                        ChoiceChip(title: "小母猫", subtitle: nil, isSelected: draft.gender == .female) {
                            draft.gender = .female
                        }
                    }
                }

                OnboardingCard(cornerRadius: 24, topPadding: 12) {
                    OnboardingFieldTitle("年龄阶段")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(CatAgeStage.allCases) { stage in
                            ChoiceChip(
                                title: stage.rawValue,
                                subtitle: subtitle(for: stage),
                                isSelected: draft.ageStage == stage
                            ) {
                                draft.ageStage = stage
                            }
                        }
                    }
                }
            }
        } footer: {
            Button {
                onNext()
            } label: {
                HStack(spacing: 8) {
                    if isValidating {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isValidating ? "识别中…" : "继续")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .disabled(isValidating)
        }
    }

    private func subtitle(for stage: CatAgeStage) -> String {
        switch stage {
        case .kitten:
            return "0 – 1 岁"
        case .young:
            return "1 – 4 岁"
        case .adult:
            return "4 – 8 岁"
        case .senior:
            return "8 岁+"
        }
    }
}

private struct OnboardingVideoScreen: View {
    @Binding var selectedVideoItems: [PhotosPickerItem]
    @Binding var videoClips: [OnboardingVideoClip]
    let isValidating: Bool
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScrollableStep(
            step: 2,
            title: "上传猫咪视频",
            subtitle: "上传 1～3 个视频展示猫咪日常，单个不超过 100MB",
            onBack: onBack
        ) {
            VStack(alignment: .leading, spacing: 0) {
                PhotosPicker(
                    selection: $selectedVideoItems,
                    maxSelectionCount: max(1, 3 - videoClips.count),
                    matching: .videos
                ) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(.white.opacity(0.60))
                            .overlay {
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .stroke(OnboardingWeb.activeBar.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                            }

                        Circle()
                            .fill(OnboardingWeb.activeBar.opacity(0.36))
                            .frame(width: 150, height: 150)
                            .blur(radius: 34)
                            .offset(x: -112, y: -88)

                        Circle()
                            .fill(OnboardingWeb.soulOpal.opacity(0.28))
                            .frame(width: 150, height: 150)
                            .blur(radius: 34)
                            .offset(x: 110, y: 86)

                        VStack(spacing: 0) {
                            Text("▶")
                                .font(.system(size: 23, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 64, height: 64)
                                .background(
                                    LinearGradient(colors: [OnboardingWeb.activeBar, OnboardingWeb.videoPink], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: Circle()
                                )
                                .shadow(color: OnboardingWeb.soulViolet.opacity(0.34), radius: 20, x: 0, y: 10)
                                .padding(.top, 4)

                            Text(videoClips.count >= 3 ? "最多只能上传 3 个视频" : "轻触上传视频")
                                .font(.system(size: NekoTypography.web(14), weight: .medium))
                                .foregroundStyle(OnboardingWeb.ink)
                                .padding(.top, 12)

                            Text("每次 1 个 · 可添加 3 次 · ≤ 100MB")
                                .font(.system(size: NekoTypography.web(11), weight: .regular))
                                .foregroundStyle(OnboardingWeb.label)
                                .padding(.top, 5)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 200)
                }
                .buttonStyle(.plain)
                .disabled(videoClips.count >= 3)

                if !videoClips.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("已上传 · \(videoClips.count) / 3")
                                .font(.system(size: NekoTypography.web(10), weight: .regular))
                                .tracking(4)
                                .foregroundStyle(OnboardingWeb.label)
                            Spacer()
                            if videoClips.count < 3 {
                                Text("可继续添加 \(3 - videoClips.count) 个")
                                    .font(.system(size: NekoTypography.web(10)))
                                    .foregroundStyle(OnboardingWeb.label)
                            }
                        }
                        .padding(.horizontal, 1)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(videoClips) { clip in
                                    VideoClipCard(clip: clip) {
                                        videoClips.removeAll { $0.id == clip.id }
                                    }
                                    .frame(width: 142)
                                }
                            }
                            .padding(.horizontal, 1)
                            .padding(.bottom, 2)
                        }
                    }
                    .padding(.top, 16)
                }

                OnboardingCard(cornerRadius: 20, topPadding: 18) {
                    OnboardingFieldTitle("建议捕捉")
                    HStack(spacing: 8) {
                        CaptureTip(emoji: "🐾", title: "走动")
                        CaptureTip(emoji: "🔊", title: "叫声")
                        CaptureTip(emoji: "🎾", title: "玩耍")
                    }
                    HStack(spacing: 8) {
                        Text("💡")
                        Text("越自然的日常画面，AI 越能感受到它的性格")
                            .font(.system(size: NekoTypography.web(10)))
                            .foregroundStyle(OnboardingWeb.labelPink)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(red: 0.97, green: 0.93, blue: 0.98).opacity(0.80), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        } footer: {
            Button {
                onNext()
            } label: {
                HStack(spacing: 8) {
                    if isValidating {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isValidating ? "识别中…" : "继续")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .disabled(isValidating)
        }
    }
}

private struct OnboardingQuizScreen: View {
    @Binding var answers: [Int: QuizChoice]
    let onNext: () -> Void
    let onSkip: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScrollableStep(
            step: 3,
            title: "行为小测试",
            subtitle: "帮助 AI 更准确理解它（可跳过）",
            onBack: onBack,
            skipAction: onSkip
        ) {
            VStack(spacing: 12) {
                ForEach(QuizQuestion.onboarding) { question in
                    OnboardingCard(cornerRadius: 22, topPadding: 0) {
                        HStack(alignment: .center, spacing: 8) {
                            Text("\(question.id + 1)")
                                .font(.system(size: NekoTypography.web(10), weight: .medium))
                                .foregroundStyle(OnboardingWeb.questionNumber)
                                .frame(width: 20, height: 20)
                                .background(Color(red: 0.984, green: 0.904, blue: 1.0), in: Circle())

                            Text(question.question)
                                .font(.system(size: NekoTypography.web(12.5), weight: .medium))
                                .foregroundStyle(OnboardingWeb.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        HStack(spacing: 8) {
                            QuizOptionButton(
                                label: "A",
                                text: question.optionA,
                                active: answers[question.id] == .a
                            ) {
                                toggleAnswer(question.id, .a)
                            }

                            QuizOptionButton(
                                label: "B",
                                text: question.optionB,
                                active: answers[question.id] == .b
                            ) {
                                toggleAnswer(question.id, .b)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
        } footer: {
            VStack(spacing: 10) {
                Button {
                    onNext()
                } label: {
                    HStack(spacing: 8) {
                        Text("好了，开始解析")
                        Text("✨")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())

                Text("AI 将结合测试结果，\n生成更准确的人格分析")
                    .font(.system(size: NekoTypography.web(10.5), weight: .regular))
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(OnboardingWeb.muted)
            }
        }
    }

    private func toggleAnswer(_ id: Int, _ choice: QuizChoice) {
        answers[id] = answers[id] == choice ? nil : choice
    }
}

private struct OnboardingAnalyzingScreen: View {
    let progress: Double
    let avatarImage: UIImage?
    let onBack: () -> Void

    private let steps = [
        "正在识别行为模式",
        "正在分析情绪表达",
        "正在建立立体人格模型",
        "正在推测 MBTI 倾向",
        "正在生成内心独白",
        "正在整合人格特征",
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            OnboardingWeb.welcomeGradient.ignoresSafeArea()
            NekoSparkles(count: 34)
            WebBackButton(onBack: onBack)

            VStack(spacing: 0) {
                Text("A I · A N A L Y Z I N G")
                    .font(.system(size: NekoTypography.web(10), weight: .regular))
                    .tracking(4.5)
                    .foregroundStyle(OnboardingWeb.labelPink)
                    .padding(.top, 64)

                Text("AI 分析中")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(OnboardingWeb.ink)
                    .padding(.top, 8)

                Text("正在构建属于它的人格画像")
                    .font(.system(size: NekoTypography.web(12), weight: .regular))
                    .foregroundStyle(OnboardingWeb.muted)
                    .padding(.top, 3)

                AnalysisRing(progress: progress, avatarImage: avatarImage)
                    .padding(.top, 28)

                VStack(spacing: 8) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                        let activeIndex = min(steps.count - 1, Int(progress * Double(steps.count)))
                        AnalysisStepRow(title: title, isActive: index == activeIndex, isDone: index < activeIndex)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 34)

                Spacer()

                Text("每只猫，\n都有独一无二的灵魂")
                    .font(.system(size: NekoTypography.web(12), weight: .regular))
                    .lineSpacing(5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(OnboardingWeb.muted)
                    .padding(.bottom, 26)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct OnboardingResultScreen: View {
    let draft: CatProfileDraft
    let avatarImage: UIImage?
    let videoCount: Int
    let persona: CatPersonaResult?
    let isSaving: Bool
    let onSave: () -> Void
    let onRestartAnalysis: () -> Void
    let onBack: () -> Void
    @State private var shareOpen = false

    var body: some View {
        ZStack {
            OnboardingWeb.welcomeGradient.ignoresSafeArea()
            NekoSparkles(count: 22)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ResultTopBar(onBack: onBack) {
                        shareOpen = true
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 50)

                    ResultHeroCard(draft: draft, avatarImage: avatarImage, persona: safePersona)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    ResultSection(title: "AI 内心独白", hint: "INNER · VOICE", tone: true) {
                        ZStack(alignment: .topLeading) {
                            Text("“")
                                .font(.system(size: 34, weight: .regular, design: .serif))
                                .foregroundStyle(OnboardingWeb.soulViolet.opacity(0.35))
                                .offset(x: -6, y: -12)
                            Text(safePersona.monologue)
                                .font(.system(size: NekoTypography.web(14), weight: .light))
                                .italic()
                                .lineSpacing(8)
                                .foregroundStyle(OnboardingWeb.ink)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 14)
                                .padding(.top, 4)
                            Text("”")
                                .font(.system(size: 34, weight: .regular, design: .serif))
                                .foregroundStyle(OnboardingWeb.soulViolet.opacity(0.35))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                .offset(x: 4, y: 8)
                        }
                        Text("—— \(draft.trimmedName) · by NEKO")
                            .font(.system(size: NekoTypography.web(10), weight: .regular))
                            .tracking(2.5)
                            .foregroundStyle(OnboardingWeb.label)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, 12)
                    }

                    ResultSection(title: "AI 人格解析", hint: "PERSONALITY · ANALYSIS") {
                        Text(safePersona.analysis)
                            .font(.system(size: NekoTypography.web(12.5), weight: .regular))
                            .lineSpacing(7)
                            .foregroundStyle(OnboardingWeb.ink.opacity(0.86))
                    }

                    ResultSection(title: "它眼中的你", hint: "YOUR · ROLE") {
                        Text(safePersona.ownerRole)
                            .font(.system(size: NekoTypography.web(12.5), weight: .regular))
                            .lineSpacing(7)
                            .foregroundStyle(OnboardingWeb.ink.opacity(0.86))
                        HStack(spacing: 6) {
                            ForEach(["温柔", "安全感", "可信", "陪伴者"], id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: NekoTypography.web(10), weight: .regular))
                                    .tracking(1)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(OnboardingWeb.selectedGradient, in: Capsule())
                            }
                        }
                        .padding(.top, 10)
                    }

                    ResultSection(title: "个性画像", hint: "PERSONALITY · PORTRAIT") {
                        HStack(spacing: 8) {
                            ForEach(Array(safePersona.traits.prefix(3))) { trait in
                                TraitRing(trait: trait)
                            }
                        }
                    }

                    ResultSection(title: "人格标签", hint: "TAGS · 06", actionTitle: "查看全部 ›") {
                        FlowWrap(items: Array(safePersona.tags.prefix(6)))
                    }

                    ResultSection(title: "AI 观察依据", hint: "WHY · AI · THINKS · SO") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("最近 30 天观察")
                                .font(.system(size: NekoTypography.web(10.5), weight: .regular))
                                .tracking(1.2)
                                .foregroundStyle(OnboardingWeb.label)

                            ForEach(safePersona.observations.prefix(4)) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.label)
                                        .font(.system(size: NekoTypography.web(10), weight: .regular))
                                        .tracking(2.2)
                                        .foregroundStyle(OnboardingWeb.label)
                                    Text(item.value)
                                        .font(.system(size: NekoTypography.web(12), weight: .medium))
                                        .lineSpacing(5)
                                        .foregroundStyle(OnboardingWeb.questionNumber)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(OnboardingWeb.border.opacity(0.70), lineWidth: 1)
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("AI 发现")
                                    .font(.system(size: NekoTypography.web(10), weight: .regular))
                                    .tracking(3.0)
                                    .foregroundStyle(OnboardingWeb.labelPink)
                                Text("它更倾向于观察后行动，因此形成明显的观察型人格特征。")
                                    .font(.system(size: NekoTypography.web(12), weight: .regular))
                                    .lineSpacing(6)
                                    .foregroundStyle(OnboardingWeb.ink.opacity(0.86))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
                .padding(.bottom, 110)
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button("重新识别") {
                        onRestartAnalysis()
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle())

                    Button {
                        onSave()
                    } label: {
                        Text(isSaving ? "保存中…" : "保存结果")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(isSaving || persona == nil)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .background(OnboardingFooterFade())
            }

            if shareOpen {
                ResultShareSheet {
                    shareOpen = false
                }
            }
        }
    }

    private var safePersona: CatPersonaResult {
        persona ?? PersonaGenerator.generate(
            profile: draft,
            quizAnswers: [:],
            videoCount: videoCount,
            hasAvatar: avatarImage != nil
        )
    }
}

private struct OnboardingScrollableStep<Content: View, Footer: View>: View {
    let step: Int
    let title: String
    let subtitle: String
    let onBack: () -> Void
    let skipAction: (() -> Void)?
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    init(
        step: Int,
        title: String,
        subtitle: String,
        onBack: @escaping () -> Void,
        skipAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.step = step
        self.title = title
        self.subtitle = subtitle
        self.onBack = onBack
        self.skipAction = skipAction
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        StepBar(step: step)
                            .padding(.top, 58)

                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(title)
                                    .font(.system(size: 22, weight: .light))
                                    .foregroundStyle(OnboardingWeb.ink)
                                Spacer()
                                if let skipAction {
                                    Button {
                                        skipAction()
                                    } label: {
                                        Text("跳过 ›")
                                            .font(.system(size: NekoTypography.web(10), weight: .regular))
                                            .tracking(3)
                                            .foregroundStyle(OnboardingWeb.label)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            Text(subtitle)
                                .font(.system(size: NekoTypography.web(12), weight: .regular))
                                .foregroundStyle(OnboardingWeb.muted)
                                .lineSpacing(4)
                                .padding(.top, 6)
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 2)

                        content
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                    }
                    .padding(.bottom, 152)
                }
                .safeAreaInset(edge: .bottom) {
                    footer
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .padding(.bottom, 10)
                        .background(OnboardingFooterFade())
                }
            }

            WebBackButton(onBack: onBack)
        }
    }
}

private struct WebBackButton: View {
    let onBack: () -> Void

    var body: some View {
        Button {
            onBack()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: NekoTypography.web(16), weight: .semibold))
                .foregroundStyle(OnboardingWeb.soulViolet)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.80), in: Circle())
                .shadow(color: OnboardingWeb.soulViolet.opacity(0.18), radius: 15, x: 0, y: 7)
        }
        .buttonStyle(.plain)
        .padding(.leading, 20)
        .padding(.top, 18)
        .zIndex(30)
    }
}

private struct StepBar: View {
    let step: Int

    var body: some View {
        HStack {
            Spacer()
            HStack(spacing: 6) {
                ForEach(1...4, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? OnboardingWeb.activeBar : OnboardingWeb.border.opacity(0.75))
                        .frame(width: index <= step ? 24 : 12, height: 4)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }
}

private struct OnboardingCard<Content: View>: View {
    let cornerRadius: CGFloat
    let topPadding: CGFloat
    @ViewBuilder let content: Content

    init(cornerRadius: CGFloat = 24, topPadding: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.topPadding = topPadding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.white.opacity(0.85), OnboardingWeb.whitePink.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.70), lineWidth: 1)
        }
        .shadow(color: OnboardingWeb.soulViolet.opacity(0.10), radius: 16, x: 0, y: 8)
        .padding(.top, topPadding)
    }
}

private struct OnboardingFieldTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: NekoTypography.web(10), weight: .regular))
            .tracking(4)
            .foregroundStyle(OnboardingWeb.label)
    }
}

private struct ChoiceChip: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: NekoTypography.web(13), weight: .medium))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: NekoTypography.web(10), weight: .regular))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isSelected ? .white : OnboardingWeb.ink)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(
                isSelected
                    ? AnyShapeStyle(OnboardingWeb.selectedGradient)
                    : AnyShapeStyle(Color.white.opacity(0.70)),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? .clear : OnboardingWeb.border.opacity(0.60), lineWidth: 1)
            }
            .shadow(color: isSelected ? OnboardingWeb.soulViolet.opacity(0.18) : .clear, radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }
}

private struct QuizOptionButton: View {
    let label: String
    let text: String
    let active: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Text(label)
                    .font(.system(size: NekoTypography.web(10), weight: .medium))
                    .frame(width: 20, height: 20)
                    .background(active ? .white.opacity(0.25) : Color(red: 0.95, green: 0.92, blue: 0.98), in: Circle())
                Text(text)
                    .font(.system(size: NekoTypography.web(12), weight: active ? .medium : .regular))
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
            }
            .foregroundStyle(active ? .white : OnboardingWeb.ink)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .padding(.horizontal, 12)
            .background(
                active
                    ? AnyShapeStyle(OnboardingWeb.selectedGradient)
                    : AnyShapeStyle(Color.white.opacity(0.70)),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(active ? .clear : OnboardingWeb.border.opacity(0.55), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct FlowAvatarView: View {
    let image: UIImage?
    let size: CGFloat
    var remoteURL: URL?
    var remoteObjectKey: String? = nil
    var placeholderTitle: String = "上传正脸"
    var placeholderSubtitle: String? = nil
    var placeholderIcon: String = "photo"

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .shadow(color: OnboardingWeb.soulViolet.opacity(0.22), radius: 22, x: 0, y: 12)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                NekoRemoteImageView(
                    remoteURL: remoteURL,
                    objectKey: remoteObjectKey,
                    contentMode: .fill
                ) {
                    fallback
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.92), lineWidth: 3)
        }
    }

    private var fallback: some View {
        ZStack {
            RadialGradient(
                colors: [.white.opacity(0.96), OnboardingWeb.whitePink.opacity(0.92), OnboardingWeb.creamBottom],
                center: UnitPoint(x: 0.5, y: 0.38),
                startRadius: 8,
                endRadius: size * 0.60
            )
            VStack(spacing: 6) {
                Image(systemName: placeholderIcon)
                    .font(.system(size: size * 0.18, weight: .regular))
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.82), in: Circle())
                    .shadow(color: OnboardingWeb.soulViolet.opacity(0.12), radius: 12, x: 0, y: 6)
                Text(placeholderTitle)
                    .font(.system(size: NekoTypography.web(11), weight: .regular))
                    .tracking(2.2)
                if let placeholderSubtitle {
                    Text(placeholderSubtitle)
                        .font(.system(size: NekoTypography.web(9), weight: .regular))
                        .tracking(1.8)
                        .foregroundStyle(OnboardingWeb.muted.opacity(0.75))
                }
            }
            .foregroundStyle(OnboardingWeb.labelPink)
        }
    }
}

private struct VideoClipCard: View {
    let clip: OnboardingVideoClip
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                LinearGradient(colors: [OnboardingWeb.activeBar.opacity(0.70), OnboardingWeb.videoPink.opacity(0.70)], startPoint: .topLeading, endPoint: .bottomTrailing)

                if let data = clip.thumbnailData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text("▶")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }

                LinearGradient(colors: [.clear, .black.opacity(0.36)], startPoint: .center, endPoint: .bottom)

                Text("▶")
                    .font(.system(size: NekoTypography.web(10), weight: .medium))
                    .foregroundStyle(OnboardingWeb.questionNumber)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.85), in: Circle())

                Text(clip.durationLabel)
                    .font(.system(size: NekoTypography.web(9), weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.35), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(7)

                Text(clip.label)
                    .font(.system(size: NekoTypography.web(10), weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: OnboardingWeb.soulViolet.opacity(0.16), radius: 12, x: 0, y: 8)

            Button {
                onRemove()
            } label: {
                Text("×")
                    .font(.system(size: NekoTypography.web(14), weight: .regular))
                    .foregroundStyle(OnboardingWeb.ink)
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.90), in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(6)
        }
    }
}

private struct CaptureTip: View {
    let emoji: String
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            Text(emoji)
                .font(.system(size: 20))
            Text(title)
                .font(.system(size: NekoTypography.web(11), weight: .regular))
                .foregroundStyle(OnboardingWeb.labelPink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: OnboardingWeb.soulViolet.opacity(0.08), radius: 7, x: 0, y: 3)
    }
}

private struct AnalysisRing: View {
    let progress: Double
    let avatarImage: UIImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(colors: [OnboardingWeb.soulPink.opacity(0.46), OnboardingWeb.soulOpal.opacity(0.16), .clear], center: .center, startRadius: 24, endRadius: 106)
                )
                .blur(radius: 28)
                .frame(width: 206, height: 206)
            Circle()
                .stroke(.white.opacity(0.72), lineWidth: 4)
                .frame(width: 184, height: 184)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(OnboardingWeb.selectedGradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 184, height: 184)

            FlowAvatarView(image: avatarImage, size: 154, placeholderTitle: "等待头像", placeholderIcon: "cat")

            Text("\(Int(progress * 100))%")
                .font(.system(size: NekoTypography.web(11), weight: .medium))
                .tracking(2.7)
                .foregroundStyle(OnboardingWeb.questionNumber)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.white.opacity(0.92), in: Capsule())
                .shadow(color: OnboardingWeb.soulViolet.opacity(0.16), radius: 10, x: 0, y: 6)
                .offset(y: 76)
        }
        .frame(width: 212, height: 212)
    }
}

private struct AnalysisStepRow: View {
    let title: String
    let isActive: Bool
    let isDone: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isDone ? OnboardingWeb.soulViolet : isActive ? OnboardingWeb.soulPink : OnboardingWeb.border)
                .frame(width: 8, height: 8)
                .shadow(color: isActive ? OnboardingWeb.soulPink.opacity(0.70) : .clear, radius: 5)

            Text(title + (isActive ? "" : "..."))
                .font(.system(size: NekoTypography.web(12), weight: .regular))
                .foregroundStyle(isDone || isActive ? OnboardingWeb.ink : OnboardingWeb.muted.opacity(0.70))

            Spacer()

            if isDone {
                Text("✓")
                    .font(.system(size: NekoTypography.web(11), weight: .medium))
                    .foregroundStyle(OnboardingWeb.labelPink)
            } else if isActive {
                HStack(spacing: 4) {
                    Circle().frame(width: 4, height: 4)
                    Circle().frame(width: 4, height: 4)
                    Circle().frame(width: 4, height: 4)
                }
                .foregroundStyle(OnboardingWeb.labelPink)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.white.opacity(isActive ? 0.85 : 0.65), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: isActive ? OnboardingWeb.soulViolet.opacity(0.14) : .clear, radius: 10, x: 0, y: 5)
        .scaleEffect(isActive ? 1.01 : 1)
        .opacity(isDone || isActive ? 1 : 0.55)
    }
}

private struct ResultTopBar: View {
    let onBack: () -> Void
    let onShare: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: NekoTypography.web(16), weight: .semibold))
                        .foregroundStyle(OnboardingWeb.labelPink)
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.80), in: Circle())
                        .shadow(color: OnboardingWeb.soulViolet.opacity(0.16), radius: 14, x: 0, y: 7)
                }
                .buttonStyle(.plain)

                Text("N E K O · I D")
                    .font(.system(size: NekoTypography.web(10), weight: .regular))
                    .tracking(5)
                    .foregroundStyle(OnboardingWeb.labelPink)
            }

            Spacer()

            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: NekoTypography.web(17), weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(LinearGradient(colors: [Color(red: 0.714, green: 0.604, blue: 0.937), Color(red: 0.902, green: 0.722, blue: 0.812)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    .shadow(color: OnboardingWeb.soulViolet.opacity(0.32), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ResultHeroCard: View {
    let draft: CatProfileDraft
    let avatarImage: UIImage?
    let persona: CatPersonaResult

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(OnboardingWeb.soulPink.opacity(0.45), lineWidth: 1)
                        .frame(width: 112, height: 112)
                    Circle()
                        .stroke(OnboardingWeb.soulOpal.opacity(0.40), lineWidth: 1)
                        .frame(width: 96, height: 96)
                    FlowAvatarView(image: avatarImage, size: 100, placeholderTitle: "本次头像", placeholderIcon: "cat")
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(draft.trimmedName)
                        .font(.system(size: NekoTypography.web(15), weight: .light))
                        .foregroundStyle(OnboardingWeb.label)

                    Text(persona.type)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 0.659, green: 0.545, blue: 0.918), Color(red: 0.784, green: 0.588, blue: 0.878), Color(red: 0.937, green: 0.686, blue: 0.784)], startPoint: .leading, endPoint: .trailing))
                        .padding(.top, 6)

                    HStack(spacing: 8) {
                        Text("MBTI")
                            .font(.system(size: NekoTypography.web(9), weight: .regular))
                            .tracking(3)
                            .foregroundStyle(OnboardingWeb.label)
                        Text(persona.mbti)
                            .font(.system(size: NekoTypography.web(11.5), weight: .medium))
                            .tracking(1)
                            .foregroundStyle(OnboardingWeb.questionNumber)
                    }
                    .padding(.top, 8)

                    HStack(spacing: 5) {
                        ForEach(Array(persona.tags.prefix(4)), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: NekoTypography.web(9.5), weight: .regular))
                                .tracking(0.8)
                                .foregroundStyle(OnboardingWeb.labelPink)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.white.opacity(0.80), in: Capsule())
                                .overlay {
                                    Capsule().stroke(OnboardingWeb.border.opacity(0.60), lineWidth: 1)
                                }
                        }
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [.white.opacity(0.92), Color(red: 0.98, green: 0.93, blue: 0.98).opacity(0.82), Color(red: 0.96, green: 0.95, blue: 1.0).opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.70), lineWidth: 1)
            }
            .shadow(color: OnboardingWeb.soulViolet.opacity(0.15), radius: 24, x: 0, y: 14)

            HStack(spacing: 4) {
                Text("人格匹配度")
                    .foregroundStyle(OnboardingWeb.label)
                Text("\(persona.matchScore)%")
                    .fontWeight(.semibold)
            }
            .font(.system(size: NekoTypography.web(9.5), weight: .regular))
            .tracking(0.4)
            .foregroundStyle(OnboardingWeb.questionNumber)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.white.opacity(0.80), in: Capsule())
            .overlay {
                Capsule().stroke(OnboardingWeb.border.opacity(0.60), lineWidth: 1)
            }
            .padding(12)
        }
    }
}

private struct ResultSection<Content: View>: View {
    let title: String
    let hint: String
    var tone = false
    var actionTitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: NekoTypography.web(13), weight: .medium))
                        .foregroundStyle(OnboardingWeb.ink)
                    Text(hint)
                        .font(.system(size: NekoTypography.web(8), weight: .regular))
                        .tracking(2.4)
                        .foregroundStyle(OnboardingWeb.labelPink)
                }
                Spacer()
                if let actionTitle {
                    Text(actionTitle)
                        .font(.system(size: NekoTypography.web(10), weight: .regular))
                        .tracking(0.8)
                        .foregroundStyle(OnboardingWeb.questionNumber)
                }
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            tone
                ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.985, green: 0.926, blue: 1.0).opacity(0.88), Color(red: 0.958, green: 0.944, blue: 1.0).opacity(0.84)], startPoint: .topLeading, endPoint: .bottomTrailing))
                : AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.88), OnboardingWeb.whitePink.opacity(0.70)], startPoint: .top, endPoint: .bottom)),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.70), lineWidth: 1)
        }
        .shadow(color: OnboardingWeb.soulViolet.opacity(0.10), radius: 15, x: 0, y: 8)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

private struct TraitRing: View {
    let trait: PersonaTrait

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color(red: 0.933, green: 0.902, blue: 0.973), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(trait.value) / 100)
                    .stroke(OnboardingWeb.selectedGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text("\(trait.value)%")
                        .font(.system(size: NekoTypography.web(15), weight: .semibold))
                        .foregroundStyle(OnboardingWeb.questionNumber)
                    Text(traitIcon(for: trait.label))
                        .font(.system(size: NekoTypography.web(11)))
                }
            }
            .frame(width: 72, height: 72)

            Text(trait.label)
                .font(.system(size: NekoTypography.web(11), weight: .regular))
                .foregroundStyle(OnboardingWeb.ink.opacity(0.80))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity)
    }

    private func traitIcon(for label: String) -> String {
        if label.contains("粘") { return "🐾" }
        if label.contains("独") { return "🏠" }
        if label.contains("奇") { return "🔍" }
        return "✦"
    }
}

private struct FlowWrap: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 7, rowSpacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Text(item)
                    .font(.system(size: NekoTypography.web(11), weight: .regular))
                    .tracking(0.5)
                    .foregroundStyle(index % 2 == 0 ? OnboardingWeb.questionNumber : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(index % 2 == 0 ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(OnboardingWeb.selectedGradient), in: Capsule())
                    .overlay {
                        if index % 2 == 0 {
                            Capsule().stroke(OnboardingWeb.border.opacity(0.65), lineWidth: 1)
                        }
                    }
            }
        }
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    let rowSpacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 16.0, *) {
            AnyLayout(FlowLayoutLayout(spacing: spacing, rowSpacing: rowSpacing)) {
                content
            }
        }
    }
}

private struct FlowLayoutLayout: Layout {
    let spacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct ResultShareSheet: View {
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                Capsule()
                    .fill(OnboardingWeb.border)
                    .frame(width: 40, height: 4)

                Text("分享我的猫人格")
                    .font(.system(size: NekoTypography.web(13), weight: .medium))
                    .foregroundStyle(OnboardingWeb.ink)
                    .padding(.top, 16)

                HStack(spacing: 16) {
                    ShareItem(label: "微信好友", emoji: "💬", colors: [Color(red: 0.42, green: 0.83, blue: 0.42), Color(red: 0.17, green: 0.72, blue: 0.36)])
                    ShareItem(label: "朋友圈", emoji: "🌈", colors: [Color(red: 1.0, green: 0.70, blue: 0.42), Color(red: 1.0, green: 0.42, blue: 0.71)])
                    ShareItem(label: "保存图片", emoji: "⬇️", colors: [Color(red: 0.714, green: 0.604, blue: 0.937), Color(red: 0.902, green: 0.722, blue: 0.812)])
                }
                .padding(.top, 20)

                Button("取消", action: onClose)
                    .font(.system(size: NekoTypography.web(13), weight: .medium))
                    .foregroundStyle(OnboardingWeb.questionNumber)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color(red: 0.96, green: 0.94, blue: 0.98), in: Capsule())
                    .padding(.top, 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 28)
            .background(.white.opacity(0.95), in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
            .shadow(color: OnboardingWeb.ink.opacity(0.20), radius: 25, x: 0, y: -10)
        }
        .zIndex(50)
    }
}

private struct ShareItem: View {
    let label: String
    let emoji: String
    let colors: [Color]

    var body: some View {
        VStack(spacing: 8) {
            Text(emoji)
                .font(.system(size: 22))
                .frame(width: 48, height: 48)
                .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                .shadow(color: OnboardingWeb.ink.opacity(0.16), radius: 10, x: 0, y: 6)
            Text(label)
                .font(.system(size: NekoTypography.web(11.5), weight: .regular))
                .foregroundStyle(OnboardingWeb.ink.opacity(0.80))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct OnboardingFooterFade: View {
    var body: some View {
        LinearGradient(
            colors: [OnboardingWeb.creamBottom.opacity(0.0), OnboardingWeb.creamBottom.opacity(0.92)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: NekoTypography.web(14), weight: .medium))
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(OnboardingWeb.ctaGradient, in: Capsule())
            .shadow(color: OnboardingWeb.soulViolet.opacity(0.26), radius: 18, x: 0, y: 10)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: NekoTypography.web(13), weight: .medium))
            .foregroundStyle(OnboardingWeb.questionNumber)
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(configuration.isPressed ? 0.78 : 1), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color(red: 0.780, green: 0.702, blue: 0.949), lineWidth: 1.5)
            }
            .shadow(color: OnboardingWeb.soulViolet.opacity(0.12), radius: 12, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

#Preview {
    NativeOnboardingFlowView()
        .environmentObject(NekoAppModel())
}
