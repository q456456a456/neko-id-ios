//
//  AppConfig.swift
//  neko-id
//
//  Created by Codex on 2026/8/15.
//

import Foundation

enum AppConfig {
    // Temporary direct-IP endpoint for pre-ICP Mainland China testing.
    // Switch back to https://api.nekoid.cn before App Store submission.
    static let productionWebURL = URL(string: "http://14.103.91.205")!
    static let serverRequestTimeout: TimeInterval = 90
    static let serverResourceTimeout: TimeInterval = 120
    static let maxAvatarImageBytes = 10 * 1024 * 1024
    static let maxVoiceImageBytes = 10 * 1024 * 1024
    static let maxOnboardingVideoBytes = 100 * 1024 * 1024
}
