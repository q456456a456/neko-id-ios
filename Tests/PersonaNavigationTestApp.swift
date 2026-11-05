import SwiftUI
import UIKit

// Exercises the shipping result page in an isolated simulator app. No network,
// account bootstrap, or production navigation state is used.
@main
struct PersonaNavigationTestApp: App {
    var body: some Scene {
        WindowGroup {
            Color.white.task { await PersonaNavigationChecks.run() }
        }
    }
}

@MainActor
private enum PersonaNavigationChecks {
    static let persona = CatPersonaResult(
        type: "沉稳温柔的观察派", mbti: "ISFP-A", matchScore: 90,
        monologue: "对周围动静充满好奇与观察，但在你身边却格外沉稳顺从，喜欢把脸贴进你手心里全然放松。",
        analysis: "它先观察，再慢慢靠近。", corePersonality: "它先观察，再慢慢靠近。",
        misunderstanding: "它安静地坐着并不是冷淡，而是在留意你的一举一动，等你伸手再慢慢靠近。",
        loveLanguageInsight: "它习惯把脸轻轻贴进你的掌心，用安静的陪伴表达喜欢，也愿意跟着你到处走走。",
        ownerRole: "你是它可以安心休息的依靠，身边有熟悉的声音和气味，它就能放下戒备。",
        tags: ["安静观察", "慢慢靠近", "喜欢陪伴"], traits: [], observations: [], dailyMood: ""
    )

    static func scrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.alwaysBounceVertical { return scroll }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }

    // Match the opaque chevron color, not the translucent white background:
    // scrolling changes the photo under the button but must not move its glyph.
    static func arrowBounds(in image: UIImage, region: CGRect) -> CGRect? {
        let source = image.cgImage!
        let width = source.width, height = source.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { storage in
            let context = CGContext(data: storage.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let bounds = region.applying(CGAffineTransform(scaleX: image.scale, y: image.scale)).integral
        var minX = width, minY = height, maxX = -1, maxY = -1, matches = 0
        for y in max(0, Int(bounds.minY))..<min(height, Int(bounds.maxY)) {
            for x in max(0, Int(bounds.minX))..<min(width, Int(bounds.maxX)) {
                let i = (y * width + x) * 4
                if abs(Int(bytes[i]) - 133) <= 4 && abs(Int(bytes[i + 1]) - 80) <= 4
                    && abs(Int(bytes[i + 2]) - 158) <= 4 {
                    minX = min(minX, x); minY = min(minY, y)
                    maxX = max(maxX, x); maxY = max(maxY, y); matches += 1
                }
            }
        }
        guard matches > 10 else { return nil }
        return CGRect(x: CGFloat(minX) / image.scale, y: CGFloat(minY) / image.scale,
                      width: CGFloat(maxX - minX + 1) / image.scale,
                      height: CGFloat(maxY - minY + 1) / image.scale)
    }

    static func snapshots(width: CGFloat, height: CGFloat, extraTop: CGFloat = 0,
                          showBack: Bool = true, directory: URL, baseline: Bool) async -> [String] {
        let page = LovablePersonaResultPage(
            catName: "老吴", avatarImage: UIImage(named: "neko-hero"), avatarURL: nil,
            avatarObjectKey: nil, persona: persona, onBack: showBack ? {} : nil,
            onRestart: {}, onSave: {}
        ).environmentObject(NekoAppModel()).preferredColorScheme(.light)
        let controller = UIHostingController(rootView: page)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        controller.additionalSafeAreaInsets.top = extraTop
        controller.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(250))
        controller.view.layoutIfNeeded()
        guard let scroll = scrollView(in: controller.view) else { preconditionFailure("Missing result scroll view") }
        let top = -scroll.adjustedContentInset.top
        let bottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        precondition(bottom - top > 200, "Fixture must exercise a genuinely scrolling page")
        let safeTop = controller.view.safeAreaInsets.top
        let buttonRegion = CGRect(x: 24, y: safeTop + 8, width: 44, height: 44)
        var initialArrow: CGRect?
        var results: [String] = []
        for (label, offset) in [("top", top), ("middle", (top + bottom) / 2), ("bottom", bottom), ("return", top)] {
            scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
            try? await Task.sleep(for: .milliseconds(120))
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            let filename = "persona-nav-\(Int(width))-safe\(Int(extraTop))-\(showBack ? "back" : "none")-\(label).png"
            try! image.pngData()!.write(to: directory.appendingPathComponent(filename))
            let arrow = arrowBounds(in: image, region: buttonRegion)
            if label == "top" { initialArrow = arrow }
            if !baseline {
                if showBack {
                    precondition(arrow != nil && initialArrow != nil, "Back arrow disappeared at \(filename)")
                    precondition(abs(arrow!.minX - initialArrow!.minX) < 0.5
                                 && abs(arrow!.minY - initialArrow!.minY) < 0.5,
                                 "Back arrow moved with scroll content at \(filename)")
                    precondition(arrow!.minY >= safeTop + 8, "Back arrow entered the top unsafe area")
                } else {
                    precondition(arrow == nil, "A missing back callback must not show a back button")
                }
            }
            results.append("\(baseline ? "BASELINE" : "PASS") \(filename): safeTop=\(safeTop), scrollY=\(offset), arrow=\(String(describing: arrow))")
        }
        window.isHidden = true
        return results
    }

    static func run() async {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let baseline = ProcessInfo.processInfo.environment["NEKO_NAV_BASELINE"] == "1"
        var results: [String] = []
        for (width, height): (CGFloat, CGFloat) in [(320, 568), (393, 852), (430, 932)] {
            for showBack in [true, false] {
                results += await snapshots(width: width, height: height, showBack: showBack,
                                           directory: directory, baseline: baseline)
            }
        }
        results += await snapshots(width: 393, height: 852, extraTop: 24, directory: directory, baseline: baseline)
        let run = ProcessInfo.processInfo.environment["NEKO_LAYOUT_RUN"] ?? "manual"
        try! (results.joined(separator: "\n") + "\n").write(
            to: directory.appendingPathComponent("navigation-checks-\(run).txt"), atomically: true, encoding: .utf8)
    }
}
