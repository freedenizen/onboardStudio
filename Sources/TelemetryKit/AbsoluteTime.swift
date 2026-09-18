import Foundation

/// Where a session sits on the wall clock, for lining data up with a video by timestamps.
extension TelemetrySession {
    /// Whether the time axis itself is seconds since 1970 (RaceChrono exports are).
    public var timesAreEpoch: Bool {
        (timeRange?.lowerBound ?? 0) > 1_000_000_000
    }

    /// Seconds since 1970 for session time `t`, when the session is anchored to the clock either
    /// by epoch timestamps or by a recorded start date (`info.createdAt` ↔ time 0).
    public func epoch(forSessionTime t: Double) -> Double? {
        if timesAreEpoch { return t }
        if let created = info.createdAt { return created.timeIntervalSince1970 + t }
        return nil
    }

    /// Session time for a wall-clock instant, the inverse of `epoch(forSessionTime:)`.
    public func sessionTime(forEpoch epoch: Double) -> Double? {
        if timesAreEpoch { return epoch }
        if let created = info.createdAt { return epoch - created.timeIntervalSince1970 }
        return nil
    }

    /// Whether timestamp-based sync is possible for this session.
    public var hasAbsoluteTime: Bool { timesAreEpoch || info.createdAt != nil }
}
