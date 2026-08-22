//
//  NekoAppModel.swift
//  neko-id
//
//  Created by Codex on 2026/8/15.
//

import Combine
import Foundation

@MainActor
final class NekoAppModel: ObservableObject {
    @Published private(set) var phase: AppPhase = .launching
    @Published private(set) var session: NekoSession?
    @Published private(set) var catProfile: CatProfile?
    @Published private(set) var persona: CatPersonaResult?
    @Published private(set) var voices: [CatVoiceResult] = []
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    private let api = SupabaseRESTClient()
    private let serverAPI = NekoServerAPIClient()
    private let sessionAccount = "supabase-session"
    private var bootstrapped = false

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true

        do {
            guard var storedSession = try KeychainStore.load(NekoSession.self, account: sessionAccount) else {
                phase = .signedOut
                return
            }

            if storedSession.isExpired {
                storedSession = try await api.refreshSession(storedSession)
                try KeychainStore.save(storedSession, account: sessionAccount)
            }

            session = storedSession
            try await reloadCloudState(session: storedSession)
        } catch {
            KeychainStore.delete(account: sessionAccount)
            session = nil
            catProfile = nil
            persona = nil
            voices = []
            phase = .signedOut
            errorMessage = "登录状态已过期，请重新登录。"
        }
    }

    func requestLoginCode(email: String) async {
        await runBusy {
            try await api.requestEmailOTP(email: email.normalizedEmail)
            noticeMessage = "验证码已发送，请查收邮箱。"
        }
    }

    func verifyLoginCode(email: String, code: String) async {
        await runBusy {
            let nextSession = try await api.verifyEmailOTP(
                email: email.normalizedEmail,
                token: code.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try KeychainStore.save(nextSession, account: sessionAccount)
            session = nextSession
            try await reloadCloudState(session: nextSession)
        }
    }

    func createCatProfile(
        _ draft: CatProfileDraft,
        avatarImageData: Data? = nil,
        quizAnswers: [Int: QuizChoice] = [:],
        persona generatedPersona: CatPersonaResult? = nil,
        videoCount: Int = 0
    ) async {
        guard draft.isValid else {
            errorMessage = "先填一个猫咪名字吧。"
            return
        }

        await runBusy {
            let activeSession = try await authenticatedSession()
            let finalPersona = generatedPersona ?? PersonaGenerator.generate(
                profile: draft,
                quizAnswers: quizAnswers,
                videoCount: videoCount,
                hasAvatar: avatarImageData != nil
            )

            let isRetestingExistingProfile = catProfile != nil
            let saved = try await serverAPI.saveCatProfile(
                currentProfile: catProfile,
                name: draft.trimmedName,
                gender: draft.gender,
                ageStage: draft.ageStage,
                quizAnswers: quizAnswers,
                persona: finalPersona,
                avatarImageData: avatarImageData,
                completeOnboarding: true,
                accessToken: activeSession.accessToken
            )
            catProfile = saved.profile
            persona = saved.persona ?? finalPersona
            if isRetestingExistingProfile {
                voices = []
            }
            phase = .home
            noticeMessage = "猫咪档案已保存。"
        }
    }

    func completeOnboarding(
        draft: CatProfileDraft,
        avatarImageData: Data?,
        quizAnswers: [Int: QuizChoice],
        persona: CatPersonaResult,
        videoCount: Int
    ) async {
        await createCatProfile(
            draft,
            avatarImageData: avatarImageData,
            quizAnswers: quizAnswers,
            persona: persona,
            videoCount: videoCount
        )
    }

    func detectCatFace(imageData: Data, mode: CatDetectionMode) async throws -> CatDetectionResult {
        let activeSession = try await authenticatedSession()
        return try await serverAPI.detectCatFace(
            imageData: imageData,
            mode: mode,
            accessToken: activeSession.accessToken
        )
    }

    func generateOnboardingPersona(
        draft: CatProfileDraft,
        quizAnswers: [Int: QuizChoice],
        avatarImageData: Data?,
        videoCount: Int
    ) async throws -> CatPersonaResult {
        let activeSession = try await authenticatedSession()
        return try await serverAPI.generateOnboardingPersona(
            draft: draft,
            quizAnswers: quizAnswers,
            avatarImageData: avatarImageData,
            videoCount: videoCount,
            accessToken: activeSession.accessToken
        )
    }

    func uploadAvatarImageData(_ data: Data) async {
        guard let profile = catProfile else {
            phase = .signedOut
            return
        }

        await runBusy {
            let activeSession = try await authenticatedSession()
            catProfile = try await serverAPI.uploadAvatarImage(
                data,
                for: profile,
                accessToken: activeSession.accessToken
            )
            noticeMessage = "头像已更新。"
        }
    }

    func loadAccountSummary() async throws -> NekoAccountSummary {
        let activeSession = try await authenticatedSession()
        return try await serverAPI.fetchAccountSummary(accessToken: activeSession.accessToken)
    }

    func updateDisplayName(_ displayName: String) async throws -> NekoAccountProfile {
        let activeSession = try await authenticatedSession()
        return try await serverAPI.updateUserProfile(
            displayName: displayName,
            accessToken: activeSession.accessToken
        )
    }

    func saveCurrentStateToCloud() async throws -> NekoAccountSummary {
        let activeSession = try await authenticatedSession()
        return try await serverAPI.fetchAccountSummary(accessToken: activeSession.accessToken)
    }

    func restoreFromCloud() async throws -> NekoAccountSummary {
        let activeSession = try await authenticatedSession()
        try await reloadCloudState(session: activeSession)
        return try await serverAPI.fetchAccountSummary(accessToken: activeSession.accessToken)
    }

    func signedMediaURL(for objectKey: String?) async -> URL? {
        guard let objectKey, !objectKey.isEmpty else { return nil }
        do {
            let activeSession = try await authenticatedSession()
            return try await serverAPI.signedMediaURL(
                for: objectKey,
                accessToken: activeSession.accessToken
            )
        } catch {
            return nil
        }
    }

    func refreshSignedMediaURLs() async {
        guard session != nil else { return }
        do {
            let activeSession = try await authenticatedSession()

            if var profile = catProfile,
               let nextAvatarURL = try? await serverAPI.signedMediaURL(
                for: profile.avatarObjectKey,
                accessToken: activeSession.accessToken
               ) {
                profile.avatarURL = nextAvatarURL
                catProfile = profile
            }

            guard !voices.isEmpty else { return }
            var refreshedVoices = voices
            for index in refreshedVoices.indices {
                guard let objectKey = refreshedVoices[index].mediaObjectKey, !objectKey.isEmpty else { continue }
                if let nextMediaURL = try? await serverAPI.signedMediaURL(
                    for: objectKey,
                    accessToken: activeSession.accessToken
                ) {
                    refreshedVoices[index].mediaURL = nextMediaURL
                }
            }
            voices = refreshedVoices
        } catch {
            // 图片 URL 刷新失败不影响主流程；单张图片组件还会在加载失败时再重试一次。
        }
    }

    func updateCatProfileDetails(
        name: String,
        gender: CatGender,
        ageStage: CatAgeStage,
        avatarImageData: Data?
    ) async throws {
        guard let profile = catProfile else {
            phase = .onboarding
            throw NekoAppError.missingCatProfile
        }

        let activeSession = try await authenticatedSession()
        let saved = try await serverAPI.saveCatProfile(
            currentProfile: profile,
            name: name,
            gender: gender,
            ageStage: ageStage,
            quizAnswers: [:],
            persona: nil,
            avatarImageData: avatarImageData,
            completeOnboarding: false,
            accessToken: activeSession.accessToken
        )

        catProfile = saved.profile
        if let savedPersona = saved.persona {
            persona = savedPersona
        }
    }

    func saveProfileAndRestartOnboarding(
        name: String,
        gender: CatGender,
        ageStage: CatAgeStage,
        avatarImageData: Data?
    ) async throws {
        try await updateCatProfileDetails(
            name: name,
            gender: gender,
            ageStage: ageStage,
            avatarImageData: avatarImageData
        )
        persona = nil
        phase = .onboarding
    }

    @discardableResult
    func reloadVoices() async throws -> [CatVoiceResult] {
        guard let profile = catProfile else {
            voices = []
            return []
        }

        let activeSession = try await authenticatedSession()
        let nextVoices = try await serverAPI.fetchVoices(
            for: profile,
            accessToken: activeSession.accessToken
        )
        voices = nextVoices
        return nextVoices
    }

    func deleteVoices(ids: [String]) async throws {
        guard let profile = catProfile else {
            throw NekoAppError.missingCatProfile
        }

        let activeSession = try await authenticatedSession()
        try await serverAPI.deleteVoices(
            ids: ids,
            for: profile,
            accessToken: activeSession.accessToken
        )
        voices.removeAll { voice in
            voice.cloudId.map { ids.contains($0) } ?? false
        }
    }

    func publishCatVoice(imageData: Data, scene: String) async throws -> CatVoiceResult {
        let generated = try await generateCatVoicePreview(imageData: imageData, scene: scene)
        return try await saveGeneratedCatVoice(generated, imageData: imageData, showNotice: true)
    }

    func generateCatVoicePreview(imageData: Data, scene: String) async throws -> CatVoiceResult {
        guard let profile = catProfile else {
            phase = .onboarding
            throw NekoAppError.missingCatProfile
        }

        let activeSession = try await authenticatedSession()
        return try await serverAPI.generateCatVoice(
            profile: profile,
            persona: persona,
            imageData: imageData,
            scene: scene,
            accessToken: activeSession.accessToken
        )
    }

    func saveGeneratedCatVoice(
        _ generated: CatVoiceResult,
        imageData: Data,
        showNotice: Bool = false
    ) async throws -> CatVoiceResult {
        guard let profile = catProfile else {
            phase = .onboarding
            throw NekoAppError.missingCatProfile
        }

        let activeSession = try await authenticatedSession()
        let saved = try await serverAPI.saveCatVoice(
            generated,
            imageData: imageData,
            for: profile,
            accessToken: activeSession.accessToken
        )
        voices.insert(saved, at: 0)
        if showNotice {
            noticeMessage = "猫咪动态已发布。"
        }
        return saved
    }

    func signOut() {
        KeychainStore.delete(account: sessionAccount)
        session = nil
        catProfile = nil
        persona = nil
        voices = []
        phase = .signedOut
    }

    func startOnboarding() {
        phase = .onboarding
    }

    func cancelOnboardingIfPossible() {
        guard catProfile != nil else { return }
        phase = .home
    }

    private func authenticatedSession() async throws -> NekoSession {
        guard var activeSession = session else {
            phase = .signedOut
            throw NekoAppError.signedOut
        }

        if activeSession.isExpired {
            activeSession = try await api.refreshSession(activeSession)
            try KeychainStore.save(activeSession, account: sessionAccount)
            session = activeSession
        }

        return activeSession
    }

    private func reloadCloudState(session activeSession: NekoSession) async throws {
        let cloudState = try await serverAPI.fetchCloudState(accessToken: activeSession.accessToken)
        catProfile = cloudState.profile
        persona = cloudState.persona
        voices = cloudState.voices
        phase = cloudState.profile == nil ? .onboarding : .home
    }

    private func runBusy(_ operation: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        noticeMessage = nil

        do {
            try await operation()
        } catch {
            errorMessage = userFacingMessage(for: error)
        }

        isBusy = false
    }

    private func userFacingMessage(for error: Error) -> String {
        if let description = (error as? LocalizedError)?.errorDescription, !description.isEmpty {
            if description.localizedCaseInsensitiveContains("rate") {
                return "验证码发送太频繁了，稍等一会儿再试。"
            }
            if description.localizedCaseInsensitiveContains("invalid") || description.localizedCaseInsensitiveContains("expired") {
                return "验证码不正确或已过期，请重新获取。"
            }
            return description
        }

        return "操作失败，请稍后再试。"
    }
}

enum NekoAppError: LocalizedError {
    case signedOut
    case missingCatProfile

    var errorDescription: String? {
        switch self {
        case .signedOut:
            return "登录状态已过期，请重新登录。"
        case .missingCatProfile:
            return "还没有猫咪档案，请先创建档案。"
        }
    }
}

private extension String {
    var normalizedEmail: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
