import SwiftUI
import UIKit

// Appended to a disposable copy of ContentView.swift, so these checks exercise
// the shipping private row/card components without touching accounts or APIs.
@main
struct HomeVoiceTimelineLayoutTestApp: App {
    var body: some Scene {
        WindowGroup {
            Color.white.task { await HomeVoiceTimelineChecks.run() }
        }
    }
}

@MainActor
private enum HomeVoiceTimelineChecks {
    static let profile = CatProfile(id: "timeline-fixture", name: "丸子", gender: .male, ageStage: .adult)
    static let mediaURL = URL(string: "https://timeline-fixture.invalid/cat.jpg")!
    static let model = NekoAppModel()

    static func voice(age: TimeInterval?, legacy: String = "刚刚") -> CatVoiceResult {
        CatVoiceResult(time: legacy, grad: "", text: "爪子先揣起来歇会儿，店里来来往往的动静我都盯紧着呢。",
                       tags: ["揣起小手", "卧柜台", "瞅瞅那边"],
                       createdAt: age.map { Int64(Date().addingTimeInterval(-$0).timeIntervalSince1970 * 1_000) },
                       mediaURL: mediaURL)
    }

    static func render<V: View>(_ view: V, width: CGFloat) -> UIImage {
        let renderer = ImageRenderer(content: view.preferredColorScheme(.light))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.scale = 3
        guard let image = renderer.uiImage else { preconditionFailure("Rendering failed") }
        precondition(abs(image.size.width - width) < 0.5, "Content escaped viewport")
        return image
    }

    static func crop(_ image: UIImage, _ rect: CGRect) -> Data {
        let pixels = CGRect(x: rect.minX * image.scale, y: rect.minY * image.scale,
                            width: rect.width * image.scale, height: rect.height * image.scale)
        return UIImage(cgImage: image.cgImage!.cropping(to: pixels)!, scale: image.scale, orientation: .up).pngData()!
    }

    static func save(_ image: UIImage, _ name: String, directory: URL) {
        try! image.pngData()!.write(to: directory.appendingPathComponent(name + ".png"))
    }

    static func railChecks(directory: URL) -> Int {
        var samples: [(TimeInterval?, String, String)] = [
            (0, "刚刚", "刚刚"), (5 * 60 + 5, "刚刚", "5分钟前"),
            (13 * 60 + 5, "刚刚", "13分钟前"),
            (59 * 60 + 5, "刚刚", "59分钟前"), (3_605, "刚刚", "1小时前"),
            (23 * 3_600 + 5, "刚刚", "23小时前"), (6 * 86_400 + 5, "刚刚", "6天前"),
            (nil, "9:05", "09:05"), (nil, "刚刚", "--:--"),
        ]
        for date in [Calendar.current.date(byAdding: .day, value: -8, to: Date())!,
                     Calendar.current.date(byAdding: .year, value: -1, to: Date())!] {
            let formatter = DateFormatter()
            formatter.dateFormat = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date())
                ? "MM-dd" : "yy-MM-dd"
            samples.append((Date().timeIntervalSince(date), "刚刚", formatter.string(from: date)))
        }
        var referenceRail: Data?
        for (index, sample) in samples.enumerated() {
            let item = voice(age: sample.0, legacy: sample.1)
            let label = item.displayTime(at: Date(), stackedYear: true)
            let presentation = HomeVoiceTimelineRail.presentationLabel(label)
            precondition(presentation == sample.2, "Unexpected presentation: \(presentation)")
            if !label.contains("\n") {
                precondition(presentation == label, "Layout must not drop or rewrite relative-time information")
            }
            let font = UIFont.systemFont(ofSize: NekoTypography.TextStyle.tiny.size)
            let lines = presentation.split(separator: "\n")
            precondition(lines.count == 1, "Timeline timestamps must never wrap")
            for line in lines {
                let width = (String(line) as NSString).size(withAttributes: [.font: font]).width
                precondition(width <= HomeVoiceTimelineLayout.timestampWidth, "Timestamp does not fit: \(presentation), \(width)")
            }
            let height = font.lineHeight * CGFloat(lines.count)
                + NekoTypography.TextStyle.tiny.lineSpacing * CGFloat(lines.count - 1)
            precondition(height <= HomeVoiceTimelineLayout.timestampHeight, "Timestamp will be clipped")
            let image = render(HomeVoiceTimelineRail(voice: item)
                .frame(height: 160).frame(width: 56, alignment: .leading).background(Color.white), width: 56)
            let rail = crop(image, CGRect(x: 0, y: 24, width: 56, height: 136))
            if let referenceRail {
                precondition(rail == referenceRail, "Text changed the marker/line position")
            } else { referenceRail = rail }
            save(image, "rail-\(index)", directory: directory)
        }
        for label in ["11-04", "--:--"] {
            precondition(HomeVoiceTimelineRail.presentationLabel(label) == label, "Dates must remain intact")
        }
        precondition(HomeVoiceTimelineRail.presentationLabel("2025\n12-31") == "25-12-31")
        precondition(HomeVoiceTimelineLayout.railWidth / 2 == 20, "The line must not move right")
        precondition(HomeVoiceTimelineLayout.railWidth + HomeVoiceTimelineLayout.rowSpacing == 56,
                     "Card leading edge must not move")
        return samples.count
    }

    static func snapshot<V: View>(_ view: V, width: CGFloat, height: CGFloat, atBottom: Bool = false) async -> UIImage {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        let controller = UIHostingController(rootView: view.environmentObject(model).preferredColorScheme(.light))
        // Use only the explicit fixture safe areas, not the booted phone's
        // status-bar insets when rendering a smaller virtual viewport.
        controller.safeAreaRegions = []
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(300))
        controller.view.layoutIfNeeded()
        if atBottom {
            func findScroll(_ view: UIView) -> UIScrollView? {
                if let scroll = view as? UIScrollView { return scroll }
                return view.subviews.lazy.compactMap { findScroll($0) }.first
            }
            guard let scroll = findScroll(controller.view) else { preconditionFailure("Missing home scroll view") }
            let bottom = max(-scroll.adjustedContentInset.top,
                             scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            precondition(bottom > 0, "Timeline must scroll on small screens")
            scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
            try? await Task.sleep(for: .milliseconds(100))
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds, format: format).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        return image
    }

    static func page(width: CGFloat, before: Bool) -> some View {
        ZStack(alignment: .bottom) {
            NekoBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    MainTabPageTitle(title: "首页")
                    HStack(spacing: 8) {
                        Text("💭").nekoText(.cardTitle)
                        Text("猫咪心声").nekoText(.button).foregroundStyle(NekoTheme.ink)
                    }
                    .padding(.horizontal, 20).padding(.top, 24)
                    VStack(spacing: 18) {
                        ForEach(Array(["今天", "昨天"].enumerated()), id: \.offset) { index, day in
                            VStack(spacing: 10) {
                                DayDivider(label: day).padding(.horizontal, 20)
                                let item = voice(age: index == 0 ? 59 * 60 : 86_400)
                                if before {
                                    ReferenceTimelineVoiceRow(availableWidth: width, voice: item, profile: profile,
                                                              onSelect: {}, onMore: {})
                                } else {
                                    TimelineVoiceRow(availableWidth: width, voice: item, profile: profile,
                                                     onSelect: {}, onMore: {})
                                }
                            }
                        }
                    }.padding(.top, 12)
                }
                .padding(.bottom, 156)
                .frame(width: width, alignment: .leading)
            }
            HomeTabBar(active: .home, onHome: {}, onPublish: {}, onAccount: {})
        }
    }

    static func run() async {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let run = ProcessInfo.processInfo.environment["NEKO_LAYOUT_RUN"] ?? "latest"
        NekoRemoteImageCache.shared.store(data: UIImage(named: "neko-noble")!.jpegData(compressionQuality: 0.95)!,
                                         objectKey: nil, url: mediaURL)
        let count = railChecks(directory: directory)
        var results = ["PASS: \(count) relative/date/legacy timestamps fit one line at the existing 11pt token; all markers/rails pixel-identical",
                       "PASS: line stays at x=20pt; card stays at x=56pt; cross-year dates use YY-MM-DD"]
        for (width, height): (CGFloat, CGFloat) in [(320, 568), (375, 667), (393, 852), (402, 874), (430, 932)] {
            let item = voice(age: 59 * 60)
            let cardWidth = HomeVoiceTimelineLayout.cardWidth(availableWidth: width)
            precondition(cardWidth == width - 76, "Do not reduce photo/card width")
            let card = render(VoiceFeedCard(voice: item, profile: profile, onSelect: {}, onMore: {})
                .environmentObject(model), width: cardWidth)
            let rowHeight = ceil(card.size.height)
            let before = await snapshot(ReferenceTimelineVoiceRow(availableWidth: width, voice: item, profile: profile,
                                                                   onSelect: {}, onMore: {}).background(Color.white),
                                        width: width, height: rowHeight)
            let after = await snapshot(TimelineVoiceRow(availableWidth: width, voice: item, profile: profile,
                                                        onSelect: {}, onMore: {}).background(Color.white),
                                       width: width, height: rowHeight)
            let cardRect = CGRect(x: 56, y: 0, width: cardWidth, height: rowHeight)
            precondition(crop(before, cardRect) == crop(after, cardRect), "Card/photo changed at width \(width)")
            save(before, "row-\(Int(width))-before", directory: directory)
            save(after, "row-\(Int(width))-after", directory: directory)
            for isBefore in [true, false] {
                let image = await snapshot(page(width: width, before: isBefore)
                    .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 44) }
                    .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 34) },
                    width: width, height: height)
                save(image, "home-\(Int(width))-\(isBefore ? "before" : "after")", directory: directory)
            }
            let bottom = await snapshot(page(width: width, before: false)
                .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 44) }
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 34) },
                width: width, height: height, atBottom: true)
            save(bottom, "home-\(Int(width))-bottom", directory: directory)
            results.append("PASS \(Int(width))pt: card/photo pixels unchanged; before/after home snapshots captured")
        }
        try! results.joined(separator: "\n").write(to: directory.appendingPathComponent("timeline-checks-\(run).txt"),
                                                 atomically: true, encoding: .utf8)
    }
}
