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
    let phone: String?

    var loginIdentifier: String? {
        phone?.nonEmpty ?? email?.nonEmpty
    }
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

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
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
    case c
}

struct QuizQuestion: Identifiable, Equatable {
    let id: Int
    let question: String
    let optionA: String
    let optionB: String
    let optionC: String

    static let onboarding: [QuizQuestion] = [
        QuizQuestion(id: 0, question: "陌生人来到家里时，它通常会？", optionA: "很快靠近，主动看看是谁", optionB: "保持一点距离，先观察一阵", optionC: "先躲起来，确定安全再说"),
        QuizQuestion(id: 1, question: "家里出现一个从没见过的东西，它通常？", optionA: "第一时间凑过去研究", optionB: "远远观察，过一会儿再靠近", optionC: "兴趣不大，基本懒得管"),
        QuizQuestion(id: 2, question: "你回到家时，它通常？", optionA: "很快出现，主动来迎接你", optionB: "看见你了，但继续待在原来的地方", optionC: "表面没什么反应，过一会儿才靠近"),
        QuizQuestion(id: 3, question: "它想让你做什么时，通常怎么告诉你？", optionA: "叫你、蹭你，想办法让你注意到", optionB: "待在附近看着你，等你自己发现", optionC: "直接行动，比如带你过去或扒拉东西"),
        QuizQuestion(id: 4, question: "突然出现很大的声音或动静，它通常？", optionA: "马上警觉，先确认发生了什么", optionB: "会被吓一下，但很快恢复正常", optionC: "基本没什么反应，该干嘛干嘛"),
        QuizQuestion(id: 5, question: "遇到自己不喜欢的互动时，它通常？", optionA: "很快明确表达：走开、挣脱或拒绝", optionB: "会忍一会儿，不舒服了才离开", optionC: "大多数时候都挺配合"),
        QuizQuestion(id: 6, question: "你忙自己的事情时，它通常？", optionA: "会主动来找你，希望你注意它", optionB: "喜欢待在你附近，但不一定打扰你", optionC: "自己找地方待着，各忙各的"),
        QuizQuestion(id: 7, question: "如果让它自己选，它最喜欢你怎么陪它？", optionA: "摸摸它、抱抱它，和它贴贴", optionB: "陪它玩、逗它，一起做点什么", optionC: "不用一直互动，待在它附近就好"),
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
    var corePersonality: String?
    var misunderstanding: String?
    var loveLanguage: String?
    var loveLanguageInsight: String?
    var ownerRole: String
    var ownerRelationship: String?
    var tags: [String]
    var traits: [PersonaTrait]
    var observations: [PersonaObservation]
    var evidence: [PersonaEvidence]
    var dailyMood: String
    var provider: String = "ios-native"
    var model: String = "native-onboarding-v1"

    enum CodingKeys: String, CodingKey {
        case type
        case mbti
        case matchScore
        case monologue
        case analysis
        case corePersonality
        case misunderstanding
        case loveLanguage
        case loveLanguageInsight
        case ownerRole
        case ownerRelationship
        case tags
        case traits
        case observations
        case evidence
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
        corePersonality: String? = nil,
        misunderstanding: String? = nil,
        loveLanguage: String? = nil,
        loveLanguageInsight: String? = nil,
        ownerRole: String,
        ownerRelationship: String? = nil,
        tags: [String],
        traits: [PersonaTrait],
        observations: [PersonaObservation],
        evidence: [PersonaEvidence] = [],
        dailyMood: String,
        provider: String = "ios-native",
        model: String = "native-onboarding-v1"
    ) {
        self.type = type
        self.mbti = mbti
        self.matchScore = matchScore
        self.monologue = monologue
        self.analysis = analysis
        self.corePersonality = corePersonality
        self.misunderstanding = misunderstanding
        self.loveLanguage = loveLanguage
        self.loveLanguageInsight = loveLanguageInsight
        self.ownerRole = ownerRole
        self.ownerRelationship = ownerRelationship
        self.tags = tags
        self.traits = traits
        self.observations = observations
        self.evidence = evidence
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
        corePersonality = try container.decodeIfPresent(String.self, forKey: .corePersonality)
        misunderstanding = try container.decodeIfPresent(String.self, forKey: .misunderstanding)
        loveLanguage = try container.decodeIfPresent(String.self, forKey: .loveLanguage)
        loveLanguageInsight = try container.decodeIfPresent(String.self, forKey: .loveLanguageInsight)
        ownerRole = try container.decode(String.self, forKey: .ownerRole)
        ownerRelationship = try container.decodeIfPresent(String.self, forKey: .ownerRelationship)
        tags = try container.decode([String].self, forKey: .tags)
        traits = try container.decode([PersonaTrait].self, forKey: .traits)
        observations = try container.decode([PersonaObservation].self, forKey: .observations)
        evidence = try container.decodeIfPresent([PersonaEvidence].self, forKey: .evidence) ?? []
        // `dailyMood` belonged to the first-generation home card and is no longer
        // emitted by the current persona prompt. Keep decoding older records, but
        // do not reject a valid persona result when the field is absent.
        dailyMood = try container.decodeIfPresent(String.self, forKey: .dailyMood) ?? ""
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? "server"
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? "neko-id-server-persona"
    }
}

struct PersonaEvidence: Codable, Equatable {
    var fact: String
    var interpretation: String
}

struct CatVoiceAnalysis: Codable, Equatable {
    var observation: String
    var personalityInterpretation: String

    private enum CodingKeys: String, CodingKey {
        case observation
        case summary
        case personalityInterpretation
    }

    init(observation: String, personalityInterpretation: String) {
        self.observation = observation
        self.personalityInterpretation = personalityInterpretation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        observation = try container.decodeIfPresent(String.self, forKey: .observation)
            ?? container.decodeIfPresent(String.self, forKey: .summary)
            ?? ""
        personalityInterpretation = try container.decodeIfPresent(String.self, forKey: .personalityInterpretation) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(observation, forKey: .observation)
        try container.encode(personalityInterpretation, forKey: .personalityInterpretation)
    }
}

struct CatVoiceShare: Codable, Equatable {
    var headline: String
    var insight: String
    var tags: [String]
}

struct CatVoiceResult: Codable, Equatable, Identifiable {
    var id: String { cloudId ?? "\(createdAt ?? 0)-\(text)" }

    var cloudId: String?
    var time: String
    var grad: String
    var text: String
    var subtext: String?
    var location: String?
    var tags: [String]
    var createdAt: Int64?
    var mediaObjectKey: String?
    var mediaType: String?
    var aspect: String?
    var videoDuration: String?
    var analysis: CatVoiceAnalysis?
    var share: CatVoiceShare?
    var mediaURL: URL?

    var analysisText: String? {
        guard let analysis else { return nil }
        return [analysis.observation, analysis.personalityInterpretation]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
            .nonEmpty
    }

    var insightSummary: String? { share?.insight.nonEmpty }

    enum CodingKeys: String, CodingKey {
        case cloudId
        case time
        case grad
        case text
        case subtext
        case location
        case tags
        case createdAt
        case mediaObjectKey
        case mediaType
        case aspect
        case videoDuration
        case analysis
        case share
        case mediaURL
    }

    init(
        cloudId: String? = nil,
        time: String,
        grad: String,
        text: String,
        subtext: String? = nil,
        location: String? = nil,
        tags: [String] = [],
        createdAt: Int64? = nil,
        mediaObjectKey: String? = nil,
        mediaType: String? = "photo",
        aspect: String? = "3:4",
        videoDuration: String? = nil,
        analysis: CatVoiceAnalysis? = nil,
        share: CatVoiceShare? = nil,
        mediaURL: URL? = nil
    ) {
        self.cloudId = cloudId
        self.time = time
        self.grad = grad
        self.text = text
        self.subtext = subtext
        self.location = location
        self.tags = tags
        self.createdAt = createdAt
        self.mediaObjectKey = mediaObjectKey
        self.mediaType = mediaType
        self.aspect = aspect
        self.videoDuration = videoDuration
        self.analysis = analysis
        self.share = share
        self.mediaURL = mediaURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cloudId = try container.decodeIfPresent(String.self, forKey: .cloudId)
        time = try container.decodeIfPresent(String.self, forKey: .time) ?? "刚刚"
        grad = try container.decodeIfPresent(String.self, forKey: .grad)
            ?? "linear-gradient(135deg, oklch(0.9 0.06 280), oklch(0.92 0.05 320))"
        text = try container.decode(String.self, forKey: .text)
        subtext = try container.decodeIfPresent(String.self, forKey: .subtext)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt = try container.decodeIfPresent(Int64.self, forKey: .createdAt)
        mediaObjectKey = try container.decodeIfPresent(String.self, forKey: .mediaObjectKey)
        mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType) ?? "photo"
        aspect = try container.decodeIfPresent(String.self, forKey: .aspect) ?? "3:4"
        videoDuration = try container.decodeIfPresent(String.self, forKey: .videoDuration)
        if let structured = try? container.decode(CatVoiceAnalysis.self, forKey: .analysis) {
            analysis = structured
        } else if let legacy = try? container.decode(String.self, forKey: .analysis), !legacy.isEmpty {
            analysis = CatVoiceAnalysis(observation: legacy, personalityInterpretation: "")
        } else {
            analysis = nil
        }
        share = try container.decodeIfPresent(CatVoiceShare.self, forKey: .share)
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
