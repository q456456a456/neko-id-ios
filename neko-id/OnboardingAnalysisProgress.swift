import Foundation

/// A visual estimate, not server-reported progress. Only a real response completes it.
struct OnboardingAnalysisProgress {
    let estimatedDuration: TimeInterval

    init(pendingVideoCount: Int) {
        // Budget for the report's model calls and each uncached video observation.
        estimatedDuration = 45 + Double(max(0, pendingVideoCount)) * 20
    }

    func value(after elapsed: TimeInterval) -> Double {
        let elapsed = max(0, elapsed)
        let steadyProgress = 0.8
        let waitingProgress = 0.19

        if elapsed <= estimatedDuration {
            return steadyProgress * elapsed / estimatedDuration
        }

        // Continue moving after the estimate, without a hard stop at 82%.
        // This tail has the same slope as the linear portion at the join.
        let overtime = elapsed - estimatedDuration
        let tailDuration = estimatedDuration * waitingProgress / steadyProgress
        return steadyProgress + waitingProgress * overtime / (overtime + tailDuration)
    }
}
