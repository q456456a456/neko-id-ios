import Foundation

// swiftc neko-id/OnboardingVideoAnalysisQueue.swift Tests/OnboardingVideoAnalysisQueueTests.swift -o /tmp/neko-video-queue-tests
// /tmp/neko-video-queue-tests
@MainActor
private final class ControlledAnalysis {
    private(set) var started: [String] = []
    private(set) var activeCount = 0
    private(set) var peakCount = 0
    private var requests: [String: CheckedContinuation<String, Error>] = [:]

    // Intentionally ignores cancellation until released, like a slow transport.
    func perform(_ name: String) async throws -> String {
        started.append(name)
        activeCount += 1
        peakCount = max(peakCount, activeCount)
        defer { activeCount -= 1 }
        return try await withCheckedThrowingContinuation { requests[name] = $0 }
    }

    func finish(_ name: String, result: Result<String, Error>? = nil) {
        guard let continuation = requests.removeValue(forKey: name) else {
            preconditionFailure("Request not running: \(name)")
        }
        continuation.resume(with: result ?? .success(name))
    }
}

@main
enum OnboardingVideoAnalysisQueueTests {
    @MainActor
    static func settle(until predicate: () -> Bool) async {
        for _ in 0..<5_000 {
            if predicate() { return }
            await Task.yield()
        }
        preconditionFailure("Timed out waiting for queue state")
    }

    @MainActor
    static func expectCancellation(_ task: Task<String, Error>) async {
        switch await task.result {
        case .success:
            preconditionFailure("Expected cancellation")
        case .failure(let error):
            precondition(error is CancellationError)
        }
    }

    @MainActor
    static func main() async throws {
        try await boundedParallelismAndReuse()
        try await cancellationAndReplacement()
        try await waiterCancellationDoesNotCancelPrefetch()
        try await failureAndExplicitRetry()
        try await leavingAndReappearing()
        try await profileChangeInvalidatesObservations()
        print("PASS: two-request limit, early prefetch, in-flight/completed reuse, result order, deletion, replacement, waiter cancellation, failures, lifecycle and profile invalidation")
    }

    @MainActor
    static func boundedParallelismAndReuse() async throws {
        let queue = OnboardingVideoAnalysisQueue<Int, String>()
        let service = ControlledAnalysis()
        var completed: [Int: String] = [:]
        for key in 1...3 {
            queue.enqueue(key) {
                try await service.perform("clip\(key)")
            } completion: { completed[key] = try? $0.get() }
        }
        // Starts before anyone requests a final result (while the quiz is open).
        await settle { service.started.count == 2 }
        precondition(service.started == ["clip1", "clip2"])
        queue.enqueue(1) { preconditionFailure("Duplicate in-flight call") } completion: { _ in }
        let generation = Task { @MainActor () throws -> [String] in
            var values: [String] = []
            for key in 1...3 { values.append(try await queue.value(for: key)) }
            return values
        }
        // Out-of-order responses free a slot, but results retain selection order.
        service.finish("clip2")
        await settle { service.started.count == 3 }
        service.finish("clip3")
        service.finish("clip1")
        let values = try await generation.value
        precondition(values == ["clip1", "clip2", "clip3"])
        precondition(service.peakCount == 2 && completed.count == 3)
        queue.enqueue(2) { preconditionFailure("Duplicate completed call") } completion: { _ in }
        let cached = try await queue.value(for: 2)
        precondition(cached == "clip2" && service.started.count == 3)
    }

    @MainActor
    static func cancellationAndReplacement() async throws {
        let queue = OnboardingVideoAnalysisQueue<Int, String>()
        let service = ControlledAnalysis()
        var staleCompletions = 0
        queue.enqueue(1) { try await service.perform("removed") } completion: { _ in staleCompletions += 1 }
        queue.enqueue(2) { try await service.perform("kept") } completion: { _ in }
        queue.enqueue(3) { preconditionFailure("Deleted queued clip must not start") } completion: { _ in staleCompletions += 1 }
        await settle { service.started.count == 2 }
        let deletedWaiter = Task { @MainActor in try await queue.value(for: 1) }
        await Task.yield()
        queue.retainOnly([2])
        await expectCancellation(deletedWaiter)
        // Reusing the same key must not let a late old result overwrite its replacement.
        queue.enqueue(1) { try await service.perform("replacement") } completion: { _ in }
        for _ in 0..<20 { await Task.yield() }
        precondition(service.started.count == 2, "Cancelled transport still occupies a slot")
        service.finish("removed")
        await settle { service.started.contains("replacement") }
        service.finish("replacement")
        service.finish("kept")
        let value = try await queue.value(for: 1)
        precondition(value == "replacement" && staleCompletions == 0 && service.peakCount == 2)
    }

    @MainActor
    static func waiterCancellationDoesNotCancelPrefetch() async throws {
        let queue = OnboardingVideoAnalysisQueue<Int, String>()
        let service = ControlledAnalysis()
        queue.enqueue(1) { try await service.perform("shared") } completion: { _ in }
        await settle { service.started.count == 1 }
        let cancelledWaiter = Task { @MainActor in try await queue.value(for: 1) }
        let nextGeneration = Task { @MainActor in try await queue.value(for: 1) }
        await Task.yield()
        cancelledWaiter.cancel()
        await expectCancellation(cancelledWaiter)
        precondition(service.activeCount == 1, "Going back to the quiz should retain prefetch")
        service.finish("shared")
        let value = try await nextGeneration.value
        precondition(value == "shared" && service.started.count == 1)

        let alreadyCancelled = Task { @MainActor in try await queue.value(for: 1) }
        alreadyCancelled.cancel()
        await expectCancellation(alreadyCancelled)
    }

    @MainActor
    static func failureAndExplicitRetry() async throws {
        enum TestFailure: Error { case unavailable }
        let queue = OnboardingVideoAnalysisQueue<Int, String>()
        let service = ControlledAnalysis()
        var failureReported = false
        queue.enqueue(1) { try await service.perform("first") } completion: {
            if case .failure = $0 { failureReported = true }
        }
        await settle { service.started.count == 1 }
        service.finish("first", result: .failure(TestFailure.unavailable))
        do {
            _ = try await queue.value(for: 1)
            preconditionFailure("A failed request must never produce a fake observation")
        } catch is TestFailure { }
        precondition(queue.hasFailed(1) && failureReported)
        queue.enqueue(1) { preconditionFailure("No unbounded automatic retries") } completion: { _ in }
        // Retry an already-failed prefetch once when final generation is requested.
        queue.remove(1)
        queue.enqueue(1) { try await service.perform("retry") } completion: { _ in }
        await settle { service.started.count == 2 }
        service.finish("retry")
        let value = try await queue.value(for: 1)
        precondition(value == "retry" && !queue.hasFailed(1))
    }

    @MainActor
    static func leavingAndReappearing() async throws {
        let queue = OnboardingVideoAnalysisQueue<Int, String>()
        let service = ControlledAnalysis()
        queue.enqueue(0) { "cached" } completion: { _ in }
        _ = try await queue.value(for: 0)
        var staleCompletions = 0
        for key in 1...3 {
            queue.enqueue(key) { try await service.perform("old\(key)") } completion: { _ in staleCompletions += 1 }
        }
        await settle { service.started.count == 2 }
        queue.cancelPendingWork()
        precondition(queue.contains(0) && !queue.contains(1) && !queue.contains(2) && !queue.contains(3))
        queue.enqueue(1) { try await service.perform("resumed") } completion: { _ in }
        service.finish("old1")
        service.finish("old2")
        await settle { service.started.contains("resumed") }
        precondition(!service.started.contains("old3"))
        service.finish("resumed")
        let value = try await queue.value(for: 1)
        precondition(value == "resumed" && staleCompletions == 0 && service.peakCount == 2)
        let cached = try await queue.value(for: 0)
        precondition(cached == "cached")
    }

    @MainActor
    static func profileChangeInvalidatesObservations() async throws {
        let queue = OnboardingVideoAnalysisQueue<OnboardingVideoAnalysisKey, String>()
        let id = UUID()
        let original = OnboardingVideoAnalysisKey(clipID: id, name: "丸子", gender: "小公猫", ageStage: "青年猫")
        let renamed = OnboardingVideoAnalysisKey(clipID: id, name: "六六", gender: "小公猫", ageStage: "青年猫")
        let changedAge = OnboardingVideoAnalysisKey(clipID: id, name: "丸子", gender: "小公猫", ageStage: "成熟猫")
        let changedGender = OnboardingVideoAnalysisKey(clipID: id, name: "丸子", gender: "小母猫", ageStage: "青年猫")
        precondition(Set([original, renamed, changedAge, changedGender]).count == 4)
        queue.enqueue(original) { "old cat" } completion: { _ in }
        _ = try await queue.value(for: original)
        queue.retainOnly([renamed])
        precondition(!queue.contains(original))
        queue.enqueue(renamed) { "new cat" } completion: { _ in }
        let value = try await queue.value(for: renamed)
        precondition(value == "new cat")
    }
}
