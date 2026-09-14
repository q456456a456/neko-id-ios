//
//  PersonaGenerator.swift
//  neko-id
//
//  Created by Codex on 2026/8/15.
//

import Foundation

private struct BehaviorProfile {
    let sociability: Int?
    let curiosity: Int?
    let caution: Int?
    let attachmentExpression: Int?
    let independence: Int?
    let boundary: Int?
    let environmentalSensitivity: Int?
    let interactionPreference: Int?
    let loveLanguage: String
    let needExpression: String

    var vigilance: Int? { environmentalSensitivity ?? caution }
    var attachment: Int? { attachmentExpression }
    var expressiveness: Int? { interactionPreference }

    static func from(_ answers: [Int: QuizChoice]) -> BehaviorProfile {
        let keys = ["sociability", "curiosity", "caution", "attachmentExpression", "independence", "boundary", "environmentalSensitivity", "interactionPreference"]
        var sums = Dictionary(uniqueKeysWithValues: keys.map { ($0, 0) })
        var counts = sums
        let deltas: [Int: [QuizChoice: [String: Int]]] = [
            0: [.a: ["sociability": 2, "caution": -1], .b: ["caution": 1], .c: ["sociability": -2, "caution": 2]],
            1: [.a: ["curiosity": 2, "caution": -1], .b: ["curiosity": 1, "caution": 2], .c: ["curiosity": -2]],
            2: [.a: ["attachmentExpression": 2, "independence": -1], .b: ["attachmentExpression": 1, "independence": 1], .c: ["attachmentExpression": -1, "independence": 2]],
            3: [.a: ["attachmentExpression": 2, "interactionPreference": 2], .b: ["attachmentExpression": 1, "interactionPreference": -1], .c: ["independence": 2, "interactionPreference": 1]],
            4: [.a: ["environmentalSensitivity": 2, "caution": 1], .b: ["environmentalSensitivity": 1], .c: ["environmentalSensitivity": -2]],
            5: [.a: ["boundary": 2], .b: ["boundary": 1], .c: ["boundary": -2]],
            6: [.a: ["attachmentExpression": 2, "independence": -1], .b: ["independence": 2], .c: ["independence": 1, "curiosity": 1]],
            7: [.a: ["interactionPreference": 2, "attachmentExpression": 2], .b: ["interactionPreference": 0, "independence": 1], .c: ["interactionPreference": -2, "independence": 2]],
        ]
        for (index, answer) in answers {
            for (key, delta) in deltas[index]?[answer] ?? [:] {
                sums[key, default: 0] += delta
                counts[key, default: 0] += 1
            }
        }
        func score(_ key: String) -> Int? {
            guard let count = counts[key], count > 0 else { return nil }
            return min(82, max(18, Int((50 + Double(sums[key, default: 0]) / Double(count) * 16).rounded())))
        }
        return BehaviorProfile(
            sociability: score("sociability"), curiosity: score("curiosity"), caution: score("caution"),
            attachmentExpression: score("attachmentExpression"), independence: score("independence"), boundary: score("boundary"),
            environmentalSensitivity: score("environmentalSensitivity"), interactionPreference: score("interactionPreference"),
            loveLanguage: answers[7] == .a ? "密集互动" : answers[7] == .b ? "安静共处" : answers[7] == .c ? "按需靠近" : "未知",
            needExpression: answers[3] == .a ? "直球型" : answers[3] == .b ? "暗示型" : answers[3] == .c ? "行动型" : "未知"
        )
    }
}

enum PersonaGenerator {
    static func generate(
        profile draft: CatProfileDraft,
        quizAnswers: [Int: QuizChoice],
        videoCount: Int,
        hasAvatar: Bool
    ) -> CatPersonaResult {
        let name = draft.trimmedName.isEmpty ? "这只小猫" : draft.trimmedName
        let behavior = BehaviorProfile.from(quizAnswers)
        var affection = behavior.attachment ?? 50
        var independence = behavior.independence ?? (100 - (behavior.attachment ?? 50))
        var curiosity = behavior.curiosity ?? 50
        var security = 100 - (behavior.vigilance ?? 50)
        var alertness = behavior.vigilance ?? 50
        let expressiveness = behavior.expressiveness ?? 50
        let boundary = behavior.boundary ?? 50
        let sociability = behavior.sociability ?? 50

        switch draft.ageStage {
        case .kitten:
            curiosity += 12
            affection += 6
        case .young:
            curiosity += 8
            independence += 4
        case .adult:
            security += 8
            independence += 6
        case .senior:
            security += 12
            alertness += 5
        }

        let type: String
        let mbti: String
        let mood: String

        if affection >= 68 && expressiveness <= 42 {
            type = "安静亲近型"
            mbti = "ISFJ-A"
            mood = "在意你，但表达得很安静"
        } else if sociability <= 42 && affection >= 68 {
            type = "熟了会更黏"
            mbti = "INFJ-A"
            mood = "只对熟悉的人主动"
        } else if curiosity >= 68 && alertness >= 68 {
            type = "好奇但谨慎"
            mbti = "INTP-T"
            mood = "好奇，但要先确认安全"
        } else if curiosity >= 68 && affection >= 68 {
            type = "爱玩也爱亲近"
            mbti = "ENFP-A"
            mood = "今天也想探索新角落"
        } else if boundary >= 68 && affection >= 68 {
            type = "主动亲近有边界"
            mbti = "INTJ-A"
            mood = "亲近要按自己的节奏"
        } else if security >= 78 {
            type = "先观察再靠近"
            mbti = "ISFJ-A"
            mood = "确认安全后才会靠近"
        } else if affection >= 76 {
            type = "喜欢待在你附近"
            mbti = "INFP-A"
            mood = "想待在你附近，假装只是路过"
        } else {
            type = ageDefaultType(for: draft.ageStage)
            mbti = ageDefaultMBTI(for: draft.ageStage)
            mood = ageDefaultMood(for: draft.ageStage)
        }

        let matchScore = min(
            97,
            82 + min(8, quizAnswers.count) + (hasAvatar ? 3 : 0) + min(4, videoCount * 2)
        )

        let strongest = [
            PersonaTrait(label: "亲近感", value: clamp(affection)),
            PersonaTrait(label: "独立性", value: clamp(independence)),
            PersonaTrait(label: "好奇心", value: clamp(curiosity)),
            PersonaTrait(label: "安全感", value: clamp(security)),
            PersonaTrait(label: "警觉度", value: clamp(alertness)),
        ]
        .sorted { $0.value > $1.value }
        .prefix(3)

        let tags = buildTags(
            type: type,
            affection: affection,
            independence: independence,
            curiosity: curiosity,
            security: security,
            alertness: alertness,
            videoCount: videoCount
        )

        return CatPersonaResult(
            type: type,
            mbti: mbti,
            matchScore: matchScore,
            monologue: buildMonologue(name: name, affection: affection, independence: independence, curiosity: curiosity),
            analysis: "\(name)是\(draft.ageStage.rawValue)里的\(draft.gender.rawValue)，性格里有\(dominantWords(from: Array(strongest)))。它会用自己的节奏观察环境，再通过靠近、停留或回望表达情绪。",
            misunderstanding: independence >= affection
                ? "它不是不需要你，只是更习惯自己决定靠近的距离。很多看似各待各的时刻，也可能是它在舒服地和你共享空间。"
                : "它不是时时靠近才算在意。就算暂时没有贴着你，它也可能一直留意你的动向，等自己认可的时机再靠近。",
            loveLanguage: affection >= independence
                ? "它更可能通过主动靠近、停留和回应你的动作表达喜欢；熟悉之后，这些小动作会比对陌生人明显得多。"
                : "它可能更习惯待在你附近、关注你的动向，却不一定长时间贴着。给它选择距离的自由，反而更容易看到它主动靠近。",
            ownerRole: "在\(name)眼里，你是它熟悉的小坐标。它不一定每次都热烈回应，但会把你的声音、脚步和日常节奏放进自己的安全地图里。",
            tags: tags,
            traits: Array(strongest),
            observations: [
                PersonaObservation(label: "视频行为", value: videoCount > 0 ? "已记录 \(videoCount) 段日常视频" : "暂未记录视频"),
                PersonaObservation(label: "行为问答", value: "完成 \(quizAnswers.count) / \(QuizQuestion.onboarding.count) 个线索"),
                PersonaObservation(label: "关系倾向", value: affection >= independence ? "更愿意靠近熟悉的人" : "保留边界，也会默默陪伴"),
                PersonaObservation(label: "年龄阶段", value: "\(draft.ageStage.rawValue)特征已纳入分析"),
            ],
            evidence: buildEvidence(from: quizAnswers),
            dailyMood: mood
        )
    }

    private static func buildEvidence(from answers: [Int: QuizChoice]) -> [PersonaEvidence] {
        let answerCode: (Int) -> String? = { index in
            answers[index].map { "Q\(index + 1):\($0.rawValue.uppercased())" }
        }
        let groups: [(String, String, [Int])] = [
            ("面对变化的反应", "陌生人和新事物的回答共同描述它是直接靠近，还是先确认安全。", [0, 1]),
            ("亲近的表达方式", "迎接方式、需求表达和日常距离共同支持它如何让主人感受到在意。", [2, 3, 6]),
            ("边界与陪伴偏好", "拒绝互动和偏好的陪伴方式共同说明它更舒服的相处节奏。", [5, 7]),
        ]

        return groups.compactMap { fact, interpretation, indexes in
            let supportedBy = indexes.compactMap(answerCode)
            guard !supportedBy.isEmpty else { return nil }
            return PersonaEvidence(
                fact: fact,
                interpretation: interpretation,
                supportedBy: supportedBy,
                confidence: min(0.92, 0.46 + Double(supportedBy.count) * 0.16)
            )
        }
    }

    private static func clamp(_ value: Int) -> Int {
        min(98, max(36, value))
    }

    private static func ageDefaultType(for stage: CatAgeStage) -> String {
        switch stage {
        case .kitten:
            return "小小探险家"
        case .young:
            return "好奇观察型"
        case .adult:
            return "安静陪伴型"
        case .senior:
            return "慢节奏陪伴型"
        }
    }

    private static func ageDefaultMBTI(for stage: CatAgeStage) -> String {
        switch stage {
        case .kitten:
            return "ENFP-A"
        case .young:
            return "INFP-A"
        case .adult:
            return "ISFJ-A"
        case .senior:
            return "INFJ-A"
        }
    }

    private static func ageDefaultMood(for stage: CatAgeStage) -> String {
        switch stage {
        case .kitten:
            return "想玩，也想被你看见"
        case .young:
            return "对世界很好奇，也对你很在意"
        case .adult:
            return "今天想安稳地陪你一会"
        case .senior:
            return "慢慢看着你，就是它的温柔"
        }
    }

    private static func buildTags(
        type: String,
        affection: Int,
        independence: Int,
        curiosity: Int,
        security: Int,
        alertness: Int,
        videoCount: Int
    ) -> [String] {
        var tags: [String] = []
        if affection >= 74 { tags.append("主动靠近") }
        if independence >= 74 { tags.append("喜欢自己决定") }
        if curiosity >= 74 { tags.append("喜欢探索") }
        if security >= 74 { tags.append("熟悉后更放松") }
        if alertness >= 70 { tags.append("先观察再靠近") }
        if videoCount > 1 { tags.append("会主动回应") }
        tags.append(contentsOf: ["不爱强抱", "边界感强", "喜欢待在附近"])
        return Array(NSOrderedSet(array: tags).compactMap { $0 as? String }.prefix(6))
    }

    private static func buildMonologue(
        name: String,
        affection: Int,
        independence: Int,
        curiosity: Int
    ) -> String {
        if affection >= independence && affection >= curiosity {
            return "我只是刚好路过你身边，才不是特地来陪你的。"
        }
        if independence >= affection && independence >= curiosity {
            return "我有自己的小宇宙，但你在的时候，那里会亮一点。"
        }
        return "这个世界有好多新鲜事，但我也会记得回头看看你。"
    }

    private static func dominantWords(from traits: [PersonaTrait]) -> String {
        traits.map(\.label).joined(separator: "、")
    }
}

enum PersonaStabilityPolicy {
    private static let forbiddenTerms = [
        "营业", "控场", "发令", "施压", "稳态", "高质互动", "策略性靠近",
    ]

    static func stabilize(
        _ current: CatPersonaResult,
        previous: CatPersonaResult?,
        currentAnswers: [Int: QuizChoice]
    ) -> CatPersonaResult {
        guard let previous else { return current }
        guard !hasStrongNewEvidence(current: current, previous: previous, currentAnswers: currentAnswers) else {
            return current
        }

        var stabilized = current
        if isNaturalTitle(previous.type) {
            stabilized.type = previous.type
        }
        stabilized.mbti = previous.mbti
        stabilized.traits = previous.traits
        stabilized.corePersonality = previous.corePersonality ?? current.corePersonality
        stabilized.misunderstanding = previous.misunderstanding ?? current.misunderstanding
        stabilized.loveLanguage = previous.loveLanguage ?? current.loveLanguage
        stabilized.loveLanguageInsight = previous.loveLanguageInsight ?? current.loveLanguageInsight
        stabilized.ownerRole = previous.ownerRole
        stabilized.ownerRelationship = previous.ownerRelationship ?? current.ownerRelationship

        let anchoredTags = Array(previous.tags.prefix(2)) + current.tags
        stabilized.tags = Array(NSOrderedSet(array: anchoredTags).compactMap { $0 as? String }.prefix(4))
        return stabilized
    }

    private static func hasStrongNewEvidence(
        current: CatPersonaResult,
        previous: CatPersonaResult,
        currentAnswers: [Int: QuizChoice]
    ) -> Bool {
        let previousAnswers = answers(from: previous.evidence)
        if !previousAnswers.isEmpty {
            let changedAnswers = Set(previousAnswers.keys).union(currentAnswers.keys).reduce(into: 0) { count, key in
                if previousAnswers[key] != currentAnswers[key] { count += 1 }
            }
            if changedAnswers > 1 { return true }
        }

        let previousTraits = Dictionary(uniqueKeysWithValues: previous.traits.map { ($0.label, $0.value) })
        let sharedDifferences = current.traits.compactMap { trait -> Int? in
            guard let prior = previousTraits[trait.label] else { return nil }
            return abs(prior - trait.value)
        }
        guard sharedDifferences.count >= 2 else { return false }
        let averageDifference = Double(sharedDifferences.reduce(0, +)) / Double(sharedDifferences.count)
        return averageDifference >= 15
    }

    private static func answers(from evidence: [PersonaEvidence]) -> [Int: QuizChoice] {
        var answers: [Int: QuizChoice] = [:]
        for item in evidence {
            for code in item.supportedBy {
                let parts = code.split(separator: ":")
                guard parts.count == 2,
                      let question = Int(parts[0].dropFirst()),
                      let choice = QuizChoice(rawValue: parts[1].lowercased()) else { continue }
                answers[question - 1] = choice
            }
        }
        return answers
    }

    private static func isNaturalTitle(_ value: String) -> Bool {
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixes = ["控", "王", "机"]
        return !title.isEmpty &&
            title.count <= 14 &&
            !suffixes.contains(where: title.hasSuffix) &&
            !forbiddenTerms.contains(where: title.contains)
    }
}
