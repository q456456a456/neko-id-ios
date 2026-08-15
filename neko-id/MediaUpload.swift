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

enum NekoMediaError: LocalizedError {
    case unsupportedImage
    case unsupportedVideo
    case imageTooLarge
    case videoTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            return "这张图片格式暂时不支持，请换一张 JPG、PNG 或系统相册里的普通照片。"
        case .unsupportedVideo:
            return "这段视频暂时无法读取，请换一段猫咪日常视频。"
        case .imageTooLarge:
            return "图片太大了，请选择 10MB 以内的图片。"
        case .videoTooLarge:
            return "视频不能超过 100MB，请压缩后再上传。"
        }
    }
}

enum MediaUploadProcessor {
    private static let maxAIImageBytes = 1_500_000

    static func prepareAvatarImage(from data: Data) throws -> PreparedImageUpload {
        if let detected = detectImageType(data), data.count <= AppConfig.maxAvatarImageBytes {
            return PreparedImageUpload(
                data: data,
                mimeType: detected.mimeType,
                fileExtension: detected.fileExtension
            )
        }

        guard let image = UIImage(data: data) else {
            throw NekoMediaError.unsupportedImage
        }

        let normalized = image.resizedToFit(maxDimension: 1600)
        for quality in [0.9, 0.82, 0.74, 0.66, 0.58, 0.5, 0.42] {
            guard let jpeg = normalized.jpegData(compressionQuality: quality) else { continue }
            if jpeg.count <= AppConfig.maxAvatarImageBytes {
                return PreparedImageUpload(data: jpeg, mimeType: "image/jpeg", fileExtension: "jpg")
            }
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
            defer { try? FileManager.default.removeItem(at: temporaryURL) }

            let asset = AVURLAsset(url: temporaryURL)
            let duration = try await asset.load(.duration)
            let durationLabel = formatDuration(duration.seconds)
            let thumbnailData = makeThumbnailData(from: asset)

            return OnboardingVideoClip(
                label: label,
                durationLabel: durationLabel,
                sizeLabel: sizeLabel,
                thumbnailData: thumbnailData
            )
        } catch {
            return OnboardingVideoClip(
                label: label,
                durationLabel: "已选择",
                sizeLabel: sizeLabel,
                thumbnailData: nil
            )
        }
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
