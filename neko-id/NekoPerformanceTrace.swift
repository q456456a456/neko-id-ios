import Foundation
import OSLog

/// Local diagnostics only: no image data, prompts, answers, URLs, tokens or error text.
nonisolated struct NekoPerformanceTrace {
    private static let logger = Logger(subsystem: "uk.nekoid.app", category: "Performance")
    let id = UUID().uuidString.lowercased()
    let operation: String
    let parentFlowID: String?
    private let startedAt = ProcessInfo.processInfo.systemUptime

    init(_ operation: String, flowID: String? = nil) {
        self.operation = operation
        self.parentFlowID = flowID
    }

    var flowID: String { parentFlowID ?? id }
    var elapsedMs: Int { Self.milliseconds(since: startedAt) }

    static func milliseconds(since start: TimeInterval) -> Int {
        max(0, Int((ProcessInfo.processInfo.systemUptime - start) * 1000))
    }

    func log(_ event: String, _ metrics: [String: Any] = [:]) {
        var fields = metrics
        fields["event"] = event
        fields["operation"] = operation
        fields["requestId"] = id
        fields["flowId"] = flowID
        fields["elapsedMs"] = elapsedMs
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
              let message = String(data: data, encoding: .utf8) else { return }
        Self.logger.info("NEKO perf \(message, privacy: .public)")
    }

    func measure<T>(_ stage: String, operation: () throws -> T) rethrows -> T {
        let started = ProcessInfo.processInfo.systemUptime
        var outcome = "error"
        defer { log("client_span_end", ["stage": stage, "durationMs": Self.milliseconds(since: started), "outcome": outcome]) }
        let result = try operation()
        outcome = "ok"
        return result
    }
}

/// URLSession's own measurements distinguish slow DNS/TLS from waiting for the
/// server. Reused connections have no DNS/connect sample; report -1, not zero.
nonisolated final class NekoURLSessionMetrics: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let trace: NekoPerformanceTrace

    init(trace: NekoPerformanceTrace) { self.trace = trace }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        func duration(_ start: Date?, _ end: Date?) -> Int {
            guard let start, let end else { return -1 }
            return max(0, Int(end.timeIntervalSince(start) * 1000))
        }
        for (index, transaction) in metrics.transactionMetrics.prefix(8).enumerated() {
            trace.log("client_transport", [
                "transactionIndex": index, "transactionCount": metrics.transactionMetrics.count,
                "dnsMs": duration(transaction.domainLookupStartDate, transaction.domainLookupEndDate),
                "connectMs": duration(transaction.connectStartDate, transaction.connectEndDate),
                "tlsMs": duration(transaction.secureConnectionStartDate, transaction.secureConnectionEndDate),
                "uploadMs": duration(transaction.requestStartDate, transaction.requestEndDate),
                "waitResponseMs": duration(transaction.requestEndDate, transaction.responseStartDate),
                "downloadMs": duration(transaction.responseStartDate, transaction.responseEndDate),
                "connectionReused": transaction.isReusedConnection,
                "proxyConnection": transaction.isProxyConnection,
                "resourceFetchType": transaction.resourceFetchType.rawValue,
            ])
        }
    }
}
