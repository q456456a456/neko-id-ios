import SwiftUI
import UIKit

// Runs the shipping bubble, photo stage, shared preview/detail card and export
// renderer in a separate simulator bundle. No network or user accounts involved.
@main
struct HeartVoiceBubbleLayoutTestApp: App {
    var body: some Scene {
        WindowGroup {
            BubbleLayoutChecks.page(width: 393, text: BubbleLayoutChecks.regressionText)
                .preferredColorScheme(.light)
                .task { await BubbleLayoutChecks.run() }
        }
    }
}

@MainActor
private enum BubbleLayoutChecks {
    static let regressionText = "柜台这块地视野真不错，那边货架上又有什么动静？"
    static let longText = "我先趴在柜台上看看左边，那边有什么动静可别漏了。你可以陪我一起安静地等一会儿，等我观察清楚，再决定要不要过去看看。"
    static let photo = UIImage(named: "neko-noble")!
    static let leftSubject = HeartVoiceSubject(
        catBoundingBox: CGRect(x: 0.04, y: 0.32, width: 0.56, height: 0.64),
        catFaceBoundingBox: CGRect(x: 0.08, y: 0.40, width: 0.32, height: 0.24)
    )

    static func voice(_ text: String) -> CatVoiceResult {
        CatVoiceResult(time: "刚刚", grad: "", text: text, analysis: CatVoiceAnalysis(
            observation: "它收拢身体伏在玻璃柜台上，头和视线朝向左侧。",
            personalityInterpretation: "画面支持它正在张望，先安静观察周围的动静。"
        ))
    }

    static func page(width: CGFloat, text: String) -> some View {
        HeartVoiceResultView(isBusy: false, onBack: {}, onSave: {}, onShare: {}) {
            VoiceResultCard(catName: "丸子", photoPreviewImage: photo, voice: voice(text), isLoading: false)
        }
    }

    static func render<V: View>(_ content: V, width: CGFloat) -> UIImage {
        let renderer = ImageRenderer(content: content.preferredColorScheme(.light))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.scale = 2
        guard let image = renderer.uiImage else { preconditionFailure("Rendering failed") }
        precondition(abs(image.size.width - width) < 1, "Content escaped viewport")
        return image
    }

    static func save(_ image: UIImage, _ name: String, in directory: URL) {
        try! image.pngData()!.write(to: directory.appendingPathComponent(name + ".png"))
    }

    static func pageSnapshots(width: CGFloat, height: CGFloat, directory: URL) async {
        let view = page(width: width, text: longText)
            .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 44) }
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 34) }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        let controller = UIHostingController(rootView: view.preferredColorScheme(.light))
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
        func snapshot() -> UIImage {
            UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
        }
        save(snapshot(), "detail-\(Int(width))-top", in: directory)
        guard let scroll = findScroll(controller.view) else { preconditionFailure("Missing scroll view") }
        let bottom = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        precondition(bottom > 0, "Long detail must remain scrollable")
        scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
        try? await Task.sleep(for: .milliseconds(100))
        save(snapshot(), "detail-\(Int(width))-bottom", in: directory)
        window.isHidden = true
    }

    // Independent 1pt width/corner sweep: if any face-safe option can show the
    // full voice, the production engine must not choose a truncated bubble.
    static func readabilityChecks(directory: URL, baseline: Bool) -> String {
        let texts = [regressionText, "笔就在这里，怎么看都觉得该拨动一下，但现在我想先按住它。",
                     "这边看看，那边看看，等你过来我再决定要不要一起玩。", longText,
                     "Look over there! Something is moving behind the counter.",
                     "先看看 👀\n别着急，我还没准备好。\n过来陪我坐一会儿吧。"]
        let subjects: [HeartVoiceSubject?] = [nil,
            HeartVoiceSubject(catBoundingBox: CGRect(x: 0.03, y: 0.03, width: 0.94, height: 0.94),
                              catFaceBoundingBox: CGRect(x: 0.08, y: 0.38, width: 0.36, height: 0.30)),
            HeartVoiceSubject(catBoundingBox: CGRect(x: 0.03, y: 0.03, width: 0.94, height: 0.94),
                              catFaceBoundingBox: CGRect(x: 0.56, y: 0.38, width: 0.36, height: 0.30)),
            HeartVoiceSubject(catBoundingBox: CGRect(x: 0.10, y: 0.02, width: 0.80, height: 0.96),
                              catFaceBoundingBox: CGRect(x: 0.20, y: 0.05, width: 0.60, height: 0.35)),
            HeartVoiceSubject(catBoundingBox: CGRect(x: 0.03, y: 0.02, width: 0.48, height: 0.94),
                              catFaceBoundingBox: CGRect(x: 0.12, y: 0.05, width: 0.26, height: 0.30)),
            HeartVoiceSubject(catBoundingBox: CGRect(x: 0.49, y: 0.02, width: 0.48, height: 0.94),
                              catFaceBoundingBox: CGRect(x: 0.62, y: 0.05, width: 0.26, height: 0.30))]
        var failures: [String] = []
        var cases = 0
        for screenWidth: CGFloat in [320, 375, 393, 430] {
            let width = screenWidth - 2 * HeartVoiceLayout.pageMargin
            let stage = CGSize(width: width, height: width * 4 / 3)
            for (subjectIndex, subject) in subjects.enumerated() {
                for (textIndex, text) in texts.enumerated() {
                    let chosen = SubjectLayoutEngine.layout(image: nil, stageSize: stage, subject: subject, catName: "丸子", text: text)
                    let protectedFace = subject?.catFaceBoundingBox.map { face in
                        CGRect(x: chosen.imageFrame.minX + face.minX * chosen.imageFrame.width,
                               y: chosen.imageFrame.minY + face.minY * chosen.imageFrame.height,
                               width: face.width * chosen.imageFrame.width, height: face.height * chosen.imageFrame.height)
                            .insetBy(dx: -HeartVoiceLayout.subjectClearance, dy: -HeartVoiceLayout.subjectClearance)
                    }
                    func isSafe(_ frame: CGRect) -> Bool {
                        guard let protectedFace else { return true }
                        let overlap = frame.intersection(protectedFace)
                        return overlap.isNull || overlap.width * overlap.height == 0
                    }
                    let minimum = max(120, width * HeartVoiceLayout.bubbleMinimumWidthRatio)
                    let maximum = width * HeartVoiceLayout.bubbleMaximumWidthRatio
                    let widths = [minimum, maximum] + stride(from: ceil(minimum), through: floor(maximum), by: 1).map { $0 }
                    var fullFitWidths: [CGFloat] = []
                    var safeWidths: [CGFloat] = []
                    var hasSafeOption = false
                    for bubbleWidth in widths {
                        let size = HeartVoiceBubbleMetrics.size(catName: "丸子", text: text, width: bubbleWidth)
                        for x in [HeartVoiceLayout.bubbleInset, width - HeartVoiceLayout.bubbleInset - bubbleWidth] {
                            let frame = CGRect(origin: CGPoint(x: x, y: HeartVoiceLayout.bubbleInset), size: size)
                            guard isSafe(frame) else { continue }
                            hasSafeOption = true
                            safeWidths.append(bubbleWidth)
                            if HeartVoiceBubbleMetrics.fitsInLines(text: text, width: bubbleWidth) {
                                fullFitWidths.append(bubbleWidth)
                            }
                        }
                    }
                    let label = "\(Int(screenWidth))/subject-\(subjectIndex)/text-\(textIndex)"
                    if hasSafeOption && !isSafe(chosen.bubbleFrame) {
                        failures.append("\(label): covered face despite a safe option")
                    }
                    if let smallest = fullFitWidths.min() {
                        if !HeartVoiceBubbleMetrics.fitsInLines(text: text, width: chosen.bubbleFrame.width) {
                            failures.append("\(label): truncated at \(chosen.bubbleFrame.width), safe full fit at \(smallest)")
                        } else if chosen.bubbleFrame.width > smallest + 1 {
                            failures.append("\(label): unnecessarily wide \(chosen.bubbleFrame.width), safe full fit at \(smallest)")
                        }
                    } else if let widest = safeWidths.max(), chosen.bubbleFrame.width < widest - 1 {
                        failures.append("\(label): fallback discards readable space at \(chosen.bubbleFrame.width), safe width \(widest)")
                    }
                    if subjectIndex == 4 && textIndex == 1 {
                        save(render(PhotoStageView(image: nil, catName: "丸子", voiceText: text, subject: subject, detectionFinished: true), width: width),
                             "readability-\(Int(screenWidth))", in: directory)
                    }
                    cases += 1
                }
            }
        }
        let report = "Readability priority: \(cases) cases, \(failures.count) failures\n" + failures.joined(separator: "\n")
        try! report.write(to: directory.appendingPathComponent("readability-priority.txt"), atomically: true, encoding: .utf8)
        if !baseline { precondition(failures.isEmpty, report) }
        return report
    }

    static func run() async {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let run = ProcessInfo.processInfo.environment["NEKO_LAYOUT_RUN"] ?? "latest"
        let baseline = ProcessInfo.processInfo.environment["NEKO_BUBBLE_BASELINE"] == "1"
        let priorityReport = readabilityChecks(directory: directory, baseline: baseline)
        var checks = 0
        let messages = ["再陪我一会儿。", regressionText, longText,
                        "先看看 👀\n别着急，我还没准备好。\n过来陪我坐一会儿吧。",
                        "Look over there! Something is moving behind the counter, and I want to see it first.",
                        String(repeating: "我想再观察一会儿，然后慢慢过去看看。", count: 20)]
        let subjects: [HeartVoiceSubject?] = [nil, leftSubject,
            HeartVoiceSubject(catBoundingBox: CGRect(x: 0.40, y: 0.30, width: 0.56, height: 0.65),
                              catFaceBoundingBox: CGRect(x: 0.62, y: 0.35, width: 0.30, height: 0.25)),
            HeartVoiceSubject(catBoundingBox: CGRect(x: 0.05, y: 0.08, width: 0.9, height: 0.9),
                              catFaceBoundingBox: CGRect(x: 0.20, y: 0.08, width: 0.5, height: 0.4))]
        for (width, height): (CGFloat, CGFloat) in [(320, 568), (375, 667), (393, 852), (430, 932)] {
            let stageWidth = width - 2 * HeartVoiceLayout.pageMargin
            for (index, text) in messages.enumerated() {
                for subject in subjects {
                    let stage = CGSize(width: stageWidth, height: stageWidth * 4 / 3)
                    let layout = SubjectLayoutEngine.layout(image: photo, stageSize: stage, subject: subject, catName: "丸子", text: text)
                    let bounds = CGRect(origin: .zero, size: stage).insetBy(dx: 16, dy: 16)
                    precondition(bounds.insetBy(dx: -0.5, dy: -0.5).contains(layout.bubbleFrame), "Bubble escaped photo")
                    precondition(layout.bubbleFrame.width <= stageWidth * HeartVoiceLayout.bubbleMaximumWidthRatio + 1,
                                 "Long text must not expand the bubble across the entire photo")
                    precondition(layout.bubbleFrame.width * layout.bubbleFrame.height / (stage.width * stage.height) < 0.25,
                                 "Bubble must leave the photo visible")
                    let bubble = render(SpeechBubbleView(catName: "丸子", text: text, placement: layout.bubblePlacement), width: layout.bubbleFrame.width)
                    precondition(bubble.size.height <= layout.bubbleFrame.height + 1,
                                 "Text was undermeasured: \(width), \(index), rendered=\(bubble.size.height), allotted=\(layout.bubbleFrame.height)")
                    precondition(bubble.size.height < 120, "Bubble exceeded one name line plus three body lines")
                    checks += 1
                }
                let stageImage = render(PhotoStageView(image: photo, catName: "丸子", voiceText: text,
                                                      subject: leftSubject, detectionFinished: true), width: stageWidth)
                precondition(abs(stageImage.size.height - stageWidth * 4 / 3) < 1,
                             "Long text must not stretch the photo or add a full-text section")
                save(stageImage, "stage-\(Int(width))-\(index)", in: directory)
            }
            save(render(VoiceResultCard(catName: "丸子", photoPreviewImage: photo, voice: voice(regressionText), isLoading: false), width: stageWidth),
                 "shared-card-\(Int(width))", in: directory)
            await pageSnapshots(width: width, height: height, directory: directory)
        }
        let short = SubjectLayoutEngine.layout(image: nil, stageSize: CGSize(width: 353, height: 471), subject: nil, catName: "丸子", text: messages[0])
        let long = SubjectLayoutEngine.layout(image: nil, stageSize: CGSize(width: 353, height: 471), subject: nil, catName: "丸子", text: longText)
        precondition(long.bubbleFrame.width > short.bubbleFrame.width && long.bubbleFrame.height > short.bubbleFrame.height, "Bubble must adapt in both dimensions")
        let threeLines = render(SpeechBubbleView(catName: "丸子", text: "先看看\n再等等\n过来吧", placement: .topLeft), width: 200)
        let manyLines = render(SpeechBubbleView(catName: "丸子", text: String(repeating: "先看看\n", count: 50), placement: .topLeft), width: 200)
        precondition(abs(manyLines.size.height - threeLines.size.height) < 1, "Body must truncate after three lines")
        let normalWidth = HeartVoiceBubbleMetrics.naturalWidth(catName: "丸子", text: regressionText)
        precondition(normalWidth > short.bubbleFrame.width, "Regression input must exercise wrapping")
        // When clear space exists, a long bubble must use the opposite corner
        // and not cover the detected face plus its original safety margin.
        for faceX: CGFloat in [0.04, 0.68] {
            let stage = CGSize(width: 353, height: 471)
            let face = CGRect(x: faceX, y: 0.12, width: 0.28, height: 0.28)
            let subject = HeartVoiceSubject(catBoundingBox: face, catFaceBoundingBox: face)
            let layout = SubjectLayoutEngine.layout(image: nil, stageSize: stage, subject: subject, catName: "丸子", text: longText)
            let image = layout.imageFrame
            let protectedFace = CGRect(x: image.minX + face.minX * image.width, y: image.minY + face.minY * image.height,
                                       width: face.width * image.width, height: face.height * image.height)
                .insetBy(dx: -HeartVoiceLayout.subjectClearance, dy: -HeartVoiceLayout.subjectClearance)
            precondition(!layout.bubbleFrame.intersects(protectedFace), "Bubble covered a face despite free space on the other side")
            precondition(layout.bubblePlacement == (faceX < 0.5 ? .topRight : .topLeft))
        }
        for loading in [false, true] {
            let name = "这是一只名字很长的小猫咪"
            let layout = SubjectLayoutEngine.layout(image: nil, stageSize: CGSize(width: 280, height: 374), subject: nil, catName: name, text: longText, showsLoadingIndicator: loading)
            let bubble = render(SpeechBubbleView(catName: name, text: longText, placement: layout.bubblePlacement, showsLoadingIndicator: loading), width: layout.bubbleFrame.width)
            precondition(bubble.size.height <= layout.bubbleFrame.height + 1, "Name/loading must be included in measurement")
            precondition(bubble.size.height < 120, "Long name/loading must not expand the bubble")
            save(bubble, "bubble-loading-\(loading)", in: directory)
        }
        for (index, text) in [regressionText, messages[5]].enumerated() {
            let data = VoiceShareCardData(catName: "丸子", mbti: "ISFP", personalityTitle: "慢热观察派", sceneTags: ["安静观察"],
                                         photo: photo, generatedVoice: text, analysisText: "它在安静观察周围的动静。")
            guard let poster = await VoiceShareImageRenderer.render(data: data) else { preconditionFailure("Export failed") }
            precondition(poster.size == CGSize(width: 360, height: 480), "Long export must truncate, not stretch the photo/poster")
            save(poster, "export-\(index)", in: directory)
        }
        try! "PASS: \(checks) capped-text/bounds/coverage cases; three-line truncation; adaptive width/height; fixed 3:4 photo; face avoidance; loading/name; four screen sizes; fixed-size export.\n\(priorityReport)\n".write(
            to: directory.appendingPathComponent("bubble-checks-\(run).txt"), atomically: true, encoding: .utf8
        )
    }
}
