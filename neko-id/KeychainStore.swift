//
//  KeychainStore.swift
//  neko-id
//
//  Created by Codex on 2026/8/15.
//

import Foundation
import Security

enum KeychainStore {
    private static let service = "uk.neko-id.app"
    private static let missingEntitlementStatus: OSStatus = -34018

    static func save<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            SimulatorFallback.delete(account: account)
            return
        }

        if status == errSecItemNotFound {
            var createQuery = query
            createQuery.merge(attributes) { _, new in new }
            let createStatus = SecItemAdd(createQuery as CFDictionary, nil)
            guard createStatus == errSecSuccess else {
                if createStatus == missingEntitlementStatus {
                    SimulatorFallback.save(data, account: account)
                    return
                }
                throw KeychainError.unhandledStatus(createStatus)
            }
            SimulatorFallback.delete(account: account)
            return
        }

        if status == missingEntitlementStatus {
            SimulatorFallback.save(data, account: account)
            return
        }

        throw KeychainError.unhandledStatus(status)
    }

    static func load<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return try SimulatorFallback.load(type, account: account)
        }

        guard status == errSecSuccess else {
            if status == missingEntitlementStatus {
                return try SimulatorFallback.load(type, account: account)
            }
            throw KeychainError.unhandledStatus(status)
        }

        guard let data = item as? Data else {
            throw KeychainError.invalidData
        }

        return try JSONDecoder().decode(type, from: data)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        SimulatorFallback.delete(account: account)
    }
}

private enum SimulatorFallback {
    private static let prefix = "neko.simulator.session."

    static func save(_ data: Data, account: String) {
        #if targetEnvironment(simulator)
        UserDefaults.standard.set(data, forKey: key(for: account))
        #endif
    }

    static func load<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
        #if targetEnvironment(simulator)
        guard let data = UserDefaults.standard.data(forKey: key(for: account)) else {
            return nil
        }
        return try JSONDecoder().decode(type, from: data)
        #else
        return nil
        #endif
    }

    static func delete(account: String) {
        #if targetEnvironment(simulator)
        UserDefaults.standard.removeObject(forKey: key(for: account))
        #endif
    }

    private static func key(for account: String) -> String {
        "\(prefix)\(account)"
    }
}

enum KeychainError: LocalizedError {
    case invalidData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Keychain data is invalid."
        case .unhandledStatus(let status):
            return "Keychain returned status \(status)."
        }
    }
}
