import SwiftUI
import UIKit
import Vision

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
    static let shopVoice = "爪子先揣起来歇会儿，店里来来往往的动静我都盯紧着呢。"
    static let chairAnalysis = "它趴在椅子底下探出头，抬起一只爪子朝镜头挥动。\n\n即便地方窄小，想伸手主动抓两下的劲头可一点没收敛。"
    // macOS Vision on the user's 900x1200 counter-cat photo. Keep this real
    // geometry in the mandatory suite even when the private photo is absent.
    static let shopHostSubject: HeartVoiceSubject = {
        let body = CGRect(x: 0.12025671993456147, y: 1 - 0.18886100455594487 - 0.5644890962593513,
                          width: 0.7617187147339188, height: 0.5644890962593513)
        return HeartVoiceSubject(catBoundingBox: body, catFaceBoundingBox: CGRect(
            x: body.midX - body.width * 0.72 / 2, y: body.minY, width: body.width * 0.72, height: body.height * 0.46))
    }()
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
        if let chairURL = Bundle.main.url(forResource: "share-user-chair", withExtension: "jpg") {
            chairShareCheck(fixtureURL: chairURL, directory: directory)
        }
        let originalURL = Bundle.main.url(forResource: "share-user-original", withExtension: "jpg")
        let screenshotURL = Bundle.main.url(forResource: "share-user-screenshot", withExtension: "jpg")
        if let fixtureURL = originalURL ?? screenshotURL {
            await screenshotShareCheck(fixtureURL: fixtureURL, isOriginal: originalURL != nil, directory: directory)
            if ProcessInfo.processInfo.environment["NEKO_SHARE_FIXTURE_ONLY"] == "1" {
                try! "Fixture export finished. See user-screenshot-share-check.txt\n".write(
                    to: directory.appendingPathComponent("bubble-checks-\(run).txt"), atomically: true, encoding: .utf8)
                return
            }
        }
        let priorityReport = readabilityChecks(directory: directory, baseline: baseline)
        let sharePriorityReport = shareReadabilityChecks(directory: directory, baseline: baseline)
        let shareReport = shareBubbleChecks(directory: directory)
        shareCanvasChecks(directory: directory)
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
            precondition(poster.size.width == 360 && poster.size.height >= 528, "Share canvas must reserve footer whitespace")
            save(poster, "export-\(index)", in: directory)
        }
        try! "PASS: \(checks) capped-text/bounds/coverage cases; three-line truncation; adaptive width/height; fixed 3:4 photo; face avoidance; loading/name; four screen sizes; content-sized export and watermark.\n\(priorityReport)\n\(shareReport)\n\(sharePriorityReport)\n".write(
            to: directory.appendingPathComponent("bubble-checks-\(run).txt"), atomically: true, encoding: .utf8
        )
    }

    static func screenshotShareCheck(fixtureURL: URL, isOriginal: Bool, directory: URL) async {
        let screenshot = UIImage(contentsOfFile: fixtureURL.path)!
        // User supplied a detail-page screenshot, not the unannotated source.
        // Keep its photo area intact, including its existing bubble; do not
        // fabricate missing pixels. Original-photo tests are separate.
        let image = isOriginal ? screenshot : UIImage(cgImage: screenshot.cgImage!.cropping(to: CGRect(x: 61, y: 578, width: 1084, height: 1446))!)
        save(image, "user-screenshot-photo-region", in: directory)
        let detectedSubject = await HeartVoiceSubjectDetector.detect(in: image)
        // Measured on this original image with macOS Vision, not a synthetic
        // face fixture. See inspect-share-subject.swift. Vision's simulator
        // implementation returns nil; that must not bypass the regression.
        let subject = detectedSubject ?? (isOriginal ? shopHostSubject : nil)
        let stage = CGSize(width: 320, height: 220)
        let layout = VoiceShareBubbleLayout.make(image: image, stageSize: stage, subject: subject, catName: "丸子", text: shopVoice)
        let data = VoiceShareCardData(catName: "丸子", mbti: "ESTP-A", personalityTitle: "坦率直球的玩伴型",
                                     sceneTags: ["揣起小手", "趴柜台", "瞅瞅那边"], photo: image,
                                     generatedVoice: shopVoice,
                                     analysisText: "整只猫揣着小手趴在玻璃柜台上，扭头盯着侧面。\n\n姿势放得很松弛，但周围稍有风吹草动就立刻转头盯上。")
        let poster = VoiceShareImageRenderer.render(data: data, subject: subject)!
        save(poster, "user-screenshot-share-poster", in: directory)
        verifyShareWatermark(poster)
        let ocr = VNRecognizeTextRequest()
        ocr.recognitionLevel = .accurate
        ocr.recognitionLanguages = ["zh-Hans", "en-US"]
        // Header/analysis compaction moves the photo; inspect the real export,
        // not a hardcoded crop from the former header's coordinates.
        try! VNImageRequestHandler(cgImage: poster.cgImage!).perform([ocr])
        let recognized = (ocr.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined()
        try! "Subject: \(String(describing: subject))\n220pt photo geometry probe (export is content-sized): \(layout.stage)\nLines: \(layout.bodyLineLimit)\nPadding: \(layout.contentPadding)\nFits: \(HeartVoiceBubbleMetrics.fitsInLines(text: shopVoice, width: layout.stage.bubbleFrame.width, lines: layout.bodyLineLimit, contentPadding: layout.contentPadding))\nPoster OCR: \(recognized)\n".write(
            to: directory.appendingPathComponent("user-screenshot-share-check.txt"), atomically: true, encoding: .utf8)
        if isOriginal {
            precondition(subject != nil, "The real-photo regression must exercise face avoidance")
            precondition(recognized.contains(shopVoice), "Real-photo export still truncates the voice: \(recognized)")
            precondition(layout.stage.bubbleFrame.width > 120, "Real-photo export fell back to the original narrow bubble")
        }
    }

    static func chairShareCheck(fixtureURL: URL, directory: URL) {
        let image = UIImage(contentsOfFile: fixtureURL.path)!
        // Measured with the same host Vision request on this cached chair-cat
        // image. Keep private user media out of source control.
        let body = CGRect(x: 0.12611608134840982, y: 1 - 0.36677628405784335 - 0.4592927799530717,
                          width: 0.8200892505584979, height: 0.4592927799530717)
        let subject = HeartVoiceSubject(catBoundingBox: body, catFaceBoundingBox: CGRect(
            x: body.midX - body.width * 0.72 / 2, y: body.minY, width: body.width * 0.72, height: body.height * 0.46))
        let data = VoiceShareCardData(catName: "丸子", mbti: "ESTP-A", personalityTitle: "坦率直球的玩伴型",
                                     sceneTags: ["椅底探头", "隔空出爪", "想抓一下"], photo: image,
                                     generatedVoice: "藏在椅子底下也能抓着你，别动，看我的爪子！", analysisText: chairAnalysis)
        let poster = VoiceShareImageRenderer.render(data: data, subject: subject)!
        save(poster, "chair-share-compact", in: directory)
        verifyShareWatermark(poster)
        let ocr = VNRecognizeTextRequest()
        ocr.recognitionLevel = .accurate
        ocr.recognitionLanguages = ["zh-Hans", "en-US"]
        try! VNImageRequestHandler(cgImage: poster.cgImage!).perform([ocr])
        let text = (ocr.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined()
        precondition(text.components(separatedBy: "喵一下").count == 2, "Brand should appear only once, in the footer")
        precondition(text.contains("没收敛"), "The second analysis sentence was lost")
        try! text.write(to: directory.appendingPathComponent("chair-share-ocr.txt"), atomically: true, encoding: .utf8)
    }

    static func verifyShareWatermark(_ poster: UIImage) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        // Inspect the footer separately so a brand elsewhere cannot mask a
        // missing or clipped watermark.
        let image = poster.cgImage!
        let footerHeight = ceil(CGFloat(image.height) * 0.20)
        let footer = image.cropping(to: CGRect(x: 0, y: CGFloat(image.height) - footerHeight,
                                               width: CGFloat(image.width), height: footerHeight))!
        try! VNImageRequestHandler(cgImage: footer).perform([request])
        let watermark = (request.results ?? []).first { observation in
            let text = observation.topCandidates(1).first?.string ?? ""
            return text.contains("喵一下") && text.contains("读懂它的小世界")
        }
        precondition(watermark != nil, "Brand watermark was clipped or missing from the footer")
        let gap = watermark!.boundingBox.minY * CGFloat(footer.height) / poster.scale
        precondition(gap >= 23 && gap <= 32, "Watermark must retain 24pt bottom padding, actual visible gap: \(gap)")
    }

    static func shareCanvasChecks(directory: URL) {
        var spacingReport: [String] = []
        for headerHeight: CGFloat in [45, 80] {
            for insightHeight: CGFloat in [40, 135, 200, 360] {
                let layout = VoiceSharePosterStack.geometry(width: 320, headerHeight: headerHeight,
                                                           insightHeight: insightHeight, watermarkHeight: 18)
                let photo = layout.frames[1]
                let insight = layout.frames[2]
                let watermark = layout.frames[3]
                precondition(abs(watermark.minY - insight.maxY - 16) < 0.01,
                             "Unused canvas space must enlarge the photo, not the footer gap")
                precondition(abs(insight.minY - photo.maxY - 8) < 0.01, "Photo/card gap changed")
                precondition(photo.height >= 220 && layout.size.height >= 490, "Content/extended canvas must stay visible")
                precondition(abs(layout.size.height - watermark.maxY) < 0.01, "Footer must end at the content boundary")
                let expectedPhotoHeight = max(220, 490 - headerHeight - insightHeight - 18 - 16 - 16)
                precondition(abs(photo.height - expectedPhotoHeight) < 0.01, "Photo failed to consume all available height")
                if headerHeight == 45 && insightHeight == 135 {
                    precondition(photo.height == 260, "Compact screenshot regression must enlarge the photo")
                }
                spacingReport.append("header=\(headerHeight), insight=\(insightHeight), photo=\(photo.height), footer gap=\(watermark.minY - insight.maxY), canvas=\(layout.size.height + 38)")
            }
        }
        try! spacingReport.joined(separator: "\n").write(to: directory.appendingPathComponent("share-photo-space.txt"),
                                                       atomically: true, encoding: .utf8)
        for (raw, expected) in [
            ("第一句。\n\n第二句。", "第一句。 第二句。"),
            ("  第一段。\r\n \r\n第二段。  ", "第一段。 第二段。"),
            ("A playful cat.\n\nIt wants to play.", "A playful cat. It wants to play."),
            ("第一句。\u{2028}\u{2029}第二句。", "第一句。 第二句。"),
            ("\n  \r\n", "")
        ] {
            precondition(VoiceShareCard.compactAnalysis(raw) == expected, "Export paragraph formatting regressed")
        }
        let longAnalysis = String(String(repeating: "它把小爪子揣好，眼睛却没闲着。", count: 6).prefix(80))
        for (index, analysis) in ["它安静地趴着，偶尔抬头看看你。", longAnalysis, chairAnalysis].enumerated() {
            let data = VoiceShareCardData(catName: "丸子", mbti: "ESTP-A", personalityTitle: "坦率直球的玩伴型",
                                         sceneTags: ["悄悄观察动静", "揣起两只小手", "偶尔抬头张望"], photo: photo,
                                         generatedVoice: shopVoice, analysisText: analysis)
            let poster = VoiceShareImageRenderer.render(data: data, subject: leftSubject)!
            precondition(poster.size.width == 360 && poster.size.height >= 528, "Extended canvas has the wrong size")
            precondition(poster.cgImage!.width == 1080, "Export width/scale must not change")
            verifyShareWatermark(poster)
            save(poster, "share-footer-\(index)", in: directory)
            if index == 2 {
                let compact = VoiceShareCardData(catName: data.catName, mbti: data.mbti, personalityTitle: data.personalityTitle,
                                                sceneTags: data.sceneTags, photo: data.photo, generatedVoice: data.generatedVoice,
                                                analysisText: analysis.replacingOccurrences(of: "\n\n", with: " "))
                let compactPoster = VoiceShareImageRenderer.render(data: compact, subject: leftSubject)!
                precondition(poster.pngData() == compactPoster.pngData(), "Blank-line input must render exactly like a continuous paragraph")
            }
        }
    }

    // Independent exhaustive width search, including cases where no full fit
    // exists. A valid wider bubble must not be discarded by the old fallback.
    static func shareReadabilityChecks(directory: URL, baseline: Bool) -> String {
        func visibleCount(_ text: String, width: CGFloat, lines: Int, padding: CGFloat) -> Int {
            if HeartVoiceBubbleMetrics.fitsInLines(text: text, width: width, lines: lines, contentPadding: padding) { return text.count }
            // Linear prefix scan in the oracle (production may use binary search).
            return (0..<text.count).last { count in
                HeartVoiceBubbleMetrics.fitsInLines(text: String(text.prefix(count)) + "…", width: width, lines: lines,
                                                   contentPadding: padding)
            } ?? 0
        }
        let texts = [shopVoice, longText, String(repeating: "小爪子先揣好，再看看店里有什么动静。", count: 6)]
        let faces = [CGRect(x: 0.20, y: 0.05, width: 0.60, height: 0.60),
                     CGRect(x: 0.35, y: 0.10, width: 0.60, height: 0.80),
                     CGRect(x: 0.05, y: 0.10, width: 0.60, height: 0.80),
                     CGRect(x: 0.30, y: 0.05, width: 0.40, height: 0.70),
                     CGRect(x: 0, y: 0.44, width: 1, height: 0.10)]
        var failures: [String] = []
        var details: [String] = []
        var cases = 0
        for height: CGFloat in [220, 265] {
            let stage = CGSize(width: 320, height: height)
            let bounds = CGRect(origin: .zero, size: stage).insetBy(dx: 16, dy: 16)
            for (faceIndex, face) in faces.enumerated() {
                let subject = HeartVoiceSubject(catBoundingBox: face, catFaceBoundingBox: face)
                let facePixels = CGRect(x: face.minX * stage.width, y: face.minY * stage.height,
                                        width: face.width * stage.width, height: face.height * stage.height)
                for (textIndex, text) in texts.enumerated() {
                    let chosen = VoiceShareBubbleLayout.make(image: nil, stageSize: stage, subject: subject, catName: "丸子", text: text)
                    let chosenCount = visibleCount(text, width: chosen.stage.bubbleFrame.width, lines: chosen.bodyLineLimit,
                                                   padding: chosen.contentPadding)
                    var bestCount = 0
                    var bestWidth: CGFloat = 0
                    for width in stride(from: ceil(stage.width * 0.36), through: floor(stage.width * 0.72), by: 1) {
                        for lines in 3...5 {
                            let size = HeartVoiceBubbleMetrics.size(catName: "丸子", text: text, width: width, bodyLineLimit: lines)
                            let count = visibleCount(text, width: width, lines: lines, padding: HeartVoiceLayout.bubblePadding)
                            guard count > bestCount else { continue }
                            for y in [bounds.minY, bounds.maxY - size.height] {
                                for x in [bounds.minX, bounds.maxX - width] {
                                    let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
                                    let coverage = CGRect(x: x, y: frame.minY, width: width, height: size.height + 8)
                                    let intersection = coverage.intersection(facePixels)
                                    let overlap = intersection.isNull ? 0 : intersection.width * intersection.height / (facePixels.width * facePixels.height)
                                    if bounds.contains(frame), width * coverage.height <= stage.width * height * 0.40, overlap <= 1.0 / 3.0 {
                                        bestCount = count
                                        bestWidth = width
                                    }
                                }
                            }
                        }
                    }
                    let label = "\(Int(height))/face-\(faceIndex)/text-\(textIndex)"
                    let detail = "\(label): \(chosenCount)/\(text.count) chars, width \(chosen.stage.bubbleFrame.width), \(chosen.bodyLineLimit) lines; oracle \(bestCount) chars at \(bestWidth)pt"
                    details.append(detail)
                    if chosenCount < bestCount { failures.append(detail) }
                    cases += 1
                }
            }
        }
        let report = "Share readability: \(cases) cases, \(failures.count) failures"
        try! (report + "\n" + details.joined(separator: "\n")).write(
            to: directory.appendingPathComponent("share-readability-priority.txt"), atomically: true, encoding: .utf8)
        if !baseline { precondition(failures.isEmpty, report + "\n" + failures.joined(separator: "\n")) }
        return report
    }

    static func shareBubbleChecks(directory: URL) -> String {
        // A regression fixture, not a transcription of the hidden screenshot ending.
        let shareText = "藏在椅子底下也能抓着你，别动，看我伸爪抓住你！"
        let messages = ["再陪我一会儿。", shareText, shopVoice, regressionText, longText,
                        "先看看 👀\n别着急\n等一下\n我来啦", String(repeating: "先看看\n", count: 50)]
        let rightFace = CGRect(x: 0.52, y: 0.20, width: 0.43, height: 0.65)
        let relaxedFace = CGRect(x: 0.35, y: 0.10, width: 0.60, height: 0.80)
        let faces: [CGRect?] = [nil, rightFace,
            CGRect(x: 0.05, y: 0.20, width: 0.43, height: 0.65),
            CGRect(x: 0.20, y: 0.05, width: 0.60, height: 0.60),
            CGRect(x: 0.30, y: 0.72, width: 0.40, height: 0.20),
            CGRect(x: 0.03, y: 0.03, width: 0.94, height: 0.94), relaxedFace,
            CGRect(x: 0.05, y: 0.10, width: 0.60, height: 0.80),
            CGRect(x: 0, y: 0.44, width: 1, height: 0.10),
            CGRect(x: 0.40, y: 0.25, width: 0.20, height: 0.20)]
        var cases = 0
        var recovered = 0
        var partialFaceFits = 0
        for height: CGFloat in [220, 265] {
            let stage = CGSize(width: 320, height: height)
            let bounds = CGRect(origin: .zero, size: stage).insetBy(dx: 16, dy: 16)
            for face in faces {
                let subject = face.map { HeartVoiceSubject(catBoundingBox: $0, catFaceBoundingBox: $0) }
                let visibleFace = face.map {
                    CGRect(x: $0.minX * stage.width, y: $0.minY * stage.height,
                           width: $0.width * stage.width, height: $0.height * stage.height)
                        .intersection(CGRect(origin: .zero, size: stage))
                }
                func overlap(_ frame: CGRect) -> CGFloat {
                    guard let visibleFace else { return 0 }
                    let coverage = CGRect(x: frame.minX, y: frame.minY, width: frame.width,
                                          height: frame.height + HeartVoiceLayout.bubbleTailOverflow)
                    let intersection = coverage.intersection(visibleFace)
                    return intersection.isNull ? 0 : intersection.width * intersection.height / (visibleFace.width * visibleFace.height)
                }
                for text in messages {
                    let old = SubjectLayoutEngine.layout(image: nil, stageSize: stage, subject: subject, catName: "丸子", text: text)
                    let chosen = VoiceShareBubbleLayout.make(image: nil, stageSize: stage, subject: subject, catName: "丸子", text: text)
                    let frame = chosen.stage.bubbleFrame
                    precondition(chosen.stage.imageFrame == old.imageFrame, "Share changed the existing image crop")
                    precondition(bounds.contains(frame), "Share bubble escaped photo")
                    precondition(overlap(frame) <= 1.0 / 3.0, "Share covered more than a third of the visible face (including tail)")
                    precondition((1...5).contains(chosen.bodyLineLimit), "Share removed the line cap")
                    precondition(frame.width * (frame.height + HeartVoiceLayout.bubbleTailOverflow) <= stage.width * stage.height * 0.40,
                                 "Share bubble covered too much photo")
                    let oldFits = HeartVoiceBubbleMetrics.fitsInLines(text: text, width: old.bubbleFrame.width)
                    let fits = HeartVoiceBubbleMetrics.fitsInLines(text: text, width: frame.width, lines: chosen.bodyLineLimit,
                                                                 contentPadding: chosen.contentPadding)
                    if oldFits && overlap(old.bubbleFrame) == 0 {
                        precondition(chosen.bodyLineLimit == 3 && frame == old.bubbleFrame, "Share changed a readable bubble or enlarged a truncated fallback")
                    } else if !oldFits && fits {
                        recovered += 1
                    }
                    if fits && overlap(frame) > 0 { partialFaceFits += 1 }
                    let rendered = render(SpeechBubbleView(catName: "丸子", text: text, placement: chosen.stage.bubblePlacement,
                                                          bodyLineLimit: chosen.bodyLineLimit, contentPadding: chosen.contentPadding), width: frame.width)
                    precondition(rendered.size.height <= frame.height + 1, "Share undermeasured text height")
                    if face == rightFace && text == shareText {
                        precondition(!oldFits && fits, "Share must reveal the regression text within its face budget")
                        save(rendered, "share-regression-bubble-\(Int(height))", in: directory)
                    }
                    if face == relaxedFace && text == shareText {
                        precondition(!oldFits && fits && overlap(frame) > 0 && overlap(frame) <= 1.0 / 3.0,
                                     "Must use the new face budget instead of retaining three-line truncation")
                    }
                    cases += 1
                }
            }
        }
        // Exercise the real poster view with a deterministic, labelled face-zone
        // fixture. This is a layout test diagram, not a user photo or new UI.
        let stage = CGSize(width: 320, height: 220)
        let facePixels = CGRect(x: relaxedFace.minX * stage.width, y: relaxedFace.minY * stage.height,
                                width: relaxedFace.width * stage.width, height: relaxedFace.height * stage.height)
        let fixture = UIGraphicsImageRenderer(size: stage).image { context in
            UIColor.systemGray6.setFill()
            context.fill(CGRect(origin: .zero, size: stage))
            UIColor.systemGray4.setFill()
            context.fill(facePixels)
            ("猫脸区域" as NSString).draw(at: CGPoint(x: facePixels.minX + 20, y: facePixels.midY),
                                      withAttributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor.black])
        }
        let subject = HeartVoiceSubject(catBoundingBox: relaxedFace, catFaceBoundingBox: relaxedFace)
        let old = SubjectLayoutEngine.layout(image: fixture, stageSize: stage, subject: subject, catName: "丸子", text: shareText)
        let chosen = VoiceShareBubbleLayout.make(image: fixture, stageSize: stage, subject: subject, catName: "丸子", text: shareText)
        for (name, layout, lines, padding) in [("before", old, 3, HeartVoiceLayout.bubblePadding),
                                             ("after", chosen.stage, chosen.bodyLineLimit, chosen.contentPadding)] {
            let stageView = ZStack(alignment: .topLeading) {
                Image(uiImage: fixture).resizable().frame(width: stage.width, height: stage.height)
                SpeechBubbleView(catName: "丸子", text: shareText, placement: layout.bubblePlacement, bodyLineLimit: lines,
                                 contentPadding: padding)
                    .frame(width: layout.bubbleFrame.width, height: layout.bubbleFrame.height)
                    .position(x: layout.bubbleFrame.midX, y: layout.bubbleFrame.midY)
            }.frame(width: stage.width, height: stage.height)
            save(render(stageView, width: stage.width), "share-regression-\(name)", in: directory)
        }
        let data = VoiceShareCardData(catName: "丸子", mbti: "ESTP-A", personalityTitle: "坦率直球的玩伴型",
                                     sceneTags: ["椅底探头", "隔空划爪", "想抓一下"], photo: fixture,
                                     generatedVoice: shareText, analysisText: "它趴在椅子底下探出头，抬起一只爪子朝镜头挥动。")
        let posterRenderer = ImageRenderer(content: VoiceShareCard(data: data, subject: subject))
        posterRenderer.proposedSize = ProposedViewSize(width: 360, height: nil)
        posterRenderer.scale = 3
        let poster = posterRenderer.uiImage!
        precondition(poster.cgImage!.width == 1080 && poster.cgImage!.height >= 1584, "Share export lacks added footer space")
        save(poster, "share-regression-poster", in: directory)
        // Verify the actual export, not just idealized stage measurements: the
        // poster's flexible photo height changes the crop and face-safe width.
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        try! VNImageRequestHandler(cgImage: poster.cgImage!).perform([request])
        let visibleText = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined()
        precondition(visibleText.contains("住你"), "Actual share poster still hides the regression voice ending: \(visibleText)")

        // Exact user-supplied wording. The face zone is a controlled fixture,
        // not a claim that we recovered the original photo/detection results.
        let shopLayout = VoiceShareBubbleLayout.make(image: fixture, stageSize: stage, subject: subject, catName: "丸子", text: shopVoice)
        let oldShopLayout = SubjectLayoutEngine.layout(image: fixture, stageSize: stage, subject: subject, catName: "丸子", text: shopVoice)
        precondition(shopLayout.bodyLineLimit == 3 && shopLayout.stage.bubbleFrame.width > oldShopLayout.bubbleFrame.width,
                     "The 26-character shop voice should widen instead of staying in a five-line column")
        let shopData = VoiceShareCardData(catName: "丸子", mbti: "ESTP-A", personalityTitle: "坦率直球的玩伴型",
                                         sceneTags: ["揣起小手", "趴柜台", "瞅瞅那边"], photo: fixture,
                                         generatedVoice: shopVoice, analysisText: "整只猫揣着小手趴在玻璃柜台上，扭头盯着侧面。")
        let shopRenderer = ImageRenderer(content: VoiceShareCard(data: shopData, subject: subject))
        shopRenderer.proposedSize = ProposedViewSize(width: 360, height: nil)
        shopRenderer.scale = 3
        let shopPoster = shopRenderer.uiImage!
        save(shopPoster, "share-shop-voice-poster", in: directory)
        try! VNImageRequestHandler(cgImage: shopPoster.cgImage!).perform([request])
        let shopVisibleText = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined()
        precondition(shopVisibleText.contains("盯紧着呢"), "Export still truncates the user's exact voice: \(shopVisibleText)")
        let began = Date()
        for _ in 0..<10 {
            _ = VoiceShareBubbleLayout.make(image: fixture, stageSize: stage, subject: subject, catName: "丸子", text: shopVoice)
        }
        let averageMilliseconds = Date().timeIntervalSince(began) * 100
        try! "Exact voice: \(shopVoice)\nWidth: \(oldShopLayout.bubbleFrame.width) -> \(shopLayout.stage.bubbleFrame.width)pt; body lines: \(shopLayout.bodyLineLimit)\nOCR: \(shopVisibleText)\nAverage layout time: \(averageMilliseconds)ms (10 runs, simulator)\n".write(
            to: directory.appendingPathComponent("share-shop-voice.txt"), atomically: true, encoding: .utf8)
        precondition(recovered > 0, "Share regression suite must exercise previously truncated text")
        precondition(partialFaceFits > 0, "Share suite must exercise the one-third face allowance")
        // A real crop/face regression, not a square grey photo: the previous
        // suite bypassed the bug because it never exercised this portrait crop.
        let portrait = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200)).image { context in
            UIColor.systemGray6.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
        }
        var portraitReport: [String] = []
        for height: CGFloat in [220, 265] {
            let stage = CGSize(width: 320, height: height)
            let layout = VoiceShareBubbleLayout.make(image: portrait, stageSize: stage, subject: shopHostSubject,
                                                    catName: "丸子", text: shopVoice)
            let frame = layout.stage.bubbleFrame
            let old = SubjectLayoutEngine.layout(image: portrait, stageSize: stage, subject: shopHostSubject,
                                                 catName: "丸子", text: shopVoice)
            precondition(layout.stage.imageFrame == old.imageFrame, "Compact export changed the photo crop")
            let face = shopHostSubject.catFaceBoundingBox!
            let crop = layout.stage.imageFrame
            let faceFrame = CGRect(x: crop.minX + face.minX * crop.width, y: crop.minY + face.minY * crop.height,
                                   width: face.width * crop.width, height: face.height * crop.height)
                .intersection(CGRect(origin: .zero, size: stage))
            let coverage = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height + 8)
            let intersection = faceFrame.intersection(coverage)
            let faceRatio = intersection.isNull ? 0 : intersection.width * intersection.height / (faceFrame.width * faceFrame.height)
            let areaRatio = coverage.width * coverage.height / (stage.width * stage.height)
            precondition(faceRatio <= 1.0 / 3.0 && areaRatio <= 0.40, "Compact export exceeded a coverage budget")
            precondition(HeartVoiceBubbleMetrics.fitsInLines(text: shopVoice, width: frame.width, lines: layout.bodyLineLimit,
                                                            contentPadding: layout.contentPadding), "Real crop still truncates the shop voice")
            let rendered = render(SpeechBubbleView(catName: "丸子", text: shopVoice, placement: layout.stage.bubblePlacement,
                                                  bodyLineLimit: layout.bodyLineLimit, contentPadding: layout.contentPadding), width: frame.width)
            precondition(rendered.size.height <= frame.height + 1, "Compact padding text measurement disagrees with rendering")
            if height == 220 { precondition(layout.contentPadding == 8 && frame.width > 120, "Crowded real crop never used compact padding") }
            portraitReport.append("\(Int(height))pt photo: bubble \(frame), padding \(layout.contentPadding), face overlap \(faceRatio), photo coverage \(areaRatio)")
        }
        try! portraitReport.joined(separator: "\n").write(to: directory.appendingPathComponent("real-portrait-regression.txt"),
                                                        atomically: true, encoding: .utf8)
        return "PASS: \(cases) share layout cases; \(recovered) truncated voices recovered; \(partialFaceFits) full fits within one-third face budget; crop retained; max five lines/40% area; readable fallback; 1080px-wide content-sized poster."
    }
}
