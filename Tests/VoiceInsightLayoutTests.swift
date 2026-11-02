import SwiftUI
import UIKit

// Appended to ContentView.swift in a disposable simulator project so the tests
// exercise the shipping private interpretation and publishing views.
@main
struct VoiceInsightLayoutTestApp: App {
    var body: some Scene {
        WindowGroup {
            Color.white.task { await VoiceInsightLayoutChecks.run() }
        }
    }
}

@MainActor
private enum VoiceInsightLayoutChecks {
    static let shortText = "小猫趴在台阶上看你。它似乎想先观察一会儿。"
    static let longText = String(repeating: "小猫趴在台阶上看着你，前爪伸直，安静观察周围的动静。", count: 8)

    static func render<V: View>(_ view: V, width: CGFloat) -> UIImage {
        let renderer = ImageRenderer(content: view.preferredColorScheme(.light))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.scale = 2
        guard let image = renderer.uiImage else { preconditionFailure("Rendering failed") }
        precondition(abs(image.size.width - width) < 1, "Interpretation escaped the viewport")
        return image
    }

    static func save(_ image: UIImage, _ name: String, directory: URL) {
        try! image.pngData()!.write(to: directory.appendingPathComponent(name + ".png"))
    }

    static func preview(width: CGFloat, height: CGFloat, directory: URL) async {
        let voice = CatVoiceResult(time: "刚刚", grad: "", text: "你先站在那里，让我看一会儿。", analysis: CatVoiceAnalysis(
            observation: "小猫趴在台阶上看着你。",
            personalityInterpretation: longText
        ))
        let view = PublishPreviewScreen(
            catName: "丸子", photoPreviewImage: UIImage(named: "neko-noble"), draftVoice: voice,
            isLoading: false, isReanalyzing: false, isPublishing: false,
            onBack: {}, onReanalyze: {}, onPublish: {}
        )
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 44) }
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 34) }
        .preferredColorScheme(.light)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(400))
        controller.view.layoutIfNeeded()
        func findScroll(_ view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            return view.subviews.lazy.compactMap { findScroll($0) }.first
        }
        guard let scroll = findScroll(controller.view) else { preconditionFailure("Missing scroll view") }
        let offset = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        try? await Task.sleep(for: .milliseconds(100))
        let snapshot = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        save(snapshot, "preview-\(Int(width))-bottom", directory: directory)
        window.isHidden = true
    }

    static func run() async {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let run = ProcessInfo.processInfo.environment["NEKO_LAYOUT_RUN"] ?? "latest"
        var results: [String] = []
        for (width, height): (CGFloat, CGFloat) in [(320, 568), (375, 667), (393, 852), (430, 932)] {
            let cardWidth = width - 40
            let short = render(VoiceInsightBlock(analysis: nil, fallbackText: shortText), width: cardWidth)
            let before = render(ReferenceVoiceInsightBlock(analysis: nil, fallbackText: shortText), width: cardWidth)
            precondition(short.pngData() == before.pngData(), "Short interpretations must retain their existing appearance")
            let long = render(VoiceInsightBlock(analysis: nil, fallbackText: longText), width: cardWidth)
            let fiveLines = render(ReferenceVoiceInsightBlock(analysis: nil, fallbackText: "一\n二\n三\n四\n五"), width: cardWidth)
            let uncapped = render(ReferenceVoiceInsightBlock(analysis: nil, fallbackText: longText), width: cardWidth)
            precondition(abs(long.size.height - fiveLines.size.height) < 1, "Body must occupy exactly five lines, excluding the title")
            precondition(uncapped.size.height > long.size.height, "Long text must be capped")
            let structured = render(VoiceInsightBlock(analysis: CatVoiceAnalysis(observation: longText, personalityInterpretation: longText), fallbackText: ""), width: cardWidth)
            precondition(abs(structured.size.height - fiveLines.size.height) < 1, "Both fields share one five-line limit")
            save(short, "insight-\(Int(width))-short", directory: directory)
            save(before, "insight-\(Int(width))-reference", directory: directory)
            save(long, "insight-\(Int(width))-long", directory: directory)
            save(structured, "insight-\(Int(width))-structured", directory: directory)
            await preview(width: width, height: height, directory: directory)
            results.append("PASS \(Int(width))x\(Int(height)): short text pixel-identical; long/structured text capped at five body lines; publishing preview captured")
        }
        try! results.joined(separator: "\n").write(to: directory.appendingPathComponent("insight-checks-\(run).txt"), atomically: true, encoding: .utf8)
    }
}
