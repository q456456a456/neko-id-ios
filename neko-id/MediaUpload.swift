//
//  MediaUpload.swift
//  neko-id
//
//  Created by Codex on 2026/8/15.
//

import AVFoundation
import Foundation
import UIKit

struct PreparedImageUpload {
    let data: Data
    let mimeType: String
    let fileExtension: String
}

enum NekoMediaAspect {
    static let portrait = "3:4"
    static let landscape = "4:3"
    static let square = "1:1"

    private static let squareTolerance: CGFloat = 0.08

    static func storedAspect(from data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        return fixedAspect(for: imageRatio(image))
    }

    static func displayRatio(for storedAspect: String?, image: UIImage? = nil) -> CGFloat {
        if let image {
            return ratio(for: fixedAspect(for: imageRatio(image)))
        }

        if let storedRatio = numericRatio(for: storedAspect) {
            return ratio(for: fixedAspect(for: storedRatio))
        }

        return ratio(for: portrait)
    }

    private static func imageRatio(_ image: UIImage) -> CGFloat {
        max(image.size.width, 1) / max(image.size.height, 1)
    }

    private static func fixedAspect(for ratio: CGFloat) -> String {
        if abs(ratio - 1) <= squareTolerance {
            return square
        }
        return ratio > 1 ? landscape : portrait
    }

    private static func ratio(for aspect: String) -> CGFloat {
        switch aspect {
        case landscape:
            return 4.0 / 3.0
        case square:
            return 1.0
        default:
            return 3.0 / 4.0
        }
    }

    private static func numericRatio(for aspect: String?) -> CGFloat? {
        guard let aspect else { return nil }
        let parts = aspect.split(separator: ":")
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              width > 0,
              height > 0
        else {
            return nil
        }
        return CGFloat(width / height)
    }
}

enum NekoMediaError: LocalizedError {
    case unsupportedImage
    case unsupportedVideo
    case imageTooLarge
    case videoTooLarge
    case videoTooShort(duration: Double)
    case videoTooLong(duration: Double)

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            return "这张图片格式暂时不支持，请换一张 JPG、PNG 或系统相册里的普通照片。"
        case .unsupportedVideo:
            return "这段视频暂时无法读取，请换一段猫咪日常视频。"
        case .imageTooLarge:
            return "图片太大了，请选择10MB以内的图片。"
        case .videoTooLarge:
            return "视频不能超过 100MB，请压缩后再上传。"
        case .videoTooShort(let duration):
            return "视频只有 \(formatVideoDuration(duration))，必须至少 5 秒。"
        case .videoTooLong(let duration):
            return "视频时长为 \(formatVideoDuration(duration))，不能超过 60 秒。"
        }
    }

    private func formatVideoDuration(_ seconds: Double) -> String {
        let safeSeconds = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", safeSeconds / 60, safeSeconds % 60)
    }
}

enum MediaUploadProcessor {
    private static let maxAIImageBytes = 1_500_000

    static func prepareAvatarImage(from data: Data) throws -> PreparedImageUpload {
        guard data.count <= AppConfig.maxAvatarImageBytes else {
            throw NekoMediaError.imageTooLarge
        }
        return try prepareStoredImageUpload(from: data, maxBytes: AppConfig.maxAvatarImageBytes)
    }

    static func prepareVoiceImage(from data: Data) throws -> PreparedImageUpload {
        guard data.count <= AppConfig.maxVoiceImageBytes else {
            throw NekoMediaError.imageTooLarge
        }
        return try prepareStoredImageUpload(from: data, maxBytes: AppConfig.maxVoiceImageBytes)
    }

    private static func prepareStoredImageUpload(from data: Data, maxBytes: Int) throws -> PreparedImageUpload {
        guard let image = UIImage(data: data) else {
            throw NekoMediaError.unsupportedImage
        }

        let normalized = image.resizedToFit(maxDimension: 1600)
        var fallback: Data?

        for quality in [0.82, 0.74, 0.66, 0.58, 0.5, 0.42] {
            guard let jpeg = normalized.jpegData(compressionQuality: quality) else { continue }
            guard jpeg.count <= maxBytes else { continue }

            if jpeg.count <= data.count {
                return PreparedImageUpload(data: jpeg, mimeType: "image/jpeg", fileExtension: "jpg")
            }

            fallback = fallback ?? jpeg
        }

        if let fallback {
            return PreparedImageUpload(data: fallback, mimeType: "image/jpeg", fileExtension: "jpg")
        }

        throw NekoMediaError.imageTooLarge
    }

    static func makeAIImageDataURL(from data: Data) throws -> String {
        guard let image = UIImage(data: data) else {
            throw NekoMediaError.unsupportedImage
        }

        let normalized = image.resizedToFit(maxDimension: 900)
        for quality in [0.82, 0.74, 0.66, 0.58, 0.5, 0.42] {
            guard let jpeg = normalized.jpegData(compressionQuality: quality) else { continue }
            if jpeg.count <= maxAIImageBytes {
                return "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
            }
        }

        throw NekoMediaError.imageTooLarge
    }

    static func prepareOnboardingVideo(
        from data: Data,
        preferredLabel: String,
        currentCount: Int
    ) async throws -> OnboardingVideoClip {
        guard data.count <= AppConfig.maxOnboardingVideoBytes else {
            throw NekoMediaError.videoTooLarge
        }

        let label = preferredLabel.isEmpty ? "视频 \(currentCount + 1)" : preferredLabel
        let sizeLabel = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("neko-onboarding-\(UUID().uuidString)")
            .appendingPathExtension("mov")

        do {
            try data.write(to: temporaryURL, options: .atomic)
        } catch {
            throw NekoMediaError.unsupportedVideo
        }
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let asset = AVURLAsset(url: temporaryURL)
        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            throw NekoMediaError.unsupportedVideo
        }

        let seconds = duration.seconds
        guard seconds.isFinite, seconds >= 0 else {
            throw NekoMediaError.unsupportedVideo
        }
        guard seconds >= 5 else {
            throw NekoMediaError.videoTooShort(duration: seconds)
        }
        guard seconds <= 60 else {
            throw NekoMediaError.videoTooLong(duration: seconds)
        }

        return OnboardingVideoClip(
            label: label,
            durationLabel: formatDuration(seconds),
            sizeLabel: sizeLabel,
            thumbnailData: makeThumbnailData(from: asset)
        )
    }

    private static func detectImageType(_ data: Data) -> (mimeType: String, fileExtension: String)? {
        let bytes = [UInt8](data.prefix(12))

        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return ("image/jpeg", "jpg")
        }

        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return ("image/png", "png")
        }

        if bytes.starts(with: [0x47, 0x49, 0x46]) {
            return ("image/gif", "gif")
        }

        if bytes.count >= 12,
           Array(bytes[0...3]) == [0x52, 0x49, 0x46, 0x46],
           Array(bytes[8...11]) == [0x57, 0x45, 0x42, 0x50] {
            return ("image/webp", "webp")
        }

        return nil
    }

    private static func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else {
            return "已选择"
        }

        let rounded = Int(seconds.rounded())
        let minutes = rounded / 60
        let seconds = rounded % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static func makeThumbnailData(from asset: AVAsset) -> Data? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)

        do {
            let cgImage = try generator.copyCGImage(
                at: CMTime(seconds: 0.2, preferredTimescale: 600),
                actualTime: nil
            )
            return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.78)
        } catch {
            return nil
        }
    }
}

private extension UIImage {
    func resizedToFit(maxDimension: CGFloat) -> UIImage {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension else { return self }

        let scale = maxDimension / largestSide
        let nextSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        return UIGraphicsImageRenderer(size: nextSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: nextSize))
        }
    }
}
