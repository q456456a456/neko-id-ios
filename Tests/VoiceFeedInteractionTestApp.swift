import SwiftUI
import UIKit

// Runs the real private feed rows with local media and harmless action handlers.
// No bootstrap, account access, photo save, or server deletion takes place.
@main
struct VoiceFeedInteractionTestApp: App {
    init() {
        let source = UIImage(named: "neko-noble")!
        let tall = UIGraphicsImageRenderer(size: CGSize(width: 180, height: 480)).image { _ in
            source.draw(in: CGRect(x: -150, y: 0, width: 480, height: 480))
        }
        for (index, image) in [source, tall, source].enumerated() {
            NekoRemoteImageCache.shared.store(data: image.jpegData(compressionQuality: 0.95)!,
                                             objectKey: nil, url: VoiceFeedInteractionFixture.url(index))
        }
    }

    var body: some Scene {
        WindowGroup { VoiceFeedInteractionFixture().environmentObject(NekoAppModel()) }
    }
}

private struct VoiceFeedInteractionFixture: View {
    let baseline = ProcessInfo.processInfo.environment["NEKO_FEED_BASELINE"] == "1"
    let profile = CatProfile(id: "fixture", name: "丸子", gender: .male, ageStage: .adult)
    @State private var action: Int?
    @State private var lastEvent = "等待点击"
    @State private var useSmallWidth = false

    static func url(_ index: Int) -> URL { URL(string: "https://feed-fixture.invalid/\(index).jpg")! }

    private func voice(_ index: Int) -> CatVoiceResult {
        CatVoiceResult(time: "刚刚", grad: "", text: "爪子先揣起来歇会儿，店里来来往往的动静我都盯紧着呢。",
                       tags: ["揣起小手", "卧柜台", "瞅瞅那边"],
                       createdAt: Int64(Date().addingTimeInterval(-Double(index + 1) * 3600).timeIntervalSince1970 * 1000),
                       mediaURL: Self.url(index))
    }

    private func record(_ event: String) {
        lastEvent = event
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = directory.appendingPathComponent("feed-events.txt")
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try! (existing + "\(baseline ? "before" : "after"): \(event)\n").write(to: url, atomically: true, encoding: .utf8)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = useSmallWidth ? min(320, proxy.size.width) : proxy.size.width
            ZStack(alignment: .bottom) {
                NekoBackground()
                VStack(spacing: 8) {
                    HStack {
                        Text("\(baseline ? "BEFORE" : "AFTER") · \(lastEvent)").nekoText(.caption)
                        Button(useSmallWidth ? "普通屏" : "小屏") { useSmallWidth.toggle() }
                    }
                    ScrollView {
                        VStack(spacing: 18) {
                            ForEach(0..<3) { index in
                                VStack(spacing: 10) {
                                    DayDivider(label: "心声 \(index + 1)").padding(.horizontal, 20)
                                    if baseline {
                                        ReferenceFeedTimelineRow(availableWidth: width, voice: voice(index), profile: profile,
                                                                 onSelect: { record("详情 \(index + 1)") },
                                                                 onMore: { record("更多 \(index + 1)"); action = index })
                                    } else {
                                        TimelineVoiceRow(availableWidth: width, voice: voice(index), profile: profile,
                                                         onSelect: { record("详情 \(index + 1)") },
                                                         onMore: { record("更多 \(index + 1)"); action = index })
                                    }
                                }
                            }
                        }.padding(.bottom, 156)
                    }
                }
                HomeTabBar(active: .home, onHome: { record("首页") }, onPublish: {}, onAccount: {}).zIndex(110)
                if let action {
                    VoiceActionSheet(title: "猫咪心声 \(action + 1)", saveText: "保存图片", showDelete: true,
                                     onClose: { record("关闭 \(action + 1)"); self.action = nil },
                                     onSave: { record("保存 \(action + 1)"); self.action = nil },
                                     onDelete: { record("删除入口 \(action + 1)"); self.action = nil }).zIndex(130)
                }
            }
            .frame(width: width)
        }
        .preferredColorScheme(.light)
    }
}
