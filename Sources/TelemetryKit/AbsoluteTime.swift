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

/// The same times as a person reads them (#457). A RaceChrono log counts seconds since 1970, and
/// the inspector showed that count: "1767150797 – 1767150799.20 s".
extension TelemetrySession {
    /// When the log ran, by the clock — "Mar 14, 2026, 10:12:30 AM – 10:34:05 AM" — for a
    /// session whose times are clock times; `nil` for one that counts from its own start, whose
    /// seconds already mean something.
    public func clockRangeText(locale: Locale = .current, timeZone: TimeZone = .current) -> String? {
        guard timesAreEpoch, let range = timeRange else { return nil }
        let style = Date.IntervalFormatStyle(date: .abbreviated, time: .standard, locale: locale, timeZone: timeZone)
        return style.format(
            Date(timeIntervalSince1970: range.lowerBound)..<Date(timeIntervalSince1970: range.upperBound))
    }

    /// What to say under a position in such a file — a start position of 1,773,483,132.2 — so the
    /// number means something: the time of day it is, and how far from the file's first sample.
    /// A position nowhere near the file's day (0, before anything is synchronized) is not a time
    /// worth naming; the note gives the file's first sample instead, which is the number to start
    /// from. `nil` when the file's seconds count from its own start.
    public func clockPositionNote(
        _ position: Double, locale: Locale = .current, timeZone: TimeZone = .current
    ) -> String? {
        guard timesAreEpoch, let range = timeRange else { return nil }
        let lead = "This file keeps clock time, in seconds since 1970. "
        let seconds = FloatingPointFormatStyle<Double>.number.grouping(.never).locale(locale)
        guard position > range.lowerBound - 86_400, position < range.upperBound + 86_400 else {
            let first = range.lowerBound.formatted(seconds.precision(.fractionLength(0...2)))
            return lead + "Its first sample is at \(first) s."
        }
        var style = Date.FormatStyle(date: .omitted, time: .standard, locale: locale)
        style.timeZone = timeZone
        let time = Date(timeIntervalSince1970: position).formatted(style)
        let offset = position - range.lowerBound
        if abs(offset) < 0.05 { return lead + "The start position is \(time), the file's first sample." }
        let amount = abs(offset).formatted(seconds.precision(.fractionLength(0...1)))
        let side = offset > 0 ? "after" : "before"
        return lead + "The start position is \(time), \(amount) s \(side) the file's first sample."
    }
}
