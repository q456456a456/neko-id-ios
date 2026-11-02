//
//  AppConfig.swift
//  neko-id
//
//  Created by Codex on 2026/8/15.
//

import Foundation

enum AppConfig {
    // Mainland China API endpoint. Use the domain with verified HTTPS.
    static let productionWebURL = URL(string: "https://api.nekoid.cn")!
    static let serverRequestTimeout: TimeInterval = 90
    static let serverResourceTimeout: TimeInterval = 120
    static let maxAvatarImageBytes = 10 * 1024 * 1024
    static let maxVoiceImageBytes = 10 * 1024 * 1024
    static let maxOnboardingVideoBytes = 100 * 1024 * 1024
}
