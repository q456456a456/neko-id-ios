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
    static let bubbleMinimumWidth: CGFloat = 168
    static let bubbleMaximumWidth: CGFloat = 236
    static let bubbleInset: CGFloat = 20
    static let subjectClearance: CGFloat = 20
    static let actionHeight: CGFloat = 54
    static let stageTopInset: CGFloat = 8
    static let navigationInset: CGFloat = 12
    static let navigationTopInset: CGFloat = 20
    static let bubblePadding: CGFloat = 16
    static let actionTopInset: CGFloat = 12
    static let actionBottomInset: CGFloat = 8
}

struct HeartVoiceSubject: Equatable {
    let catBoundingBox: CGRect
    let catFaceBoundingBox: CGRect?

    static let fallback = HeartVoiceSubject(
        catBoundingBox: CGRect(x: 0.24, y: 0.22, width: 0.52, height: 0.58),
        catFaceBoundingBox: nil
    )
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
    case upperLeftCenter
    case upperRightCenter
}

struct HeartVoiceStageLayout {
    let imageFrame: CGRect
    let bubbleFrame: CGRect
    let decorationFrames: [CGRect]
}

enum SubjectLayoutEngine {
    static func layout(
        image: UIImage?,
        stageSize: CGSize,
        subject: HeartVoiceSubject?,
        bubbleSize: CGSize
    ) -> HeartVoiceStageLayout {
        let imageSize = image?.size ?? stageSize
        let detectedSubject = subject ?? .fallback
        let imageFrame = aspectFillFrame(
            imageSize: imageSize,
            stageSize: stageSize,
            focalPoint: CGPoint(x: detectedSubject.catBoundingBox.midX, y: detectedSubject.catBoundingBox.midY)
        )
        let catFrame = map(detectedSubject.catBoundingBox, through: imageFrame)
        let faceFrame = detectedSubject.catFaceBoundingBox.map { map($0, through: imageFrame) }
        let candidates = HeartVoiceBubblePlacement.allCases.map {
            ($0, frame(for: $0, stageSize: stageSize, bubbleSize: bubbleSize))
        }
        let winner: CGRect
        if subject == nil {
            winner = frame(for: .topRight, stageSize: stageSize, bubbleSize: bubbleSize)
        } else {
            winner = candidates.max {
                score(
                    $0.1,
                    placement: $0.0,
                    stageSize: stageSize,
                    catFrame: catFrame,
                    faceFrame: faceFrame,
                    backgroundScore: backgroundScore(image: image, candidate: $0.1, imageFrame: imageFrame)
                ) < score(
                    $1.1,
                    placement: $1.0,
                    stageSize: stageSize,
                    catFrame: catFrame,
                    faceFrame: faceFrame,
                    backgroundScore: backgroundScore(image: image, candidate: $1.1, imageFrame: imageFrame)
                )
            }?.1 ?? frame(for: .topRight, stageSize: stageSize, bubbleSize: bubbleSize)
        }

        let decorations = decorationFrames(
            stageSize: stageSize,
            excluded: [winner, catFrame] + (faceFrame.map { [$0] } ?? []),
            reduced: subject == nil
        )
        return HeartVoiceStageLayout(imageFrame: imageFrame, bubbleFrame: winner, decorationFrames: decorations)
    }

    private static func aspectFillFrame(imageSize: CGSize, stageSize: CGSize, focalPoint: CGPoint) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: stageSize)
        }
        let scale = max(stageSize.width / imageSize.width, stageSize.height / imageSize.height)
        let rendered = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let desiredX = stageSize.width / 2 - focalPoint.x * rendered.width
        let desiredY = stageSize.height / 2 - focalPoint.y * rendered.height
        let originX = min(0, max(stageSize.width - rendered.width, desiredX))
        let originY = min(0, max(stageSize.height - rendered.height, desiredY))
        return CGRect(origin: CGPoint(x: originX, y: originY), size: rendered)
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
        let centeredY = max(edge, stageSize.height * 0.22)
        switch placement {
        case .topLeft:
            return CGRect(x: edge, y: edge, width: bubbleSize.width, height: bubbleSize.height)
        case .topRight:
            return CGRect(x: stageSize.width - edge - bubbleSize.width, y: edge, width: bubbleSize.width, height: bubbleSize.height)
        case .upperLeftCenter:
            return CGRect(x: edge, y: centeredY, width: bubbleSize.width, height: bubbleSize.height)
        case .upperRightCenter:
            return CGRect(x: stageSize.width - edge - bubbleSize.width, y: centeredY, width: bubbleSize.width, height: bubbleSize.height)
        }
    }

    private static func score(
        _ frame: CGRect,
        placement: HeartVoiceBubblePlacement,
        stageSize: CGSize,
        catFrame: CGRect,
        faceFrame: CGRect?,
        backgroundScore: CGFloat
    ) -> CGFloat {
        var value = backgroundScore
        let safeFace = faceFrame?.insetBy(dx: -HeartVoiceLayout.subjectClearance, dy: -HeartVoiceLayout.subjectClearance)
        if let safeFace { value -= overlapRatio(frame, safeFace) * 1_000 }
        value -= overlapRatio(frame, catFrame) * 320

        let safeBounds = CGRect(origin: .zero, size: stageSize).insetBy(dx: HeartVoiceLayout.bubbleInset, dy: HeartVoiceLayout.bubbleInset)
        if !safeBounds.contains(frame) { value -= 500 }

        let bubbleIsLeft = frame.midX < stageSize.width / 2
        let catIsLeft = catFrame.midX < stageSize.width / 2
        if bubbleIsLeft != catIsLeft { value += 90 }
        if placement == .topLeft || placement == .topRight { value += 12 }
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

    private static func decorationFrames(stageSize: CGSize, excluded: [CGRect], reduced: Bool) -> [CGRect] {
        let size: CGFloat = 28
        let candidates = [
            CGRect(x: 24, y: stageSize.height * 0.42, width: size, height: size),
            CGRect(x: stageSize.width - 52, y: stageSize.height * 0.50, width: size, height: size),
            CGRect(x: stageSize.width - 60, y: stageSize.height - 84, width: size, height: size),
            CGRect(x: 28, y: stageSize.height - 96, width: size, height: size),
        ]
        let limit = reduced ? 2 : 3
        return Array(candidates.filter { candidate in
            !excluded.contains { $0.insetBy(dx: -12, dy: -12).intersects(candidate) }
        }.prefix(limit))
    }
}

struct HeartVoiceResultView: View {
    let image: UIImage?
    let catName: String
    let voiceText: String
    let isBusy: Bool
    let onBack: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void

    @State private var subject: HeartVoiceSubject?
    @State private var detectionFinished = false

    var body: some View {
        GeometryReader { proxy in
            let stageHeight = min(
                HeartVoiceLayout.maximumStageHeight,
                max(HeartVoiceLayout.minimumStageHeight, proxy.size.height * HeartVoiceLayout.stageHeightRatio)
            )

            ZStack(alignment: .topLeading) {
                NekoTheme.backgroundGradient.ignoresSafeArea()

                PhotoStageView(
                    image: image,
                    catName: catName,
                    voiceText: voiceText,
                    subject: subject,
                    detectionFinished: detectionFinished
                )
                .frame(height: stageHeight)
                .padding(.horizontal, HeartVoiceLayout.pageMargin)
                .padding(.top, HeartVoiceLayout.stageTopInset)

                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .nekoText(.cardTitle)
                        .foregroundStyle(NekoTheme.ink)
                        .frame(width: 44, height: 44)
                        .background(NekoTheme.cardWhite, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, HeartVoiceLayout.pageMargin + HeartVoiceLayout.navigationInset)
                .padding(.top, HeartVoiceLayout.navigationTopInset)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HeartVoiceBottomActionBar(
                    isBusy: isBusy,
                    onSave: onSave,
                    onShare: onShare
                )
            }
        }
        .task(id: image) {
            guard let image else {
                subject = nil
                detectionFinished = true
                return
            }
            detectionFinished = false
            subject = await HeartVoiceSubjectDetector.detect(in: image)
            detectionFinished = true
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
            let bubbleWidth = min(
                HeartVoiceLayout.bubbleMaximumWidth,
                max(HeartVoiceLayout.bubbleMinimumWidth, stageSize.width * HeartVoiceLayout.bubbleWidthRatio)
            )
            let bubbleSize = CGSize(width: bubbleWidth, height: 132)
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
                        .offset(x: layout.imageFrame.minX, y: layout.imageFrame.minY)
                }

                DoodleOverlayView(frames: layout.decorationFrames)

                SpeechBubbleView(catName: catName, text: voiceText)
                    .frame(width: layout.bubbleFrame.width, height: layout.bubbleFrame.height)
                    .offset(x: layout.bubbleFrame.minX, y: layout.bubbleFrame.minY)
            }
            .frame(width: stageSize.width, height: stageSize.height)
            .clipShape(RoundedRectangle(cornerRadius: HeartVoiceLayout.stageRadius, style: .continuous))
        }
    }
}

struct SpeechBubbleView: View {
    let catName: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(catName)
                .nekoText(.support)
                .foregroundStyle(NekoTheme.muted)
                .lineLimit(1)
            Text(text)
                .nekoText(.body)
                .foregroundStyle(NekoTheme.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(HeartVoiceLayout.bubblePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.90), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(NekoTheme.softLilac.opacity(0.90), lineWidth: 1)
        }
    }
}

struct DoodleOverlayView: View {
    let frames: [CGRect]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                decoration(for: index)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func decoration(for index: Int) -> some View {
        switch index % 3 {
        case 0:
            Image(systemName: "heart")
                .font(NekoTypography.font(.iconMedium))
                .foregroundStyle(NekoTheme.soulPink.opacity(0.50))
        case 1:
            Image(systemName: "pawprint")
                .font(NekoTypography.font(.iconMedium))
                .foregroundStyle(NekoTheme.soulViolet.opacity(0.42))
        default:
            SparkleDecoration()
                .stroke(NekoTheme.softPink.opacity(0.52), lineWidth: 2)
        }
    }
}

struct SparkleDecoration: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.midX, y: rect.midY * 0.75),
            control2: CGPoint(x: rect.midX * 1.25, y: rect.midY)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.midX * 1.25, y: rect.midY),
            control2: CGPoint(x: rect.midX, y: rect.midY * 1.25)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.midY),
            control1: CGPoint(x: rect.midX, y: rect.midY * 1.25),
            control2: CGPoint(x: rect.midX * 0.75, y: rect.midY)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.midX * 0.75, y: rect.midY),
            control2: CGPoint(x: rect.midX, y: rect.midY * 0.75)
        )
        return path
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
