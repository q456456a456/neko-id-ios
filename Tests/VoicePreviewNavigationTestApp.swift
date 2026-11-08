import SwiftUI
import UIKit

// The runner exposes only PublishPreviewScreen in a disposable source copy.
// Exercise the shipping preview without logging in or contacting the backend.
@main
struct VoicePreviewNavigationTestApp: App {
    var body: some Scene {
        WindowGroup {
            Color.white.task { await VoicePreviewNavigationChecks.run() }
        }
    }
}

@MainActor
private enum VoicePreviewNavigationChecks {
    static let voice = CatVoiceResult(
        time: "刚刚", grad: "pink",
        text: "手都给你揣好了，你欠我的那些小鱼干到底打算什么时候结清？",
        sceneTags: ["揣起小手", "安静等待", "看看你"],
        analysis: CatVoiceAnalysis(
            observation: "它把爪子揣在胸前，安安静静地看着你。",
            personalityInterpretation: "看起来没什么动静，其实耳朵一直留意着周围。你要是走近一点，它大概还会抬起头看看，是来摸摸它，还是终于想起开饭了。"
        )
    )

    static func scrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.alwaysBounceVertical { return scroll }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }

    static func crop(_ image: UIImage, _ rect: CGRect) -> Data {
        let pixels = rect.applying(CGAffineTransform(scaleX: image.scale, y: image.scale)).integral
        return UIImage(cgImage: image.cgImage!.cropping(to: pixels)!).pngData()!
    }

    // The bottom bar is intentionally translucent: compare the opaque button
    // label, not its background (which changes with the content underneath).
    static func inkBounds(_ image: UIImage, region: CGRect) -> CGRect? {
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
        let pixels = region.applying(CGAffineTransform(scaleX: image.scale, y: image.scale)).integral
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in max(0, Int(pixels.minY))..<min(height, Int(pixels.maxY)) {
            for x in max(0, Int(pixels.minX))..<min(width, Int(pixels.maxX)) {
                let i = (y * width + x) * 4
                if abs(Int(bytes[i]) - 62) <= 4 && abs(Int(bytes[i + 1]) - 49) <= 4
                    && abs(Int(bytes[i + 2]) - 94) <= 4 {
                    minX = min(minX, x); minY = min(minY, y)
                    maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX else { return nil }
        return CGRect(x: CGFloat(minX) / image.scale, y: CGFloat(minY) / image.scale,
                      width: CGFloat(maxX - minX + 1) / image.scale,
                      height: CGFloat(maxY - minY + 1) / image.scale)
    }

    static func snapshots(width: CGFloat, height: CGFloat, extraTop: CGFloat = 0,
                          loading: Bool = false, directory: URL, baseline: Bool) async -> [String] {
        let page = ZStack {
            NekoBackground()
            PublishPreviewScreen(
                catName: "老吴", photoPreviewImage: UIImage(named: "neko-hero"),
                draftVoice: loading ? nil : voice, isLoading: loading,
                isReanalyzing: false, isPublishing: false,
                onBack: {}, onReanalyze: {}, onPublish: {}
            )
        }.preferredColorScheme(.light)
        let controller = UIHostingController(rootView: page)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        controller.additionalSafeAreaInsets.top = extraTop
        controller.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(350))
        controller.view.layoutIfNeeded()
        guard let scroll = scrollView(in: controller.view) else { preconditionFailure("Missing preview scroll view") }
        let top = -scroll.adjustedContentInset.top
        let bottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        precondition(bottom - top > 20, "Fixture must actually scroll")
        let safeTop = controller.view.safeAreaInsets.top
        let safeBottom = controller.view.safeAreaInsets.bottom
        let viewportTop = scroll.convert(scroll.bounds, to: controller.view).minY
        let headerRegion = CGRect(x: 0, y: safeTop, width: width,
                                  height: baseline ? 96 : viewportTop - safeTop)
        let footerRegion = CGRect(x: 20, y: height - safeBottom - 64,
                                  width: (width - 50) / 2, height: 54)
        var initialHeader: Data?
        var initialFooter: CGRect?
        var results: [String] = []
        for (label, offset) in [("top", top), ("middle", (top + bottom) / 2), ("bottom", bottom), ("return", top)] {
            scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
            try? await Task.sleep(for: .milliseconds(150))
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            let filename = "voice-nav-\(Int(width))-safe\(Int(extraTop))-\(loading ? "loading" : "ready")-\(label).png"
            try! image.pngData()!.write(to: directory.appendingPathComponent(filename))
            let header = crop(image, headerRegion)
            let footer = inkBounds(image, region: footerRegion)
            if label == "top" { initialHeader = header; initialFooter = footer }
            let headerFixed = header == initialHeader
            let footerFixed = footer == initialFooter
            let scrollFrame = scroll.convert(scroll.bounds, to: controller.view)
            if !baseline {
                precondition(headerFixed, "Back button / step label moved or was overlapped at \(filename)")
                precondition(footerFixed && footer != nil, "Bottom action bar moved while scrolling at \(filename)")
                precondition(headerRegion.height >= 88, "Header is compressed or in the unsafe area")
                precondition(scrollFrame.minY >= headerRegion.maxY - 0.5,
                             "Scrollable content overlaps fixed navigation at \(filename)")
            }
            results.append("\(baseline ? "BASELINE" : "PASS") \(filename): safeTop=\(safeTop), scrollY=\(offset), viewportY=\(scrollFrame.minY), headerFixed=\(headerFixed), footerFixed=\(footerFixed)")
        }
        window.isHidden = true
        return results
    }

    static func run() async {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let baseline = ProcessInfo.processInfo.environment["NEKO_NAV_BASELINE"] == "1"
        var results: [String] = []
        for (width, height): (CGFloat, CGFloat) in [(320, 568), (393, 852), (430, 932)] {
            for loading in [false, true] {
                results += await snapshots(width: width, height: height, loading: loading,
                                           directory: directory, baseline: baseline)
            }
        }
        results += await snapshots(width: 393, height: 852, extraTop: 24,
                                   directory: directory, baseline: baseline)
        let run = ProcessInfo.processInfo.environment["NEKO_LAYOUT_RUN"] ?? "manual"
        try! (results.joined(separator: "\n") + "\n").write(
            to: directory.appendingPathComponent("voice-navigation-checks-\(run).txt"),
            atomically: true, encoding: .utf8
        )
    }
}
