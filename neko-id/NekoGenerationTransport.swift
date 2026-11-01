import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// AI POST requests can spend most of their lifetime waiting for the response.
/// A default-session data task is suspended with the app. File-backed uploads in
/// a background session keep the SAME request alive in the system networking
/// process, including delivery of its JSON response. Never replay a generation.
@MainActor
final class NekoGenerationTransport: NSObject, URLSessionDataDelegate {
    static let sessionIdentifier = "uk.nekoid.app.generation.v1"
    static let shared = NekoGenerationTransport(configuration: backgroundConfiguration(
        requestTimeout: AppConfig.serverRequestTimeout,
        resourceTimeout: AppConfig.serverResourceTimeout
    ))

    static func handles(_ path: String) -> Bool {
        ["/api/ios/onboarding/persona", "/api/ios/onboarding/video-analysis",
         "/api/ios/detect-cat-face", "/api/ios/voice"].contains(path)
    }

    static func backgroundConfiguration(requestTimeout: TimeInterval, resourceTimeout: TimeInterval) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        return configuration
    }

    private final class PendingRequest {
        var request: URLRequest?
        let continuation: CheckedContinuation<(Data, URLResponse), Error>
        let trace: NekoPerformanceTrace?
        var task: URLSessionUploadTask?
        var bodyURL: URL?
        var data = Data()

        init(request: URLRequest, continuation: CheckedContinuation<(Data, URLResponse), Error>, trace: NekoPerformanceTrace?) {
            self.request = request
            self.continuation = continuation
            self.trace = trace
        }
    }

    private let configuration: URLSessionConfiguration
    private let bodyDirectory: URL
    private let canStart: @MainActor () -> Bool
    private let responseLimit: Int
    private var pending: [UUID: PendingRequest] = [:]
    private var reconnected = false
    private var backgroundCompletionHandler: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    private lazy var session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

    // The configuration and gate are injectable so regression checks need no
    // production credentials, AI calls, or real SMS/database mutations.
    init(configuration: URLSessionConfiguration, bodyDirectory: URL? = nil,
         responseLimit: Int = 4 * 1024 * 1024,
         canStart: @escaping @MainActor () -> Bool = NekoGenerationTransport.isForeground) {
        self.configuration = configuration
        self.bodyDirectory = bodyDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NekoGenerationRequests", isDirectory: true)
        self.responseLimit = responseLimit
        self.canStart = canStart
        super.init()
#if canImport(UIKit)
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.logLifecycle("client_generation_background") }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.logLifecycle("client_generation_foreground")
                self?.resumeQueuedRequests()
            }
        })
#endif
    }

    private static func isForeground() -> Bool {
#if canImport(UIKit)
        UIApplication.shared.applicationState != .background
#else
        true
#endif
    }

    /// Reattach to the single system session on launch (including OS wakeups).
    func reconnect() {
        guard !reconnected else { return }
        reconnected = true
        session.getAllTasks { tasks in
            let activeIDs = Set(tasks.compactMap { $0.taskDescription }.compactMap(UUID.init(uuidString:)))
            DispatchQueue.main.async {
                // Remove files left by an interrupted write/force quit, but never
                // a file still owned by this process or by a system transfer.
                let retained = activeIDs.union(self.pending.keys)
                let files = (try? FileManager.default.contentsOfDirectory(at: self.bodyDirectory, includingPropertiesForKeys: nil)) ?? []
                for file in files where file.pathExtension == "json" {
                    guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), !retained.contains(id) else { continue }
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    func handleBackgroundEvents(completionHandler: @escaping () -> Void) {
        backgroundCompletionHandler = completionHandler
        reconnect()
    }

    func data(for request: URLRequest, trace: NekoPerformanceTrace?) async throws -> (Data, URLResponse) {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pending[id] = PendingRequest(request: request, continuation: continuation, trace: trace)
                if canStart() {
                    start(id)
                } else {
                    // Starting a new background task while already backgrounded
                    // makes iOS treat it as discretionary, delaying later video
                    // analysis/persona stages. Start those on foreground instead.
                    trace?.log("client_generation_wait_foreground")
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    func resumeQueuedRequests() {
        guard canStart() else { return }
        for id in Array(pending.keys) where pending[id]?.task == nil { start(id) }
    }

    private func start(_ id: UUID) {
        guard let entry = pending[id], entry.task == nil, var request = entry.request else { return }
        do {
            try Task.checkCancellation()
            guard let body = request.httpBody else { throw URLError(.badURL) }
            try FileManager.default.createDirectory(at: bodyDirectory, withIntermediateDirectories: true)
            let bodyURL = bodyDirectory.appendingPathComponent(id.uuidString + ".json")
            entry.bodyURL = bodyURL
#if canImport(UIKit)
            // The system must still be able to read the upload after screen lock.
            try body.write(to: bodyURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
#else
            try body.write(to: bodyURL, options: .atomic)
#endif
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: bodyURL.path)
            request.httpBody = nil
            let task = session.uploadTask(with: request, fromFile: bodyURL)
            task.taskDescription = id.uuidString
            task.priority = URLSessionTask.highPriority
            task.countOfBytesClientExpectsToSend = Int64(body.count)
            task.countOfBytesClientExpectsToReceive = 64 * 1024
            entry.task = task
            entry.request = nil
            entry.trace?.log("client_generation_transfer_start", ["transport": "background_upload", "requestBytes": body.count])
            task.resume()
        } catch {
            finish(id, result: .failure(error))
        }
    }

    private func cancel(_ id: UUID) {
        guard let entry = pending[id] else { return }
        entry.trace?.log("client_generation_cancelled")
        entry.task?.cancel()
        finish(id, result: .failure(CancellationError()))
    }

    private func finish(_ id: UUID, result: Result<(Data, URLResponse), Error>) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        if let url = entry.bodyURL { try? FileManager.default.removeItem(at: url) }
        entry.continuation.resume(with: result)
    }

    private func logLifecycle(_ event: String) {
        for entry in pending.values {
            entry.trace?.log(event, ["activeRequests": pending.count, "started": entry.task != nil])
        }
    }

    // URLSession delivers delegate events serially. Enqueue them on the main
    // queue in that same order; independent unstructured Tasks could allow the
    // completion to overtake the final response chunk.
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let rawID = dataTask.taskDescription, let id = UUID(uuidString: rawID) else { return }
        DispatchQueue.main.async {
            guard let entry = self.pending[id] else { return }
            guard data.count <= self.responseLimit - entry.data.count else {
                entry.task?.cancel()
                self.finish(id, result: .failure(URLError(.dataLengthExceedsMaximum)))
                return
            }
            entry.data.append(data)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let rawID = task.taskDescription, let id = UUID(uuidString: rawID) else { return }
        let response = task.response
        DispatchQueue.main.async {
            guard let entry = self.pending[id] else {
                // A previous process may have been killed. Its view/continuation
                // no longer exists; only clean up our UUID-named request file.
                try? FileManager.default.removeItem(at: self.bodyDirectory.appendingPathComponent(id.uuidString + ".json"))
                return
            }
            entry.trace?.log("client_generation_transfer_end", ["urlErrorCode": (error as? URLError)?.code.rawValue ?? 0, "responseBytes": entry.data.count])
            if let error {
                self.finish(id, result: .failure(error))
            } else if let response {
                self.finish(id, result: .success((entry.data, response)))
            } else {
                self.finish(id, result: .failure(URLError(.badServerResponse)))
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let rawID = task.taskDescription, let id = UUID(uuidString: rawID) else { return }
        DispatchQueue.main.async {
            guard let trace = self.pending[id]?.trace else { return }
            NekoURLSessionMetrics(trace: trace).urlSession(session, task: task, didFinishCollecting: metrics)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            let completion = self.backgroundCompletionHandler
            self.backgroundCompletionHandler = nil
            completion?()
        }
    }
}

#if canImport(UIKit)
final class NekoAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NekoGenerationTransport.shared.reconnect()
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == NekoGenerationTransport.sessionIdentifier else {
            completionHandler()
            return
        }
        NekoGenerationTransport.shared.handleBackgroundEvents(completionHandler: completionHandler)
    }
}
#endif
