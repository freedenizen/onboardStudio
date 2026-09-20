import Foundation
import ProjectModel
import TelemetryKit

// MARK: - Laps on the timeline (#51)

extension EditorModel {
    /// The data input laps are read from: the selected one when it is a data file, otherwise the
    /// first. Most projects have exactly one, and this keeps that case free of ceremony.
    var lapInput: Input? {
        if selectedObjectID == nil, let input = selectedInput, input.kind.isData { return input }
        return project.dataInputs.first
    }

    /// Every lap of `input` placed on the project ruler.
    ///
    /// Laps are timed in the data file's own clock, so they move when the input is re-synced —
    /// the same reasoning as a marker belonging to an input.
    func laps(of input: Input) -> [PlacedLap] {
        guard let session = sessions[input.id] else { return [] }
        return session.laps.map { lap in
            PlacedLap(
                lap: lap, start: input.sync.projectTime(forInputTime: lap.start),
                end: lap.end.map { input.sync.projectTime(forInputTime: $0) })
        }
    }

    var canJumpByLap: Bool { lapInput.map { !laps(of: $0).isEmpty } ?? false }

    @discardableResult
    func goToNextLap() -> Bool { goToLap { $0.lap(startingAfter: $1) } }

    @discardableResult
    func goToPreviousLap() -> Bool { goToLap { $0.lap(startingBefore: $1) } }

    private func goToLap(_ pick: ([Lap], Double) -> Lap?) -> Bool {
        guard let input = lapInput, let session = sessions[input.id], !session.laps.isEmpty else {
            statusMessage = "No laps in this project's data."
            return false
        }
        // Ask in the data's own time, then come back through the sync, so a re-synced input
        // jumps to the right place without the laps being recomputed.
        let dataTime = input.sync.inputTime(forProjectTime: currentTime)
        guard let lap = pick(session.laps, dataTime) else {
            statusMessage = "No lap that way."
            return false
        }
        seek(to: max(0, input.sync.projectTime(forInputTime: lap.start)))
        statusMessage =
            lap.duration.map { "Lap \(lap.number) — \(TimeParsing.lapTimeString($0))" }
            ?? "Lap \(lap.number) (incomplete)"
        return true
    }
}

/// A lap with the place it falls on the project ruler worked out.
struct PlacedLap: Identifiable {
    var id: Int { lap.number }
    let lap: Lap
    let start: Double
    /// `nil` for a lap whose end was never observed; it runs to the end of what was recorded.
    let end: Double?
}

extension EditorModel {
    /// Where a data input sits on the project ruler, from its session's own time range.
    func dataSpan(of input: Input) -> (start: Double, end: Double) {
        guard let range = sessions[input.id]?.timeRange else {
            return (input.sync.offsetInProject, input.sync.offsetInProject)
        }
        return (
            input.sync.projectTime(forInputTime: range.lowerBound),
            input.sync.projectTime(forInputTime: range.upperBound)
        )
    }
}
