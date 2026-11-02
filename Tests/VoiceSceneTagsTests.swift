import Foundation

// Run with Models.swift and VoiceTimestampFormatter.swift (no simulator needed).
@main
enum VoiceSceneTagsTests {
    static func decode(_ fields: [String: Any]) throws -> CatVoiceResult {
        var payload = fields
        payload["text"] = "先把球放着，我想再看一会儿。"
        return try JSONDecoder().decode(CatVoiceResult.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    static func main() throws {
        let shortTags = ["看球", "想玩了", "准备出爪"]
        let cases: [([String: Any], [String])] = [
            (["sceneTags": shortTags], shortTags),
            (["tags": shortTags], shortTags),
            (["sceneTags": shortTags, "tags": ["旧的标签"]], shortTags),
            (["sceneTags": NSNull(), "tags": shortTags], shortTags),
            (["sceneTags": [], "tags": shortTags], []),
            ([:], []),
            (["sceneTags": [" #看球 ", "看球", "想玩了", "准备出爪", "歇会儿"]], shortTags),
            (["tags": ["先观察一会再决定", "歇会儿", "好奇"]], ["先观察一会再决定", "歇会儿", "好奇"]),
            (["sceneTags": ["", "猫", "这条标签长度超过了十个字", "𠮷猫", "想玩了"]], ["𠮷猫", "想玩了"]),
        ]
        for (fields, expected) in cases {
            let result = try decode(fields)
            precondition(result.sceneTags == expected, "sceneTags lost or changed: \(fields)")
            precondition(result.tags == expected, "Legacy alias diverged")
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as! [String: Any]
            precondition(encoded["sceneTags"] as? [String] == expected)
            precondition(encoded["tags"] as? [String] == expected)
            let roundTrip = try JSONDecoder().decode(CatVoiceResult.self, from: JSONEncoder().encode(result))
            precondition(roundTrip == result)
        }
        var initialized = CatVoiceResult(time: "刚刚", grad: "", text: "看看", sceneTags: shortTags)
        precondition(initialized.sceneTags == shortTags)
        initialized.tags = [" #观察 ", "准备出爪", "观察", "歇会儿"]
        precondition(initialized.sceneTags == ["观察", "准备出爪", "歇会儿"])
        let legacyInit = CatVoiceResult(time: "刚刚", grad: "", text: "看看", tags: shortTags)
        precondition(legacyInit.sceneTags == shortTags)
        print("PASS: short sceneTags, legacy tags, field precedence, historical labels, deduplication and Codable round trips")
    }
}
