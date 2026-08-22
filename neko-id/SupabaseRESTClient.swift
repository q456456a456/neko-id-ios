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

    func requestPhoneOTP(phone: String) async throws {
        let body = PhoneOTPRequest(phone: phone)
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

    func verifyPhoneOTP(phone: String, token: String) async throws -> NekoSession {
        let body = VerifyPhoneOTPRequest(phone: phone, token: token)
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
        JSONDecoder()
    }
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

private struct PhoneOTPRequest: Encodable {
    let phone: String
    let createUser = true

    enum CodingKeys: String, CodingKey {
        case phone
        case createUser = "create_user"
    }
}

private struct VerifyOTPRequest: Encodable {
    let email: String
    let token: String
    let type = "email"
}

private struct VerifyPhoneOTPRequest: Encodable {
    let phone: String
    let token: String
    let type = "sms"
}

private struct RefreshRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
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
            user: NekoUser(id: user.id, email: user.email, phone: user.phone)
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
    let phone: String?
}
