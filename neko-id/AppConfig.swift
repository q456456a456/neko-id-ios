//
//  AppConfig.swift
//  neko-id
//
//  Created by Codex on 2026/8/15.
//

import Foundation

enum AppConfig {
    static let productionWebURL = URL(string: "https://www.neko-id.uk")!
    static let supabaseURL = URL(string: "https://jbjgrkivscrombvnlcrl.supabase.co")!
    static let supabaseMediaBucket = "neko-media"
    static let maxAvatarImageBytes = 10 * 1024 * 1024
    static let maxVoiceImageBytes = 10 * 1024 * 1024
    static let maxOnboardingVideoBytes = 100 * 1024 * 1024

    /// Supabase publishable keys are safe to ship in client apps.
    /// Never put `SUPABASE_SECRET_KEY`, service role keys, or ByteCat keys in the iOS app.
    static let supabasePublishableKey = "sb_publishable_zxMk_QCMWRqc5d6KLQc0FA_5Akfmg8S"
}
