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
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func detectCatFace(
        imageData: Data,
        mode: CatDetectionMode,
        accessToken: String
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
        accessToken: String
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
            }
        )

        return try await perform(
            path: "/api/ios/onboarding/persona",
            body: body,
            accessToken: accessToken
        )
    }

    private func perform<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        body: RequestBody,
        accessToken: String
    ) async throws -> ResponseBody {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw NekoServerAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

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
        JSONDecoder()
    }

    private static func plainText(from data: Data) -> String {
        String(data: data, encoding: .utf8) ?? "服务器请求失败。"
    }
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
        case .server(_, let message):
            return message
        }
    }
}

private struct DetectCatFaceRequest: Encodable {
    let imageDataUrl: String
    let mode: String
}

private struct PersonaRequest: Encodable {
    let profile: ServerCatProfile
    let imageDataUrl: String?
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
