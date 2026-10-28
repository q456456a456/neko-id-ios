import SwiftUI
import UIKit

// Standalone simulator fixture. Tests/run-heart-voice-layout-checks.sh copies this
// over the app entry point in a disposable workspace; it is never in the shipping target.
@main
struct HeartVoiceLayoutTestApp: App {
    private let scenario = HeartVoiceFixture.selectedScenario

    var body: some Scene {
        WindowGroup {
            ZStack {
                NekoTheme.backgroundGradient.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    Text(scenario.title)
                        .nekoText(.moduleTitle)
                        .foregroundStyle(NekoTheme.ink)

                    PhotoStageView(
                        image: scenario.image,
                        catName: "六六",
                        voiceText: "你先别停，我还在等最好时机。",
                        subject: scenario.subject,
                        detectionFinished: true
                    )
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    Text("3:4 · aspectFill · focal crop")
                        .nekoText(.support)
                        .foregroundStyle(NekoTheme.muted)
                }
                .padding(24)
            }
            .preferredColorScheme(.light)
        }
    }
}

private struct HeartVoiceFixture {
    let title: String
    let image: UIImage
    let subject: HeartVoiceSubject

    static var selectedScenario: HeartVoiceFixture {
        let argument = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--heart-voice=") })?
            .replacingOccurrences(of: "--heart-voice=", with: "") ?? "landscape-left"
        return fixture(named: argument)
    }

    static func fixture(named name: String) -> HeartVoiceFixture {
        let base = UIImage(named: "neko-pink")!
        let canvas: CGSize
        let drawRect: CGRect
        let title: String
        switch name {
        case "landscape-right":
            canvas = CGSize(width: 1_600, height: 900)
            drawRect = CGRect(x: 925, y: 0, width: 675, height: 900)
            title = "横图 · 猫偏右"
        case "portrait-left":
            canvas = CGSize(width: 900, height: 1_600)
            drawRect = CGRect(x: 0, y: 350, width: 675, height: 900)
            title = "竖图 · 猫偏左"
        case "portrait-right":
            canvas = CGSize(width: 900, height: 1_600)
            drawRect = CGRect(x: 225, y: 350, width: 675, height: 900)
            title = "竖图 · 猫偏右"
        case "face-top":
            canvas = CGSize(width: 900, height: 1_600)
            drawRect = CGRect(x: -200, y: -220, width: 900, height: 1_200)
            title = "猫脸靠近顶部"
        case "large-subject":
            canvas = CGSize(width: 1_600, height: 900)
            drawRect = CGRect(x: 520, y: -455, width: 1_360, height: 1_813)
            title = "猫主体占画面很大"
        default:
            canvas = CGSize(width: 1_600, height: 900)
            drawRect = CGRect(x: 0, y: 0, width: 675, height: 900)
            title = "横图 · 猫偏左"
        }

        let renderer = UIGraphicsImageRenderer(size: canvas)
        let image = renderer.image { context in
            UIColor(red: 0.96, green: 0.90, blue: 0.91, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            base.draw(in: drawRect)
        }

        let baseCat = CGRect(x: 0.08, y: 0.18, width: 0.72, height: 0.74)
        let baseFace = CGRect(x: 0.27, y: 0.22, width: 0.44, height: 0.36)
        return HeartVoiceFixture(
            title: title,
            image: image,
            subject: HeartVoiceSubject(
                catBoundingBox: mapped(baseCat, drawRect: drawRect, canvas: canvas),
                catFaceBoundingBox: mapped(baseFace, drawRect: drawRect, canvas: canvas)
            )
        )
    }

    private static func mapped(_ box: CGRect, drawRect: CGRect, canvas: CGSize) -> CGRect {
        CGRect(
            x: (drawRect.minX + box.minX * drawRect.width) / canvas.width,
            y: (drawRect.minY + box.minY * drawRect.height) / canvas.height,
            width: box.width * drawRect.width / canvas.width,
            height: box.height * drawRect.height / canvas.height
        )
        .intersection(CGRect(origin: .zero, size: CGSize(width: 1, height: 1)))
    }
}
