import ProjectModel
import SwiftUI
import TelemetryKit

/// A lap range offers every lap with its time and starts on the best one (#467).
extension ExportSheet {
    /// The fastest complete lap, as the Logbook counts it.
    var bestLapNumber: Int? { lapSession.flatMap { SessionStats(session: $0).bestLap?.number } }

    /// Every lap of the data file with its time, the best one marked (#467).
    @ViewBuilder var lapChoices: some View {
        let best = bestLapNumber
        ForEach(lapSession?.laps ?? [], id: \.number) { lap in
            Text(Self.lapTitle(lap, isBest: lap.number == best)).tag(lap.number)
        }
    }

    /// "Lap 7 · 1:42.31 (best)", "Lap 0 · 0:58.20 (partial)".
    static func lapTitle(_ lap: Lap, isBest: Bool) -> String {
        let time = lap.duration.map { TimeParsing.lapTimeString($0) } ?? "—"
        let note = isBest ? " (best)" : lap.isComplete ? "" : " (partial)"
        return "Lap \(lap.number) · \(time)\(note)"
    }

    /// A lap range starts on the best lap, not lap 1, unless the project saved one, and is held to
    /// the laps there are (#467).
    func startLapRange() {
        var savedLaps = false
        if case .laps = settings.range { savedLaps = true }
        if !savedLaps, let best = bestLapNumber {
            firstLap = best
            lastLap = best
        }
        firstLap = min(max(firstLap, lapNumbers.lowerBound), lapNumbers.upperBound)
        lastLap = min(max(lastLap, firstLap), lapNumbers.upperBound)
    }
}
