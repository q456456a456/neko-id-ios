import SwiftUI
import UIKit
import Vision

enum HeartVoiceLayout {
    static let pageMargin: CGFloat = 20
    static let stageRadius: CGFloat = 28
    static let stageHeightRatio: CGFloat = 0.70
    static let minimumStageHeight: CGFloat = 500
    static let maximumStageHeight: CGFloat = 680
    static let bubbleWidthRatio: CGFloat = 0.48
    static let fallbackBubbleWidthRatio: CGFloat = 0.42
    static let largeSubjectBubbleWidthRatio: CGFloat = 0.36
    static let bubbleHeight: CGFloat = 92
    static let bubbleInset: CGFloat = 16
    static let subjectClearance: CGFloat = 18
    static let actionHeight: CGFloat = 54
    static let stageTopInset: CGFloat = 8
    static let navigationInset: CGFloat = 12
    static let navigationTopInset: CGFloat = 20
    static let bubblePadding: CGFloat = 12
    static let actionTopInset: CGFloat = 12
    static let actionBottomInset: CGFloat = 8
}

struct HeartVoiceSubject: Equatable {
    let catBoundingBox: CGRect
    let catFaceBoundingBox: CGRect?
}

enum HeartVoiceSubjectDetector {
    static func detect(in image: UIImage) async -> HeartVoiceSubject? {
        guard let cgImage = image.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeAnimalsRequest()
                let handler = VNImageRequestHandler(
                    cgImage: cgImage,
                    orientation: CGImagePropertyOrientation(image.imageOrientation),
                    options: [:]
                )

                do {
                    try handler.perform([request])
                    let cat = request.results?
                        .filter { observation in
                            observation.labels.contains { $0.identifier.lowercased() == "cat" }
                        }
                        .max { $0.confidence < $1.confidence }

                    guard let cat else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let box = topLeadingNormalized(cat.boundingBox)
                    continuation.resume(
                        returning: HeartVoiceSubject(
                            catBoundingBox: box,
                            catFaceBoundingBox: estimatedFaceBox(in: box)
                        )
                    )
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func topLeadingNormalized(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }

    // Vision exposes a reliable animal body observation but no public cat-face request.
    // This conservative upper-body region is used only as an extra avoidance zone.
    private static func estimatedFaceBox(in body: CGRect) -> CGRect? {
        guard body.width > 0.12, body.height > 0.16 else { return nil }
        let width = body.width * 0.72
        let height = body.height * 0.46
        return CGRect(
            x: body.midX - width / 2,
            y: body.minY,
            width: width,
            height: height
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

enum HeartVoiceBubblePlacement: CaseIterable {
    case topLeft
    case topRight
}

struct HeartVoiceStageLayout {
    let imageFrame: CGRect
    let bubbleFrame: CGRect
    let bubblePlacement: HeartVoiceBubblePlacement
}

enum SubjectLayoutEngine {
    static func bubbleWidthRatio(
        for subject: HeartVoiceSubject?,
        detectionFinished: Bool
    ) -> CGFloat {
        guard detectionFinished, let subject else {
            return HeartVoiceLayout.fallbackBubbleWidthRatio
        }
        if usesLargeSubjectBubble(for: subject) {
            return HeartVoiceLayout.largeSubjectBubbleWidthRatio
        }
        if usesCompactBubble(for: subject) {
            return HeartVoiceLayout.fallbackBubbleWidthRatio
        }
        return HeartVoiceLayout.bubbleWidthRatio
    }

    static func layout(
        image: UIImage?,
        stageSize: CGSize,
        subject: HeartVoiceSubject?,
        bubbleSize: CGSize
    ) -> HeartVoiceStageLayout {
        let imageFrame = focalAspectFillFrame(
            imageSize: image?.size ?? stageSize,
            stageSize: stageSize,
            subject: subject
        )
        let catFrame = subject.map { map($0.catBoundingBox, through: imageFrame) }
        let faceFrame = subject?.catFaceBoundingBox.map { map($0, through: imageFrame) }
        let subjectAnchor = faceFrame ?? catFrame
        let candidates = HeartVoiceBubblePlacement.allCases.map {
            ($0, frame(for: $0, stageSize: stageSize, bubbleSize: bubbleSize))
        }
        let placement = bubblePlacement(
            subjectAnchor: subjectAnchor,
            candidates: candidates,
            image: image,
            imageFrame: imageFrame,
            stageSize: stageSize,
            catFrame: catFrame,
            faceFrame: faceFrame
        )
        let winner = frame(for: placement, stageSize: stageSize, bubbleSize: bubbleSize)

        return HeartVoiceStageLayout(
            imageFrame: imageFrame,
            bubbleFrame: winner,
            bubblePlacement: placement
        )
    }

    static func focalAspectFillFrame(
        imageSize: CGSize,
        stageSize: CGSize,
        subject: HeartVoiceSubject?
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: stageSize)
        }
        let scale = max(stageSize.width / imageSize.width, stageSize.height / imageSize.height)
        let rendered = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        guard let subject else {
            return CGRect(
                x: (stageSize.width - rendered.width) / 2,
                y: (stageSize.height - rendered.height) / 2,
                width: rendered.width,
                height: rendered.height
            )
        }

        let focus = subject.catFaceBoundingBox ?? subject.catBoundingBox
        let targetX: CGFloat
        if focus.midX < 0.42 {
            targetX = 0.36
        } else if focus.midX > 0.58 {
            targetX = 0.64
        } else {
            let leftSpace = focus.minX
            let rightSpace = 1 - focus.maxX
            targetX = rightSpace >= leftSpace ? 0.40 : 0.60
        }
        let targetY: CGFloat = focus.midY < 0.42 ? 0.46 : 0.52
        var origin = CGPoint(
            x: stageSize.width * targetX - focus.midX * rendered.width,
            y: stageSize.height * targetY - focus.midY * rendered.height
        )
        origin.x = clampedOrigin(origin.x, renderedLength: rendered.width, stageLength: stageSize.width)
        origin.y = clampedOrigin(origin.y, renderedLength: rendered.height, stageLength: stageSize.height)

        let faceOrSubject = subject.catFaceBoundingBox ?? subject.catBoundingBox
        let safety = HeartVoiceLayout.bubbleInset
        let visibleBounds = CGRect(origin: .zero, size: stageSize).insetBy(dx: safety, dy: safety)
        var frame = CGRect(origin: origin, size: rendered)
        let focusFrame = map(faceOrSubject, through: frame)

        if focusFrame.minX < visibleBounds.minX {
            origin.x += visibleBounds.minX - focusFrame.minX
        } else if focusFrame.maxX > visibleBounds.maxX {
            origin.x -= focusFrame.maxX - visibleBounds.maxX
        }
        if focusFrame.minY < visibleBounds.minY {
            origin.y += visibleBounds.minY - focusFrame.minY
        } else if focusFrame.maxY > visibleBounds.maxY {
            origin.y -= focusFrame.maxY - visibleBounds.maxY
        }

        origin.x = clampedOrigin(origin.x, renderedLength: rendered.width, stageLength: stageSize.width)
        origin.y = clampedOrigin(origin.y, renderedLength: rendered.height, stageLength: stageSize.height)
        frame.origin = origin
        return frame
    }

    static func usesCompactBubble(for subject: HeartVoiceSubject?) -> Bool {
        guard let subject else { return true }
        let faceNeedsTopClearance = subject.catFaceBoundingBox.map {
            $0.width >= 0.36 && $0.minY < 0.36
        } ?? false
        return usesLargeSubjectBubble(for: subject) || faceNeedsTopClearance
    }

    private static func usesLargeSubjectBubble(for subject: HeartVoiceSubject) -> Bool {
        let box = subject.catBoundingBox
        return box.width >= 0.72
            || box.height >= 0.78
            || box.width * box.height >= 0.48
    }

    private static func clampedOrigin(_ value: CGFloat, renderedLength: CGFloat, stageLength: CGFloat) -> CGFloat {
        min(0, max(stageLength - renderedLength, value))
    }

    private static func map(_ normalized: CGRect, through imageFrame: CGRect) -> CGRect {
        CGRect(
            x: imageFrame.minX + normalized.minX * imageFrame.width,
            y: imageFrame.minY + normalized.minY * imageFrame.height,
            width: normalized.width * imageFrame.width,
            height: normalized.height * imageFrame.height
        )
    }

    private static func frame(
        for placement: HeartVoiceBubblePlacement,
        stageSize: CGSize,
        bubbleSize: CGSize
    ) -> CGRect {
        let edge = HeartVoiceLayout.bubbleInset
        switch placement {
        case .topLeft:
            return CGRect(x: edge, y: edge, width: bubbleSize.width, height: bubbleSize.height)
        case .topRight:
            return CGRect(x: stageSize.width - edge - bubbleSize.width, y: edge, width: bubbleSize.width, height: bubbleSize.height)
        }
    }

    private static func bubblePlacement(
        subjectAnchor: CGRect?,
        candidates: [(HeartVoiceBubblePlacement, CGRect)],
        image: UIImage?,
        imageFrame: CGRect,
        stageSize: CGSize,
        catFrame: CGRect?,
        faceFrame: CGRect?
    ) -> HeartVoiceBubblePlacement {
        guard let subjectAnchor else { return .topRight }
        let centerRatio = subjectAnchor.midX / max(stageSize.width, 1)
        if centerRatio < 0.42 { return .topRight }
        if centerRatio > 0.58 { return .topLeft }

        return candidates.max {
            score(
                $0.1,
                stageSize: stageSize,
                catFrame: catFrame,
                faceFrame: faceFrame,
                backgroundScore: backgroundScore(image: image, candidate: $0.1, imageFrame: imageFrame)
            ) < score(
                $1.1,
                stageSize: stageSize,
                catFrame: catFrame,
                faceFrame: faceFrame,
                backgroundScore: backgroundScore(image: image, candidate: $1.1, imageFrame: imageFrame)
            )
        }?.0 ?? .topRight
    }

    private static func score(
        _ frame: CGRect,
        stageSize: CGSize,
        catFrame: CGRect?,
        faceFrame: CGRect?,
        backgroundScore: CGFloat
    ) -> CGFloat {
        var value = backgroundScore
        let safeFace = faceFrame?.insetBy(dx: -HeartVoiceLayout.subjectClearance, dy: -HeartVoiceLayout.subjectClearance)
        if let safeFace { value -= overlapRatio(frame, safeFace) * 1_000 }
        if let catFrame { value -= overlapRatio(frame, catFrame) * 320 }

        let safeBounds = CGRect(origin: .zero, size: stageSize).insetBy(dx: HeartVoiceLayout.bubbleInset, dy: HeartVoiceLayout.bubbleInset)
        if !safeBounds.contains(frame) { value -= 500 }

        return value
    }

    private static func backgroundScore(image: UIImage?, candidate: CGRect, imageFrame: CGRect) -> CGFloat {
        guard let cgImage = image?.cgImage, imageFrame.width > 0, imageFrame.height > 0 else { return 0 }
        let normalizedCenter = CGPoint(
            x: min(1, max(0, (candidate.midX - imageFrame.minX) / imageFrame.width)),
            y: min(1, max(0, (candidate.midY - imageFrame.minY) / imageFrame.height))
        )
        let sampleWidth = max(1, cgImage.width / 24)
        let sampleHeight = max(1, cgImage.height / 24)
        let centerX = Int(normalizedCenter.x * CGFloat(cgImage.width - 1))
        let centerY = Int(normalizedCenter.y * CGFloat(cgImage.height - 1))
        let crop = CGRect(
            x: max(0, centerX - sampleWidth * 2),
            y: max(0, centerY - sampleHeight * 2),
            width: min(sampleWidth * 4, cgImage.width - max(0, centerX - sampleWidth * 2)),
            height: min(sampleHeight * 4, cgImage.height - max(0, centerY - sampleHeight * 2))
        )
        guard let sample = cgImage.cropping(to: crop), let data = sample.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data), sample.bitsPerPixel >= 24 else { return 0 }

        let byteCount = CFDataGetLength(data)
        let stride = max(sample.bitsPerPixel / 8, 3)
        var luminances: [CGFloat] = []
        for index in Swift.stride(from: 0, to: byteCount - stride, by: stride) {
            let red = CGFloat(bytes[index])
            let green = CGFloat(bytes[index + 1])
            let blue = CGFloat(bytes[index + 2])
            luminances.append((red * 0.2126 + green * 0.7152 + blue * 0.0722) / 255)
        }
        guard !luminances.isEmpty else { return 0 }
        let mean = luminances.reduce(0, +) / CGFloat(luminances.count)
        let variance = luminances.reduce(0) { $0 + pow($1 - mean, 2) } / CGFloat(luminances.count)
        return max(0, 48 - variance * 240)
    }

    private static func overlapRatio(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, lhs.width > 0, lhs.height > 0 else { return 0 }
        return intersection.width * intersection.height / (lhs.width * lhs.height)
    }

}

struct HeartVoiceResultView<Content: View>: View {
    let isBusy: Bool
    let onBack: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    private let content: Content

    init(
        isBusy: Bool,
        onBack: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onShare: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isBusy = isBusy
        self.onBack = onBack
        self.onSave = onSave
        self.onShare = onShare
        self.content = content()
    }

    var body: some View {
        ZStack {
            NekoTheme.backgroundGradient.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: HeartVoiceLayout.pageMargin) {
                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .nekoText(.cardTitle)
                                .foregroundStyle(NekoTheme.ink)
                                .frame(width: 44, height: 44)
                                .background(NekoTheme.cardWhite, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("返回")
                        .accessibilityIdentifier("voice.detail.back")
                        Spacer()
                    }

                    Text("这是它想对你说的话")
                        .nekoText(.moduleTitle)
                        .foregroundStyle(NekoTheme.ink)

                    // The preview and saved detail share the exact same square
                    // photo, bounded speech bubble and AI interpretation card.
                    content
                }
                .padding(.horizontal, HeartVoiceLayout.pageMargin)
                .padding(.top, HeartVoiceLayout.navigationTopInset)
                .padding(.bottom, HeartVoiceLayout.pageMargin)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HeartVoiceBottomActionBar(
                isBusy: isBusy,
                onSave: onSave,
                onShare: onShare
            )
        }
    }
}

struct PhotoStageView: View {
    let image: UIImage?
    let catName: String
    let voiceText: String
    let subject: HeartVoiceSubject?
    let detectionFinished: Bool

    var body: some View {
        GeometryReader { proxy in
            let stageSize = proxy.size
            let widthRatio = SubjectLayoutEngine.bubbleWidthRatio(
                for: subject,
                detectionFinished: detectionFinished
            )
            let bubbleSize = CGSize(
                width: stageSize.width * widthRatio,
                height: HeartVoiceLayout.bubbleHeight
            )
            let layout = SubjectLayoutEngine.layout(
                image: image,
                stageSize: stageSize,
                subject: detectionFinished ? subject : nil,
                bubbleSize: bubbleSize
            )

            ZStack(alignment: .topLeading) {
                NekoTheme.photoPlaceholderGradient
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: layout.imageFrame.width, height: layout.imageFrame.height)
                        .position(x: layout.imageFrame.midX, y: layout.imageFrame.midY)
                }

                SpeechBubbleView(
                    catName: catName,
                    text: voiceText,
                    placement: layout.bubblePlacement
                )
                    .frame(width: layout.bubbleFrame.width, height: layout.bubbleFrame.height)
                    .position(x: layout.bubbleFrame.midX, y: layout.bubbleFrame.midY)
            }
            .frame(width: stageSize.width, height: stageSize.height)
            .clipShape(RoundedRectangle(cornerRadius: HeartVoiceLayout.stageRadius, style: .continuous))
        }
    }
}

struct SpeechBubbleView: View {
    let catName: String
    let text: String
    let placement: HeartVoiceBubblePlacement

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(catName)
                .nekoText(.support)
                .foregroundStyle(NekoTheme.muted)
                .lineLimit(1)
            Text(text)
                .nekoText(.voiceBubble)
                .foregroundStyle(NekoTheme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(HeartVoiceLayout.bubblePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.90), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(NekoTheme.softLilac.opacity(0.90), lineWidth: 1)
        }
        .overlay(alignment: placement == .topLeft ? .bottomTrailing : .bottomLeading) {
            HeartVoiceBubbleTail()
                .fill(Color.white.opacity(0.90))
                .frame(width: 18, height: 12)
                .scaleEffect(x: placement == .topLeft ? -1 : 1, y: 1)
                .offset(x: placement == .topLeft ? -24 : 24, y: 8)
        }
    }
}

struct HeartVoiceBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.maxY * 0.72)
        )
        path.closeSubpath()
        return path
    }
}

struct HeartVoiceFocalImageView: View {
    let image: UIImage
    var knownSubject: HeartVoiceSubject? = nil

    @State private var detectedSubject: HeartVoiceSubject?

    var body: some View {
        GeometryReader { proxy in
            let imageFrame = SubjectLayoutEngine.focalAspectFillFrame(
                imageSize: image.size,
                stageSize: proxy.size,
                subject: knownSubject ?? detectedSubject
            )

            Image(uiImage: image)
                .resizable()
                .frame(width: imageFrame.width, height: imageFrame.height)
                .position(x: imageFrame.midX, y: imageFrame.midY)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
        }
        .task {
            guard knownSubject == nil, detectedSubject == nil else { return }
            detectedSubject = await HeartVoiceSubjectDetector.detect(in: image)
        }
    }
}

struct HeartVoiceBottomActionBar: View {
    let isBusy: Bool
    let onSave: () -> Void
    let onShare: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSave) {
                Label(isBusy ? "保存中…" : "保存图片", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
                    .frame(height: HeartVoiceLayout.actionHeight)
            }
            .buttonStyle(HeartVoiceSecondaryButtonStyle())
            .disabled(isBusy)

            Button(action: onShare) {
                Label("分享心声", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
                    .frame(height: HeartVoiceLayout.actionHeight)
            }
            .buttonStyle(HeartVoicePrimaryButtonStyle())
            .disabled(isBusy)
        }
        .padding(.horizontal, HeartVoiceLayout.pageMargin)
        .padding(.top, HeartVoiceLayout.actionTopInset)
        .padding(.bottom, HeartVoiceLayout.actionBottomInset)
        .background(Color.white.opacity(0.92).ignoresSafeArea(edges: .bottom))
    }
}

private struct HeartVoicePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .nekoText(.button)
            .foregroundStyle(.white)
            .background(NekoTheme.primaryGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

private struct HeartVoiceSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .nekoText(.button)
            .foregroundStyle(NekoTheme.ink)
            .background(NekoTheme.cardWhite, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(NekoTheme.softLilac, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}
