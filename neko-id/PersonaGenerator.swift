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
    let vigilance: Int?
    let attachment: Int?
    let expressiveness: Int?
    let boundary: Int?
    let loveLanguage: String
    let needExpression: String

    static func from(_ answers: [Int: QuizChoice]) -> BehaviorProfile {
        let keys = ["sociability", "curiosity", "vigilance", "attachment", "expressiveness", "boundary"]
        var sums = Dictionary(uniqueKeysWithValues: keys.map { ($0, 0) })
        var counts = sums
        let deltas: [Int: [QuizChoice: [String: Int]]] = [
            0: [.a: ["sociability": 2, "vigilance": -1], .b: ["sociability": 0, "vigilance": 1], .c: ["sociability": -2, "vigilance": 2]],
            1: [.a: ["curiosity": 2, "vigilance": -1], .b: ["curiosity": 1, "vigilance": 2], .c: ["curiosity": -2, "vigilance": -1]],
            2: [.a: ["attachment": 2, "expressiveness": 2], .b: ["attachment": 1, "expressiveness": -1], .c: ["attachment": 2, "expressiveness": -2]],
            3: [.a: ["expressiveness": 2, "attachment": 1], .b: ["expressiveness": -2, "attachment": 1], .c: ["expressiveness": 1, "curiosity": 1]],
            4: [.a: ["vigilance": 2], .b: ["vigilance": 0], .c: ["vigilance": -2]],
            5: [.a: ["boundary": 2, "expressiveness": 1], .b: ["boundary": 1, "expressiveness": -1], .c: ["boundary": -2]],
            6: [.a: ["attachment": 2, "expressiveness": 2], .b: ["attachment": 2, "expressiveness": -1], .c: ["attachment": -1, "expressiveness": -1]],
            7: [.a: ["attachment": 2, "boundary": -1], .b: ["attachment": 1, "curiosity": 2], .c: ["attachment": 1, "boundary": 2]],
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
            sociability: score("sociability"), curiosity: score("curiosity"), vigilance: score("vigilance"),
            attachment: score("attachment"), expressiveness: score("expressiveness"), boundary: score("boundary"),
            loveLanguage: answers[7] == .a ? "亲密接触" : answers[7] == .b ? "互动玩耍" : answers[7] == .c ? "安静共处" : "未知",
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
        var independence = 100 - (behavior.attachment ?? 50)
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
            type = "喜欢你但不爱黏着你"
            mbti = "ISFJ-A"
            mood = "在意你，但表达得很安静"
        } else if sociability <= 42 && affection >= 68 {
            type = "熟人限定的小黏猫"
            mbti = "INFJ-A"
            mood = "只对熟悉的人主动"
        } else if curiosity >= 68 && alertness >= 68 {
            type = "又怂又想看的好奇派"
            mbti = "INTP-T"
            mood = "好奇，但要先确认安全"
        } else if curiosity >= 68 && affection >= 68 {
            type = "爱玩也爱找你的小猫"
            mbti = "ENFP-A"
            mood = "今天也想探索新角落"
        } else if boundary >= 68 && affection >= 68 {
            type = "喜欢你也很有边界"
            mbti = "INTJ-A"
            mood = "亲近要按自己的节奏"
        } else if security >= 78 {
            type = "慢热守护者"
            mbti = "ISFJ-A"
            mood = "确认安全后才会靠近"
        } else if affection >= 76 {
            type = "温柔陪伴者"
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
            dailyMood: mood
        )
    }

    private static func clamp(_ value: Int) -> Int {
        min(98, max(36, value))
    }

    private static func ageDefaultType(for stage: CatAgeStage) -> String {
        switch stage {
        case .kitten:
            return "小小探险家"
        case .young:
            return "灵动观察者"
        case .adult:
            return "从容陪伴者"
        case .senior:
            return "安静小智者"
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
        var tags = [type]
        if affection >= 74 { tags.append("温柔贴近") }
        if independence >= 74 { tags.append("独立有边界") }
        if curiosity >= 74 { tags.append("好奇心旺") }
        if security >= 74 { tags.append("需要安全感") }
        if alertness >= 70 { tags.append("观察细腻") }
        if videoCount > 1 { tags.append("动态线索丰富") }
        tags.append(contentsOf: ["慢热可爱", "小小主见", "陪伴型"])
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
