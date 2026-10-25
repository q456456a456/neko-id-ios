import Foundation

// Run from the repository root:
// swiftc neko-id/OnboardingAnalysisProgress.swift Tests/OnboardingAnalysisProgressTests.swift -o /tmp/neko-progress-tests
// /tmp/neko-progress-tests
@main
enum OnboardingAnalysisProgressTests {
    @MainActor
    static func main() {
        let reportOnly = OnboardingAnalysisProgress(pendingVideoCount: 0)
        precondition(reportOnly.value(after: -1) == 0)
        precondition(reportOnly.value(after: 0) == 0)
        precondition(reportOnly.value(after: 3) < 0.1, "Must not rush to 82% in three seconds")
        precondition(OnboardingAnalysisProgress(pendingVideoCount: -1).estimatedDuration == reportOnly.estimatedDuration)

        for videoCount in 0...3 {
            let estimate = OnboardingAnalysisProgress(pendingVideoCount: videoCount)
            precondition(estimate.estimatedDuration == 45 + Double(videoCount) * 20)

            // Equal time intervals have equal progress increments before the tail.
            for fraction in [0.25, 0.5, 0.75, 1.0] {
                let actual = estimate.value(after: fraction * estimate.estimatedDuration)
                precondition(abs(actual - fraction * 0.8) < 0.000_001)
            }

            // Includes long responses, beyond the normal network timeout.
            var previous = estimate.value(after: 0)
            for tick in 1...6000 {
                let current = estimate.value(after: Double(tick) / 10)
                precondition(current > previous, "Progress must keep moving, including past 82%")
                precondition(current < 0.99, "Only a real response may complete the progress")
                previous = current
            }

            // No jump or abrupt slope change where the linear portion meets the tail.
            let boundary = estimate.estimatedDuration
            let epsilon = 0.001
            let before = estimate.value(after: boundary - epsilon)
            let at = estimate.value(after: boundary)
            let after = estimate.value(after: boundary + epsilon)
            precondition(abs((at - before) - (after - at)) < 0.000_001)
        }

        precondition(
            OnboardingAnalysisProgress(pendingVideoCount: 3).value(after: 30)
                < reportOnly.value(after: 30),
            "Uncached videos must get additional time instead of an early plateau"
        )
        print("PASS: progress pacing, 0–3 videos, continuity, monotonicity and completion ceiling")
    }
}
