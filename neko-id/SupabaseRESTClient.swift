//
//  SupabaseRESTClient.swift
//  neko-id
//
//  Created by Codex on 2026/8/15.
//

import Foundation

struct SupabaseRESTClient {
    private let baseURL: URL
    private let publishableKey: String
    private let session: URLSession

    init(
        baseURL: URL = AppConfig.supabaseURL,
        publishableKey: String = AppConfig.supabasePublishableKey,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.publishableKey = publishableKey
        self.session = session
    }

    func requestEmailOTP(email: String) async throws {
        let body = OTPRequest(email: email)
        _ = try await perform(
            path: "auth/v1/otp",
            method: "POST",
            body: encode(body),
            prefer: nil,
            accessToken: nil
        )
    }

    func verifyEmailOTP(email: String, token: String) async throws -> NekoSession {
        let body = VerifyOTPRequest(email: email, token: token)
        let data = try await perform(
            path: "auth/v1/verify",
            method: "POST",
            body: encode(body),
            prefer: nil,
            accessToken: nil
        )
        let response = try decoder.decode(VerifyOTPResponse.self, from: data)
        return response.session
    }

    func refreshSession(_ session: NekoSession) async throws -> NekoSession {
        let body = RefreshRequest(refreshToken: session.refreshToken)
        let data = try await perform(
            path: "auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            method: "POST",
            body: encode(body),
            prefer: nil,
            accessToken: nil
        )
        let response = try decoder.decode(VerifyOTPResponse.self, from: data)
        return response.session
    }

    func fetchActiveCat(session: NekoSession) async throws -> CatProfile? {
        let queryItems = [
            URLQueryItem(name: "select", value: "id,name,gender,age_stage,avatar_object_key,updated_at"),
            URLQueryItem(name: "user_id", value: "eq.\(session.user.id)"),
            URLQueryItem(name: "is_active", value: "eq.true"),
            URLQueryItem(name: "order", value: "updated_at.desc"),
            URLQueryItem(name: "limit", value: "1")
        ]

        let data = try await perform(
            path: "rest/v1/cats",
            queryItems: queryItems,
            method: "GET",
            body: nil,
            prefer: nil,
            accessToken: session.accessToken
        )
        guard var profile = try decoder.decode([CatRow].self, from: data).first?.profile else {
            return nil
        }

        profile.avatarURL = try? await signedMediaURL(for: profile.avatarObjectKey, session: session)
        return profile
    }

    func fetchPersona(for profile: CatProfile, session: NekoSession) async throws -> CatPersonaResult? {
        let data = try await perform(
            path: "rest/v1/cat_personas",
            queryItems: [
                URLQueryItem(name: "select", value: "type,mbti,match_score,monologue,analysis,owner_role,tags,traits,observations,daily_mood,provider,model"),
                URLQueryItem(name: "cat_id", value: "eq.\(profile.id)"),
                URLQueryItem(name: "limit", value: "1")
            ],
            method: "GET",
            body: nil,
            prefer: nil,
            accessToken: session.accessToken
        )

        return try decoder.decode([PersonaRow].self, from: data).first?.persona
    }

    func createCatProfile(
        _ draft: CatProfileDraft,
        quizAnswers: [Int: QuizChoice] = [:],
        persona: CatPersonaResult? = nil,
        session: NekoSession
    ) async throws -> CatProfile {
        let request = CreateCatRequest(
            userId: session.user.id,
            name: draft.trimmedName,
            gender: draft.gender.rawValue,
            ageStage: draft.ageStage.rawValue,
            quiz: Self.quizPayload(from: quizAnswers)
        )
        let data = try await perform(
            path: "rest/v1/cats",
            queryItems: [URLQueryItem(name: "select", value: "id,name,gender,age_stage,avatar_object_key,updated_at")],
            method: "POST",
            body: encode(request),
            prefer: "return=representation",
            accessToken: session.accessToken
        )

        guard let profile = try decoder.decode([CatRow].self, from: data).first?.profile else {
            throw SupabaseError.invalidResponse
        }

        try await upsertPersona(
            persona ?? PersonaGenerator.generate(
                profile: draft,
                quizAnswers: quizAnswers,
                videoCount: 0,
                hasAvatar: false
            ),
            for: profile,
            session: session
        )
        try await markOnboardingCompleted(session: session)
        return profile
    }

    func uploadAvatarImage(
        _ upload: PreparedImageUpload,
        for profile: CatProfile,
        session: NekoSession
    ) async throws -> CatProfile {
        let objectKey = "\(session.user.id)/cats/\(profile.id)/avatar.\(upload.fileExtension)"

        _ = try await perform(
            path: "storage/v1/object/\(AppConfig.supabaseMediaBucket)/\(objectKey)",
            method: "POST",
            body: upload.data,
            prefer: nil,
            accessToken: session.accessToken,
            contentType: upload.mimeType,
            extraHeaders: [
                "Cache-Control": "3600",
                "x-upsert": "true"
            ]
        )

        return try await updateCatAvatarObjectKey(objectKey, for: profile, session: session)
    }

    func saveCatVoice(
        _ voice: CatVoiceResult,
        imageUpload: PreparedImageUpload,
        for profile: CatProfile,
        session: NekoSession
    ) async throws -> CatVoiceResult {
        let voiceId = (voice.cloudId?.isEmpty == false ? voice.cloudId! : UUID().uuidString).lowercased()
        let objectKey = "\(session.user.id)/voices/\(voiceId)/media.\(imageUpload.fileExtension)"

        _ = try await perform(
            path: "storage/v1/object/\(AppConfig.supabaseMediaBucket)/\(objectKey)",
            method: "POST",
            body: imageUpload.data,
            prefer: nil,
            accessToken: session.accessToken,
            contentType: imageUpload.mimeType,
            extraHeaders: [
                "Cache-Control": "3600",
                "x-upsert": "true"
            ]
        )

        let createdAtDate = voice.createdAt.map {
            Date(timeIntervalSince1970: Double($0) / 1000)
        } ?? Date()
        let request = CreateVoiceRequest(
            id: voiceId,
            catId: profile.id,
            userId: session.user.id,
            voice: voice,
            mediaObjectKey: objectKey,
            createdAt: Self.iso8601WithFractionalSeconds.string(from: createdAtDate)
        )

        let data = try await perform(
            path: "rest/v1/cat_voices",
            queryItems: [
                URLQueryItem(name: "select", value: "id,text,analysis,location,tags,media_object_key,media_type,aspect,video_duration,grad,local_time_label,created_at")
            ],
            method: "POST",
            body: encode(request),
            prefer: "return=representation",
            accessToken: session.accessToken
        )

        guard let saved = try decoder.decode([VoiceRow].self, from: data).first?.voice else {
            throw SupabaseError.invalidResponse
        }

        return saved
    }

    private func upsertPersona(_ persona: CatPersonaResult, for profile: CatProfile, session: NekoSession) async throws {
        let request = UpsertPersonaRequest(
            catId: profile.id,
            userId: session.user.id,
            persona: persona
        )

        _ = try await perform(
            path: "rest/v1/cat_personas",
            queryItems: [
                URLQueryItem(name: "on_conflict", value: "cat_id"),
                URLQueryItem(name: "select", value: "id")
            ],
            method: "POST",
            body: encode(request),
            prefer: "resolution=merge-duplicates,return=representation",
            accessToken: session.accessToken
        )
    }

    private func markOnboardingCompleted(session: NekoSession) async throws {
        let body = try JSONSerialization.data(
            withJSONObject: ["onboarding_completed_at": ISO8601DateFormatter().string(from: Date())],
            options: []
        )

        _ = try await perform(
            path: "rest/v1/profiles",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(session.user.id)")],
            method: "PATCH",
            body: body,
            prefer: "return=minimal",
            accessToken: session.accessToken
        )
    }

    private func updateCatAvatarObjectKey(
        _ objectKey: String,
        for profile: CatProfile,
        session: NekoSession
    ) async throws -> CatProfile {
        let body = try JSONSerialization.data(
            withJSONObject: ["avatar_object_key": objectKey],
            options: []
        )

        let data = try await perform(
            path: "rest/v1/cats",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(profile.id)"),
                URLQueryItem(name: "user_id", value: "eq.\(session.user.id)"),
                URLQueryItem(name: "select", value: "id,name,gender,age_stage,avatar_object_key,updated_at")
            ],
            method: "PATCH",
            body: body,
            prefer: "return=representation",
            accessToken: session.accessToken
        )

        guard var updated = try decoder.decode([CatRow].self, from: data).first?.profile else {
            throw SupabaseError.invalidResponse
        }

        updated.avatarURL = try? await signedMediaURL(for: updated.avatarObjectKey, session: session)
        return updated
    }

    private func signedMediaURL(for objectKey: String?, session: NekoSession) async throws -> URL? {
        guard let objectKey, !objectKey.isEmpty else {
            return nil
        }

        let data = try await perform(
            path: "storage/v1/object/sign/\(AppConfig.supabaseMediaBucket)/\(objectKey)",
            method: "POST",
            body: encode(SignedURLRequest(expiresIn: 60 * 60)),
            prefer: nil,
            accessToken: session.accessToken
        )

        let response = try decoder.decode(SignedURLResponse.self, from: data)
        return response.url(relativeTo: baseURL)
    }

    private func perform(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        body: Data?,
        prefer: String?,
        accessToken: String?,
        contentType: String = "application/json",
        extraHeaders: [String: String] = [:]
    ) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components?.url else {
            throw SupabaseError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        extraHeaders.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseError.server(statusCode: http.statusCode, message: parseErrorMessage(from: data))
        }

        return data
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    private static func quizPayload(from answers: [Int: QuizChoice]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: answers.map { key, value in
            (String(key), value.rawValue)
        })
    }

    private func parseErrorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = object["message"] as? String {
                return message
            }
            if let error = object["error_description"] as? String {
                return error
            }
            if let error = object["error"] as? String {
                return error
            }
        }
        return String(data: data, encoding: .utf8) ?? "Unknown Supabase error"
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

enum SupabaseError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Supabase URL 配置错误。"
        case .invalidResponse:
            return "Supabase 返回了无法识别的数据。"
        case .server(_, let message):
            return message
        }
    }
}

private struct OTPRequest: Encodable {
    let email: String
    let createUser = true

    enum CodingKeys: String, CodingKey {
        case email
        case createUser = "create_user"
    }
}

private struct VerifyOTPRequest: Encodable {
    let email: String
    let token: String
    let type = "email"
}

private struct RefreshRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct SignedURLRequest: Encodable {
    let expiresIn: Int
}

private struct SignedURLResponse: Decodable {
    let signedURL: String?
    let signedUrl: String?

    func url(relativeTo baseURL: URL) -> URL? {
        guard let raw = signedURL ?? signedUrl else {
            return nil
        }

        if let absolute = URL(string: raw), absolute.scheme != nil {
            return absolute
        }

        var components = URLComponents()
        components.scheme = baseURL.scheme
        components.host = baseURL.host
        components.port = baseURL.port

        guard let origin = components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else {
            return nil
        }

        if raw.hasPrefix("/storage/v1") {
            return URL(string: "\(origin)\(raw)")
        }

        if raw.hasPrefix("/") {
            return URL(string: "\(origin)/storage/v1\(raw)")
        }

        return URL(string: "\(origin)/storage/v1/\(raw)")
    }

    enum CodingKeys: String, CodingKey {
        case signedURL
        case signedUrl
    }
}

private struct VerifyOTPResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int?
    let expiresAt: Int?
    let user: UserRow

    var session: NekoSession {
        let fallback = Date().addingTimeInterval(TimeInterval(expiresIn ?? 3600))
        let expiry = expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? fallback
        return NekoSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiry,
            user: NekoUser(id: user.id, email: user.email)
        )
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user
    }
}

private struct UserRow: Decodable {
    let id: String
    let email: String?
}

private struct CatRow: Decodable {
    let id: String
    let name: String
    let gender: String
    let ageStage: String
    let avatarObjectKey: String?
    let updatedAt: Date?

    var profile: CatProfile? {
        guard let gender = CatGender(rawValue: gender),
              let ageStage = CatAgeStage(rawValue: ageStage) else {
            return nil
        }

        return CatProfile(
            id: id,
            name: name,
            gender: gender,
            ageStage: ageStage,
            avatarObjectKey: avatarObjectKey,
            updatedAt: updatedAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case gender
        case ageStage = "age_stage"
        case avatarObjectKey = "avatar_object_key"
        case updatedAt = "updated_at"
    }
}

private struct PersonaRow: Decodable {
    let type: String
    let mbti: String
    let matchScore: Int
    let monologue: String
    let analysis: String
    let ownerRole: String
    let tags: [String]
    let traits: [PersonaTrait]
    let observations: [PersonaObservation]
    let dailyMood: String
    let provider: String?
    let model: String?

    var persona: CatPersonaResult {
        CatPersonaResult(
            type: type,
            mbti: mbti,
            matchScore: matchScore,
            monologue: monologue,
            analysis: analysis,
            ownerRole: ownerRole,
            tags: tags,
            traits: traits,
            observations: observations,
            dailyMood: dailyMood,
            provider: provider ?? "unknown",
            model: model ?? "unknown"
        )
    }

    enum CodingKeys: String, CodingKey {
        case type
        case mbti
        case matchScore = "match_score"
        case monologue
        case analysis
        case ownerRole = "owner_role"
        case tags
        case traits
        case observations
        case dailyMood = "daily_mood"
        case provider
        case model
    }
}

private struct VoiceRow: Decodable {
    let id: String
    let text: String
    let analysis: String?
    let location: String?
    let tags: [String]
    let mediaObjectKey: String?
    let mediaType: String?
    let aspect: String?
    let videoDuration: String?
    let grad: String?
    let localTimeLabel: String?
    let createdAt: Date?

    var voice: CatVoiceResult {
        CatVoiceResult(
            cloudId: id,
            time: localTimeLabel ?? "刚刚",
            grad: grad ?? "linear-gradient(135deg, oklch(0.9 0.06 280), oklch(0.92 0.05 320))",
            text: text,
            location: location,
            tags: tags,
            createdAt: createdAt.map { Int64($0.timeIntervalSince1970 * 1000) },
            mediaObjectKey: mediaObjectKey,
            mediaType: mediaType,
            aspect: aspect,
            videoDuration: videoDuration,
            analysis: analysis
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case analysis
        case location
        case tags
        case mediaObjectKey = "media_object_key"
        case mediaType = "media_type"
        case aspect
        case videoDuration = "video_duration"
        case grad
        case localTimeLabel = "local_time_label"
        case createdAt = "created_at"
    }
}

private struct CreateCatRequest: Encodable {
    let userId: String
    let name: String
    let gender: String
    let ageStage: String
    let quiz: [String: String]
    let isActive = true

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case gender
        case ageStage = "age_stage"
        case quiz
        case isActive = "is_active"
    }
}

private struct CreateVoiceRequest: Encodable {
    let id: String
    let catId: String
    let userId: String
    let text: String
    let analysis: String?
    let location: String?
    let tags: [String]
    let mediaObjectKey: String
    let mediaType: String
    let aspect: String
    let videoDuration: String?
    let grad: String
    let localTimeLabel: String
    let createdAt: String

    init(
        id: String,
        catId: String,
        userId: String,
        voice: CatVoiceResult,
        mediaObjectKey: String,
        createdAt: String
    ) {
        self.id = id
        self.catId = catId
        self.userId = userId
        self.text = voice.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "今天也想被你看见。"
            : voice.text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.analysis = voice.analysis
        self.location = voice.location
        self.tags = Array(voice.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(6))
        self.mediaObjectKey = mediaObjectKey
        self.mediaType = voice.mediaType ?? "photo"
        self.aspect = voice.aspect ?? "3:4"
        self.videoDuration = voice.videoDuration
        self.grad = voice.grad
        self.localTimeLabel = voice.time
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case catId = "cat_id"
        case userId = "user_id"
        case text
        case analysis
        case location
        case tags
        case mediaObjectKey = "media_object_key"
        case mediaType = "media_type"
        case aspect
        case videoDuration = "video_duration"
        case grad
        case localTimeLabel = "local_time_label"
        case createdAt = "created_at"
    }
}

private struct UpsertPersonaRequest: Encodable {
    let catId: String
    let userId: String
    let provider: String
    let model: String
    let type: String
    let mbti: String
    let matchScore: Int
    let monologue: String
    let analysis: String
    let ownerRole: String
    let tags: [String]
    let traits: [PersonaTrait]
    let observations: [PersonaObservation]
    let dailyMood: String

    init(catId: String, userId: String, persona: CatPersonaResult) {
        self.catId = catId
        self.userId = userId
        self.provider = persona.provider
        self.model = persona.model
        self.type = persona.type
        self.mbti = persona.mbti
        self.matchScore = persona.matchScore
        self.monologue = persona.monologue
        self.analysis = persona.analysis
        self.ownerRole = persona.ownerRole
        self.tags = persona.tags
        self.traits = persona.traits
        self.observations = persona.observations
        self.dailyMood = persona.dailyMood
    }

    enum CodingKeys: String, CodingKey {
        case catId = "cat_id"
        case userId = "user_id"
        case provider
        case model
        case type
        case mbti
        case matchScore = "match_score"
        case monologue
        case analysis
        case ownerRole = "owner_role"
        case tags
        case traits
        case observations
        case dailyMood = "daily_mood"
    }
}
