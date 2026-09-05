//
//  NekoAppModel.swift
//  neko-id
//
//  Created by Codex on 2026/8/15.
//

import Combine
import Foundation

struct NekoLoginPrompt: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

@MainActor
final class NekoAppModel: ObservableObject {
    @Published private(set) var phase: AppPhase = .launching
    @Published private(set) var session: NekoSession?
    @Published private(set) var catProfile: CatProfile?
    @Published private(set) var persona: CatPersonaResult?
    @Published private(set) var voices: [CatVoiceResult] = []
    @Published var loginPrompt: NekoLoginPrompt?
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    private let serverAPI = NekoServerAPIClient()
    private let sessionAccount = "neko-session"
    private let legacySessionAccount = "supabase-session"
    private var bootstrapped = false
    private var signedMediaCache: [String: CachedSignedMediaURL] = [:]

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true

        do {
            guard var storedSession = try loadStoredSession() else {
                phase = .onboarding
                return
            }

            if storedSession.isExpired {
                storedSession = try await serverAPI.refreshSession(storedSession)
                try saveStoredSession(storedSession)
            }

            session = storedSession
            try await reloadCloudState(session: storedSession)
        } catch {
            deleteStoredSession()
            session = nil
            catProfile = nil
            persona = nil
            voices = []
            phase = .onboarding
            errorMessage = "登录状态已过期，保存时请重新登录。"
        }
    }

    @discardableResult
    func requestLoginCode(phone: String) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        errorMessage = nil
        noticeMessage = nil

        do {
            try await serverAPI.requestPhoneOTP(phone: try phone.normalizedMainlandPhone())
            isBusy = false
            return true
        } catch {
            errorMessage = userFacingMessage(for: error)
            isBusy = false
            return false
        }
    }

    @discardableResult
    func verifyLoginCode(
        phone: String,
        code: String,
        reloadCloudStateAfterLogin: Bool = true
    ) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        errorMessage = nil
        noticeMessage = nil

        do {
            let nextSession = try await serverAPI.verifyPhoneOTP(
                phone: try phone.normalizedMainlandPhone(),
                token: code.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try saveStoredSession(nextSession)
            session = nextSession
            if reloadCloudStateAfterLogin {
                try await reloadCloudState(session: nextSession)
            }
            loginPrompt = nil
            isBusy = false
            return true
        } catch {
            errorMessage = userFacingMessage(for: error)
            isBusy = false
            return false
        }
    }

    func requestLogin(message: String) {
        loginPrompt = NekoLoginPrompt(message: message)
    }

    func dismissLoginPrompt() {
        loginPrompt = nil
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

            if catProfile == nil {
                let didRestoreHistory = try await restoreExistingCloudState(
                    session: activeSession,
                    showNotice: true
                )
                if didRestoreHistory {
                    return
                }
            }

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
            invalidateSignedMediaURL(for: saved.profile.avatarObjectKey)
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
        return try await serverAPI.detectCatFace(
            imageData: imageData,
            mode: mode
        )
    }

    func generateOnboardingPersona(
        draft: CatProfileDraft,
        quizAnswers: [Int: QuizChoice],
        avatarImageData: Data?,
        videoCount: Int
    ) async throws -> CatPersonaResult {
        return try await serverAPI.generateOnboardingPersona(
            draft: draft,
            quizAnswers: quizAnswers,
            avatarImageData: avatarImageData,
            videoCount: videoCount
        )
    }

    func uploadAvatarImageData(_ data: Data) async {
        guard let profile = catProfile else {
            phase = .onboarding
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

    func signedMediaURL(for objectKey: String?, forceRefresh: Bool = false) async -> URL? {
        guard let objectKey, !objectKey.isEmpty else { return nil }

        if !forceRefresh,
           let cached = signedMediaCache[objectKey],
           cached.isUsable {
            return cached.url
        }

        do {
            let activeSession = try await authenticatedSession()
            guard let url = try await serverAPI.signedMediaURL(
                for: objectKey,
                accessToken: activeSession.accessToken
            ) else {
                signedMediaCache.removeValue(forKey: objectKey)
                return nil
            }
            signedMediaCache[objectKey] = CachedSignedMediaURL(url: url)
            return url
        } catch {
            if forceRefresh {
                signedMediaCache.removeValue(forKey: objectKey)
            }
            return nil
        }
    }

    func invalidateSignedMediaURL(for objectKey: String?) {
        guard let objectKey, !objectKey.isEmpty else { return }
        signedMediaCache.removeValue(forKey: objectKey)
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

        invalidateSignedMediaURL(for: saved.profile.avatarObjectKey)
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
        invalidateSignedMediaURL(for: saved.mediaObjectKey)
        voices.insert(saved, at: 0)
        if showNotice {
            noticeMessage = "猫咪动态已发布。"
        }
        return saved
    }

    func signOut() {
        deleteStoredSession()
        session = nil
        catProfile = nil
        persona = nil
        voices = []
        signedMediaCache = [:]
        phase = .onboarding
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
            requestLogin(message: "继续前需要先登录，猫咪档案和心声会安全保存到你的云端账号。")
            throw NekoAppError.signedOut
        }

        if activeSession.isExpired {
            activeSession = try await serverAPI.refreshSession(activeSession)
            try saveStoredSession(activeSession)
            session = activeSession
        }

        return activeSession
    }

    private func loadStoredSession() throws -> NekoSession? {
        if let session = try KeychainStore.load(NekoSession.self, account: sessionAccount) {
            return session
        }

        guard let legacySession = try KeychainStore.load(NekoSession.self, account: legacySessionAccount) else {
            return nil
        }

        try saveStoredSession(legacySession)
        KeychainStore.delete(account: legacySessionAccount)
        return legacySession
    }

    private func saveStoredSession(_ session: NekoSession) throws {
        try KeychainStore.save(session, account: sessionAccount)
        KeychainStore.delete(account: legacySessionAccount)
    }

    private func deleteStoredSession() {
        KeychainStore.delete(account: sessionAccount)
        KeychainStore.delete(account: legacySessionAccount)
    }

    private func reloadCloudState(session activeSession: NekoSession) async throws {
        let cloudState = try await serverAPI.fetchCloudState(accessToken: activeSession.accessToken)
        applyCloudState(cloudState)
    }

    @discardableResult
    private func restoreExistingCloudState(
        session activeSession: NekoSession,
        showNotice: Bool
    ) async throws -> Bool {
        let cloudState = try await serverAPI.fetchCloudState(accessToken: activeSession.accessToken)
        guard cloudState.profile != nil else {
            return false
        }

        applyCloudState(cloudState)
        if showNotice {
            noticeMessage = "已恢复账号里的历史猫咪档案。"
        }
        return true
    }

    private func applyCloudState(_ cloudState: NekoCloudState) {
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
        NekoUserFacingError.message(for: error)
    }
}

private struct CachedSignedMediaURL {
    let url: URL
    let expiresAt: Date

    init(url: URL, ttl: TimeInterval = 50 * 60) {
        self.url = url
        self.expiresAt = Date().addingTimeInterval(ttl)
    }

    var isUsable: Bool {
        expiresAt > Date().addingTimeInterval(30)
    }
}

enum NekoAppError: LocalizedError {
    case signedOut
    case missingCatProfile
    case invalidPhone

    var errorDescription: String? {
        switch self {
        case .signedOut:
            return "登录状态已过期，请重新登录。"
        case .missingCatProfile:
            return "还没有猫咪档案，请先创建档案。"
        case .invalidPhone:
            return "请输入有效的中国大陆手机号。"
        }
    }
}

private extension String {
    func normalizedMainlandPhone() throws -> String {
        let compact = trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")

        if compact.hasPrefix("+86") {
            let phone = String(compact.dropFirst(3))
            guard phone.range(of: #"^1\d{10}$"#, options: .regularExpression) != nil else {
                throw NekoAppError.invalidPhone
            }
            return "+86\(phone)"
        }

        if compact.hasPrefix("86") {
            let phone = String(compact.dropFirst(2))
            guard phone.range(of: #"^1\d{10}$"#, options: .regularExpression) != nil else {
                throw NekoAppError.invalidPhone
            }
            return "+86\(phone)"
        }

        guard compact.range(of: #"^1\d{10}$"#, options: .regularExpression) != nil else {
            throw NekoAppError.invalidPhone
        }
        return "+86\(compact)"
    }
}
