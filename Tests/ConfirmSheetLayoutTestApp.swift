import SwiftUI
import UIKit

// Standalone local fixture: no app bootstrap, backend calls, or account data.
@main
struct ConfirmSheetLayoutTestApp: App {
    var body: some Scene {
        WindowGroup {
            Color.white.task { await ConfirmSheetLayoutChecks.run() }
        }
    }
}

@MainActor
private enum ConfirmSheetLayoutChecks {
    static let persona = CatPersonaResult(
        type: "慢热观察派", mbti: "ISFP-A", matchScore: 90,
        monologue: "先观察再行动。", analysis: "先观察再行动。", corePersonality: "先观察再行动。",
        misunderstanding: "它躲在椅子底下不出来并不是胆小，而是在蓄势待发，注意力其实全在你身上。",
        loveLanguageInsight: "它很少主动凑上来黏人，但每次全神贯注陪你玩逗猫棒，就是它最大的热情。",
        ownerRole: "你是它安心的靠山，只要有你在场，它就能放心释放好奇心尽情玩耍。",
        tags: ["先观察", "有耐心", "亲人"], traits: [], observations: [], dailyMood: ""
    )

    static func pixel(_ image: UIImage, x: CGFloat, y: CGFloat) -> [UInt8] {
        let source = image.cgImage!
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: -x * image.scale, y: -(image.size.height - y - 1) * image.scale)
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        return bytes
    }

    static func snapshot(width: CGFloat, height: CGFloat, safeBottom: CGFloat, hint: String, label: String, directory: URL, baseline: Bool, showPersona: Bool = false, appearance: ConfirmSheetOverlay.ButtonAppearance = .compactPersonaExit, showsConfirmation: Bool = true, title: String = "结果还未保存，确定离开吗？") async -> String {
        let model = NekoAppModel()
        let usesResultStyles = appearance == .compactPersonaExit
        let isProfileCreation = appearance == .personaResult
        let root = ZStack {
            if showPersona {
                LovablePersonaResultPage(catName: "丸子", avatarImage: UIImage(named: "neko-hero"), avatarURL: nil,
                                        avatarObjectKey: nil, persona: persona, onBack: {}, onRestart: {}, onSave: {})
                    .environmentObject(model)
            } else {
                Color.red.ignoresSafeArea()
            }
            if showsConfirmation {
                ConfirmSheetOverlay(title: title, hint: hint,
                                    confirmText: isProfileCreation ? "去创建档案" : "离开",
                                    cancelText: isProfileCreation ? "取消" : "继续查看",
                                    buttonAppearance: appearance, danger: !isProfileCreation,
                                    onConfirm: {}, onCancel: {})
            }
        }.preferredColorScheme(.light)
        let controller = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        controller.additionalSafeAreaInsets.bottom = safeBottom
        controller.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(200))
        controller.view.layoutIfNeeded()

        if showPersona {
            func findScroll(_ view: UIView) -> UIScrollView? {
                if let scroll = view as? UIScrollView, scroll.alwaysBounceVertical { return scroll }
                return view.subviews.lazy.compactMap { findScroll($0) }.first
            }
            if let scroll = findScroll(controller.view) {
                scroll.setContentOffset(CGPoint(x: 0, y: max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), animated: false)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let name = "sheet-\(label)-\(Int(width))-\(baseline ? "before" : "after").png"
        try! image.pngData()!.write(to: directory.appendingPathComponent(name))
        let actualInset = controller.view.safeAreaInsets.bottom
        window.isHidden = true
        guard !showPersona else { return "CAPTURE \(name): real persona page, confirmation=\(showsConfirmation)" }

        let bottom = pixel(image, x: width / 2, y: height - 4)
        let fillsSafeArea = bottom[0] > 235 && bottom[1] > 235 && bottom[2] > 235
        let redRows = (0..<Int(height)).filter { y in
            let color = pixel(image, x: width / 2, y: CGFloat(y))
            return color[0] > 110 && color[1] < 100 && color[2] < 100
        }
        let panelHeight = height - CGFloat((redRows.last ?? 0) + 1)
        if !baseline {
            precondition(fillsSafeArea, "Sheet background must cover the bottom safe area")
            precondition(panelHeight > actualInset + 100, "Missing sheet content")
            precondition(panelHeight < height - 80, "Sheet must fit a small screen")
            if label == "normal" { precondition(panelHeight - actualInset < 160, "The single-message confirmation must remain compact") }

            // Sample inside the button edges, clear of text and rounded corners.
            let buttonHeight = usesResultStyles ? PersonaResultActionButtonStyle.Size.confirmation.hitHeight
                : (isProfileCreation ? PersonaResultActionButtonStyle.Size.regular.hitHeight : 54)
            let rowWidth = usesResultStyles ? min(width - 48, 264) : width - 48
            let rowLeading = (width - rowWidth) / 2
            let buttonGap: CGFloat = usesResultStyles ? 24 : 12
            let buttonWidth = (rowWidth - buttonGap) / 2
            let buttonY = height - actualInset - 24 - buttonHeight / 2
            let cancelFill = pixel(image, x: rowLeading + 14, y: buttonY)
            let confirmFill = pixel(image, x: width - rowLeading - 14, y: buttonY)
            if usesResultStyles {
                precondition(cancelFill[2] > 180 && cancelFill[2] > cancelFill[0] && cancelFill[1] < 220,
                             "Continue viewing must use the existing purple-pink primary fill")
            } else {
                precondition(cancelFill.prefix(3).allSatisfy { $0 > 235 },
                             "Other sheets must retain their white secondary button")
            }
            if isProfileCreation {
                precondition(confirmFill[0] > 180 && confirmFill[2] > 170 && confirmFill[1] < 220,
                             "Create profile must use the result page's primary gradient")
                precondition(buttonHeight == 52, "Profile creation must use regular result buttons, not compact exit buttons")
            } else {
                precondition(confirmFill.prefix(3).allSatisfy { $0 > 235 }, "Leave must keep its white fill")
            }

            // Sample the white secondary action's text; unrelated danger dialogs stay red.
            let sampledTextCenterX = isProfileCreation ? rowLeading + buttonWidth / 2
                : width / 2 + buttonGap / 2 + buttonWidth / 2
            let textColors = stride(from: buttonY - 10, through: buttonY + 10, by: 2).flatMap { y in
                stride(from: sampledTextCenterX - 18, through: sampledTextCenterX + 18, by: 2).map { x in
                    pixel(image, x: x, y: y)
                }
            }
            let redCount = textColors.filter { $0[0] > 200 && $0[1] < 120 && $0[2] < 120 }.count
            let purpleCount = textColors.filter { $0[2] > $0[0] && $0[0] > $0[1] && $0[0] < 200 }.count
            precondition((usesResultStyles || isProfileCreation) ? (redCount == 0 && purpleCount > 0) : redCount > 0,
                         "Secondary button text must match the selected result/default appearance")
        }
        return "\(baseline ? "BASELINE" : "PASS") \(name): bottomInset=\(actualInset), panelHeight=\(panelHeight), fillsSafeArea=\(fillsSafeArea), appearance=\(appearance)"
    }

    static func run() async {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let run = ProcessInfo.processInfo.environment["NEKO_LAYOUT_RUN"] ?? "latest"
        let baseline = ProcessInfo.processInfo.environment["NEKO_SHEET_BASELINE"] == "1"
        var results: [String] = []
        for (width, height, inset): (CGFloat, CGFloat, CGFloat) in [(320, 568, 0), (393, 852, 34), (430, 932, 34)] {
            results.append(await snapshot(width: width, height: height, safeBottom: inset, hint: "", label: "normal", directory: directory, baseline: baseline))
            results.append(await snapshot(width: width, height: height, safeBottom: inset,
                                          hint: "生成心声前，先创建猫咪档案，让 AI 更了解它。",
                                          label: "profile-required", directory: directory, baseline: baseline,
                                          appearance: .personaResult, title: "先创建猫咪档案"))
        }
        results.append(await snapshot(width: 320, height: 568, safeBottom: 0, hint: "", label: "long-title", directory: directory, baseline: baseline, title: "这次生成的结果还没有保存，确定要离开并放弃当前结果吗？"))
        results.append(await snapshot(width: 320, height: 568, safeBottom: 0, hint: "当前结果还没有保存。离开后需要重新识别，你可以继续查看并保存这次的猫咪档案。", label: "long-hint", directory: directory, baseline: baseline))
        results.append(await snapshot(width: 393, height: 852, safeBottom: 34, hint: "当前结果还没有保存。", label: "default-secondary", directory: directory, baseline: baseline, appearance: .standard))
        results.append(await snapshot(width: 393, height: 852, safeBottom: 34, hint: "", label: "persona", directory: directory, baseline: baseline, showPersona: true))
        results.append(await snapshot(width: 393, height: 852, safeBottom: 34, hint: "", label: "result-reference", directory: directory, baseline: baseline, showPersona: true, showsConfirmation: false))
        try! (results.joined(separator: "\n") + "\n").write(to: directory.appendingPathComponent("sheet-checks-\(run).txt"), atomically: true, encoding: .utf8)
    }
}
