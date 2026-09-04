//
//  AppConfig.swift
//  neko-id
//
//  Created by Codex on 2026/8/15.
//

import Foundation

enum AppConfig {
    static let productionWebURL = URL(string: "https://www.neko-id.uk")!
    static let maxAvatarImageBytes = 10 * 1024 * 1024
    static let maxVoiceImageBytes = 10 * 1024 * 1024
    static let maxOnboardingVideoBytes = 100 * 1024 * 1024
}
