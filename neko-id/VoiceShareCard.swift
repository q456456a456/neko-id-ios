import Photos
import SwiftUI
import UIKit

struct VoiceShareCardData {
    let catName: String
    let mbti: String
    let personalityTitle: String
    let personalityTags: [String]
    let photo: UIImage
    let generatedVoice: String
    let shareHeadline: String
    let insightSummary: String
}

struct VoiceShareCard: View {
    let data: VoiceShareCardData

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Image(uiImage: data.photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 414, height: 382)
                    .clipped()

                LinearGradient(
                    colors: [Color.white.opacity(0.80), Color.white.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .center
                )

                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("喵懂  NEKO.ID")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(2.2)
                            Text("\(data.catName) · \(data.mbti)")
                                .font(.system(size: 15, weight: .semibold))
                            Text(data.personalityTitle)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color(red: 0.31, green: 0.25, blue: 0.38))
                        Spacer()
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 20)

                    Spacer()

                    VStack(alignment: .leading, spacing: 7) {
                        Text(data.shareHeadline)
                            .font(.system(size: 22, weight: .semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.80)
                        Text("“\(data.generatedVoice)”")
                            .font(.system(size: 14, weight: .medium))
                            .lineSpacing(3)
                            .lineLimit(2)
                            .minimumScaleFactor(0.84)
                            .opacity(0.84)
                    }
                        .foregroundStyle(Color(red: 0.28, green: 0.23, blue: 0.34))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(.white.opacity(0.78), lineWidth: 1)
                        }
                        .shadow(color: Color.black.opacity(0.13), radius: 18, x: 0, y: 8)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)
                }
            }
            .frame(width: 414, height: 382)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("🐾 AI 读到的小心思")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.52, green: 0.37, blue: 0.61))
                    Text(data.insightSummary)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(red: 0.31, green: 0.27, blue: 0.37))
                        .lineSpacing(3)
                        .lineLimit(2)
                        .minimumScaleFactor(0.88)
                }

                HStack(spacing: 7) {
                    ForEach(Array(data.personalityTags.prefix(3)), id: \.self) { tag in
                        Text(tag.hasPrefix("#") ? tag : "#\(tag)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(red: 0.49, green: 0.34, blue: 0.58))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.66), in: Capsule())
                    }
                }

                Spacer(minLength: 0)

                Text("喵懂 · 读懂它的小世界")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(Color(red: 0.52, green: 0.46, blue: 0.59).opacity(0.82))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .frame(width: 414, height: 170, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.99, green: 0.95, blue: 0.98),
                        Color(red: 0.95, green: 0.92, blue: 1.00),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .frame(width: 414, height: 552)
        .background(Color.white)
        .clipped()
    }
}

@MainActor
enum VoiceShareImageRenderer {
    static func render(data: VoiceShareCardData) -> UIImage? {
        let renderer = ImageRenderer(content: VoiceShareCard(data: data))
        renderer.proposedSize = ProposedViewSize(width: 414, height: 552)
        renderer.scale = 3
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
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw VoiceShareError.photoPermissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
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
            return "没有相册写入权限，请在系统设置里允许喵懂添加照片。"
        case .renderFailed:
            return "分享图生成失败，请稍后再试。"
        case .saveFailed:
            return "保存到相册失败，请稍后再试。"
        }
    }
}
