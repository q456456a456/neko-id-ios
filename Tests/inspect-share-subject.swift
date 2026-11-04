// Read-only macOS diagnostic for the same Vision requests used by share export.
// Simulator Vision may return no detections; run this against the actual photo
// to exercise the host's image-analysis implementation without any network.
import AppKit
import Vision

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let image = NSImage(contentsOf: url)!
var rect = CGRect(origin: .zero, size: image.size)
let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
let animal = VNRecognizeAnimalsRequest()
do {
    try VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([animal])
    for observation in animal.results ?? [] {
        print("Animal:", observation.boundingBox, observation.labels.map { ($0.identifier, $0.confidence) })
    }
} catch { print("Animal error:", error) }
let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
do {
    try VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([saliency])
    for object in saliency.results?.first?.salientObjects ?? [] {
        print("Saliency:", object.boundingBox, object.confidence)
    }
} catch { print("Saliency error:", error) }
