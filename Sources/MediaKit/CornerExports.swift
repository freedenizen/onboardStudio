import Foundation
import ProjectModel
import TelemetryKit

/// One file of an every-corner export (#326): which corner, and the project seconds it covers.
public struct CornerExport: Sendable, Equatable {
    public let index: Int
    /// What the circuit calls it ("4", "3a"), else its number.
    public let label: String
    public let range: ClosedRange<Double>
    /// Seconds lost (+) or gained (−) against the reference in this corner.
    public let timeLost: Double

    public init(index: Int, label: String, range: ClosedRange<Double>, timeLost: Double) {
        self.index = index
        self.label = label
        self.range = range
        self.timeLost = timeLost
    }

    public var title: String { "Turn \(label)" }

    /// `Sonoma – Turn 4.mp4`.
    public func fileName(base: String, fileExtension: String) -> String {
        "\(base) – \(title).\(fileExtension)"
    }
}

extension ProjectCompiler {
    /// Seconds before the brake point a corner's clip begins, and after the corner it ends.
    public static let cornerClipLeadSeconds = 2.0
    public static let cornerClipHoldSeconds = 2.0

    /// The files an every-corner export writes: the corners of the coaching lap — the lap chosen
    /// in Project ▸ Coaching…, else the lap being compared, else the first lap read — each from
    /// `cornerClipLeadSeconds` before its brake point to `cornerClipHoldSeconds` after its end,
    /// in project time and clipped to it. With `onlyOpportunities`, the corners that lost time,
    /// biggest loss first. Empty for any other kind of range, or without a data input that reads.
    public static func cornerExports(_ range: ExportRange, in loaded: LoadedProject, duration: Double)
        -> [CornerExport]
    {
        guard case .eachCorner(let onlyOpportunities) = range else { return [] }
        let project = loaded.project
        for input in project.dataInputs {
            guard let session = loaded.sessions[input.id] else { continue }
            let track =
                loaded.coaching[input.id]
                ?? CoachingTracks.make(for: project, sessions: loaded.sessions, previous: nil)[input.id]
            guard let track, !track.laps.isEmpty else { continue }
            let chosen =
                project.coaching.flatMap { $0.dataInputID == input.id ? $0.lap : nil }
                ?? project.lapComparison.flatMap { $0.lap.dataInputID == input.id ? $0.lap.lap : nil }
            let lap = track.laps.first { $0.number == chosen } ?? track.laps[0]
            guard let analysis = track.analyses[lap.number] else { continue }
            let corners =
                onlyOpportunities ? analysis.opportunities.map(\.corner) : analysis.corners
            _ = session
            return corners.compactMap { comparison in
                let metrics = comparison.lap
                let from = lap.start + analysis.lap.elapsed(atDistance: metrics.phaseStart) - cornerClipLeadSeconds
                let exit = analysis.lap.elapsed(atDistance: metrics.corner.endDistance)
                let to = lap.start + exit + cornerClipHoldSeconds
                let start = min(max(input.sync.projectTime(forInputTime: from), 0), duration)
                let stop = min(max(input.sync.projectTime(forInputTime: to), start), duration)
                guard stop > start else { return nil }
                return CornerExport(
                    index: comparison.index, label: comparison.label, range: start...stop,
                    timeLost: comparison.timeLost)
            }
        }
        return []
    }
}
