import SwiftUI

/// Refresh only the label, not the feed or its media, as a record ages.
struct VoiceTimestampText: View {
    @Environment(\.timeZone) private var timeZone

    let voice: CatVoiceResult
    var prefix = ""
    var stackedYear = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(prefix + voice.displayTime(at: context.date, timeZone: timeZone, stackedYear: stackedYear))
        }
    }
}
