import SwiftUI
import UIKit

// Standalone simulator fixture, copied over the app entry point by
// run-persona-layout-checks.sh. Never included in the shipping app or its data flow.
@main
struct PersonaResultLayoutTestApp: App {
    @StateObject private var appModel = NekoAppModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                LovablePersonaResultPage(
                    catName: "丸子", avatarImage: UIImage(named: "neko-hero"),
                    avatarURL: nil, avatarObjectKey: nil,
                    persona: LayoutFixture.persona, onBack: {}, onRestart: {}, onSave: {}
                )
            }
            .environmentObject(appModel)
            .preferredColorScheme(.light)
            .task { LayoutFixture.runChecks() }
        }
    }
}

@MainActor
private enum LayoutFixture {
    static let description = "丸子是个既亲人又很有耐心的互动小能手。面对玩具和逗弄，它很少盲目乱扑，而是喜欢先找个掩护。"
    static let tags = ["先观察再出手", "喜欢暗中埋伏", "对人很亲近", "玩耍时极专注"]
    static let misunderstanding = "它蹲在掩体后不动不是胆小或不想玩，而是在认真观察、锁定目标，那是它专属的蓄力前奏。"
    static let loveLanguage = "它会把所有的专注力都放在你身上，用每一次全力以赴的伏击和出爪，认真回应你的每一次逗弄。"
    static let ownerRole = "你既是让它能安心卸下防备的靠山，也是能彻底激发它捕猎热情的最佳玩伴。"
    static let persona = CatPersonaResult(
        type: "认真观察的小猎手", mbti: "ISFP-A", matchScore: 90,
        monologue: description, analysis: description, corePersonality: description,
        misunderstanding: misunderstanding, loveLanguageInsight: loveLanguage,
        ownerRole: ownerRole, tags: tags, traits: [], observations: [], dailyMood: ""
    )

    static func hero(width: CGFloat, title: String, description: String, tags: [String], image: UIImage?) -> some View {
        LovableResultHero(
            catName: "丸子", avatarImage: image, avatarURL: nil, avatarObjectKey: nil,
            personaType: title, personaMbti: "ISFP-A", coreDescription: description,
            keywords: tags, contentWidth: width
        )
    }

    static func render<V: View>(_ view: V, width: CGFloat) -> UIImage {
        let renderer = ImageRenderer(content: view.environmentObject(NekoAppModel()))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.scale = 2
        guard let image = renderer.uiImage else { preconditionFailure("ImageRenderer failed") }
        precondition(abs(image.size.width - width) < 1, "Content must stay within the requested width")
        return image
    }

    static func photo(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemGray6.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    static func runChecks() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var results: [String] = []
        for width: CGFloat in [320, 375, 393, 430] {
            let compact = render(hero(width: width, title: "慢热观察派", description: "先观察再行动。", tags: ["亲人"], image: nil), width: width)
            let normal = render(hero(width: width, title: "认真观察的小猎手", description: description, tags: tags, image: nil), width: width)
            precondition(normal.size.height > compact.size.height + 50, "Long copy and wrapped tags must increase the hero height")

            for size in [CGSize(width: 800, height: 1600), CGSize(width: 800, height: 800), CGSize(width: 1600, height: 800)] {
                let withPhoto = render(hero(width: width, title: "认真观察的小猎手", description: description, tags: tags, image: photo(size: size)), width: width)
                precondition(abs(withPhoto.size.height - normal.size.height) < 1, "Photo aspect ratio must not change copy layout")
            }

            var previousLayout: (hero: CGFloat, export: CGFloat)?
            for title in ["慢热观察派", "认真观察的小猎手"] {
                let heroHeight = render(hero(width: width, title: title, description: description, tags: tags, image: nil), width: width).size.height
                let exported = render(LovableResultShareImage(
                    catName: "丸子", avatarImage: UIImage(named: "neko-hero"),
                    personaType: title, personaMbti: "ISFP-A", coreDescription: description,
                    keywords: tags, misunderstanding: misunderstanding,
                    loveLanguage: loveLanguage, ownerRole: ownerRole, width: width
                ), width: width)
                let filename = "persona-\(Int(width))-\(title.count).png"
                try! exported.pngData()!.write(to: directory.appendingPathComponent(filename))
                precondition(exported.size.height > normal.size.height + 400, "Export must include all three insight cards")
                if let previousLayout {
                    let heroGrowth = heroHeight - previousLayout.hero
                    let exportGrowth = exported.size.height - previousLayout.export
                    precondition(abs(heroGrowth - exportGrowth) < 1, "Export must grow with the hero instead of clipping it to a fixed height")
                }
                previousLayout = (heroHeight, exported.size.height)
                results.append("PASS \(filename): \(exported.size)")
            }
            // Exercise four long tags (one per row at the narrowest width).
            let longTags = Array(repeating: "每一次都认真观察", count: 4).enumerated().map { "\($0.offset)\($0.element)" }
            let expanded = render(hero(width: width, title: "认真观察的小猎手", description: description, tags: longTags, image: nil), width: width)
            precondition(expanded.size.height >= normal.size.height, "Additional tag rows must remain in the hero")
            results.append("PASS \(Int(width))pt: copy growth, photo ratios, multi-row tags")
        }
        let report = results.joined(separator: "\n") + "\nPASS: all persona layout checks\n"
        let runID = ProcessInfo.processInfo.environment["NEKO_LAYOUT_RUN"] ?? "manual"
        try! report.write(to: directory.appendingPathComponent("layout-checks-\(runID).txt"), atomically: true, encoding: .utf8)
        print(report)
    }
}
