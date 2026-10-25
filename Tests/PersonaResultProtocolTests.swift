import Foundation

@main
enum PersonaResultProtocolTests {
    static let decoder = JSONDecoder()

    static let dimensions: [[String: Any]] = [
        ["key": "social", "name": "社交倾向", "leftLabel": "主动亲近", "rightLabel": "慢热谨慎", "direction": "center_left", "strength": "medium"],
        ["key": "exploration", "name": "探索倾向", "leftLabel": "好奇探索", "rightLabel": "稳定保守", "direction": "left", "strength": "strong"],
        ["key": "companionship", "name": "陪伴倾向", "leftLabel": "喜欢陪伴", "rightLabel": "独立自主", "direction": "center", "strength": "weak"],
        ["key": "boundary", "name": "边界倾向", "leftLabel": "接受互动", "rightLabel": "边界明确", "direction": "center_right", "strength": "medium"],
    ]

    static let insights: [String: Any] = [
        "misunderstanding": ["title": "你可能一直误会它的一件事", "conclusion": "它不是没兴趣，只是会先确认。"],
        "affection": ["title": "它表达喜欢的方式", "conclusion": "它会把注意力放在你身上。"],
        "relationship": ["title": "在它眼里，你的位置", "conclusion": "你是它愿意回到附近的人。"],
    ]

    static var canonical: [String: Any] {
        [
            "persona": ["mbti": "INTJ-A", "personaTitle": "慢热观察型", "summary": "它会先确认环境，再按自己的节奏靠近。"],
            "dimensions": dimensions,
            "insights": insights,
            "bondSummary": ["title": "你们的关系", "quote": "你是它愿意放心靠近的人。"],
        ]
    }

    static var legacy: [String: Any] {
        [
            "type": "先看再行动", "mbti": "ISFP-A", "matchScore": 88,
            "monologue": "让我先看看。", "analysis": "它会先观察再靠近。",
            "corePersonality": "它谨慎但愿意亲近。", "misunderstanding": "它不是冷淡。",
            "loveLanguageInsight": "它会待在你附近。", "ownerRole": "你是它的安全参照。",
            "traits": [
                ["label": "亲近感", "value": 68], ["label": "好奇心", "value": 82],
                ["label": "陪伴倾向", "value": 60], ["label": "边界感", "value": 75],
            ],
            "tags": ["先观察再靠近"], "observations": [], "evidence": [], "dailyMood": "",
        ]
    }

    static func decode(_ object: [String: Any]) throws -> CatPersonaResult {
        try decoder.decode(CatPersonaResult.self, from: JSONSerialization.data(withJSONObject: object))
    }

    static func expectFailure(_ object: [String: Any], _ label: String) {
        do {
            _ = try decode(object)
            preconditionFailure("Expected failure: \(label)")
        } catch {}
    }

    static func main() throws {
        let newResult = try decode(canonical)
        precondition(newResult.isCanonicalValid && newResult.dimensions.count == 4)

        let oldResult = try decode(legacy)
        precondition(oldResult.isCanonicalValid)
        precondition(oldResult.persona.personaTitle == "先看再行动")
        precondition(Set(oldResult.dimensions.map(\.key)) == Set(PersonaDimensionKey.allCases))

        var mixed = legacy
        for (key, value) in canonical { mixed[key] = value }
        mixed["type"] = "冲突旧标题"
        let mixedResult = try decode(mixed)
        precondition(mixedResult.persona.personaTitle == "慢热观察型")
        precondition(mixedResult.type == "慢热观察型")

        var missingDimensions = canonical
        missingDimensions.removeValue(forKey: "dimensions")
        expectFailure(missingDimensions, "missing dimensions")

        var missingInsights = canonical
        missingInsights.removeValue(forKey: "insights")
        expectFailure(missingInsights, "missing insights")

        var missingBond = canonical
        missingBond.removeValue(forKey: "bondSummary")
        expectFailure(missingBond, "missing bondSummary")

        var invalidEnum = canonical
        var invalidDimensions = dimensions
        invalidDimensions[0]["direction"] = "mostly_left"
        invalidEnum["dimensions"] = invalidDimensions
        expectFailure(invalidEnum, "invalid direction enum")

        precondition(oldResult.dimensions.first(where: { $0.key == .exploration })?.direction == .left)
        precondition(oldResult.dimensions.first(where: { $0.key == .boundary })?.direction == .centerRight)

        print("PASS: Persona Result protocol and legacy migration (8 scenarios)")
    }
}
