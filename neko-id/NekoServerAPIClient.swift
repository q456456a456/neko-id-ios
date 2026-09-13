//
//  NekoServerAPIClient.swift
//  neko-id
//
//  Created by Codex on 2026/8/15.
//

import Foundation

struct NekoServerAPIClient {
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = AppConfig.productionWebURL,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        self.session = session ?? Self.defaultSession
    }

    func isProtectedMediaURL(_ url: URL) -> Bool {
        guard url.path == "/api/ios/cloud/media" else { return false }
        guard let host = url.host?.lowercased(), let baseHost = baseURL.host?.lowercased(), host == baseHost else {
            return false
        }
        return normalizedPort(for: url) == normalizedPort(for: baseURL)
            && url.scheme?.lowercased() == baseURL.scheme?.lowercased()
    }

    func mediaRequest(for url: URL, accessToken: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if isProtectedMediaURL(url), let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = AppConfig.serverRequestTimeout
        configuration.timeoutIntervalForResource = AppConfig.serverResourceTimeout
        return URLSession(configuration: configuration)
    }()

    private func normalizedPort(for url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "http":
            return 80
        case "https":
            return 443
        default:
            return nil
        }
    }

    func requestPhoneOTP(phone: String) async throws {
        let _: PhoneOTPResponse = try await perform(
            path: "/api/ios/auth/phone-otp",
            body: PhoneOTPServerRequest(phone: phone),
            accessToken: nil
        )
    }

    func verifyPhoneOTP(phone: String, token: String) async throws -> NekoSession {
        try await perform(
            path: "/api/ios/auth/phone-verify",
            body: VerifyPhoneOTPServerRequest(phone: phone, token: token),
            accessToken: nil
        )
    }

    func refreshSession(_ session: NekoSession) async throws -> NekoSession {
        try await perform(
            path: "/api/ios/auth/refresh",
            body: RefreshSessionServerRequest(refreshToken: session.refreshToken),
            accessToken: nil
        )
    }

    func detectCatFace(
        imageData: Data,
        mode: CatDetectionMode,
        accessToken: String? = nil
    ) async throws -> CatDetectionResult {
        let body = DetectCatFaceRequest(
            imageDataUrl: try MediaUploadProcessor.makeAIImageDataURL(from: imageData),
            mode: mode.rawValue
        )

        return try await perform(
            path: "/api/ios/detect-cat-face",
            body: body,
            accessToken: accessToken
        )
    }

    func generateOnboardingPersona(
        draft: CatProfileDraft,
        quizAnswers: [Int: QuizChoice],
        avatarImageData: Data?,
        videoCount: Int,
        videoObservations: [CatVideoObservation],
        accessToken: String? = nil
    ) async throws -> CatPersonaResult {
        let body = PersonaRequest(
            profile: ServerCatProfile(
                name: draft.trimmedName,
                gender: draft.gender.rawValue,
                ageStage: draft.ageStage.rawValue,
                quiz: Dictionary(uniqueKeysWithValues: quizAnswers.map { key, value in
                    (String(key), value.rawValue)
                }),
                videoCount: videoCount,
                updatedAt: Int64(Date().timeIntervalSince1970 * 1000)
            ),
            imageDataUrl: try avatarImageData.map {
                try MediaUploadProcessor.makeAIImageDataURL(from: $0)
            },
            videoObservations: videoObservations
        )

        return try await perform(
            path: "/api/ios/onboarding/persona",
            body: body,
            accessToken: accessToken
        )
    }

    func analyzeOnboardingVideoClip(
        draft: CatProfileDraft,
        quizAnswers: [Int: QuizChoice],
        clip: OnboardingVideoClip,
        videoCount: Int,
        accessToken: String? = nil
    ) async throws -> CatVideoObservation {
        let body = VideoAnalysisRequest(
            profile: ServerCatProfile(
                name: draft.trimmedName,
                gender: draft.gender.rawValue,
                ageStage: draft.ageStage.rawValue,
                quiz: Dictionary(uniqueKeysWithValues: quizAnswers.map { key, value in
                    (String(key), value.rawValue)
                }),
                videoCount: videoCount,
                updatedAt: Int64(Date().timeIntervalSince1970 * 1000)
            ),
            clipId: clip.id.uuidString,
            label: clip.label,
            duration: clip.durationLabel,
            frames: clip.videoFrames
        )

        return try await perform(
            path: "/api/ios/onboarding/video-analysis",
            body: body,
            accessToken: accessToken
        )
    }

    func generateCatVoice(
        profile: CatProfile,
        persona: CatPersonaResult?,
        imageData: Data,
        scene: String,
        accessToken: String
    ) async throws -> CatVoiceResult {
        let body = VoiceRequest(
            profile: ServerCatProfile(
                name: profile.name,
                gender: profile.gender.rawValue,
                ageStage: profile.ageStage.rawValue,
                quiz: [:],
                videoCount: 0,
                updatedAt: Int64((profile.updatedAt ?? Date()).timeIntervalSince1970 * 1000)
            ),
            persona: persona,
            imageDataUrl: try MediaUploadProcessor.makeAIImageDataURL(from: imageData),
            scene: scene.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        return try await perform(
            path: "/api/ios/voice",
            body: body,
            accessToken: accessToken
        )
    }

    func fetchCloudState(accessToken: String) async throws -> NekoCloudState {
        try await perform(
            path: "/api/ios/cloud/state",
            body: EmptyServerRequest(),
            accessToken: accessToken
        )
    }

    func saveCatProfile(
        currentProfile: CatProfile?,
        name: String,
        gender: CatGender,
        ageStage: CatAgeStage,
        quizAnswers: [Int: QuizChoice],
        persona: CatPersonaResult?,
        avatarImageData: Data?,
        completeOnboarding: Bool,
        accessToken: String
    ) async throws -> NekoCatProfileSaveResult {
        let catId = currentProfile?.id ?? UUID().uuidString
        let avatarObjectKey: String?
        let avatarUpload = try avatarImageData.map { data in
            try MediaUploadProcessor.prepareAvatarImage(from: data)
        }
        if let avatarUpload {
            let uploadTarget = try await requestMediaUploadURL(
                purpose: .catAvatar,
                catId: catId,
                voiceId: nil,
                upload: avatarUpload,
                accessToken: accessToken
            )
            try await uploadPreparedImage(avatarUpload, to: uploadTarget)
            avatarObjectKey = uploadTarget.objectKey
        } else {
            avatarObjectKey = nil
        }

        let body = SaveCatProfileRequest(
            currentCatId: currentProfile?.id,
            catId: catId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            gender: gender.rawValue,
            ageStage: ageStage.rawValue,
            quiz: Dictionary(uniqueKeysWithValues: quizAnswers.map { key, value in
                (String(key), value.rawValue)
            }),
            persona: persona,
            avatarObjectKey: avatarObjectKey,
            completeOnboarding: completeOnboarding
        )

        return try await perform(
            path: "/api/ios/cloud/cat-profile",
            body: body,
            accessToken: accessToken
        )
    }

    func uploadAvatarImage(
        _ imageData: Data,
        for profile: CatProfile,
        accessToken: String
    ) async throws -> CatProfile {
        let upload = try MediaUploadProcessor.prepareAvatarImage(from: imageData)
        let uploadTarget = try await requestMediaUploadURL(
            purpose: .catAvatar,
            catId: profile.id,
            voiceId: nil,
            upload: upload,
            accessToken: accessToken
        )
        try await uploadPreparedImage(upload, to: uploadTarget)

        let body = AvatarUploadRequest(
            catId: profile.id,
            avatarObjectKey: uploadTarget.objectKey
        )

        return try await perform(
            path: "/api/ios/cloud/avatar",
            body: body,
            accessToken: accessToken
        )
    }

    func fetchAccountSummary(accessToken: String) async throws -> NekoAccountSummary {
        try await perform(
            path: "/api/ios/cloud/account-summary",
            body: EmptyServerRequest(),
            accessToken: accessToken
        )
    }

    func updateUserProfile(displayName: String, accessToken: String) async throws -> NekoAccountProfile {
        try await perform(
            path: "/api/ios/cloud/user-profile",
            body: UpdateUserProfileRequest(displayName: displayName),
            accessToken: accessToken
        )
    }

    func fetchVoices(for profile: CatProfile, accessToken: String) async throws -> [CatVoiceResult] {
        try await perform(
            path: "/api/ios/cloud/voices",
            body: FetchVoicesRequest(catId: profile.id),
            accessToken: accessToken
        )
    }

    func deleteVoices(ids: [String], for profile: CatProfile, accessToken: String) async throws {
        let _: DeleteVoicesResponse = try await perform(
            path: "/api/ios/cloud/voices/delete",
            body: DeleteVoicesRequest(catId: profile.id, ids: ids),
            accessToken: accessToken
        )
    }

    func saveCatVoice(
        _ voice: CatVoiceResult,
        imageData: Data,
        for profile: CatProfile,
        accessToken: String
    ) async throws -> CatVoiceResult {
        var voiceToSave = voice
        if voiceToSave.cloudId?.isEmpty ?? true {
            voiceToSave.cloudId = UUID().uuidString
        }

        let upload = try MediaUploadProcessor.prepareVoiceImage(from: imageData)
        let uploadTarget = try await requestMediaUploadURL(
            purpose: .voiceMedia,
            catId: nil,
            voiceId: voiceToSave.cloudId,
            upload: upload,
            accessToken: accessToken
        )
        try await uploadPreparedImage(upload, to: uploadTarget)
        voiceToSave.mediaObjectKey = uploadTarget.objectKey

        let body = SaveVoiceRequest(
            catId: profile.id,
            voice: voiceToSave,
            mediaObjectKey: uploadTarget.objectKey
        )

        return try await perform(
            path: "/api/ios/cloud/voice",
            body: body,
            accessToken: accessToken
        )
    }

    func signedMediaURL(for objectKey: String?, accessToken: String) async throws -> URL? {
        let response: SignedMediaURLResponse = try await perform(
            path: "/api/ios/cloud/media-url",
            body: SignedMediaURLRequest(objectKey: objectKey),
            accessToken: accessToken
        )
        return response.mediaURL
    }

    private func requestMediaUploadURL(
        purpose: MediaUploadPurpose,
        catId: String?,
        voiceId: String?,
        upload: PreparedImageUpload,
        accessToken: String
    ) async throws -> MediaUploadURLResponse {
        try await perform(
            path: "/api/ios/cloud/media-upload",
            body: MediaUploadURLRequest(
                purpose: purpose.rawValue,
                catId: catId,
                voiceId: voiceId,
                contentType: upload.mimeType,
                fileExtension: upload.fileExtension,
                byteSize: upload.data.count
            ),
            accessToken: accessToken
        )
    }

    private func uploadPreparedImage(
        _ upload: PreparedImageUpload,
        to target: MediaUploadURLResponse
    ) async throws {
        var request = URLRequest(url: target.uploadURL)
        request.httpMethod = target.method
        request.httpBody = upload.data
        request.setValue(upload.mimeType, forHTTPHeaderField: "Content-Type")
        target.headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NekoServerAPIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            throw NekoServerAPIError.server(
                statusCode: http.statusCode,
                message: "图片上传失败，请稍后再试。"
            )
        }
    }

    private func perform<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        body: RequestBody,
        accessToken: String? = nil
    ) async throws -> ResponseBody {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw NekoServerAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NekoServerAPIError.invalidResponse
        }

        let envelope = try? decoder.decode(APIEnvelope<ResponseBody>.self, from: data)
        guard (200..<300).contains(http.statusCode) else {
            throw NekoServerAPIError.server(
                statusCode: http.statusCode,
                message: envelope?.error?.message ?? Self.plainText(from: data)
            )
        }

        guard envelope?.ok == true, let payload = envelope?.data else {
            throw NekoServerAPIError.server(
                statusCode: http.statusCode,
                message: envelope?.error?.message ?? "服务器没有返回可识别的数据。"
            )
        }

        return payload
    }

    private var encoder: JSONEncoder {
        JSONEncoder()
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            if let date = Self.iso8601WithFractionalSeconds.date(from: string) ?? Self.iso8601.date(from: string) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO date")
        }
        return decoder
    }

    private static func plainText(from data: Data) -> String {
        String(data: data, encoding: .utf8) ?? "服务器请求失败。"
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

enum NekoServerAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "服务器地址配置错误。"
        case .invalidResponse:
            return "服务器返回了无法识别的数据。"
        case .server(let statusCode, let message):
            return NekoUserFacingError.message(from: message, statusCode: statusCode)
        }
    }
}

enum NekoUserFacingError {
    static func message(
        for error: Error,
        fallback: String = "操作失败，请稍后再试。"
    ) -> String {
        if let description = (error as? LocalizedError)?.errorDescription, !description.isEmpty {
            return message(from: description, fallback: fallback)
        }

        return message(from: error.localizedDescription, fallback: fallback)
    }

    static func message(
        from rawMessage: String?,
        statusCode: Int? = nil,
        fallback: String = "操作失败，请稍后再试。"
    ) -> String {
        let message = (rawMessage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return fallback }

        let lowercased = message.lowercased()

        if lowercased.contains("rate") || lowercased.contains("too many") {
            return "验证码发送太频繁了，稍等一会儿再试。"
        }

        if lowercased.contains("invalid") && lowercased.contains("otp") {
            return "验证码不正确或已过期，请重新获取。"
        }

        if lowercased.contains("expired") && lowercased.contains("登录") {
            return "登录状态已过期，请重新登录。"
        }

        if lowercased.contains("missing bearer") || lowercased.contains("bearer token") {
            return "请先登录后再继续。"
        }

        if lowercased.contains("keychain returned") || lowercased.contains("osstatus") {
            return "登录状态保存失败，请重启 App 后再试。"
        }

        if lowercased.contains("internet connection") ||
            lowercased.contains("network connection") ||
            lowercased.contains("offline") ||
            lowercased.contains("not connected") {
            return "网络连接不太稳定，请检查后再试。"
        }

        if lowercased.contains("timed out") ||
            lowercased.contains("timeout") ||
            lowercased.contains("operation was aborted") {
            if message.contains("心声") {
                return "AI 现在有点忙，猫咪心声暂时没有生成成功，请稍后再试。"
            }
            if message.contains("人格") {
                return "AI 现在有点忙，人格档案暂时没有生成成功，请稍后再试。"
            }
            return "服务响应有点慢，请稍后再试。"
        }

        if containsInternalDetails(lowercased) {
            if message.contains("心声") {
                return "AI 心声暂时没有生成成功，请稍后再试。"
            }
            if message.contains("人格") {
                return "AI 人格档案暂时没有生成成功，请稍后再试。"
            }
            if statusCode == 401 {
                return "登录状态已过期，请重新登录。"
            }
            return fallback
        }

        return message
    }

    private static func containsInternalDetails(_ lowercasedMessage: String) -> Bool {
        let tokens = [
            "bytecat",
            "openai",
            "qwen",
            "deepseek",
            "dashscope",
            "supabase",
            "api_key",
            "bearer",
            "timeout after",
            "nsurlerrordomain",
            "nscocoaerrordomain",
            "stack trace",
            "localizederror"
        ]

        return tokens.contains { lowercasedMessage.contains($0) }
    }
}

private struct PhoneOTPServerRequest: Encodable {
    let phone: String
}

private struct PhoneOTPResponse: Decodable {
    let sent: Bool
}

private struct VerifyPhoneOTPServerRequest: Encodable {
    let phone: String
    let token: String
}

private struct RefreshSessionServerRequest: Encodable {
    let refreshToken: String
}

private struct DetectCatFaceRequest: Encodable {
    let imageDataUrl: String
    let mode: String
}

private struct PersonaRequest: Encodable {
    let profile: ServerCatProfile
    let imageDataUrl: String?
    let videoObservations: [CatVideoObservation]
}

private struct VideoAnalysisRequest: Encodable {
    let profile: ServerCatProfile
    let clipId: String
    let label: String
    let duration: String
    let frames: [CatVideoFramePayload]
}

private struct VoiceRequest: Encodable {
    let profile: ServerCatProfile
    let persona: CatPersonaResult?
    let imageDataUrl: String
    let scene: String
}

struct NekoCloudState: Decodable, Equatable {
    let profile: CatProfile?
    let persona: CatPersonaResult?
    let voices: [CatVoiceResult]
}

struct NekoCatProfileSaveResult: Decodable, Equatable {
    let profile: CatProfile
    let persona: CatPersonaResult?
}

private struct EmptyServerRequest: Encodable {}

private enum MediaUploadPurpose: String {
    case catAvatar = "cat_avatar"
    case voiceMedia = "voice_media"
}

private struct MediaUploadURLRequest: Encodable {
    let purpose: String
    let catId: String?
    let voiceId: String?
    let contentType: String
    let fileExtension: String
    let byteSize: Int
}

private struct MediaUploadURLResponse: Decodable {
    let objectKey: String
    let uploadURL: URL
    let method: String
    let headers: [String: String]?
    let expiresInSeconds: Int?
}

private struct SaveCatProfileRequest: Encodable {
    let currentCatId: String?
    let catId: String
    let name: String
    let gender: String
    let ageStage: String
    let quiz: [String: String]
    let persona: CatPersonaResult?
    let avatarObjectKey: String?
    let completeOnboarding: Bool
}

private struct AvatarUploadRequest: Encodable {
    let catId: String
    let avatarObjectKey: String
}

private struct UpdateUserProfileRequest: Encodable {
    let displayName: String
}

private struct FetchVoicesRequest: Encodable {
    let catId: String
}

private struct DeleteVoicesRequest: Encodable {
    let catId: String
    let ids: [String]
}

private struct DeleteVoicesResponse: Decodable {
    let deleted: Int?
}

private struct SaveVoiceRequest: Encodable {
    let catId: String
    let voice: CatVoiceResult
    let mediaObjectKey: String
}

private struct SignedMediaURLRequest: Encodable {
    let objectKey: String?
}

private struct SignedMediaURLResponse: Decodable {
    let mediaURL: URL?
}

private struct ServerCatProfile: Encodable {
    let name: String
    let gender: String
    let ageStage: String
    let quiz: [String: String]
    let videoCount: Int
    let updatedAt: Int64
}

private struct APIEnvelope<Payload: Decodable>: Decodable {
    let ok: Bool
    let data: Payload?
    let error: APIErrorBody?
}

private struct APIErrorBody: Decodable {
    let code: String?
    let message: String
}
