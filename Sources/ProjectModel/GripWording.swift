import Foundation
import TelemetryKit

/// Grip use in words (#558), as the Logbook, Coaching and Trends say it.
public enum GripWording {
    /// "Used 82% of the grip braking and turning · 14% of the lap near the limit · 3.2 s coasting".
    public static func measurements(_ use: GripUse) -> String {
        [
            "Used \(percent(use.meanUsed)) of the grip braking and turning",
            "\(percent(use.nearLimit)) of the lap near the limit",
            use.coastingSeconds >= 0.5 ? String(format: "%.1f s coasting", use.coastingSeconds) : nil,
        ].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Braking stopped before turning into Turns 2 and 5." — the corners whose combined G fell
    /// below `Options.gapBelow` of the limit between braking and turning; `nil` when none did.
    public static func gaps(_ use: GripUse, options: GripUse.Options = .init()) -> String? {
        let labels = use.corners.filter { ($0.gap?.lowestUsed ?? 1) < options.gapBelow }.map(\.label)
        guard !labels.isEmpty else { return nil }
        let turns = labels.count == 1 ? "Turn \(labels[0])" : "Turns \(labels.formattedList)"
        return "Braking stopped before turning into \(turns)."
    }

    /// "Against 1.00–1.20 G from 3 sessions, dry".
    public static func against(_ limit: CarGripLimit) -> String { "Against \(limit.summary)" }

    public static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }
}

extension LogbookEntry {
    /// The best lap's grip use against `limit`, when the session's G was read.
    public func gripUse(against limit: CarGripLimit) -> GripUse? {
        grip?.bestLap.flatMap { GripUse.measure($0, envelope: limit.limit) }
    }
}
