import Photos
import SwiftUI
import UIKit
import Vision

struct VoiceShareCardData {
    let catName: String
    let mbti: String
    let personalityTitle: String
    let sceneTags: [String]
    let photo: UIImage
    let generatedVoice: String
    let analysisText: String
}
private enum VoiceShareLayout {
    static let canvasSize = CGSize(width: 360, height: 480)
    static let canvasScale: CGFloat = 3
    static let pageMargin: CGFloat = 20
    static let verticalPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 8
    static let photoRadius: CGFloat = 24
    static let photoMinimumHeight: CGFloat = 220
    static let photoMaximumHeight: CGFloat = 265
    static let cardRadius: CGFloat = 22
    static let cardPadding: CGFloat = 10
    static let bubblePadding: CGFloat = 12
    static let bubbleMinimumHeight: CGFloat = 80
    static let bubbleMaximumHeight: CGFloat = 92
}

struct VoiceShareCard: View {
    let data: VoiceShareCardData
    let subject: HeartVoiceSubject?

    var body: some View {
        VStack(alignment: .leading, spacing: VoiceShareLayout.sectionSpacing) {
            header

            VoiceSharePhotoStage(data: data, subject: subject)
                .frame(maxWidth: .infinity)
                .frame(
                    minHeight: VoiceShareLayout.photoMinimumHeight,
                    maxHeight: VoiceShareLayout.photoMaximumHeight
                )
                .layoutPriority(1)

            insightCard

            Text("喵一下 · 读懂它的小世界")
                .nekoText(.tiny)
                .foregroundStyle(NekoTheme.muted)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, VoiceShareLayout.pageMargin)
        .padding(.vertical, VoiceShareLayout.verticalPadding)
        .frame(
            width: VoiceShareLayout.canvasSize.width,
            height: VoiceShareLayout.canvasSize.height,
            alignment: .topLeading
        )
        .background(NekoTheme.backgroundGradient)
        .clipped()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("喵一下")
                .nekoText(.tiny)
                .foregroundStyle(NekoTheme.muted)
            Text("\(data.catName) · \(data.mbti)")
                .nekoText(.moduleTitle)
                .foregroundStyle(NekoTheme.ink)
            Text(data.personalityTitle)
                .nekoText(.badge)
                .foregroundStyle(NekoTheme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AI 解读")
                .nekoText(.voiceInsightTitle)
                .foregroundStyle(NekoTheme.ink)

            Text(data.analysisText)
                .nekoText(.support)
                .foregroundStyle(NekoTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            if !data.sceneTags.isEmpty {
                VoiceShareTagFlowLayout(spacing: 6) {
                    ForEach(Array(data.sceneTags.prefix(3).enumerated()), id: \.offset) { index, tag in
                        Text("#\(tag)")
                            .nekoText(.micro)
                            .foregroundStyle(index.isMultiple(of: 2) ? NekoTheme.ink : NekoTheme.dangerRed)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                index.isMultiple(of: 2)
                                    ? NekoTheme.softLilac.opacity(0.58)
                                    : NekoTheme.softPink.opacity(0.66),
                                in: Capsule()
                            )
                    }
                }
            }
        }
        .padding(VoiceShareLayout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NekoTheme.cardWhite, in: RoundedRectangle(cornerRadius: VoiceShareLayout.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VoiceShareLayout.cardRadius, style: .continuous)
                .stroke(NekoTheme.softLilac.opacity(0.88), lineWidth: 1)
        }
    }
}

private struct VoiceSharePhotoStage: View {
    let data: VoiceShareCardData
    let subject: HeartVoiceSubject?

    var body: some View {
        GeometryReader { proxy in
            let stageSize = proxy.size
            let bubbleWidthRatio = SubjectLayoutEngine.bubbleWidthRatio(
                for: subject,
                detectionFinished: true
            )
            let bubbleWidth = stageSize.width * bubbleWidthRatio
            let bubbleHeight = measuredBubbleHeight(
                text: data.generatedVoice,
                width: bubbleWidth
            )
            let layout = SubjectLayoutEngine.layout(
                image: data.photo,
                stageSize: stageSize,
                subject: subject,
                bubbleSize: CGSize(width: bubbleWidth, height: bubbleHeight)
            )

            ZStack(alignment: .topLeading) {
                NekoTheme.photoPlaceholderGradient

                Image(uiImage: data.photo)
                    .resizable()
                    .frame(width: layout.imageFrame.width, height: layout.imageFrame.height)
                    .position(x: layout.imageFrame.midX, y: layout.imageFrame.midY)

                VoiceShareSpeechBubble(
                    catName: data.catName,
                    text: data.generatedVoice,
                    placement: layout.bubblePlacement
                )
                .frame(width: layout.bubbleFrame.width, height: layout.bubbleFrame.height)
                .position(x: layout.bubbleFrame.midX, y: layout.bubbleFrame.midY)
            }
            .frame(width: stageSize.width, height: stageSize.height)
            .clipShape(RoundedRectangle(cornerRadius: VoiceShareLayout.photoRadius, style: .continuous))
        }
    }

    private func measuredBubbleHeight(text: String, width: CGFloat) -> CGFloat {
        let textWidth = max(1, width - VoiceShareLayout.bubblePadding * 2)
        let estimatedCharactersPerLine = max(5, Int(textWidth / 12))
        let estimatedLineCount = max(
            1,
            Int(ceil(Double(text.count) / Double(estimatedCharactersPerLine)))
        )
        let contentHeight = CGFloat(estimatedLineCount) * 16 + 18
            + VoiceShareLayout.bubblePadding * 2
        return max(VoiceShareLayout.bubbleMinimumHeight, min(112, contentHeight))
    }
}

private struct VoiceShareSpeechBubble: View {
    let catName: String
    let text: String
    let placement: HeartVoiceBubblePlacement

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(catName)
                .nekoText(.tiny)
                .foregroundStyle(NekoTheme.muted)
                .lineLimit(1)
            Text(text)
                .nekoText(.micro)
                .foregroundStyle(NekoTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(VoiceShareLayout.bubblePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.90), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(NekoTheme.softLilac.opacity(0.92), lineWidth: 1)
        }
        .overlay(alignment: placement == .topLeft ? .bottomTrailing : .bottomLeading) {
            HeartVoiceBubbleTail()
                .fill(Color.white.opacity(0.90))
                .frame(width: 12, height: 8)
                .scaleEffect(x: placement == .topLeft ? -1 : 1, y: 1)
                .offset(x: placement == .topLeft ? -10 : 10, y: 5)
        }
    }
}

private struct VoiceShareTagFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let availableWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maximumRowWidth: CGFloat = 0
        var points: [CGPoint] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > availableWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            maximumRowWidth = max(maximumRowWidth, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }

        let measuredWidth = availableWidth.isFinite ? availableWidth : maximumRowWidth
        return (CGSize(width: measuredWidth, height: y + rowHeight), points)
    }
}

private enum VoiceShareSubjectDetector {
    static func detect(in image: UIImage) async -> HeartVoiceSubject? {
        if let animal = await HeartVoiceSubjectDetector.detect(in: image) {
            return animal
        }
        guard let cgImage = image.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNGenerateAttentionBasedSaliencyImageRequest()
                let handler = VNImageRequestHandler(
                    cgImage: cgImage,
                    orientation: cgOrientation(for: image.imageOrientation),
                    options: [:]
                )

                do {
                    try handler.perform([request])
                    guard let observation = request.results?.first,
                          let salient = observation.salientObjects?.max(by: {
                              $0.boundingBox.width * $0.boundingBox.height
                                  < $1.boundingBox.width * $1.boundingBox.height
                          }) else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let subjectBox = topLeadingNormalized(salient.boundingBox)
                    let faceBox = estimatedFaceBox(in: subjectBox)
                    continuation.resume(
                        returning: HeartVoiceSubject(
                            catBoundingBox: subjectBox,
                            catFaceBoundingBox: faceBox
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

    private static func estimatedFaceBox(in subject: CGRect) -> CGRect {
        let faceHeight = subject.height * 0.52
        let faceWidth = subject.width * 0.82
        return CGRect(
            x: subject.midX - faceWidth / 2,
            y: subject.minY,
            width: faceWidth,
            height: faceHeight
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private static func cgOrientation(for orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}

@MainActor
enum VoiceShareImageRenderer {
    static func render(data: VoiceShareCardData) async -> UIImage? {
        let subject = await VoiceShareSubjectDetector.detect(in: data.photo)
        let renderer = ImageRenderer(content: VoiceShareCard(data: data, subject: subject))
        renderer.proposedSize = ProposedViewSize(
            width: VoiceShareLayout.canvasSize.width,
            height: VoiceShareLayout.canvasSize.height
        )
        renderer.scale = VoiceShareLayout.canvasScale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

struct VoiceSystemShareView: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum VoicePhotoLibrarySaver {
    static func save(_ image: UIImage) async throws {
        guard image.size.width > 0,
              image.size.height > 0,
              image.cgImage != nil || image.ciImage != nil else {
            print("[VoicePhotoLibrarySaver] Refused to save an invalid UIImage.")
            throw VoiceShareError.renderFailed
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        switch status {
        case .authorized, .limited:
            break
        case .denied, .restricted:
            print("[VoicePhotoLibrarySaver] Photo add-only permission unavailable: \(status.rawValue)")
            throw VoiceShareError.photoPermissionDenied
        case .notDetermined:
            print("[VoicePhotoLibrarySaver] Photo authorization remained undetermined.")
            throw VoiceShareError.photoPermissionDenied
        @unknown default:
            print("[VoicePhotoLibrarySaver] Unknown photo authorization status: \(status.rawValue)")
            throw VoiceShareError.photoPermissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if let error {
                    print("[VoicePhotoLibrarySaver] PHPhotoLibrary performChanges failed: \(error)")
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    print("[VoicePhotoLibrarySaver] PHPhotoLibrary returned success=false without an error.")
                    continuation.resume(throwing: VoiceShareError.saveFailed)
                }
            }
        }
    }
}

enum VoiceShareError: LocalizedError {
    case missingContent
    case photoPermissionDenied
    case renderFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .missingContent:
            return "分享图内容还没有准备好，请稍后再试。"
        case .photoPermissionDenied:
            return "无法保存图片，请前往系统设置开启照片添加权限。"
        case .renderFailed:
            return "分享图生成失败，请稍后再试。"
        case .saveFailed:
            return "保存到相册失败，请稍后再试。"
        }
    }
}

