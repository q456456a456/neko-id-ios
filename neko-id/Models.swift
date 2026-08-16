//
//  Models.swift
//  neko-id
//
//  Created by Codex on 2026/8/15.
//

import Foundation

enum CatGender: String, CaseIterable, Identifiable, Codable {
    case male = "小公猫"
    case female = "小母猫"

    var id: String { rawValue }
}

enum CatAgeStage: String, CaseIterable, Identifiable, Codable {
    case kitten = "幼猫"
    case young = "青年猫"
    case adult = "成熟猫"
    case senior = "资深猫"

    var id: String { rawValue }
}

struct NekoUser: Codable, Equatable {
    let id: String
    let email: String?
}

struct NekoSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: NekoUser

    var isExpired: Bool {
        expiresAt <= Date().addingTimeInterval(60)
    }
}

struct NekoAccountProfile: Codable, Equatable {
    let id: String
    let email: String?
    var displayName: String?
}

struct NekoAccountSummary: Codable, Equatable {
    var profile: NekoAccountProfile
    var catCount: Int
    var voiceCount: Int
}

struct CatProfile: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var gender: CatGender
    var ageStage: CatAgeStage
    var avatarObjectKey: String?
    var avatarURL: URL?
    var updatedAt: Date?
}

enum QuizChoice: String, Codable, Equatable {
    case a
    case b
}

struct QuizQuestion: Identifiable, Equatable {
    let id: Int
    let question: String
    let optionA: String
    let optionB: String

    static let onboarding: [QuizQuestion] = [
        QuizQuestion(id: 0, question: "陌生人来家里时，它通常会？", optionA: "立刻躲起来", optionB: "主动观察"),
        QuizQuestion(id: 1, question: "家里出现新玩具时，它会？", optionA: "立即研究", optionB: "观察很久再靠近"),
        QuizQuestion(id: 2, question: "你回家时，它会？", optionA: "马上出现", optionB: "假装不在意"),
        QuizQuestion(id: 3, question: "被抚摸的时候，它更喜欢？", optionA: "蹭过来", optionB: "保持一点距离"),
        QuizQuestion(id: 4, question: "听到突然的声响，它会？", optionA: "瞬间警觉", optionB: "懒得理你"),
        QuizQuestion(id: 5, question: "看见镜子里的自己，它会？", optionA: "好奇靠近", optionB: "完全无视"),
        QuizQuestion(id: 6, question: "你忙的时候，它通常？", optionA: "在你脚边", optionB: "找自己的位置"),
        QuizQuestion(id: 7, question: "睡觉时，它喜欢？", optionA: "和你贴着", optionB: "独占一个角落"),
    ]
}

struct PersonaTrait: Codable, Equatable, Identifiable {
    var id: String { label }
    let label: String
    let value: Int
}

struct PersonaObservation: Codable, Equatable, Identifiable {
    var id: String { "\(label)-\(value)" }
    let label: String
    let value: String
}

enum CatDetectionMode: String, Codable {
    case face
    case presence
}

struct CatDetectionResult: Decodable, Equatable {
    let isCat: Bool
    let reason: String?
}

struct CatPersonaResult: Codable, Equatable {
    var type: String
    var mbti: String
    var matchScore: Int
    var monologue: String
    var analysis: String
    var ownerRole: String
    var tags: [String]
    var traits: [PersonaTrait]
    var observations: [PersonaObservation]
    var dailyMood: String
    var provider: String = "ios-native"
    var model: String = "native-onboarding-v1"

    enum CodingKeys: String, CodingKey {
        case type
        case mbti
        case matchScore
        case monologue
        case analysis
        case ownerRole
        case tags
        case traits
        case observations
        case dailyMood
        case provider
        case model
    }

    init(
        type: String,
        mbti: String,
        matchScore: Int,
        monologue: String,
        analysis: String,
        ownerRole: String,
        tags: [String],
        traits: [PersonaTrait],
        observations: [PersonaObservation],
        dailyMood: String,
        provider: String = "ios-native",
        model: String = "native-onboarding-v1"
    ) {
        self.type = type
        self.mbti = mbti
        self.matchScore = matchScore
        self.monologue = monologue
        self.analysis = analysis
        self.ownerRole = ownerRole
        self.tags = tags
        self.traits = traits
        self.observations = observations
        self.dailyMood = dailyMood
        self.provider = provider
        self.model = model
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        mbti = try container.decode(String.self, forKey: .mbti)
        matchScore = try container.decode(Int.self, forKey: .matchScore)
        monologue = try container.decode(String.self, forKey: .monologue)
        analysis = try container.decode(String.self, forKey: .analysis)
        ownerRole = try container.decode(String.self, forKey: .ownerRole)
        tags = try container.decode([String].self, forKey: .tags)
        traits = try container.decode([PersonaTrait].self, forKey: .traits)
        observations = try container.decode([PersonaObservation].self, forKey: .observations)
        dailyMood = try container.decode(String.self, forKey: .dailyMood)
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? "server"
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? "neko-id-server-persona"
    }
}

struct CatVoiceResult: Codable, Equatable, Identifiable {
    var id: String { cloudId ?? "\(createdAt ?? 0)-\(text)" }

    var cloudId: String?
    var time: String
    var grad: String
    var text: String
    var location: String?
    var tags: [String]
    var createdAt: Int64?
    var mediaObjectKey: String?
    var mediaType: String?
    var aspect: String?
    var videoDuration: String?
    var analysis: String?
    var mediaURL: URL?

    enum CodingKeys: String, CodingKey {
        case cloudId
        case time
        case grad
        case text
        case location
        case tags
        case createdAt
        case mediaObjectKey
        case mediaType
        case aspect
        case videoDuration
        case analysis
        case mediaURL
    }

    init(
        cloudId: String? = nil,
        time: String,
        grad: String,
        text: String,
        location: String? = nil,
        tags: [String] = [],
        createdAt: Int64? = nil,
        mediaObjectKey: String? = nil,
        mediaType: String? = "photo",
        aspect: String? = "3:4",
        videoDuration: String? = nil,
        analysis: String? = nil,
        mediaURL: URL? = nil
    ) {
        self.cloudId = cloudId
        self.time = time
        self.grad = grad
        self.text = text
        self.location = location
        self.tags = tags
        self.createdAt = createdAt
        self.mediaObjectKey = mediaObjectKey
        self.mediaType = mediaType
        self.aspect = aspect
        self.videoDuration = videoDuration
        self.analysis = analysis
        self.mediaURL = mediaURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cloudId = try container.decodeIfPresent(String.self, forKey: .cloudId)
        time = try container.decodeIfPresent(String.self, forKey: .time) ?? "刚刚"
        grad = try container.decodeIfPresent(String.self, forKey: .grad)
            ?? "linear-gradient(135deg, oklch(0.9 0.06 280), oklch(0.92 0.05 320))"
        text = try container.decode(String.self, forKey: .text)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt = try container.decodeIfPresent(Int64.self, forKey: .createdAt)
        mediaObjectKey = try container.decodeIfPresent(String.self, forKey: .mediaObjectKey)
        mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType) ?? "photo"
        aspect = try container.decodeIfPresent(String.self, forKey: .aspect) ?? "3:4"
        videoDuration = try container.decodeIfPresent(String.self, forKey: .videoDuration)
        analysis = try container.decodeIfPresent(String.self, forKey: .analysis)
        mediaURL = try container.decodeIfPresent(URL.self, forKey: .mediaURL)
    }
}

struct OnboardingVideoClip: Identifiable, Equatable {
    let id: UUID
    let label: String
    let durationLabel: String
    let sizeLabel: String
    let thumbnailData: Data?

    init(
        id: UUID = UUID(),
        label: String,
        durationLabel: String,
        sizeLabel: String,
        thumbnailData: Data?
    ) {
        self.id = id
        self.label = label
        self.durationLabel = durationLabel
        self.sizeLabel = sizeLabel
        self.thumbnailData = thumbnailData
    }
}

struct CatProfileDraft: Equatable {
    var name = ""
    var gender: CatGender = .female
    var ageStage: CatAgeStage = .young

    init(name: String = "", gender: CatGender = .female, ageStage: CatAgeStage = .young) {
        self.name = name
        self.gender = gender
        self.ageStage = ageStage
    }

    init(profile: CatProfile) {
        self.name = profile.name
        self.gender = profile.gender
        self.ageStage = profile.ageStage
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 40
    }
}

enum AppPhase: Equatable, Hashable {
    case launching
    case signedOut
    case onboarding
    case home
}
