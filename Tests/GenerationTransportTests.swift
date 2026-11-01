import Foundation

// Controlled transport only: never calls the model, auth or production APIs.
private final class ControlledProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var running: [String: ControlledProtocol] = [:]
    private static var starts: [String: Int] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let path = request.url!.path
        Self.running[path] = self
        Self.starts[path, default: 0] += 1
        Self.lock.unlock()
    }

    override func stopLoading() {}

    static func count(_ path: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return starts[path, default: 0]
    }

    static func take(_ path: String) -> ControlledProtocol {
        lock.lock()
        defer { lock.unlock() }
        return running.removeValue(forKey: path)!
    }

    static func complete(_ path: String, chunks: [Data] = [Data("{\"ok\":true}".utf8)], status: Int = 200) {
        let instance = take(path)
        let response = HTTPURLResponse(url: instance.request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        instance.client!.urlProtocol(instance, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in chunks { instance.client!.urlProtocol(instance, didLoad: chunk) }
        instance.client!.urlProtocolDidFinishLoading(instance)
    }

    static func fail(_ path: String) {
        let instance = take(path)
        instance.client!.urlProtocol(instance, didFailWithError: URLError(.networkConnectionLost))
    }
}

@main
enum GenerationTransportTests {
    @MainActor
    private final class ForegroundGate { var active = true }

    private static func request(_ path: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://generation.test" + path)!)
        request.httpMethod = "POST"
        request.httpBody = Data("{\"image\":\"test-image\",\"scene\":\"test-scene\"}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer test-token", forHTTPHeaderField: "Authorization")
        request.setValue("test-request-id", forHTTPHeaderField: "X-Neko-Request-ID")
        return request
    }

    @MainActor
    private static func waitForStart(_ path: String) async throws {
        for _ in 0..<300 {
            if ControlledProtocol.count(path) > 0 { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        preconditionFailure("Request never started: " + path)
    }

    private static func expectCancellation(_ task: Task<(Data, URLResponse), Error>) async {
        switch await task.result {
        case .success: preconditionFailure("Cancelled request returned a result")
        case .failure(let error): precondition(error is CancellationError)
        }
    }

    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("neko-generation-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bodies = directory.appendingPathComponent("bodies")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ControlledProtocol.self]
        let gate = ForegroundGate()
        let transport = NekoGenerationTransport(configuration: config, bodyDirectory: bodies, responseLimit: 1024, canStart: { gate.active })

        let production = NekoGenerationTransport.backgroundConfiguration(requestTimeout: 90, resourceTimeout: 120)
        precondition(production.identifier == NekoGenerationTransport.sessionIdentifier)
        precondition(!production.isDiscretionary && production.sessionSendsLaunchEvents)
        precondition(production.timeoutIntervalForRequest == 90 && production.timeoutIntervalForResource == 120)
        for path in ["/api/ios/voice", "/api/ios/onboarding/persona", "/api/ios/onboarding/video-analysis", "/api/ios/detect-cat-face"] {
            precondition(NekoGenerationTransport.handles(path))
        }
        for path in ["/api/ios/auth/phone-otp", "/api/ios/cloud/account/delete", "/api/ios/cloud/cat-profile", "/api/ios/cloud/voices", "/api/ios/cloud/media-upload"] {
            precondition(!NekoGenerationTransport.handles(path), "Mutations must not use generation transport")
        }

        // Start once, simulate background/foreground repeatedly, and deliver
        // chunks only later (as URLSession does when the app is resumed).
        let voiceRequest = request("/voice")
        let voice = Task { try await transport.data(for: voiceRequest, trace: nil) }
        try await waitForStart("/voice")
        let files = try FileManager.default.contentsOfDirectory(at: bodies, includingPropertiesForKeys: nil)
        precondition(files.count == 1)
        let body = try Data(contentsOf: files[0])
        precondition(body == voiceRequest.httpBody)
        let attributes = try FileManager.default.attributesOfItem(atPath: files[0].path)
        precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let orphan = bodies.appendingPathComponent(UUID().uuidString + ".json")
        let unrelated = bodies.appendingPathComponent("keep.txt")
        try Data("orphan".utf8).write(to: orphan)
        try Data("keep".utf8).write(to: unrelated)
        transport.reconnect()
        for _ in 0..<300 {
            if !FileManager.default.fileExists(atPath: orphan.path) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        precondition(!FileManager.default.fileExists(atPath: orphan.path))
        precondition(FileManager.default.fileExists(atPath: files[0].path), "Cleanup removed an active upload")
        precondition(FileManager.default.fileExists(atPath: unrelated.path), "Cleanup removed an unrelated file")
        try FileManager.default.removeItem(at: unrelated)
        gate.active = false
        transport.resumeQueuedRequests()
        gate.active = true
        transport.resumeQueuedRequests()
        transport.resumeQueuedRequests()
        let protocolRequest = ControlledProtocol.take("/voice")
        precondition(protocolRequest.request.httpMethod == "POST")
        precondition(protocolRequest.request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        precondition(protocolRequest.request.value(forHTTPHeaderField: "X-Neko-Request-ID") == "test-request-id")
        let response = HTTPURLResponse(url: voiceRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        protocolRequest.client!.urlProtocol(protocolRequest, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in ["{\"result\":", "\"真实结果\"}"] { protocolRequest.client!.urlProtocol(protocolRequest, didLoad: Data(chunk.utf8)) }
        protocolRequest.client!.urlProtocolDidFinishLoading(protocolRequest)
        let result = try await voice.value
        precondition(String(decoding: result.0, as: UTF8.self) == "{\"result\":\"真实结果\"}")
        precondition(ControlledProtocol.count("/voice") == 1, "Foreground must not regenerate")
        let filesAfterSuccess = try FileManager.default.contentsOfDirectory(atPath: bodies.path)
        precondition(filesAfterSuccess.isEmpty)

        // A follow-up persona request while backgrounded must wait for foreground.
        gate.active = false
        let persona = Task { try await transport.data(for: request("/persona"), trace: nil) }
        try await Task.sleep(nanoseconds: 30_000_000)
        precondition(ControlledProtocol.count("/persona") == 0)
        gate.active = true
        transport.resumeQueuedRequests()
        try await waitForStart("/persona")
        ControlledProtocol.complete("/persona")
        _ = try await persona.value
        precondition(ControlledProtocol.count("/persona") == 1)

        // Independent concurrent videos can complete out of order.
        let clip1 = Task { try await transport.data(for: request("/clip1"), trace: nil) }
        let clip2 = Task { try await transport.data(for: request("/clip2"), trace: nil) }
        try await waitForStart("/clip1")
        try await waitForStart("/clip2")
        ControlledProtocol.complete("/clip2", chunks: [Data("second".utf8)])
        ControlledProtocol.complete("/clip1", chunks: [Data("first".utf8)])
        let firstClip = try await clip1.value
        let secondClip = try await clip2.value
        precondition(firstClip.0 == Data("first".utf8))
        precondition(secondClip.0 == Data("second".utf8))

        gate.active = false
        let cancelledBeforeStart = Task { try await transport.data(for: request("/cancel-queued"), trace: nil) }
        try await Task.sleep(nanoseconds: 30_000_000)
        cancelledBeforeStart.cancel()
        await expectCancellation(cancelledBeforeStart)
        gate.active = true
        transport.resumeQueuedRequests()
        precondition(ControlledProtocol.count("/cancel-queued") == 0)
        let alreadyCancelled = Task { try await transport.data(for: request("/cancel-before-registration"), trace: nil) }
        alreadyCancelled.cancel()
        await expectCancellation(alreadyCancelled)
        precondition(ControlledProtocol.count("/cancel-before-registration") == 0)
        let cancelled = Task { try await transport.data(for: request("/cancel-running"), trace: nil) }
        try await waitForStart("/cancel-running")
        cancelled.cancel()
        await expectCancellation(cancelled)
        _ = ControlledProtocol.take("/cancel-running")

        // Real failures remain failures; transport must never retry the model or
        // turn a server error into a fabricated successful generation.
        let failed = Task { try await transport.data(for: request("/network-error"), trace: nil) }
        try await waitForStart("/network-error")
        ControlledProtocol.fail("/network-error")
        do { _ = try await failed.value; preconditionFailure("Network error lost") }
        catch { precondition((error as? URLError)?.code == .networkConnectionLost) }
        precondition(ControlledProtocol.count("/network-error") == 1)
        let serverError = Task { try await transport.data(for: request("/server-error"), trace: nil) }
        try await waitForStart("/server-error")
        ControlledProtocol.complete("/server-error", status: 503)
        let serverResult = try await serverError.value
        precondition((serverResult.1 as? HTTPURLResponse)?.statusCode == 503)

        let oversized = Task { try await transport.data(for: request("/oversized"), trace: nil) }
        try await waitForStart("/oversized")
        ControlledProtocol.complete("/oversized", chunks: [Data(repeating: 1, count: 1025)])
        do { _ = try await oversized.value; preconditionFailure("Oversized response accepted") }
        catch { precondition((error as? URLError)?.code == .dataLengthExceedsMaximum) }
        let filesAfterFailures = try FileManager.default.contentsOfDirectory(atPath: bodies.path)
        precondition(filesAfterFailures.isEmpty)

        // Failure before creating the URLSession task must also finish the waiter.
        let blockedDirectory = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: blockedDirectory)
        let broken = NekoGenerationTransport(configuration: config, bodyDirectory: blockedDirectory, canStart: { true })
        do { _ = try await broken.data(for: request("/disk-error"), trace: nil); preconditionFailure("Disk error lost") }
        catch { precondition(ControlledProtocol.count("/disk-error") == 0) }
        print("PASS: background configuration, scoped routing, same-request resume, response chunks, protected body cleanup, foreground gating, concurrency, cancellation, network/HTTP/disk errors, response size bound")
    }
}
