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

    var body: some View {
        ZStack {
            NekoOnboardingBackground()

            Group {
                switch step {
                case .welcome:
                    OnboardingWelcomeScreen {
                        goForward()
                    }
                case .profile:
                    OnboardingProfileScreen(
                        draft: $draft,
                        selectedAvatarItem: $selectedAvatarItem,
                        avatarPreviewImage: avatarPreviewImage,
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

private struct NekoOnboardingBackground: View {
    var body: some View {
        NekoBackground()
    }
}

private struct OnboardingWelcomeScreen: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 44)

            ZStack {
                Circle()
                    .stroke(.white.opacity(0.65), lineWidth: 1)
                    .frame(width: 230, height: 230)
                Circle()
                    .stroke(NekoTheme.softPink.opacity(0.48), lineWidth: 1)
                    .frame(width: 176, height: 176)
                Circle()
                    .fill(.white.opacity(0.72))
                    .frame(width: 154, height: 154)
                    .shadow(color: NekoTheme.soulViolet.opacity(0.20), radius: 30, x: 0, y: 18)

                Image(systemName: "pawprint.fill")
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(
                        NekoTheme.primaryGradient
                    )
            }

            VStack(spacing: 12) {
                Text("N E K O . I D")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(6)
                    .foregroundStyle(NekoTheme.soulViolet)

                Text("读懂它的小世界")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(NekoTheme.ink)

                Text("通过照片、视频和行为问答，生成一份专属于猫咪的人格档案。")
                    .font(.system(size: 14))
                    .foregroundStyle(NekoTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: 300)
            }
            .padding(.top, 34)

            Spacer()

            Button {
                onStart()
            } label: {
                Label("开始创建猫咪人格档案", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
    }
}

private struct OnboardingProfileScreen: View {
    @Binding var draft: CatProfileDraft
    @Binding var selectedAvatarItem: PhotosPickerItem?
    let avatarPreviewImage: UIImage?
    let isValidating: Bool
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        OnboardingScrollableStep(step: 1, title: "上传猫咪正脸照片", subtitle: "头像会用于生成人格档案，图片不超过 10MB。", onBack: onBack) {
            VStack(alignment: .leading, spacing: 18) {
                PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                    VStack(spacing: 12) {
                        FlowAvatarView(image: avatarPreviewImage, size: 168)
                        Text(avatarPreviewImage == nil ? "轻触选择照片" : "照片已选择，可轻触更换")
                            .font(.system(size: 12, weight: .medium))
                            .tracking(1.8)
                            .foregroundStyle(NekoTheme.soulViolet)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                OnboardingCard {
                    OnboardingFieldTitle("猫咪名称")
                    TextField("它叫什么名字呀～", text: $draft.name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .onChange(of: draft.name) { _, value in
                            draft.name = String(value.prefix(40))
                        }
                }

                OnboardingCard {
                    OnboardingFieldTitle("性别")
                    Picker("性别", selection: $draft.gender) {
                        ForEach(CatGender.allCases) { gender in
                            Text(gender.rawValue).tag(gender)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                OnboardingCard {
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
                    Text(isValidating ? "识别猫脸中…" : "继续")
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
            return "0–1 岁"
        case .young:
            return "1–4 岁"
        case .adult:
            return "4–8 岁"
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
        OnboardingScrollableStep(step: 2, title: "上传猫咪视频", subtitle: "选择 1～3 段日常视频；单个不超过 100MB，本轮只用于分析，不长期保存。", onBack: onBack) {
            VStack(alignment: .leading, spacing: 18) {
                PhotosPicker(
                    selection: $selectedVideoItems,
                    maxSelectionCount: max(1, 3 - videoClips.count),
                    matching: .videos
                ) {
                    VStack(spacing: 12) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 50, weight: .light))
                            .foregroundStyle(NekoTheme.soulViolet)
                        Text(videoClips.count >= 3 ? "最多 3 段视频" : "轻触选择视频")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(NekoTheme.ink)
                        Text("建议捕捉走动、叫声、玩耍、靠近等自然片段")
                            .font(.system(size: 12))
                            .foregroundStyle(NekoTheme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 190)
                    .background(.white.opacity(0.54), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(NekoTheme.soulViolet.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                    }
                }
                .disabled(videoClips.count >= 3)

                if !videoClips.isEmpty {
                    OnboardingCard {
                        HStack {
                            OnboardingFieldTitle("已选择 · \(videoClips.count) / 3")
                            Spacer()
                            Text("不上传云端")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(NekoTheme.muted)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(videoClips) { clip in
                                    VideoClipCard(clip: clip) {
                                        videoClips.removeAll { $0.id == clip.id }
                                    }
                                    .frame(width: 132)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                OnboardingCard {
                    OnboardingFieldTitle("建议捕捉")
                    HStack(spacing: 10) {
                        CaptureTip(emoji: "🐾", title: "走动")
                        CaptureTip(emoji: "🔊", title: "叫声")
                        CaptureTip(emoji: "🎾", title: "玩耍")
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
                    Text(isValidating ? "校验视频中…" : "继续")
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
        OnboardingScrollableStep(step: 3, title: "行为小测试", subtitle: "帮助 NEKO 更准确理解它；也可以先跳过，之后再补。", onBack: onBack) {
            VStack(spacing: 12) {
                ForEach(QuizQuestion.onboarding) { question in
                    OnboardingCard {
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(question.id + 1)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(NekoTheme.soulViolet)
                                .frame(width: 24, height: 24)
                                .background(NekoTheme.softPink.opacity(0.52), in: Circle())

                            Text(question.question)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(NekoTheme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        HStack(spacing: 10) {
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
                    }
                }
            }
        } footer: {
            VStack(spacing: 10) {
                Button {
                    onNext()
                } label: {
                    Label("好了，开始解析", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())

                Button("先跳过问答") {
                    onSkip()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NekoTheme.muted)
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
        VStack(spacing: 0) {
            OnboardingTopBar(step: 4, onBack: onBack)

            Spacer(minLength: 24)

            Text("A I · A N A L Y Z I N G")
                .font(.system(size: 10, weight: .semibold))
                .tracking(5)
                .foregroundStyle(NekoTheme.soulViolet)

            Text("AI 分析中")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(NekoTheme.ink)
                .padding(.top, 8)

            Text("正在构建属于它的人格画像")
                .font(.system(size: 13))
                .foregroundStyle(NekoTheme.muted)
                .padding(.top, 4)

            ZStack {
                Circle()
                    .stroke(.white.opacity(0.72), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        NekoTheme.primaryGradient,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                FlowAvatarView(image: avatarImage, size: 142)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(NekoTheme.soulViolet)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.86), in: Capsule())
                    .offset(y: 86)
            }
            .frame(width: 220, height: 220)
            .padding(.top, 28)

            VStack(spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                    let threshold = Double(index + 1) / Double(steps.count)
                    AnalysisStepRow(title: title, isActive: progress <= threshold && progress > threshold - 1 / Double(steps.count), isDone: progress >= threshold)
                }
            }
            .padding(.top, 34)
            .padding(.horizontal, 28)

            Spacer()

            Text("每只猫，都有独一无二的灵魂。")
                .font(.system(size: 12))
                .foregroundStyle(NekoTheme.muted)
                .padding(.bottom, 26)
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

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(step: 4, onBack: onBack)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ResultHeroCard(draft: draft, avatarImage: avatarImage, persona: safePersona)

                    ResultSection(title: "AI 内心独白", hint: "INNER · VOICE") {
                        Text("“\(safePersona.monologue)”")
                            .font(.system(size: 16, weight: .light))
                            .italic()
                            .multilineTextAlignment(.center)
                            .lineSpacing(6)
                            .frame(maxWidth: .infinity)
                    }

                    ResultSection(title: "AI 人格解析", hint: "PERSONALITY") {
                        Text(safePersona.analysis)
                            .font(.system(size: 13))
                            .lineSpacing(5)
                    }

                    ResultSection(title: "它眼中的你", hint: "YOUR · ROLE") {
                        Text(safePersona.ownerRole)
                            .font(.system(size: 13))
                            .lineSpacing(5)
                    }

                    ResultSection(title: "个性画像", hint: "TRAITS") {
                        HStack(spacing: 10) {
                            ForEach(safePersona.traits) { trait in
                                TraitRing(trait: trait)
                            }
                        }
                    }

                    ResultSection(title: "人格标签", hint: "TAGS") {
                        FlowWrap(items: safePersona.tags)
                    }

                    ResultSection(title: "AI 观察依据", hint: "WHY · AI · THINKS · SO") {
                        VStack(spacing: 8) {
                            ForEach(safePersona.observations) { item in
                                HStack {
                                    Text(item.label)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(NekoTheme.muted)
                                    Spacer()
                                    Text(item.value)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(NekoTheme.ink)
                                        .multilineTextAlignment(.trailing)
                                }
                                .padding(12)
                                .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }

                    Text("视频已参与本次分析：\(videoCount) 段。本轮不会把 onboarding 视频保存到云端。")
                        .font(.system(size: 11))
                        .foregroundStyle(NekoTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 128)
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button("重新分析") {
                        onRestartAnalysis()
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle())

                    Button {
                        onSave()
                    } label: {
                        Text(isSaving ? "保存中…" : "保存结果")
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(isSaving || persona == nil)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .background(.ultraThinMaterial)
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
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(step: step, onBack: onBack)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(title)
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(NekoTheme.ink)
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(NekoTheme.muted)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                    content
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 118)
            }
            .safeAreaInset(edge: .bottom) {
                footer
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 14)
                    .background(.ultraThinMaterial)
            }
        }
    }
}

private struct OnboardingTopBar: View {
    let step: Int
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NekoTheme.soulViolet)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.74), in: Circle())
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(1...4, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? NekoTheme.soulViolet.opacity(0.62) : .white.opacity(0.72))
                        .frame(width: index <= step ? 24 : 12, height: 5)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
    }
}

private struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .background(.white.opacity(0.50), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.54), lineWidth: 1)
        }
    }
}

private struct OnboardingFieldTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(3)
            .foregroundStyle(NekoTheme.muted)
    }
}

private struct ChoiceChip: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10))
                    .opacity(0.78)
            }
            .foregroundStyle(isSelected ? .white : NekoTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                isSelected
                    ? AnyShapeStyle(NekoTheme.primaryGradient)
                    : AnyShapeStyle(Color.white.opacity(0.70)),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
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
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(active ? .white.opacity(0.22) : NekoTheme.softPink.opacity(0.52), in: Circle())
                Text(text)
                    .font(.system(size: 12, weight: active ? .semibold : .regular))
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
            }
            .foregroundStyle(active ? .white : NekoTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.horizontal, 10)
            .background(
                active
                    ? AnyShapeStyle(NekoTheme.primaryGradient)
                    : AnyShapeStyle(Color.white.opacity(0.70)),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct FlowAvatarView: View {
    let image: UIImage?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.78))
                .shadow(color: NekoTheme.soulViolet.opacity(0.18), radius: 24, x: 0, y: 12)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: size * 0.24, weight: .semibold))
                    Text("上传正脸")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(2)
                }
                .foregroundStyle(NekoTheme.soulViolet)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.88), lineWidth: 3)
        }
    }
}

private struct VideoClipCard: View {
    let clip: OnboardingVideoClip
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [NekoTheme.softPink.opacity(0.64), NekoTheme.softLilac.opacity(0.62)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if let data = clip.thumbnailData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "video.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.86))
                }

                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 3) {
                        Text(clip.label)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Text("\(clip.durationLabel) · \(clip.sizeLabel)")
                            .font(.system(size: 9, weight: .medium))
                            .opacity(0.86)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        LinearGradient(colors: [.clear, .black.opacity(0.48)], startPoint: .top, endPoint: .bottom)
                    )
                }
            }
            .frame(height: 176)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NekoTheme.ink)
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.88), in: Circle())
            }
            .padding(8)
        }
    }
}

private struct CaptureTip: View {
    let emoji: String
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            Text(emoji)
                .font(.system(size: 22))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NekoTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct AnalysisStepRow: View {
    let title: String
    let isActive: Bool
    let isDone: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isDone ? NekoTheme.soulPink.opacity(0.78) : isActive ? NekoTheme.soulViolet.opacity(0.72) : .white.opacity(0.8))
                .frame(width: 9, height: 9)

            Text(title)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isDone || isActive ? NekoTheme.ink : NekoTheme.muted)

            Spacer()

            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(NekoTheme.soulViolet)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(.white.opacity(isActive ? 0.82 : 0.56), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ResultHeroCard: View {
    let draft: CatProfileDraft
    let avatarImage: UIImage?
    let persona: CatPersonaResult

    var body: some View {
        HStack(spacing: 16) {
            FlowAvatarView(image: avatarImage, size: 112)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("人格匹配度")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NekoTheme.muted)
                    Text("\(persona.matchScore)%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(NekoTheme.soulViolet)
                }

                Text(draft.trimmedName)
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(NekoTheme.muted)

                Text(persona.type)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(
                        NekoTheme.primaryGradient
                    )

                HStack(spacing: 6) {
                    Text("MBTI")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(2)
                        .foregroundStyle(NekoTheme.muted)
                    Text(persona.mbti)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NekoTheme.ink)
                }

                Text("\(draft.gender.rawValue) · \(draft.ageStage.rawValue)")
                    .font(.system(size: 12))
                    .foregroundStyle(NekoTheme.muted)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.64), lineWidth: 1)
        }
    }
}

private struct ResultSection<Content: View>: View {
    let title: String
    let hint: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NekoTheme.ink)
                Spacer()
                Text(hint)
                    .font(.system(size: 9, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(NekoTheme.muted)
            }

            content
        }
        .padding(16)
        .background(.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.56), lineWidth: 1)
        }
    }
}

private struct TraitRing: View {
    let trait: PersonaTrait

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.74), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: CGFloat(trait.value) / 100)
                    .stroke(
                        NekoTheme.primaryGradient,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(trait.value)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(NekoTheme.ink)
            }
            .frame(width: 70, height: 70)

            Text(trait.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NekoTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FlowWrap: View {
    let items: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NekoTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(.white.opacity(0.64), in: Capsule())
            }
        }
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .background(NekoTheme.primaryGradient, in: Capsule())
            .shadow(color: NekoTheme.soulViolet.opacity(0.18), radius: 20, x: 0, y: 10)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(NekoTheme.soulViolet)
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(configuration.isPressed ? 0.66 : 0.84), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

#Preview {
    NativeOnboardingFlowView()
        .environmentObject(NekoAppModel())
}
