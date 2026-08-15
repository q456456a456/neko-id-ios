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
            catProfile = try await api.fetchActiveCat(session: storedSession)
            if let catProfile {
                persona = try? await api.fetchPersona(for: catProfile, session: storedSession)
            }
            phase = catProfile == nil ? .onboarding : .home
        } catch {
            KeychainStore.delete(account: sessionAccount)
            session = nil
            catProfile = nil
            persona = nil
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
            catProfile = try await api.fetchActiveCat(session: nextSession)
            if let catProfile {
                persona = try? await api.fetchPersona(for: catProfile, session: nextSession)
            }
            phase = catProfile == nil ? .onboarding : .home
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

            var profile = try await api.createCatProfile(
                draft,
                quizAnswers: quizAnswers,
                persona: finalPersona,
                session: activeSession
            )
            if let avatarImageData {
                let upload = try MediaUploadProcessor.prepareAvatarImage(from: avatarImageData)
                profile = try await api.uploadAvatarImage(upload, for: profile, session: activeSession)
            }
            catProfile = profile
            persona = finalPersona
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
            let upload = try MediaUploadProcessor.prepareAvatarImage(from: data)
            catProfile = try await api.uploadAvatarImage(upload, for: profile, session: activeSession)
            noticeMessage = "头像已更新。"
        }
    }

    func signOut() {
        KeychainStore.delete(account: sessionAccount)
        session = nil
        catProfile = nil
        persona = nil
        phase = .signedOut
    }

    func startOnboarding() {
        phase = .onboarding
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

    var errorDescription: String? {
        switch self {
        case .signedOut:
            return "登录状态已过期，请重新登录。"
        }
    }
}

private extension String {
    var normalizedEmail: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
