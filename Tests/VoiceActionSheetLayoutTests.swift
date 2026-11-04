import SwiftUI
import UIKit

// Appended to a disposable ContentView.swift copy to test the actual private
// action sheet. No app bootstrap, live account, photo save, or deletion occurs.
@main
struct VoiceActionSheetLayoutTestApp: App {
    var body: some Scene {
        WindowGroup {
            Color.white.task { await VoiceActionSheetChecks.run() }
        }
    }
}

@MainActor
private enum VoiceActionSheetChecks {
    static func pixel(_ image: UIImage, x: CGFloat, y: CGFloat) -> [UInt8] {
        let source = image.cgImage!
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: -x * image.scale, y: -(image.size.height - y - 1) * image.scale)
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        return bytes
    }

    static func snapshot(width: CGFloat, height: CGFloat, safeBottom: CGFloat,
                         before: Bool, showDelete: Bool, home: Bool, directory: URL) async -> UIImage {
        let root = ZStack(alignment: .bottom) {
            if home {
                NekoBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        MainTabPageTitle(title: "首页")
                        DayDivider(label: "今天")
                        Image("neko-noble").resizable().scaledToFill()
                            .frame(width: width - 76, height: (width - 76) * 4 / 3)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }.padding(.horizontal, 20)
                }
                HomeTabBar(active: .home, onHome: {}, onPublish: {}, onAccount: {}).zIndex(110)
            } else {
                Color.red.ignoresSafeArea()
            }
            Group {
                if before {
                    ReferenceVoiceActionSheet(title: "猫咪心声", saveText: "保存图片", showDelete: showDelete,
                                              onClose: {}, onSave: {}, onDelete: {})
                } else {
                    VoiceActionSheet(title: "猫咪心声", saveText: "保存图片", showDelete: showDelete,
                                     onClose: {}, onSave: {}, onDelete: {})
                }
            }.zIndex(130)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: safeBottom) }
        .preferredColorScheme(.light)
        let controller = UIHostingController(rootView: root)
        controller.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(200))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        let name = "voice-actions-\(Int(width))x\(Int(height))-\(showDelete ? "two" : "one")-\(home ? "home" : "solid")-\(before ? "before" : "after").png"
        try! image.pngData()!.write(to: directory.appendingPathComponent(name))
        return image
    }

    static func panelTop(_ image: UIImage) -> Int {
        (0..<Int(image.size.height)).first { y in
            pixel(image, x: image.size.width / 2, y: CGFloat(y)).prefix(3).allSatisfy { $0 > 235 }
        }!
    }

    static func run() async {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let run = ProcessInfo.processInfo.environment["NEKO_LAYOUT_RUN"] ?? "latest"
        var results: [String] = []
        for (width, height, inset): (CGFloat, CGFloat, CGFloat) in [
            (320, 568, 0), (375, 667, 0), (393, 852, 34), (402, 874, 34), (430, 932, 34), (844, 390, 21)
        ] {
            for showDelete in [true, false] {
                let before = await snapshot(width: width, height: height, safeBottom: inset,
                                            before: true, showDelete: showDelete, home: false, directory: directory)
                let after = await snapshot(width: width, height: height, safeBottom: inset,
                                           before: false, showDelete: showDelete, home: false, directory: directory)
                for x in [CGFloat(4), width / 2, width - 4] {
                    for y in stride(from: height - max(inset, 4) + 1, through: height - 2, by: 2) {
                        precondition(pixel(after, x: x, y: y).prefix(3).allSatisfy { $0 > 250 },
                                     "The sheet must fill the entire bottom safe area")
                    }
                }
                if inset > 0 {
                    precondition(!pixel(before, x: width / 2, y: height - 4).prefix(3).allSatisfy { $0 > 235 },
                                 "Baseline must reproduce the uncovered bottom strip")
                }
                precondition(abs(panelTop(before) - panelTop(after)) <= 1, "Controls/panel position must not move")
                precondition(height - CGFloat(panelTop(after)) - inset < 180, "Keep the existing compact content height")
                precondition(CGFloat(panelTop(after)) > 44, "Sheet must fit without top clipping")
                results.append("PASS \(Int(width))x\(Int(height)), inset \(Int(inset)), delete=\(showDelete): bottom filled, panel/controls stay in place")
            }
        }
        for before in [true, false] {
            _ = await snapshot(width: 402, height: 874, safeBottom: 34,
                               before: before, showDelete: true, home: true, directory: directory)
        }
        try! results.joined(separator: "\n").write(to: directory.appendingPathComponent("voice-action-checks-\(run).txt"),
                                                 atomically: true, encoding: .utf8)
    }
}
