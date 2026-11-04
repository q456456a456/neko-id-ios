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
    static let canvasWidth: CGFloat = 360
    static let canvasMinimumHeight: CGFloat = 528
    static let canvasScale: CGFloat = 3
    static let pageMargin: CGFloat = 20
    static let verticalPadding: CGFloat = 14
    static let bottomPadding: CGFloat = 24
    static let watermarkSpacing: CGFloat = 16
    static let sectionSpacing: CGFloat = 8
    static let photoRadius: CGFloat = 24
    static let photoMinimumHeight: CGFloat = 220
    static let cardRadius: CGFloat = 22
    static let cardPadding: CGFloat = 10
    static let bubbleMaximumBodyLines = 5
    // Responsive export fallback on the existing 4/8pt grid. Only used when
    // regular padding cannot show the voice; font and photo crop stay intact.
    static let bubbleCompactPadding: CGFloat = 8
    // Design System: keep at least 60% of the photo unobstructed.
    static let bubbleMaximumAreaRatio: CGFloat = 0.40
    // User-authorized export-only exception: at most one third of the visible
    // estimated face region may be covered when that makes the voice readable.
    static let bubbleMaximumFaceOverlapRatio: CGFloat = 1.0 / 3.0
}

/// Export-only readability policy; never relax the result/detail face rule.
/// Use a wider, shorter full-text bubble within the user-authorized face budget;
/// otherwise maximize readable text instead of reverting to a narrow bubble.
/// Result/detail pages keep their existing three-line policy.
struct VoiceShareBubbleLayout {
    let stage: HeartVoiceStageLayout
    let bodyLineLimit: Int
    let contentPadding: CGFloat

    private struct Candidate {
        let bubble: VoiceShareBubbleLayout
        let faceOverlap: CGFloat
        let fitsText: Bool
    }

    static func make(
        image: UIImage?, stageSize: CGSize, subject: HeartVoiceSubject?, catName: String, text: String
    ) -> VoiceShareBubbleLayout {
        let regular = make(image: image, stageSize: stageSize, subject: subject, catName: catName, text: text,
                           contentPadding: HeartVoiceLayout.bubblePadding)
        func visibleCount(_ layout: VoiceShareBubbleLayout) -> Int {
            HeartVoiceBubbleMetrics.visibleCharacterCount(
                text: text, width: layout.stage.bubbleFrame.width, lines: layout.bodyLineLimit,
                contentPadding: layout.contentPadding)
        }
        let regularCount = visibleCount(regular)
        if regularCount == text.count { return regular }
        let compact = make(image: image, stageSize: stageSize, subject: subject, catName: catName, text: text,
                           contentPadding: VoiceShareLayout.bubbleCompactPadding)
        return visibleCount(compact) > regularCount ? compact : regular
    }

    private static func make(
        image: UIImage?, stageSize: CGSize, subject: HeartVoiceSubject?, catName: String, text: String,
        contentPadding: CGFloat
    ) -> VoiceShareBubbleLayout {
        let standard = SubjectLayoutEngine.layout(
            image: image, stageSize: stageSize, subject: subject, catName: catName, text: text
        )
        let initialSize = HeartVoiceBubbleMetrics.size(catName: catName, text: text, width: standard.bubbleFrame.width,
                                                       contentPadding: contentPadding)
        let fallback = VoiceShareBubbleLayout(stage: HeartVoiceStageLayout(
            imageFrame: standard.imageFrame, bubbleFrame: CGRect(origin: standard.bubbleFrame.origin, size: initialSize),
            bubblePlacement: standard.bubblePlacement), bodyLineLimit: HeartVoiceLayout.bubbleBodyLineLimit,
            contentPadding: contentPadding)
        // The budget is a fraction of the visible, estimated face, NOT the
        // padded avoidance box or the full photo (which would be too lenient).
        let photoBounds = CGRect(origin: .zero, size: stageSize)
        let visibleFace = subject?.catFaceBoundingBox.map { face in
            CGRect(
                x: standard.imageFrame.minX + face.minX * standard.imageFrame.width,
                y: standard.imageFrame.minY + face.minY * standard.imageFrame.height,
                width: face.width * standard.imageFrame.width,
                height: face.height * standard.imageFrame.height
            ).intersection(photoBounds)
        }
        func faceOverlapRatio(_ frame: CGRect) -> CGFloat {
            guard let visibleFace, !visibleFace.isNull, visibleFace.width > 0, visibleFace.height > 0 else { return 0 }
            let overlap = frame.intersection(visibleFace)
            return overlap.isNull ? 0 : overlap.width * overlap.height / (visibleFace.width * visibleFace.height)
        }
        let bounds = photoBounds
            .insetBy(dx: HeartVoiceLayout.bubbleInset, dy: HeartVoiceLayout.bubbleInset)
        let maximumArea = stageSize.width * stageSize.height * VoiceShareLayout.bubbleMaximumAreaRatio
        func candidate(_ bubble: VoiceShareBubbleLayout) -> Candidate? {
            let frame = bubble.stage.bubbleFrame
            // Include the tail conservatively in both budgets, not just the
            // rounded body. Its enclosing rectangle slightly overestimates ink.
            let coverage = CGRect(x: frame.minX, y: frame.minY, width: frame.width,
                                  height: frame.height + HeartVoiceLayout.bubbleTailOverflow)
            let overlap = faceOverlapRatio(coverage)
            guard bounds.contains(frame), photoBounds.contains(coverage),
                  coverage.width * coverage.height <= maximumArea,
                  overlap <= VoiceShareLayout.bubbleMaximumFaceOverlapRatio else { return nil }
            return Candidate(
                bubble: bubble, faceOverlap: overlap,
                fitsText: HeartVoiceBubbleMetrics.fitsInLines(text: text, width: frame.width, lines: bubble.bodyLineLimit,
                                                            contentPadding: contentPadding)
            )
        }
        let original = candidate(fallback)
        if let original, original.fitsText && original.faceOverlap == 0 { return fallback }

        let naturalWidth = HeartVoiceBubbleMetrics.naturalWidth(catName: catName, text: text, contentPadding: contentPadding)
        let minimumWidth = min(bounds.width, naturalWidth, stageSize.width * HeartVoiceLayout.bubbleMinimumWidthRatio)
        let maximumWidth = min(bounds.width, naturalWidth, stageSize.width * HeartVoiceLayout.bubbleMaximumWidthRatio)
        var widths = [minimumWidth, maximumWidth, standard.bubbleFrame.width]
        widths += [0.25, 0.5, 0.75].map { minimumWidth + (maximumWidth - minimumWidth) * $0 }
        // Exact wrapping boundaries are required: the old engine only returned
        // its least-overlapping option, even when a wider readable one was legal.
        for lines in 1...VoiceShareLayout.bubbleMaximumBodyLines {
            if let width = HeartVoiceBubbleMetrics.minimumFittingWidth(
                text: text, lines: lines, minimum: minimumWidth, maximum: maximumWidth, showsLoadingIndicator: false,
                contentPadding: contentPadding
            ) { widths.append(width) }
        }
        if let visibleFace, !visibleFace.isNull {
            for clearance in [CGFloat.zero, HeartVoiceLayout.subjectClearance] {
                widths += [visibleFace.minX - bounds.minX - clearance,
                           bounds.maxX - visibleFace.maxX - clearance]
            }
        }
        // A coarse set of widths can skip the best legal fallback. Include the
        // exact area/face-budget boundaries for each possible measured height.
        // Wrapped full-text heights and capped heights can differ slightly.
        let sampledWidths = widths.filter { $0 >= minimumWidth && $0 <= maximumWidth }
        let heights = Set(sampledWidths.flatMap { width in
            (1...VoiceShareLayout.bubbleMaximumBodyLines).map { lines in
                HeartVoiceBubbleMetrics.size(catName: catName, text: text, width: width, bodyLineLimit: lines,
                                             contentPadding: contentPadding).height
            }
        })
        func addBoundary(_ width: CGFloat) {
            // Round inward to avoid exceeding a strict geometric budget due to
            // floating-point error. This is precision, not a new spacing token.
            widths.append(floor(width * 1_000) / 1_000)
        }
        for height in heights {
            let coverageHeight = height + HeartVoiceLayout.bubbleTailOverflow
            addBoundary(maximumArea / coverageHeight)
            guard let visibleFace, !visibleFace.isNull, visibleFace.width > 0, visibleFace.height > 0 else { continue }
            for y in [bounds.minY, bounds.maxY - height] {
                let verticalOverlap = max(0, min(y + coverageHeight, visibleFace.maxY) - max(y, visibleFace.minY))
                guard verticalOverlap > 0 else { continue }
                let allowedOverlap = visibleFace.width * visibleFace.height
                    * VoiceShareLayout.bubbleMaximumFaceOverlapRatio / verticalOverlap
                guard allowedOverlap < visibleFace.width else { continue }
                addBoundary(visibleFace.minX - bounds.minX + allowedOverlap)
                addBoundary(bounds.maxX - visibleFace.maxX + allowedOverlap)
            }
        }
        let availableWidths = Set(widths.filter { $0 >= minimumWidth && $0 <= maximumWidth }).sorted()
        func candidates(lines: [Int], atBottom: Bool = false) -> [Candidate] {
            lines.flatMap { limit in
                availableWidths.flatMap { width in
                    let size = HeartVoiceBubbleMetrics.size(catName: catName, text: text, width: width, bodyLineLimit: limit,
                                                           contentPadding: contentPadding)
                    return HeartVoiceBubblePlacement.allCases.compactMap { placement in
                        let frame = CGRect(
                            x: placement == .topLeft ? bounds.minX : bounds.maxX - width,
                            y: atBottom ? bounds.maxY - size.height : bounds.minY,
                            width: width, height: size.height
                        )
                        return candidate(VoiceShareBubbleLayout(
                            stage: HeartVoiceStageLayout(imageFrame: standard.imageFrame, bubbleFrame: frame, bubblePlacement: placement),
                            bodyLineLimit: limit, contentPadding: contentPadding
                        ))
                    }
                }
            }
        }
        func best(_ options: [Candidate]) -> VoiceShareBubbleLayout? {
            guard !options.isEmpty else { return nil }
            // Resolve geometry/readability first. Sampling image pixels for
            // every rejected width is expensive and cannot affect the winner.
            var eligible = options
            if eligible.contains(where: \.fitsText) {
                eligible = eligible.filter(\.fitsText)
                let fewestLines = eligible.map { $0.bubble.bodyLineLimit }.min()!
                eligible = eligible.filter { $0.bubble.bodyLineLimit == fewestLines }
            } else {
                let readable = eligible.map { option in
                    (option: option, visible: HeartVoiceBubbleMetrics.visibleCharacterCount(
                        text: text, width: option.bubble.stage.bubbleFrame.width, lines: option.bubble.bodyLineLimit,
                        contentPadding: contentPadding))
                }
                let mostVisible = readable.map(\.visible).max()!
                eligible = readable.filter { $0.visible == mostVisible }.map(\.option)
            }
            // The face region is estimated from an animal box. Sub-percent
            // asymmetry is not meaningful precision: in the same 1% band,
            // prefer the quieter image area over textured facial features.
            // The exact one-third budget was already enforced above.
            let lowestOverlapBand = eligible.map { Int(($0.faceOverlap * 100).rounded()) }.min()!
            eligible = eligible.filter { Int(($0.faceOverlap * 100).rounded()) == lowestOverlapBand }
            let scored = eligible.map { option in
                (option: option, background: SubjectLayoutEngine.backgroundScore(
                    image: image, candidate: option.bubble.stage.bubbleFrame, imageFrame: standard.imageFrame))
            }
            return scored.min { left, right in
                let lhs = left.option
                let rhs = right.option
                if left.background != right.background { return left.background > right.background }
                if lhs.bubble.bodyLineLimit != rhs.bubble.bodyLineLimit { return lhs.bubble.bodyLineLimit < rhs.bubble.bodyLineLimit }
                let leftWidth = lhs.bubble.stage.bubbleFrame.width
                let rightWidth = rhs.bubble.stage.bubbleFrame.width
                if leftWidth != rightWidth { return lhs.fitsText ? leftWidth < rightWidth : leftWidth > rightWidth }
                return lhs.bubble.stage.bubblePlacement == standard.bubblePlacement
                    && rhs.bubble.stage.bubblePlacement != standard.bubblePlacement
            }?.option.bubble
        }
        let topCandidates = candidates(lines: Array(3...VoiceShareLayout.bubbleMaximumBodyLines))
        if let full = best(topCandidates.filter(\.fitsText)) { return full }
        // Check the lower corners before truncating. If the full voice cannot
        // fit anywhere, retain the most visible text within all three caps.
        let lowerCandidates = candidates(lines: Array(3...VoiceShareLayout.bubbleMaximumBodyLines), atBottom: true)
        if let full = best(lowerCandidates.filter(\.fitsText)) { return full }
        let compactCandidates = candidates(lines: [1, 2]) + candidates(lines: [1, 2], atBottom: true)
        return best(topCandidates + lowerCandidates + compactCandidates) ?? fallback
    }
}

struct VoiceShareCard: View {
    let data: VoiceShareCardData
    let subject: HeartVoiceSubject?

    // The shared model separates observation/interpretation with blank lines.
    // Match the detail page's continuous paragraph at the presentation boundary
    // without rewriting stored/generated text or changing other consumers.
    static func compactAnalysis(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var body: some View {
        VoiceSharePosterStack {
            header

            VoiceSharePhotoStage(data: data, subject: subject)

            insightCard

            Text("喵一下 · 读懂它的小世界")
                .nekoText(.caption)
                .foregroundStyle(NekoTheme.inkSoft)
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, VoiceShareLayout.pageMargin)
        .padding(.top, VoiceShareLayout.verticalPadding)
        .padding(.bottom, VoiceShareLayout.bottomPadding)
        .frame(width: VoiceShareLayout.canvasWidth, alignment: .topLeading)
        .background(NekoTheme.backgroundGradient)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
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

            Text(Self.compactAnalysis(data.analysisText))
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

/// Reserve measured text and fixed footer spacing first. Give unused canvas
/// height to the photo, rather than leaving a blank block above the watermark.
/// Longer text can still grow the canvas without shrinking the photo below its
/// minimum or clipping the footer.
struct VoiceSharePosterStack: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        geometry(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = geometry(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                 anchor: .topLeading,
                                 proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func geometry(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let width = proposal.width ?? VoiceShareLayout.canvasWidth - 2 * VoiceShareLayout.pageMargin
        let textProposal = ProposedViewSize(width: width, height: nil)
        let headerHeight = subviews[0].sizeThatFits(textProposal).height
        let insightHeight = subviews[2].sizeThatFits(textProposal).height
        let watermarkHeight = subviews[3].sizeThatFits(textProposal).height
        return Self.geometry(width: width, headerHeight: headerHeight, insightHeight: insightHeight,
                             watermarkHeight: watermarkHeight)
    }

    static func geometry(width: CGFloat, headerHeight: CGFloat, insightHeight: CGFloat,
                         watermarkHeight: CGFloat) -> (size: CGSize, frames: [CGRect]) {
        let minimumHeight = VoiceShareLayout.canvasMinimumHeight - VoiceShareLayout.verticalPadding - VoiceShareLayout.bottomPadding
        let photoBudget = minimumHeight - headerHeight - insightHeight - watermarkHeight
            - 2 * VoiceShareLayout.sectionSpacing - VoiceShareLayout.watermarkSpacing
        let photoHeight = max(VoiceShareLayout.photoMinimumHeight, photoBudget)
        let photoY = headerHeight + VoiceShareLayout.sectionSpacing
        let insightY = photoY + photoHeight + VoiceShareLayout.sectionSpacing
        let watermarkY = insightY + insightHeight + VoiceShareLayout.watermarkSpacing
        let height = watermarkY + watermarkHeight
        return (CGSize(width: width, height: height), [
            CGRect(x: 0, y: 0, width: width, height: headerHeight),
            CGRect(x: 0, y: photoY, width: width, height: photoHeight),
            CGRect(x: 0, y: insightY, width: width, height: insightHeight),
            CGRect(x: 0, y: watermarkY, width: width, height: watermarkHeight)
        ])
    }
}

private struct VoiceSharePhotoStage: View {
    let data: VoiceShareCardData
    let subject: HeartVoiceSubject?

    var body: some View {
        GeometryReader { proxy in
            let stageSize = proxy.size
            let bubble = VoiceShareBubbleLayout.make(
                image: data.photo,
                stageSize: stageSize,
                subject: subject,
                catName: data.catName,
                text: data.generatedVoice
            )
            let layout = bubble.stage

            ZStack(alignment: .topLeading) {
                NekoTheme.photoPlaceholderGradient

                Image(uiImage: data.photo)
                    .resizable()
                    .frame(width: layout.imageFrame.width, height: layout.imageFrame.height)
                    .position(x: layout.imageFrame.midX, y: layout.imageFrame.midY)

                SpeechBubbleView(
                    catName: data.catName,
                    text: data.generatedVoice,
                    placement: layout.bubblePlacement,
                    bodyLineLimit: bubble.bodyLineLimit,
                    contentPadding: bubble.contentPadding
                )
                .frame(width: layout.bubbleFrame.width, height: layout.bubbleFrame.height)
                .position(x: layout.bubbleFrame.midX, y: layout.bubbleFrame.midY)
            }
            .frame(width: stageSize.width, height: stageSize.height)
            .clipShape(RoundedRectangle(cornerRadius: VoiceShareLayout.photoRadius, style: .continuous))
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
        return render(data: data, subject: subject)
    }

    // Keep the actual export path testable with device/host Vision results;
    // the simulator can silently return nil for both detection requests.
    static func render(data: VoiceShareCardData, subject: HeartVoiceSubject?) -> UIImage? {
        let renderer = ImageRenderer(content: VoiceShareCard(data: data, subject: subject))
        renderer.proposedSize = ProposedViewSize(
            width: VoiceShareLayout.canvasWidth,
            height: nil
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
