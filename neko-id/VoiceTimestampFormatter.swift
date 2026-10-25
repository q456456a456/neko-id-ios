import Foundation

enum VoiceTimestampFormatter {
    /// API timestamps are Unix milliseconds. Never reuse persisted relative
    /// copy such as "刚刚": it becomes incorrect as soon as the record ages.
    static func timeLabel(
        createdAt: Int64?,
        legacyTime: String,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        stackedYear: Bool = false
    ) -> String {
        if let createdAt, createdAt > 0 {
            let date = Date(timeIntervalSince1970: Double(createdAt) / 1_000)
            let elapsed = now.timeIntervalSince(date)

            // Tolerate small device/server clock differences, but do not label
            // a clearly future-dated record as a recent publication.
            if elapsed >= -300 {
                let age = max(elapsed, 0)
                if age < 5 * 60 { return "刚刚" }
                if age < 60 * 60 { return "\(Int(age / 60))分钟前" }
                if age < 24 * 60 * 60 { return "\(Int(age / 3_600))小时前" }
                if age < 7 * 24 * 60 * 60 { return "\(Int(age / 86_400))天前" }
            }

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = components.year, let month = components.month, let day = components.day else {
                return "--:--"
            }
            let monthDay = String(format: "%02d-%02d", month, day)
            guard year != calendar.component(.year, from: now) else { return monthDay }
            let separator = stackedYear ? "\n" : "-"
            return "\(year)\(separator)\(monthDay)"
        }

        // Some older records only have a literal clock time. Preserve that,
        // but do not invent a publication time when no timestamp is available.
        let text = legacyTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2,
           (1...2).contains(parts[0].count), parts[1].count == 2,
           parts.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
           let hour = Int(parts[0]), (0...23).contains(hour),
           let minute = Int(parts[1]), (0...59).contains(minute) {
            return String(format: "%02d:%02d", hour, minute)
        }
        return "--:--"
    }
}
