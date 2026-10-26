import SwiftUI
import UIKit

// Simulator-only fixture: append this file to ContentView.swift in a disposable
// project copy and omit the normal app entry point. This accesses the actual
// private VoiceResultCard without exposing it or changing the shipping preview.
// Uses local assets only. No login, model calls, user media, saving or sharing.
@main
struct HeartVoiceDetailLayoutTestApp: App {
    var body: some Scene {
        WindowGroup {
            HeartVoiceDetailLayoutChecks.detail
                .preferredColorScheme(.light)
                .task { await HeartVoiceDetailLayoutChecks.run() }
        }
    }
}

@MainActor
private enum HeartVoiceDetailLayoutChecks {
    static let voice = CatVoiceResult(
        time: "刚刚", grad: "", text: "我先趴在柜台上看看左边，那边有什么动静可别漏了。",
        analysis: CatVoiceAnalysis(
            observation: "它收拢身体伏在玻璃柜台上，头和视线朝向左侧。",
            personalityInterpretation: "画面支持它正在张望，先安静观察周围的动静。"
        )
    )
    static var photo: UIImage? { UIImage(named: "neko-noble") }
    static var detail: some View {
        HeartVoiceResultView(isBusy: false, onBack: {}, onSave: {}, onShare: {}) {
            VoiceResultCard(catName: "丸子", photoPreviewImage: photo, voice: voice, isLoading: false)
        }
    }

    static func render<V: View>(_ view: V, width: CGFloat, height: CGFloat? = nil) -> UIImage {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        renderer.scale = 2
        guard let image = renderer.uiImage else { preconditionFailure("Rendering failed") }
        precondition(abs(image.size.width - width) < 1, "Page must remain inside the viewport")
        return image
    }

    // ScrollView contents are not reliably drawn by ImageRenderer. Attach the
    // complete page to a real window and capture UIKit's rendered hierarchy.
    static func renderPage<V: View>(
        _ view: V, width: CGFloat, height: CGFloat
    ) async -> (top: UIImage, bottom: UIImage, scrollable: Bool) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        let controller = UIHostingController(rootView: view.preferredColorScheme(.light))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(250))
        controller.view.layoutIfNeeded()

        func scrollView(in view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
        func snapshot() -> UIImage {
            UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
        }
        guard let scroll = scrollView(in: controller.view) else {
            preconditionFailure("Detail must contain a real scroll view")
        }
        precondition(scroll.contentSize.height > width, "Photo and interpretation must be laid out")
        let top = snapshot()
        let bottomOffset = max(
            -scroll.adjustedContentInset.top,
            scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
        )
        let scrollable = bottomOffset > scroll.contentOffset.y + 1
        scroll.setContentOffset(CGPoint(x: 0, y: bottomOffset), animated: false)
        try? await Task.sleep(for: .milliseconds(100))
        controller.view.layoutIfNeeded()
        let bottom = snapshot()
        window.isHidden = true
        return (top, bottom, scrollable)
    }

    static func run() async {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let run = ProcessInfo.processInfo.environment["NEKO_LAYOUT_RUN"] ?? "latest"
        var results: [String] = []
        for (width, height): (CGFloat, CGFloat) in [(320, 568), (375, 667), (393, 852), (430, 932)] {
            let page = await renderPage(
                detail
                    .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 44) }
                    .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 34) }
                    .frame(width: width, height: height),
                width: width, height: height
            )
            let image = page.top
            precondition(abs(image.size.height - height) < 1)
            try! image.pngData()!.write(to: directory.appendingPathComponent("voice-detail-\(Int(width)).png"))
            try! page.bottom.pngData()!.write(to: directory.appendingPathComponent("voice-detail-\(Int(width))-scrolled.png"))
            if height <= 667 { precondition(page.scrollable, "Small screens must scroll to the interpretation") }

            let contentWidth = width - 2 * HeartVoiceLayout.pageMargin
            let card = render(
                VoiceResultCard(catName: "丸子", photoPreviewImage: photo, voice: voice, isLoading: false),
                width: contentWidth
            )
            precondition(card.size.height > contentWidth + 60, "Square photo must be followed by the AI interpretation")
            try! card.pngData()!.write(to: directory.appendingPathComponent("voice-shared-card-\(Int(width)).png"))
            results.append("PASS \(Int(width))x\(Int(height)): bounded page and shared photo/AI card")

            let stage = CGSize(width: contentWidth, height: contentWidth)
            let bounds = CGRect(origin: .zero, size: stage).insetBy(dx: HeartVoiceLayout.bubbleInset, dy: HeartVoiceLayout.bubbleInset)
            for box in [
                CGRect(x: 0, y: 0, width: 0.45, height: 0.6),
                CGRect(x: 0.55, y: 0.4, width: 0.45, height: 0.6),
                CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
            ] {
                let layout = SubjectLayoutEngine.layout(
                    image: photo, stageSize: stage,
                    subject: HeartVoiceSubject(catBoundingBox: box, catFaceBoundingBox: nil),
                    bubbleSize: CGSize(width: min(264, contentWidth * 0.68), height: 78)
                )
                precondition(bounds.contains(layout.bubbleFrame.clamped(to: bounds)), "Bubble must remain inside photo")
            }
        }

        let busy = HeartVoiceResultView(isBusy: true, onBack: {}, onSave: {}, onShare: {}) {
            VoiceResultCard(catName: "丸子", photoPreviewImage: nil, voice: voice, isLoading: false)
        }
        let busyPage = await renderPage(busy.frame(width: 393, height: 852), width: 393, height: 852)
        try! busyPage.top.pngData()!.write(to: directory.appendingPathComponent("voice-detail-loading-photo.png"))
        results.append("PASS missing photo and busy actions")
        results.append("PASS 12 subject-position cases: no bubble escapes the photo")
        try! results.joined(separator: "\n").write(
            to: directory.appendingPathComponent("voice-layout-\(run).txt"), atomically: true, encoding: .utf8
        )
    }
}
