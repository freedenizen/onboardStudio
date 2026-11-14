import TelemetryKit

/// What a logbook entry reads from its session's samples beyond the laps: its standing starts and
/// stops (#553) and how far it drove.
extension LogbookEntry {
    /// Whether its standing starts and stops are measured: as the driver asked, else when it has
    /// no laps and no runs.
    public var measuresPerformanceInForce: Bool { measuresPerformance ?? laps.isEmpty }

    /// Its standing starts and stops from `session` when they are measured, else none: what the
    /// session's reading measured, or measured now.
    public mutating func readPerformance(of session: TelemetrySession) {
        performance =
            measuresPerformanceInForce ? session.performance ?? PerformanceRuns.measure(in: session) : nil
    }

    /// How far the session drove, from its distance channel; `nil` without one.
    public static func distance(of session: TelemetrySession) -> Double? {
        guard let channel = session[.distance], let low = channel.minValue, let high = channel.maxValue, high > low
        else { return nil }
        return high - low
    }
}
