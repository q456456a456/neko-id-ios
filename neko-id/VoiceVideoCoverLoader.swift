import AVFoundation
import UIKit
import UniformTypeIdentifiers

/// Produces the same uncropped video frame for every heart voice surface.
/// Cropping stays in the shared 3:4 viewport; originals are never modified.
enum VoiceVideoCoverLoader {
    static func image(for request: URLRequest) async throws -> UIImage {
        let (download, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: download) }
        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            throw URLError(.badServerResponse)
        }
        try Task.checkCancellation()

        // Some older records already point at an extracted poster image.
        if let poster = UIImage(contentsOfFile: download.path) {
            return poster
        }

        // URLSession downloads use a .tmp suffix, which AVFoundation cannot
        // reliably identify. Keep the video's media extension while decoding.
        let responseExtension = response.url?.pathExtension.lowercased() ?? ""
        let mediaExtension = ["mp4", "mov", "m4v"].contains(responseExtension)
            ? responseExtension
            : response.mimeType.flatMap { UTType(mimeType: $0)?.preferredFilenameExtension } ?? "mp4"
        let videoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(mediaExtension)
        try FileManager.default.moveItem(at: download, to: videoURL)
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            throw URLError(.cannotDecodeContentData)
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 1200)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: min(0.2, seconds / 2), preferredTimescale: 600)
        let frame = try await generator.image(at: time)
        try Task.checkCancellation()
        return UIImage(cgImage: frame.image)
    }
}
