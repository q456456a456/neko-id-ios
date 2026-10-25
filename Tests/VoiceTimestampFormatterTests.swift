import Foundation

// Run from the repository root:
// swiftc neko-id/VoiceTimestampFormatter.swift Tests/VoiceTimestampFormatterTests.swift -o /tmp/neko-voice-time-tests
// /tmp/neko-voice-time-tests
@main
enum VoiceTimestampFormatterTests {
    static func timestamp(_ iso8601: String) -> Int64 {
        Int64(ISO8601DateFormatter().date(from: iso8601)!.timeIntervalSince1970 * 1_000)
    }

    static func main() {
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        let utc = TimeZone(secondsFromGMT: 0)!
        let nowTimestamp = timestamp("2026-10-25T07:04:00Z")
        let now = Date(timeIntervalSince1970: Double(nowTimestamp) / 1_000)

        func label(_ time: Int64?, _ legacy: String = "刚刚", zone: TimeZone? = nil, stackedYear: Bool = false) -> String {
            VoiceTimestampFormatter.timeLabel(
                createdAt: time, legacyTime: legacy, now: now,
                timeZone: zone ?? shanghai, stackedYear: stackedYear
            )
        }

        // Exact transitions, including the last millisecond before each boundary.
        let cases: [(ageMilliseconds: Int64, expected: String)] = [
            (0, "刚刚"), (299_999, "刚刚"), (300_000, "5分钟前"),
            (359_999, "5分钟前"), (360_000, "6分钟前"),
            (3_599_999, "59分钟前"), (3_600_000, "1小时前"),
            (86_399_999, "23小时前"), (86_400_000, "1天前"),
            (172_800_000, "2天前"), (604_799_999, "6天前"),
            (604_800_000, "10-18"),
        ]
        for test in cases {
            precondition(label(nowTimestamp - test.ageMilliseconds) == test.expected, "Incorrect age boundary: \(test.ageMilliseconds)")
        }

        // Persisted "刚刚" or a stale clock time never overrides a valid timestamp.
        let savedAt = timestamp("2026-09-13T07:04:00Z")
        precondition(label(savedAt) == "09-13")
        precondition(label(savedAt, "09:00") == "09-13")
        precondition(label(nowTimestamp - 3_600_000, zone: utc) == "1小时前")

        // Dates follow the device time zone and include the year across years.
        let newYear = timestamp("2025-12-31T16:00:00Z")
        precondition(label(newYear) == "01-01")
        precondition(label(newYear, zone: utc) == "2025-12-31")
        precondition(label(newYear, zone: utc, stackedYear: true) == "2025\n12-31")

        // Relative days are elapsed 24-hour periods, not midnight/DST crossings.
        let beforeMidnight = timestamp("2026-10-24T15:59:00Z")
        let afterMidnight = Date(timeIntervalSince1970: Double(beforeMidnight + 120_000) / 1_000)
        precondition(VoiceTimestampFormatter.timeLabel(createdAt: beforeMidnight, legacyTime: "", now: afterMidnight, timeZone: shanghai) == "刚刚")
        let newYork = TimeZone(identifier: "America/New_York")!
        let beforeDST = timestamp("2026-03-08T06:30:00Z")
        let afterDST = Date(timeIntervalSince1970: Double(beforeDST + 3_600_000) / 1_000)
        precondition(VoiceTimestampFormatter.timeLabel(createdAt: beforeDST, legacyTime: "", now: afterDST, timeZone: newYork) == "1小时前")

        // Recompute from the render time, so a page left open never freezes at "刚刚".
        let newRecord = nowTimestamp - 299_000
        precondition(label(newRecord) == "刚刚")
        precondition(VoiceTimestampFormatter.timeLabel(createdAt: newRecord, legacyTime: "刚刚", now: now.addingTimeInterval(60), timeZone: shanghai) == "5分钟前")
        precondition(label(nowTimestamp + 60_000) == "刚刚", "Small clock differences should not produce negative ages")
        precondition(label(nowTimestamp + 86_400_000) == "10-26", "Clearly future dates should not be described as recent")

        // Missing timestamps may only fall back to an explicit, valid clock time.
        precondition(label(nil, " 9:05 ") == "09:05")
        precondition(label(nil, "23:59") == "23:59")
        for invalid in ["刚刚", "5分钟前", "昨天", "", "24:00", "12:60", "12:5", "12:34:56", "+1:20"] {
            precondition(label(nil, invalid) == "--:--", "Do not invent a time for \(invalid)")
        }
        precondition(label(0) == "--:--")
        precondition(label(-1) == "--:--")
        print("PASS: 5m/1h/24h/7d boundaries, flooring, historical dates, years, time zones, midnight, DST, refresh, clock skew and missing data")
    }
}
