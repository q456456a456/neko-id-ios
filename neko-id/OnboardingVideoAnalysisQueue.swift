import Foundation

/// Session-local, deduplicated work shared by video prefetch and final generation.
/// A cancelled request occupies its slot until it actually exits, so replacement
/// videos cannot temporarily push the number of active requests over the limit.
@MainActor
final class OnboardingVideoAnalysisQueue<Key: Hashable & Sendable, Value> {
    private final class Entry {
        let token = UUID()
        var operation: (@MainActor () async throws -> Value)?
        var completion: (@MainActor (Result<Value, Error>) -> Void)?
        var result: Result<Value, Error>?
        var waiters: [UUID: CheckedContinuation<Value, Error>] = [:]

        init(
            operation: @escaping @MainActor () async throws -> Value,
            completion: @escaping @MainActor (Result<Value, Error>) -> Void
        ) {
            self.operation = operation
            self.completion = completion
        }
    }

    private let concurrencyLimit: Int
    private var entries: [Key: Entry] = [:]
    private var pending: [Key] = []
    private var running: [UUID: Task<Void, Never>] = [:]

    init(concurrencyLimit: Int = 2) {
        precondition(concurrencyLimit > 0)
        self.concurrencyLimit = concurrencyLimit
    }

    func contains(_ key: Key) -> Bool {
        entries[key] != nil
    }

    func hasFailed(_ key: Key) -> Bool {
        guard let result = entries[key]?.result else { return false }
        if case .failure = result { return true }
        return false
    }

    func enqueue(
        _ key: Key,
        operation: @escaping @MainActor () async throws -> Value,
        completion: @escaping @MainActor (Result<Value, Error>) -> Void
    ) {
        guard entries[key] == nil else { return }
        entries[key] = Entry(operation: operation, completion: completion)
        pending.append(key)
        startAvailableWork()
    }

    func retainOnly(_ keys: Set<Key>) {
        // Remove the entire obsolete batch before allowing any queued work to run.
        for key in Array(entries.keys) where !keys.contains(key) {
            removeEntry(key)
        }
        startAvailableWork()
    }

    func remove(_ key: Key) {
        removeEntry(key)
        startAvailableWork()
    }

    /// Keeps completed observations for reappearance, but stops all pending work.
    func cancelPendingWork() {
        for key in Array(entries.keys) where entries[key]?.result == nil {
            removeEntry(key)
        }
    }

    func value(for key: Key) async throws -> Value {
        let trace = NekoPerformanceTrace("video_wait")
        var cached = false
        var outcome = "error"
        defer { trace.log("client_video_wait_end", ["cacheHit": cached, "outcome": outcome]) }
        try Task.checkCancellation()
        guard let entry = entries[key] else { throw CancellationError() }
        if let result = entry.result {
            cached = true
            let value = try result.get()
            outcome = "ok"
            return value
        }

        let waiterID = UUID()
        let token = entry.token
        // Cancelling the result-page waiter must not cancel shared prefetch work:
        // returning to the quiz should let those same requests finish in background.
        let value: Value = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    entry.waiters[waiterID] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let entry = self?.entries[key], entry.token == token else { return }
                entry.waiters.removeValue(forKey: waiterID)?.resume(throwing: CancellationError())
            }
        }
        outcome = "ok"
        return value
    }

    private func removeEntry(_ key: Key) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        pending.removeAll { $0 == key }
        running[entry.token]?.cancel()
        for continuation in entry.waiters.values {
            continuation.resume(throwing: CancellationError())
        }
    }

    private func startAvailableWork() {
        while running.count < concurrencyLimit, !pending.isEmpty {
            let key = pending.removeFirst()
            guard let entry = entries[key], let operation = entry.operation else { continue }
            entry.operation = nil
            let token = entry.token
            running[token] = Task { @MainActor [weak self] in
                let result: Result<Value, Error>
                do {
                    try Task.checkCancellation()
                    let value = try await operation()
                    try Task.checkCancellation()
                    result = .success(value)
                } catch {
                    result = .failure(error)
                }
                self?.finish(key, token: token, result: result)
            }
        }
    }

    private func finish(_ key: Key, token: UUID, result: Result<Value, Error>) {
        running.removeValue(forKey: token)
        if let entry = entries[key], entry.token == token {
            entry.result = result
            let completion = entry.completion
            entry.completion = nil
            completion?(result)
            for continuation in entry.waiters.values {
                continuation.resume(with: result)
            }
            entry.waiters.removeAll()
        }
        startAvailableWork()
    }
}

/// Quiz answers and the number of other clips deliberately do not affect video
/// observations. Changing cat identity/basic facts does invalidate cached work.
nonisolated struct OnboardingVideoAnalysisKey: Hashable, Sendable {
    let clipID: UUID
    let name: String
    let gender: String
    let ageStage: String
}
