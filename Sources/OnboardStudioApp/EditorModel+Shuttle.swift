import Foundation
import TelemetryKit

/// The editor's two oldest navigation habits, from tape-deck logging (#230, `docs/conventions.md`).
extension EditorModel {
    /// J, K and L: backward, stop, forward; tapping again goes faster.
    func shuttle(_ direction: Int) {
        guard preview.shuttle(direction) else {
            // A picture that cannot play backward still steps back, rather than doing nothing.
            step(by: -1)
            statusMessage = "This video cannot play backward here, so J steps back a frame at a time."
            return
        }
        let rate = preview.rate
        if abs(rate) > 1 {
            statusMessage = "Playing \(rate < 0 ? "backward" : "forward") at \(Int(abs(rate)))×."
        }
    }

    /// The marked range, when both ends are set and in order.
    var inOutRange: ClosedRange<Double>? {
        guard let markIn, let markOut, markOut > markIn else { return nil }
        return markIn...markOut
    }

    /// I: the range starts at the playhead. An out point before it no longer makes a range.
    func markInAtPlayhead() {
        markIn = currentTime
        if let markOut, markOut <= currentTime { self.markOut = nil }
        statusMessage = "In at \(TimeParsing.lapTimeString(currentTime))."
    }

    /// O: the range ends at the playhead.
    func markOutAtPlayhead() {
        markOut = currentTime
        if let markIn, markIn >= currentTime { self.markIn = nil }
        statusMessage = "Out at \(TimeParsing.lapTimeString(currentTime))."
    }

    func clearInOut() {
        markIn = nil
        markOut = nil
    }
}
