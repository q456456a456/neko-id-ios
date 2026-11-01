import SwiftUI
import UIKit

@main
struct OnboardingVideoLayoutTestApp: App {
    var body: some Scene {
        WindowGroup {
            Color.white.task { await OnboardingVideoLayoutChecks.run() }
        }
    }
}

@MainActor
private enum OnboardingVideoLayoutChecks {
    static func clip(index: Int, size: CGSize?) -> OnboardingVideoClip {
        let thumbnail = size.map { size in
            UIGraphicsImageRenderer(size: size).image { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                UIImage(named: "neko-noble")?.draw(in: CGRect(origin: .zero, size: size))
            }.pngData()!
        }
        return OnboardingVideoClip(
            label: "视频 \(index + 1)", durationLabel: "00:15", sizeLabel: "2 MB",
            thumbnailData: thumbnail
        )
    }

    static func save(_ image: UIImage, name: String, directory: URL) {
        try! image.pngData()!.write(to: directory.appendingPathComponent(name + ".png"))
    }

    static func isRed(_ image: UIImage, point: CGPoint) -> Bool {
        guard let source = image.cgImage else { return false }
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.translateBy(x: -point.x * image.scale, y: -point.y * image.scale)
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        return pixel[0] > 240 && pixel[1] < 15 && pixel[2] < 15
    }

    static func checkCard(_ clip: OnboardingVideoClip, width: CGFloat, directory: URL, label: String) -> Bool {
        let padding: CGFloat = 48
        let height = width * 4 / 3
        let content = VideoClipCard(clip: clip, onRemove: {})
            .frame(width: width, height: height)
            .padding(padding)
            .background(Color(red: 1, green: 0, blue: 0))
        let renderer = ImageRenderer(content: content.preferredColorScheme(.light))
        renderer.scale = 2
        let image = renderer.uiImage!
        save(image, name: "card-\(label)-\(Int(width))", directory: directory)
        let probes = [
            CGPoint(x: image.size.width / 2, y: 8),
            CGPoint(x: image.size.width / 2, y: image.size.height - 8),
            CGPoint(x: 8, y: image.size.height / 2),
            CGPoint(x: image.size.width - 8, y: image.size.height / 2),
        ]
        return abs(image.size.width - width - 2 * padding) < 1
            && abs(image.size.height - height - 2 * padding) < 1
            && probes.allSatisfy { isRed(image, point: $0) }
    }

    static func snapshots(clips: [OnboardingVideoClip], width: CGFloat, height: CGFloat, directory: URL) async {
        let view = ZStack {
            NekoOnboardingBackground()
            OnboardingVideoScreen(
                selectedVideoItems: .constant([]), videoClips: clips, isValidating: false,
                onRemove: { _ in }, onNext: {}, onBack: {}
            )
        }
        .preferredColorScheme(.light)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(250))
        controller.view.layoutIfNeeded()

        func screenshot(_ suffix: String) {
            let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            save(image, name: "videos-\(clips.count)-\(Int(width))-\(suffix)", directory: directory)
        }
        func findScroll(_ view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView, scroll.alwaysBounceVertical { return scroll }
            return view.subviews.lazy.compactMap { findScroll($0) }.first
        }
        screenshot("top")
        guard let scroll = findScroll(controller.view) else { preconditionFailure("Missing vertical scroll view") }
        let offset = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        try? await Task.sleep(for: .milliseconds(100))
        screenshot("bottom")
        window.isHidden = true
    }

    static func run() async {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let runID = ProcessInfo.processInfo.environment["NEKO_LAYOUT_RUN"] ?? "latest"
        let isBaseline = ProcessInfo.processInfo.environment["NEKO_VIDEO_BASELINE"] == "1"
        let clips = [
            clip(index: 0, size: CGSize(width: 270, height: 480)),
            clip(index: 1, size: CGSize(width: 480, height: 270)),
            clip(index: 2, size: CGSize(width: 300, height: 300)),
            clip(index: 3, size: nil),
        ]
        var results: [String] = []
        for (width, height): (CGFloat, CGFloat) in [(320, 568), (393, 852), (430, 932)] {
            for (index, clip) in clips.enumerated() {
                for ratio in [CGFloat(1), CGFloat(0.625)] {
                    let passed = checkCard(clip, width: (width - 40) * ratio, directory: directory, label: "\(index)")
                    results.append("\(passed ? "PASS" : "FAIL") card \(index) width \(width) ratio \(ratio): thumbnail stays inside its layout bounds")
                    if !isBaseline { precondition(passed, "Video thumbnail escaped its card bounds") }
                }
            }
            for count in 0...3 {
                await snapshots(clips: Array(clips.prefix(count)), width: width, height: height, directory: directory)
                results.append("CAPTURE \(count) videos at \(Int(width))x\(Int(height)): top and bottom")
            }
        }
        try! (results.joined(separator: "\n") + "\n").write(
            to: directory.appendingPathComponent("video-checks-\(runID).txt"), atomically: true, encoding: .utf8
        )
    }
}
