import Foundation

// swiftc neko-id/Models.swift neko-id/VoiceTimestampFormatter.swift neko-id/PersonaGenerator.swift Tests/PersonaStabilityPolicyTests.swift -o /tmp/neko-persona-stability-tests
@main
enum PersonaStabilityPolicyTests {
    static func main() throws {
        let answers: [Int: QuizChoice] = [0: .a, 1: .b, 2: .a, 3: .b, 4: .c, 5: .a, 6: .b, 7: .a]
        var current = PersonaGenerator.generate(profile: CatProfileDraft(), quizAnswers: answers, videoCount: 0, hasAvatar: false)
        current.mbti = "ENTJ-A"
        current.persona = PersonaSummary(mbti: current.mbti, personaTitle: current.type, summary: current.persona.summary)
        var previous = current
        previous.mbti = "ISFP-A"
        previous.persona = PersonaSummary(mbti: previous.mbti, personaTitle: previous.type, summary: previous.persona.summary)
        previous.questionnaireAnswers = answers
        previous.traits = [PersonaTrait(label: "旧维度", value: 0)]

        func check(_ quiz: [Int: QuizChoice], prior: CatPersonaResult?, retain: Bool) {
            precondition((PersonaStabilityPolicy.referencePersona(prior, currentAnswers: quiz) != nil) == retain)
            let result = PersonaStabilityPolicy.stabilize(current, previous: prior, currentAnswers: quiz)
            precondition(result.mbti == (retain ? "ISFP-A" : "ENTJ-A"))
            precondition(result.persona.mbti == result.mbti, "Canonical and legacy MBTI must remain aligned after merging the new protocol")
            precondition(result.isCanonicalValid)
            precondition(result.questionnaireAnswers == quiz)
        }

        check(answers, prior: previous, retain: true)
        for question in answers.keys {
            for choice in [QuizChoice.a, .b, .c] where choice != answers[question] {
                var changed = answers
                changed[question] = choice
                check(changed, prior: previous, retain: false)
            }
            var removed = answers
            removed.removeValue(forKey: question)
            check(removed, prior: previous, retain: false)
            var partial = previous
            partial.questionnaireAnswers = removed
            check(answers, prior: partial, retain: false)
        }
        var unknown = previous
        unknown.questionnaireAnswers = nil
        check(answers, prior: unknown, retain: false)
        check([:], prior: unknown, retain: false)
        check(answers, prior: nil, retain: false)
        var empty = previous
        empty.questionnaireAnswers = [:]
        check([:], prior: empty, retain: true)

        let data = try JSONEncoder().encode(previous)
        let restored = try JSONDecoder().decode(CatPersonaResult.self, from: data)
        check(answers, prior: restored, retain: true)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let encodedAnswers = json["questionnaireAnswers"] as! [String: String]
        precondition(encodedAnswers["7"] == "a", "Snapshot must use the backend's JSON object format")
        json.removeValue(forKey: "questionnaireAnswers")
        let legacy = try JSONDecoder().decode(CatPersonaResult.self, from: JSONSerialization.data(withJSONObject: json))
        check(answers, prior: legacy, retain: false)
        let refreshed = PersonaStabilityPolicy.stabilize(current, previous: legacy, currentAnswers: answers)
        precondition(refreshed.questionnaireAnswers == answers)
        print("PASS: exact-match retention, all 8 single-choice changes, additions/removals, unknown/empty snapshots, legacy decoding and JSON round trip")
    }
}
