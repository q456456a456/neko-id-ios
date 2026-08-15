//
//  PersonaGenerator.swift
//  neko-id
//
//  Created by Codex on 2026/8/15.
//

import Foundation

enum PersonaGenerator {
    static func generate(
        profile draft: CatProfileDraft,
        quizAnswers: [Int: QuizChoice],
        videoCount: Int,
        hasAvatar: Bool
    ) -> CatPersonaResult {
        let name = draft.trimmedName.isEmpty ? "这只小猫" : draft.trimmedName
        var affection = 56
        var independence = 56
        var curiosity = 56
        var security = 58
        var alertness = 52

        for (index, choice) in quizAnswers {
            switch (index, choice) {
            case (0, .a):
                security += 10
                alertness += 6
            case (0, .b):
                curiosity += 10
            case (1, .a):
                curiosity += 12
            case (1, .b):
                security += 8
                alertness += 4
            case (2, .a):
                affection += 12
            case (2, .b):
                independence += 8
            case (3, .a):
                affection += 10
            case (3, .b):
                independence += 10
            case (4, .a):
                alertness += 12
                security += 4
            case (4, .b):
                independence += 8
            case (5, .a):
                curiosity += 10
            case (5, .b):
                independence += 6
            case (6, .a):
                affection += 9
                security += 4
            case (6, .b):
                independence += 10
            case (7, .a):
                affection += 11
                security += 5
            case (7, .b):
                independence += 9
            default:
                break
            }
        }

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

        if curiosity >= 78 && affection >= 70 {
            type = "好奇贴贴家"
            mbti = "ENFP-A"
            mood = "今天也想探索新角落"
        } else if independence >= 78 && alertness >= 65 {
            type = "优雅观察者"
            mbti = "INTJ-A"
            mood = "安静观察，也悄悄在意你"
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
