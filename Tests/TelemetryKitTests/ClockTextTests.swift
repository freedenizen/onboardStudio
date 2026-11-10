import Foundation
import Testing

@testable import TelemetryKit

@Suite("A log's clock times in words (#457)")
struct ClockTextTests {
    static let locale = Locale(identifier: "en_US")
    static let utc = TimeZone(identifier: "UTC") ?? .gmt
    /// An invented log: 2026-03-14 10:12:30 UTC.
    static let start = 1_773_483_150.0

    func session(from base: Double, length: Double = 1295) -> TelemetrySession {
        TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [
                Channel(role: .speed, name: "s", unit: .metersPerSecond, times: [base, base + length], values: [1, 2])
            ])
    }

    /// Spaces as the formatter sets them (narrow and non-breaking ones among them) made plain.
    func plain(_ text: String?) -> String? {
        text.map { String($0.map { $0.isWhitespace ? " " : $0 }) }
    }

    @Test func aLogOnTheWallClockSaysWhenItRan() {
        let text = plain(session(from: Self.start).clockRangeText(locale: Self.locale, timeZone: Self.utc))
        #expect(text == "Mar 14, 2026, 10:12:30 AM – 10:34:05 AM", "\(text ?? "nil")")
    }

    @Test func aLogThatCountsFromItsOwnStartKeepsItsSeconds() {
        let relative = session(from: 0)
        #expect(relative.clockRangeText(locale: Self.locale, timeZone: Self.utc) == nil)
        #expect(relative.clockPositionNote(12, locale: Self.locale, timeZone: Self.utc) == nil)
        #expect(TelemetrySession(info: SessionInfo(sourceFormat: "x"), channels: []).clockRangeText() == nil)
    }

    @Test func aPositionInSuchAFileIsATimeOfDayAndADistanceFromItsFirstSample() {
        let log = session(from: Self.start)
        let lead = "This file keeps clock time, in seconds since 1970. "
        func note(_ position: Double) -> String? {
            plain(log.clockPositionNote(position, locale: Self.locale, timeZone: Self.utc))
        }
        #expect(note(Self.start) == lead + "The start position is 10:12:30 AM, the file's first sample.")
        #expect(
            note(Self.start - 17.8)
                == lead + "The start position is 10:12:12 AM, 17.8 s before the file's first sample.")
        #expect(
            note(Self.start + 1290) == lead + "The start position is 10:34:00 AM, 1290 s after the file's first sample."
        )
    }

    /// Before anything is synchronized the position is 0, which is no time on the file's day: the
    /// note gives the number to start from, ungrouped, rather than "midnight, 1,773,483,150 s before".
    @Test func aPositionNowhereNearTheFileNamesItsFirstSampleInstead() {
        let log = session(from: Self.start + 0.6)
        let lead = "This file keeps clock time, in seconds since 1970. "
        func note(_ position: Double) -> String? {
            plain(log.clockPositionNote(position, locale: Self.locale, timeZone: Self.utc))
        }
        #expect(note(0) == lead + "Its first sample is at 1773483150.6 s.")
        #expect(note(Self.start + 3 * 86_400) == lead + "Its first sample is at 1773483150.6 s.")
    }
}
